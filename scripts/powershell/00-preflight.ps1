# Preflight: checks tools and logins. Changes nothing.
# Usage: .\scripts\powershell\00-preflight.ps1 [-Aws]
param([switch]$Aws)
. (Join-Path $PSScriptRoot 'lib.ps1')

Write-Host '== Tools'
foreach ($c in @('git', 'python')) {
    if (-not (Get-Command $c -ErrorAction SilentlyContinue)) {
        if ($c -eq 'python' -and (Get-Command python3 -ErrorAction SilentlyContinue)) { Write-Ok 'python3 found'; continue }
        if ($c -eq 'python' -and (Get-Command py -ErrorAction SilentlyContinue)) { Write-Ok 'py found'; continue }
        Stop-Fail "'$c' is not installed. See docs/RUNBOOK-POWERSHELL.md, Step 1."
    }
    Write-Ok "$c found"
}
if ($Aws) {
    if (-not (Get-Command aws -ErrorAction SilentlyContinue)) { Stop-Fail "'aws' is not installed." }
    Write-Ok 'aws found'
    Write-Ok ("{0} found" -f (Get-TfBin))
}

Write-Host '== CXone login'
Connect-Cx
$count = @(Get-CxNames 'skills').Count
Write-Ok "Admin API reachable (your tenant has $count skills)"
Write-Info 'Check that this is your LAB tenant. If it is not, close this window.'

if ($Aws) {
    Write-Host '== AWS login'
    & aws sts get-caller-identity --query Arn --output text *> $null
    if ($LASTEXITCODE -ne 0) { Stop-Fail "AWS login not working. Run 'aws sso login' or set AWS_PROFILE." }
    Write-Ok 'AWS credentials work'
    $region = $env:AWS_REGION; if (-not $region) { $region = $env:AWS_DEFAULT_REGION }; if (-not $region) { $region = 'not set' }
    Write-Info "Region: $region. Check this is your LAB account."
}
