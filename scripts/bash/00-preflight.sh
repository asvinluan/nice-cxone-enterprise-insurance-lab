#!/usr/bin/env bash
# Preflight: checks tools and logins. Changes nothing.
# Usage: ./scripts/bash/00-preflight.sh [--aws]
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

WITH_AWS=0; [ "${1:-}" = "--aws" ] && WITH_AWS=1

echo "== Tools"
for c in curl jq python3 git; do need_cmd "$c"; say_ok "$c found"; done
if [ "$WITH_AWS" = "1" ]; then
  need_cmd aws; say_ok "aws found"
  tf_bin >/dev/null; say_ok "$(tf_bin) found"
fi

echo "== CXone login"
cx_login
count="$(cx_names skills | jq length)"
say_ok "Admin API reachable (your tenant has $count skills)"
say_info "Check that this is your LAB tenant. If it is not, close this shell."

if [ "$WITH_AWS" = "1" ]; then
  echo "== AWS login"
  need_cmd aws
  aws sts get-caller-identity --query Arn --output text >/dev/null 2>&1 || say_fail "AWS login not working. Run 'aws sso login' or set AWS_PROFILE."
  say_ok "AWS credentials work"
  say_info "Region: ${AWS_REGION:-${AWS_DEFAULT_REGION:-not set}}. Check this is your LAB account."
fi
