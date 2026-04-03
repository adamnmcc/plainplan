from __future__ import annotations

import hashlib
import secrets
from typing import Any

from fastapi import Header, HTTPException

from .db import execute, fetch_one


def hash_key(raw_key: str) -> str:
    return hashlib.sha256(raw_key.encode("utf-8")).hexdigest()


def generate_api_key() -> tuple[str, str, str]:
    key = f"pp_live_{secrets.token_hex(24)}"
    return key, hash_key(key), key[:12]


def _extract_key(auth_header: str | None) -> str:
    if not auth_header:
        raise HTTPException(
            status_code=401,
            detail={
                "success": False,
                "error": "MISSING_API_KEY",
                "message": "Missing Authorization header. Use: Authorization: Bearer pp_live_xxxxx",
            },
        )

    parts = auth_header.split(" ")
    key = parts[1] if len(parts) == 2 and parts[0].lower() == "bearer" else parts[0]

    if not key or not key.startswith("pp_live_"):
        raise HTTPException(
            status_code=401,
            detail={
                "success": False,
                "error": "INVALID_API_KEY",
                "message": "Invalid API key format. Keys start with pp_live_",
            },
        )
    return key


def authenticate_api_key(authorization: str | None = Header(default=None)) -> dict[str, Any]:
    raw_key = _extract_key(authorization)
    key_hash = hash_key(raw_key)

    row = fetch_one(
        "SELECT id, email, name, is_active, rate_limit_per_minute, rate_limit_per_day, key_hash, key_prefix "
        "FROM api_keys WHERE key_hash = %s",
        (key_hash,),
    )

    if not row:
        raise HTTPException(
            status_code=401,
            detail={
                "success": False,
                "error": "INVALID_API_KEY",
                "message": "API key not found. Generate one at https://dev.plainplan.click/api/keys",
            },
        )

    if not row["is_active"]:
        raise HTTPException(
            status_code=401,
            detail={
                "success": False,
                "error": "KEY_DISABLED",
                "message": "This API key has been deactivated",
            },
        )

    execute("UPDATE api_keys SET last_used_at = NOW() WHERE id = %s", (row["id"],))
    return row
