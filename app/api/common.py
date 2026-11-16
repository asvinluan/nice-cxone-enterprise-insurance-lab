"""Shared helpers for the CXone integration functions.

Design rules this file enforces, because Studio's REST API action is picky:

  * Every response is a small, flat JSON object. Studio reads JSON only and
    accepts about 32 KB of response.
  * Logging NEVER carries customer identifiers. ``log()`` refuses a field whose
    name looks like one, so a careless future edit fails a test instead of
    leaking a policy number into CloudWatch.
  * A malformed request is a 400 with a machine-readable reason. Anything
    unexpected is a 500 with no detail. Studio's REST action retries twice by
    itself, so every write must be safe to repeat (see crm_case).
"""

from __future__ import annotations

import base64
import json
import os
import re
import time
from typing import Any, Callable

# ---------------------------------------------------------------- limits

MAX_ATTEMPTS = 5  # failed verifications before a lock-out
LOCK_SECONDS = 15 * 60  # how long a lock-out lasts

POLICY_RE = re.compile(r"^\d{8}$")  # keyed on a phone keypad, so digits only
CLAIM_RE = re.compile(r"^9\d{9}$")  # ten digits starting with 9: cannot be mistaken for a tax file or Medicare number
POSTCODE_RE = re.compile(r"^\d{4}$")

# Names of fields that must never reach a log line.
_FORBIDDEN_LOG_FIELDS = frozenset(
    {
        "policynumber", "policy_number", "claimnumber", "claim_number", "postcode",
        "text", "question", "answer", "summary", "name", "phone", "email",
        "address", "card", "pan", "body", "premium", "subject",
    }
)


class BadRequest(Exception):
    """The caller sent something unusable. ``field`` names the problem."""

    def __init__(self, field: str, reason: str = "invalid_input") -> None:
        super().__init__(f"{reason}: {field}")
        self.field = field
        self.reason = reason


# ---------------------------------------------------------------- responses


def response(status: int, body: dict[str, Any]) -> dict[str, Any]:
    """API Gateway proxy response."""
    return {
        "statusCode": status,
        "headers": {
            "Content-Type": "application/json",
            "Cache-Control": "no-store",
        },
        "body": json.dumps(body, separators=(",", ":")),
    }


def bad_request(exc: BadRequest, status: int = 400) -> dict[str, Any]:
    return response(status, {"error": exc.reason, "field": exc.field})


def internal_error() -> dict[str, Any]:
    return response(500, {"error": "internal"})


# ---------------------------------------------------------------- input


def parse_body(event: dict[str, Any]) -> dict[str, Any]:
    """Return the JSON object in an API Gateway proxy event."""
    raw = (event or {}).get("body")
    if raw is None or raw == "":
        raise BadRequest("body", "empty_body")
    if (event or {}).get("isBase64Encoded"):
        try:
            raw = base64.b64decode(raw).decode("utf-8")
        except (ValueError, UnicodeDecodeError) as exc:
            raise BadRequest("body", "bad_encoding") from exc
    try:
        data = json.loads(raw)
    except (TypeError, ValueError) as exc:
        raise BadRequest("body", "bad_json") from exc
    if not isinstance(data, dict):
        raise BadRequest("body", "not_an_object")
    return data


def digits_only(value: Any, field: str, pattern: re.Pattern[str]) -> str:
    """Accept '1234 5678' or '1234-5678' (typed on the web) and return digits.

    A phone keypad can only send digits, so the stored format is digits.
    """
    if not isinstance(value, str) and not isinstance(value, int):
        raise BadRequest(field)
    cleaned = re.sub(r"[\s-]", "", str(value))
    if not pattern.match(cleaned):
        raise BadRequest(field)
    return cleaned


def text_field(data: dict[str, Any], field: str, max_len: int, required: bool = True) -> str:
    value = data.get(field)
    if value is None or value == "":
        if required:
            raise BadRequest(field, "missing_field")
        return ""
    if not isinstance(value, str):
        raise BadRequest(field)
    value = value.strip()
    if len(value) > max_len:
        raise BadRequest(field, "too_long")
    return value


# ---------------------------------------------------------------- logging


def log(event: str, **fields: Any) -> None:
    """One JSON line per call. CloudWatch metric filters read these fields."""
    for key in fields:
        if key.lower() in _FORBIDDEN_LOG_FIELDS:
            raise ValueError(f"refusing to log field {key!r}: it can hold customer data")
    print(json.dumps({"event": event, **fields}, separators=(",", ":")))


class Timer:
    def __init__(self) -> None:
        self._start = time.monotonic()

    def ms(self) -> int:
        return int((time.monotonic() - self._start) * 1000)


# ---------------------------------------------------------------- tables

_table_factory: Callable[[str], Any] | None = None


def set_table_factory(factory: Callable[[str], Any] | None) -> None:
    """Tests install a fake here. Production leaves it None."""
    global _table_factory
    _table_factory = factory


def table(logical_name: str) -> Any:
    """Return the DynamoDB table for a logical name such as 'policies'."""
    if _table_factory is not None:
        return _table_factory(logical_name)
    import boto3  # imported late so tests and tools need no AWS setup

    env_name = f"TABLE_{logical_name.upper()}"
    name = os.environ.get(env_name)
    if not name:
        raise RuntimeError(f"{env_name} is not set")
    return boto3.resource("dynamodb").Table(name)


def now() -> int:
    return int(time.time())


# ---------------------------------------------------------------- lock-out


def lock_subject(kind: str, number: str) -> str:
    return f"{kind}#{number}"


def is_locked(subject: str) -> bool:
    item = table("attempts").get_item(Key={"subject": subject}).get("Item")
    if not item:
        return False
    return int(item.get("count", 0)) >= MAX_ATTEMPTS and int(item.get("expires_at", 0)) > now()


def record_failure(subject: str) -> int:
    """Count one failed check. Counts any failure, whether or not the number exists,
    so a lock-out cannot be used to find out which numbers are real."""
    result = table("attempts").update_item(
        Key={"subject": subject},
        UpdateExpression="ADD #c :one SET expires_at = :exp",
        ExpressionAttributeNames={"#c": "count"},
        ExpressionAttributeValues={":one": 1, ":exp": now() + LOCK_SECONDS},
        ReturnValues="UPDATED_NEW",
    )
    return int(result.get("Attributes", {}).get("count", 0))


# ---------------------------------------------------------------- number checks


def luhn_ok(digits: str) -> bool:
    total = 0
    for i, ch in enumerate(reversed(digits)):
        n = int(ch)
        if i % 2 == 1:
            n *= 2
            if n > 9:
                n -= 9
        total += n
    return total % 10 == 0


def tfn_ok(digits: str) -> bool:
    """Australian tax file number: nine digits, weighted sum divisible by 11."""
    if len(digits) != 9:
        return False
    weights = (1, 4, 3, 7, 5, 8, 6, 9, 10)
    return sum(int(d) * w for d, w in zip(digits, weights)) % 11 == 0


def medicare_ok(digits: str) -> bool:
    """Medicare card number: ten digits, first 2 to 6, ninth digit is a check digit."""
    if len(digits) not in (10, 11) or digits[0] not in "23456":
        return False
    weights = (1, 3, 7, 9, 1, 3, 7, 9)
    return sum(int(d) * w for d, w in zip(digits[:8], weights)) % 10 == int(digits[8])


def sensitive_numbers_in(text: str) -> list[str]:
    """Names (never values) of sensitive number types found in free text."""
    found: set[str] = set()
    for match in re.finditer(r"(?<!\d)(?:\d[ -]?){8,19}(?!\d)", text):
        digits = re.sub(r"[ -]", "", match.group())
        if 13 <= len(digits) <= 19 and luhn_ok(digits):
            found.add("card_number")
        if len(digits) == 9 and tfn_ok(digits):
            found.add("tax_file_number")
        if len(digits) in (10, 11) and medicare_ok(digits):
            found.add("medicare_number")
    return sorted(found)
