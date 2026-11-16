#!/usr/bin/env bash
# Counts the lab objects that exist in CXone. Read-only.
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
cx_login
total=0
for r in skills teams hoursOfOperation dispositions unavailableCodes pointsOfContact; do
  n="$(lab_objects "$r" | wc -l | tr -d ' ')"
  total=$((total + n))
  printf '%-20s %s\n' "$r" "$n"
done
echo "--------------------------"
printf '%-20s %s\n' "lab objects" "$total"
echo
echo "Points of contact:"
lab_objects pointsOfContact | jq -r '"  " + .name' || true
