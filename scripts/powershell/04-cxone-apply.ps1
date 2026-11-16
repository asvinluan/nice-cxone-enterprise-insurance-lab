# Creates the CXone objects in cxone/config. This CHANGES your tenant.
. (Join-Path $PSScriptRoot 'lib.ps1')
Connect-Cx
Write-Host ''
Write-Host "Tenant: $($env:CXONE_TENANT_ID)"
if ($env:KESTREL_ASSUME_YES -ne '1') {
    $again = Read-Host 'Type the tenant name again to confirm this is the LAB tenant'
    if ($again -ne $env:CXONE_TENANT_ID) { Stop-Fail 'Tenant name did not match. Nothing was changed.' }
}
Confirm-Action 'This will CREATE skills, teams, hours, dispositions, codes and points of contact.' 'YES'
$script:DryRun = $false
Invoke-ApplyAll
Write-Host ''
Write-Ok ("Created {0}, already existed {1}, failed {2}." -f $script:Created, $script:Exists, $script:Failed)
if ($script:Failed -ne 0) { Stop-Fail 'Some objects failed. Read the WARN lines above, fix, and run again. It only adds what is missing.' }
Write-Info 'Next: import the Studio scripts (docs/BUILD-MANUAL.md, Part 7), then run 05-health-check.ps1.'
