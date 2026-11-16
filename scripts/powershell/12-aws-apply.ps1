# Builds the AWS side FROM THE SAVED PLAN. This CHANGES your AWS account.
# Usage: .\scripts\powershell\12-aws-apply.ps1 [minimal|full|nonprod]
param([Parameter(Position = 0)][string]$Environment = 'minimal')
. (Join-Path $PSScriptRoot 'lib.ps1')
[void](Get-TfVarsFile $Environment)
$tf = Get-TfBin
$planFile = Join-Path $script:TfDir "$Environment.tfplan"
if (-not (Test-Path $planFile)) { Stop-Fail "No saved plan for '$Environment'. Run 11-aws-plan.ps1 $Environment first." }
Confirm-Action "This will BUILD AWS resources from the saved '$Environment' plan. Check the account and region first." 'YES'
Push-Location $script:TfDir
try { Invoke-Native $tf @('apply', '-input=false', "$Environment.tfplan") } finally { Pop-Location }
Remove-Item -Path $planFile -Force
Write-Ok 'Applied. Next: .\scripts\powershell\13-aws-seed.ps1 then 14-aws-test-api.ps1'
