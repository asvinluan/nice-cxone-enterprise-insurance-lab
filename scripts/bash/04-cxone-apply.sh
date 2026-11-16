#!/usr/bin/env bash
# Creates the CXone objects in cxone/config. This CHANGES your tenant.
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
cx_login
echo
echo "Tenant: $CXONE_TENANT_ID"
if [ "${KESTREL_ASSUME_YES:-}" != "1" ]; then
  printf 'Type the tenant name again to confirm this is the LAB tenant: '
  read -r again
  [ "$again" = "$CXONE_TENANT_ID" ] || say_fail "Tenant name did not match. Nothing was changed."
fi
confirm "This will CREATE skills, teams, hours, dispositions, codes and points of contact." "YES"
export DRY_RUN=0
apply_all
echo
say_ok "Created $CREATED, already existed $EXISTS, failed $FAILED."
[ "$FAILED" -eq 0 ] || say_fail "Some objects failed. Read the WARN lines above, fix, and run again. It only adds what is missing."
say_info "Next: import the Studio scripts (docs/BUILD-MANUAL.md, Part 7), then run 05-health-check.sh."
