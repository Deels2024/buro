from datetime import UTC, datetime
from uuid import UUID

from fastapi import APIRouter, HTTPException, Query
from sqlalchemy import func, select

from app.api.deps import DB, AdminUser, CurrentUser
from app.core.security import decrypt_json, encrypt_json
from app.db.models import OrganizationMember, SupportMessage, SupportTicket
from app.schemas import (
    SupportMessageCreate,
    SupportMessageOut,
    SupportTicketCreate,
    SupportTicketOut,
    SupportTicketUpdate,
)
from app.services.audit import add_audit

router = APIRouter()
admin_router = APIRouter()


def _message_out(message: SupportMessage) -> SupportMessageOut:
    return SupportMessageOut(
        id=message.id,
        ticket_id=message.ticket_id,
        sender_id=message.sender_id,
        body=decrypt_json(message.body_cipher)["body"],
        attachment_ids=[UUID(value) for value in message.attachment_ids],
        internal=message.internal,
        created_at=message.created_at,
    )


async def _ticket_access(db: DB, ticket_id: UUID, user: CurrentUser) -> SupportTicket:
    ticket = await db.get(SupportTicket, ticket_id)
    if not ticket:
        raise HTTPException(status_code=404, detail="Обращение не найдено")
    if ticket.user_id != user.id and user.role not in {"admin", "moderator"}:
        raise HTTPException(status_code=403, detail="Нет доступа к обращению")
    return ticket


@router.post("/tickets", response_model=SupportTicketOut, status_code=201)
async def create_ticket(payload: SupportTicketCreate, db: DB, user: CurrentUser) -> SupportTicket:
    if payload.organization_id:
        membership = await db.scalar(
            select(OrganizationMember.id).where(
                OrganizationMember.organization_id == payload.organization_id,
                OrganizationMember.user_id == user.id,
                OrganizationMember.status == "active",
            )
        )
        if not membership:
            raise HTTPException(status_code=403, detail="Нет доступа к организации")
    ticket = SupportTicket(
        user_id=user.id,
        organization_id=payload.organization_id,
        subject=payload.subject.strip(),
        category=payload.category,
    )
    db.add(ticket)
    await db.flush()
    db.add(
        SupportMessage(
            ticket_id=ticket.id,
            sender_id=user.id,
            body_cipher=encrypt_json({"body": payload.message.strip()}),
            attachment_ids=[str(value) for value in payload.attachment_ids],
        )
    )
    await db.commit()
    await db.refresh(ticket)
    return ticket


@router.get("/tickets", response_model=list[SupportTicketOut])
async def my_tickets(db: DB, user: CurrentUser, limit: int = Query(50, ge=1, le=100)) -> list[SupportTicket]:
    result = await db.scalars(
        select(SupportTicket)
        .where(SupportTicket.user_id == user.id)
        .order_by(SupportTicket.updated_at.desc())
        .limit(limit)
    )
    return list(result)


@router.get("/tickets/{ticket_id}", response_model=SupportTicketOut)
async def get_ticket(ticket_id: UUID, db: DB, user: CurrentUser) -> SupportTicket:
    return await _ticket_access(db, ticket_id, user)


@router.get("/tickets/{ticket_id}/messages", response_model=list[SupportMessageOut])
async def ticket_messages(ticket_id: UUID, db: DB, user: CurrentUser) -> list[SupportMessageOut]:
    await _ticket_access(db, ticket_id, user)
    filters = [SupportMessage.ticket_id == ticket_id]
    if user.role not in {"admin", "moderator"}:
        filters.append(SupportMessage.internal.is_(False))
    result = await db.scalars(select(SupportMessage).where(*filters).order_by(SupportMessage.created_at))
    return [_message_out(message) for message in result]


@router.post("/tickets/{ticket_id}/messages", response_model=SupportMessageOut, status_code=201)
async def add_message(
    ticket_id: UUID,
    payload: SupportMessageCreate,
    db: DB,
    user: CurrentUser,
) -> SupportMessageOut:
    ticket = await _ticket_access(db, ticket_id, user)
    if ticket.status == "closed":
        raise HTTPException(status_code=409, detail="Обращение закрыто")
    internal = payload.internal and user.role in {"admin", "moderator"}
    message = SupportMessage(
        ticket_id=ticket.id,
        sender_id=user.id,
        body_cipher=encrypt_json({"body": payload.body.strip()}),
        attachment_ids=[str(value) for value in payload.attachment_ids],
        internal=internal,
    )
    db.add(message)
    if user.role in {"admin", "moderator"}:
        ticket.first_response_at = ticket.first_response_at or datetime.now(UTC)
        ticket.status = "waiting_user" if not internal else ticket.status
    elif ticket.status == "waiting_user":
        ticket.status = "in_progress"
    await db.commit()
    await db.refresh(message)
    return _message_out(message)


@admin_router.get("/tickets")
async def admin_tickets(
    db: DB,
    _: AdminUser,
    status: str | None = None,
    priority: str | None = None,
    assigned_to: UUID | None = None,
    limit: int = Query(50, ge=1, le=100),
    offset: int = Query(0, ge=0),
) -> dict:
    filters = []
    if status:
        filters.append(SupportTicket.status == status)
    if priority:
        filters.append(SupportTicket.priority == priority)
    if assigned_to:
        filters.append(SupportTicket.assigned_to == assigned_to)
    total = await db.scalar(select(func.count(SupportTicket.id)).where(*filters)) or 0
    result = await db.scalars(
        select(SupportTicket)
        .where(*filters)
        .order_by(SupportTicket.updated_at.desc())
        .offset(offset)
        .limit(limit)
    )
    return {
        "items": [SupportTicketOut.model_validate(item).model_dump(mode="json") for item in result],
        "total": total,
        "limit": limit,
        "offset": offset,
    }


@admin_router.patch("/tickets/{ticket_id}", response_model=SupportTicketOut)
async def update_ticket(
    ticket_id: UUID,
    payload: SupportTicketUpdate,
    db: DB,
    admin: AdminUser,
) -> SupportTicket:
    ticket = await db.get(SupportTicket, ticket_id)
    if not ticket:
        raise HTTPException(status_code=404, detail="Обращение не найдено")
    data = payload.model_dump(exclude_unset=True)
    for key, value in data.items():
        setattr(ticket, key, value)
    if ticket.status in {"resolved", "closed"}:
        ticket.resolved_at = ticket.resolved_at or datetime.now(UTC)
    add_audit(
        db,
        actor_id=admin.id,
        action="support.ticket.update",
        entity_type="support_ticket",
        entity_id=ticket.id,
        payload=data,
    )
    await db.commit()
    await db.refresh(ticket)
    return ticket
