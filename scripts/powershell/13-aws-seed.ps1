# Loads the FICTIONAL seed data (app/seed/*.json) into the DynamoDB tables.
. (Join-Path $PSScriptRoot 'lib.ps1')
if (-not (Get-Command aws -ErrorAction SilentlyContinue)) { Stop-Fail "'aws' is not installed." }
$tf = Get-TfBin
Push-Location $script:TfDir
try { $namesJson = (& $tf output -json table_names) -join "`n" } finally { Pop-Location }
if ($LASTEXITCODE -ne 0 -or -not $namesJson) { Stop-Fail 'No outputs. Apply the AWS side first.' }
$names = $namesJson | ConvertFrom-Json

function ConvertTo-DynamoItem {
    param($Obj)
    $item = [ordered]@{}
    foreach ($p in $Obj.PSObject.Properties) {
        $v = $p.Value
        if ($v -is [bool])      { $item[$p.Name] = @{ BOOL = $v } }
        elseif ($v -is [string]) { $item[$p.Name] = @{ S = $v } }
        elseif ($v -is [ValueType]) { $item[$p.Name] = @{ N = ([string]$v) } }
        else                    { $item[$p.Name] = @{ S = [string]$v } }
    }
    return $item
}

function Import-Seed {
    param([string]$Logical, [string]$File)
    $table = $names.$Logical
    if (-not $table) { Stop-Fail "Table '$Logical' not found in outputs." }
    $items = Get-Content -Raw -Path (Join-Path $script:RepoRoot "app\seed\$File") | ConvertFrom-Json
    $n = 0
    # Windows PowerShell 5.1 mangles quotes in arguments to programs, so the item goes in a file.
    $tmp = [System.IO.Path]::GetTempFileName()
    try {
        foreach ($i in @($items)) {
            [System.IO.File]::WriteAllText($tmp, ((ConvertTo-DynamoItem $i) | ConvertTo-Json -Compress -Depth 5), (New-Object System.Text.UTF8Encoding($false)))
            & aws dynamodb put-item --table-name $table --item ("file://" + $tmp.Replace('\', '/')) | Out-Null
            if ($LASTEXITCODE -ne 0) { Stop-Fail "put-item failed for $Logical." }
            $n++
        }
    } finally { Remove-Item -Path $tmp -Force -ErrorAction SilentlyContinue }
    Write-Ok "Loaded $n items into $Logical"
}

Confirm-Action 'This writes fictional test data into the lab tables. Never run it against real data.' 'YES'
Import-Seed 'policies' 'policies.json'
Import-Seed 'claims' 'claims.json'
Import-Seed 'cat_events' 'cat_events.json'
