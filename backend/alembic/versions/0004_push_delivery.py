"""Persist push attempts independently from the in-app notification."""
import sqlalchemy as sa

from alembic import op

revision = "0004_push_delivery"
down_revision = "0003_public_search"
branch_labels = None
depends_on = None


def upgrade() -> None:
    # 0001 uses current metadata on fresh installs; existing installations still
    # need this additive table. Support both paths without replacing any rows.
    if sa.inspect(op.get_bind()).has_table("push_deliveries"):
        return
    op.create_table("push_deliveries",
        sa.Column("id", sa.Uuid(), primary_key=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("notification_id", sa.Uuid(), sa.ForeignKey("notifications.id", ondelete="CASCADE"), nullable=False),
        sa.Column("device_id", sa.Uuid(), sa.ForeignKey("push_devices.id", ondelete="CASCADE"), nullable=False),
        sa.Column("status", sa.String(24), nullable=False),
        sa.Column("attempts", sa.Integer(), nullable=False),
        sa.Column("next_attempt_at", sa.DateTime(timezone=True), nullable=False),
        sa.UniqueConstraint("notification_id", "device_id"),
    )
    op.create_index("ix_push_deliveries_status", "push_deliveries", ["status"])
    op.create_index("ix_push_deliveries_next_attempt_at", "push_deliveries", ["next_attempt_at"])


def downgrade() -> None:
    op.drop_table("push_deliveries")
