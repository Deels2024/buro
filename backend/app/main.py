import asyncio
import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.api.public_site import router as public_router
from app.api.router import api_router
from app.core.config import settings
from app.middleware import IdempotencyMiddleware, RequestContextMiddleware
from app.services.ai import ai_service
from app.services.cache import redis
from app.services.storage import storage

logging.basicConfig(
    level=getattr(logging, settings.log_level.upper(), logging.INFO),
    format="%(asctime)s %(levelname)s %(name)s %(message)s",
)


@asynccontextmanager
async def lifespan(_: FastAPI):
    if not settings.is_production:
        try:
            await asyncio.to_thread(storage.ensure_bucket)
        except Exception:
            logging.getLogger(__name__).exception("Object storage is not ready")
    yield
    await ai_service.close()
    await redis.aclose()


app = FastAPI(
    title="Бюро находок API",
    description="API единой поисковой сети пропаж и находок России",
    version="0.2.0",
    docs_url="/docs" if not settings.is_production else None,
    redoc_url="/redoc" if not settings.is_production else None,
    openapi_url="/openapi.json",
    lifespan=lifespan,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origins,
    allow_credentials=True,
    allow_methods=["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"],
    allow_headers=["Authorization", "Content-Type", "Idempotency-Key", "X-Request-ID"],
)
app.add_middleware(IdempotencyMiddleware)
app.add_middleware(RequestContextMiddleware)
app.include_router(api_router, prefix="/v1")

app.include_router(public_router)
