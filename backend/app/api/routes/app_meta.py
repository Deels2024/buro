from fastapi import APIRouter
from sqlalchemy import select

from app.api.deps import DB
from app.core.config import settings
from app.db.models import SystemSetting

router = APIRouter()


DEFAULT_CATEGORIES = [
    {"code": "documents", "title": "Документы", "sensitive": True},
    {"code": "phones", "title": "Телефоны и электроника", "sensitive": True},
    {"code": "keys", "title": "Ключи", "sensitive": True},
    {"code": "bags", "title": "Сумки и рюкзаки", "sensitive": False},
    {"code": "clothes", "title": "Одежда", "sensitive": False},
    {"code": "jewelry", "title": "Украшения", "sensitive": True},
    {"code": "toys", "title": "Игрушки", "sensitive": False},
    {"code": "sport", "title": "Спорт", "sensitive": False},
    {"code": "other", "title": "Другое", "sensitive": False},
]


@router.get("/bootstrap")
async def bootstrap(db: DB) -> dict:
    public_rows = await db.scalars(
        select(SystemSetting).where(SystemSetting.public.is_(True)).order_by(SystemSetting.key)
    )
    public_settings = {row.key: row.value for row in public_rows}
    return {
        "api_version": "2.0",
        "base_url": settings.public_api_url,
        "minimum_versions": {
            "ios": settings.min_ios_version,
            "android": settings.min_android_version,
        },
        "features": {
            "ai_description": True,
            "photo_search": True,
            "voice_input": True,
            "secure_chat": True,
            "qr_handover": True,
            "delivery": False,
            "organization_api": True,
        },
        "limits": {
            "max_upload_bytes": settings.max_upload_bytes,
            "max_listing_media": 9,
            "max_evidence_media": 5,
        },
        "categories": DEFAULT_CATEGORIES,
        "support": {"email": settings.support_email, "in_app": True},
        "settings": public_settings,
    }
