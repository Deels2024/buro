"""Real HTTP/SQL workflows, with only queue and object storage boundaries isolated."""
import asyncio
import os
from datetime import UTC, datetime
from uuid import UUID, uuid4

import pytest
from fakeredis.aioredis import FakeRedis
from httpx import ASGITransport, AsyncClient
from sqlalchemy import select, text
from sqlalchemy.ext.asyncio import async_sessionmaker, create_async_engine

from app.core.security import create_access_token, decrypt_json, encrypt_json
from app.db.base import Base
from app.db.models import Handover, Listing, MediaObject, Organization, OrganizationMember, User
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


async def test_managed_location_round_trip_is_private_and_preserved_on_other_edits(workflow):
    client, sessions, users, h = workflow
    original = {'region': 'Москва', 'latitude': 55.753219, 'longitude': 37.615782,
                'exact_address': 'PRIVATE-ADDRESS-104'}
    created = await client.post('/v1/listings', headers=h('holder'),
                                json=listing_body(kind='lost', publish=True, location=original))
    assert created.status_code == 201, created.text
    lid = created.json()['id']
    managed = await client.get(f'/v1/listings/{lid}/manage', headers=h('holder'))
    assert managed.json()['location'] == original
    assert managed.headers['cache-control'] == 'no-store'
    assert (await client.get(f'/v1/listings/{lid}/manage', headers=h('stranger'))).status_code == 403
    assert (await client.patch(f'/v1/listings/{lid}', headers=h('stranger'),
                               json={'location': original})).status_code == 403
    unchanged = await client.patch(f'/v1/listings/{lid}', headers=h('holder'),
                                   json={'title': 'Обновлённое название рюкзака'})
    assert unchanged.json()['location'] == original
    replacement = {**original, 'latitude': 55.769321, 'longitude': 37.608912,
                   'exact_address': 'PRIVATE-ADDRESS-205'}
    updated = await client.patch(f'/v1/listings/{lid}', headers=h('holder'), json={'location': replacement})
    assert updated.status_code == 200, updated.text
    assert updated.json()['location'] == replacement
    assert updated.headers['cache-control'] == 'no-store'
    assert updated.json()['storage_code'] == 'PRIVATE-104'
    assert updated.json()['moderation_status'] == 'pending'
    reopened = await client.get(f'/v1/listings/{lid}/manage', headers=h('holder'))
    assert reopened.json()['location'] == replacement
    async with sessions() as db:
        listing = await db.get(Listing, UUID(lid))
        assert replacement['exact_address'] not in listing.exact_location_cipher
        assert decrypt_json(listing.exact_location_cipher) == replacement
    approved = await client.post(f'/v1/admin/moderation/listings/{lid}', headers=h('admin'),
                                 json={'decision': 'approve', 'reason': 'Адрес проверен'})
    assert approved.status_code == 200, approved.text
    public = (await client.get(f'/v1/listings/{lid}')).json()
    assert 'location' not in public and 'exact_address' not in public
    assert public['approx_latitude'] == round(replacement['latitude'], 2)
    assert public['approx_longitude'] == round(replacement['longitude'], 2)
    for url in (f'/v1/listings/{lid}', '/v1/listings', f'/items/{lid}/'):
        response = await client.get(url)
        assert response.status_code == 200
        assert 'PRIVATE-ADDRESS' not in response.text


async def test_manual_location_clears_old_coordinates_and_legacy_location_stays_absent(workflow):
    client, sessions, users, h = workflow
    created = await client.post('/v1/listings', headers=h('holder'), json=listing_body(kind='lost'))
    lid = created.json()['id']
    manual = {'region': 'Санкт-Петербург', 'latitude': None, 'longitude': None, 'exact_address': None}
    updated = await client.patch(f'/v1/listings/{lid}', headers=h('holder'), json={'location': manual})
    assert updated.status_code == 200, updated.text
    assert updated.json()['location'] == manual
    assert updated.json()['approx_latitude'] is None and updated.json()['approx_longitude'] is None
    async with sessions() as db:
        listing = await db.get(Listing, UUID(lid))
        listing.exact_location_cipher = None
        await db.commit()
    legacy = await client.get(f'/v1/listings/{lid}/manage', headers=h('holder'))
    assert legacy.json()['location'] is None
    renamed = await client.patch(f'/v1/listings/{lid}', headers=h('holder'),
                                 json={'title': 'Рюкзак после переименования'})
    assert renamed.json()['location'] is None


async def search_listing(sessions, owner, **changes):
    async with sessions() as db:
        listing = Listing(**{
            'owner_id': owner.id, 'kind': 'found', 'status': 'active',
            'moderation_status': 'approved', 'title': 'Чёрный рюкзак',
            'description': 'С красной молнией', 'category': 'bags',
            'tags': ['Путешествия'], 'public_features': ['Светоотражатель'],
            'event_at': datetime.now(UTC), 'published_at': datetime.now(UTC),
            'public_region': 'Санкт-Петербург',
            'storage_code': 'privatecabinet',
            'hidden_features_cipher': encrypt_json(['privateproof']),
            'exact_location_cipher': encrypt_json({'exact_address': 'privateaddress'}),
            **changes,
        })
        db.add(listing)
        await db.commit()
        return listing


async def test_public_search_tokens_filters_and_private_exclusions(workflow):
    client, sessions, users, _ = workflow
    first = await search_listing(sessions, users['holder'], title='red backpack', description='zipper', tags=['travel'], public_features=['reflector'])
    second = await search_listing(sessions, users['holder'], title='red backpack', description='zipper', kind='lost')
    for changes in ({'status':'draft'}, {'moderation_status':'pending'}, {'moderation_status':'blocked'}, {'status':'closed'}):
        await search_listing(sessions, users['holder'], title='red backpack', **changes)
    async def search(**params):
        r = await client.get('/v1/listings', params=params)
        assert r.status_code == 200, r.text
        return r.json()
    result = await search(query='backpack red')
    assert result['total'] == 2
    assert {row['id'] for row in result['items']} == {str(first.id), str(second.id)}
    for query in ('travel reflector', 'privatecabinet', 'privateproof', 'privateaddress', '%_*&|!'):
        result = await search(query=query)
        assert result['total'] == (1 if query == 'travel reflector' else 0)
    assert (await search(query='red', kind='found', category='Сумки', region='Петербург'))['total'] == 1
    assert (await search(query='red', region='%'))['total'] == 0
    assert (await search(query='red', since='2099-01-01T00:00:00Z'))['total'] == 0
    first_page = await search(query='red', limit=1)
    second_page = await search(query='red', limit=1, offset=1)
    assert first_page['total'] == second_page['total'] == 2
    assert first_page['items'][0]['id'] != second_page['items'][0]['id']
    assert 'exact_location_cipher' not in str(first_page)
    assert (await search(query='   '))['total'] == 2


@pytest.mark.skipif(not os.environ.get('TEST_DATABASE_URL', '').startswith('postgresql'), reason='Russian dictionary and GIN require PostgreSQL')
async def test_russian_search_morphology_prefix_json_and_index(workflow):
    import importlib.util

    from alembic.migration import MigrationContext
    from alembic.operations import Operations

    client, sessions, users, _ = workflow
    expected = await search_listing(sessions, users['holder'])
    await search_listing(sessions, users['holder'], title='Зонт', description='Синий зонт', category='other', tags=[], public_features=[])
    # Exercise the actual migration on existing rows; SQL generation alone cannot validate GIN immutability.
    spec = importlib.util.spec_from_file_location('search_migration', 'alembic/versions/0003_public_search.py')
    migration = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(migration)
    async with sessions() as db:
        connection = await db.connection()
        def create_index(sync_connection):
            with Operations.context(MigrationContext.configure(sync_connection)):
                migration.upgrade()
        await connection.run_sync(create_index)
        await db.commit()
    for query in ('молния красная рюкзак', 'ЧЕРНЫЙ рюкзак', 'чёрный', 'рюк', 'светоотражатели', 'путешествие', 'петербург рюкзак'):
        result = await client.get('/v1/listings', params={'query':query})
        assert result.status_code == 200, result.text
        assert [item['id'] for item in result.json()['items']] == [str(expected.id)], (query, result.text)
    # Relevance beats recency, and public JSON words are decoded rather than matching escaped Unicode.
    await search_listing(sessions, users['holder'], title='Дорожная вещь', description='Чёрный рюкзак с красной молнией')
    result = (await client.get('/v1/listings', params={'query':'чёрный рюкзак'})).json()
    assert result['total'] == 2 and result['items'][0]['id'] == str(expected.id)
    assert (await client.get('/v1/listings', params={'query':'и в на'})).status_code == 200


@pytest.mark.skipif(not os.environ.get('TEST_DATABASE_URL', '').startswith('postgresql'), reason='Cosine distance requires pgvector')
async def test_photo_search_unique_listings_and_filters(workflow):
    from datetime import timedelta

    client, sessions, users, h = workflow
    first = await search_listing(sessions, users['holder'])
    second = await search_listing(sessions, users['holder'])
    others = [await search_listing(sessions, users['holder'], **change) for change in (
        {'kind':'lost'}, {'category':'electronics'}, {'public_region':'Москва'},
        {'event_at':datetime.now(UTC)-timedelta(days=365)}, {'moderation_status':'pending'}, {'status':'draft'},
    )]
    query_id = await photo(sessions, users['claimant'])
    async with sessions() as db:
        query = await db.get(MediaObject, UUID(query_id))
        query.embedding = [1.0] + [0.0]*511
        for listing in [first, second, *others]:
            for _ in range(8 if listing.id == first.id else 1):
                db.add(MediaObject(owner_id=users['holder'].id, listing_id=listing.id, purpose='listing', object_key=uuid4().hex,
                    mime_type='image/jpeg', size_bytes=100, sha256='0'*64, status='ready',
                    embedding=([1.0, 0.0] if listing.id == first.id else [0.9, 0.1])+[0.0]*510))
        await db.commit()
    payload = {'media_id':query_id, 'target_kind':'found', 'category':'Сумки', 'region':'Петербург',
        'since':(datetime.now(UTC)-timedelta(days=7)).isoformat(), 'limit':2}
    result = await client.post('/v1/listings/ai/search', json=payload, headers=h('claimant'))
    assert result.status_code == 200, result.text
    assert [item['listing']['id'] for item in result.json()] == [str(first.id), str(second.id)]
    assert (await client.post('/v1/listings/ai/search', json=payload, headers=h('stranger'))).status_code == 404
