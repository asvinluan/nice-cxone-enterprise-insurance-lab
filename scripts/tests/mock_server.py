#!/usr/bin/env python3
"""A local stand-in for NICE CXone (discovery, token, Admin API) and for the
AWS API. It exists so the Bash and PowerShell scripts can be run for real,
offline, in CI, with no tenant and no AWS account.

What it is NOT: a copy of the real CXone. Paths and field names follow
cxone/endpoints.json and the lab scripts, nothing more. Passing tests here
proves the scripts' logic. It does not prove the real API accepts the calls.

Behaviour you can rely on in tests:
  * Admin calls need "Authorization: Bearer <token>" from /auth/token.
  * Deleting a skill still used by a team, or an hours profile still used by a
    point of contact, returns 409 (like the real thing is likely to).
  * MOCK_FAIL_ONCE=<text>: the first request whose path contains <text> gets 503.
  * The AWS API runs the REAL handler code with fake tables (no AWS).
  * The token is written to --token-file so tests can check it never leaks.

Usage: mock_server.py --port-file PATH --token-file PATH
"""
from __future__ import annotations

import argparse
import json
import os
import secrets
import sys
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "app" / "api"))
sys.path.insert(0, str(ROOT / "app"))
os.environ.setdefault("REQUIRE_GUARDRAIL", "false")
os.environ.setdefault("SERVICE_VERSION", "mock")

import common  # noqa: E402
import handlers  # noqa: E402
from tests.fakes import FakeTable  # noqa: E402

KEY_ID = os.environ.get("MOCK_KEY_ID", "mock-key-id")
KEY_SECRET = os.environ.get("MOCK_KEY_SECRET", "mock-key-secret-do-not-leak")
API_KEY = os.environ.get("MOCK_API_KEY", "mock-api-key-do-not-leak")
TENANT = os.environ.get("MOCK_TENANT", "lab-tenant")
ADMIN = "/incontactapi/services/v27.0"

RESOURCES = {  # path -> (listKey, idField, nameField)
    "skills": ("skills", "skillId", "skillName"),
    "teams": ("teams", "teamId", "teamName"),
    "hours-of-operation": ("hoursOfOperationProfiles", "profileId", "profileName"),
    "dispositions": ("dispositions", "dispositionId", "dispositionName"),
    "unavailable-codes": ("unavailableCodes", "unavailableCodeId", "unavailableCodeName"),
    "points-of-contact": ("pointsOfContact", "pointOfContactId", "pointOfContactName"),
    "campaigns": ("campaigns", "campaignId", "campaignName"),
}

LOCK = threading.Lock()
STATE: dict[str, list[dict]] = {k: [] for k in RESOURCES}
TEAM_SKILLS: list[dict] = []
HOLIDAYS: list[dict] = []
TOKENS: set[str] = set()
FAIL_ONCE = {"text": os.environ.get("MOCK_FAIL_ONCE", ""), "done": False}
NEXT_ID = [1000]
REQUEST_LOG: list[str] = []


def seed_api_tables() -> dict:
    def load(name: str):
        return json.loads((ROOT / "app" / "seed" / name).read_text())

    return {
        "policies": FakeTable("policy_number", load("policies.json")),
        "claims": FakeTable("claim_number", load("claims.json")),
        "cases": FakeTable("case_id"),
        "attempts": FakeTable("subject"),
        "cat_events": FakeTable("postcode", load("cat_events.json")),
    }


API_TABLES = seed_api_tables()
common.set_table_factory(lambda name: API_TABLES[name])
handlers.set_bedrock_client(None)

API_ROUTES = {
    ("POST", "/policy/verify"): handlers.policy_verify,
    ("POST", "/claims/status"): handlers.claim_status,
    ("POST", "/crm/cases"): handlers.crm_case,
    ("POST", "/cat/check"): handlers.cat_check,
    ("POST", "/guard"): handlers.guard_gateway,
    ("POST", "/ai/answer"): handlers.ai_answer,
    ("GET", "/health"): handlers.health,
}


class H(BaseHTTPRequestHandler):
    server_version = "mock"

    def log_message(self, fmt, *args):  # keep test output quiet
        pass

    # -- helpers
    def _send(self, code: int, obj) -> None:
        data = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def _body(self):
        n = int(self.headers.get("Content-Length") or 0)
        raw = self.rfile.read(n).decode() if n else ""
        return raw

    def _maybe_fail_once(self, path: str) -> bool:
        t = FAIL_ONCE["text"]
        if t and not FAIL_ONCE["done"] and t in path:
            FAIL_ONCE["done"] = True
            self._send(503, {"error": "temporarily unavailable"})
            return True
        return False

    def _authed(self) -> bool:
        h = self.headers.get("Authorization", "")
        return h.startswith("Bearer ") and h[7:] in TOKENS

    # -- dispatch
    def do_GET(self):
        self._route("GET")

    def do_POST(self):
        self._route("POST")

    def do_PUT(self):
        self._route("PUT")

    def do_DELETE(self):
        self._route("DELETE")

    def _route(self, method: str):
        u = urlparse(self.path)
        path = u.path
        with LOCK:
            REQUEST_LOG.append(f"{method} {path}")
            if path == "/__state":
                return self._send(200, {"state": STATE, "teamSkills": TEAM_SKILLS, "holidays": HOLIDAYS, "log": REQUEST_LOG})
            if path == "/.well-known/cxone-configuration" and method == "GET":
                q = parse_qs(u.query)
                if q.get("tenantId", [""])[0] != TENANT:
                    return self._send(404, {"error": "unknown tenant"})
                base = f"http://127.0.0.1:{self.server.server_port}"
                return self._send(200, {"area": "mock", "domain": "local", "auth_endpoint": base, "api_endpoint": base})
            if path == "/auth/token" and method == "POST":
                try:
                    body = json.loads(self._body() or "{}")
                except ValueError:
                    return self._send(400, {"error": "bad json"})
                if body.get("username") != KEY_ID or body.get("password") != KEY_SECRET:
                    return self._send(401, {"error": "invalid_grant"})
                tok = "tok-" + secrets.token_hex(16)
                TOKENS.add(tok)
                with open(self.server.token_file, "a", encoding="utf-8") as fh:
                    fh.write(tok + "\n")
                return self._send(200, {"access_token": tok, "token_type": "Bearer", "expires_in": 3600})
            if path.startswith(ADMIN):
                if self._maybe_fail_once(path):
                    return
                if not self._authed():
                    return self._send(401, {"error": "unauthorized"})
                return self._admin(method, path[len(ADMIN):])
            if path.startswith("/api/v1"):
                return self._api(method, path[len("/api/v1"):])
        self._send(404, {"error": "not found"})

    # -- CXone admin
    def _admin(self, method: str, rest: str):
        parts = [p for p in rest.split("/") if p]
        if not parts or parts[0] not in RESOURCES:
            return self._send(404, {"error": "unknown resource"})
        res = parts[0]
        key, idf, namef = RESOURCES[res]
        items = STATE[res]
        if len(parts) == 1:
            if method == "GET":
                return self._send(200, {key: items})
            if method == "POST":
                body = json.loads(self._body() or "{}")
                if any(i.get(namef) == body.get(namef) for i in items):
                    return self._send(409, {"error": "name already exists"})
                NEXT_ID[0] += 1
                obj = dict(body)
                obj[idf] = NEXT_ID[0]
                items.append(obj)
                return self._send(201, obj)
        obj = next((i for i in items if str(i[idf]) == parts[1]), None)
        if obj is None:
            return self._send(404, {"error": "not found"})
        if len(parts) == 2:
            if method == "GET":
                return self._send(200, obj)
            if method == "PUT":
                obj.update(json.loads(self._body() or "{}"))
                return self._send(200, obj)
            if method == "DELETE":
                if res == "skills" and any(str(ts["skillId"]) == parts[1] for ts in TEAM_SKILLS):
                    return self._send(409, {"error": "skill is in use by a team"})
                if res == "hours-of-operation" and any(p.get("hoursProfileName") == obj.get(namef) for p in STATE["points-of-contact"]):
                    return self._send(409, {"error": "profile is in use"})
                if res == "teams":
                    TEAM_SKILLS[:] = [ts for ts in TEAM_SKILLS if str(ts["teamId"]) != parts[1]]
                items.remove(obj)
                return self._send(204 if False else 200, {})
        if len(parts) == 3 and res == "teams" and parts[2] == "skills" and method == "POST":
            body = json.loads(self._body() or "{}")
            TEAM_SKILLS.append({"teamId": parts[1], "skillId": body.get("skillId"), "proficiency": body.get("proficiency")})
            return self._send(201, {})
        if len(parts) == 3 and res == "hours-of-operation" and parts[2] == "holidays" and method == "POST":
            body = json.loads(self._body() or "{}")
            HOLIDAYS.append({"profileId": parts[1], **body})
            return self._send(201, {})
        return self._send(405, {"error": "method not allowed"})

    # -- AWS API (real handlers, fake tables)
    def _api(self, method: str, rest: str):
        if self.headers.get("x-api-key") != API_KEY:
            return self._send(403, {"message": "Forbidden"})
        fn = API_ROUTES.get((method, rest))
        if fn is None:
            return self._send(404, {"message": "Not Found"})
        raw = self._body() if method == "POST" else ""
        out = fn({"body": raw}, None)
        self._send(out["statusCode"], json.loads(out["body"]))


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--port-file", required=True)
    ap.add_argument("--token-file", required=True)
    ap.add_argument("--port", type=int, default=0)
    a = ap.parse_args()
    srv = ThreadingHTTPServer(("127.0.0.1", a.port), H)
    srv.token_file = a.token_file
    Path(a.token_file).write_text("", encoding="utf-8")
    Path(a.port_file).write_text(str(srv.server_port), encoding="utf-8")
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
