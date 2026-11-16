#!/usr/bin/env bash
# Tears down everything the AWS side built. This DELETES things.
# Usage: ./scripts/bash/19-aws-destroy.sh [minimal|full|nonprod]
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
env="${1:-minimal}"; vars="$(tf_env_file "$env")"; TF="$(tf_bin)"
need_cmd aws
aws sts get-caller-identity >/dev/null 2>&1 || say_fail "AWS login not working."
cd "$TF_DIR" || exit 1
"$TF" init -input=false >/dev/null
echo "Resources that will be destroyed:"
"$TF" plan -destroy -input=false -var-file="$vars" -out=destroy.tfplan | tail -n 40
confirm "This DELETES the '$env' stack, including tables and logs. An Object Lock archive bucket with unexpired retention cannot be deleted until retention ends." "DESTROY"
"$TF" apply -input=false destroy.tfplan
rm -f destroy.tfplan
say_ok "Destroyed. Now check the AWS Billing console for anything that remains."
