"""Two-shift partner workflow via the real HTTP routes."""
from datetime import UTC, datetime, timedelta
from uuid import UUID

from sqlalchemy import select
from test_workflows import listing_body, photo, workflow  # noqa: F401

from app import worker
from app.db.models import (
    AuditEvent,
    Branch,
    CounterReturn,
    Handover,
    Listing,
    Organization,
    OrganizationMember,
    User,
)

APPROVAL = {"decision": "approve", "reason": "Тестовая фотография проверена"}


async def test_partner_intake_match_and_exact_return_report(workflow, monkeypatch):  # noqa: F811
    client, sessions, users, h = workflow
    async with sessions() as db:
        venue = Organization(name="Тестовый ТЦ", inn="1234567890", status="verified")
        other = Organization(name="Другая площадка", inn="0987654321", status="verified")
        db.add_all([venue, other])
        await db.flush()
        branch = Branch(organization_id=venue.id, name="Первая стойка", public_address="Тестовый адрес")
        other_branch = Branch(organization_id=other.id, name="Другая стойка", public_address="Другой тестовый адрес")
        db.add_all([branch, other_branch])
        db.add_all([
            OrganizationMember(organization_id=venue.id, user_id=users["holder"].id, role="owner"),
            OrganizationMember(organization_id=venue.id, user_id=users["admin"].id, role="manager"),
            OrganizationMember(organization_id=venue.id, user_id=users["viewer"].id, role="viewer"),
            OrganizationMember(organization_id=other.id, user_id=users["stranger"].id, role="owner"),
        ])
        # A regular operator, not an administrator, forms the second shift.
        db.add(OrganizationMember(organization_id=venue.id, user_id=users["claimant"].id, role="operator"))
        await db.commit()

    prefix = f"/v1/organizations/{venue.id}"
    body = {"organization_id": str(venue.id), "branch_id": str(branch.id), "publish": True}
    new = await client.post("/v1/listings", json=listing_body(
        **body, media_ids=[await photo(sessions, users["holder"])],
    ), headers=h("holder"))
    assert new.status_code == 201, new.text
    item = new.json()["id"]
    assert (await client.post(f"/v1/admin/moderation/listings/{item}", json=APPROVAL,
                              headers=h("admin"))).status_code == 200
    lost = await client.post("/v1/listings", json=listing_body(kind="lost", publish=True),
                             headers=h("stranger"))
    lid = lost.json()["id"]
    assert (await client.post(f"/v1/admin/moderation/listings/{lid}", json=APPROVAL,
                              headers=h("admin"))).status_code == 200
    async with sessions() as db:
        # Real past intake that is returned today: period returns may exceed same-cohort returns.
        entry = await db.get(Listing, UUID(item))
        entry.created_at = datetime.now(UTC) - timedelta(days=31)
        await db.commit()

    monkeypatch.setattr(worker, "SessionLocal", sessions)
    await worker.match_listing(UUID(item))
    assert (await client.get(f"/v1/listings/{lid}/matches", headers=h("stranger"))).json()[0]["candidate"]["id"] == item

    role = await client.get(f"{prefix}", headers=h("claimant"))
    assert role.json()["member_role"] == "operator"
    matches = f"/v1/listings/{item}/matches"
    match = await client.get(matches, headers=h("claimant"))
    assert match.status_code == 200 and match.json()[0]["candidate"]["id"] == lid
    assert match.json()[0]["candidate"]["storage_code"] is None
    assert (await client.get(matches, headers=h("stranger"))).status_code == 403
    assert (await client.get(matches, headers=h("viewer"))).status_code == 403
    journal = await client.get(f"{prefix}/inventory", params={"q": "PRIVATE-104"}, headers=h("claimant"))
    assert journal.status_code == 200 and journal.json()[0]["storage_code"] == "PRIVATE-104"
    assert journal.headers["cache-control"] == "no-store"
    assert (await client.get(f"{prefix}/inventory", params={"q": "PRIVATE-104"},
                             headers=h("viewer"))).json() == []
    public = await client.get(f"/items/{item}/")
    assert "Нет доступа к телефону?" in public.text and "Тестовый адрес" in public.text
    assert "PRIVATE-104" not in public.text and "secret-zip" not in public.text
    private = await client.get(f"/v1/listings/{item}/manage", headers=h("claimant"))
    assert private.json()["hidden_features"] == ["secret-zip"]
    assert "hidden_features" not in (await client.get(f"/v1/listings/{item}")).json()

    first = await client.get(f"{prefix}/analytics", params={"days": 30}, headers=h("holder"))
    assert first.json()["on_hand"] == 1
    assert first.json()["return_rate"] is None

    manual = await client.post("/v1/listings", json=listing_body(
        organization_id=str(venue.id), branch_id=str(branch.id),
    ), headers=h("holder"))
    assert (await client.patch(f"/v1/listings/{manual.json()['id']}", json={"status": "closed"},
                               headers=h("holder"))).status_code == 200
    path = f"{prefix}/inventory/{item}/counter-return"
    attest = {"verification": "private_feature", "confirmed": True}
    for role in ("viewer", "claimant", "stranger"):
        assert (await client.post(path, json=attest, headers=h(role))).status_code == 403
    assert (await client.post(path, json={**attest, "confirmed": False}, headers=h("holder"))).status_code == 422
    result = await client.post(path, json=attest, headers=h("holder"))
    assert result.status_code == 200, result.text
    assert set(result.json()) == {"listing_id", "completed_at"}
    assert (await client.post(path, json=attest, headers=h("holder"))).json() == result.json()
    assert (await client.patch(f"/v1/listings/{item}", headers=h("admin"),
                               json={"status": "active"})).status_code == 409
    assert (await client.get(f"/items/{item}/")).status_code == 404

    report = await client.get(f"{prefix}/analytics", params={"days": 30, "branch_id": str(branch.id)},
                              headers=h("holder"))
    vals = report.json()
    assert [vals[k] for k in ("registered", "on_hand", "returned", "closed_without_return",
                               "returned_in_cohort", "return_rate")] == [1, 0, 1, 1, 0, 0]
    assert (await client.get(f"{prefix}/dashboard", headers=h("holder"))).json()["returned_30d"] == 1
    assert (await client.get(f"{prefix}/analytics", params={"branch_id": str(other_branch.id)},
                             headers=h("holder"))).status_code == 404
    async with sessions() as db:
        row = await db.get(CounterReturn, UUID(item))
        assert row.actor_id == users["holder"].id and row.verification == "private_feature"
        assert len(list(await db.scalars(select(AuditEvent).where(
            AuditEvent.entity_id == UUID(item), AuditEvent.action == "listing.counter_returned"
        )))) == 1
        assert len(list(await db.scalars(select(User)))) == len(users)
        assert not list(await db.scalars(select(Handover)))


async def test_qr_completion_uses_actual_return_date_and_cannot_be_counted_again(workflow):  # noqa: F811
    client, sessions, users, h = workflow
    async with sessions() as db:
        venue = Organization(name="Вторая площадка", inn="1234567890", status="verified")
        db.add(venue)
        await db.flush()
        db.add(OrganizationMember(organization_id=venue.id, user_id=users["holder"].id, role="owner"))
        await db.commit()
    created = await client.post("/v1/listings", json=listing_body(
        organization_id=str(venue.id), publish=True, media_ids=[await photo(sessions, users["holder"])],
    ), headers=h("holder"))
    item = created.json()["id"]
    await client.post(f"/v1/admin/moderation/listings/{item}", json=APPROVAL, headers=h("admin"))
    claim = (await client.post("/v1/claims", json={"listing_id": item}, headers=h("claimant"))).json()["id"]
    path = f"/v1/claims/{claim}"
    await client.put(f"{path}/answers", json={"answers": {"Примета": "secret-zip"}}, headers=h("claimant"))
    await client.post(f"{path}/submit", headers=h("claimant"))
    decision = await client.post(f"{path}/decision", json={
        "decision": "approved", "reason": "Владение подтверждено контрольной приметой",
    }, headers=h("holder"))
    assert decision.status_code == 200, decision.text
    qr = await client.post(f"{path}/handover", json={"method": "safe_point", "place": "Стойка"},
                           headers=h("claimant"))
    assert qr.status_code == 200, qr.text
    token = qr.json()["qr_token"]
    async with sessions() as db:
        handover = await db.get(Handover, UUID(qr.json()["id"]))
        handover.created_at = datetime.now(UTC) - timedelta(days=31)
        await db.commit()

    prefix = f"/v1/organizations/{venue.id}"
    scan = "/v1/claims/handover/scan"
    assert (await client.post(scan, json={"token": token}, headers=h("holder"))).json()["completed_at"] is None
    assert (await client.get(f"{prefix}/analytics", params={"days": 30}, headers=h("holder"))).json()["returned"] == 0
    completed = await client.post(scan, json={"token": token}, headers=h("claimant"))
    assert completed.status_code == 200 and completed.json()["completed_at"]
    assert (await client.post(scan, json={"token": token}, headers=h("holder"))).json() == completed.json()
    assert (await client.get(f"{prefix}/analytics", params={"days": 30}, headers=h("holder"))).json()["returned"] == 1
    assisted = await client.post(f"{prefix}/inventory/{item}/counter-return", json={
        "verification": "ownership_evidence", "confirmed": True,
    }, headers=h("holder"))
    assert assisted.status_code == 409


async def test_additive_migration_works_on_existing_and_fresh_database(workflow):  # noqa: F811
    import importlib.util
    from pathlib import Path

    from alembic.migration import MigrationContext
    from alembic.operations import Operations
    from sqlalchemy import inspect

    _, sessions, users, _ = workflow
    async with sessions.kw["bind"].begin() as connection:
        def upgrade(sync_connection):
            path = Path(__file__).parents[1] / "alembic/versions/0006_counter_returns.py"
            spec = importlib.util.spec_from_file_location("counter_migration", path)
            module = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(module)
            CounterReturn.__table__.drop(sync_connection)
            with Operations.context(MigrationContext.configure(sync_connection)):
                module.upgrade()
                module.upgrade()
            assert inspect(sync_connection).get_pk_constraint("counter_returns")["constrained_columns"] == ["listing_id"]

        await connection.run_sync(upgrade)
    async with sessions() as db:
        assert await db.get(User, users["holder"].id) is not None
