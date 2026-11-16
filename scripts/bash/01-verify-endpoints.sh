#!/usr/bin/env bash
# Read-only check that every list path in cxone/endpoints.json answers on YOUR tenant.
# Run this BEFORE the plan. If a path is wrong, fix cxone/endpoints.json, not the scripts.
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
cx_login

bad=0
for r in $(jq -r '.admin.resources | to_entries[] | select(.value.list != null) | .key' "$ENDPOINTS"); do
  url="$CX_ADMIN$(res_path "$r" list)"
  if cx_call GET "$url" >/dev/null 2>"$CX_TMP/err.txt"; then
    say_ok "$r  $(res_path "$r" list)"
  else
    say_warn "$r  $(res_path "$r" list)  -> $(cat "$CX_TMP/err.txt")"
    bad=$((bad + 1))
  fi
done
echo
if [ "$bad" -gt 0 ]; then
  say_fail "$bad path(s) did not answer. Fix cxone/endpoints.json (every entry marked verify=true is a guess until this passes)."
fi
say_ok "All list paths answered. Create, update and delete paths are still unverified until the first apply."
