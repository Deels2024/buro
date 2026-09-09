"""Release-time vision probe using a generated image, never user data."""
import asyncio
import base64
import io
import json
import re

from fastapi import HTTPException
from PIL import Image, ImageDraw

from app.core.config import settings
from app.services.ai import ai_service


async def main() -> None:
    if not settings.is_production or not ai_service.openai_configured:
        print(json.dumps({"openai_vision": "skipped", "reason": "no_production_key"}))
        return
    proxy = "configured" if settings.openai_proxy_address.strip() else "direct"
    picture = Image.new("RGB", (128, 128), "white")
    ImageDraw.Draw(picture).rectangle((24, 24, 104, 104), fill="red")
    buffer = io.BytesIO()
    picture.save(buffer, format="PNG")
    image_url = "data:image/png;base64," + base64.b64encode(buffer.getvalue()).decode("ascii")
    try:
        result = await ai_service.describe_item(
            image_url, "found", "Проверка соединения: опиши только видимую геометрическую фигуру.",
        )
        if not result.title.strip() or not result.description.strip():
            raise HTTPException(502, "[AI_EMPTY]")
        print(json.dumps({"openai_vision": "ok", "openai_proxy": proxy, "model": settings.openai_model}))
    except HTTPException as exc:
        match = re.search(r"\[AI_[A-Z_]+\]", str(exc.detail))
        print(json.dumps({"openai_vision": "failed", "openai_proxy": proxy,
                          "reason": match.group(0) if match else "AI_ERROR"}))
        raise SystemExit(1) from None
    except Exception:
        print(json.dumps({"openai_vision": "failed", "openai_proxy": proxy, "reason": "AI_PROBE_ERROR"}))
        raise SystemExit(1) from None
    finally:
        await ai_service.close()


if __name__ == "__main__":
    asyncio.run(main())
