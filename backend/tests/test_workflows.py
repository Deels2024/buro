"""Real HTTP/SQL workflows, with only queue and object storage boundaries isolated."""
import asyncio
import os
from datetime import UTC, datetime
from uuid import uuid4

import pytest
from fakeredis.aioredis import FakeRedis
from httpx import ASGITransport, AsyncClient
from sqlalchemy import select, text
from sqlalchemy.ext.asyncio import async_sessionmaker, create_async_engine

from app.core.security import create_access_token, encrypt_json
from app.db.base import Base
from app.db.models import Handover, MediaObject, Organization, OrganizationMember, User
from app.db.session import get_db
from app.main import app
from app.services import cache, traffic


@pytest.fixture
async def workflow(monkeypatch, tmp_path):
    # Concurrent requests need independent transactions. In-memory SQLite
    # shares one connection and a request rollback can undo another request.
    url = os.environ.get('TEST_DATABASE_URL', f'sqlite+aiosqlite:///{tmp_path}/workflows.db')
    engine = create_async_engine(url)
    async with engine.begin() as connection:
        if url.startswith('postgresql'):
            await connection.execute(text('CREATE EXTENSION IF NOT EXISTS vector'))
        await connection.run_sync(Base.metadata.create_all)
    sessions = async_sessionmaker(engine, expire_on_commit=False)
    async def database():
        async with sessions() as db:
            yield db
    app.dependency_overrides[get_db] = database
    fake = FakeRedis(decode_responses=True)
    monkeypatch.setattr(cache, 'redis', fake)
    monkeypatch.setattr(traffic, 'redis', fake)
    users = {}
    async with sessions() as db:
        for role in ('holder', 'claimant', 'stranger', 'admin', 'viewer'):
            user = User(phone_hash=uuid4().hex, phone_cipher=encrypt_json({'phone': '+79991234567'}), display_name=role, role='admin' if role == 'admin' else 'user')
            db.add(user)
            await db.flush()
            users[role] = user
        await db.commit()
    def headers(role):
        return {'Authorization': 'Bearer ' + create_access_token(str(users[role].id), users[role].role)}
    async with AsyncClient(transport=ASGITransport(app=app), base_url='http://test') as client:
        yield client, sessions, users, headers
    app.dependency_overrides.clear()
    await fake.aclose()
    async with engine.begin() as connection:
        await connection.run_sync(Base.metadata.drop_all)
    await engine.dispose()


async def photo(sessions, owner, purpose='listing'):
    async with sessions() as db:
        media = MediaObject(owner_id=owner.id, purpose=purpose, object_key=f'{purpose}/{owner.id}/{uuid4()}.jpg', mime_type='image/jpeg', size_bytes=100, sha256='0'*64, status='ready')
        db.add(media)
        await db.commit()
        return str(media.id)


def listing_body(**extra):
    return {'kind':'found', 'title':'Рюкзак <script>alert(1)</script>', 'description':'Чёрный рюкзак с красной молнией.', 'category':'Сумки', 'tags':[], 'hidden_features':['secret-zip'], 'public_features':[], 'event_at':datetime.now(UTC).isoformat(), 'location':{'region':'Москва','latitude':55.753,'longitude':37.615}, 'storage_code':'PRIVATE-104', **extra}


async def test_two_users_complete_return_and_private_data_stays_private(workflow):
    client, sessions, users, h = workflow
    media_id = await photo(sessions, users['holder'])
    r = await client.post('/v1/listings', json=listing_body(media_ids=[media_id]), headers=h('holder'))
    assert r.status_code == 201, r.text
    listing_id = r.json()['id']
    assert (await client.get(f'/v1/listings/{listing_id}')).status_code == 404
    assert (await client.get(f'/v1/listings/{listing_id}/manage',headers=h('stranger'))).status_code == 403
    assert (await client.patch(f'/v1/listings/{listing_id}',json={'status':'active'},headers=h('holder'))).json()['moderation_status']=='pending'
    assert (await client.post('/v1/claims',json={'listing_id':listing_id},headers=h('claimant'))).status_code==404
    r = await client.post(f'/v1/admin/moderation/listings/{listing_id}',json={'decision':'approve','reason':'Фотография и описание проверены'},headers=h('admin'))
    assert r.status_code == 200, r.text
    public=(await client.get(f'/v1/listings/{listing_id}')).json()
    assert public['category']=='bags' and public['storage_code'] is None
    assert 'hidden_features' not in public
    for category in ('bags','Сумки','Сумки и рюкзаки'):
        assert (await client.get('/v1/listings',params={'category':category})).json()['total']==1
    html=await client.get(f'/items/{listing_id}/')
    assert html.status_code==200 and '&lt;script&gt;' in html.text
    assert 'secret-zip' not in html.text and 'PRIVATE-104' not in html.text
    assert f'/items/{listing_id}/' in (await client.get('/sitemap.xml')).text
    claim=(await client.post('/v1/claims',json={'listing_id':listing_id},headers=h('claimant'))).json()
    cid=claim['id']
    assert (await client.get(f'/v1/claims/{cid}/review',headers=h('claimant'))).status_code==403
    assert (await client.get(f'/v1/claims/{cid}/review',headers=h('stranger'))).status_code==403
    assert (await client.put(f'/v1/claims/{cid}/answers',json={'answers':{'Скрытый признак':'secret-zip'}},headers=h('claimant'))).status_code==200
    proof=await photo(sessions,users['claimant'],'evidence')
    assert (await client.post(f'/v1/claims/{cid}/evidence',json={'media_id':proof,'evidence_type':'old_photo','note':'Старое фото'},headers=h('claimant'))).status_code==200
    assert (await client.post(f'/v1/claims/{cid}/submit',headers=h('claimant'))).status_code==200
    incoming=(await client.get('/v1/claims/incoming',headers=h('holder'))).json()
    assert incoming[0]['id']==cid
    review=(await client.get(f'/v1/claims/{cid}/review',headers=h('holder'))).json()
    assert review['answers']['Скрытый признак']=='secret-zip' and review['hidden_features']==['secret-zip']
    assert review['evidence'][0]['media']['id']==proof
    decision=await client.post(f'/v1/claims/{cid}/decision',json={'decision':'approved','reason':'Признаки и доказательство совпали'},headers=h('holder'))
    assert decision.status_code==200, decision.text
    conversation=(await client.get(f'/v1/claims/{cid}/conversation',headers=h('claimant'))).json()['conversation_id']
    r=await client.post(f'/v1/chat/{conversation}/messages',json={'body':'Встретимся у стойки информации'},headers=h('holder'))
    assert r.status_code==201, r.text
    assert (await client.get(f'/v1/chat/{conversation}/messages',headers=h('claimant'))).json()[0]['body']=='Встретимся у стойки информации'
    assert (await client.get(f'/v1/chat/{conversation}/messages',headers=h('stranger'))).status_code==403
    first=await client.put(f'/v1/claims/{cid}/contact-consent',json={'consent':True},headers=h('claimant'))
    assert first.json()['unlocked'] is False
    assert (await client.put(f'/v1/claims/{cid}/contact-consent',json={'consent':True},headers=h('holder'))).json()['unlocked'] is True
    handover=await client.post(f'/v1/claims/{cid}/handover',json={'method':'safe_point','place':'Стойка информации'},headers=h('claimant'))
    assert handover.status_code==200, handover.text
    token=handover.json()['qr_token']
    wrong_claim = await client.post('/v1/claims/handover/scan', json={'token':token,'claim_id':str(uuid4())}, headers=h('holder'))
    assert wrong_claim.status_code == 409
    unchanged = (await client.get(f'/v1/claims/{cid}/handover', headers=h('claimant'))).json()
    assert unchanged['holder_confirmed_at'] is None
    first=(await client.post('/v1/claims/handover/scan',json={'token':token},headers=h('holder'))).json()
    assert first['holder_confirmed_at'] and not first['completed_at']
    renewed=(await client.post(f'/v1/claims/{cid}/handover/regenerate',headers=h('claimant'))).json()
    assert renewed['holder_confirmed_at']==first['holder_confirmed_at']
    token=renewed['qr_token']
    completed, simultaneous = await asyncio.gather(
        client.post('/v1/claims/handover/scan',json={'token':token,'claim_id':cid},headers=h('claimant')),
        client.post('/v1/claims/handover/scan',json={'token':token,'claim_id':cid},headers=h('holder')),
    )
    assert completed.status_code==200 and completed.json()['completed_at'], completed.text
    assert simultaneous.status_code == 200, simultaneous.text
    repeated=await client.post('/v1/claims/handover/scan',json={'token':token},headers=h('holder'))
    assert repeated.json()['completed_at']==completed.json()['completed_at']
    assert (await client.get(f'/items/{listing_id}/')).status_code==404
    assert f'/items/{listing_id}/' not in (await client.get('/sitemap.xml')).text
    assert (await traffic.traffic_totals())['counts']['handover_completed'] == 1
    async with sessions() as db:
        assert len(list(await db.scalars(select(Handover))))==1


async def test_lost_without_photo_and_revised_content_requires_moderation(workflow):
    client,sessions,users,h=workflow
    r=await client.post('/v1/listings',json=listing_body(kind='lost',publish=True),headers=h('holder'))
    assert r.status_code==201, r.text
    lid=r.json()['id']
    assert (await client.post(f'/v1/admin/moderation/listings/{lid}',json={'decision':'approve','reason':'Описание проверено'},headers=h('admin'))).status_code==200
    assert (await client.get(f'/v1/listings/{lid}')).status_code==200
    changed=await client.patch(f'/v1/listings/{lid}',json={'description':'Новое описание с дополнительными подробностями'},headers=h('holder'))
    assert changed.json()['moderation_status']=='pending'
    assert (await client.get(f'/v1/listings/{lid}')).status_code==404
    assert (await client.get(f'/v1/listings/{lid}/manage',headers=h('holder'))).status_code==200
    bad_photo=await photo(sessions,users['claimant'],'evidence')
    assert (await client.post('/v1/listings',json=listing_body(media_ids=[bad_photo]),headers=h('holder'))).status_code==422


async def test_viewer_cannot_inspect_or_decide_claim(workflow):
    client,sessions,users,h=workflow
    async with sessions() as db:
        org=Organization(name='Проверяемая организация',inn='1234567890')
        db.add(org)
        await db.flush()
        for role in ('holder','viewer'):
            db.add(OrganizationMember(organization_id=org.id,user_id=users[role].id,role='owner' if role=='holder' else 'viewer'))
        await db.commit()
        org_id=str(org.id)
    mid=await photo(sessions,users['holder'])
    r=await client.post('/v1/listings',json=listing_body(organization_id=org_id,media_ids=[mid],publish=True),headers=h('holder'))
    lid=r.json()['id']
    await client.post(f'/v1/admin/moderation/listings/{lid}',json={'decision':'approve','reason':'Карточка проверена'},headers=h('admin'))
    cid=(await client.post('/v1/claims',json={'listing_id':lid},headers=h('claimant'))).json()['id']
    assert (await client.get(f'/v1/claims/{cid}/review',headers=h('viewer'))).status_code==403
    assert (await client.post(f'/v1/claims/{cid}/decision',json={'decision':'approved','reason':'Я наблюдатель'},headers=h('viewer'))).status_code==403
