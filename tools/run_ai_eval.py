#!/usr/bin/env python3
"""Runs the fixed AI guard test prompts in evals/guardrail_cases.json.

Offline (default): runs the real guard_gateway code with a fake table layer.
  Only cases with layer=local can be judged. layer=bedrock cases are reported
  as SKIPPED (not passed): they need the real guardrail.

Online: python3 tools/run_ai_eval.py --url https://.../v1
  with KESTREL_API_KEY in the environment. Runs every case through your
  deployed /guard endpoint.

Exit code 0 only if every case that ran matched its expected action.
It prints no secret. The API key is read from the environment, never from args.
"""
from __future__ import annotations

import argparse
import contextlib
import io
import json
import os
import sys
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "app" / "api"))
sys.path.insert(0, str(ROOT / "app"))


def run_offline(case: dict) -> tuple[str, list[str]]:
    os.environ["REQUIRE_GUARDRAIL"] = "false"
    import handlers  # noqa: PLC0415

    body = {"direction": case["direction"], "text": case["text"]}
    with contextlib.redirect_stdout(io.StringIO()):  # the handler writes one log line per call
        out = handlers.guard_gateway({"body": json.dumps(body)}, None)
    data = json.loads(out["body"])
    return data["action"], data.get("reasons", [])


def run_online(case: dict, url: str, key: str) -> tuple[str, list[str]]:
    body = {"direction": case["direction"], "text": case["text"]}
    if case.get("grounding"):
        body["groundingSource"] = case["grounding"]
    if case.get("query"):
        body["query"] = case["query"]
    req = urllib.request.Request(
        url.rstrip("/") + "/guard", data=json.dumps(body).encode(), method="POST",
        headers={"Content-Type": "application/json", "x-api-key": key},
    )
    try:
        with urllib.request.urlopen(req, timeout=15) as resp:  # noqa: S310
            data = json.loads(resp.read())
    except urllib.error.HTTPError as exc:
        return f"http_{exc.code}", []
    return data.get("action", "none"), data.get("reasons", [])


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--url", help="API base URL including stage. Omit to run offline.")
    ap.add_argument("--cases", default=str(ROOT / "evals" / "guardrail_cases.json"))
    a = ap.parse_args()
    cases = json.loads(Path(a.cases).read_text(encoding="utf-8"))["cases"]
    key = os.environ.get("KESTREL_API_KEY", "")
    if a.url and not key:
        print("FAIL Set KESTREL_API_KEY first.", file=sys.stderr)
        return 2

    passed = failed = skipped = 0
    for c in cases:
        if not a.url and c["layer"] != "local":
            skipped += 1
            print(f"SKIP  {c['id']}  needs the real guardrail  ({c['why']})")
            continue
        got, reasons = run_online(c, a.url, key) if a.url else run_offline(c)
        good = got == c["expect"] and (not c.get("reason") or c["reason"] in reasons)
        if good:
            passed += 1
            print(f"PASS  {c['id']}  {c['expect']}")
        else:
            failed += 1
            print(f"FAIL  {c['id']}  expected {c['expect']}, got {got} {reasons}  ({c['why']})")
    mode = "online" if a.url else "offline"
    print(f"\n{mode}: {passed} passed, {failed} failed, {skipped} skipped (not run).")
    if skipped:
        print("Skipped cases are NOT passes. Run with --url against a deployed lab to cover them.")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
