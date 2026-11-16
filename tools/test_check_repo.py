"""Proves the repo checker actually catches mistakes.

A checker that has never been seen to fail is not evidence. Each test copies
the repo, breaks ONE thing, and expects check_repo.py to say so.
Run: python3 -m pytest tools -q
"""
from __future__ import annotations

import shutil
import subprocess
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
SKIP = shutil.ignore_patterns(".git", ".terraform", "__pycache__", ".pytest_cache", "evidence", "*.zip", "*.tfplan")


@pytest.fixture()
def repo(tmp_path):
    dst = tmp_path / "r"
    shutil.copytree(ROOT, dst, ignore=SKIP)
    return dst


def check(repo: Path) -> tuple[int, str]:
    r = subprocess.run([sys.executable, str(repo / "tools" / "check_repo.py"), "--root", str(repo)], capture_output=True, text=True)
    return r.returncode, r.stdout


def edit(repo: Path, rel: str, old: str, new: str) -> None:
    p = repo / rel
    text = p.read_text(encoding="utf-8")
    assert old in text, f"test setup: '{old}' not found in {rel}"
    p.write_text(text.replace(old, new, 1), encoding="utf-8")


def test_clean_repo_passes(repo):
    code, out = check(repo)
    assert code == 0, out


CASES = [
    ("sensitive capture not masked", "cxone/studio/verify_caller.yaml", "    mask: true\n    onTimeout: fail_path\n    onInvalid: retry\n    why: DTMF", "    mask: false\n    onTimeout: fail_path\n    onInvalid: retry\n    why: DTMF", "must be captured with mask"),
    ("bad failMode", "cxone/studio/verify_caller.yaml", "failMode: closed", "failMode: maybe", "failMode must be"),
    ("timeout too long", "cxone/studio/verify_caller.yaml", "timeoutSeconds: 6", "timeoutSeconds: 30", "timeoutSeconds must be set"),
    ("unknown skill in Studio", "cxone/studio/ai_assist.yaml", "skill: Servicing General", "skill: Nonexistent Skill", "does not exist"),
    ("operation not in OpenAPI", "cxone/studio/ai_assist.yaml", "operation: guard\n", "operation: guardX\n", "not in the OpenAPI"),
    ("loop with no exit", "cxone/studio/care_path.yaml", "    next: queue_care\n  queue_care", "    next: greet\n  queue_care", "cannot reach an end"),
    ("spoken sensitive variable", "cxone/studio/claims_self_service.yaml", "text: \"I couldn't check those details here. Let me connect you to a person.\"", "text: \"Claim {claimNumber} not found\"", "sensitive variable"),
    ("Case without default", "cxone/studio/front_door.yaml", "      default: claims_menu\n", "", "needs a 'default'"),
    ("Hours branch missing", "cxone/studio/front_door.yaml", "      holiday: recording_notice\n", "", "Hours must handle"),
    ("team uses unknown skill", "cxone/config/teams.json", '"Claims FNOL"', '"Claims Missing"', "does not exist"),
    ("point of contact uses unknown script", "cxone/config/points_of_contact.json", '"front_door"', '"no_such_script"', "no design file"),
    ("real-looking phone number", "cxone/config/points_of_contact.json", "+61355500101", "+612" + "99991234", "points_of_contact.json"),
    ("config out of range", "cxone/config/skills.json", '"slaPercent": 80', '"slaPercent": 180', "skills.json"),
    ("terraform output missing", "terraform/main.tf", "module.foundation.kms_key_arn", "module.foundation.kms_key_arnX", "has no such output"),
    ("access key committed", "app/api/common.py", "import json", 'import json\nKEY = "' + "AKIA" + 'ABCDEFGHIJKLMNOP"', "AWS access key"),
    ("openapi route missing", "openapi/kestrel-cxone-api.yaml", "  /cat/check:", "  /cat/checkX:", "missing from openapi"),
]


@pytest.mark.parametrize("label,rel,old,new,expect", CASES, ids=[c[0] for c in CASES])
def test_breaking_one_thing_is_caught(repo, label, rel, old, new, expect):
    edit(repo, rel, old, new)
    code, out = check(repo)
    assert code == 1, f"{label}: checker did not fail\n{out}"
    assert expect in out, f"{label}: expected '{expect}' in output\n{out}"


def test_state_file_is_refused(repo):
    (repo / "terraform" / "terraform.tfstate").write_text("{}", encoding="utf-8")
    code, out = check(repo)
    assert code == 1 and "must never be committed" in out
