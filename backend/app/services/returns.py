from sqlalchemy import func, select, union_all

from app.db.models import Claim, CounterReturn, Handover


def confirmed_returns():
    """A real handover, not a listing status. Keep exactly one event per item."""
    events = union_all(
        select(Claim.listing_id, Handover.completed_at)
        .join(Claim, Claim.id == Handover.claim_id)
        .where(Handover.completed_at.is_not(None)),
        select(CounterReturn.listing_id, CounterReturn.completed_at),
    ).subquery()
    return (
        select(events.c.listing_id, func.min(events.c.completed_at).label("completed_at"))
        .group_by(events.c.listing_id)
        .subquery()
    )
