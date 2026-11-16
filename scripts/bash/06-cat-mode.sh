#!/usr/bin/env bash
# The catastrophe switch. Turns the Emergency flag on the CAT hours profile on or off.
# While ON, every phone number is sent to the cat_surge script.
# Usage: ./scripts/bash/06-cat-mode.sh status|on|off
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
mode="${1:-status}"
case "$mode" in status|on|off) ;; *) say_fail "Usage: 06-cat-mode.sh status|on|off" ;; esac
cx_login

profile="$(jq -r .catSwitchProfile "$CONFIG_DIR/hours.json")"
pid="$(id_of hoursOfOperation "$profile")"
[ -n "$pid" ] || say_fail "Hours profile '$profile' does not exist. Run 04-cxone-apply.sh first."

current="$(cx_call GET "$CX_ADMIN$(res_path hoursOfOperation list)/$pid" | jq -r '.isEmergency // false')"
echo "Profile: $profile    Emergency flag now: $current"
[ "$mode" = "status" ] && exit 0

want=false; [ "$mode" = "on" ] && want=true
if [ "$current" = "$want" ]; then say_ok "Already $mode. Nothing to do."; exit 0; fi
confirm "This switches CAT mode $mode for EVERY phone number in this tenant." "$(echo "$mode" | tr "[:lower:]" "[:upper:]")"
path="$(res_path hoursOfOperation update | sed "s#{id}#$pid#")"
cx_call PUT "$CX_ADMIN$path" "$(jq -nc --argjson e "$want" '{isEmergency:$e}')" >/dev/null || say_fail "The change was refused."
now="$(cx_call GET "$CX_ADMIN$(res_path hoursOfOperation list)/$pid" | jq -r '.isEmergency // false')"
[ "$now" = "$want" ] || say_fail "The flag did not change. Check in CXone."
say_ok "CAT mode is now $mode at $(date -u +%Y-%m-%dT%H:%M:%SZ)"
say_info "Write this time in the incident log. Test one call on one number."
