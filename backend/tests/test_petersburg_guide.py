from xml.etree import ElementTree

from test_workflows import workflow  # noqa: F401

CITY = "/byuro-nahodok-sankt-peterburg/"


async def test_city_guide_is_public_and_useful_with_no_listings(workflow):  # noqa: F811
    client, *_ = workflow
    page = await client.get(CITY)
    assert page.status_code == 200
    assert '<meta name="robots" content="index, follow">' in page.text
    assert f'<link rel="canonical" href="https://edinburo.ru{CITY}">' in page.text
    assert "Объявлений: 0" in page.text
    assert "здесь не проверяются" in page.text
    for official in ("metro.spb.ru", "pulkovoairport.ru", "lost.fpc.ru", "ppk-piter.ru", "galeria.spb.ru", "letomall.ru"):
        assert official in page.text

    filtered = await client.get(CITY, params={"q": "несуществующая находка"})
    assert '<meta name="robots" content="noindex, follow">' in filtered.text
    assert 'id="petersburg-guide"' not in filtered.text
    assert f'{CITY}#petersburg-guide' in filtered.text
    moscow = await client.get("/byuro-nahodok-moskva/")
    assert 'id="petersburg-guide"' not in moscow.text


async def test_city_sitemap_points_to_guide_with_real_modification_date(workflow):  # noqa: F811
    client, *_ = workflow
    response = await client.get("/sitemaps/pages.xml")
    assert response.status_code == 200
    ns = {"s": "http://www.sitemaps.org/schemas/sitemap/0.9"}
    root = ElementTree.fromstring(response.content)
    urls = {
        u.findtext("s:loc", namespaces=ns): u.findtext("s:lastmod", namespaces=ns)
        for u in root.findall("s:url", ns)
    }
    assert urls["https://edinburo.ru" + CITY] == "2026-11-27"
    assert len(urls) == 8
    assert "https://edinburo.ru/app/" not in urls
