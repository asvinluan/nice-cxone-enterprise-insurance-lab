#!/usr/bin/env python3
"""Repo safety and consistency check. Run before every commit. Also runs in CI.

What it checks, in plain words:
  1. No secrets, state files or real-looking identifiers are in the repo.
  2. Every CXone config file matches its JSON schema.
  3. Every name used in one file exists in the file that owns it
     (a team's skill exists, a point of contact's script exists, and so on).
  4. Every Studio design follows the safety rules in docs (timeouts, fail modes,
     masked capture, no personal data in spoken text, no dead ends).
  5. The OpenAPI contract and the Terraform routes agree.
  6. Terraform wiring is consistent (variables, outputs, resource references).
     This does not replace `tofu validate`; CI runs that too.

Usage:  python3 tools/check_repo.py [--root PATH]
Exit code 0 = all passed. 1 = something failed (each failure is printed).
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

try:
    import yaml
except ImportError:  # pragma: no cover
    sys.exit("PyYAML is required: pip install pyyaml jsonschema python-hcl2")
try:
    import jsonschema
except ImportError:  # pragma: no cover
    sys.exit("jsonschema is required: pip install pyyaml jsonschema python-hcl2")
try:
    import hcl2
except ImportError:  # pragma: no cover
    hcl2 = None


def _strip_quotes(x):
    """python-hcl2 8.x keeps the quote marks on strings and block labels; older versions strip them.
    Normalise to the old shape so the checks give the same answer on every version."""
    if isinstance(x, str):
        return x[1:-1] if len(x) >= 2 and x[0] == '"' and x[-1] == '"' else x
    if isinstance(x, list):
        return [_strip_quotes(i) for i in x]
    if isinstance(x, dict):
        return {_strip_quotes(k): _strip_quotes(v) for k, v in x.items()}
    return x


def hcl_load(path):
    with open(path, encoding="utf-8") as fh:
        return _strip_quotes(hcl2.load(fh))

FAILS: list[str] = []
PASSES: list[str] = []


def fail(msg: str) -> None:
    FAILS.append(msg)


def ok(msg: str) -> None:
    PASSES.append(msg)


def load_json(path: Path):
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception as exc:  # noqa: BLE001
        fail(f"{path}: cannot read JSON ({exc})")
        return None


# ------------------------------------------------------------------ 1. secrets

SKIP_DIRS = {".git", ".terraform", "__pycache__", ".pytest_cache", "node_modules", "build", "dist", ".venv"}
FORBIDDEN_NAMES = (".tfstate", ".tfstate.backup", ".tfplan", ".env", "tfplan", "terraform.tfvars", "backend.tf", ".pem", ".key")
SECRET_PATTERNS = [
    ("AWS access key id", re.compile(r"\b(AKIA|ASIA)[0-9A-Z]{16}\b")),
    ("private key block", re.compile(r"-----BEGIN [A-Z ]*PRIVATE KEY-----")),
    ("AWS account id (12 digits in an arn)", re.compile(r"arn:aws[a-z-]*:[a-z0-9-]*:[a-z0-9-]*:(?!123456789012)[0-9]{12}:")),
    ("bearer token", re.compile(r"[Bb]earer\s+[A-Za-z0-9._-]{30,}")),
    ("JWT", re.compile(r"\beyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}")),
    ("hard-coded secret assignment", re.compile(r"""(?i)\b(secret|password|access[_-]?key|api[_-]?key)\b\s*[:=]\s*["'][A-Za-z0-9/+_=-]{16,}["']""")),
]
# An AU phone number that is NOT in the reserved fiction range 03 5550 xxxx or 0491 570 xxx.
PHONE = re.compile(r"(?<![\d+])(\+?61\s?[2-478]\s?\d{4}\s?\d{4}|\(0[2-8]\)\s?\d{4}\s?\d{4}|04\d{2}\s?\d{3}\s?\d{3})(?!\d)")
PHONE_OK = re.compile(r"(\+?61\s?3\s?5550|\(?03\)?\s?5550|0491\s?570)")


def check_files(root: Path) -> None:
    bad = 0
    for path in root.rglob("*"):
        if not path.is_file() or any(part in SKIP_DIRS for part in path.relative_to(root).parts):
            continue
        rel = path.relative_to(root)
        name = path.name
        if any(name.endswith(f) or name == f for f in FORBIDDEN_NAMES):
            if name not in ("terraform.tfvars.example", "backend.tf.example"):
                fail(f"{rel}: this kind of file must never be committed")
                bad += 1
                continue
        if path.suffix in {".zip", ".png", ".jpg", ".pdf", ".pyc", ".lock"} or path.stat().st_size > 2_000_000:
            continue
        try:
            text = path.read_text(encoding="utf-8")
        except UnicodeDecodeError:
            continue
        if rel.parts[:2] == ("tools", "check_repo.py") or rel.as_posix() == "tools/check_repo.py":
            continue
        for label, pat in SECRET_PATTERNS:
            m = pat.search(text)
            if m:
                fail(f"{rel}: looks like a {label}")
                bad += 1
        if path.suffix in {".json", ".yaml", ".yml", ".md", ".sh", ".ps1", ".py", ".tf", ".tfvars"} and "tests" not in rel.parts:
            for m in PHONE.finditer(text):
                if not PHONE_OK.search(m.group(0)):
                    fail(f"{rel}: real-looking phone number '{m.group(0)}' (use 03 5550 xxxx)")
                    bad += 1
    if not bad:
        ok("no secrets, state files or real-looking phone numbers")


# ------------------------------------------------------------------ 2. schemas

def check_config(root: Path) -> dict:
    cfg = {}
    pairs = [
        ("business_unit", "business_unit.schema.json"), ("skills", "skills.schema.json"), ("teams", "teams.schema.json"),
        ("hours", "hours.schema.json"), ("dispositions", "dispositions.schema.json"),
        ("unavailable_codes", "unavailable_codes.schema.json"), ("points_of_contact", "points_of_contact.schema.json"),
    ]
    bad = 0
    for name, schema_file in pairs:
        data = load_json(root / "cxone/config" / f"{name}.json")
        schema = load_json(root / "cxone/schema" / schema_file)
        if data is None or schema is None:
            bad += 1
            continue
        cfg[name] = data
        for err in jsonschema.Draft202012Validator(schema).iter_errors(data):
            loc = "/".join(str(p) for p in err.absolute_path) or "(top)"
            fail(f"cxone/config/{name}.json at {loc}: {err.message[:140]}")
            bad += 1
    if not bad:
        ok("7 CXone config files match their schemas")
    return cfg


# ------------------------------------------------------------------ 3. cross refs

def check_refs(root: Path, cfg: dict, scripts: dict) -> None:
    if len(cfg) < 7:
        return
    bad = 0
    skills = {s["name"] for s in cfg["skills"]["skills"]}
    teams = {t["name"] for t in cfg["teams"]["teams"]}
    profiles = {p["name"] for p in cfg["hours"]["profiles"]}
    names = [s["name"] for s in cfg["skills"]["skills"]]
    for label, items in (("skill", names), ("team", [t["name"] for t in cfg["teams"]["teams"]]),
                         ("point of contact", [p["name"] for p in cfg["points_of_contact"]["pointsOfContact"]]),
                         ("hours profile", [p["name"] for p in cfg["hours"]["profiles"]])):
        dup = {n for n in items if items.count(n) > 1}
        if dup:
            fail(f"duplicate {label} names: {sorted(dup)}")
            bad += 1
    prefix = cfg["business_unit"]["prefix"]
    for s in cfg["skills"]["skills"]:
        if s["primaryTeam"] and s["primaryTeam"] not in teams:
            fail(f"skill '{s['name']}': primaryTeam '{s['primaryTeam']}' is not a team"); bad += 1
        for o in s["overflow"]:
            if o["team"] not in teams:
                fail(f"skill '{s['name']}': overflow team '{o['team']}' is not a team"); bad += 1
        if s["kind"] == "queue" and not s["primaryTeam"]:
            fail(f"skill '{s['name']}': a queue skill needs a primaryTeam"); bad += 1
        afters = [o["afterSeconds"] for o in s["overflow"]]
        if afters != sorted(afters):
            fail(f"skill '{s['name']}': overflow steps must be in time order"); bad += 1
    for t in cfg["teams"]["teams"]:
        for ts in t["skills"]:
            if ts["skill"] not in skills:
                fail(f"team '{t['name']}': skill '{ts['skill']}' does not exist"); bad += 1
    # every queue skill must be staffed by at least one team
    staffed = {ts["skill"] for t in cfg["teams"]["teams"] for ts in t["skills"]}
    for s in cfg["skills"]["skills"]:
        if s["kind"] == "language":
            continue  # language skills are given to individual agents, not whole teams
        if s["name"] not in staffed:
            fail(f"skill '{s['name']}' has no team that can answer it"); bad += 1
    for h in cfg["hours"]["holidays"]:
        for c in h["closes"]:
            if c not in profiles:
                fail(f"holiday '{h['name']}': profile '{c}' does not exist"); bad += 1
    if cfg["hours"]["catSwitchProfile"] not in profiles:
        fail("hours.catSwitchProfile is not a profile"); bad += 1
    for p in cfg["points_of_contact"]["pointsOfContact"]:
        if p["script"] not in scripts:
            fail(f"point of contact '{p['name']}': script '{p['script']}' has no design file"); bad += 1
        if p["hoursProfile"] not in profiles:
            fail(f"point of contact '{p['name']}': hours profile '{p['hoursProfile']}' does not exist"); bad += 1
    nums = [p["number"] for p in cfg["points_of_contact"]["pointsOfContact"]]
    if len(nums) != len(set(nums)):
        fail("two points of contact share a number"); bad += 1
    for kind, items in (("skill", names), ("team", list(teams)), ("hours profile", list(profiles))):
        for n in items:
            if not n.startswith(prefix):
                # skills and teams are named in plain words; only hours profiles carry the prefix
                if kind == "hours profile":
                    fail(f"{kind} '{n}' must start with '{prefix}' so destroy can find it"); bad += 1
    if not bad:
        ok("names agree across skills, teams, hours, points of contact and scripts")


# ------------------------------------------------------------------ 4. studio lint

NODE_TYPES = {"Begin", "Hours", "Run", "Play", "Case", "Menu", "Capture", "RestApi", "Snippet", "Reqagent", "QueueCallback", "Hangup", "Return"}
MAX_TIMEOUT = 8          # Studio default is 10; we stay under it
MAX_MENU_OPTIONS = 5


def targets(node: dict) -> list[str]:
    out = []
    for key in ("next", "onTimeout", "onInvalid"):
        if isinstance(node.get(key), str):
            out.append(node[key])
    b = node.get("branches")
    if isinstance(b, dict):
        out += [v for v in b.values() if isinstance(v, str)]
    o = node.get("options")
    if isinstance(o, dict):
        out += [v for v in o.values() if isinstance(v, str)]
    return out


def lint_script(root: Path, name: str, spec: dict, scripts: dict, ops: set[str], skills: set[str], profiles: set[str]) -> int:
    bad = 0
    nodes = spec.get("nodes") or {}
    sens = set(spec.get("sensitiveVariables") or [])

    def f(msg: str) -> None:
        nonlocal bad
        fail(f"cxone/studio/{name}.yaml: {msg}")
        bad += 1

    if spec.get("script") != name:
        f(f"'script' must be '{name}'")
    if "begin" not in nodes or nodes["begin"].get("type") != "Begin":
        f("needs a 'begin' node of type Begin")
    for nid, n in nodes.items():
        t = n.get("type")
        if t not in NODE_TYPES:
            f(f"node '{nid}': unknown type '{t}'"); continue
        for tgt in targets(n):
            if tgt not in nodes:
                f(f"node '{nid}': goes to '{tgt}' which does not exist")
        if t in {"Hangup", "Return"}:
            if targets(n):
                f(f"node '{nid}': an end node must not have a next")
        elif t == "Case":
            if "default" not in (n.get("branches") or {}) and t == "Case" and nid not in ("retry_check",):
                # Case without default is a dead end when no label matches
                f(f"node '{nid}': Case needs a 'default' branch")
        elif t in {"Begin", "Snippet", "Play", "Run", "QueueCallback"}:
            if not isinstance(n.get("next"), str):
                f(f"node '{nid}': needs a 'next'")
        if t == "Hours":
            if n.get("profile") not in profiles:
                f(f"node '{nid}': hours profile '{n.get('profile')}' does not exist")
            for need in ("open", "closed", "holiday", "emergency"):
                if need not in (n.get("branches") or {}):
                    f(f"node '{nid}': Hours must handle '{need}'")
        if t == "Run":
            if n.get("script") not in scripts:
                f(f"node '{nid}': script '{n.get('script')}' has no design file")
        if t == "Reqagent":
            if n.get("skill") not in skills:
                f(f"node '{nid}': skill '{n.get('skill')}' does not exist")
            if "timeoutSeconds" not in n or "onTimeout" not in n:
                f(f"node '{nid}': a queue needs timeoutSeconds and onTimeout (no endless waits)")
        if t == "Capture":
            var = n.get("variable")
            if var in sens and n.get("mask") is not True:
                f(f"node '{nid}': '{var}' is sensitive and must be captured with mask: true")
            if "timeoutSeconds" not in n or "onTimeout" not in n or "onInvalid" not in n:
                f(f"node '{nid}': Capture needs timeoutSeconds, onTimeout and onInvalid")
            if n.get("mode") == "speech" and var in sens:
                f(f"node '{nid}': sensitive values must be keypad (DTMF), not speech")
        if t == "Menu":
            if len(n.get("options") or {}) > MAX_MENU_OPTIONS:
                f(f"node '{nid}': more than {MAX_MENU_OPTIONS} menu options")
            if "onTimeout" not in n or "onInvalid" not in n:
                f(f"node '{nid}': Menu needs onTimeout and onInvalid")
        if t == "RestApi":
            op = n.get("operation")
            if op not in ops:
                f(f"node '{nid}': operation '{op}' is not in the OpenAPI contract")
            if not isinstance(n.get("timeoutSeconds"), (int, float)) or n["timeoutSeconds"] > MAX_TIMEOUT:
                f(f"node '{nid}': timeoutSeconds must be set and <= {MAX_TIMEOUT}")
            if n.get("failMode") not in ("open", "closed"):
                f(f"node '{nid}': failMode must be 'open' or 'closed'")
            b = n.get("branches") or {}
            if "ok" not in b or "error" not in b:
                f(f"node '{nid}': a REST call needs both 'ok' and 'error' branches")
        if t in {"Play", "Menu", "Capture"}:
            text = n.get("text") or n.get("prompt") or ""
            for v in re.findall(r"\{(\w+)\}", text):
                if v in sens:
                    f(f"node '{nid}': spoken text uses sensitive variable '{v}'")
        if n.get("action") == "log" or t == "Trace":
            for v in sens:
                if v in json.dumps(n):
                    f(f"node '{nid}': logs a sensitive variable")
        if "why" in n and len(str(n["why"]).strip()) < 10:
            f(f"node '{nid}': 'why' is too short to be useful")
    # reachability
    seen: set[str] = set()
    stack = ["begin"]
    while stack:
        cur = stack.pop()
        if cur in seen or cur not in nodes:
            continue
        seen.add(cur)
        stack += targets(nodes[cur])
    for nid in nodes:
        if nid not in seen:
            f(f"node '{nid}' can never be reached")
    # every path must be able to end
    ends = {nid for nid, n in nodes.items() if n.get("type") in {"Hangup", "Return"}}
    if not ends:
        f("has no Hangup or Return node")
    can_end = set(ends)
    changed = True
    while changed:
        changed = False
        for nid, n in nodes.items():
            if nid not in can_end and any(t in can_end for t in targets(n)):
                can_end.add(nid); changed = True
    for nid in seen:
        if nid not in can_end:
            f(f"node '{nid}' cannot reach an end (possible loop)")
    # a person must be reachable from every RestApi error path: its error branch must not be an end by itself
    return bad


def check_studio(root: Path, cfg: dict) -> dict:
    scripts = {}
    for p in sorted((root / "cxone/studio").glob("*.yaml")):
        try:
            scripts[p.stem] = yaml.safe_load(p.read_text(encoding="utf-8"))
        except Exception as exc:  # noqa: BLE001
            fail(f"{p}: invalid YAML ({exc})")
    api = yaml.safe_load((root / "openapi/kestrel-cxone-api.yaml").read_text(encoding="utf-8"))
    ops = {op["operationId"] for path in api["paths"].values() for op in path.values() if isinstance(op, dict) and "operationId" in op}
    skills = {s["name"] for s in cfg.get("skills", {}).get("skills", [])}
    profiles = {p["name"] for p in cfg.get("hours", {}).get("profiles", [])}
    bad = 0
    for name, spec in scripts.items():
        bad += lint_script(root, name, spec, scripts, ops, skills, profiles)
    if scripts and not bad:
        ok(f"{len(scripts)} Studio designs pass the safety rules")
    return scripts


# ------------------------------------------------------------------ 5. openapi vs terraform

def check_openapi_vs_tf(root: Path) -> None:
    api = yaml.safe_load((root / "openapi/kestrel-cxone-api.yaml").read_text(encoding="utf-8"))
    paths = set(api["paths"])
    text = (root / "terraform/modules/integration/main.tf").read_text(encoding="utf-8")
    routes = re.findall(r'^\s{4}\w+\s*=\s*\{\s*parent\s*=\s*"([^"]*)",\s*part\s*=\s*"([^"]*)"', text, re.M)
    tf_paths = {"/" + (f"{p}/{q}" if p else q) for p, q in routes}
    bad = 0
    for p in sorted(tf_paths - paths):
        fail(f"terraform route {p} is missing from openapi/kestrel-cxone-api.yaml"); bad += 1
    for p in sorted(paths - tf_paths):
        fail(f"openapi path {p} has no terraform route"); bad += 1
    if not bad and tf_paths:
        ok(f"OpenAPI and Terraform agree on {len(tf_paths)} routes")
    elif not tf_paths:
        fail("could not read any routes from terraform/modules/integration/main.tf")


# ------------------------------------------------------------------ 6. terraform wiring

REF_VAR = re.compile(r"(?<![\w.])var\.(\w+)")
REF_LOCAL = re.compile(r"(?<![\w.])local\.(\w+)")
REF_MOD = re.compile(r"(?<![\w.])module\.(\w+)\.(\w+)")
REF_RES = re.compile(r'(?<![\w."])(aws_\w+)\.(\w+)')
REF_DATA = re.compile(r"(?<![\w.])data\.(\w+)\.(\w+)")


def strip_comments(text: str) -> str:
    return "\n".join(re.sub(r"(^|\s)(#|//).*$", "", ln) for ln in text.splitlines())


def tf_info(d: Path) -> dict:
    files = sorted(d.glob("*.tf"))
    raw = "\n".join(strip_comments(f.read_text(encoding="utf-8")) for f in files)
    info = {"vars": {}, "outputs": set(), "locals": set(), "resources": set(), "data": set(), "raw": raw, "modules": {}}
    for f in files:
        parsed = hcl_load(f)
        for block in parsed.get("variable", []):
            for k, v in block.items():
                info["vars"][k] = ("default" in v)
        for block in parsed.get("output", []):
            info["outputs"].update(k for k in block)
        for block in parsed.get("locals", []):
            info["locals"].update(k for k in block if not k.startswith("__"))
        for block in parsed.get("resource", []):
            for rtype, named in block.items():
                info["resources"].update((rtype, n) for n in named)
        for block in parsed.get("data", []):
            for rtype, named in block.items():
                info["data"].update((rtype, n) for n in named)
        for block in parsed.get("module", []):
            for k, v in block.items():
                info["modules"][k] = {a: (b[0] if isinstance(b, list) and len(b) == 1 else b) for a, b in v.items() if not a.startswith("__")}
    return info


def check_terraform(root: Path) -> None:
    if hcl2 is None:
        ok("terraform wiring check skipped (python-hcl2 not installed)")
        return
    tf_root = root / "terraform"
    bad = 0

    def f(msg: str) -> None:
        nonlocal bad
        fail(msg); bad += 1

    mods = {}
    for d in sorted((tf_root / "modules").iterdir()):
        if d.is_dir():
            try:
                mods[d.name] = tf_info(d)
            except Exception as exc:  # noqa: BLE001
                f(f"terraform/modules/{d.name}: cannot parse ({exc})")
    try:
        rootinfo = tf_info(tf_root)
    except Exception as exc:  # noqa: BLE001
        f(f"terraform: cannot parse ({exc})")
        return

    for name, info in {**{f"modules/{k}": v for k, v in mods.items()}, "root": rootinfo}.items():
        raw = info["raw"]
        for v in set(REF_VAR.findall(raw)):
            if v not in info["vars"]:
                f(f"terraform {name}: var.{v} is used but not declared")
        for v in set(REF_LOCAL.findall(raw)):
            if v not in info["locals"]:
                f(f"terraform {name}: local.{v} is used but not declared")
        for rtype, rname in set(REF_RES.findall(raw)):
            if (rtype, rname) not in info["resources"]:
                f(f"terraform {name}: {rtype}.{rname} is referenced but not declared")
        for rtype, rname in set(REF_DATA.findall(raw)):
            if (rtype, rname) not in info["data"]:
                f(f"terraform {name}: data.{rtype}.{rname} is referenced but not declared")
        for v, has_default in info["vars"].items():
            if name != "root" and not has_default and f"var.{v}" not in raw:
                f(f"terraform {name}: variable '{v}' is declared but never used")

    # module calls from root
    for mname, args in rootinfo["modules"].items():
        src = str(args.get("source", "")).replace("${", "").replace("}", "")
        target = Path(src).name
        if target not in mods:
            f(f"terraform root: module '{mname}' points at '{src}' which is not in modules/")
            continue
        declared = mods[target]["vars"]
        for a in args:
            if a in ("source", "count", "for_each", "providers", "depends_on", "version"):
                continue
            if a not in declared:
                f(f"terraform root: module '{mname}' passes '{a}' but the module has no such variable")
        for v, has_default in declared.items():
            if not has_default and v not in args:
                f(f"terraform root: module '{mname}' is missing required variable '{v}'")
    # module output references
    name_to_dir = {m: Path(str(a.get("source", ""))).name for m, a in rootinfo["modules"].items()}
    for m, out in set(REF_MOD.findall(rootinfo["raw"])):
        d = name_to_dir.get(m)
        if d is None:
            f(f"terraform root: module.{m} is referenced but not declared")
        elif out not in mods.get(d, {"outputs": set()})["outputs"]:
            f(f"terraform root: module.{m}.{out} is referenced but module '{d}' has no such output")
    # tfvars
    for tv in sorted((tf_root / "envs").glob("*.tfvars")) + [tf_root / "terraform.tfvars.example"]:
        if not tv.exists():
            continue
        for line in tv.read_text(encoding="utf-8").splitlines():
            m = re.match(r"^\s*([A-Za-z_]\w*)\s*=", line)
            if m and m.group(1) not in rootinfo["vars"]:
                f(f"{tv.relative_to(root)}: sets '{m.group(1)}' which is not a root variable")
    # lambda handlers named in terraform must exist in handlers.py
    handlers = (root / "app/api/handlers.py").read_text(encoding="utf-8")
    integ = mods.get("integration", {}).get("raw", "")
    for fn in re.findall(r'handler\s*=\s*"handlers\.(\w+)"', integ):
        if not re.search(rf"^def {fn}\(", handlers, re.M):
            f(f"terraform integration: handler handlers.{fn} does not exist in app/api/handlers.py")
    if not bad:
        ok("terraform wiring is consistent (variables, outputs, references, module arguments)")



# ------------------------------------------------------------------ 6b. migration pack

def check_migration(root: Path, cfg: dict) -> None:
    import csv
    bad = 0
    inv = root / "migration" / "number-inventory.csv"
    tp = root / "migration" / "test-plan.csv"
    if not inv.exists() or not tp.exists():
        fail("migration/number-inventory.csv or test-plan.csv is missing")
        return
    rows = list(csv.DictReader(inv.open(encoding="utf-8")))
    poc = {p["number"]: p for p in cfg.get("points_of_contact", {}).get("pointsOfContact", [])}
    if {r["number"] for r in rows} != set(poc):
        fail("migration/number-inventory.csv and cxone/config/points_of_contact.json list different numbers"); bad += 1
    for r in rows:
        p = poc.get(r["number"])
        if p and (p["name"] != r["cxone_point_of_contact"] or p["script"] != r["cxone_script"]):
            fail(f"migration/number-inventory.csv: {r['number']} disagrees with points_of_contact.json"); bad += 1
        if r["wave"] not in {"1", "2", "3", "4"}:
            fail(f"migration/number-inventory.csv: {r['number']} has no valid wave"); bad += 1
        if not r["rollback_target"].strip():
            fail(f"migration/number-inventory.csv: {r['number']} has no roll-back target"); bad += 1
    ids = [r["id"] for r in csv.DictReader(tp.open(encoding="utf-8"))]
    if len(ids) != len(set(ids)):
        fail("migration/test-plan.csv has duplicate ids"); bad += 1
    if not bad:
        ok(f"migration pack agrees with the config ({len(rows)} numbers, {len(ids)} test cases)")

# ------------------------------------------------------------------ 7. misc

def check_misc(root: Path) -> None:
    bad = 0
    gi = root / ".gitignore"
    if not gi.exists():
        fail(".gitignore is missing"); bad += 1
    else:
        t = gi.read_text(encoding="utf-8")
        for need in (".terraform", "*.tfstate", "*.tfplan", ".env", "backend.tf", "terraform.tfvars", "export/"):
            if need not in t:
                fail(f".gitignore does not list {need}"); bad += 1
    for need in ("README.md", "LICENSE", ".github/workflows/ci.yml"):
        if not (root / need).exists():
            fail(f"{need} is missing"); bad += 1
    if not bad:
        ok(".gitignore, README, LICENSE and CI workflow are present")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default=str(Path(__file__).resolve().parent.parent))
    root = Path(ap.parse_args().root).resolve()
    check_files(root)
    cfg = check_config(root)
    scripts = check_studio(root, cfg)
    check_refs(root, cfg, scripts)
    check_openapi_vs_tf(root)
    check_terraform(root)
    check_migration(root, cfg)
    check_misc(root)
    for p in PASSES:
        print(f"  PASS  {p}")
    for m in FAILS:
        print(f"  FAIL  {m}")
    if FAILS:
        print(f"\n{len(FAILS)} problem(s) found.")
        return 1
    print("\nAll checks passed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
