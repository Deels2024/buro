"""Record staff-attested in-person returns without claimant accounts."""

from alembic import op
from app.db.models import CounterReturn

revision = "0006_counter_returns"
down_revision = "0005_guest_support"
branch_labels = None
depends_on = None


def upgrade() -> None:
    # 0001 initializes fresh databases from current metadata.
    CounterReturn.__table__.create(op.get_bind(), checkfirst=True)


def downgrade() -> None:
    raise RuntimeError("Counter-return records require a data-preserving rollback")
