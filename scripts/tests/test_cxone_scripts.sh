#!/usr/bin/env bash
# Runs the CXone scripts against the local mock (no tenant, no AWS account).
# Usage: bash scripts/tests/test_cxone_scripts.sh [bash|pwsh]
# The SAME checks run against the Bash and the PowerShell scripts.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
FLAVOR="${1:-bash}"
PWSH="${PWSH:-$(command -v pwsh || echo /home/claude/pwsh/pwsh)}"
case "$FLAVOR" in bash|pwsh) ;; *) echo "Usage: $0 [bash|pwsh]"; exit 2 ;; esac
sc() {  # sc SCRIPT-NAME [args...]  -> runs that script in the chosen flavour
  local n="$1"; shift
  if [ "$FLAVOR" = "pwsh" ]; then "$PWSH" -NoProfile -File "$ROOT/scripts/powershell/$n.ps1" "$@"
  else "$ROOT/scripts/bash/$n.sh" "$@"; fi
}
WORK="$(mktemp -d)"
PASS=0; FAIL=0
SERVER_PID=""

stop_server() { [ -n "$SERVER_PID" ] && kill "$SERVER_PID" 2>/dev/null; wait "$SERVER_PID" 2>/dev/null; SERVER_PID=""; }
trap 'stop_server; rm -rf "$WORK"' EXIT

start_server() {  # start_server [ENV=VALUE ...]
  stop_server
  rm -f "$WORK/port" "$WORK/tokens"
  env "$@" python3 "$HERE/mock_server.py" --port-file "$WORK/port" --token-file "$WORK/tokens" >/dev/null 2>&1 &
  SERVER_PID=$!
  for _ in $(seq 1 50); do [ -s "$WORK/port" ] && break; sleep 0.1; done
  PORT="$(cat "$WORK/port")"
  export CXONE_DISCOVERY_URL="http://127.0.0.1:$PORT/.well-known/cxone-configuration"
  export KESTREL_API_URL="http://127.0.0.1:$PORT/api/v1"
}

ok()   { PASS=$((PASS + 1)); printf 'PASS  %s\n' "$1"; }
bad()  { FAIL=$((FAIL + 1)); printf 'FAIL  %s\n' "$1"; }
check() { # check "label" "command that should succeed"
  if eval "$2" >/dev/null 2>&1; then ok "$1"; else bad "$1"; fi
}
state() { curl -s "http://127.0.0.1:$PORT/__state"; }

export CXONE_TENANT_ID="lab-tenant" CXONE_ACCESS_KEY_ID="mock-key-id" CXONE_ACCESS_KEY_SECRET="mock-key-secret-do-not-leak"
export KESTREL_API_KEY="mock-api-key-do-not-leak" CXONE_RETRY_SLEEP=0 KESTREL_ASSUME_YES=1
ALL="$WORK/all-output.txt"; : > "$ALL"
run() { # run script args... ; appends to ALL and sets OUT / RC
  OUT="$("$@" 2>&1)"; RC=$?; printf '%s\n' "$OUT" >> "$ALL"
}

# expected counts from the config
N_SKILLS=$(jq '.skills|length' "$ROOT/cxone/config/skills.json")
N_TEAMS=$(jq '.teams|length' "$ROOT/cxone/config/teams.json")
N_HOURS=$(jq '.profiles|length' "$ROOT/cxone/config/hours.json")
N_DISP=$(jq '.dispositions|length' "$ROOT/cxone/config/dispositions.json")
N_UNAV=$(jq '.unavailableCodes|length' "$ROOT/cxone/config/unavailable_codes.json")
N_POC=$(jq '.pointsOfContact|length' "$ROOT/cxone/config/points_of_contact.json")
N_TS=$(jq '[.teams[].skills[]]|length' "$ROOT/cxone/config/teams.json")
N_HOL=$(jq '[.holidays[].closes[]]|length' "$ROOT/cxone/config/hours.json")
N_ALL=$((N_SKILLS+N_TEAMS+N_HOURS+N_DISP+N_UNAV+N_POC))

echo "== CXone scripts ($FLAVOR)"
start_server

run sc 00-preflight;               check "preflight succeeds" "[ $RC -eq 0 ]"
check "preflight says token received"   "grep -q 'Token received' <<<\"\$OUT\""

CXONE_ACCESS_KEY_SECRET="wrong-secret-value-xyz" run sc 00-preflight
check "wrong secret fails"              "[ $RC -ne 0 ]"
check "wrong secret message is clear"   "grep -q 'Could not get a token' <<<\"\$OUT\""
check "wrong secret is not echoed"      "! grep -q 'wrong-secret-value-xyz' <<<\"\$OUT\""

CXONE_TENANT_ID="no-such-tenant" run sc 00-preflight
check "unknown tenant fails"            "[ $RC -ne 0 ]"

run sc 01-verify-endpoints;        check "verify-endpoints passes" "[ $RC -eq 0 ]"

run sc 03-cxone-plan
check "plan succeeds"                   "[ $RC -eq 0 ]"
check "plan counts $N_ALL to create"    "grep -q \"Plan: $N_ALL to create, 0 already exist\" <<<\"\$OUT\""
check "plan changed nothing"            "[ \$(state | jq '[.state[]|length]|add') -eq 0 ]"

# an object with the same name but NO lab marker, made by someone else
curl -s -X POST "http://127.0.0.1:$PORT/incontactapi/services/v27.0/dispositions" \
  -H "Authorization: Bearer $(head -1 "$WORK/tokens")" -H 'Content-Type: application/json' \
  -d '{"dispositionName":"Complaint","description":"Somebody elses real disposition"}' >/dev/null
check "setup: real object exists"       "[ \$(state | jq '.state.dispositions|length') -eq 1 ]"

run sc 04-cxone-apply
check "apply succeeds"                  "[ $RC -eq 0 ]"
check "apply created all but the existing one" "grep -q \"Created $((N_ALL-1)), already existed 1, failed 0\" <<<\"\$OUT\""
check "skills created"                  "[ \$(state | jq '.state.skills|length') -eq $N_SKILLS ]"
check "teams created"                   "[ \$(state | jq '.state.teams|length') -eq $N_TEAMS ]"
check "team skills assigned"            "[ \$(state | jq '.teamSkills|length') -eq $N_TS ]"
check "hours created"                   "[ \$(state | jq '.state[\"hours-of-operation\"]|length') -eq $N_HOURS ]"
check "holidays added"                  "[ \$(state | jq '.holidays|length') -eq $N_HOL ]"
check "points of contact created"       "[ \$(state | jq '.state[\"points-of-contact\"]|length') -eq $N_POC ]"
check "every created object carries the lab marker" \
  "[ \$(state | jq '[.state.skills[],.state.teams[],.state[\"points-of-contact\"][]|select(.description|contains(\"[kestrel-lab]\"))]|length') -eq $((N_SKILLS+N_TEAMS+N_POC)) ]"
check "hours body has Melbourne zone"   "state | jq -e '.state[\"hours-of-operation\"][0].timeZone==\"Australia/Melbourne\"'"

run sc 04-cxone-apply
check "second apply creates nothing"    "grep -q 'Created 0, already existed $N_ALL, failed 0' <<<\"\$OUT\""
run sc 03-cxone-plan
check "plan after apply is empty"       "grep -q 'Plan: 0 to create' <<<\"\$OUT\""

run sc 02-cxone-inventory
check "inventory counts lab objects only (not the real disposition)" "grep -q \"lab objects *$((N_ALL-1))\" <<<\"\$OUT\""

run sc 06-cat-mode status;         check "cat mode starts off"  "grep -q 'Emergency flag now: false' <<<\"\$OUT\""
run sc 06-cat-mode on;             check "cat mode on works"    "[ $RC -eq 0 ] && grep -q 'CAT mode is now on' <<<\"\$OUT\""
check "flag is set in the tenant"       "state | jq -e '[.state[\"hours-of-operation\"][]|select(.profileName==\"KI CAT Switch\")|.isEmergency]==[true]'"
run sc 06-cat-mode on;             check "cat mode on twice is a no-op" "grep -q 'Already on' <<<\"\$OUT\""
run sc 06-cat-mode off;            check "cat mode off works"   "grep -q 'CAT mode is now off' <<<\"\$OUT\""
run sc 06-cat-mode sideways;       check "bad cat mode argument fails" "[ $RC -ne 0 ]"

run sc 09-cxone-destroy
check "destroy succeeds"                "[ $RC -eq 0 ] && grep -q 'Destroyed' <<<\"\$OUT\""
check "destroy left the real disposition alone" "[ \$(state | jq '[.state[]|length]|add') -eq 1 ] && state | jq -e '.state.dispositions[0].description==\"Somebody elses real disposition\"'"
check "destroy printed the list first"  "grep -q 'will be deleted' <<<\"\$OUT\""
run sc 09-cxone-destroy;           check "second destroy has nothing to do" "grep -q 'Nothing to delete' <<<\"\$OUT\""

echo "== Retry on temporary failure"
start_server MOCK_FAIL_ONCE=/skills
run sc 03-cxone-plan;              check "a single 503 is retried and the plan still works" "[ $RC -eq 0 ] && grep -q 'to create' <<<\"\$OUT\""

echo "== Confirmation prompts (without the test switch)"
start_server
(
  unset KESTREL_ASSUME_YES
  OUT="$(printf 'no\n' | sc 04-cxone-apply 2>&1)"; SUBRC=$?
  [ $SUBRC -ne 0 ] && grep -q 'did not match' <<<"$OUT" && exit 0 || exit 1
) ; check "apply stops when the tenant name is not retyped" "[ $? -eq 0 ]"
(
  unset KESTREL_ASSUME_YES
  OUT="$(printf 'lab-tenant\nnope\n' | sc 04-cxone-apply 2>&1)"; SUBRC=$?
  [ $SUBRC -ne 0 ] && grep -q 'Nothing was changed' <<<"$OUT" && exit 0 || exit 1
) ; check "apply stops when YES is not typed" "[ $? -eq 0 ] && [ \$(state | jq '[.state[]|length]|add') -eq 0 ]"

echo "== AWS API smoke tests (real handler code, fake tables)"
start_server
run sc 14-aws-test-api;            check "smoke tests pass" "[ $RC -eq 0 ] && grep -q 'All smoke tests passed' <<<\"\$OUT\""
check "smoke tests ran 12 checks"       "grep -q 'Passed 12, failed 0' <<<\"\$OUT\""
run sc 05-health-check;            check "health check passes" "[ $RC -eq 0 ] && grep -q 'Integration layer healthy' <<<\"\$OUT\""
KESTREL_API_KEY="wrong-api-key-value" run sc 05-health-check
check "wrong API key is refused"        "[ $RC -ne 0 ]"
check "wrong API key is not echoed"     "! grep -q 'wrong-api-key-value' <<<\"\$OUT\""

echo "== Nothing secret in any output"
check "no access key secret printed"    "! grep -q 'mock-key-secret-do-not-leak' '$ALL'"
check "no API key printed"              "! grep -q 'mock-api-key-do-not-leak' '$ALL'"
check "no bearer token printed"         "! grep -qf '$WORK/tokens' '$ALL' || [ ! -s '$WORK/tokens' ]"

echo
echo "Passed $PASS, failed $FAIL."
[ "$FAIL" -eq 0 ]
