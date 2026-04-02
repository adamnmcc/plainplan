from __future__ import annotations

import threading
import time
from collections import defaultdict
from typing import Any

from fastapi import Depends, HTTPException

from .auth import authenticate_api_key

_request_log: dict[str, list[float]] = defaultdict(list)
_lock = threading.Lock()


def _cleanup_old(entries: list[float], now: float) -> list[float]:
    day_ago = now - 86400.0
    return [t for t in entries if t > day_ago]


def rate_limited_api_key(api_key: dict[str, Any] = Depends(authenticate_api_key)) -> dict[str, Any]:
    key_id = str(api_key["id"])
    now = time.time()

    per_minute = int(api_key.get("rate_limit_per_minute") or 10)
    per_day = int(api_key.get("rate_limit_per_day") or 200)

    with _lock:
        entries = _cleanup_old(_request_log[key_id], now)

        minute_ago = now - 60.0
        minute_entries = [t for t in entries if t > minute_ago]

        if len(minute_entries) >= per_minute:
            oldest = min(minute_entries)
            retry_after = max(int((oldest + 60.0 - now) + 0.999), 1)
            raise HTTPException(
                status_code=429,
                detail={
                    "success": False,
                    "error": "RATE_LIMITED",
                    "message": f"Rate limit exceeded ({per_minute}/minute). Try again in {retry_after}s",
                    "retry_after": retry_after,
                },
            )

        if len(entries) >= per_day:
            oldest_day = min(entries)
            retry_after = max(int((oldest_day + 86400.0 - now) + 0.999), 1)
            raise HTTPException(
                status_code=429,
                detail={
                    "success": False,
                    "error": "RATE_LIMITED",
                    "message": f"Daily rate limit exceeded ({per_day}/day). Upgrade your plan for higher limits.",
                    "retry_after": retry_after,
                },
            )

        entries.append(now)
        _request_log[key_id] = entries

    return api_key
