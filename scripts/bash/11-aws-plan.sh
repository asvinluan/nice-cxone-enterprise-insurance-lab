#!/usr/bin/env bash
# Shows what the AWS side would build. Changes nothing.
# Usage: ./scripts/bash/11-aws-plan.sh [minimal|full|nonprod]
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
env="${1:-minimal}"; vars="$(tf_env_file "$env")"; TF="$(tf_bin)"
need_cmd aws
aws sts get-caller-identity >/dev/null 2>&1 || say_fail "AWS login not working. Run 'aws sso login' or set AWS_PROFILE."
cd "$TF_DIR" || exit 1
"$TF" init -input=false >/dev/null
"$TF" plan -input=false -var-file="$vars" -out="$env.tfplan"
say_ok "Plan saved as terraform/$env.tfplan (it is in .gitignore)."
say_info "Read it. On a first run nothing should be changed or destroyed."
