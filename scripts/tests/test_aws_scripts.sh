#!/usr/bin/env bash
# Tests the AWS-side scripts with stand-ins for tofu and aws.
# Usage: bash scripts/tests/test_aws_scripts.sh [bash|pwsh]
# This checks the scripts' logic (order of calls, flags, confirmations). It does not touch AWS.
# shellcheck disable=SC2034  # OUT is read inside eval strings
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
FLAVOR="${1:-bash}"
PWSH="${PWSH:-$(command -v pwsh || echo /home/claude/pwsh/pwsh)}"
case "$FLAVOR" in bash|pwsh) ;; *) echo "Usage: $0 [bash|pwsh]"; exit 2 ;; esac
sc() {
  local n="$1"; shift
  if [ "$FLAVOR" = "pwsh" ]; then "$PWSH" -NoProfile -File "$ROOT/scripts/powershell/$n.ps1" "$@"
  else "$ROOT/scripts/bash/$n.sh" "$@"; fi
}
export SHIM_LOG; SHIM_LOG="$(mktemp)"
export PATH="$HERE/shims:$PATH"
PASS=0; FAIL=0
ok() { PASS=$((PASS + 1)); printf 'PASS  %s\n' "$1"; }
check() { if eval "$2" >/dev/null 2>&1; then ok "$1"; else FAIL=$((FAIL + 1)); printf 'FAIL  %s\n' "$1"; fi; }
cleanup() { rm -f "$SHIM_LOG" "$ROOT"/terraform/*.tfplan; }
trap cleanup EXIT
: > "$SHIM_LOG"

echo "== AWS scripts with stand-in tools ($FLAVOR)"
OUT="$(sc 11-aws-plan minimal 2>&1)"; RC=$?
check "plan succeeds"                         "[ $RC -eq 0 ]"
check "plan uses the minimal tfvars"          "grep -q 'plan -input=false -var-file=envs/minimal.tfvars -out=minimal.tfplan' '$SHIM_LOG'"
check "plan initialises first"                "[ \$(grep -n '^tofu init' '$SHIM_LOG' | head -1 | cut -d: -f1) -lt \$(grep -n '^tofu plan' '$SHIM_LOG' | head -1 | cut -d: -f1) ]"
check "plan file was created"                 "[ -f '$ROOT/terraform/minimal.tfplan' ]"

OUT="$(sc 11-aws-plan bogus 2>&1)"; RC=$?
check "unknown environment is refused"        "[ $RC -ne 0 ] && grep -q 'must be minimal, full or nonprod' <<<\"\$OUT\""

rm -f "$ROOT/terraform/full.tfplan"
OUT="$(KESTREL_ASSUME_YES=1 sc 12-aws-apply full 2>&1)"; RC=$?
check "apply without a saved plan is refused" "[ $RC -ne 0 ] && grep -q 'No saved plan' <<<\"\$OUT\""

: > "$SHIM_LOG"
sc 12-aws-apply minimal >/dev/null 2>&1 <<<"no"; RC=$?
check "apply stops unless YES is typed"       "[ $RC -ne 0 ] && ! grep -q '^tofu apply' '$SHIM_LOG'"
sc 12-aws-apply minimal >/dev/null 2>&1 <<<"YES"; RC=$?
check "apply runs the saved plan"             "[ $RC -eq 0 ] && grep -q '^tofu apply -input=false minimal.tfplan' '$SHIM_LOG'"
check "plan file removed after apply"         "[ ! -f '$ROOT/terraform/minimal.tfplan' ]"

: > "$SHIM_LOG"
KESTREL_ASSUME_YES=1 sc 13-aws-seed >/dev/null 2>&1; RC=$?
check "seed succeeds"                         "[ $RC -eq 0 ]"
N=$(( $(jq length "$ROOT/app/seed/policies.json") + $(jq length "$ROOT/app/seed/claims.json") + $(jq length "$ROOT/app/seed/cat_events.json") ))
check "seed wrote $N items"                   "[ \$(grep -c 'aws dynamodb put-item' '$SHIM_LOG') -eq $N ]"
check "seed uses the table names from outputs" "grep -q 'put-item --table-name ki-policies' '$SHIM_LOG' && grep -q 'put-item --table-name ki-cat-events' '$SHIM_LOG'"
check "seed items are DynamoDB-typed"         "grep -q '\"policy_number\":{\"S\":\"40000001\"}' '$SHIM_LOG' && grep -q '\"premium_cents\":{\"N\":\"128450\"}' '$SHIM_LOG' && grep -q '\"care_flag\":{\"BOOL\":true}' '$SHIM_LOG'"

: > "$SHIM_LOG"
sc 19-aws-destroy minimal >/dev/null 2>&1 <<<"no"; RC=$?
check "destroy stops unless DESTROY is typed" "[ $RC -ne 0 ] && ! grep -q '^tofu apply' '$SHIM_LOG'"
sc 19-aws-destroy minimal >/dev/null 2>&1 <<<"DESTROY"; RC=$?
check "destroy plans before it destroys"      "[ $RC -eq 0 ] && grep -q '^tofu plan -destroy' '$SHIM_LOG' && grep -q '^tofu apply -input=false destroy.tfplan' '$SHIM_LOG'"

echo
echo "Passed $PASS, failed $FAIL."
[ "$FAIL" -eq 0 ]
