# Smoke tests: calls the API with the sample payloads and checks the answers.
# Reads the URL and key from OpenTofu outputs or KESTREL_API_URL / KESTREL_API_KEY.
# Never prints the key.
. (Join-Path $PSScriptRoot 'lib.ps1')
$url = $env:KESTREL_API_URL; $key = $env:KESTREL_API_KEY
if (-not $url -or -not $key) {
    Push-Location $script:TfDir
    try {
        if (-not $url) { $url = (& (Get-TfBin) output -raw api_url) }
        if (-not $key) { $key = (& (Get-TfBin) output -raw api_key_value) }
    } finally { Pop-Location }
}
$headers = @{ 'x-api-key' = $key; 'Content-Type' = 'application/json' }
$key = $null
$P = Join-Path $script:RepoRoot 'cxone\payloads'
$script:Pass = 0; $script:FailN = 0

function Send-Post {
    param([string]$Path, [string]$Json)
    try {
        $r = Invoke-WebRequest -Method Post -Uri ($url.TrimEnd('/') + $Path) -Headers $headers -Body $Json -UseBasicParsing
        return [pscustomobject]@{ Code = [int]$r.StatusCode; Body = ([string]$r.Content | ConvertFrom-Json) }
    } catch {
        $txt = Get-HttpErrorText $_
        $b = $null; try { $b = $txt | ConvertFrom-Json } catch { }
        return [pscustomobject]@{ Code = (Get-HttpStatus $_); Body = $b }
    }
}
function Test-Reply {
    param([string]$Label, [int]$Want, [scriptblock]$Test, $Reply)
    $good = $false
    if ($Reply.Code -eq $Want -and $null -ne $Reply.Body) { try { $good = [bool](& $Test $Reply.Body) } catch { $good = $false } }
    if ($good) { $script:Pass++; Write-Ok $Label } else { $script:FailN++; [Console]::Error.WriteLine("FAIL $Label (HTTP $($Reply.Code))") }
}
function Read-Payload { param([string]$Name) (Get-Content -Raw -Path (Join-Path $P $Name)).Trim() }

$id = 'smoke-' + [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
Test-Reply 'policy verify: right number and postcode'    200 { param($b) $b.result -eq 'verified' }     (Send-Post '/policy/verify' (Read-Payload 'policy_verify.request.json'))
Test-Reply 'policy verify: wrong postcode'               200 { param($b) $b.result -eq 'not_verified' } (Send-Post '/policy/verify' '{"policyNumber":"40000001","postcode":"9999"}')
Test-Reply 'policy verify: unknown number (same answer)' 200 { param($b) $b.result -eq 'not_verified' } (Send-Post '/policy/verify' '{"policyNumber":"49999999","postcode":"3000"}')
Test-Reply 'policy verify: bad input is refused'         400 { param($b) $b.error -eq 'invalid_input' -and $b.field -eq 'policyNumber' } (Send-Post '/policy/verify' '{"policyNumber":"abc","postcode":"3000"}')
Test-Reply 'claim status: found'                         200 { param($b) $b.result -eq 'found' }        (Send-Post '/claims/status' (Read-Payload 'claim_status.request.json'))
Test-Reply 'cat check: inside an event area'             200 { param($b) $b.inEventArea -eq $true }     (Send-Post '/cat/check' (Read-Payload 'cat_check.request.json'))
Test-Reply 'cat check: outside'                          200 { param($b) $b.inEventArea -eq $false }    (Send-Post '/cat/check' '{"postcode":"2000"}')

$case = Read-Payload 'crm_case.request.json' | ConvertFrom-Json
$case.idempotencyKey = $id
$caseJson = $case | ConvertTo-Json -Compress
Test-Reply 'case: created'                               201 { param($b) $b.result -eq 'created' }      (Send-Post '/crm/cases' $caseJson)
Test-Reply 'case: same key again is a duplicate'         200 { param($b) $b.result -eq 'duplicate' }    (Send-Post '/crm/cases' $caseJson)
$case.idempotencyKey = "$id-x"; $case.summary = 'card 4111 1111 1111 1111'
Test-Reply 'case: card number in summary is refused'     422 { param($b) $b.error -eq 'pii_in_summary' } (Send-Post '/crm/cases' ($case | ConvertTo-Json -Compress))
Test-Reply 'guard: normal question allowed or masked'    200 { param($b) $b.action -eq 'allow' -or $b.action -eq 'mask' } (Send-Post '/guard' (Read-Payload 'guard.input.request.json'))
Test-Reply 'guard: attack phrase is blocked'             200 { param($b) $b.action -eq 'block' }        (Send-Post '/guard' (Read-Payload 'guard.attack.request.json'))

Write-Host ''
Write-Host "Passed $($script:Pass), failed $($script:FailN)."
if ($script:FailN -ne 0) { Stop-Fail 'Some checks failed.' }
Write-Ok 'All smoke tests passed.'
