import importlib.util
import json
from datetime import UTC, datetime
from pathlib import Path
from xml.etree import ElementTree

import pytest
from test_auth_sessions import add_user
from test_auth_sessions import session_app as session_app

from app.api import public_site
from app.db.models import Listing

spec = importlib.util.spec_from_file_location("notify_search", Path(__file__).resolve().parents[2] / "scripts/notify-search.py")
search = importlib.util.module_from_spec(spec)
spec.loader.exec_module(search)


async def test_sitemap_shards_include_only_approved_active_listings(session_app, monkeypatch):
    client, sessions, _ = session_app
    user = await add_user(sessions)
    monkeypatch.setattr(public_site, "SITEMAP_SIZE", 1)
    async with sessions() as db:
        listings = [Listing(owner_id=user.id, kind="found", status=status, moderation_status=moderation,
                            title="Вещь", description="Описание", category="other", public_region="Москва",
                            event_at=datetime.now(UTC)) for status, moderation in
                    [("active", "approved"), ("active", "auto_approved"), ("draft", "approved"), ("active", "pending")]]
        db.add_all(listings)
        await db.commit()
        expected = {str(row.id) for row in listings[:2]}
    root = ElementTree.fromstring((await client.get("/sitemap.xml")).text)
    paths = [node.text.replace(search.ORIGIN, "") for node in root.findall("s:sitemap/s:loc", search.NS)]
    assert paths == ["/sitemaps/pages.xml", "/sitemaps/items-1.xml", "/sitemaps/items-2.xml"]
    found = set()
    for path in paths[1:]:
        root = ElementTree.fromstring((await client.get(path)).text)
        found.update(node.text.split("/")[-2] for node in root.findall("s:url/s:loc", search.NS))
    assert found == expected
    assert (await client.get("/sitemaps/items-0.xml")).status_code == 404
    key = (await client.get("/indexnow-key.txt")).text
    assert len(key) == 64 and key != public_site.get_settings().app_secret


def sitemap(urls):
    return '<urlset xmlns="' + search.NS['s'] + '">' + ''.join(
        f'<url><loc>{url}</loc><lastmod>{modified}</lastmod></url>' for url, modified in urls.items()) + '</urlset>'


def test_notification_tracks_changes_removals_and_does_not_repeat(tmp_path):
    path = tmp_path / "state.json"
    old = {search.ORIGIN + "/": "", search.ORIGIN + "/items/old/": "1"}
    new = {search.ORIGIN + "/": "", search.ORIGIN + "/items/new/": "2"}
    path.write_text(json.dumps(old))
    submissions = []

    def fetch(url, payload=None):
        if payload:
            submissions.append(payload)
            return 202, ""
        return (200, "a" * 64) if url.endswith(".txt") else (200, sitemap(new))

    search.notify(path, fetcher=fetch)
    assert submissions[0]["urlList"] == [search.ORIGIN + "/items/new/", search.ORIGIN + "/items/old/"]
    search.notify(path, fetcher=fetch)
    assert len(submissions) == 1


def test_failed_notification_keeps_state_for_retry(tmp_path):
    path = tmp_path / "state.json"
    path.write_text("{}")

    def fetch(url, payload=None):
        if payload:
            return 429, ""
        return (200, "a" * 64) if url.endswith(".txt") else (200, sitemap({search.ORIGIN + "/": ""}))

    with pytest.raises(ValueError, match="429"):
        search.notify(path, fetcher=fetch)
    assert path.read_text() == "{}"


def test_private_or_incomplete_sitemap_is_never_submitted():
    for urls in [{search.ORIGIN + "/app/": ""}, {search.ORIGIN + "/items/one/": ""}]:
        with pytest.raises(ValueError):
            search.collect_sitemap(lambda url, urls=urls: (200, sitemap(urls)))
