#!/usr/bin/env bash
# Smoke tests: calls the API with the sample payloads and checks the answers.
# Reads the URL and key from OpenTofu outputs or KESTREL_API_URL / KESTREL_API_KEY.
# Never prints the key.
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
need_cmd curl; need_cmd jq
url="${KESTREL_API_URL:-}"; key="${KESTREL_API_KEY:-}"
[ -n "$url" ] || url="$(cd "$TF_DIR" && "$(tf_bin)" output -raw api_url)"
[ -n "$key" ] || key="$(cd "$TF_DIR" && "$(tf_bin)" output -raw api_key_value)"
tmp="$(umask 077; mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
( umask 077; printf 'header = "x-api-key: %s"\nheader = "Content-Type: application/json"\n' "$key" > "$tmp/k.conf" ); unset key
P="$REPO_ROOT/cxone/payloads"
pass=0; failn=0

post() {  # post PATH BODY_JSON -> prints "STATUS<TAB>BODY"
  local code
  code="$(printf '%s' "$2" | curl -sS -o "$tmp/out.json" -w '%{http_code}' -X POST -K "$tmp/k.conf" --data @- "${url%/}$1" || true)"
  printf '%s\t%s\n' "$code" "$(cat "$tmp/out.json" 2>/dev/null)"
}
expect() {  # expect LABEL STATUS JQ_TEST RESULT_LINE
  local label="$1" want="$2" test="$3" line="$4" code body
  code="${line%%$'\t'*}"; body="${line#*$'\t'}"
  if [ "$code" = "$want" ] && jq -e "$test" <<<"$body" >/dev/null 2>&1; then
    pass=$((pass + 1)); say_ok "$label"
  else
    failn=$((failn + 1)); printf 'FAIL %s (HTTP %s)\n' "$label" "$code" >&2
  fi
}

id="smoke-$(date +%s)"
expect "policy verify: right number and postcode"   200 '.result=="verified"'       "$(post /policy/verify "$(cat "$P/policy_verify.request.json")")"
expect "policy verify: wrong postcode"              200 '.result=="not_verified"'   "$(post /policy/verify '{"policyNumber":"40000001","postcode":"9999"}')"
expect "policy verify: unknown number (same answer)" 200 '.result=="not_verified"'  "$(post /policy/verify '{"policyNumber":"49999999","postcode":"3000"}')"
expect "policy verify: bad input is refused"        400 '.error=="invalid_input" and .field=="policyNumber"'     "$(post /policy/verify '{"policyNumber":"abc","postcode":"3000"}')"
expect "claim status: found"                        200 '.result=="found"'          "$(post /claims/status "$(cat "$P/claim_status.request.json")")"
expect "cat check: inside an event area"            200 '.inEventArea==true'        "$(post /cat/check "$(cat "$P/cat_check.request.json")")"
expect "cat check: outside"                         200 '.inEventArea==false'       "$(post /cat/check '{"postcode":"2000"}')"
body="$(jq -c --arg k "$id" '.idempotencyKey=$k' "$P/crm_case.request.json")"
expect "case: created"                              201 '.result=="created"'        "$(post /crm/cases "$body")"
expect "case: same key again is a duplicate"        200 '.result=="duplicate"'      "$(post /crm/cases "$body")"
expect "case: card number in summary is refused"    422 '.error=="pii_in_summary"'            "$(post /crm/cases "$(jq -c --arg k "$id-x" '.idempotencyKey=$k | .summary="card 4111 1111 1111 1111"' "$P/crm_case.request.json")")"
expect "guard: normal question allowed or masked"   200 '.action=="allow" or .action=="mask"' "$(post /guard "$(cat "$P/guard.input.request.json")")"
expect "guard: attack phrase is blocked"            200 '.action=="block"'          "$(post /guard "$(cat "$P/guard.attack.request.json")")"
echo
echo "Passed $pass, failed $failn."
[ "$failn" -eq 0 ] || say_fail "Some checks failed."
say_ok "All smoke tests passed."
