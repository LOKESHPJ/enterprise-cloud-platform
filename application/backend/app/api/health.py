"""Liveness and readiness endpoints.

The readiness probe behind the ALB target group and the CloudWatch synthetic
check both use /api/health, so the payload reports which storage backend is in
play instead of returning a bare 200.
"""

from __future__ import annotations

from datetime import datetime, timezone

from fastapi import APIRouter, Response, status

from app.config import settings
from app.schemas import HealthResponse
from app.storage import get_repository

router = APIRouter()


@router.get("/health", response_model=HealthResponse, tags=["health"])
def health(response: Response) -> HealthResponse:
    healthy = False
    try:
        healthy = get_repository().health()
    except Exception:
        healthy = False

    if not healthy:
        response.status_code = status.HTTP_503_SERVICE_UNAVAILABLE

    return HealthResponse(
        status="ok" if healthy else "degraded",
        version=settings.version,
        environment=settings.environment,
        storage_backend=settings.storage_backend,
        storage_healthy=healthy,
        checked_at=datetime.now(timezone.utc),
    )
