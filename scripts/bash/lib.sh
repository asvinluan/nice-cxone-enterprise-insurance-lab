#!/usr/bin/env bash
# Shared helpers. Source this file; do not run it.
# Rules every script follows:
#   * stop at the first failure (set -euo pipefail)
#   * never print a secret, a token, or an API key
#   * secrets come from environment variables only, never from files in the repo
#   * anything that changes a system asks you to type a word first

# shellcheck disable=SC2034  # variables here are used by the scripts that source this file
set -euo pipefail

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$LIB_DIR/../.." && pwd)"
CONFIG_DIR="$REPO_ROOT/cxone/config"
ENDPOINTS="$REPO_ROOT/cxone/endpoints.json"
TF_DIR="$REPO_ROOT/terraform"

say_info() { printf '    %s\n' "$*"; }
say_ok()   { printf 'OK  %s\n' "$*"; }
say_warn() { printf 'WARN %s\n' "$*" >&2; }
say_fail() { printf 'FAIL %s\n' "$*" >&2; exit 1; }

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || say_fail "'$1' is not installed. See docs/RUNBOOK-BASH.md, Step 1."
}

need_env() {
  # Checks the NAME only. Never prints the value.
  local name
  for name in "$@"; do
    [ -n "${!name:-}" ] || say_fail "Set $name first (docs/RUNBOOK-BASH.md, Step 3)."
  done
}

confirm() {
  # confirm "what will happen" "WORD"   -> asks the user to type WORD
  local what="$1" word="$2" reply
  if [ "${KESTREL_ASSUME_YES:-}" = "1" ]; then
    say_warn "KESTREL_ASSUME_YES=1: skipping the confirmation prompt (for automated tests only)."
    return 0
  fi
  printf '\n%s\nType %s to continue, anything else to stop: ' "$what" "$word"
  read -r reply
  [ "$reply" = "$word" ] || say_fail "Stopped. Nothing was changed."
}

# ---------------------------------------------------------------- OpenTofu or Terraform

tf_bin() {
  if command -v tofu >/dev/null 2>&1; then echo tofu
  elif command -v terraform >/dev/null 2>&1; then echo terraform
  else say_fail "Neither tofu nor terraform is installed. See docs/RUNBOOK-BASH.md, Step 1."
  fi
}

tf_env_file() {
  local env="${1:-minimal}"
  case "$env" in minimal|full|nonprod) ;; *) say_fail "Environment must be minimal, full or nonprod (got '$env')." ;; esac
  echo "envs/$env.tfvars"
}

# ---------------------------------------------------------------- CXone: login and calls

CX_TMP=""
CX_API=""
CX_ADMIN=""

cx_cleanup() { [ -n "$CX_TMP" ] && rm -rf "$CX_TMP"; }

ep() { jq -r "$1" "$ENDPOINTS"; }

cx_login() {
  # Finds your tenant's API address, gets a token, and keeps the token in a
  # private temp file that curl reads. The token never appears on a command
  # line, in the terminal, or in a log.
  need_cmd curl; need_cmd jq
  need_env CXONE_TENANT_ID CXONE_ACCESS_KEY_ID CXONE_ACCESS_KEY_SECRET
  CX_TMP="$(umask 077; mktemp -d)"
  trap cx_cleanup EXIT

  local discovery="${CXONE_DISCOVERY_URL:-$(ep '.discovery.tenantLookup.url')}"
  local body="$CX_TMP/discovery.json" code
  code="$(curl -sS -o "$body" -w '%{http_code}' -G --data-urlencode "tenantId=$CXONE_TENANT_ID" "$discovery" || true)"
  [ "$code" = "200" ] || say_fail "Tenant lookup failed (HTTP $code). Check CXONE_TENANT_ID."
  CX_API="$(jq -r '.api_endpoint // empty' "$body")"
  local auth
  auth="$(jq -r '.auth_endpoint // empty' "$body")"
  [ -n "$CX_API" ] && [ -n "$auth" ] || say_fail "Tenant lookup did not return api_endpoint and auth_endpoint. Update cxone/endpoints.json."

  local token_url="${CXONE_TOKEN_URL:-${auth%/}$(ep '.discovery.token.path')}"
  # The credentials go to jq through the environment, then to curl on stdin.
  # Neither appears in the process list.
  code="$(jq -n '{grant_type:"password", username:env.CXONE_ACCESS_KEY_ID, password:env.CXONE_ACCESS_KEY_SECRET,
                  client_id:env.CXONE_CLIENT_ID, client_secret:env.CXONE_CLIENT_SECRET} | with_entries(select(.value != null))' \
        | curl -sS -o "$CX_TMP/token.json" -w '%{http_code}' -X POST -H 'Content-Type: application/json' --data @- "$token_url" || true)"
  [ "$code" = "200" ] || say_fail "Could not get a token (HTTP $code). Check the access key, secret and tenant."
  local token
  token="$(jq -r '.access_token // empty' "$CX_TMP/token.json")"
  [ -n "$token" ] || say_fail "The token reply had no access_token."
  ( umask 077; printf 'header = "Authorization: Bearer %s"\n' "$token" > "$CX_TMP/auth.conf" )
  rm -f "$CX_TMP/token.json"
  unset token
  CX_ADMIN="${CX_API%/}$(ep '.admin.base' | sed 's#{apiEndpoint}##; s#{version}#'"$(ep '.admin.version')"'#')"
  say_ok "Token received for tenant $CXONE_TENANT_ID"
}

cx_call() {
  # cx_call METHOD ABSOLUTE_URL [JSON_BODY]   -> prints the reply body
  # Retries 429 and 5xx up to 3 times. Prints status and a short reply on failure.
  local method="$1" url="$2" data="${3:-}" attempt=0 code out="$CX_TMP/reply.json"
  local pause="${CXONE_RETRY_SLEEP:-2}"
  while :; do
    attempt=$((attempt + 1))
    if [ -n "$data" ]; then
      code="$(printf '%s' "$data" | curl -sS -o "$out" -w '%{http_code}' -X "$method" -K "$CX_TMP/auth.conf" \
              -H 'Content-Type: application/json' --data @- "$url" || true)"
    else
      code="$(curl -sS -o "$out" -w '%{http_code}' -X "$method" -K "$CX_TMP/auth.conf" "$url" || true)"
    fi
    case "$code" in
      2??) cat "$out"; return 0 ;;
      429|5??) if [ "$attempt" -lt 3 ]; then sleep "$pause"; continue; fi ;;
    esac
    printf 'HTTP %s %s %s: %s\n' "$code" "$method" "${url#"$CX_API"}" "$(head -c 200 "$out" 2>/dev/null | tr '\n' ' ')" >&2
    return 1
  done
}

res()    { ep ".admin.resources.$1.$2"; }                       # res skills listKey
res_path() { res "$1" "$2" | sed 's#^[A-Z]* ##'; }              # "GET /skills" -> "/skills"
cx_list() { cx_call GET "$CX_ADMIN$(res_path "$1" list)"; }

cx_names() {
  # cx_names RESOURCE -> a JSON array of {id,name,description} for that resource
  local r="$1" key idf namef
  key="$(res "$r" listKey)"; idf="$(res "$r" idField)"; namef="$(res "$r" nameField)"
  cx_list "$r" | jq -c --arg k "$key" --arg i "$idf" --arg n "$namef" \
    '[ (.[$k] // [])[] | {id: (.[$i]|tostring), name: .[$n], description: (.description // "")} ]'
}

LAB_MARK=""
lab_mark() { [ -n "$LAB_MARK" ] || LAB_MARK="$(ep '._labMarker')"; echo "$LAB_MARK"; }

# ---------------------------------------------------------------- desired-state bodies (jq)

body_skill() {
  jq -c --arg m "$(lab_mark)" --arg c "$(jq -r .campaign "$CONFIG_DIR/skills.json")" \
    '{skillName:.name, mediaType:.mediaType, campaignName:$c, description:((.description // "") + " " + $m),
      acwSeconds:.acwSeconds, serviceLevelPercent:.slaPercent, serviceLevelSeconds:.slaSeconds, isRecorded:.record}'
}
body_team() {
  jq -c --arg m "$(lab_mark)" '{teamName:.name, description:(.description + " " + $m)}'
}
body_hours() {
  jq -c --arg m "$(lab_mark)" \
    '{profileName:.name, description:(.description + " " + $m), timeZone:.timezone, isEmergency:false,
      days:[ .days | to_entries[] | {day:.key, intervals:[ .value[] | {start:.[0], end:.[1]} ]} ]}'
}
body_disposition() {
  jq -c --arg m "$(lab_mark)" '{dispositionName:.name, description:(.description + " " + $m), classification:.classification}'
}
body_unavailable() {
  jq -c --arg m "$(lab_mark)" '{unavailableCodeName:.name, description:(.description + " " + $m), isPaid:.paid}'
}
body_poc() {
  jq -c --arg m "$(lab_mark)" \
    '{pointOfContactName:.name, description:(.description + " " + $m), number:.number, scriptName:.script,
      hoursProfileName:.hoursProfile, parameters:.parameters}'
}

# ---------------------------------------------------------------- apply engine

CREATED=0; EXISTS=0; FAILED=0; DRY_RUN="${DRY_RUN:-0}"

ensure() {
  # ensure RESOURCE NAME BODY   -> creates if missing. Never updates. Never deletes.
  local r="$1" name="$2" body="$3" found
  found="$(jq -r --arg n "$name" '[.[] | select(.name == $n)] | length' <<<"$CURRENT_LIST")"
  if [ "$found" != "0" ]; then
    EXISTS=$((EXISTS + 1)); say_info "exists      $r: $name"; return 0
  fi
  if [ "$DRY_RUN" = "1" ]; then
    CREATED=$((CREATED + 1)); say_info "would create $r: $name"; return 0
  fi
  if cx_call POST "$CX_ADMIN$(res_path "$r" create)" "$body" >/dev/null; then
    CREATED=$((CREATED + 1)); say_info "created     $r: $name"
  else
    FAILED=$((FAILED + 1)); say_warn "could not create $r: $name"
  fi
}

apply_collection() {
  # apply_collection RESOURCE FILE JQ_PATH BODY_FN
  local r="$1" file="$2" path="$3" fn="$4" item name
  CURRENT_LIST="$(cx_names "$r")"
  while IFS= read -r item; do
    name="$(jq -r .name <<<"$item")"
    ensure "$r" "$name" "$("$fn" <<<"$item")"
  done < <(jq -c "$path" "$CONFIG_DIR/$file")
}

id_of() {
  # id_of RESOURCE NAME -> id, or empty
  cx_names "$1" | jq -r --arg n "$2" '[.[] | select(.name == $n)][0].id // empty'
}

apply_team_skills() {
  local team skill prof tid sid
  while IFS=$'\t' read -r team skill prof; do
    if [ "$DRY_RUN" = "1" ]; then say_info "would assign skill '$skill' (proficiency $prof) to team '$team'"; continue; fi
    tid="$(id_of teams "$team")"; sid="$(id_of skills "$skill")"
    if [ -z "$tid" ] || [ -z "$sid" ]; then FAILED=$((FAILED + 1)); say_warn "cannot assign '$skill' to '$team' (missing id)"; continue; fi
    local path; path="$(res_path teamSkills assign | sed "s#{teamId}#$tid#")"
    if cx_call POST "$CX_ADMIN$path" "$(jq -nc --arg s "$sid" --argjson p "$prof" '{skillId:$s, proficiency:$p}')" >/dev/null; then
      say_info "assigned    $skill -> $team"
    else
      FAILED=$((FAILED + 1)); say_warn "could not assign '$skill' to '$team'"
    fi
  done < <(jq -r '.teams[] | .name as $t | .skills[] | [$t, .skill, .proficiency] | @tsv' "$CONFIG_DIR/teams.json")
}

apply_holidays() {
  local profile hname date pid
  while IFS=$'\t' read -r hname date profile; do
    if [ "$DRY_RUN" = "1" ]; then say_info "would add holiday '$hname' ($date) to '$profile'"; continue; fi
    pid="$(id_of hoursOfOperation "$profile")"
    [ -n "$pid" ] || { FAILED=$((FAILED + 1)); say_warn "no profile '$profile' for holiday '$hname'"; continue; }
    local path; path="$(res_path hoursOfOperation addHoliday | sed "s#{id}#$pid#")"
    if cx_call POST "$CX_ADMIN$path" "$(jq -nc --arg n "$hname" --arg d "$date" '{holidayName:$n, date:$d}')" >/dev/null; then
      say_info "holiday     $hname -> $profile"
    else
      FAILED=$((FAILED + 1)); say_warn "could not add holiday '$hname' to '$profile'"
    fi
  done < <(jq -r '.holidays[] | .name as $n | .date as $d | .closes[] | [$n, $d, .] | @tsv' "$CONFIG_DIR/hours.json")
}

apply_all() {
  say_info "-- skills";             apply_collection skills skills.json '.skills[]' body_skill
  say_info "-- teams";              apply_collection teams teams.json '.teams[]' body_team
  say_info "-- team skills";        apply_team_skills
  say_info "-- hours of operation"; apply_collection hoursOfOperation hours.json '.profiles[]' body_hours
  say_info "-- holidays";           apply_holidays
  say_info "-- dispositions";       apply_collection dispositions dispositions.json '.dispositions[]' body_disposition
  say_info "-- unavailable codes";  apply_collection unavailableCodes unavailable_codes.json '.unavailableCodes[]' body_unavailable
  say_info "-- points of contact";  apply_collection pointsOfContact points_of_contact.json '.pointsOfContact[]' body_poc
}

# Resources in the order destroy removes them (reverse of apply).
DESTROY_ORDER=(pointsOfContact unavailableCodes dispositions hoursOfOperation teams skills)

in_config() {
  # in_config RESOURCE NAME -> exit 0 if the name is in our desired-state files
  case "$1" in
    skills)           jq -e --arg n "$2" '[.skills[].name] | index($n)' "$CONFIG_DIR/skills.json" >/dev/null ;;
    teams)            jq -e --arg n "$2" '[.teams[].name] | index($n)' "$CONFIG_DIR/teams.json" >/dev/null ;;
    hoursOfOperation) jq -e --arg n "$2" '[.profiles[].name] | index($n)' "$CONFIG_DIR/hours.json" >/dev/null ;;
    dispositions)     jq -e --arg n "$2" '[.dispositions[].name] | index($n)' "$CONFIG_DIR/dispositions.json" >/dev/null ;;
    unavailableCodes) jq -e --arg n "$2" '[.unavailableCodes[].name] | index($n)' "$CONFIG_DIR/unavailable_codes.json" >/dev/null ;;
    pointsOfContact)  jq -e --arg n "$2" '[.pointsOfContact[].name] | index($n)' "$CONFIG_DIR/points_of_contact.json" >/dev/null ;;
    *) return 1 ;;
  esac
}

# Lists objects that are BOTH in our config AND carry the lab marker.
lab_objects() {
  local r="$1" item name desc
  while IFS= read -r item; do
    name="$(jq -r .name <<<"$item")"; desc="$(jq -r .description <<<"$item")"
    if in_config "$r" "$name" && [[ "$desc" == *"$(lab_mark)"* ]]; then jq -c . <<<"$item"; fi
  done < <(cx_names "$r" | jq -c '.[]')
}
