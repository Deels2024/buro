from uuid import UUID

from sqlalchemy.ext.asyncio import AsyncSession

from app.db.models import AuditEvent


def add_audit(
    db: AsyncSession,
    *,
    actor_id: UUID | None,
    action: str,
    entity_type: str,
    entity_id: UUID | None,
    payload: dict | None = None,
) -> None:
    db.add(
        AuditEvent(
            actor_id=actor_id,
            action=action,
            entity_type=entity_type,
            entity_id=entity_id,
            payload=payload or {},
        )
    )
