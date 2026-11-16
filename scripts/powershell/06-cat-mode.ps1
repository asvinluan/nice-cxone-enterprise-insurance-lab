# The catastrophe switch. Turns the Emergency flag on the CAT hours profile on or off.
# While ON, every phone number is sent to the cat_surge script.
# Usage: .\scripts\powershell\06-cat-mode.ps1 status|on|off
param([Parameter(Position = 0)][string]$Mode = 'status')
. (Join-Path $PSScriptRoot 'lib.ps1')
if (@('status', 'on', 'off') -notcontains $Mode) { Stop-Fail 'Usage: 06-cat-mode.ps1 status|on|off' }
Connect-Cx

$profile2 = (Read-Config 'hours.json').catSwitchProfile
$pid2 = Get-CxId 'hoursOfOperation' $profile2
if (-not $pid2) { Stop-Fail "Hours profile '$profile2' does not exist. Run 04-cxone-apply.ps1 first." }

function Get-Flag { $o = Invoke-Cx -Method GET -Url ($script:CxAdmin + (Get-ResPath 'hoursOfOperation' 'list') + '/' + $pid2); return [bool]$o.isEmergency }
$current = Get-Flag
Write-Host ("Profile: {0}    Emergency flag now: {1}" -f $profile2, $current.ToString().ToLower())
if ($Mode -eq 'status') { exit 0 }

$want = ($Mode -eq 'on')
if ($current -eq $want) { Write-Ok "Already $Mode. Nothing to do."; exit 0 }
Confirm-Action "This switches CAT mode $Mode for EVERY phone number in this tenant." $Mode.ToUpper()
$path = (Get-ResPath 'hoursOfOperation' 'update').Replace('{id}', $pid2)
if (-not (Test-Cx -Method PUT -Url ($script:CxAdmin + $path) -Body ([ordered]@{ isEmergency = $want }))) { Stop-Fail 'The change was refused.' }
if ((Get-Flag) -ne $want) { Stop-Fail 'The flag did not change. Check in CXone.' }
Write-Ok ("CAT mode is now {0} at {1}" -f $Mode, (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ'))
Write-Info 'Write this time in the incident log. Test one call on one number.'
