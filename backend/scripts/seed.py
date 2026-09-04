import asyncio
from datetime import UTC, datetime, timedelta

from sqlalchemy import select

from app.core.config import settings
from app.core.security import encrypt_json, normalize_phone, phone_lookup_hash
from app.db.models import (
    AdCampaign,
    Claim,
    Conversation,
    Listing,
    MatchCandidate,
    Organization,
    OrganizationMember,
    SupportMessage,
    SupportTicket,
    SystemSetting,
    User,
)
from app.db.session import SessionLocal


async def seed_settings(db) -> None:
    defaults = {
        "search.radius_km": ({"value": 50}, "Радиус поиска по умолчанию", True),
        "matching.minimum_score": ({"value": 45}, "Минимальный ИИ-рейтинг совпадения", False),
        "support.sla_hours": ({"normal": 24, "urgent": 2}, "SLA поддержки", False),
        "storage.default_days": ({"value": 90}, "Срок хранения по умолчанию", True),
    }
    for key, (value, description, public) in defaults.items():
        existing = await db.scalar(select(SystemSetting).where(SystemSetting.key == key))
        if not existing:
            db.add(SystemSetting(key=key, value=value, description=description, public=public))


async def seed_ad(db) -> None:
    existing = await db.scalar(select(AdCampaign).where(AdCampaign.erid == "DEMO-ERID-NOT-FOR-PROD"))
    if not existing:
        db.add(
            AdCampaign(
                advertiser_name="SafePoint Demo",
                title="Безопасная точка передачи рядом",
                body="Партнёрский пункт хранения и передачи вещей.",
                action_label="Открыть карту",
                action_url="https://example.org/safepoint",
                placements=["home_feed", "search_results"],
                targeting={"regions": ["Санкт-Петербург"]},
                erid="DEMO-ERID-NOT-FOR-PROD",
                age_rating="0+",
                starts_at=datetime.now(UTC),
                ends_at=datetime.now(UTC) + timedelta(days=30),
                daily_budget_kopecks=100_000,
                status="active",
            )
        )


async def seed_demo_operations(db) -> None:
    phone = normalize_phone(settings.bootstrap_admin_phone)
    admin = await db.scalar(select(User).where(User.phone_hash == phone_lookup_hash(phone)))
    if not admin:
        admin = User(
            phone_hash=phone_lookup_hash(phone),
            phone_cipher=encrypt_json({"phone": phone}),
            display_name="Администратор пилота",
            role="admin",
            status="active",
            verified_at=datetime.now(UTC),
        )
        db.add(admin)
        await db.flush()

    if settings.is_production or not settings.seed_demo_data:
        return

    organization = await db.scalar(select(Organization).where(Organization.inn == "7800000000"))
    if not organization:
        organization = Organization(
            name="Демо ТЦ · Санкт-Петербург",
            inn="7800000000",
            ogrn="1027800000000",
            status="verified",
            verification_data={"seed": True},
            api_enabled=True,
        )
        db.add(organization)
        await db.flush()
    membership = await db.scalar(
        select(OrganizationMember).where(
            OrganizationMember.organization_id == organization.id,
            OrganizationMember.user_id == admin.id,
        )
    )
    if not membership:
        db.add(
            OrganizationMember(
                organization_id=organization.id,
                user_id=admin.id,
                role="owner",
                status="active",
            )
        )

    existing_listing = await db.scalar(
        select(Listing).where(
            Listing.organization_id == organization.id,
            Listing.storage_code == "DEMO-A-104",
        )
    )
    if existing_listing:
        return

    found = Listing(
        owner_id=admin.id,
        organization_id=organization.id,
        kind="found",
        status="active",
        title="Чёрный рюкзак с красной молнией",
        description="Найден рядом с фудкортом, внутри спортивная форма.",
        category="bags",
        tags=["рюкзак", "чёрный", "красная молния"],
        public_features=["красная молния"],
        hidden_features_cipher=encrypt_json(["инициалы на внутренней бирке"]),
        event_at=datetime.now(UTC) - timedelta(hours=8),
        public_region="Санкт-Петербург",
        approx_latitude=59.93,
        approx_longitude=30.32,
        exact_location_cipher=encrypt_json({"region": "Санкт-Петербург", "exact_address": "демо"}),
        storage_code="DEMO-A-104",
        moderation_status="approved",
        ai_status="ready",
        ai_confidence=0.94,
        published_at=datetime.now(UTC) - timedelta(hours=7),
    )
    lost = Listing(
        owner_id=admin.id,
        kind="lost",
        status="active",
        title="Рюкзак с красной молнией",
        description="Оставлен по пути через торговый центр, внутри была синяя форма.",
        category="bags",
        tags=["рюкзак", "чёрный", "красная молния"],
        public_features=["красная молния"],
        hidden_features_cipher=encrypt_json(["инициалы на внутренней бирке"]),
        event_at=datetime.now(UTC) - timedelta(hours=9),
        public_region="Санкт-Петербург",
        approx_latitude=59.94,
        approx_longitude=30.31,
        exact_location_cipher=encrypt_json({"region": "Санкт-Петербург"}),
        moderation_status="approved",
        ai_status="ready",
        ai_confidence=0.91,
        published_at=datetime.now(UTC) - timedelta(hours=8),
    )
    db.add_all([found, lost])
    await db.flush()
    match = MatchCandidate(
        source_listing_id=lost.id,
        candidate_listing_id=found.id,
        score=93.4,
        factors={"visual": 0.95, "tags": 1.0, "date": 0.96, "location": 0.9, "category": 1.0},
    )
    db.add(match)
    await db.flush()
    claim = Claim(
        listing_id=found.id,
        claimant_id=admin.id,
        match_id=match.id,
        status="under_review",
        answers_cipher=encrypt_json({"hidden_feature": "инициалы"}),
        risk_score=0.18,
        risk_factors=[],
        submitted_at=datetime.now(UTC) - timedelta(hours=1),
    )
    db.add(claim)
    await db.flush()
    db.add(Conversation(claim_id=claim.id))
    ticket = SupportTicket(
        user_id=admin.id,
        organization_id=organization.id,
        subject="Проверка демо-очереди поддержки",
        category="technical",
        priority="normal",
    )
    db.add(ticket)
    await db.flush()
    db.add(
        SupportMessage(
            ticket_id=ticket.id,
            sender_id=admin.id,
            body_cipher=encrypt_json({"body": "Это демонстрационное обращение для проверки админки."}),
            attachment_ids=[],
        )
    )


async def seed() -> None:
    async with SessionLocal() as db:
        await seed_settings(db)
        if not settings.is_production and settings.seed_demo_data:
            await seed_ad(db)
        await seed_demo_operations(db)
        await db.commit()
    print("Initial settings and administrator are ready; demo data is opt-in outside production")


if __name__ == "__main__":
    asyncio.run(seed())
