#!/usr/bin/env bash
# Shows what apply WOULD create. Changes nothing.
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
cx_login
export DRY_RUN=1
apply_all
echo
say_ok "Plan: $CREATED to create, $EXISTS already exist."
say_info "Apply only ever creates. It does not change or delete what already exists."
