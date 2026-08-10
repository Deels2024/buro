from datetime import UTC, datetime, timedelta
from uuid import UUID

from fastapi import APIRouter, HTTPException
from sqlalchemy import select

from app.api.deps import DB, CurrentUser
from app.core.security import decrypt_json, encrypt_json, hash_secret, random_token
from app.db.models import (
    Claim,
    ClaimEvidence,
    ContactGrant,
    Conversation,
    Handover,
    Listing,
    MatchCandidate,
    MediaObject,
    ModerationCase,
    Notification,
    OrganizationMember,
    User,
)
from app.schemas import (
    ClaimAnswers,
    ClaimAppeal,
    ClaimCreate,
    ClaimDecision,
    ClaimOut,
    ContactConsent,
    ContactOut,
    EvidenceCreate,
    HandoverCreate,
    HandoverOut,
    HandoverScan,
)
from app.services.audit import add_audit
from app.services.webhooks import create_deliveries, enqueue_deliveries

router = APIRouter()


async def _claim_and_listing(db: DB, claim_id: UUID) -> tuple[Claim, Listing]:
    claim = await db.get(Claim, claim_id)
    if not claim:
        raise HTTPException(status_code=404, detail="Заявление не найдено")
    listing = await db.get(Listing, claim.listing_id)
    if not listing:
        raise HTTPException(status_code=404, detail="Публикация не найдена")
    return claim, listing


async def _is_org_member(db: DB, user_id: UUID, organization_id: UUID | None) -> bool:
    if not organization_id:
        return False
    member = await db.scalar(
        select(OrganizationMember.id).where(
            OrganizationMember.organization_id == organization_id,
            OrganizationMember.user_id == user_id,
            OrganizationMember.status == "active",
        )
    )
    return member is not None


async def _assert_participant(db: DB, user: User, claim: Claim, listing: Listing) -> None:
    allowed = claim.claimant_id == user.id or listing.owner_id == user.id or user.role in {"admin", "moderator"}
    if not allowed:
        allowed = await _is_org_member(db, user.id, listing.organization_id)
    if not allowed:
        raise HTTPException(status_code=403, detail="Нет доступа к заявлению")


async def _assert_holder(db: DB, user: User, listing: Listing) -> None:
    allowed = listing.owner_id == user.id or user.role in {"admin", "moderator"}
    if not allowed:
        allowed = await _is_org_member(db, user.id, listing.organization_id)
    if not allowed:
        raise HTTPException(status_code=403, detail="Решение может принять только держатель вещи")


@router.post("", response_model=ClaimOut, status_code=201)
async def create_claim(payload: ClaimCreate, db: DB, user: CurrentUser) -> Claim:
    listing = await db.get(Listing, payload.listing_id)
    if not listing or listing.status != "active" or listing.kind != "found":
        raise HTTPException(status_code=404, detail="Активная находка не найдена")
    if listing.owner_id == user.id:
        raise HTTPException(status_code=422, detail="Нельзя заявить права на свою публикацию")
    existing = await db.scalar(
        select(Claim).where(Claim.listing_id == listing.id, Claim.claimant_id == user.id)
    )
    if existing:
        return existing
    if payload.match_id:
        match = await db.get(MatchCandidate, payload.match_id)
        if not match or match.candidate_listing_id != listing.id:
            raise HTTPException(status_code=422, detail="Совпадение не относится к находке")
    claim = Claim(listing_id=listing.id, claimant_id=user.id, match_id=payload.match_id)
    db.add(claim)
    await db.flush()
    db.add(Conversation(claim_id=claim.id))
    await db.commit()
    await db.refresh(claim)
    return claim


@router.get("/mine", response_model=list[ClaimOut])
async def my_claims(db: DB, user: CurrentUser) -> list[Claim]:
    result = await db.scalars(
        select(Claim).where(Claim.claimant_id == user.id).order_by(Claim.created_at.desc())
    )
    return list(result)


@router.get("/{claim_id}", response_model=ClaimOut)
async def get_claim(claim_id: UUID, db: DB, user: CurrentUser) -> Claim:
    claim, listing = await _claim_and_listing(db, claim_id)
    await _assert_participant(db, user, claim, listing)
    return claim


@router.get("/{claim_id}/conversation")
async def claim_conversation(claim_id: UUID, db: DB, user: CurrentUser) -> dict[str, str]:
    claim, listing = await _claim_and_listing(db, claim_id)
    await _assert_participant(db, user, claim, listing)
    conversation = await db.scalar(select(Conversation).where(Conversation.claim_id == claim.id))
    if not conversation:
        raise HTTPException(status_code=404, detail="Чат заявления не найден")
    return {"conversation_id": str(conversation.id), "status": conversation.status}


@router.put("/{claim_id}/answers", response_model=ClaimOut)
async def save_answers(payload: ClaimAnswers, claim_id: UUID, db: DB, user: CurrentUser) -> Claim:
    claim, listing = await _claim_and_listing(db, claim_id)
    if claim.claimant_id != user.id or claim.status not in {"draft", "needs_more_info"}:
        raise HTTPException(status_code=403, detail="Ответы нельзя изменить")
    claim.answers_cipher = encrypt_json(payload.answers)
    await db.commit()
    await db.refresh(claim)
    return claim


@router.post("/{claim_id}/evidence", response_model=ClaimOut)
async def add_evidence(payload: EvidenceCreate, claim_id: UUID, db: DB, user: CurrentUser) -> Claim:
    claim, _ = await _claim_and_listing(db, claim_id)
    if claim.claimant_id != user.id or claim.status not in {"draft", "needs_more_info"}:
        raise HTTPException(status_code=403, detail="Доказательства нельзя изменить")
    media = await db.get(MediaObject, payload.media_id)
    if not media or media.owner_id != user.id or media.purpose != "evidence":
        raise HTTPException(status_code=404, detail="Доказательство не найдено")
    db.add(
        ClaimEvidence(
            claim_id=claim.id,
            media_id=media.id,
            evidence_type=payload.evidence_type,
            note_cipher=encrypt_json({"note": payload.note}) if payload.note else None,
        )
    )
    await db.commit()
    await db.refresh(claim)
    return claim


@router.post("/{claim_id}/submit", response_model=ClaimOut)
async def submit_claim(claim_id: UUID, db: DB, user: CurrentUser) -> Claim:
    claim, listing = await _claim_and_listing(db, claim_id)
    if claim.claimant_id != user.id or claim.status not in {"draft", "needs_more_info"}:
        raise HTTPException(status_code=403, detail="Заявление нельзя отправить")
    if not claim.answers_cipher:
        raise HTTPException(status_code=422, detail="Ответьте на контрольные вопросы")
    evidence_count = len(
        list(await db.scalars(select(ClaimEvidence.id).where(ClaimEvidence.claim_id == claim.id)))
    )
    previous_claims = len(
        list(
            await db.scalars(
                select(Claim.id).where(
                    Claim.claimant_id == user.id,
                    Claim.created_at >= datetime.now(UTC) - timedelta(days=30),
                )
            )
        )
    )
    factors = []
    risk = 0.15
    if evidence_count == 0:
        risk += 0.25
        factors.append("нет медиа-доказательств")
    if previous_claims > 3:
        risk += 0.35
        factors.append("много заявлений за 30 дней")
    claim.risk_score = min(risk, 1.0)
    claim.risk_factors = factors
    claim.status = "under_review"
    claim.submitted_at = datetime.now(UTC)
    db.add(
        Notification(
            user_id=listing.owner_id,
            kind="claim_submitted",
            title="Новое заявление владельца",
            body=f"По находке «{listing.title}» поступило заявление.",
            data={"claim_id": str(claim.id)},
        )
    )
    delivery_ids = await create_deliveries(
        db,
        organization_id=listing.organization_id,
        event_type="claim.submitted",
        payload={"claim_id": str(claim.id), "listing_id": str(listing.id)},
    )
    await db.commit()
    await enqueue_deliveries(delivery_ids)
    await db.refresh(claim)
    return claim


@router.post("/{claim_id}/decision", response_model=ClaimOut)
async def decide_claim(payload: ClaimDecision, claim_id: UUID, db: DB, user: CurrentUser) -> Claim:
    claim, listing = await _claim_and_listing(db, claim_id)
    await _assert_holder(db, user, listing)
    if claim.status not in {"under_review", "needs_more_info"}:
        raise HTTPException(status_code=409, detail="Заявление уже обработано")
    claim.status = payload.decision
    claim.decision_reason = payload.reason
    claim.decided_by = user.id
    claim.decided_at = datetime.now(UTC)
    db.add(
        Notification(
            user_id=claim.claimant_id,
            kind="claim_decision",
            title="Статус заявления изменён",
            body="Владелец подтверждён." if payload.decision == "approved" else payload.reason,
            data={"claim_id": str(claim.id), "status": payload.decision},
        )
    )
    if payload.decision == "approved":
        grant = await db.scalar(select(ContactGrant).where(ContactGrant.claim_id == claim.id))
        if not grant:
            db.add(ContactGrant(claim_id=claim.id))
    add_audit(
        db,
        actor_id=user.id,
        action="claim.decision",
        entity_type="claim",
        entity_id=claim.id,
        payload={"decision": payload.decision},
    )
    delivery_ids = await create_deliveries(
        db,
        organization_id=listing.organization_id,
        event_type="claim.decided",
        payload={"claim_id": str(claim.id), "status": claim.status},
    )
    await db.commit()
    await enqueue_deliveries(delivery_ids)
    await db.refresh(claim)
    return claim


@router.post("/{claim_id}/appeal", status_code=201)
async def appeal_claim(payload: ClaimAppeal, claim_id: UUID, db: DB, user: CurrentUser) -> dict[str, str]:
    claim, _ = await _claim_and_listing(db, claim_id)
    if claim.claimant_id != user.id or claim.status != "rejected":
        raise HTTPException(status_code=409, detail="Апелляция недоступна")
    existing = await db.scalar(
        select(ModerationCase).where(
            ModerationCase.entity_type == "claim",
            ModerationCase.entity_id == claim.id,
            ModerationCase.status == "open",
        )
    )
    if existing:
        return {"case_id": str(existing.id), "status": existing.status}
    case = ModerationCase(
        entity_type="claim",
        entity_id=claim.id,
        reason=payload.reason[:120],
        status="open",
        priority=70,
        resolution=encrypt_json({"appeal_text": payload.reason}),
    )
    db.add(case)
    await db.commit()
    await db.refresh(case)
    return {"case_id": str(case.id), "status": case.status}


@router.put("/{claim_id}/contact-consent", response_model=ContactOut)
async def contact_consent(payload: ContactConsent, claim_id: UUID, db: DB, user: CurrentUser) -> ContactOut:
    claim, listing = await _claim_and_listing(db, claim_id)
    await _assert_participant(db, user, claim, listing)
    if claim.status != "approved":
        raise HTTPException(status_code=409, detail="Сначала подтвердите владельца")
    grant = await db.scalar(select(ContactGrant).where(ContactGrant.claim_id == claim.id))
    if not grant:
        grant = ContactGrant(claim_id=claim.id)
        db.add(grant)
    now = datetime.now(UTC) if payload.consent else None
    if user.id == claim.claimant_id:
        grant.claimant_consent_at = now
    else:
        await _assert_holder(db, user, listing)
        grant.holder_consent_at = now
    grant.revoked_at = None if payload.consent else datetime.now(UTC)
    add_audit(
        db,
        actor_id=user.id,
        action="contact.consent",
        entity_type="claim",
        entity_id=claim.id,
        payload={"consent": payload.consent},
    )
    await db.commit()
    return await _contact_out(db, claim, listing, grant)


@router.get("/{claim_id}/contacts", response_model=ContactOut)
async def contacts(claim_id: UUID, db: DB, user: CurrentUser) -> ContactOut:
    claim, listing = await _claim_and_listing(db, claim_id)
    await _assert_participant(db, user, claim, listing)
    grant = await db.scalar(select(ContactGrant).where(ContactGrant.claim_id == claim.id))
    return await _contact_out(db, claim, listing, grant)


async def _contact_out(db: DB, claim: Claim, listing: Listing, grant: ContactGrant | None) -> ContactOut:
    unlocked = bool(
        grant
        and grant.claimant_consent_at
        and grant.holder_consent_at
        and not grant.revoked_at
        and claim.status == "approved"
    )
    if not unlocked:
        return ContactOut(unlocked=False)
    claimant = await db.get(User, claim.claimant_id)
    holder = await db.get(User, listing.owner_id)
    return ContactOut(
        unlocked=True,
        claimant_phone=decrypt_json(claimant.phone_cipher)["phone"] if claimant else None,
        holder_phone=decrypt_json(holder.phone_cipher)["phone"] if holder else None,
    )


@router.post("/{claim_id}/handover", response_model=HandoverOut)
async def create_handover(payload: HandoverCreate, claim_id: UUID, db: DB, user: CurrentUser) -> HandoverOut:
    claim, listing = await _claim_and_listing(db, claim_id)
    await _assert_participant(db, user, claim, listing)
    if claim.claimant_id != user.id:
        raise HTTPException(status_code=403, detail="Способ передачи выбирает подтверждённый владелец")
    if claim.status != "approved":
        raise HTTPException(status_code=409, detail="Владелец ещё не подтверждён")
    existing = await db.scalar(select(Handover).where(Handover.claim_id == claim.id))
    if existing:
        return _handover_out(existing)
    raw_token = random_token(24)
    handover = Handover(
        claim_id=claim.id,
        method=payload.method,
        place_cipher=encrypt_json({"place": payload.place}),
        scheduled_at=payload.scheduled_at,
        qr_token_hash=hash_secret(raw_token),
        qr_expires_at=datetime.now(UTC) + timedelta(minutes=20),
    )
    db.add(handover)
    await db.commit()
    await db.refresh(handover)
    return _handover_out(handover, raw_token)


@router.get("/{claim_id}/handover", response_model=HandoverOut)
async def get_handover(claim_id: UUID, db: DB, user: CurrentUser) -> HandoverOut:
    claim, listing = await _claim_and_listing(db, claim_id)
    await _assert_participant(db, user, claim, listing)
    handover = await db.scalar(select(Handover).where(Handover.claim_id == claim.id))
    if not handover:
        raise HTTPException(status_code=404, detail="Передача ещё не создана")
    return _handover_out(handover)


def _handover_out(handover: Handover, raw_token: str | None = None) -> HandoverOut:
    return HandoverOut(
        id=handover.id,
        claim_id=handover.claim_id,
        method=handover.method,
        place=decrypt_json(handover.place_cipher)["place"] if handover.place_cipher else None,
        scheduled_at=handover.scheduled_at,
        qr_token=raw_token,
        qr_expires_at=handover.qr_expires_at,
        holder_confirmed_at=handover.holder_confirmed_at,
        claimant_confirmed_at=handover.claimant_confirmed_at,
        completed_at=handover.completed_at,
    )


@router.post("/{claim_id}/handover/regenerate", response_model=HandoverOut)
async def regenerate_handover(claim_id: UUID, db: DB, user: CurrentUser) -> HandoverOut:
    claim, listing = await _claim_and_listing(db, claim_id)
    await _assert_participant(db, user, claim, listing)
    if claim.claimant_id != user.id:
        raise HTTPException(status_code=403, detail="QR обновляет подтверждённый владелец")
    handover = await db.scalar(select(Handover).where(Handover.claim_id == claim.id))
    if not handover or handover.completed_at:
        raise HTTPException(status_code=409, detail="Передача недоступна")
    raw_token = random_token(24)
    handover.qr_token_hash = hash_secret(raw_token)
    handover.qr_expires_at = datetime.now(UTC) + timedelta(minutes=20)
    handover.holder_confirmed_at = None
    handover.claimant_confirmed_at = None
    await db.commit()
    await db.refresh(handover)
    return _handover_out(handover, raw_token)


@router.post("/handover/scan", response_model=HandoverOut)
async def scan_handover(payload: HandoverScan, db: DB, user: CurrentUser) -> HandoverOut:
    handover = await db.scalar(select(Handover).where(Handover.qr_token_hash == hash_secret(payload.token)))
    if not handover or handover.qr_expires_at <= datetime.now(UTC):
        raise HTTPException(status_code=400, detail="QR-код недействителен или истёк")
    claim, listing = await _claim_and_listing(db, handover.claim_id)
    await _assert_participant(db, user, claim, listing)
    now = datetime.now(UTC)
    if user.id == claim.claimant_id:
        handover.claimant_confirmed_at = now
    else:
        await _assert_holder(db, user, listing)
        handover.holder_confirmed_at = now
    if handover.claimant_confirmed_at and handover.holder_confirmed_at:
        handover.completed_at = now
        claim.status = "completed"
        listing.status = "closed"
        listing.closed_at = now
    add_audit(
        db,
        actor_id=user.id,
        action="handover.scan",
        entity_type="handover",
        entity_id=handover.id,
        payload={"completed": handover.completed_at is not None},
    )
    delivery_ids = []
    if handover.completed_at:
        delivery_ids = await create_deliveries(
            db,
            organization_id=listing.organization_id,
            event_type="handover.completed",
            payload={"handover_id": str(handover.id), "claim_id": str(claim.id)},
        )
    await db.commit()
    await enqueue_deliveries(delivery_ids)
    await db.refresh(handover)
    return _handover_out(handover)
