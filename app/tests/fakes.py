"""Tiny stand-ins for DynamoDB and Bedrock, so tests need no AWS account."""

from __future__ import annotations

from typing import Any


class ConditionalCheckFailed(Exception):
    def __init__(self) -> None:
        super().__init__("conditional check failed")
        self.response = {"Error": {"Code": "ConditionalCheckFailedException"}}


class FakeTable:
    def __init__(self, key: str, items: list[dict[str, Any]] | None = None) -> None:
        self.key = key
        self.items: dict[str, dict[str, Any]] = {}
        for item in items or []:
            self.items[str(item[key])] = dict(item)
        self.fail_next = False

    def get_item(self, Key: dict[str, Any], **_: Any) -> dict[str, Any]:  # noqa: N803
        if self.fail_next:
            raise RuntimeError("simulated outage")
        item = self.items.get(str(Key[self.key]))
        return {"Item": dict(item)} if item else {}

    def put_item(self, Item: dict[str, Any], ConditionExpression: str | None = None, **_: Any) -> dict[str, Any]:  # noqa: N803
        k = str(Item[self.key])
        if ConditionExpression == f"attribute_not_exists({self.key})" and k in self.items:
            raise ConditionalCheckFailed()
        self.items[k] = dict(Item)
        return {}

    def update_item(self, Key: dict[str, Any], ExpressionAttributeValues: dict[str, Any], **_: Any) -> dict[str, Any]:  # noqa: N803
        k = str(Key[self.key])
        item = self.items.setdefault(k, {self.key: k})
        item["count"] = int(item.get("count", 0)) + int(ExpressionAttributeValues[":one"])
        item["expires_at"] = ExpressionAttributeValues[":exp"]
        return {"Attributes": {"count": item["count"]}}


class FakeBedrock:
    """Returns whatever you give it, and remembers the last call."""

    def __init__(self, result: dict[str, Any] | None = None, error: Exception | None = None) -> None:
        self.result = result or {"action": "NONE"}
        self.error = error
        self.calls: list[dict[str, Any]] = []

    def converse(self, **kwargs: Any) -> dict[str, Any]:
        self.calls.append(kwargs)
        if self.error:
            raise self.error
        return self.result

    def apply_guardrail(self, **kwargs: Any) -> dict[str, Any]:
        self.calls.append(kwargs)
        if self.error:
            raise self.error
        return self.result
