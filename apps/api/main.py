from __future__ import annotations

import os
from datetime import datetime, timezone

from fastapi import FastAPI
from fastapi.responses import JSONResponse

app = FastAPI(
    title="JAI Business Platform API",
    version=os.getenv("JAI_VERSION", "0.1.0"),
    docs_url="/docs",
    redoc_url="/redoc",
)


@app.get("/health/live", tags=["health"])
def liveness() -> dict[str, str]:
    return {"status": "ok"}


@app.get("/health/ready", tags=["health"])
def readiness() -> JSONResponse:
    # The first POC keeps readiness intentionally small. Database/AI probes
    # will be added behind dedicated adapters so health checks cannot mutate data.
    return JSONResponse(
        status_code=200,
        content={
            "status": "ready",
            "timestamp": datetime.now(timezone.utc).isoformat(),
        },
    )


@app.get("/api/v1/platform", tags=["platform"])
def platform() -> dict[str, str]:
    return {
        "product": "JAI",
        "mode": "private-local-ai",
        "tenant_model": "multi-tenant-capable",
        "database": "postgresql",
        "vector_store": "pgvector",
    }
