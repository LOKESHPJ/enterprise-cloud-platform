"""DynamoDB implementation of the storage contract.

Single table design:
  products: pk=PRODUCT#<id>  sk=METADATA  gsi1pk=TYPE#PRODUCT  gsi1sk=<created_at>
  orders:   pk=ORDER#<id>    sk=METADATA  gsi1pk=TYPE#ORDER    gsi1sk=<created_at>
"""

from __future__ import annotations

import uuid
from datetime import datetime, timezone
from typing import Any

import boto3
from boto3.dynamodb.conditions import Key
from botocore.exceptions import ClientError

from app.config import settings
from app.storage.base import Repository

INDEX_NAME = "gsi1"
INTERNAL_KEYS = {"pk", "sk", "gsi1pk", "gsi1sk"}

# The catalogue is platform-owned reference data, not visitor-writable content.
# Deterministic ids make seeding idempotent: a conditional put means a second
# cold start cannot duplicate a product.
SEED_PRODUCTS: list[dict[str, Any]] = [
    {
        "id": "seed-aurora-desk-lamp",
        "name": "Aurora Desk Lamp",
        "description": "Warm dimmable LED lamp with a machined aluminium base.",
        "price_cents": 8900,
        "currency": "USD",
        "category": "lighting",
        "stock": 42,
    },
    {
        "id": "seed-orbit-headphones",
        "name": "Orbit Wireless Headphones",
        "description": "Over-ear ANC headphones, 40 hour battery.",
        "price_cents": 24900,
        "currency": "USD",
        "category": "audio",
        "stock": 18,
    },
    {
        "id": "seed-slate-keyboard",
        "name": "Slate Mechanical Keyboard",
        "description": "75 percent layout, hot-swap switches, PBT caps.",
        "price_cents": 13500,
        "currency": "USD",
        "category": "peripherals",
        "stock": 27,
    },
    {
        "id": "seed-nimbus-mat",
        "name": "Nimbus Standing Mat",
        "description": "Anti-fatigue mat for standing desks.",
        "price_cents": 6900,
        "currency": "USD",
        "category": "furniture",
        "stock": 60,
    },
]


def _now() -> datetime:
    return datetime.now(timezone.utc)


def _iso(value: datetime) -> str:
    return value.astimezone(timezone.utc).isoformat().replace("+00:00", "Z")


def _public(item: dict[str, Any]) -> dict[str, Any]:
    """Strip DynamoDB plumbing and normalise numeric types."""
    cleaned = {k: v for k, v in item.items() if k not in INTERNAL_KEYS}
    for key in ("price_cents", "stock", "total_cents", "quantity",
                "unit_price_cents", "subtotal_cents"):
        if key in cleaned:
            cleaned[key] = int(cleaned[key])
    if "items" in cleaned and isinstance(cleaned["items"], list):
        for row in cleaned["items"]:
            for key in ("quantity", "unit_price_cents", "subtotal_cents"):
                if key in row:
                    row[key] = int(row[key])
    return cleaned


class DynamoRepository(Repository):
    backend_name = "dynamodb"

    def __init__(self, table_name: str | None = None) -> None:
        self.table_name = table_name or settings.table_name
        self._table = boto3.resource("dynamodb").Table(self.table_name)
        self._seeded = False

    # ---------------------------------------------------------------- seeding
    def _ensure_seeded(self) -> None:
        if self._seeded:
            return
        self._seeded = True
        for product in SEED_PRODUCTS:
            item = {
                **product,
                "created_at": "2026-01-01T00:00:00Z",
                "updated_at": "2026-01-01T00:00:00Z",
                "pk": f"PRODUCT#{product['id']}",
                "sk": "METADATA",
                "gsi1pk": "TYPE#PRODUCT",
                "gsi1sk": f"2026-01-01T00:00:00Z#{product['id']}",
            }
            try:
                self._table.put_item(
                    Item=item, ConditionExpression="attribute_not_exists(pk)"
                )
            except ClientError as exc:
                if exc.response["Error"]["Code"] != "ConditionalCheckFailedException":
                    raise

    # ---------------------------------------------------------------- health
    def health(self) -> bool:
        try:
            self._table.load()
            return True
        except Exception:
            return False

    # -------------------------------------------------------------- products
    def list_products(self, limit: int = 50) -> list[dict[str, Any]]:
        self._ensure_seeded()
        response = self._table.query(
            IndexName=INDEX_NAME,
            KeyConditionExpression=Key("gsi1pk").eq("TYPE#PRODUCT"),
            ScanIndexForward=False,
            Limit=limit,
        )
        return [_public(item) for item in response.get("Items", [])]

    def get_product(self, product_id: str) -> dict[str, Any] | None:
        self._ensure_seeded()
        response = self._table.get_item(
            Key={"pk": f"PRODUCT#{product_id}", "sk": "METADATA"}
        )
        item = response.get("Item")
        return _public(item) if item else None

    def create_product(self, data: dict[str, Any]) -> dict[str, Any]:
        product_id = data.get("id") or uuid.uuid4().hex
        stamp = _now()
        item = {
            **data,
            "id": product_id,
            "created_at": _iso(stamp),
            "updated_at": _iso(stamp),
            "pk": f"PRODUCT#{product_id}",
            "sk": "METADATA",
            "gsi1pk": "TYPE#PRODUCT",
            "gsi1sk": f"{_iso(stamp)}#{product_id}",
        }
        self._table.put_item(
            Item=item,
            ConditionExpression="attribute_not_exists(pk)",
        )
        return _public(item)

    def update_product(
        self, product_id: str, patch: dict[str, Any]
    ) -> dict[str, Any] | None:
        if not patch:
            return self.get_product(product_id)

        patch = {**patch, "updated_at": _iso(_now())}
        names = {f"#f{i}": key for i, key in enumerate(patch)}
        values = {f":v{i}": value for i, value in enumerate(patch.values())}
        assignments = ", ".join(f"#f{i} = :v{i}" for i in range(len(patch)))
        try:
            response = self._table.update_item(
                Key={"pk": f"PRODUCT#{product_id}", "sk": "METADATA"},
                UpdateExpression=f"SET {assignments}",
                ExpressionAttributeNames=names,
                ExpressionAttributeValues=values,
                ConditionExpression="attribute_exists(pk)",
                ReturnValues="ALL_NEW",
            )
        except ClientError as exc:
            if exc.response["Error"]["Code"] == "ConditionalCheckFailedException":
                return None
            raise
        return _public(response["Attributes"])

    def delete_product(self, product_id: str) -> bool:
        try:
            self._table.delete_item(
                Key={"pk": f"PRODUCT#{product_id}", "sk": "METADATA"},
                ConditionExpression="attribute_exists(pk)",
            )
            return True
        except ClientError as exc:
            if exc.response["Error"]["Code"] == "ConditionalCheckFailedException":
                return False
            raise

    # ---------------------------------------------------------------- orders
    def list_orders(self, limit: int = 50) -> list[dict[str, Any]]:
        response = self._table.query(
            IndexName=INDEX_NAME,
            KeyConditionExpression=Key("gsi1pk").eq("TYPE#ORDER"),
            ScanIndexForward=False,
            Limit=limit,
        )
        return [_public(item) for item in response.get("Items", [])]

    def get_order(self, order_id: str) -> dict[str, Any] | None:
        response = self._table.get_item(
            Key={"pk": f"ORDER#{order_id}", "sk": "METADATA"}
        )
        item = response.get("Item")
        return _public(item) if item else None

    def create_order(self, data: dict[str, Any]) -> dict[str, Any]:
        order_id = data.get("id") or uuid.uuid4().hex
        stamp = _now()
        item = {
            **data,
            "id": order_id,
            "status": data.get("status", "confirmed"),
            "created_at": _iso(stamp),
            "pk": f"ORDER#{order_id}",
            "sk": "METADATA",
            "gsi1pk": "TYPE#ORDER",
            "gsi1sk": f"{_iso(stamp)}#{order_id}",
        }
        self._table.put_item(Item=item)
        return _public(item)
