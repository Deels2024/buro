from datetime import UTC, datetime
from uuid import UUID

from pgvector.sqlalchemy import Vector
from sqlalchemy import (
    JSON,
    BigInteger,
    Boolean,
    DateTime,
    Float,
    ForeignKey,
    Index,
    Integer,
    String,
    Text,
    UniqueConstraint,
)
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base, TimestampMixin, UUIDPrimaryKeyMixin


class User(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "users"

    phone_hash: Mapped[str] = mapped_column(String(64), unique=True, index=True)
    phone_cipher: Mapped[str] = mapped_column(Text)
    display_name: Mapped[str] = mapped_column(String(120), default="Пользователь")
    role: Mapped[str] = mapped_column(String(24), default="user", index=True)
    status: Mapped[str] = mapped_column(String(24), default="active", index=True)
    verified_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    last_seen_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    admin_2fa_enabled: Mapped[bool] = mapped_column(Boolean, default=False)
    admin_totp_secret_cipher: Mapped[str | None] = mapped_column(Text)

    listings: Mapped[list["Listing"]] = relationship(back_populates="owner")


class RefreshToken(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "refresh_tokens"

    user_id: Mapped[UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    token_hash: Mapped[str] = mapped_column(String(64), unique=True, index=True)
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), index=True)
    revoked_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    device_name: Mapped[str | None] = mapped_column(String(120))
    mfa_verified: Mapped[bool] = mapped_column(Boolean, default=False)


class Organization(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "organizations"

    name: Mapped[str] = mapped_column(String(240), index=True)
    inn: Mapped[str] = mapped_column(String(12), unique=True, index=True)
    ogrn: Mapped[str | None] = mapped_column(String(15))
    status: Mapped[str] = mapped_column(String(24), default="pending", index=True)
    verification_data: Mapped[dict] = mapped_column(JSON, default=dict)
    api_enabled: Mapped[bool] = mapped_column(Boolean, default=False)


class OrganizationMember(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "organization_members"
    __table_args__ = (UniqueConstraint("organization_id", "user_id"),)

    organization_id: Mapped[UUID] = mapped_column(ForeignKey("organizations.id", ondelete="CASCADE"), index=True)
    user_id: Mapped[UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    role: Mapped[str] = mapped_column(String(24), default="operator")
    status: Mapped[str] = mapped_column(String(24), default="active")


class OrganizationApiKey(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "organization_api_keys"

    organization_id: Mapped[UUID] = mapped_column(ForeignKey("organizations.id", ondelete="CASCADE"), index=True)
    created_by: Mapped[UUID] = mapped_column(ForeignKey("users.id", ondelete="RESTRICT"))
    name: Mapped[str] = mapped_column(String(120))
    key_prefix: Mapped[str] = mapped_column(String(24), index=True)
    key_hash: Mapped[str] = mapped_column(String(64), unique=True, index=True)
    permissions: Mapped[list] = mapped_column(JSON, default=list)
    status: Mapped[str] = mapped_column(String(24), default="active", index=True)
    expires_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    last_used_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))


class BulkImportJob(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "bulk_import_jobs"

    organization_id: Mapped[UUID] = mapped_column(ForeignKey("organizations.id", ondelete="CASCADE"), index=True)
    created_by: Mapped[UUID] = mapped_column(ForeignKey("users.id", ondelete="RESTRICT"))
    status: Mapped[str] = mapped_column(String(24), default="processing", index=True)
    total_rows: Mapped[int] = mapped_column(Integer, default=0)
    processed_rows: Mapped[int] = mapped_column(Integer, default=0)
    errors: Mapped[list] = mapped_column(JSON, default=list)


class Branch(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "branches"

    organization_id: Mapped[UUID] = mapped_column(ForeignKey("organizations.id", ondelete="CASCADE"), index=True)
    name: Mapped[str] = mapped_column(String(180))
    public_address: Mapped[str] = mapped_column(String(320))
    location_cipher: Mapped[str | None] = mapped_column(Text)
    timezone: Mapped[str] = mapped_column(String(64), default="Europe/Moscow")
    active: Mapped[bool] = mapped_column(Boolean, default=True)


class Listing(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "listings"
    __table_args__ = (
        Index("ix_listings_search", "kind", "status", "category", "event_at"),
    )

    owner_id: Mapped[UUID] = mapped_column(ForeignKey("users.id", ondelete="RESTRICT"), index=True)
    organization_id: Mapped[UUID | None] = mapped_column(ForeignKey("organizations.id", ondelete="SET NULL"), index=True)
    branch_id: Mapped[UUID | None] = mapped_column(ForeignKey("branches.id", ondelete="SET NULL"), index=True)
    kind: Mapped[str] = mapped_column(String(16), index=True)  # lost | found
    status: Mapped[str] = mapped_column(String(24), default="draft", index=True)
    title: Mapped[str] = mapped_column(String(180))
    description: Mapped[str] = mapped_column(Text)
    category: Mapped[str] = mapped_column(String(80), index=True)
    tags: Mapped[list] = mapped_column(JSON, default=list)
    public_features: Mapped[list] = mapped_column(JSON, default=list)
    hidden_features_cipher: Mapped[str | None] = mapped_column(Text)
    event_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), index=True)
    public_region: Mapped[str] = mapped_column(String(180), index=True)
    approx_latitude: Mapped[float | None] = mapped_column(Float)
    approx_longitude: Mapped[float | None] = mapped_column(Float)
    exact_location_cipher: Mapped[str | None] = mapped_column(Text)
    storage_code: Mapped[str | None] = mapped_column(String(80), index=True)
    ai_status: Mapped[str] = mapped_column(String(24), default="pending")
    ai_confidence: Mapped[float | None] = mapped_column(Float)
    moderation_status: Mapped[str] = mapped_column(String(24), default="pending", index=True)
    published_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), index=True)
    closed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))

    owner: Mapped[User] = relationship(back_populates="listings")
    media: Mapped[list["MediaObject"]] = relationship(back_populates="listing", cascade="all, delete-orphan")


class MediaObject(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "media_objects"

    owner_id: Mapped[UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    listing_id: Mapped[UUID | None] = mapped_column(ForeignKey("listings.id", ondelete="CASCADE"), index=True)
    purpose: Mapped[str] = mapped_column(String(24), default="listing")
    object_key: Mapped[str] = mapped_column(String(512), unique=True)
    mime_type: Mapped[str] = mapped_column(String(120))
    size_bytes: Mapped[int] = mapped_column(BigInteger)
    sha256: Mapped[str] = mapped_column(String(64))
    width: Mapped[int | None] = mapped_column(Integer)
    height: Mapped[int | None] = mapped_column(Integer)
    duration_seconds: Mapped[float | None] = mapped_column(Float)
    status: Mapped[str] = mapped_column(String(24), default="uploaded", index=True)
    moderation_labels: Mapped[list] = mapped_column(JSON, default=list)
    embedding: Mapped[list[float] | None] = mapped_column(Vector(512))

    listing: Mapped[Listing | None] = relationship(back_populates="media")


class MatchCandidate(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "match_candidates"
    __table_args__ = (UniqueConstraint("source_listing_id", "candidate_listing_id"),)

    source_listing_id: Mapped[UUID] = mapped_column(ForeignKey("listings.id", ondelete="CASCADE"), index=True)
    candidate_listing_id: Mapped[UUID] = mapped_column(ForeignKey("listings.id", ondelete="CASCADE"), index=True)
    score: Mapped[float] = mapped_column(Float, index=True)
    factors: Mapped[dict] = mapped_column(JSON, default=dict)
    status: Mapped[str] = mapped_column(String(24), default="suggested", index=True)


class Claim(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "claims"
    __table_args__ = (UniqueConstraint("listing_id", "claimant_id"),)

    listing_id: Mapped[UUID] = mapped_column(ForeignKey("listings.id", ondelete="CASCADE"), index=True)
    claimant_id: Mapped[UUID] = mapped_column(ForeignKey("users.id", ondelete="RESTRICT"), index=True)
    match_id: Mapped[UUID | None] = mapped_column(ForeignKey("match_candidates.id", ondelete="SET NULL"))
    status: Mapped[str] = mapped_column(String(32), default="draft", index=True)
    answers_cipher: Mapped[str | None] = mapped_column(Text)
    risk_score: Mapped[float] = mapped_column(Float, default=0)
    risk_factors: Mapped[list] = mapped_column(JSON, default=list)
    decision_reason: Mapped[str | None] = mapped_column(Text)
    decided_by: Mapped[UUID | None] = mapped_column(ForeignKey("users.id", ondelete="SET NULL"))
    submitted_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    decided_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))


class ClaimEvidence(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "claim_evidence"

    claim_id: Mapped[UUID] = mapped_column(ForeignKey("claims.id", ondelete="CASCADE"), index=True)
    media_id: Mapped[UUID] = mapped_column(ForeignKey("media_objects.id", ondelete="CASCADE"))
    evidence_type: Mapped[str] = mapped_column(String(32))
    note_cipher: Mapped[str | None] = mapped_column(Text)


class Conversation(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "conversations"

    claim_id: Mapped[UUID] = mapped_column(ForeignKey("claims.id", ondelete="CASCADE"), unique=True, index=True)
    status: Mapped[str] = mapped_column(String(24), default="active")


class Message(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "messages"
    __table_args__ = (Index("ix_messages_conversation_created", "conversation_id", "created_at"),)

    conversation_id: Mapped[UUID] = mapped_column(ForeignKey("conversations.id", ondelete="CASCADE"), index=True)
    sender_id: Mapped[UUID] = mapped_column(ForeignKey("users.id", ondelete="RESTRICT"), index=True)
    body_cipher: Mapped[str] = mapped_column(Text)
    attachment_ids: Mapped[list] = mapped_column(JSON, default=list)
    system: Mapped[bool] = mapped_column(Boolean, default=False)
    read_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))


class ContactGrant(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "contact_grants"

    claim_id: Mapped[UUID] = mapped_column(ForeignKey("claims.id", ondelete="CASCADE"), unique=True, index=True)
    claimant_consent_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    holder_consent_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    revoked_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))


class Handover(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "handovers"

    claim_id: Mapped[UUID] = mapped_column(ForeignKey("claims.id", ondelete="CASCADE"), unique=True, index=True)
    method: Mapped[str] = mapped_column(String(24))
    place_cipher: Mapped[str | None] = mapped_column(Text)
    scheduled_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    qr_token_hash: Mapped[str] = mapped_column(String(64), unique=True, index=True)
    qr_expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    holder_confirmed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    claimant_confirmed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    completed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))


class Notification(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "notifications"

    user_id: Mapped[UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    kind: Mapped[str] = mapped_column(String(32), index=True)
    title: Mapped[str] = mapped_column(String(180))
    body: Mapped[str] = mapped_column(Text)
    data: Mapped[dict] = mapped_column(JSON, default=dict)
    read_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))


class SavedListing(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "saved_listings"
    __table_args__ = (UniqueConstraint("user_id", "listing_id"),)

    user_id: Mapped[UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    listing_id: Mapped[UUID] = mapped_column(ForeignKey("listings.id", ondelete="CASCADE"), index=True)


class ModerationCase(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "moderation_cases"

    entity_type: Mapped[str] = mapped_column(String(24), index=True)
    entity_id: Mapped[UUID] = mapped_column(index=True)
    reason: Mapped[str] = mapped_column(String(120), index=True)
    status: Mapped[str] = mapped_column(String(24), default="open", index=True)
    priority: Mapped[int] = mapped_column(Integer, default=50, index=True)
    assigned_to: Mapped[UUID | None] = mapped_column(ForeignKey("users.id", ondelete="SET NULL"))
    resolution: Mapped[str | None] = mapped_column(Text)


class AdCampaign(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "ad_campaigns"

    advertiser_name: Mapped[str] = mapped_column(String(180))
    title: Mapped[str] = mapped_column(String(180))
    body: Mapped[str] = mapped_column(String(320))
    action_label: Mapped[str] = mapped_column(String(60), default="Открыть")
    action_url: Mapped[str] = mapped_column(String(1000))
    placements: Mapped[list] = mapped_column(JSON, default=list)
    targeting: Mapped[dict] = mapped_column(JSON, default=dict)
    erid: Mapped[str] = mapped_column(String(120))
    age_rating: Mapped[str] = mapped_column(String(8), default="0+")
    starts_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), index=True)
    ends_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), index=True)
    daily_budget_kopecks: Mapped[int] = mapped_column(Integer)
    status: Mapped[str] = mapped_column(String(24), default="draft", index=True)


class AdEvent(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "ad_events"

    campaign_id: Mapped[UUID] = mapped_column(ForeignKey("ad_campaigns.id", ondelete="CASCADE"), index=True)
    event_type: Mapped[str] = mapped_column(String(16), index=True)
    placement: Mapped[str] = mapped_column(String(32), index=True)
    anonymous_id_hash: Mapped[str | None] = mapped_column(String(64))
    user_id: Mapped[UUID | None] = mapped_column(ForeignKey("users.id", ondelete="SET NULL"))
    context: Mapped[dict] = mapped_column(JSON, default=dict)


class AuditEvent(UUIDPrimaryKeyMixin, Base):
    __tablename__ = "audit_events"

    actor_id: Mapped[UUID | None] = mapped_column(ForeignKey("users.id", ondelete="SET NULL"), index=True)
    action: Mapped[str] = mapped_column(String(80), index=True)
    entity_type: Mapped[str] = mapped_column(String(40), index=True)
    entity_id: Mapped[UUID | None] = mapped_column(index=True)
    payload: Mapped[dict] = mapped_column(JSON, default=dict)
    ip_hash: Mapped[str | None] = mapped_column(String(64))
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=lambda: datetime.now(UTC), index=True
    )


class PushDevice(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "push_devices"
    __table_args__ = (UniqueConstraint("platform", "token_hash"),)

    user_id: Mapped[UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    platform: Mapped[str] = mapped_column(String(16), index=True)
    token_hash: Mapped[str] = mapped_column(String(64), index=True)
    token_cipher: Mapped[str] = mapped_column(Text)
    device_name: Mapped[str | None] = mapped_column(String(120))
    app_version: Mapped[str | None] = mapped_column(String(40))
    locale: Mapped[str] = mapped_column(String(16), default="ru")
    status: Mapped[str] = mapped_column(String(24), default="active", index=True)
    last_seen_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))


class SupportTicket(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "support_tickets"

    user_id: Mapped[UUID] = mapped_column(ForeignKey("users.id", ondelete="RESTRICT"), index=True)
    organization_id: Mapped[UUID | None] = mapped_column(
        ForeignKey("organizations.id", ondelete="SET NULL"), index=True
    )
    subject: Mapped[str] = mapped_column(String(180))
    category: Mapped[str] = mapped_column(String(40), index=True)
    priority: Mapped[str] = mapped_column(String(16), default="normal", index=True)
    status: Mapped[str] = mapped_column(String(24), default="open", index=True)
    assigned_to: Mapped[UUID | None] = mapped_column(ForeignKey("users.id", ondelete="SET NULL"), index=True)
    first_response_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    resolved_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))


class SupportMessage(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "support_messages"
    __table_args__ = (Index("ix_support_messages_ticket_created", "ticket_id", "created_at"),)

    ticket_id: Mapped[UUID] = mapped_column(ForeignKey("support_tickets.id", ondelete="CASCADE"), index=True)
    sender_id: Mapped[UUID] = mapped_column(ForeignKey("users.id", ondelete="RESTRICT"), index=True)
    body_cipher: Mapped[str] = mapped_column(Text)
    attachment_ids: Mapped[list] = mapped_column(JSON, default=list)
    internal: Mapped[bool] = mapped_column(Boolean, default=False)


class IntegrationWebhook(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "integration_webhooks"

    organization_id: Mapped[UUID] = mapped_column(
        ForeignKey("organizations.id", ondelete="CASCADE"), index=True
    )
    name: Mapped[str] = mapped_column(String(120))
    url: Mapped[str] = mapped_column(String(1000))
    secret_cipher: Mapped[str] = mapped_column(Text)
    events: Mapped[list] = mapped_column(JSON, default=list)
    status: Mapped[str] = mapped_column(String(24), default="active", index=True)
    last_success_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    last_failure_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    failure_count: Mapped[int] = mapped_column(Integer, default=0)


class WebhookDelivery(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "webhook_deliveries"

    webhook_id: Mapped[UUID] = mapped_column(
        ForeignKey("integration_webhooks.id", ondelete="CASCADE"), index=True
    )
    event_id: Mapped[UUID] = mapped_column(index=True)
    event_type: Mapped[str] = mapped_column(String(80), index=True)
    payload: Mapped[dict] = mapped_column(JSON, default=dict)
    status: Mapped[str] = mapped_column(String(24), default="pending", index=True)
    attempts: Mapped[int] = mapped_column(Integer, default=0)
    response_status: Mapped[int | None] = mapped_column(Integer)
    response_excerpt: Mapped[str | None] = mapped_column(String(500))
    next_attempt_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), index=True)
    delivered_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))


class SystemSetting(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "system_settings"

    key: Mapped[str] = mapped_column(String(120), unique=True, index=True)
    value: Mapped[dict] = mapped_column(JSON, default=dict)
    description: Mapped[str] = mapped_column(String(500), default="")
    public: Mapped[bool] = mapped_column(Boolean, default=False, index=True)
    updated_by: Mapped[UUID | None] = mapped_column(ForeignKey("users.id", ondelete="SET NULL"))
