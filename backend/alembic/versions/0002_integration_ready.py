"""Integration-ready admin, support, devices, webhooks and 2FA.

Revision ID: 0002_integration_ready
Revises: 0001_initial
"""

import sqlalchemy as sa

from alembic import op
from app.db.models import (
    IntegrationWebhook,
    PushDevice,
    SupportMessage,
    SupportTicket,
    SystemSetting,
    WebhookDelivery,
)

revision = "0002_integration_ready"
down_revision = "0001_initial"
branch_labels = None
depends_on = None


NEW_TABLES = [
    PushDevice.__table__,
    SupportTicket.__table__,
    SupportMessage.__table__,
    IntegrationWebhook.__table__,
    WebhookDelivery.__table__,
    SystemSetting.__table__,
]


def _columns(table: str) -> set[str]:
    return {item["name"] for item in sa.inspect(op.get_bind()).get_columns(table)}


def upgrade() -> None:
    user_columns = _columns("users")
    if "admin_2fa_enabled" not in user_columns:
        op.add_column(
            "users",
            sa.Column("admin_2fa_enabled", sa.Boolean(), nullable=False, server_default=sa.false()),
        )
    if "admin_totp_secret_cipher" not in user_columns:
        op.add_column("users", sa.Column("admin_totp_secret_cipher", sa.Text(), nullable=True))

    refresh_columns = _columns("refresh_tokens")
    if "mfa_verified" not in refresh_columns:
        op.add_column(
            "refresh_tokens",
            sa.Column("mfa_verified", sa.Boolean(), nullable=False, server_default=sa.false()),
        )

    bind = op.get_bind()
    for table in NEW_TABLES:
        table.create(bind=bind, checkfirst=True)


def downgrade() -> None:
    bind = op.get_bind()
    for table in reversed(NEW_TABLES):
        table.drop(bind=bind, checkfirst=True)
    if "mfa_verified" in _columns("refresh_tokens"):
        op.drop_column("refresh_tokens", "mfa_verified")
    user_columns = _columns("users")
    if "admin_totp_secret_cipher" in user_columns:
        op.drop_column("users", "admin_totp_secret_cipher")
    if "admin_2fa_enabled" in user_columns:
        op.drop_column("users", "admin_2fa_enabled")
