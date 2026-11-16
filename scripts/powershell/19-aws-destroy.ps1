# Tears down everything the AWS side built. This DELETES things.
# Usage: .\scripts\powershell\19-aws-destroy.ps1 [minimal|full|nonprod]
param([Parameter(Position = 0)][string]$Environment = 'minimal')
. (Join-Path $PSScriptRoot 'lib.ps1')
$vars = Get-TfVarsFile $Environment
$tf = Get-TfBin
if (-not (Get-Command aws -ErrorAction SilentlyContinue)) { Stop-Fail "'aws' is not installed." }
& aws sts get-caller-identity *> $null
if ($LASTEXITCODE -ne 0) { Stop-Fail 'AWS login not working.' }
Push-Location $script:TfDir
try {
    Invoke-Native $tf @('init', '-input=false') | Out-Null
    Write-Host 'Resources that will be destroyed:'
    Invoke-Native $tf @('plan', '-destroy', '-input=false', "-var-file=$vars", '-out=destroy.tfplan')
    Confirm-Action "This DELETES the '$Environment' stack, including tables and logs. An Object Lock archive bucket with unexpired retention cannot be deleted until retention ends." 'DESTROY'
    Invoke-Native $tf @('apply', '-input=false', 'destroy.tfplan')
    Remove-Item -Path 'destroy.tfplan' -Force -ErrorAction SilentlyContinue
} finally { Pop-Location }
Write-Ok 'Destroyed. Now check the AWS Billing console for anything that remains.'
