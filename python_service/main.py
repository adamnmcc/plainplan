from __future__ import annotations

import hashlib
import json
from pathlib import Path
from time import time
from typing import Any

from fastapi import Depends, FastAPI, Header, HTTPException, Query, Request
from fastapi.responses import JSONResponse

from .ai_analyzer import analyze_plan
from .auth import generate_api_key, hash_key
from .config import get_settings
from .db import execute, fetch_all, fetch_one
from .plan_parser import PlanParseError, parse_plan
from .rate_limit import rate_limited_api_key

FIXTURE_PATH = Path(__file__).resolve().parent.parent / "test-fixtures" / "sample-plan.json"

app = FastAPI(title="PlanPlain API", docs_url=None, redoc_url=None)


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "healthy"}


@app.get("/")
def root() -> dict[str, Any]:
    return {
        "name": "PlanPlain API",
        "status": "healthy",
        "docs_path": "/api",
    }


@app.get("/api")
def api_info() -> dict[str, Any]:
    return {
        "name": "PlanPlain API",
        "version": "1.0.0",
        "description": "Terraform plan analysis made simple",
        "endpoints": {
            "POST /api/keys": {"description": "Generate an API key", "auth": "none"},
            "GET /api/keys/verify": {"description": "Verify an API key", "auth": "Bearer pp_live_xxxxx"},
            "POST /api/analyze": {"description": "Analyze a Terraform plan", "auth": "Bearer pp_live_xxxxx"},
            "GET /api/example": {"description": "Get a sample plan for testing", "auth": "none"},
        },
    }


@app.get("/api/example")
def api_example() -> dict[str, Any]:
    try:
        sample = json.loads(FIXTURE_PATH.read_text(encoding="utf-8"))
        return {"description": "Sample Terraform plan for testing", "plan": sample}
    except FileNotFoundError as exc:
        raise HTTPException(status_code=500, detail={"error": "Sample plan not found"}) from exc


@app.post("/api/keys")
def create_key(payload: dict[str, Any]) -> JSONResponse:
    settings = get_settings()
    email = payload.get("email")
    name = payload.get("name")

    if not isinstance(email, str) or "@" not in email:
        raise HTTPException(status_code=400, detail={"success": False, "error": "INVALID_INPUT", "message": "Valid email is required"})

    user_row = fetch_one("SELECT id FROM users WHERE LOWER(email) = LOWER(%s)", (email,))
    if user_row:
        user_id = user_row["id"]
    else:
        inserted = fetch_one(
            "INSERT INTO users (email, name) VALUES (%s, %s) RETURNING id",
            (email.lower(), name),
        )
        user_id = inserted["id"]

    key_count_row = fetch_one(
        "SELECT COUNT(*) AS count FROM api_keys WHERE user_id = %s AND is_active = true",
        (user_id,),
    )
    if int(key_count_row["count"]) >= 5:
        raise HTTPException(status_code=400, detail={"success": False, "error": "KEY_LIMIT", "message": "Maximum 5 active API keys per account."})

    raw_key, key_hash, key_prefix = generate_api_key()
    key_name = (name or "default")[:255]

    execute(
        "INSERT INTO api_keys (key_hash, key_prefix, user_id, email, name) VALUES (%s, %s, %s, %s, %s)",
        (key_hash, key_prefix, user_id, email.lower(), key_name),
    )

    return JSONResponse(
        status_code=201,
        content={
            "success": True,
            "api_key": raw_key,
            "key_prefix": key_prefix,
            "message": "Store this key securely — it cannot be retrieved later.",
            "dashboard_url": f"{settings.website_base_url}/dashboard?key={raw_key}" if settings.website_base_url else f"/dashboard?key={raw_key}",
        },
    )


@app.get("/api/keys/verify")
def verify_key(authorization: str | None = Header(default=None)) -> dict[str, Any]:
    if not authorization:
        raise HTTPException(status_code=401, detail={"success": False, "valid": False, "message": "No API key provided"})

    parts = authorization.split(" ")
    key = parts[1] if len(parts) == 2 else parts[0]
    if not key.startswith("pp_live_"):
        raise HTTPException(status_code=401, detail={"success": False, "valid": False, "message": "Invalid key format"})

    row = fetch_one(
        "SELECT id, email, name, is_active, rate_limit_per_minute, rate_limit_per_day, created_at, last_used_at "
        "FROM api_keys WHERE key_hash = %s",
        (hash_key(key),),
    )

    if not row or not row["is_active"]:
        raise HTTPException(status_code=401, detail={"success": False, "valid": False, "message": "Invalid or inactive key"})

    return {
        "success": True,
        "valid": True,
        "key": {
            "name": row["name"],
            "email": row["email"],
            "created_at": row["created_at"],
            "last_used_at": row["last_used_at"],
            "limits": {"per_minute": row["rate_limit_per_minute"], "per_day": row["rate_limit_per_day"]},
        },
    }


def _log_api_request(data: dict[str, Any]) -> None:
    execute(
        "INSERT INTO api_requests (api_key_hash, request_size_bytes, response_time_ms, risk_level, resource_count, error) "
        "VALUES (%s, %s, %s, %s, %s, %s)",
        (
            data.get("api_key_hash"),
            data.get("request_size_bytes"),
            data.get("response_time_ms"),
            data.get("risk_level"),
            data.get("resource_count"),
            data.get("error"),
        ),
    )


def _log_analysis(data: dict[str, Any]) -> None:
    metadata = data["metadata"]
    execute(
        "INSERT INTO analysis_logs (api_key_id, plan_hash, resources_total, resources_created, resources_updated, resources_destroyed, resources_replaced, max_risk_level, processing_time_ms, ai_tokens_used) "
        "VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s)",
        (
            data.get("api_key_id"),
            data.get("plan_hash"),
            metadata.get("resources_total"),
            metadata.get("resources_created"),
            metadata.get("resources_updated"),
            metadata.get("resources_destroyed"),
            metadata.get("resources_replaced"),
            data.get("max_risk_level"),
            data.get("processing_time_ms"),
            data.get("tokens_used"),
        ),
    )


@app.post("/api/analyze")
async def analyze(request: Request, api_key: dict[str, Any] = Depends(rate_limited_api_key)) -> dict[str, Any]:
    settings = get_settings()
    start = time()
    body = await request.body()

    try:
        plan_json = await request.json()
    except Exception as exc:  # noqa: BLE001
        _log_api_request({
            "api_key_hash": api_key.get("key_hash"),
            "request_size_bytes": len(body),
            "response_time_ms": int((time() - start) * 1000),
            "risk_level": None,
            "resource_count": None,
            "error": "INVALID_INPUT",
        })
        raise HTTPException(status_code=400, detail={"success": False, "error": "INVALID_INPUT", "message": "Request body must be JSON"}) from exc

    if not isinstance(plan_json, dict) or len(plan_json) == 0:
        _log_api_request({
            "api_key_hash": api_key.get("key_hash"),
            "request_size_bytes": len(body),
            "response_time_ms": int((time() - start) * 1000),
            "risk_level": None,
            "resource_count": None,
            "error": "INVALID_INPUT",
        })
        raise HTTPException(
            status_code=400,
            detail={
                "success": False,
                "error": "INVALID_INPUT",
                "message": "Request body must be a non-empty JSON object. Send: terraform show -json tfplan",
            },
        )

    try:
        parsed = parse_plan(plan_json)
    except PlanParseError as exc:
        _log_api_request({
            "api_key_hash": api_key.get("key_hash"),
            "request_size_bytes": len(body),
            "response_time_ms": int((time() - start) * 1000),
            "risk_level": None,
            "resource_count": None,
            "error": f"INVALID_PLAN: {exc}",
        })
        raise HTTPException(status_code=422, detail={"success": False, "error": "INVALID_PLAN", "message": str(exc)}) from exc

    if len(parsed.changes) == 0:
        processing_time = int((time() - start) * 1000)
        _log_api_request({
            "api_key_hash": api_key.get("key_hash"),
            "request_size_bytes": len(body),
            "response_time_ms": processing_time,
            "risk_level": "NONE",
            "resource_count": 0,
            "error": None,
        })
        return {
            "success": True,
            "analysis": {
                "summary": "No infrastructure changes detected. The plan is empty — your infrastructure matches the desired state.",
                "risk_flags": [],
                "reviewer_checklist": ["Confirm this is the expected result (no changes needed)"],
                "pr_markdown": "## Terraform Plan Analysis\n\n> No changes detected. Infrastructure is up to date.\n\n---\n"
                f"*Generated by [PlanPlain]({settings.website_base_url or 'https://plainplan.click'})*",
            },
            "metadata": parsed.metadata,
        }

    try:
        analysis = analyze_plan({"changes": parsed.changes, "risk_flags": parsed.risk_flags, "metadata": parsed.metadata})
    except RuntimeError:
        analysis = {
            "summary": f"This plan includes {parsed.metadata['resources_total']} change(s).",
            "risk_flags": parsed.risk_flags,
            "reviewer_checklist": [
                "Review all HIGH severity risk flags before approving",
                "Confirm this plan was generated from the correct branch/workspace",
            ],
            "pr_markdown": "## Terraform Plan Analysis\n\nAI unavailable. Falling back to heuristic analysis.",
            "_ai_metadata": {"processing_time_ms": 0, "tokens_used": 0, "fallback": True},
        }

    processing_time = int((time() - start) * 1000)
    risk_level = parsed.metadata.get("max_risk_level", "LOW")
    resource_count = parsed.metadata.get("resources_total", 0)

    plan_hash = hashlib.sha256(json.dumps(plan_json)[:10000].encode("utf-8")).hexdigest()[:16]

    _log_analysis({
        "api_key_id": api_key.get("id"),
        "plan_hash": plan_hash,
        "metadata": parsed.metadata,
        "max_risk_level": risk_level,
        "processing_time_ms": processing_time,
        "tokens_used": analysis.get("_ai_metadata", {}).get("tokens_used", 0),
    })

    _log_api_request({
        "api_key_hash": api_key.get("key_hash"),
        "request_size_bytes": len(body),
        "response_time_ms": processing_time,
        "risk_level": risk_level,
        "resource_count": resource_count,
        "error": None,
    })

    return {
        "success": True,
        "analysis": {
            "summary": analysis["summary"],
            "risk_flags": analysis["risk_flags"],
            "reviewer_checklist": analysis["reviewer_checklist"],
            "pr_markdown": analysis["pr_markdown"],
        },
        "metadata": {**parsed.metadata, "processing_time_ms": processing_time},
    }


@app.get("/api/stats")
def stats(authorization: str | None = Header(default=None)) -> dict[str, Any]:
    settings = get_settings()
    if not settings.stats_secret:
        raise HTTPException(status_code=503, detail={"success": False, "error": "Stats not configured"})

    token = (authorization or "").replace("Bearer ", "")
    if token != settings.stats_secret:
        raise HTTPException(status_code=401, detail={"success": False, "error": "Unauthorized"})

    row = fetch_one(
        "SELECT "
        "COUNT(*) FILTER (WHERE created_at > NOW() - INTERVAL '24 hours') AS requests_24h, "
        "COUNT(*) FILTER (WHERE created_at > NOW() - INTERVAL '7 days') AS requests_7d, "
        "COUNT(*) FILTER (WHERE created_at > NOW() - INTERVAL '30 days') AS requests_30d, "
        "COUNT(*) AS total_requests, "
        "COUNT(DISTINCT api_key_hash) FILTER (WHERE api_key_hash IS NOT NULL) AS unique_keys_total, "
        "ROUND(AVG(response_time_ms)) AS avg_response_time_ms, "
        "COUNT(*) FILTER (WHERE error IS NOT NULL) AS total_errors "
        "FROM api_requests"
    )

    return {
        "success": True,
        "stats": {
            "requests": {
                "last_24h": int(row["requests_24h"] or 0),
                "last_7d": int(row["requests_7d"] or 0),
                "last_30d": int(row["requests_30d"] or 0),
                "total": int(row["total_requests"] or 0),
            },
            "unique_api_keys": {"total": int(row["unique_keys_total"] or 0)},
            "performance": {"avg_response_time_ms": int(row["avg_response_time_ms"] or 0)},
            "errors": {"total": int(row["total_errors"] or 0)},
        },
    }


@app.get("/api/dashboard")
def dashboard_data(key: str = Query(default="")) -> dict[str, Any]:
    if not key.startswith("pp_live_"):
        raise HTTPException(status_code=401, detail={"success": False, "error": "INVALID_KEY", "message": "Provide your API key as ?key=pp_live_xxx"})

    key_hash = hash_key(key)
    key_row = fetch_one(
        "SELECT id, key_prefix, email, name, created_at, last_used_at, rate_limit_per_minute, rate_limit_per_day, is_active "
        "FROM api_keys WHERE key_hash = %s",
        (key_hash,),
    )

    if not key_row or not key_row["is_active"]:
        raise HTTPException(status_code=401, detail={"success": False, "error": "KEY_NOT_FOUND", "message": "API key not found or inactive"})

    usage = fetch_one(
        "SELECT COUNT(*) AS total, "
        "COUNT(*) FILTER (WHERE created_at >= NOW() - INTERVAL '24 hours') AS today, "
        "COUNT(*) FILTER (WHERE created_at >= NOW() - INTERVAL '7 days') AS week, "
        "COUNT(*) FILTER (WHERE created_at >= NOW() - INTERVAL '30 days') AS month, "
        "ROUND(AVG(response_time_ms)) AS avg_ms, "
        "ROUND(100.0 * COUNT(*) FILTER (WHERE error IS NOT NULL) / NULLIF(COUNT(*), 0), 1) AS error_rate "
        "FROM api_requests WHERE api_key_hash = %s",
        (key_hash,),
    )

    minute = fetch_one(
        "SELECT COUNT(*) AS cnt FROM api_requests WHERE api_key_hash = %s AND created_at >= NOW() - INTERVAL '1 minute'",
        (key_hash,),
    )

    recent = fetch_all(
        "SELECT created_at, risk_level, response_time_ms, resource_count, error "
        "FROM api_requests WHERE api_key_hash = %s ORDER BY created_at DESC LIMIT 10",
        (key_hash,),
    )

    daily_used = int(usage["today"] or 0)
    minute_used = int(minute["cnt"] or 0)
    day_limit = int(key_row["rate_limit_per_day"] or 200)
    minute_limit = int(key_row["rate_limit_per_minute"] or 10)

    return {
        "success": True,
        "key": {
            "prefix": key_row["key_prefix"],
            "email": key_row["email"],
            "name": key_row["name"],
            "created_at": key_row["created_at"],
            "last_used_at": key_row["last_used_at"],
        },
        "usage": {
            "today": daily_used,
            "week": int(usage["week"] or 0),
            "month": int(usage["month"] or 0),
            "total": int(usage["total"] or 0),
            "avg_response_ms": int(usage["avg_ms"] or 0),
            "error_rate": float(usage["error_rate"] or 0.0),
        },
        "rate_limits": {
            "per_minute": minute_limit,
            "per_day": day_limit,
            "used_minute": minute_used,
            "used_day": daily_used,
            "remaining_minute": max(minute_limit - minute_used, 0),
            "remaining_day": max(day_limit - daily_used, 0),
        },
        "recent_requests": [
            {
                "timestamp": r["created_at"],
                "risk_level": r["risk_level"],
                "response_time_ms": r["response_time_ms"],
                "resource_count": r["resource_count"],
                "status": "error" if r["error"] else "ok",
                "error": r["error"],
            }
            for r in recent
        ],
    }


@app.post("/analyze")
async def legacy_analyze(plan: dict[str, Any]) -> dict[str, Any]:
    """Website playground endpoint — no auth required, uses local parsing only."""
    settings = get_settings()
    if not isinstance(plan, dict):
        raise HTTPException(status_code=400, detail={"error": "Invalid request body"})

    try:
        parsed = parse_plan(plan)
    except PlanParseError as exc:
        raise HTTPException(status_code=400, detail={"error": str(exc)}) from exc

    risk_flags = [
        {"level": f.get("severity", "LOW"), "resource": f.get("resource", "unknown"), "reason": f.get("message", "")}
        for f in parsed.risk_flags
    ]

    checklist: list[str] = []
    if parsed.metadata["resources_destroyed"] > 0:
        checklist.append(f"Confirm {parsed.metadata['resources_destroyed']} resource(s) are safe to destroy")
    if parsed.metadata["resources_replaced"] > 0:
        checklist.append(f"Verify {parsed.metadata['resources_replaced']} replaced resource(s) will not cause downtime")
    if any(f["level"] == "HIGH" for f in risk_flags):
        checklist.append("Review all HIGH severity risk flags before approving")
    checklist.append("Confirm this plan was generated from the correct branch/workspace")

    md_lines = ["## Terraform Plan Analysis\n"]
    md_lines.append(f"**{parsed.metadata['resources_total']} change(s)** — "
                     f"+{parsed.metadata['resources_created']} create, "
                     f"~{parsed.metadata['resources_updated']} update, "
                     f"-{parsed.metadata['resources_destroyed']} destroy"
                     + (f", ↻{parsed.metadata['resources_replaced']} replace" if parsed.metadata['resources_replaced'] else ""))
    if risk_flags:
        md_lines.append(f"\n### Risk Flags ({len(risk_flags)})\n")
        for f in risk_flags:
            md_lines.append(f"- **{f['level']}** `{f['resource']}` — {f['reason']}")
    md_lines.append(f"\n---\n*Generated by [PlanPlain]({settings.website_base_url or 'https://plainplan.click'})*")

    return {
        "summary": {
            "total_changes": parsed.metadata["resources_total"],
            "to_add": parsed.metadata["resources_created"],
            "to_change": parsed.metadata["resources_updated"],
            "to_destroy": parsed.metadata["resources_destroyed"],
            "to_replace": parsed.metadata["resources_replaced"],
            "description": f"{parsed.metadata['resources_total']} resource(s) will be modified. "
                           f"Max risk level: {parsed.metadata.get('max_risk_level', 'LOW')}.",
        },
        "risk_flags": risk_flags,
        "reviewer_checklist": checklist,
        "markdown": "\n".join(md_lines),
    }


@app.exception_handler(HTTPException)
async def http_exception_handler(_: Request, exc: HTTPException) -> JSONResponse:
    if isinstance(exc.detail, dict):
        return JSONResponse(status_code=exc.status_code, content=exc.detail)
    return JSONResponse(status_code=exc.status_code, content={"success": False, "error": str(exc.detail)})


@app.exception_handler(Exception)
async def unhandled_exception_handler(_: Request, exc: Exception) -> JSONResponse:
    return JSONResponse(status_code=500, content={"success": False, "error": "INTERNAL_ERROR", "message": str(exc)})
