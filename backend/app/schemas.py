from datetime import datetime
from typing import Literal
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, HttpUrl, field_validator

from app.services.categories import normalize_category


class APIModel(BaseModel):
    model_config = ConfigDict(from_attributes=True)


class MessageResponse(APIModel):
    message: str


class PhoneCodeRequest(APIModel):
    phone: str


class PhoneCodeRequested(APIModel):
    expires_in: int
    retry_after: int
    dev_code: str | None = None


class PhoneCodeVerify(APIModel):
    phone: str
    code: str = Field(pattern=r"^\d{6}$")
    device_name: str | None = Field(default=None, max_length=120)


class RefreshRequest(APIModel):
    refresh_token: str
    device_name: str | None = Field(default=None, max_length=120)


class TokenPair(APIModel):
    access_token: str
    refresh_token: str
    token_type: Literal["bearer"] = "bearer"
    expires_in: int


class MFARequired(APIModel):
    mfa_required: Literal[True] = True
    mfa_ticket: str
    expires_in: int = 300


class MFAVerifyRequest(APIModel):
    mfa_ticket: str = Field(min_length=20, max_length=200)
    code: str = Field(pattern=r"^\d{6}$")
    device_name: str | None = Field(default=None, max_length=120)


class TOTPSetupOut(APIModel):
    secret: str
    provisioning_uri: str


class TOTPEnableRequest(APIModel):
    code: str = Field(pattern=r"^\d{6}$")


class UserOut(APIModel):
    id: UUID
    display_name: str
    phone_masked: str
    role: str
    status: str
    verified_at: datetime | None
    admin_2fa_enabled: bool = False


class UserUpdate(APIModel):
    display_name: str = Field(min_length=2, max_length=120)


class AccountDeleteRequest(APIModel):
    confirmation: Literal["УДАЛИТЬ"]


class MediaPresignRequest(APIModel):
    filename: str = Field(min_length=1, max_length=240)
    mime_type: Literal["image/jpeg", "image/png", "image/webp", "video/mp4", "video/quicktime"]
    size_bytes: int = Field(gt=0, le=100 * 1024 * 1024)
    purpose: Literal["listing", "evidence", "chat", "avatar"] = "listing"


class MediaPresignOut(APIModel):
    object_key: str
    upload_url: str
    required_headers: dict[str, str]
    expires_in: int


class MediaCompleteRequest(APIModel):
    object_key: str
    mime_type: Literal["image/jpeg", "image/png", "image/webp", "video/mp4", "video/quicktime"]
    size_bytes: int = Field(gt=0, le=100 * 1024 * 1024)
    sha256: str = Field(pattern=r"^[a-fA-F0-9]{64}$")
    purpose: Literal["listing", "evidence", "chat", "avatar"] = "listing"
    listing_id: UUID | None = None
    width: int | None = Field(default=None, gt=0)
    height: int | None = Field(default=None, gt=0)
    duration_seconds: float | None = Field(default=None, ge=0, le=60)


class MediaOut(APIModel):
    id: UUID
    mime_type: str
    size_bytes: int
    status: str
    download_url: str
    width: int | None
    height: int | None
    duration_seconds: float | None


class LocationInput(APIModel):
    region: str = Field(min_length=2, max_length=180)
    latitude: float | None = Field(default=None, ge=-90, le=90)
    longitude: float | None = Field(default=None, ge=-180, le=180)
    exact_address: str | None = Field(default=None, max_length=500)


class ListingCreate(APIModel):
    kind: Literal["lost", "found"]
    title: str = Field(min_length=3, max_length=180)
    description: str = Field(min_length=10, max_length=5000)
    category: str = Field(min_length=2, max_length=80)
    tags: list[str] = Field(default_factory=list, max_length=30)
    public_features: list[str] = Field(default_factory=list, max_length=30)
    hidden_features: list[str] = Field(default_factory=list, max_length=30)
    event_at: datetime
    location: LocationInput
    media_ids: list[UUID] = Field(default_factory=list, max_length=9)
    organization_id: UUID | None = None
    branch_id: UUID | None = None
    storage_code: str | None = Field(default=None, max_length=80)
    publish: bool = False

    _category = field_validator("category")(normalize_category)

    @field_validator("tags", "public_features", "hidden_features")
    @classmethod
    def normalize_strings(cls, values: list[str]) -> list[str]:
        return list(dict.fromkeys(item.strip().lower() for item in values if item.strip()))


class ListingUpdate(APIModel):
    title: str | None = Field(default=None, min_length=3, max_length=180)
    description: str | None = Field(default=None, min_length=10, max_length=5000)
    category: str | None = Field(default=None, min_length=2, max_length=80)
    tags: list[str] | None = None
    public_features: list[str] | None = None
    hidden_features: list[str] | None = None
    event_at: datetime | None = None
    location: LocationInput | None = None
    status: Literal["draft", "active", "paused", "closed"] | None = None
    storage_code: str | None = Field(default=None, max_length=80)
    media_ids: list[UUID] | None = Field(default=None, max_length=9)

    @field_validator("category")
    @classmethod
    def normalize_category_value(cls, value: str | None) -> str | None:
        return normalize_category(value) if value is not None else None


class ListingOut(APIModel):
    id: UUID
    owner_id: UUID
    organization_id: UUID | None
    branch_id: UUID | None
    kind: str
    status: str
    title: str
    description: str
    category: str
    tags: list[str]
    public_features: list[str]
    event_at: datetime
    public_region: str
    approx_latitude: float | None
    approx_longitude: float | None
    storage_code: str | None = None
    ai_status: str
    ai_confidence: float | None
    moderation_status: str
    published_at: datetime | None
    media: list[MediaOut] = Field(default_factory=list)
    created_at: datetime
    updated_at: datetime


class ListingPage(APIModel):
    items: list[ListingOut]
    total: int
    limit: int
    offset: int


class AIItemDescription(APIModel):
    title: str
    category: str
    description: str
    tags: list[str]
    colors: list[str]
    distinctive_features: list[str]
    sensitive_details_to_hide: list[str]
    confidence: float = Field(ge=0, le=1)


class AIDescribeRequest(APIModel):
    media_id: UUID
    kind: Literal["lost", "found"]
    user_hint: str = Field(default="", max_length=1000)


class AIPhotoSearchRequest(APIModel):
    media_id: UUID
    target_kind: Literal["lost", "found"] | None = None
    category: str | None = Field(default=None, max_length=80)
    region: str | None = Field(default=None, max_length=180)
    limit: int = Field(default=20, ge=1, le=50)


class PhotoSearchOut(APIModel):
    listing: ListingOut
    visual_score: float


class MatchOut(APIModel):
    id: UUID
    candidate: ListingOut
    score: float
    factors: dict[str, float]
    status: str
    created_at: datetime


class MatchDecision(APIModel):
    status: Literal["accepted", "rejected", "hidden"]


class ClaimCreate(APIModel):
    listing_id: UUID
    match_id: UUID | None = None


class ClaimAnswers(APIModel):
    answers: dict[str, str] = Field(min_length=1, max_length=20)


class EvidenceCreate(APIModel):
    media_id: UUID
    evidence_type: Literal["old_photo", "receipt", "packaging", "serial", "other"]
    note: str = Field(default="", max_length=1000)


class ClaimDecision(APIModel):
    decision: Literal["approved", "rejected", "needs_more_info"]
    reason: str = Field(min_length=3, max_length=2000)


class ClaimAppeal(APIModel):
    reason: str = Field(min_length=10, max_length=3000)


class ClaimOut(APIModel):
    id: UUID
    listing_id: UUID
    claimant_id: UUID
    match_id: UUID | None
    status: str
    risk_score: float
    risk_factors: list[str]
    decision_reason: str | None
    submitted_at: datetime | None
    decided_at: datetime | None
    created_at: datetime
    updated_at: datetime


class ChatMessageCreate(APIModel):
    body: str = Field(min_length=1, max_length=4000)
    attachment_ids: list[UUID] = Field(default_factory=list, max_length=5)


class ChatMessageOut(APIModel):
    id: UUID
    conversation_id: UUID
    sender_id: UUID
    body: str
    attachment_ids: list[UUID]
    system: bool
    read_at: datetime | None
    created_at: datetime


class ContactConsent(APIModel):
    consent: bool


class ContactOut(APIModel):
    unlocked: bool
    claimant_phone: str | None = None
    holder_phone: str | None = None


class HandoverCreate(APIModel):
    method: Literal["safe_point", "meeting", "delivery"]
    place: str = Field(min_length=3, max_length=500)
    scheduled_at: datetime | None = None


class HandoverOut(APIModel):
    id: UUID
    claim_id: UUID
    method: str
    place: str | None
    scheduled_at: datetime | None
    qr_token: str | None = None
    qr_expires_at: datetime
    holder_confirmed_at: datetime | None
    claimant_confirmed_at: datetime | None
    completed_at: datetime | None


class HandoverScan(APIModel):
    token: str
    claim_id: UUID | None = None


class OrganizationCreate(APIModel):
    name: str = Field(min_length=3, max_length=240)
    inn: str = Field(pattern=r"^\d{10}(\d{2})?$")
    ogrn: str | None = Field(default=None, pattern=r"^\d{13}(\d{2})?$")


class OrganizationOut(APIModel):
    id: UUID
    name: str
    inn: str
    ogrn: str | None
    status: str
    api_enabled: bool
    created_at: datetime


class BranchCreate(APIModel):
    name: str = Field(min_length=2, max_length=180)
    public_address: str = Field(min_length=3, max_length=320)
    exact_location: LocationInput | None = None
    timezone: str = Field(default="Europe/Moscow", max_length=64)


class InviteMember(APIModel):
    phone: str
    role: Literal["owner", "manager", "operator", "viewer"] = "operator"


class BulkListingItem(APIModel):
    title: str = Field(min_length=3, max_length=180)
    description: str = Field(min_length=10, max_length=5000)
    category: str = Field(min_length=2, max_length=80)
    tags: list[str] = Field(default_factory=list, max_length=30)
    event_at: datetime
    region: str = Field(min_length=2, max_length=180)
    storage_code: str | None = Field(default=None, max_length=80)
    branch_id: UUID | None = None


class CSVImportRequest(APIModel):
    csv: str = Field(min_length=1, max_length=1024 * 1024)


class BulkImportRequest(APIModel):
    items: list[BulkListingItem] = Field(min_length=1, max_length=1000)


class OrganizationSettingsUpdate(APIModel):
    api_enabled: bool


class OrganizationApiKeyCreate(APIModel):
    name: str = Field(min_length=2, max_length=120)
    permissions: list[Literal["inventory:read", "inventory:write", "claims:read"]] = Field(
        min_length=1, max_length=3
    )
    expires_at: datetime | None = None


class OrganizationApiKeyOut(APIModel):
    id: UUID
    name: str
    key_prefix: str
    permissions: list[str]
    status: str
    expires_at: datetime | None
    last_used_at: datetime | None
    api_key: str | None = None


class OrganizationDashboard(APIModel):
    active_inventory: int
    open_claims: int
    returned_30d: int
    median_return_hours: float | None


class NotificationOut(APIModel):
    id: UUID
    kind: str
    title: str
    body: str
    data: dict
    read_at: datetime | None
    created_at: datetime


class PushDeviceCreate(APIModel):
    platform: Literal["ios", "android", "web"]
    token: str = Field(min_length=20, max_length=4096)
    device_name: str | None = Field(default=None, max_length=120)
    app_version: str | None = Field(default=None, max_length=40)
    locale: str = Field(default="ru", min_length=2, max_length=16)


class PushDeviceOut(APIModel):
    id: UUID
    platform: str
    device_name: str | None
    app_version: str | None
    locale: str
    status: str
    last_seen_at: datetime | None


class SessionOut(APIModel):
    id: UUID
    device_name: str | None
    expires_at: datetime
    created_at: datetime
    current: bool = False


class SupportTicketCreate(APIModel):
    subject: str = Field(min_length=3, max_length=180)
    category: Literal["search", "claim", "handover", "organization", "billing", "technical", "other"]
    message: str = Field(min_length=3, max_length=4000)
    organization_id: UUID | None = None
    attachment_ids: list[UUID] = Field(default_factory=list, max_length=5)


class SupportMessageCreate(APIModel):
    body: str = Field(min_length=1, max_length=4000)
    attachment_ids: list[UUID] = Field(default_factory=list, max_length=5)
    internal: bool = False


class SupportMessageOut(APIModel):
    id: UUID
    ticket_id: UUID
    sender_id: UUID
    body: str
    attachment_ids: list[UUID]
    internal: bool
    created_at: datetime


class SupportTicketOut(APIModel):
    id: UUID
    user_id: UUID
    organization_id: UUID | None
    subject: str
    category: str
    priority: str
    status: str
    assigned_to: UUID | None
    first_response_at: datetime | None
    resolved_at: datetime | None
    created_at: datetime
    updated_at: datetime


class SupportTicketUpdate(APIModel):
    status: Literal["open", "waiting_user", "in_progress", "resolved", "closed"] | None = None
    priority: Literal["low", "normal", "high", "urgent"] | None = None
    assigned_to: UUID | None = None


WebhookEvent = Literal[
    "listing.created",
    "listing.updated",
    "match.created",
    "claim.submitted",
    "claim.decided",
    "handover.completed",
]


class WebhookCreate(APIModel):
    name: str = Field(min_length=2, max_length=120)
    url: HttpUrl
    events: list[WebhookEvent] = Field(min_length=1, max_length=6)


class WebhookOut(APIModel):
    id: UUID
    organization_id: UUID
    name: str
    url: str
    events: list[str]
    status: str
    last_success_at: datetime | None
    last_failure_at: datetime | None
    failure_count: int
    signing_secret: str | None = None
    created_at: datetime


class AdminUserUpdate(APIModel):
    role: Literal["user", "operator", "manager", "moderator", "admin"] | None = None
    status: Literal["active", "blocked", "deleted"] | None = None


class SystemSettingUpdate(APIModel):
    value: dict
    description: str = Field(default="", max_length=500)
    public: bool = False


class ModerationDecision(APIModel):
    decision: Literal["approve", "reject", "block", "request_changes"]
    reason: str = Field(min_length=3, max_length=2000)


class AdCampaignCreate(APIModel):
    advertiser_name: str = Field(min_length=2, max_length=180)
    title: str = Field(min_length=3, max_length=180)
    body: str = Field(min_length=3, max_length=320)
    action_label: str = Field(default="Открыть", max_length=60)
    action_url: HttpUrl
    placements: list[Literal["home_feed", "search_results"]] = Field(min_length=1, max_length=2)
    targeting: dict = Field(default_factory=dict)
    erid: str = Field(min_length=3, max_length=120)
    age_rating: str = Field(default="0+", max_length=8)
    starts_at: datetime
    ends_at: datetime
    daily_budget_kopecks: int = Field(gt=0)


class AdCampaignOut(APIModel):
    id: UUID
    advertiser_name: str
    title: str
    body: str
    action_label: str
    action_url: str
    placements: list[str]
    erid: str
    age_rating: str
    status: str
    starts_at: datetime
    ends_at: datetime


class AdEventCreate(APIModel):
    campaign_id: UUID
    event_type: Literal["impression", "click"]
    placement: Literal["home_feed", "search_results"]
    anonymous_id: str | None = Field(default=None, max_length=200)
    tracking_consent: bool = False
    context: dict = Field(default_factory=dict)
