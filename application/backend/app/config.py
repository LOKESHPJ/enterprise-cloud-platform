"""Runtime configuration.

Every value is environment driven so the exact same image/package can run on
ECS Fargate (PostgreSQL) or AWS Lambda (DynamoDB) without code changes.

The database URI is assembled from the discrete DB_* values that ECS injects from
Secrets Manager, so credentials never appear in a task definition or Terraform
plan output. Setting DATABASE_URL directly still wins when present (local use).
"""

from __future__ import annotations

import os
from dataclasses import dataclass, field
from urllib.parse import quote_plus


def _csv(name: str, default: str) -> list[str]:
    raw = os.getenv(name, default)
    return [item.strip() for item in raw.split(",") if item.strip()]


def _database_url() -> str:
    explicit = os.getenv("DATABASE_URL", "").strip()
    if explicit:
        return explicit

    host = os.getenv("DB_HOST", "").strip()
    if not host:
        return ""

    user = quote_plus(os.getenv("DB_USER", "platform"))
    password = quote_plus(os.getenv("DB_PASSWORD", ""))
    port = os.getenv("DB_PORT", "5432").strip()
    name = os.getenv("DB_NAME", "platform").strip()
    return f"postgresql+psycopg2://{user}:{password}@{host}:{port}/{name}"


@dataclass(frozen=True)
class Settings:
    app_name: str = "Enterprise Cloud Platform API"
    version: str = os.getenv("APP_VERSION", "0.0.0")
    environment: str = os.getenv("ENVIRONMENT", "dev")
    # dynamodb | postgres
    storage_backend: str = os.getenv("STORAGE_BACKEND", "dynamodb").lower()
    table_name: str = os.getenv("TABLE_NAME", "ecp-data")
    database_url: str = field(default_factory=_database_url)
    cors_origins: list[str] = field(
        default_factory=lambda: _csv("CORS_ORIGINS", "*")
    )
    log_level: str = os.getenv("LOG_LEVEL", "INFO")


settings = Settings()
