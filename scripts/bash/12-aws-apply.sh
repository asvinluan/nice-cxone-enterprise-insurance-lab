#!/usr/bin/env bash
# Builds the AWS side FROM THE SAVED PLAN. This CHANGES your AWS account.
# Usage: ./scripts/bash/12-aws-apply.sh [minimal|full|nonprod]
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
env="${1:-minimal}"; tf_env_file "$env" >/dev/null; TF="$(tf_bin)"
[ -f "$TF_DIR/$env.tfplan" ] || say_fail "No saved plan for '$env'. Run 11-aws-plan.sh $env first."
confirm "This will BUILD AWS resources from the saved '$env' plan. Check the account and region first." "YES"
cd "$TF_DIR" || exit 1
"$TF" apply -input=false "$env.tfplan"
rm -f "$env.tfplan"
say_ok "Applied. Next: ./scripts/bash/13-aws-seed.sh then 14-aws-test-api.sh"
