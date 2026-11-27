"""Backend selection.

Imports are lazy so that the Lambda package never needs SQLAlchemy and the Fargate
image never needs boto3 unless it is actually talking to DynamoDB.
"""

from __future__ import annotations

from functools import lru_cache

from app.config import settings
from app.storage.base import Repository


@lru_cache(maxsize=1)
def get_repository() -> Repository:
    if settings.storage_backend == "postgres":
        from app.storage.postgres import PostgresRepository

        return PostgresRepository()

    from app.storage.dynamo import DynamoRepository

    return DynamoRepository()


__all__ = ["Repository", "get_repository"]
