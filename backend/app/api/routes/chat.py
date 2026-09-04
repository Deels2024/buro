import json
from collections import defaultdict
from uuid import UUID

from fastapi import APIRouter, HTTPException, Query, WebSocket, WebSocketDisconnect
from sqlalchemy import select

from app.api.deps import DB, CurrentUser
from app.core.security import decrypt_json, encrypt_json, random_token
from app.db.models import Claim, Conversation, Listing, MediaObject, Message, OrganizationMember, User
from app.db.session import SessionLocal
from app.schemas import ChatMessageCreate, ChatMessageOut
from app.services.cache import redis, set_json

router = APIRouter()


class ConnectionManager:
    def __init__(self) -> None:
        self.connections: dict[UUID, set[WebSocket]] = defaultdict(set)

    async def connect(self, conversation_id: UUID, websocket: WebSocket) -> None:
        await websocket.accept()
        self.connections[conversation_id].add(websocket)

    def disconnect(self, conversation_id: UUID, websocket: WebSocket) -> None:
        self.connections[conversation_id].discard(websocket)

    async def broadcast(self, conversation_id: UUID, payload: dict) -> None:
        stale = []
        for connection in self.connections[conversation_id]:
            try:
                await connection.send_json(payload)
            except Exception:
                stale.append(connection)
        for connection in stale:
            self.disconnect(conversation_id, connection)


manager = ConnectionManager()


async def _conversation_access(db: DB, conversation_id: UUID, user: User) -> tuple[Conversation, Claim]:
    conversation = await db.get(Conversation, conversation_id)
    if not conversation:
        raise HTTPException(status_code=404, detail="Чат не найден")
    claim = await db.get(Claim, conversation.claim_id)
    listing = await db.get(Listing, claim.listing_id) if claim else None
    if not claim or not listing:
        raise HTTPException(status_code=404, detail="Заявление не найдено")
    allowed = user.id in {claim.claimant_id, listing.owner_id} or user.role in {"admin", "moderator"}
    if not allowed and listing.organization_id:
        allowed = (
            await db.scalar(
                select(OrganizationMember.id).where(
                    OrganizationMember.organization_id == listing.organization_id,
                    OrganizationMember.user_id == user.id,
                    OrganizationMember.status == "active",
                    OrganizationMember.role.in_(["owner", "manager", "operator"]),
                )
            )
            is not None
        )
    if not allowed:
        raise HTTPException(status_code=403, detail="Нет доступа к чату")
    return conversation, claim


def _message_out(message: Message) -> ChatMessageOut:
    return ChatMessageOut(
        id=message.id,
        conversation_id=message.conversation_id,
        sender_id=message.sender_id,
        body=decrypt_json(message.body_cipher)["body"],
        attachment_ids=[UUID(value) for value in message.attachment_ids],
        system=message.system,
        read_at=message.read_at,
        created_at=message.created_at,
    )


@router.get("/{conversation_id}/messages", response_model=list[ChatMessageOut])
async def messages(
    conversation_id: UUID,
    db: DB,
    user: CurrentUser,
    limit: int = Query(default=50, ge=1, le=100),
) -> list[ChatMessageOut]:
    await _conversation_access(db, conversation_id, user)
    result = await db.scalars(
        select(Message)
        .where(Message.conversation_id == conversation_id)
        .order_by(Message.created_at.desc())
        .limit(limit)
    )
    return [_message_out(message) for message in reversed(list(result))]


@router.post("/{conversation_id}/messages", response_model=ChatMessageOut, status_code=201)
async def send_message(
    payload: ChatMessageCreate,
    conversation_id: UUID,
    db: DB,
    user: CurrentUser,
) -> ChatMessageOut:
    conversation, claim = await _conversation_access(db, conversation_id, user)
    if claim.status not in {"under_review", "needs_more_info", "approved"}:
        raise HTTPException(status_code=409, detail="Чат пока недоступен")
    if payload.attachment_ids:
        owned = list(await db.scalars(select(MediaObject.id).where(MediaObject.id.in_(payload.attachment_ids), MediaObject.owner_id == user.id, MediaObject.purpose == "chat", MediaObject.status == "ready")))
        if len(owned) != len(set(payload.attachment_ids)):
            raise HTTPException(422, "Вложение недоступно")
    message = Message(
        conversation_id=conversation.id,
        sender_id=user.id,
        body_cipher=encrypt_json({"body": payload.body.strip()}),
        attachment_ids=[str(value) for value in payload.attachment_ids],
    )
    db.add(message)
    await db.commit()
    await db.refresh(message)
    output = _message_out(message)
    await manager.broadcast(conversation_id, output.model_dump(mode="json"))
    return output


@router.post("/{conversation_id}/ticket")
async def websocket_ticket(conversation_id: UUID, db: DB, user: CurrentUser) -> dict[str, str | int]:
    await _conversation_access(db, conversation_id, user)
    ticket = random_token(24)
    await set_json(
        f"ws-ticket:{ticket}",
        {"user_id": str(user.id), "conversation_id": str(conversation_id)},
        ttl=60,
    )
    return {"ticket": ticket, "expires_in": 60}


@router.websocket("/{conversation_id}/ws")
async def websocket_chat(websocket: WebSocket, conversation_id: UUID, ticket: str = Query()) -> None:
    try:
        raw = await redis.getdel(f"ws-ticket:{ticket}")
        payload = json.loads(raw) if raw else None
        if not payload or payload["conversation_id"] != str(conversation_id):
            raise ValueError
        user_id = UUID(payload["user_id"])
    except (ValueError, KeyError, json.JSONDecodeError):
        await websocket.close(code=4401)
        return
    async with SessionLocal() as db:
        user = await db.get(User, user_id)
        if not user:
            await websocket.close(code=4401)
            return
        try:
            await _conversation_access(db, conversation_id, user)
        except HTTPException:
            await websocket.close(code=4403)
            return
    await manager.connect(conversation_id, websocket)
    try:
        while True:
            raw = await websocket.receive_text()
            if raw == "ping":
                await websocket.send_text("pong")
            else:
                await websocket.send_json({"type": "error", "message": "Отправляйте сообщения через POST API"})
    except WebSocketDisconnect:
        manager.disconnect(conversation_id, websocket)
