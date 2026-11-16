#!/usr/bin/env bash
# Collects non-secret evidence into evidence/<timestamp>/ with a SHA-256 manifest.
# Safe to hand to an auditor. Never contains tokens, keys, account ids or personal data.
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
need_cmd jq; need_cmd python3

stamp="$(date -u +%Y%m%dT%H%M%SZ)"
out="$REPO_ROOT/evidence/$stamp"
mkdir -p "$out"

{
  echo "created_utc: $stamp"
  echo "git_commit: $(git -C "$REPO_ROOT" rev-parse --short HEAD 2>/dev/null || echo 'not a git repo')"
  echo "python: $(python3 --version 2>&1)"
  echo "jq: $(jq --version)"
  command -v tofu >/dev/null 2>&1 && echo "tofu: $(tofu version | head -1)"
  command -v terraform >/dev/null 2>&1 && echo "terraform: $(terraform version | head -1)"
} > "$out/environment.txt"

( cd "$REPO_ROOT" && python3 tools/check_repo.py ) > "$out/repo-check.txt" 2>&1 || true
( cd "$REPO_ROOT/app" && python3 -m pytest -q -p no:cacheprovider ) > "$out/unit-tests.txt" 2>&1 || true

( cd "$REPO_ROOT" && find cxone openapi terraform app -type f \
    -not -path '*/.terraform/*' -not -path '*/__pycache__/*' -not -name '*.pyc' | LC_ALL=C sort | xargs sha256sum ) > "$out/file-hashes.txt"

if [ -n "${CXONE_TENANT_ID:-}" ] && [ -n "${CXONE_ACCESS_KEY_ID:-}" ] && [ -n "${CXONE_ACCESS_KEY_SECRET:-}" ]; then
  cx_login >/dev/null
  { for r in skills teams hoursOfOperation dispositions unavailableCodes pointsOfContact; do
      printf '%s\t%s\n' "$r" "$(lab_objects "$r" | wc -l | tr -d ' ')"
    done; } > "$out/cxone-lab-object-counts.tsv"
  say_ok "CXone object counts included"
else
  say_info "No CXone login in this shell: object counts skipped."
fi

( cd "$out" && sha256sum ./*.txt ./*.tsv 2>/dev/null > MANIFEST.sha256 ) || true
say_ok "Evidence written to evidence/$stamp"
say_info "It is in .gitignore. Review it before you share it."
