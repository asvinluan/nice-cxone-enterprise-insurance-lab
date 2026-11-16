# Shows what apply WOULD create. Changes nothing.
. (Join-Path $PSScriptRoot 'lib.ps1')
Connect-Cx
$script:DryRun = $true
Invoke-ApplyAll
Write-Host ''
Write-Ok ("Plan: {0} to create, {1} already exist." -f $script:Created, $script:Exists)
Write-Info 'Apply only ever creates. It does not change or delete what already exists.'
