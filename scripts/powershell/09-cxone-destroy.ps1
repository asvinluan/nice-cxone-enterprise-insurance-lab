# Deletes ONLY objects that are (1) named in cxone/config and (2) carry the lab marker.
# Anything else in the tenant is left alone.
. (Join-Path $PSScriptRoot 'lib.ps1')
Connect-Cx

$todo = @()
foreach ($r in $script:DestroyOrder) {
    foreach ($o in @(Get-LabObjects $r)) { $todo += [pscustomobject]@{ resource = $r; id = $o.id; name = $o.name } }
}
if ($todo.Count -eq 0) { Write-Ok 'No lab objects found. Nothing to delete.'; exit 0 }
Write-Host "These $($todo.Count) objects will be deleted:"
foreach ($t in $todo) { Write-Host ('  {0,-18} {1}' -f $t.resource, $t.name) }
Confirm-Action "Deleting lab objects from tenant $($env:CXONE_TENANT_ID). This cannot be undone." 'DESTROY'

$failed = 0
foreach ($t in $todo) {
    $path = (Get-ResPath $t.resource 'delete').Replace('{id}', $t.id)
    if (Test-Cx -Method DELETE -Url ($script:CxAdmin + $path)) { Write-Info ("deleted {0}: {1}" -f $t.resource, $t.name) }
    else { $failed++; Write-Warn2 ("could not delete {0}: {1}" -f $t.resource, $t.name) }
}
if ($failed -ne 0) { Stop-Fail "$failed object(s) could not be deleted (often because something still uses them). Remove the dependency and run again." }
Write-Ok 'Destroyed.'
Write-Info 'Studio scripts, phone numbers and carrier routing are not removed by this script. See docs/BUILD-MANUAL.md, Part 12.'
