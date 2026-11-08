"""
main.py — MSME Delivery & Acceptance Ledger — FastAPI Application
Milestone 1: Scaffolding only. No application features implemented.
"""

import time
import logging

import httpx
from fastapi import FastAPI, Response
from fastapi.middleware.cors import CORSMiddleware

logger = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Application instance
# ---------------------------------------------------------------------------
app = FastAPI(
    title="MSME Delivery & Acceptance Ledger API",
    description=(
        "Decentralized delivery tracking and acceptance platform for MSMEs. "
        "Powered by Ethereum blockchain and Supabase."
    ),
    version="0.1.0",
    docs_url="/docs",
    redoc_url="/redoc",
)

# ---------------------------------------------------------------------------
# CORS — allow frontend dev server during development
# Update allowed_origins in production via environment variable
# ---------------------------------------------------------------------------
app.add_middleware(
    CORSMiddleware,
    allow_origins=["http://localhost:5173"],  # Vite dev server
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


# ---------------------------------------------------------------------------
# Health check endpoint
# ---------------------------------------------------------------------------
@app.get(
    "/health",
    summary="Health Check",
    description="Returns the operational status of the API server.",
    tags=["System"],
)
async def health_check():
    """
    GET /health

    Returns a simple status payload confirming the API is running.
    Used by load balancers, monitoring systems, and CI validation.
    """
    return {
        "status": "ok",
        "service": "MSME Delivery Ledger API",
        "version": "0.1.0",
    }


# ---------------------------------------------------------------------------
# Supabase connectivity health check
# ---------------------------------------------------------------------------
@app.get(
    "/api/health/supabase",
    summary="Supabase Connectivity Check",
    description=(
        "Performs a lightweight probe against Supabase to verify the backend "
        "can reach the project. Credentials are NEVER included in the response."
    ),
    tags=["System"],
)
async def supabase_health_check(response: Response):
    """
    GET /api/health/supabase

    Sends a lightweight HTTP GET to the PostgREST root endpoint
    ({SUPABASE_URL}/rest/v1/) to verify network reachability and
    valid credentials without touching any database table.

    Response fields:
    - status       : "ok" | "error"
    - connected    : bool — whether Supabase responded successfully
    - latency_ms   : round-trip time in milliseconds (success only)
    - message      : human-readable description
    - service      : always "supabase"

    HTTP status codes:
    - 200 : Supabase reachable and credentials accepted
    - 503 : Supabase unreachable or credentials rejected
    - 500 : Configuration error (missing environment variables)

    Security:
    - API keys and credentials are NEVER included in the response.
    - Internal error details are logged server-side only.
    """
    # -----------------------------------------------------------------------
    # Resolve credentials from the backend module (env already validated there)
    # -----------------------------------------------------------------------
    try:
        from app.database.supabase import _SUPABASE_URL, _SUPABASE_SECRET_KEY
    except EnvironmentError as exc:
        logger.error("Supabase config error: %s", exc, exc_info=True)
        response.status_code = 500
        return {
            "status": "error",
            "connected": False,
            "message": "Supabase environment variables are not configured.",
            "service": "supabase",
        }

    # -----------------------------------------------------------------------
    # Probe: HTTP GET {SUPABASE_URL}/rest/v1/
    # PostgREST returns 200 + an OpenAPI description when credentials are valid.
    # This requires no user tables to exist.
    # -----------------------------------------------------------------------
    probe_url = _SUPABASE_URL.rstrip("/") + "/rest/v1/"
    headers = {
        "apikey": _SUPABASE_SECRET_KEY,
        "Authorization": f"Bearer {_SUPABASE_SECRET_KEY}",
    }

    try:
        start = time.monotonic()
        async with httpx.AsyncClient(timeout=5.0) as client:
            probe_response = await client.get(probe_url, headers=headers)
        latency_ms = round((time.monotonic() - start) * 1000, 2)

        if probe_response.status_code == 200:
            return {
                "status": "ok",
                "connected": True,
                "latency_ms": latency_ms,
                "message": "Supabase connection successful.",
                "service": "supabase",
            }

        # PostgREST returned a non-200 — credentials rejected or project paused
        logger.warning(
            "Supabase probe returned HTTP %s (latency %.1f ms)",
            probe_response.status_code,
            latency_ms,
        )
        response.status_code = 503
        return {
            "status": "error",
            "connected": False,
            "latency_ms": latency_ms,
            "message": f"Supabase responded with HTTP {probe_response.status_code}.",
            "service": "supabase",
        }

    except httpx.TimeoutException:
        logger.error("Supabase probe timed out after 5 s")
        response.status_code = 503
        return {
            "status": "error",
            "connected": False,
            "message": "Supabase connection timed out.",
            "service": "supabase",
        }

    except httpx.RequestError as exc:
        # Network-level error (DNS failure, connection refused, etc.)
        logger.error("Supabase probe network error: %s", type(exc).__name__, exc_info=True)
        response.status_code = 503
        return {
            "status": "error",
            "connected": False,
            "message": "Supabase is unreachable. Check server logs for details.",
            "service": "supabase",
        }
