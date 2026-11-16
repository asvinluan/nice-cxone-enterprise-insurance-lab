# Read-only check that every list path in cxone/endpoints.json answers on YOUR tenant.
# Run this BEFORE the plan. If a path is wrong, fix cxone/endpoints.json, not the scripts.
. (Join-Path $PSScriptRoot 'lib.ps1')
Connect-Cx

$bad = 0
foreach ($r in $script:Endpoints.admin.resources.PSObject.Properties) {
    if (-not ($r.Value.PSObject.Properties.Name -contains 'list')) { continue }
    $path = Get-ResPath $r.Name 'list'
    if (Test-Cx -Method GET -Url ($script:CxAdmin + $path)) { Write-Ok ("{0}  {1}" -f $r.Name, $path) }
    else { Write-Warn2 ("{0}  {1}  -> did not answer" -f $r.Name, $path); $bad++ }
}
Write-Host ''
if ($bad -gt 0) { Stop-Fail "$bad path(s) did not answer. Fix cxone/endpoints.json (every entry marked verify=true is a guess until this passes)." }
Write-Ok 'All list paths answered. Create, update and delete paths are still unverified until the first apply.'
