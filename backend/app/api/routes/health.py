from fastapi import APIRouter, HTTPException
from sqlalchemy import text

from app.api.deps import DB
from app.core.config import settings
from app.services.ai import ai_service
from app.services.cache import redis

router = APIRouter(tags=["health"])


@router.get("/health/live")
async def live() -> dict[str, str]:
    return {"status": "ok", "version": "0.2.0"}


@router.get("/health/ready")
async def ready(db: DB) -> dict[str, str]:
    try:
        await db.execute(text("SELECT 1"))
        await redis.ping()
    except Exception as exc:
        raise HTTPException(status_code=503, detail="Dependencies unavailable") from exc
    return {
        "status": "ready",
        "database": "ok",
        "redis": "ok",
        "openai": "configured" if ai_service.openai_configured else "fallback",
        "openai_model": settings.openai_model,
        "version": "0.2.0",
        "release_sha": settings.release_sha,
        "sms": "configured" if settings.smsc_is_configured else "development",
        "storage_transport": "https" if settings.s3_public_endpoint.startswith("https://") else "http",
        "worker": "ok" if (await redis.get("bureau:worker:heartbeat") or "").startswith(settings.release_sha + ":") else "unavailable",
    }
