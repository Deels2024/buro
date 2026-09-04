from datetime import UTC, datetime, timedelta
from uuid import UUID

from fastapi import APIRouter, HTTPException, Query
from sqlalchemy import func, select
from sqlalchemy.orm import selectinload

from app.api.deps import DB, CurrentUser, OrganizationKey
from app.core.security import encrypt_json, hash_secret, normalize_phone, phone_lookup_hash, random_token
from app.db.models import (
    Branch,
    BulkImportJob,
    Claim,
    IntegrationWebhook,
    Listing,
    Organization,
    OrganizationApiKey,
    OrganizationMember,
    User,
    WebhookDelivery,
)
from app.schemas import (
    BranchCreate,
    BulkImportRequest,
    ClaimOut,
    CSVImportRequest,
    InviteMember,
    ListingOut,
    OrganizationApiKeyCreate,
    OrganizationApiKeyOut,
    OrganizationCreate,
    OrganizationDashboard,
    OrganizationOut,
    OrganizationSettingsUpdate,
    WebhookCreate,
    WebhookOut,
)
from app.services.cache import enqueue
from app.services.categories import normalize_category
from app.services.csv_import import parse_inventory_csv
from app.services.serializers import listing_out
from app.services.webhooks import validate_webhook_url

router = APIRouter()


async def _membership(db: DB, organization_id: UUID, user_id: UUID) -> OrganizationMember:
    member = await db.scalar(
        select(OrganizationMember).where(
            OrganizationMember.organization_id == organization_id,
            OrganizationMember.user_id == user_id,
            OrganizationMember.status == "active",
        )
    )
    if not member:
        raise HTTPException(status_code=403, detail="Нет доступа к организации")
    return member


async def _manager(db: DB, organization_id: UUID, user_id: UUID) -> OrganizationMember:
    member = await _membership(db, organization_id, user_id)
    if member.role not in {"owner", "manager"}:
        raise HTTPException(status_code=403, detail="Нужна роль руководителя")
    return member


@router.post("", response_model=OrganizationOut, status_code=201)
async def create_organization(payload: OrganizationCreate, db: DB, user: CurrentUser) -> Organization:
    existing = await db.scalar(select(Organization).where(Organization.inn == payload.inn))
    if existing:
        raise HTTPException(status_code=409, detail="Организация с таким ИНН уже зарегистрирована")
    organization = Organization(
        name=payload.name.strip(),
        inn=payload.inn,
        ogrn=payload.ogrn,
        verification_data={"submitted_by": str(user.id), "submitted_at": datetime.now(UTC).isoformat()},
    )
    db.add(organization)
    await db.flush()
    db.add(OrganizationMember(organization_id=organization.id, user_id=user.id, role="owner"))
    await db.commit()
    await db.refresh(organization)
    return organization


@router.get("/mine", response_model=list[OrganizationOut])
async def my_organizations(db: DB, user: CurrentUser) -> list[Organization]:
    result = await db.scalars(
        select(Organization)
        .join(OrganizationMember, OrganizationMember.organization_id == Organization.id)
        .where(OrganizationMember.user_id == user.id, OrganizationMember.status == "active")
        .order_by(Organization.name)
    )
    return list(result)


@router.get("/{organization_id}", response_model=OrganizationOut)
async def get_organization(organization_id: UUID, db: DB, user: CurrentUser) -> Organization:
    await _membership(db, organization_id, user.id)
    organization = await db.get(Organization, organization_id)
    if not organization:
        raise HTTPException(status_code=404, detail="Организация не найдена")
    return organization


@router.get("/{organization_id}/dashboard", response_model=OrganizationDashboard)
async def dashboard(organization_id: UUID, db: DB, user: CurrentUser) -> OrganizationDashboard:
    await _membership(db, organization_id, user.id)
    active_inventory = await db.scalar(
        select(func.count(Listing.id)).where(
            Listing.organization_id == organization_id,
            Listing.status == "active",
            Listing.kind == "found",
        )
    )
    open_claims = await db.scalar(
        select(func.count(Claim.id))
        .join(Listing, Listing.id == Claim.listing_id)
        .where(
            Listing.organization_id == organization_id,
            Claim.status.in_(["under_review", "needs_more_info"]),
        )
    )
    returned = await db.scalar(
        select(func.count(Listing.id)).where(
            Listing.organization_id == organization_id,
            Listing.status == "closed",
            Listing.closed_at >= datetime.now(UTC) - timedelta(days=30),
        )
    )
    return OrganizationDashboard(
        active_inventory=active_inventory or 0,
        open_claims=open_claims or 0,
        returned_30d=returned or 0,
        median_return_hours=None,
    )


@router.get("/{organization_id}/inventory", response_model=list[ListingOut])
async def inventory(
    organization_id: UUID,
    db: DB,
    user: CurrentUser,
    status: str | None = Query(default=None, max_length=24),
    limit: int = Query(default=50, ge=1, le=100),
) -> list[ListingOut]:
    await _membership(db, organization_id, user.id)
    filters = [Listing.organization_id == organization_id]
    if status:
        filters.append(Listing.status == status)
    result = await db.scalars(
        select(Listing)
        .where(*filters)
        .options(selectinload(Listing.media))
        .order_by(Listing.created_at.desc())
        .limit(limit)
    )
    return [listing_out(item) for item in result]


@router.get("/{organization_id}/claims", response_model=list[ClaimOut])
async def organization_claims(
    organization_id: UUID,
    db: DB,
    user: CurrentUser,
    limit: int = Query(default=50, ge=1, le=100),
) -> list[Claim]:
    await _membership(db, organization_id, user.id)
    result = await db.scalars(
        select(Claim)
        .join(Listing, Listing.id == Claim.listing_id)
        .where(Listing.organization_id == organization_id)
        .order_by(Claim.created_at.desc())
        .limit(limit)
    )
    return list(result)


@router.post("/{organization_id}/branches", status_code=201)
async def create_branch(
    payload: BranchCreate,
    organization_id: UUID,
    db: DB,
    user: CurrentUser,
) -> dict:
    await _manager(db, organization_id, user.id)
    branch = Branch(
        organization_id=organization_id,
        name=payload.name,
        public_address=payload.public_address,
        location_cipher=encrypt_json(payload.exact_location.model_dump(mode="json")) if payload.exact_location else None,
        timezone=payload.timezone,
    )
    db.add(branch)
    await db.commit()
    await db.refresh(branch)
    return {"id": str(branch.id), "name": branch.name, "public_address": branch.public_address}


@router.get("/{organization_id}/branches")
async def branches(organization_id: UUID, db: DB, user: CurrentUser) -> list[dict]:
    await _membership(db, organization_id, user.id)
    result = await db.scalars(
        select(Branch)
        .where(Branch.organization_id == organization_id)
        .order_by(Branch.active.desc(), Branch.name)
    )
    return [
        {
            "id": str(branch.id),
            "name": branch.name,
            "public_address": branch.public_address,
            "timezone": branch.timezone,
            "active": branch.active,
        }
        for branch in result
    ]


@router.get("/{organization_id}/team")
async def team(organization_id: UUID, db: DB, user: CurrentUser) -> list[dict]:
    await _membership(db, organization_id, user.id)
    rows = await db.execute(
        select(OrganizationMember, User)
        .join(User, User.id == OrganizationMember.user_id)
        .where(OrganizationMember.organization_id == organization_id)
        .order_by(OrganizationMember.created_at)
    )
    return [
        {
            "id": str(member.id),
            "user_id": str(member.user_id),
            "display_name": account.display_name,
            "role": member.role,
            "status": member.status,
        }
        for member, account in rows.all()
    ]


@router.post("/{organization_id}/team/invite", status_code=201)
async def invite_member(
    payload: InviteMember,
    organization_id: UUID,
    db: DB,
    user: CurrentUser,
) -> dict[str, str]:
    await _manager(db, organization_id, user.id)
    try:
        phone = normalize_phone(payload.phone)
    except ValueError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc
    phone_hash = phone_lookup_hash(phone)
    account = await db.scalar(select(User).where(User.phone_hash == phone_hash))
    if not account:
        account = User(
            phone_hash=phone_hash,
            phone_cipher=encrypt_json({"phone": phone}),
            display_name="Приглашённый сотрудник",
            status="invited",
        )
        db.add(account)
        await db.flush()
    existing = await db.scalar(
        select(OrganizationMember).where(
            OrganizationMember.organization_id == organization_id,
            OrganizationMember.user_id == account.id,
        )
    )
    if existing:
        existing.role = payload.role
        existing.status = "active"
    else:
        db.add(
            OrganizationMember(
                organization_id=organization_id,
                user_id=account.id,
                role=payload.role,
                status="active",
            )
        )
    await db.commit()
    return {"status": "invited", "user_id": str(account.id)}


@router.post("/{organization_id}/bulk-import", status_code=201)
async def bulk_import(
    payload: BulkImportRequest,
    organization_id: UUID,
    db: DB,
    user: CurrentUser,
) -> dict:
    member = await _membership(db, organization_id, user.id)
    if member.role not in {"owner", "manager", "operator"}:
        raise HTTPException(status_code=403, detail="Нет права на импорт")
    job = BulkImportJob(
        organization_id=organization_id,
        created_by=user.id,
        total_rows=len(payload.items),
    )
    db.add(job)
    await db.flush()
    errors: list[dict] = []
    processed = 0
    for index, item in enumerate(payload.items, start=1):
        if item.branch_id:
            branch = await db.get(Branch, item.branch_id)
            if not branch or branch.organization_id != organization_id:
                errors.append({"row": index, "error": "Филиал не принадлежит организации"})
                continue
        db.add(
            Listing(
                owner_id=user.id,
                organization_id=organization_id,
                branch_id=item.branch_id,
                kind="found",
                status="draft",
                title=item.title,
                description=item.description,
                category=normalize_category(item.category),
                tags=item.tags,
                public_features=[],
                event_at=item.event_at,
                public_region=item.region,
                exact_location_cipher=encrypt_json({"region": item.region}),
                storage_code=item.storage_code,
                moderation_status="pending",
            )
        )
        processed += 1
    job.processed_rows = processed
    job.errors = errors[:100]
    job.status = "completed_with_errors" if errors else "completed"
    await db.commit()
    return {
        "job_id": str(job.id),
        "status": job.status,
        "total": job.total_rows,
        "processed": job.processed_rows,
        "errors": job.errors,
    }


@router.post("/{organization_id}/external/inventory", status_code=201)
async def external_inventory_import(
    payload: BulkImportRequest,
    organization_id: UUID,
    db: DB,
    key: OrganizationKey,
) -> dict:
    if key.organization_id != organization_id or "inventory:write" not in key.permissions:
        raise HTTPException(status_code=403, detail="Ключ не имеет права на импорт")
    creator = await db.get(User, key.created_by)
    if not creator:
        raise HTTPException(status_code=403, detail="Создатель ключа недоступен")
    return await bulk_import(payload, organization_id, db, creator)


@router.get("/{organization_id}/analytics")
async def analytics(organization_id: UUID, db: DB, user: CurrentUser) -> dict:
    await _membership(db, organization_id, user.id)
    category_rows = await db.execute(
        select(Listing.category, func.count(Listing.id))
        .where(Listing.organization_id == organization_id)
        .group_by(Listing.category)
        .order_by(func.count(Listing.id).desc())
        .limit(20)
    )
    returned_90d = await db.scalar(
        select(func.count(Listing.id)).where(
            Listing.organization_id == organization_id,
            Listing.closed_at >= datetime.now(UTC) - timedelta(days=90),
        )
    )
    total_90d = await db.scalar(
        select(func.count(Listing.id)).where(
            Listing.organization_id == organization_id,
            Listing.created_at >= datetime.now(UTC) - timedelta(days=90),
        )
    )
    return {
        "period_days": 90,
        "registered": total_90d or 0,
        "returned": returned_90d or 0,
        "return_rate": round((returned_90d or 0) / (total_90d or 1) * 100, 2),
        "categories": [{"category": category, "count": count} for category, count in category_rows.all()],
    }


@router.patch("/{organization_id}/settings", response_model=OrganizationOut)
async def update_settings(
    payload: OrganizationSettingsUpdate,
    organization_id: UUID,
    db: DB,
    user: CurrentUser,
) -> Organization:
    await _manager(db, organization_id, user.id)
    organization = await db.get(Organization, organization_id)
    if not organization:
        raise HTTPException(status_code=404, detail="Организация не найдена")
    if payload.api_enabled and organization.status != "verified":
        raise HTTPException(status_code=409, detail="API доступен после проверки организации")
    organization.api_enabled = payload.api_enabled
    await db.commit()
    await db.refresh(organization)
    return organization


@router.get("/{organization_id}/api-keys", response_model=list[OrganizationApiKeyOut])
async def api_keys(organization_id: UUID, db: DB, user: CurrentUser) -> list[OrganizationApiKeyOut]:
    await _manager(db, organization_id, user.id)
    result = await db.scalars(
        select(OrganizationApiKey)
        .where(OrganizationApiKey.organization_id == organization_id)
        .order_by(OrganizationApiKey.created_at.desc())
    )
    return [OrganizationApiKeyOut.model_validate(item) for item in result]


@router.post("/{organization_id}/api-keys", response_model=OrganizationApiKeyOut, status_code=201)
async def create_api_key(
    payload: OrganizationApiKeyCreate,
    organization_id: UUID,
    db: DB,
    user: CurrentUser,
) -> OrganizationApiKeyOut:
    await _manager(db, organization_id, user.id)
    organization = await db.get(Organization, organization_id)
    if not organization or organization.status != "verified" or not organization.api_enabled:
        raise HTTPException(status_code=409, detail="Сначала подтвердите организацию и включите API")
    secret = f"bn_live_{random_token(32)}"
    key = OrganizationApiKey(
        organization_id=organization_id,
        created_by=user.id,
        name=payload.name,
        key_prefix=secret[:20],
        key_hash=hash_secret(secret),
        permissions=payload.permissions,
        expires_at=payload.expires_at,
    )
    db.add(key)
    await db.commit()
    await db.refresh(key)
    output = OrganizationApiKeyOut.model_validate(key)
    return output.model_copy(update={"api_key": secret})


@router.delete("/{organization_id}/api-keys/{key_id}", status_code=204)
async def revoke_api_key(
    organization_id: UUID,
    key_id: UUID,
    db: DB,
    user: CurrentUser,
) -> None:
    await _manager(db, organization_id, user.id)
    key = await db.get(OrganizationApiKey, key_id)
    if not key or key.organization_id != organization_id:
        raise HTTPException(status_code=404, detail="Ключ не найден")
    key.status = "revoked"
    await db.commit()


@router.get("/{organization_id}/webhooks", response_model=list[WebhookOut])
async def webhooks(organization_id: UUID, db: DB, user: CurrentUser) -> list[IntegrationWebhook]:
    await _manager(db, organization_id, user.id)
    result = await db.scalars(
        select(IntegrationWebhook)
        .where(IntegrationWebhook.organization_id == organization_id)
        .order_by(IntegrationWebhook.created_at.desc())
    )
    return list(result)


@router.post("/{organization_id}/webhooks", response_model=WebhookOut, status_code=201)
async def create_webhook(
    organization_id: UUID,
    payload: WebhookCreate,
    db: DB,
    user: CurrentUser,
) -> WebhookOut:
    await _manager(db, organization_id, user.id)
    try:
        validate_webhook_url(str(payload.url))
    except ValueError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc
    raw_secret = random_token(32)
    webhook = IntegrationWebhook(
        organization_id=organization_id,
        name=payload.name.strip(),
        url=str(payload.url),
        secret_cipher=encrypt_json({"secret": raw_secret}),
        events=list(dict.fromkeys(payload.events)),
    )
    db.add(webhook)
    await db.commit()
    await db.refresh(webhook)
    output = WebhookOut.model_validate(webhook)
    output.signing_secret = raw_secret
    return output


@router.delete("/{organization_id}/webhooks/{webhook_id}", status_code=204)
async def delete_webhook(
    organization_id: UUID,
    webhook_id: UUID,
    db: DB,
    user: CurrentUser,
) -> None:
    await _manager(db, organization_id, user.id)
    webhook = await db.get(IntegrationWebhook, webhook_id)
    if webhook and webhook.organization_id == organization_id:
        await db.delete(webhook)
        await db.commit()


@router.post("/{organization_id}/webhooks/{webhook_id}/test", status_code=202)
async def test_webhook(
    organization_id: UUID,
    webhook_id: UUID,
    db: DB,
    user: CurrentUser,
) -> dict[str, str]:
    await _manager(db, organization_id, user.id)
    webhook = await db.get(IntegrationWebhook, webhook_id)
    if not webhook or webhook.organization_id != organization_id:
        raise HTTPException(status_code=404, detail="Вебхук не найден")
    event_type = webhook.events[0] if webhook.events else "listing.created"
    delivery = WebhookDelivery(
        webhook_id=webhook.id,
        event_id=webhook.id,
        event_type=event_type,
        payload={
            "id": str(webhook.id),
            "type": event_type,
            "test": True,
            "data": {"organization_id": str(organization_id)},
        },
    )
    db.add(delivery)
    await db.commit()
    await enqueue("deliver_webhook", {"delivery_id": str(delivery.id)})
    return {"status": "queued", "delivery_id": str(delivery.id)}


@router.get("/{organization_id}/webhook-deliveries")
async def webhook_deliveries(
    organization_id: UUID,
    db: DB,
    user: CurrentUser,
    limit: int = Query(50, ge=1, le=100),
) -> list[dict]:
    await _manager(db, organization_id, user.id)
    result = await db.execute(
        select(WebhookDelivery, IntegrationWebhook.name)
        .join(IntegrationWebhook, IntegrationWebhook.id == WebhookDelivery.webhook_id)
        .where(IntegrationWebhook.organization_id == organization_id)
        .order_by(WebhookDelivery.created_at.desc())
        .limit(limit)
    )
    return [
        {
            "id": str(delivery.id),
            "webhook_name": name,
            "event_type": delivery.event_type,
            "status": delivery.status,
            "attempts": delivery.attempts,
            "response_status": delivery.response_status,
            "created_at": delivery.created_at,
            "delivered_at": delivery.delivered_at,
        }
        for delivery, name in result.all()
    ]


@router.post("/{organization_id}/bulk-import-csv", status_code=201)
async def import_csv(payload: CSVImportRequest, organization_id: UUID, db: DB, user: CurrentUser) -> dict:
    await _membership(db, organization_id, user.id)
    return await bulk_import(BulkImportRequest(items=parse_inventory_csv(payload.csv)), organization_id, db, user)
