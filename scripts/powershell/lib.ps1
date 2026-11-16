# Shared helpers. Dot-source this file; do not run it.
# Works in Windows PowerShell 5.1 and PowerShell 7.
# Rules every script follows:
#   * stop at the first failure
#   * never print a secret, a token, or an API key
#   * secrets come from environment variables only, never from files in the repo
#   * anything that changes a system asks you to type a word first

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:LibDir     = Split-Path -Parent $MyInvocation.MyCommand.Path
$script:RepoRoot   = (Resolve-Path (Join-Path $script:LibDir '..\..')).Path
$script:ConfigDir  = Join-Path $script:RepoRoot 'cxone\config'
$script:EndpointsFile = Join-Path $script:RepoRoot 'cxone\endpoints.json'
$script:TfDir      = Join-Path $script:RepoRoot 'terraform'
$script:Endpoints  = Get-Content -Raw -Path $script:EndpointsFile | ConvertFrom-Json

function Write-Info { param([string]$Text) Write-Host ("    " + $Text) }
function Write-Ok   { param([string]$Text) Write-Host ("OK  " + $Text) }
function Write-Warn2 { param([string]$Text) [Console]::Error.WriteLine("WARN " + $Text) }
function Stop-Fail  { param([string]$Text) [Console]::Error.WriteLine("FAIL " + $Text); exit 1 }

function Read-Config {
    param([string]$File)
    Get-Content -Raw -Path (Join-Path $script:ConfigDir $File) | ConvertFrom-Json
}

function Assert-Env {
    # Checks the NAME only. Never prints the value.
    param([string[]]$Names)
    foreach ($n in $Names) {
        $v = [Environment]::GetEnvironmentVariable($n)
        if ([string]::IsNullOrEmpty($v)) { Stop-Fail "Set `$env:$n first (docs/RUNBOOK-POWERSHELL.md, Step 3)." }
    }
}

function Confirm-Action {
    param([string]$What, [string]$Word)
    if ($env:KESTREL_ASSUME_YES -eq '1') {
        Write-Warn2 'KESTREL_ASSUME_YES=1: skipping the confirmation prompt (for automated tests only).'
        return
    }
    Write-Host ""
    Write-Host $What
    $reply = Read-Host "Type $Word to continue, anything else to stop"
    if ($reply -ne $Word) { Stop-Fail 'Stopped. Nothing was changed.' }
}

# ---------------------------------------------------------------- OpenTofu or Terraform

function Get-TfBin {
    if (Get-Command tofu -ErrorAction SilentlyContinue) { return 'tofu' }
    if (Get-Command terraform -ErrorAction SilentlyContinue) { return 'terraform' }
    Stop-Fail 'Neither tofu nor terraform is installed. See docs/RUNBOOK-POWERSHELL.md, Step 1.'
}

function Get-TfVarsFile {
    param([string]$Environment)
    if (@('minimal', 'full', 'nonprod') -notcontains $Environment) {
        Stop-Fail "Environment must be minimal, full or nonprod (got '$Environment')."
    }
    return "envs/$Environment.tfvars"
}

function Invoke-Native {
    # Runs a program, stops on a non-zero exit code. Output goes to the screen.
    param([string]$Exe, [string[]]$Arguments)
    & $Exe @Arguments
    if ($LASTEXITCODE -ne 0) { Stop-Fail "$Exe $($Arguments[0]) failed (exit code $LASTEXITCODE)." }
}

# ---------------------------------------------------------------- CXone: login and calls

$script:CxApi    = ''
$script:CxAdmin  = ''
$script:CxHeaders = @{}
$script:LabMark  = $script:Endpoints._labMarker

function Get-HttpStatus {
    param($ErrorRecord)
    $resp = $ErrorRecord.Exception.Response
    if ($null -eq $resp) { return 0 }
    return [int]$resp.StatusCode
}

function Get-HttpErrorText {
    param($ErrorRecord)
    $text = ''
    if ($ErrorRecord.ErrorDetails -and $ErrorRecord.ErrorDetails.Message) { $text = $ErrorRecord.ErrorDetails.Message }
    else {
        try {
            $s = $ErrorRecord.Exception.Response.GetResponseStream()
            $text = (New-Object System.IO.StreamReader($s)).ReadToEnd()
        } catch { $text = '' }
    }
    $text = ($text -replace '\s+', ' ')
    if ($text.Length -gt 200) { $text = $text.Substring(0, 200) }
    return $text
}

function Connect-Cx {
    # Finds your tenant's API address and gets a token. The token is kept in
    # a script variable and sent in a header. It is never written to the screen,
    # a file, or a log.
    Assert-Env @('CXONE_TENANT_ID', 'CXONE_ACCESS_KEY_ID', 'CXONE_ACCESS_KEY_SECRET')
    $discovery = $env:CXONE_DISCOVERY_URL
    if ([string]::IsNullOrEmpty($discovery)) { $discovery = $script:Endpoints.discovery.tenantLookup.url }

    try {
        $d = Invoke-RestMethod -Method Get -Uri ($discovery + '?tenantId=' + [uri]::EscapeDataString($env:CXONE_TENANT_ID)) -UseBasicParsing
    } catch {
        Stop-Fail ("Tenant lookup failed (HTTP " + (Get-HttpStatus $_) + "). Check CXONE_TENANT_ID.")
    }
    if (-not $d.api_endpoint -or -not $d.auth_endpoint) {
        Stop-Fail 'Tenant lookup did not return api_endpoint and auth_endpoint. Update cxone/endpoints.json.'
    }
    $script:CxApi = [string]$d.api_endpoint

    $tokenUrl = $env:CXONE_TOKEN_URL
    if ([string]::IsNullOrEmpty($tokenUrl)) { $tokenUrl = ([string]$d.auth_endpoint).TrimEnd('/') + $script:Endpoints.discovery.token.path }

    $body = [ordered]@{ grant_type = 'password'; username = $env:CXONE_ACCESS_KEY_ID; password = $env:CXONE_ACCESS_KEY_SECRET }
    if ($env:CXONE_CLIENT_ID)     { $body['client_id'] = $env:CXONE_CLIENT_ID }
    if ($env:CXONE_CLIENT_SECRET) { $body['client_secret'] = $env:CXONE_CLIENT_SECRET }
    try {
        $t = Invoke-RestMethod -Method Post -Uri $tokenUrl -ContentType 'application/json' -Body ($body | ConvertTo-Json -Compress) -UseBasicParsing
    } catch {
        Stop-Fail ("Could not get a token (HTTP " + (Get-HttpStatus $_) + "). Check the access key, secret and tenant.")
    } finally {
        $body = $null
    }
    if (-not $t.access_token) { Stop-Fail 'The token reply had no access_token.' }
    $script:CxHeaders = @{ Authorization = ('Bearer ' + $t.access_token) }
    $t = $null

    $base = [string]$script:Endpoints.admin.base
    $base = $base.Replace('{apiEndpoint}', '').Replace('{version}', [string]$script:Endpoints.admin.version)
    $script:CxAdmin = $script:CxApi.TrimEnd('/') + $base
    Write-Ok "Token received for tenant $($env:CXONE_TENANT_ID)"
}

function Invoke-Cx {
    # Invoke-Cx METHOD URL [BODY-OBJECT]  -> returns the parsed reply, or $null for an empty reply.
    # Retries 429 and 5xx up to 3 times. Returns $false-ish by throwing CxError on other failures.
    param([string]$Method, [string]$Url, $Body = $null)
    $pause = 2
    if ($env:CXONE_RETRY_SLEEP) { $pause = [int]$env:CXONE_RETRY_SLEEP }
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        try {
            $p = @{ Method = $Method; Uri = $Url; Headers = $script:CxHeaders; UseBasicParsing = $true }
            if ($null -ne $Body) { $p['Body'] = ($Body | ConvertTo-Json -Depth 10 -Compress); $p['ContentType'] = 'application/json' }
            $r = Invoke-WebRequest @p
            if ([string]::IsNullOrWhiteSpace([string]$r.Content)) { return $null }
            return ([string]$r.Content | ConvertFrom-Json)
        } catch {
            $code = Get-HttpStatus $_
            if (($code -eq 429 -or $code -ge 500) -and $attempt -lt 3) { Start-Sleep -Seconds $pause; continue }
            $short = $Url
            if ($Url.StartsWith($script:CxApi)) { $short = $Url.Substring($script:CxApi.Length) }
            [Console]::Error.WriteLine(("HTTP {0} {1} {2}: {3}" -f $code, $Method, $short, (Get-HttpErrorText $_)))
            throw 'CxError'
        }
    }
}

function Test-Cx {
    # Like Invoke-Cx but returns $true/$false instead of throwing. Result in $script:CxLast.
    param([string]$Method, [string]$Url, $Body = $null)
    try { $script:CxLast = Invoke-Cx -Method $Method -Url $Url -Body $Body; return $true }
    catch { if ($_.Exception.Message -eq 'CxError') { return $false } else { throw } }
}

function Get-ResField { param([string]$Resource, [string]$Field) return $script:Endpoints.admin.resources.$Resource.$Field }
function Get-ResPath {
    param([string]$Resource, [string]$Field)
    $v = [string](Get-ResField $Resource $Field)
    return ($v -replace '^[A-Z]+ ', '')
}

function Get-CxNames {
    # Returns objects with id, name, description for one resource.
    param([string]$Resource)
    $reply = Invoke-Cx -Method GET -Url ($script:CxAdmin + (Get-ResPath $Resource 'list'))
    $key = Get-ResField $Resource 'listKey'; $idf = Get-ResField $Resource 'idField'; $nf = Get-ResField $Resource 'nameField'
    $out = @()
    if ($null -ne $reply -and $reply.PSObject.Properties.Name -contains $key) {
        foreach ($o in @($reply.$key)) {
            $desc = ''
            if ($o.PSObject.Properties.Name -contains 'description') { $desc = [string]$o.description }
            $out += [pscustomobject]@{ id = [string]$o.$idf; name = [string]$o.$nf; description = $desc }
        }
    }
    return $out
}

function Get-CxId {
    param([string]$Resource, [string]$Name)
    $hit = @(Get-CxNames $Resource | Where-Object { $_.name -eq $Name })
    if ($hit.Count -gt 0) { return $hit[0].id }
    return ''
}

# ---------------------------------------------------------------- desired-state bodies

function New-SkillBody { param($S, [string]$Campaign)
    [ordered]@{ skillName = $S.name; mediaType = $S.mediaType; campaignName = $Campaign
        description = ((([string]$S.description) + ' ' + $script:LabMark).Trim())
        acwSeconds = $S.acwSeconds; serviceLevelPercent = $S.slaPercent; serviceLevelSeconds = $S.slaSeconds; isRecorded = $S.record } }
function New-TeamBody { param($T) [ordered]@{ teamName = $T.name; description = ($T.description + ' ' + $script:LabMark) } }
function New-HoursBody { param($H)
    $days = @()
    foreach ($d in $H.days.PSObject.Properties) {
        $iv = @()
        foreach ($pair in @($d.Value)) { $iv += [ordered]@{ start = $pair[0]; end = $pair[1] } }
        $days += [ordered]@{ day = $d.Name; intervals = @($iv) }
    }
    [ordered]@{ profileName = $H.name; description = ($H.description + ' ' + $script:LabMark); timeZone = $H.timezone; isEmergency = $false; days = @($days) } }
function New-DispositionBody { param($D) [ordered]@{ dispositionName = $D.name; description = ($D.description + ' ' + $script:LabMark); classification = $D.classification } }
function New-UnavailableBody { param($U) [ordered]@{ unavailableCodeName = $U.name; description = ($U.description + ' ' + $script:LabMark); isPaid = $U.paid } }
function New-PocBody { param($P)
    [ordered]@{ pointOfContactName = $P.name; description = ($P.description + ' ' + $script:LabMark); number = $P.number
        scriptName = $P.script; hoursProfileName = $P.hoursProfile; parameters = $P.parameters } }

# ---------------------------------------------------------------- apply engine

$script:Created = 0; $script:Exists = 0; $script:Failed = 0; $script:DryRun = $false

function Add-IfMissing {
    param([string]$Resource, [string]$Name, $Body, $Current)
    if (@($Current | Where-Object { $null -ne $_ -and $_.name -eq $Name }).Count -gt 0) {
        $script:Exists++; Write-Info ("exists      {0}: {1}" -f $Resource, $Name); return
    }
    if ($script:DryRun) { $script:Created++; Write-Info ("would create {0}: {1}" -f $Resource, $Name); return }
    if (Test-Cx -Method POST -Url ($script:CxAdmin + (Get-ResPath $Resource 'create')) -Body $Body) {
        $script:Created++; Write-Info ("created     {0}: {1}" -f $Resource, $Name)
    } else {
        $script:Failed++; Write-Warn2 ("could not create {0}: {1}" -f $Resource, $Name)
    }
}

function Invoke-ApplyCollection {
    param([string]$Resource, $Items, [scriptblock]$BodyFn)
    $current = @(Get-CxNames $Resource)
    foreach ($item in @($Items)) {
        Add-IfMissing -Resource $Resource -Name $item.name -Body (& $BodyFn $item) -Current $current
    }
}

function Invoke-ApplyTeamSkills {
    $cfg = Read-Config 'teams.json'
    foreach ($t in $cfg.teams) {
        foreach ($s in @($t.skills)) {
            if ($script:DryRun) { Write-Info ("would assign skill '{0}' (proficiency {1}) to team '{2}'" -f $s.skill, $s.proficiency, $t.name); continue }
            $tid = Get-CxId 'teams' $t.name; $sid = Get-CxId 'skills' $s.skill
            if (-not $tid -or -not $sid) { $script:Failed++; Write-Warn2 ("cannot assign '{0}' to '{1}' (missing id)" -f $s.skill, $t.name); continue }
            $path = (Get-ResPath 'teamSkills' 'assign').Replace('{teamId}', $tid)
            if (Test-Cx -Method POST -Url ($script:CxAdmin + $path) -Body ([ordered]@{ skillId = $sid; proficiency = [int]$s.proficiency })) {
                Write-Info ("assigned    {0} -> {1}" -f $s.skill, $t.name)
            } else { $script:Failed++; Write-Warn2 ("could not assign '{0}' to '{1}'" -f $s.skill, $t.name) }
        }
    }
}

function Invoke-ApplyHolidays {
    $cfg = Read-Config 'hours.json'
    foreach ($h in $cfg.holidays) {
        foreach ($profile in @($h.closes)) {
            if ($script:DryRun) { Write-Info ("would add holiday '{0}' ({1}) to '{2}'" -f $h.name, $h.date, $profile); continue }
            $pid2 = Get-CxId 'hoursOfOperation' $profile
            if (-not $pid2) { $script:Failed++; Write-Warn2 ("no profile '{0}' for holiday '{1}'" -f $profile, $h.name); continue }
            $path = (Get-ResPath 'hoursOfOperation' 'addHoliday').Replace('{id}', $pid2)
            if (Test-Cx -Method POST -Url ($script:CxAdmin + $path) -Body ([ordered]@{ holidayName = $h.name; date = $h.date })) {
                Write-Info ("holiday     {0} -> {1}" -f $h.name, $profile)
            } else { $script:Failed++; Write-Warn2 ("could not add holiday '{0}' to '{1}'" -f $h.name, $profile) }
        }
    }
}

function Invoke-ApplyAll {
    $skills = Read-Config 'skills.json'
    Write-Info '-- skills';             Invoke-ApplyCollection 'skills' $skills.skills { param($i) New-SkillBody $i $skills.campaign }
    Write-Info '-- teams';              Invoke-ApplyCollection 'teams' (Read-Config 'teams.json').teams { param($i) New-TeamBody $i }
    Write-Info '-- team skills';        Invoke-ApplyTeamSkills
    Write-Info '-- hours of operation'; Invoke-ApplyCollection 'hoursOfOperation' (Read-Config 'hours.json').profiles { param($i) New-HoursBody $i }
    Write-Info '-- holidays';           Invoke-ApplyHolidays
    Write-Info '-- dispositions';       Invoke-ApplyCollection 'dispositions' (Read-Config 'dispositions.json').dispositions { param($i) New-DispositionBody $i }
    Write-Info '-- unavailable codes';  Invoke-ApplyCollection 'unavailableCodes' (Read-Config 'unavailable_codes.json').unavailableCodes { param($i) New-UnavailableBody $i }
    Write-Info '-- points of contact';  Invoke-ApplyCollection 'pointsOfContact' (Read-Config 'points_of_contact.json').pointsOfContact { param($i) New-PocBody $i }
}

# Resources in the order destroy removes them (reverse of apply).
$script:DestroyOrder = @('pointsOfContact', 'unavailableCodes', 'dispositions', 'hoursOfOperation', 'teams', 'skills')

function Get-ConfigNames {
    param([string]$Resource)
    switch ($Resource) {
        'skills'           { return @((Read-Config 'skills.json').skills | ForEach-Object { $_.name }) }
        'teams'            { return @((Read-Config 'teams.json').teams | ForEach-Object { $_.name }) }
        'hoursOfOperation' { return @((Read-Config 'hours.json').profiles | ForEach-Object { $_.name }) }
        'dispositions'     { return @((Read-Config 'dispositions.json').dispositions | ForEach-Object { $_.name }) }
        'unavailableCodes' { return @((Read-Config 'unavailable_codes.json').unavailableCodes | ForEach-Object { $_.name }) }
        'pointsOfContact'  { return @((Read-Config 'points_of_contact.json').pointsOfContact | ForEach-Object { $_.name }) }
        default            { return @() }
    }
}

# Objects that are BOTH named in our config AND carry the lab marker.
function Get-LabObjects {
    param([string]$Resource)
    $names = Get-ConfigNames $Resource
    $out = @()
    foreach ($o in @(Get-CxNames $Resource)) {
        if (($names -contains $o.name) -and $o.description.Contains($script:LabMark)) { $out += $o }
    }
    return $out
}
