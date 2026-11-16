# Counts the lab objects that exist in CXone. Read-only.
. (Join-Path $PSScriptRoot 'lib.ps1')
Connect-Cx
$total = 0
foreach ($r in @('skills', 'teams', 'hoursOfOperation', 'dispositions', 'unavailableCodes', 'pointsOfContact')) {
    $n = @(Get-LabObjects $r).Count
    $total += $n
    Write-Host ('{0,-20} {1}' -f $r, $n)
}
Write-Host '--------------------------'
Write-Host ('{0,-20} {1}' -f 'lab objects', $total)
Write-Host ''
Write-Host 'Points of contact:'
foreach ($o in @(Get-LabObjects 'pointsOfContact')) { Write-Host ("  " + $o.name) }
