# Offline checks for the AWS side. Changes nothing. Needs no AWS login.
. (Join-Path $PSScriptRoot 'lib.ps1')
$tf = Get-TfBin
$py = 'python'; if (-not (Get-Command python -ErrorAction SilentlyContinue)) { $py = 'python3' }

Write-Host '== Repo checks'
Push-Location $script:RepoRoot; try { Invoke-Native $py @('tools/check_repo.py') } finally { Pop-Location }

Write-Host '== Unit tests'
Push-Location (Join-Path $script:RepoRoot 'app'); try { Invoke-Native $py @('-m', 'pytest', '-q', '-p', 'no:cacheprovider') } finally { Pop-Location }
Write-Ok 'Unit tests pass'

Write-Host '== Formatting'
Push-Location $script:TfDir
try {
    & $tf fmt -check -recursive
    if ($LASTEXITCODE -ne 0) { Stop-Fail "Formatting. Run: cd terraform; $tf fmt -recursive" }
    Write-Ok 'Formatting is clean'
    Write-Host '== Init and validate'
    Invoke-Native $tf @('init', '-backend=false', '-input=false')
    Invoke-Native $tf @('validate')
    Write-Ok 'Configuration is valid'
} finally { Pop-Location }
