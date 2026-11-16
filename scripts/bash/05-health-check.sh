#!/usr/bin/env bash
# Calls the AWS integration layer's /health. Changes nothing. Never prints the API key.
# Reads the URL and key from the OpenTofu outputs, or from KESTREL_API_URL / KESTREL_API_KEY.
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
need_cmd curl; need_cmd jq

url="${KESTREL_API_URL:-}"
if [ -z "$url" ]; then
  ( cd "$TF_DIR" && "$(tf_bin)" output -raw api_url ) > /dev/null 2>&1 || say_fail "Set KESTREL_API_URL, or apply the AWS side first (12-aws-apply.sh)."
  url="$(cd "$TF_DIR" && "$(tf_bin)" output -raw api_url)"
fi
key="${KESTREL_API_KEY:-}"
if [ -z "$key" ]; then key="$(cd "$TF_DIR" && "$(tf_bin)" output -raw api_key_value)"; fi

tmp="$(umask 077; mktemp)"; trap 'rm -f "$tmp"' EXIT
code="$(printf 'header = "x-api-key: %s"\n' "$key" | curl -sS -o "$tmp" -w '%{http_code}' -K - "${url%/}/health" || true)"
unset key
echo "HTTP $code"
jq . "$tmp" 2>/dev/null || head -c 300 "$tmp"
[ "$code" = "200" ] || say_fail "The integration layer is not healthy."
say_ok "Integration layer healthy"
