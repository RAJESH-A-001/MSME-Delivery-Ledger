"""
app/database/supabase.py — MSME Delivery & Acceptance Ledger

Initialises and exports a singleton Supabase client for use by
all FastAPI route handlers and service modules.

Environment variables (loaded from backend/.env via python-dotenv):
    SUPABASE_URL            — Project REST URL
    SUPABASE_SECRET_KEY     — Service-role key  (secret — backend only)

The service-role key bypasses Row-Level Security and must NEVER be
sent to the browser or included in any API response.

Fallback: if SUPABASE_SECRET_KEY is absent the module also checks
SUPABASE_SERVICE_ROLE_KEY, which is the name used in the existing
.env / .env.example files.
"""

import os
import logging
from functools import lru_cache

from dotenv import load_dotenv
from supabase import create_client, Client

logger = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Load .env from the backend root (two levels up from this file)
# backend/
#   .env                   ← loaded here
#   app/
#     database/
#       supabase.py        ← this file
# ---------------------------------------------------------------------------
_env_path = os.path.join(os.path.dirname(__file__), "..", "..", ".env")
load_dotenv(dotenv_path=_env_path, override=False)


# ---------------------------------------------------------------------------
# Environment variable resolution
# ---------------------------------------------------------------------------
def _resolve_env(primary: str, fallback: str | None = None) -> str | None:
    """Return the value of *primary* env var, or *fallback* if primary is unset."""
    value = os.getenv(primary)
    if value:
        return value
    if fallback:
        value = os.getenv(fallback)
        if value:
            logger.debug(
                "Env var '%s' not found; using fallback '%s'.", primary, fallback
            )
            return value
    return None


# ---------------------------------------------------------------------------
# Validate required variables at import time
# ---------------------------------------------------------------------------
_SUPABASE_URL: str | None = _resolve_env("SUPABASE_URL")
# Accept either SUPABASE_SECRET_KEY (canonical per spec) or the existing
# SUPABASE_SERVICE_ROLE_KEY name already present in the project .env files.
_SUPABASE_SECRET_KEY: str | None = _resolve_env(
    "SUPABASE_SECRET_KEY", "SUPABASE_SERVICE_ROLE_KEY"
)

_missing: list[str] = []
if not _SUPABASE_URL:
    _missing.append("SUPABASE_URL")
if not _SUPABASE_SECRET_KEY:
    _missing.append("SUPABASE_SECRET_KEY (or SUPABASE_SERVICE_ROLE_KEY)")

if _missing:
    raise EnvironmentError(
        f"[Supabase] Missing required environment variable(s): {', '.join(_missing)}.\n"
        "Copy backend/.env.example to backend/.env and fill in the values."
    )

# Validate URL format
try:
    from urllib.parse import urlparse
    _parsed = urlparse(_SUPABASE_URL)
    if not _parsed.scheme or not _parsed.netloc:
        raise ValueError
except ValueError:
    raise ValueError(
        f"[Supabase] SUPABASE_URL is not a valid URL: '{_SUPABASE_URL}'"
    )


# ---------------------------------------------------------------------------
# Supabase client factory (cached singleton)
# ---------------------------------------------------------------------------
@lru_cache(maxsize=1)
def get_supabase_client() -> Client:
    """
    Return the application-wide Supabase client (service-role).

    The client is constructed once and cached for the lifetime of the
    process.  It is safe to call this function from any module.
    """
    client: Client = create_client(_SUPABASE_URL, _SUPABASE_SECRET_KEY)  # type: ignore[arg-type]
    logger.info("Supabase client initialised for project: %s", _SUPABASE_URL)
    return client


# ---------------------------------------------------------------------------
# Module-level convenience export
# ---------------------------------------------------------------------------
# Import this directly where a client instance is needed:
#   from app.database.supabase import supabase
supabase: Client = get_supabase_client()
