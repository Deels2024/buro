"""Allow access-recovery requests without creating an account."""
import sqlalchemy as sa

from alembic import op

revision = "0005_guest_support"
down_revision = "0004_push_delivery"
branch_labels = None
depends_on = None


def upgrade() -> None:
    inspector = sa.inspect(op.get_bind())
    columns = {column["name"]: column for column in inspector.get_columns("support_tickets")}
    if "guest_contact_cipher" not in columns:
        op.add_column("support_tickets", sa.Column("guest_contact_cipher", sa.Text(), nullable=True))
    if not columns["user_id"]["nullable"]:
        op.alter_column("support_tickets", "user_id", existing_type=sa.Uuid(), nullable=True)
    messages = {column["name"]: column for column in inspector.get_columns("support_messages")}
    if not messages["sender_id"]["nullable"]:
        op.alter_column("support_messages", "sender_id", existing_type=sa.Uuid(), nullable=True)


def downgrade() -> None:
    # Never silently delete guest requests or their encrypted contacts.
    raise RuntimeError("Guest-support migration requires an explicit data-preserving rollback")
