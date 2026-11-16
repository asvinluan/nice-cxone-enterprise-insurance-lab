#!/usr/bin/env bash
# Offline checks for the AWS side. Changes nothing. Needs no AWS login.
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
need_cmd python3
TF="$(tf_bin)"

echo "== Repo checks"
( cd "$REPO_ROOT" && python3 tools/check_repo.py )

echo "== Unit tests"
( cd "$REPO_ROOT/app" && python3 -m pytest -q -p no:cacheprovider )
say_ok "Unit tests pass"

echo "== Formatting"
( cd "$TF_DIR" && "$TF" fmt -check -recursive ) || say_fail "Formatting. Run: cd terraform && $TF fmt -recursive"
say_ok "Formatting is clean"

echo "== Init and validate"
( cd "$TF_DIR" && "$TF" init -backend=false -input=false >/dev/null && "$TF" validate )
say_ok "Configuration is valid"
