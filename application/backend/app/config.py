"""Runtime configuration.

Every value is environment driven so the exact same image/package can run on
ECS Fargate (PostgreSQL) or AWS Lambda (DynamoDB) without code changes.
"""

from __future__ import annotations

import os
from dataclasses import dataclass, field


def _csv(name: str, default: str) -> list[str]:
    raw = os.getenv(name, default)
    return [item.strip() for item in raw.split(",") if item.strip()]


@dataclass(frozen=True)
class Settings:
    app_name: str = "Enterprise Cloud Platform API"
    version: str = os.getenv("APP_VERSION", "0.0.0")
    environment: str = os.getenv("ENVIRONMENT", "dev")
    # dynamodb | postgres
    storage_backend: str = os.getenv("STORAGE_BACKEND", "dynamodb").lower()
    table_name: str = os.getenv("TABLE_NAME", "ecp-data")
    database_url: str = os.getenv("DATABASE_URL", "")
    cors_origins: list[str] = field(
        default_factory=lambda: _csv("CORS_ORIGINS", "*")
    )
    log_level: str = os.getenv("LOG_LEVEL", "INFO")


settings = Settings()
