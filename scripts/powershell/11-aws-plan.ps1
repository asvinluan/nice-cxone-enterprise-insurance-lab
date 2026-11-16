# Shows what the AWS side would build. Changes nothing.
# Usage: .\scripts\powershell\11-aws-plan.ps1 [minimal|full|nonprod]
param([Parameter(Position = 0)][string]$Environment = 'minimal')
. (Join-Path $PSScriptRoot 'lib.ps1')
$vars = Get-TfVarsFile $Environment
$tf = Get-TfBin
if (-not (Get-Command aws -ErrorAction SilentlyContinue)) { Stop-Fail "'aws' is not installed." }
& aws sts get-caller-identity *> $null
if ($LASTEXITCODE -ne 0) { Stop-Fail "AWS login not working. Run 'aws sso login' or set AWS_PROFILE." }
Push-Location $script:TfDir
try {
    Invoke-Native $tf @('init', '-input=false') | Out-Null
    Invoke-Native $tf @('plan', '-input=false', "-var-file=$vars", "-out=$Environment.tfplan")
} finally { Pop-Location }
Write-Ok "Plan saved as terraform\$Environment.tfplan (it is in .gitignore)."
Write-Info 'Read it. On a first run nothing should be changed or destroyed.'
