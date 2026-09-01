from fastapi import APIRouter

from app.api.routes import (
    admin,
    admin_console,
    ads,
    app_meta,
    auth,
    chat,
    claims,
    health,
    internal_deployment,
    listings,
    media,
    organizations,
    support,
    users,
)

api_router = APIRouter()
api_router.include_router(health.router)
api_router.include_router(internal_deployment.router, prefix="/internal/deployment")
api_router.include_router(app_meta.router, prefix="/app", tags=["app"])
api_router.include_router(auth.router, prefix="/auth", tags=["auth"])
api_router.include_router(users.router, prefix="/users", tags=["users"])
api_router.include_router(media.router, prefix="/media", tags=["media"])
api_router.include_router(listings.router, prefix="/listings", tags=["listings"])
api_router.include_router(claims.router, prefix="/claims", tags=["claims"])
api_router.include_router(chat.router, prefix="/chat", tags=["chat"])
api_router.include_router(organizations.router, prefix="/organizations", tags=["organizations"])
api_router.include_router(ads.router, prefix="/ads", tags=["ads"])
api_router.include_router(admin.router, prefix="/admin", tags=["admin"])
api_router.include_router(admin_console.router, prefix="/admin", tags=["admin-console"])
api_router.include_router(support.router, prefix="/support", tags=["support"])
api_router.include_router(support.admin_router, prefix="/admin/support", tags=["admin-support"])
