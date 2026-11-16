#!/usr/bin/env bash
# Loads the FICTIONAL seed data (app/seed/*.json) into the DynamoDB tables.
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
need_cmd aws; need_cmd jq
TF="$(tf_bin)"
names="$(cd "$TF_DIR" && "$TF" output -json table_names)" || say_fail "No outputs. Apply the AWS side first."

to_dynamo() {  # plain JSON object -> DynamoDB typed JSON
  jq -c 'with_entries(.value |= (if type=="string" then {S:.} elif type=="number" then {N:tostring} elif type=="boolean" then {BOOL:.} else {S:tostring} end))'
}

load() {  # load LOGICAL_TABLE FILE
  local logical="$1" file="$REPO_ROOT/app/seed/$2" table n=0 item
  table="$(jq -r --arg k "$logical" '.[$k] // empty' <<<"$names")"
  [ -n "$table" ] || say_fail "Table '$logical' not found in outputs."
  while IFS= read -r item; do
    aws dynamodb put-item --table-name "$table" --item "$(to_dynamo <<<"$item")" >/dev/null
    n=$((n + 1))
  done < <(jq -c '.[]' "$file")
  say_ok "Loaded $n items into $logical"
}

confirm "This writes fictional test data into the lab tables. Never run it against real data." "YES"
load policies policies.json
load claims claims.json
load cat_events cat_events.json
