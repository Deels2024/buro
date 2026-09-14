#!/usr/bin/env python3
"""Notify IndexNow of public sitemap changes; retain state only after acceptance."""
import argparse
import json
import re
from pathlib import Path
from urllib.parse import urlsplit
from urllib.request import Request, urlopen
from xml.etree import ElementTree

ORIGIN = "https://edinburo.ru"
NS = {"s": "http://www.sitemaps.org/schemas/sitemap/0.9"}


def public_url(url):
    parsed = urlsplit(url)
    return (parsed.scheme == "https" and parsed.netloc == "edinburo.ru"
            and not parsed.query and not parsed.fragment
            and not parsed.path.startswith(("/app", "/v1", "/api", "/admin")))


def fetch(url, payload=None):
    if not public_url(url) and url != "https://api.indexnow.org/indexnow":
        raise ValueError("Untrusted URL")
    request = Request(url, data=json.dumps(payload).encode() if payload else None,
                      headers={"User-Agent": "Bureau-Search/1.0", "Content-Type": "application/json"})
    with urlopen(request, timeout=30) as response:  # nosec B310 -- HTTPS hosts validated above
        data = response.read(8 * 1024 * 1024 + 1)
        if len(data) > 8 * 1024 * 1024:
            raise ValueError("Response too large")
        return response.status, data.decode("utf-8")


def collect_sitemap(fetcher=fetch):
    pending = [ORIGIN + "/sitemap.xml"]
    visited = set()
    urls = {}
    while pending:
        url = pending.pop()
        if url in visited:
            continue
        if not public_url(url) or len(visited) >= 50001:
            raise ValueError("Invalid sitemap tree")
        visited.add(url)
        status, body = fetcher(url)
        if status != 200:
            raise ValueError("Sitemap unavailable")
        root = ElementTree.fromstring(body)
        if root.tag == "{" + NS["s"] + "}sitemapindex":
            pending.extend(node.text or "" for node in root.findall("s:sitemap/s:loc", NS))
        elif root.tag == "{" + NS["s"] + "}urlset":
            for node in root.findall("s:url", NS):
                location = node.findtext("s:loc", default="", namespaces=NS)
                if not public_url(location):
                    raise ValueError("Non-public sitemap URL")
                urls[location] = node.findtext("s:lastmod", default="", namespaces=NS)
        else:
            raise ValueError("Unexpected sitemap document")
    if ORIGIN + "/" not in urls:
        raise ValueError("Incomplete sitemap; refusing removal notifications")
    return urls


def changes(previous, current):
    return sorted({url for url, modified in current.items() if previous.get(url) != modified}
                  | (previous.keys() - current.keys()))


def notify(state_path, dry_run=False, fetcher=fetch):
    previous = json.loads(state_path.read_text()) if state_path.exists() else {}
    if not isinstance(previous, dict) or any(not public_url(url) for url in previous):
        raise ValueError("Invalid previous sitemap state")
    current = collect_sitemap(fetcher)
    changed = changes(previous, current)
    if not dry_run and changed:
        status, key = fetcher(ORIGIN + "/indexnow-key.txt")
        key = key.strip()
        if status != 200 or not re.fullmatch(r"[a-f0-9]{64}", key):
            raise ValueError("IndexNow verification file unavailable")
        for start in range(0, len(changed), 10000):
            status, _ = fetcher("https://api.indexnow.org/indexnow", {
                "host": "edinburo.ru", "key": key,
                "keyLocation": ORIGIN + "/indexnow-key.txt", "urlList": changed[start:start + 10000],
            })
            if status not in (200, 202):
                raise ValueError(f"IndexNow rejected notification: {status}")
    if not dry_run:
        state_path.parent.mkdir(parents=True, exist_ok=True)
        temporary = state_path.with_suffix(".tmp")
        temporary.write_text(json.dumps(current, ensure_ascii=False))
        temporary.replace(state_path)
    print(json.dumps({"public_pages": len(current), "changed_pages": len(changed), "dry_run": dry_run}))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--state", type=Path, default=Path(".search-state/sitemap.json"))
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()
    notify(args.state, args.dry_run)
