"""FastAPI application entry point.

Runs unchanged in three places:
  * ECS Fargate behind the ALB          (STORAGE_BACKEND=postgres)
  * AWS Lambda behind API Gateway HTTP  (STORAGE_BACKEND=dynamodb, via Mangum)
  * a developer's machine               (STORAGE_BACKEND=postgres, optional)
"""

from __future__ import annotations

import logging
import time
from pathlib import Path

from fastapi import FastAPI, HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse, JSONResponse
from fastapi.staticfiles import StaticFiles

from app.api import health, orders, products
from app.config import settings

logging.basicConfig(
    level=settings.log_level,
    format='{"level":"%(levelname)s","logger":"%(name)s","message":"%(message)s"}',
)
log = logging.getLogger("ecp.api")

app = FastAPI(
    title=settings.app_name,
    version=settings.version,
    description="Enterprise Cloud Platform - catalogue and order API.",
    docs_url="/api/docs",
    redoc_url=None,
    openapi_url="/api/openapi.json",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origins,
    allow_credentials=False,
    allow_methods=["GET", "POST", "PATCH", "DELETE", "OPTIONS"],
    allow_headers=["*"],
)


@app.middleware("http")
async def access_log(request: Request, call_next):
    started = time.perf_counter()
    response = await call_next(request)
    elapsed_ms = round((time.perf_counter() - started) * 1000, 2)
    log.info(
        "%s %s -> %s in %sms",
        request.method,
        request.url.path,
        response.status_code,
        elapsed_ms,
    )
    response.headers["X-Response-Time-ms"] = str(elapsed_ms)
    return response


@app.exception_handler(Exception)
async def unhandled_exception_handler(request: Request, exc: Exception) -> JSONResponse:
    log.exception("unhandled error on %s %s", request.method, request.url.path)
    return JSONResponse(
        status_code=500,
        content={"detail": "internal server error", "path": request.url.path},
    )


app.include_router(health.router, prefix="/api")
app.include_router(products.router, prefix="/api")
app.include_router(orders.router, prefix="/api")

# ---------------------------------------------------------------------------
# Optional SPA hosting from the same process.
#
# Lambda mode bundles the built React app into `static/` next to the `app`
# package, so one HTTPS origin serves both the UI and the API (no CORS, no
# CloudFront dependency). In the container track the bundle is served by nginx
# instead, `static/` is absent, and this block is skipped.
# ---------------------------------------------------------------------------
STATIC_DIR = Path(__file__).resolve().parent.parent / "static"
SPA_AVAILABLE = (STATIC_DIR / "index.html").is_file()

if SPA_AVAILABLE:
    assets_dir = STATIC_DIR / "assets"
    if assets_dir.is_dir():
        app.mount("/assets", StaticFiles(directory=assets_dir), name="assets")

    @app.get("/{full_path:path}", include_in_schema=False)
    def serve_spa(full_path: str) -> FileResponse:
        if full_path == "api" or full_path.startswith("api/"):
            raise HTTPException(status_code=404, detail="not found")

        candidate = (STATIC_DIR / full_path).resolve()
        if full_path and candidate.is_file() and STATIC_DIR.resolve() in candidate.parents:
            return FileResponse(candidate)

        # Client side routing: any unknown path renders the SPA shell.
        return FileResponse(STATIC_DIR / "index.html")

else:

    @app.get("/", include_in_schema=False)
    def root() -> dict[str, str]:
        return {
            "service": settings.app_name,
            "version": settings.version,
            "environment": settings.environment,
            "storage_backend": settings.storage_backend,
            "docs": "/api/docs",
            "health": "/api/health",
        }
