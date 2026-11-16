#!/usr/bin/env bash
# Deletes ONLY objects that are (1) named in cxone/config and (2) carry the lab marker.
# Anything else in the tenant is left alone.
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
cx_login

todo="$CX_TMP/todo.tsv"; : > "$todo"
for r in "${DESTROY_ORDER[@]}"; do
  while IFS= read -r item; do
    [ -n "$item" ] || continue
    printf '%s\t%s\t%s\n' "$r" "$(jq -r .id <<<"$item")" "$(jq -r .name <<<"$item")" >> "$todo"
  done < <(lab_objects "$r")
done
n="$(wc -l < "$todo" | tr -d ' ')"
if [ "$n" = "0" ]; then say_ok "No lab objects found. Nothing to delete."; exit 0; fi
echo "These $n objects will be deleted:"
awk -F'\t' '{printf "  %-18s %s\n", $1, $3}' "$todo"
confirm "Deleting lab objects from tenant $CXONE_TENANT_ID. This cannot be undone." "DESTROY"

failed=0
while IFS=$'\t' read -r r id name; do
  path="$(res_path "$r" delete | sed "s#{id}#$id#")"
  if cx_call DELETE "$CX_ADMIN$path" >/dev/null; then say_info "deleted $r: $name"; else failed=$((failed + 1)); say_warn "could not delete $r: $name"; fi
done < "$todo"
[ "$failed" -eq 0 ] || say_fail "$failed object(s) could not be deleted (often because something still uses them). Remove the dependency and run again."
say_ok "Destroyed."
say_info "Studio scripts, phone numbers and carrier routing are not removed by this script. See docs/BUILD-MANUAL.md, Part 12."
