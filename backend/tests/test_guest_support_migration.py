import importlib.util
from pathlib import Path

import pytest
from alembic.migration import MigrationContext
from alembic.operations import Operations
from sqlalchemy import inspect, text
from test_workflows import workflow  # noqa: F401

from app.core.security import encrypt_json
from app.db.models import SupportMessage, SupportTicket


async def test_existing_support_records_survive_guest_migration(workflow):  # noqa: F811
    _, sessions, users, _ = workflow
    async with sessions() as db:
        if db.bind.dialect.name != "postgresql":
            pytest.skip("PostgreSQL ALTER COLUMN migration is checked in CI")
        ticket = SupportTicket(user_id=users['holder'].id, subject='Существующее обращение', category='technical')
        db.add(ticket)
        await db.flush()
        message = SupportMessage(ticket_id=ticket.id, sender_id=users['holder'].id,
                                 body_cipher=encrypt_json({'body': 'Существующее сообщение'}))
        db.add(message)
        await db.commit()
        ticket_id, message_id = ticket.id, message.id
        # Recreate the previous release's constraints, preserving real rows.
        await db.execute(text('ALTER TABLE support_tickets DROP COLUMN guest_contact_cipher'))
        await db.execute(text('ALTER TABLE support_tickets ALTER COLUMN user_id SET NOT NULL'))
        await db.execute(text('ALTER TABLE support_messages ALTER COLUMN sender_id SET NOT NULL'))
        await db.commit()
    async with sessions.kw['bind'].begin() as connection:
        def upgrade(sync_connection):
            path = Path(__file__).parents[1] / 'alembic/versions/0005_guest_support.py'
            spec = importlib.util.spec_from_file_location('guest_migration', path)
            module = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(module)
            with Operations.context(MigrationContext.configure(sync_connection)):
                module.upgrade()
                module.upgrade()  # Also safe after metadata-based fresh installs.
            columns = {column['name']: column for column in inspect(sync_connection).get_columns('support_tickets')}
            assert columns['user_id']['nullable'] and columns['guest_contact_cipher']['nullable']
        await connection.run_sync(upgrade)
    async with sessions() as db:
        assert (await db.get(SupportTicket, ticket_id)).user_id == users['holder'].id
        assert (await db.get(SupportMessage, message_id)).sender_id == users['holder'].id
        db.add(SupportTicket(subject='Гостевое обращение', category='technical',
                             guest_contact_cipher=encrypt_json({'contact': 'help@example.org'})))
        await db.commit()
