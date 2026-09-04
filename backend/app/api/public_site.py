"""Accessible, server-rendered public pages; private workflows stay in /app/."""
import json
from html import escape
from urllib.parse import urlencode
from uuid import UUID

from fastapi import APIRouter, HTTPException, Query, Request
from fastapi.responses import HTMLResponse, RedirectResponse, Response
from sqlalchemy import func, or_, select
from sqlalchemy.orm import selectinload

from app.api.deps import DB
from app.db.models import Listing, MediaObject
from app.services.categories import CATEGORIES, category_values, normalize_category
from app.services.storage import storage
from app.services.traffic import record_event

router = APIRouter(include_in_schema=False)
ORIGIN = "https://edinburo.ru"
PUBLIC = (Listing.status == "active", Listing.moderation_status.in_(["approved", "auto_approved"]))
GUIDES = {
    "/poteryal-veshch/": "Что делать, если потерял вещь",
    "/nashel-veshch/": "Что делать, если нашёл вещь",
    "/naydennye-veshchi/": "Найденные вещи",
    "/poteryannye-veshchi/": "Потерянные вещи",
    "/byuro-nahodok-moskva/": "Бюро находок Москвы",
    "/byuro-nahodok-sankt-peterburg/": "Бюро находок Санкт-Петербурга",
}
CSS = """
:root{--ink:#14263d;--muted:#52657b;--blue:#174de0;--line:#dce3ee;--bg:#f5f7fb;--green:#087c55}
*{box-sizing:border-box}body{margin:0;color:var(--ink);font:16px/1.65 system-ui,-apple-system,sans-serif;background:var(--bg)}
a{color:var(--blue);text-underline-offset:3px}a:hover{text-decoration:underline}a:focus-visible,button:focus-visible,input:focus-visible,select:focus-visible{outline:3px solid #ffbc42;outline-offset:4px}
.skip{position:absolute;top:-80px}.skip:focus{top:8px;left:8px;background:white;z-index:10;padding:12px}
header{background:#fff;border-bottom:1px solid var(--line)}.nav{max-width:1200px;margin:auto;display:flex;align-items:center;gap:24px;padding:18px 24px;flex-wrap:wrap}.brand{font-weight:800;font-size:21px;color:var(--ink);text-decoration:none}.nav nav{display:flex;gap:20px;flex:1;flex-wrap:wrap}.nav nav a{text-decoration:none}.button,button{display:inline-block;padding:11px 20px;border:1px solid var(--blue);border-radius:12px;background:var(--blue);color:#fff;font:inherit;font-weight:650;text-decoration:none;cursor:pointer}.button.secondary{background:#fff;color:var(--blue)}main{max-width:1200px;padding:32px 24px 64px;margin:auto}.hero{padding:48px 0 32px;max-width:860px}.eyebrow{font-size:14px;font-weight:750;color:var(--green);letter-spacing:.04em}h1{font-size:clamp(32px,5vw,56px);line-height:1.12;letter-spacing:-.035em;margin:16px 0 24px}h2{font-size:27px;line-height:1.3;margin:36px 0 20px}h3{font-size:20px;line-height:1.35;margin:8px 0}.lead{font-size:20px;color:var(--muted);max-width:760px}.actions{display:flex;gap:12px;flex-wrap:wrap;margin:24px 0}.search{display:grid;grid-template-columns:2fr 1fr 1fr auto;gap:12px;background:white;padding:20px;border-radius:16px;border:1px solid var(--line);align-items:end}label{display:block;font-size:14px;font-weight:650}input,select,textarea{display:block;width:100%;padding:12px;border:1px solid #9eafc4;border-radius:9px;background:#fff;color:var(--ink);font:inherit;margin-top:6px;min-width:0}.grid{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:20px}.card{background:#fff;border:1px solid var(--line);border-radius:16px;overflow:hidden}.card .text{padding:20px}.card img,.placeholder{width:100%;height:215px;object-fit:cover;background:#e9eef7}.placeholder{display:grid;place-content:center;color:var(--muted)}.card h3 a{color:var(--ink);text-decoration:none}.meta{color:var(--muted);font-size:14px}.tag{font-size:13px;color:var(--green);font-weight:700}.empty,.note{padding:24px;border:1px solid var(--line);background:#fff;border-radius:16px}.steps{counter-reset:step}.steps article{padding:24px}.steps article::before{counter-increment:step;content:counter(step);display:grid;place-items:center;width:36px;height:36px;border-radius:50%;background:#e8efff;color:var(--blue);font-weight:800}.detail{display:grid;grid-template-columns:minmax(0,1.25fr) minmax(300px,1fr);gap:32px}.gallery{display:grid;gap:16px}.gallery img{max-width:100%;max-height:650px;border-radius:16px;object-fit:contain;background:#fff}.description{white-space:pre-wrap;overflow-wrap:anywhere}.breadcrumbs{font-size:14px;display:flex;gap:10px;flex-wrap:wrap}.pager{display:flex;gap:16px;align-items:center;margin:28px 0}footer{background:#e9eef7;padding:32px 24px}.footer{max-width:1152px;margin:auto;display:flex;gap:24px;justify-content:space-between;flex-wrap:wrap}.footer nav{display:flex;gap:16px;flex-wrap:wrap}.map{width:100%;height:320px;border:0;border-radius:14px}details{padding:16px 0;border-bottom:1px solid var(--line)}summary{cursor:pointer;font-weight:650}
@media(max-width:850px){.grid{grid-template-columns:repeat(2,minmax(0,1fr))}.search{grid-template-columns:1fr 1fr}.detail{grid-template-columns:1fr}.hero{padding-top:22px}}
@media(max-width:520px){main{padding:24px 16px 40px}.nav{gap:12px;padding:16px}.nav nav{order:3;width:100%;flex-basis:100%;gap:14px;font-size:14px}.nav>.button{margin-left:auto}.grid,.search{grid-template-columns:1fr}h1{font-size:36px}.lead{font-size:18px}.button{padding:10px 14px}.card img,.placeholder{height:220px}.hero{padding-top:10px}}
"""


def page(title: str, description: str, path: str, body: str, *, noindex: bool = False, schema: dict | None = None, status: int = 200) -> HTMLResponse:
    structured = schema or {"@context": "https://schema.org", "@type": "WebPage", "name": title, "url": ORIGIN + path, "inLanguage": "ru"}
    data = json.dumps(structured, ensure_ascii=False).replace("<", "\\u003c")
    html = f'''<!doctype html><html lang="ru"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>{escape(title)} | Бюро находок</title><meta name="description" content="{escape(description)}"><meta name="robots" content="{'noindex, follow' if noindex else 'index, follow'}">
<link rel="canonical" href="{ORIGIN}{escape(path)}"><meta property="og:title" content="{escape(title)}"><meta property="og:description" content="{escape(description)}"><meta property="og:url" content="{ORIGIN}{escape(path)}"><meta property="og:type" content="website"><meta property="og:image" content="{ORIGIN}/og-image.png">
<link rel="icon" href="/favicon.svg" type="image/svg+xml"><link rel="stylesheet" href="/public.css"><script type="application/ld+json">{data}</script></head><body>
<a class="skip" href="#content">К содержанию</a><header><div class="nav"><a class="brand" href="/">Бюро находок</a><nav aria-label="Основная навигация"><a href="/naydennye-veshchi/">Находки</a><a href="/poteryannye-veshchi/">Пропажи</a><a href="/organizations/">Организациям</a></nav><a class="button secondary" href="/app/">Личный кабинет</a></div></header>
<main id="content">{body}</main><footer><div class="footer"><span>Бюро находок · Помогаем вещам вернуться домой</span><nav aria-label="Справка"><a href="/poteryal-veshch/">Потеряли вещь?</a><a href="/nashel-veshch/">Нашли вещь?</a><a href="/app/?action=support">Поддержка</a></nav></div></footer></body></html>'''
    return HTMLResponse(html, status_code=status, headers={"X-Content-Type-Options": "nosniff", "Referrer-Policy": "strict-origin-when-cross-origin", "Cache-Control": "no-cache"})


def cards(items: list[Listing]) -> str:
    if not items:
        return '<div class="empty"><h3>Пока нет подходящих объявлений</h3><p>Попробуйте другой запрос или город. Оставьте описание пропажи — к поиску смогут подключиться другие люди.</p><a class="button" href="/app/?action=lost">Сообщить о пропаже</a></div>'
    result = []
    for item in items:
        photo = next((m for m in item.media if m.status == "ready" and m.mime_type.startswith("image/")), None)
        visual = f'<img src="/items/{item.id}/photo/{photo.id}" alt="{escape(item.title)}" loading="lazy" width="360" height="215">' if photo else '<div class="placeholder">Фотография не добавлена</div>'
        kind = "Найдена вещь" if item.kind == "found" else "Ищут владельца пропажи"
        if item.kind == "lost":
            kind = "Потеряна вещь"
        result.append(f'<article class="card"><a href="/items/{item.id}/" tabindex="-1" aria-hidden="true">{visual}</a><div class="text"><span class="tag">{kind}</span><h3><a href="/items/{item.id}/">{escape(item.title)}</a></h3><p class="meta">{escape(item.public_region)} · {item.event_at:%d.%m.%Y}</p><p>{escape(item.description[:140])}{"…" if len(item.description)>140 else ""}</p></div></article>')
    return '<div class="grid">' + ''.join(result) + '</div>'


async def select_listings(db: DB, filters: list, limit: int, offset: int = 0) -> list[Listing]:
    return list(await db.scalars(select(Listing).where(*PUBLIC, *filters).options(selectinload(Listing.media)).order_by(Listing.published_at.desc(), Listing.id).limit(limit).offset(offset)))


@router.get("/public.css")
async def stylesheet() -> Response:
    return Response(CSS, media_type="text/css", headers={"Cache-Control": "public, max-age=3600"})


@router.get("/")
async def home(db: DB) -> HTMLResponse:
    await record_event("home")
    items = await select_listings(db, [], 6)
    body = '''<section class="hero"><span class="eyebrow">ПОТЕРЯЛИ ИЛИ НАШЛИ ВЕЩЬ?</span><h1>Поможем найти.<br>Поможем вернуть.</h1><p class="lead">Объявления о пропажах и находках, проверка владельца и безопасная передача. Поиск открыт для всех — войти понадобится, когда захотите откликнуться или добавить вещь.</p><div class="actions"><a class="button" href="/naydennye-veshchi/">Ищу свою вещь</a><a class="button secondary" href="/app/?action=found">Я нашёл вещь</a></div></section>
<form class="search" action="/naydennye-veshchi/" method="get"><label>Что потеряли?<input name="q" placeholder="Например, чёрный рюкзак" maxlength="200"></label><label>Город или район<input name="region" placeholder="Вся Россия" maxlength="180"></label><label>Категория<select name="category"><option value="">Все категории</option>'''
    body += ''.join(f'<option value="{code}">{label}</option>' for code, label in CATEGORIES.items())
    body += '</select></label><button type="submit">Найти</button></form><h2>Последние объявления</h2>' + cards(items)
    body += '''<h2>От поиска до возвращения</h2><div class="grid steps"><article class="card"><h3>Найдите похожую вещь</h3><p>Сравните описание, место и дату. Если совпадения нет, создайте объявление о пропаже.</p></article><article class="card"><h3>Подтвердите владение</h3><p>Ответьте на вопросы о деталях вещи. Старое фото или чек помогут держателю проверить заявку.</p></article><article class="card"><h3>Договоритесь о передаче</h3><p>Обсудите встречу в чате. Контакты открываются по взаимному согласию; передачу подтверждают обе стороны.</p></article></div>
<h2>Частые вопросы</h2><details><summary>Нужна ли регистрация для поиска?</summary><p>Нет. Смотреть каталог и карточки можно без входа. SMS-вход нужен для публикации, заявок и переписки.</p></details><details><summary>Что нельзя указывать в объявлении?</summary><p>Не публикуйте номера документов, полный адрес, телефон и скрытые признаки, по которым можно проверить владельца. Для таких деталей предусмотрены закрытые поля и чат.</p></details><details><summary>Что делать, если требуют предоплату?</summary><p>Не переводите деньги за обещание вернуть вещь. Сохраните переписку и обратитесь в поддержку через личный кабинет.</p></details>'''
    return page("Поиск потерянных и найденных вещей", "Найдите потерянную вещь или помогите вернуть находку владельцу. Открытый каталог по городам, проверка заявок и чат для передачи.", "/", body, schema={"@context":"https://schema.org", "@type":"WebSite", "name":"Бюро находок", "url":ORIGIN+"/", "inLanguage":"ru"})


@router.get("/naydennye-veshchi/")
@router.get("/poteryannye-veshchi/")
@router.get("/byuro-nahodok-moskva/")
@router.get("/byuro-nahodok-sankt-peterburg/")
async def catalogue(request: Request, db: DB, q: str = Query("", max_length=200), region: str = Query("", max_length=180), category: str = Query("", max_length=80), p: int = Query(1, ge=1, le=10000)) -> HTMLResponse:
    await record_event("search")
    path = request.url.path
    city = {"/byuro-nahodok-moskva/": "Москва", "/byuro-nahodok-sankt-peterburg/": "Санкт-Петербург"}.get(path)
    region = city or region.strip()
    kind = "lost" if path == "/poteryannye-veshchi/" else "found"
    filters = [Listing.kind == kind]
    if q.strip():
        filters.append(or_(Listing.title.ilike(f"%{q.strip()}%"), Listing.description.ilike(f"%{q.strip()}%")))
    if region:
        filters.append(Listing.public_region.ilike(f"%{region}%"))
    if category:
        filters.append(func.lower(Listing.category).in_(category_values(category)))
    total = await db.scalar(select(func.count(Listing.id)).where(*PUBLIC, *filters)) or 0
    items = await select_listings(db, filters, 24, (p-1)*24)
    title = GUIDES[path]
    desc = f"{title}: реальные объявления с описанием, фотографиями, местом и датой. Сравните признаки и свяжитесь с держателем через проверку заявки."
    options = '<option value="">Все категории</option>' + ''.join(f'<option value="{code}" {"selected" if code == category else ""}>{label}</option>' for code,label in CATEGORIES.items())
    body = f'<nav class="breadcrumbs"><a href="/">Главная</a><span> / {title}</span></nav><h1>{title}</h1><p class="lead">{desc}</p><form class="search" method="get"><label>Название или примета<input name="q" value="{escape(q)}" maxlength="200"></label><label>Город<input name="region" value="{escape(region)}" maxlength="180" {"readonly" if city else ""}></label><label>Категория<select name="category">{options}</select></label><button>Найти</button></form><p class="meta">Объявлений: {total}. Страница {p}.</p>' + cards(items)
    params = {"q":q, "region":region, "category":category}
    body += '<nav class="pager" aria-label="Страницы каталога">'
    if p>1:
        body += f'<a href="?{escape(urlencode({**params,"p":p-1}))}" rel="prev">← Предыдущая</a>'
    if p*24<total:
        body += f'<a href="?{escape(urlencode({**params,"p":p+1}))}" rel="next">Следующая →</a>'
    body += '</nav><div class="note"><h2>Нет вашей вещи?</h2><p>Добавьте описание пропажи. Укажите место, примерную дату и приметы, а уникальные детали оставьте для проверки владельца.</p><a class="button" href="/app/?action=lost">Сообщить о пропаже</a></div>'
    canonical = path + (f"?p={p}" if p>1 else "")
    return page(title + (f" — страница {p}" if p>1 else ""), desc, canonical, body, noindex=bool(q or category or (region and not city) or (not items and p>1)))


@router.get("/items/{listing_id}/")
async def item_page(listing_id: UUID, db: DB) -> HTMLResponse:
    items = await select_listings(db, [Listing.id == listing_id], 1)
    if not items:
        return page("Объявление недоступно", "Публикация закрыта или ещё проверяется.", f"/items/{listing_id}/", '<h1>Объявление недоступно</h1><p>Возможно, вещь уже вернулась владельцу или публикация ещё проверяется.</p><a class="button" href="/naydennye-veshchi/">Перейти к поиску</a>', noindex=True, status=404)
    await record_event("listing_view")
    item = items[0]
    photos = [m for m in item.media if m.status == "ready" and m.mime_type.startswith("image/")]
    gallery = ''.join(f'<img src="/items/{item.id}/photo/{m.id}" alt="{escape(item.title)} — фото {i+1}" width="700" loading="lazy">' for i,m in enumerate(photos)) or '<div class="placeholder">Фотография не добавлена</div>'
    found = item.kind == "found"
    action = f'/app/?{urlencode({"action":"claim" if found else "listing", "listing":str(item.id)})}'
    body = f'<nav class="breadcrumbs"><a href="/">Главная</a><a href="/{"naydennye" if found else "poteryannye"}-veshchi/"> / {"Находки" if found else "Пропажи"}</a></nav><h1>{escape(item.title)}</h1><div class="detail"><div class="gallery">{gallery}</div><section><span class="tag">{"Найдено" if found else "Потеряно"} · {CATEGORIES[normalize_category(item.category)]}</span><p>{escape(item.public_region)} · {item.event_at:%d.%m.%Y}</p><p class="description">{escape(item.description)}</p><div class="actions"><a class="button" href="{escape(action)}">{"Это может быть моё" if found else "Открыть объявление в кабинете"}</a></div><p class="meta">{"Потребуется вход по SMS и подтверждение признаков вещи." if found else "Нашли похожую вещь? Добавьте находку — мы сравним объявления."}</p><a href="/app/?action=found">Сообщить о находке</a></section></div>'
    if item.approx_latitude is not None and item.approx_longitude is not None:
        lat, lon = item.approx_latitude, item.approx_longitude
        url = 'https://www.openstreetmap.org/export/embed.html?' + urlencode({"bbox":f"{lon-.02},{lat-.015},{lon+.02},{lat+.015}", "layer":"mapnik", "marker":f"{lat},{lon}"})
        body += f'<h2>Примерное место</h2><p class="meta">Точка округлена для конфиденциальности. Карта OpenStreetMap загружается при раскрытии.</p><details><summary>Показать на карте</summary><iframe class="map" title="Примерное место" loading="lazy" referrerpolicy="no-referrer" src="{escape(url)}"></iframe><a href="https://www.openstreetmap.org/copyright">© OpenStreetMap</a></details>'
    return page(item.title, f'{"Найдено" if found else "Потеряно"}: {item.title}. {item.public_region}. {item.description[:180]}', f"/items/{item.id}/", body, schema={"@context":"https://schema.org", "@type":"WebPage", "name":item.title, "description":item.description[:500], "url":f"{ORIGIN}/items/{item.id}/", "dateModified":item.updated_at.isoformat(), "image":[f"{ORIGIN}/items/{item.id}/photo/{m.id}" for m in photos], "inLanguage":"ru"})


@router.get("/items/{listing_id}/photo/{media_id}")
async def public_photo(listing_id: UUID, media_id: UUID, db: DB) -> RedirectResponse:
    media = await db.scalar(select(MediaObject).join(Listing, Listing.id == MediaObject.listing_id).where(*PUBLIC, Listing.id == listing_id, MediaObject.id == media_id, MediaObject.status == "ready", MediaObject.purpose == "listing", MediaObject.mime_type.like("image/%")))
    if not media:
        raise HTTPException(404, "Фотография недоступна")
    return RedirectResponse(storage.presign_download(media.object_key), status_code=307, headers={"Cache-Control":"no-store"})


@router.get("/organizations/")
async def organizations() -> HTMLResponse:
    body = '''<span class="eyebrow">ДЛЯ ТОРГОВЫХ ЦЕНТРОВ, ТРАНСПОРТА И ПЛОЩАДОК</span><h1>Бюро находок<br>для вашей организации</h1><p class="lead">Ведите единый учёт найденных вещей, проверяйте заявки владельцев и фиксируйте передачу. Сотрудники работают в одном кабинете с разграничением ролей.</p><div class="actions"><a class="button" href="/app/?action=organization">Подключить организацию</a><a class="button secondary" href="/app/?action=support">Обсудить подключение</a></div><div class="grid steps"><article class="card"><h3>Учёт находок</h3><p>Фотографии, описание, филиал и место хранения. Скрытые признаки доступны сотрудникам для проверки владельца.</p></article><article class="card"><h3>Проверка заявок</h3><p>Ответы, доказательства и переписка в карточке заявления. Решение принимает уполномоченный сотрудник.</p></article><article class="card"><h3>Контроль передачи</h3><p>QR-код и подтверждение двух сторон помогают зафиксировать возвращение вещи.</p></article></div><h2>Как начать</h2><p>Войдите по телефону, создайте организацию, заполните реквизиты и дождитесь проверки. После подключения добавьте филиалы и сотрудников. Вопросы об условиях и интеграции отправьте в поддержку.</p>'''
    return page("Бюро находок для организаций", "Учёт находок, проверка заявок и передача вещей для организаций. Единый кабинет, роли сотрудников, филиалы и история решений.", "/organizations/", body)


@router.get("/robots.txt")
async def robots() -> Response:
    return Response(f"User-agent: *\nAllow: /\nDisallow: /app/\nDisallow: /v1/\nDisallow: /admin\nDisallow: /api/\nDisallow: /docs\nDisallow: /redoc\nDisallow: /openapi.json\nSitemap: {ORIGIN}/sitemap.xml\n", media_type="text/plain")


@router.get("/sitemap.xml")
async def sitemap(db: DB) -> Response:
    rows = await db.execute(select(Listing.id, Listing.updated_at).where(*PUBLIC).order_by(Listing.updated_at.desc()).limit(49000))
    urls = [("/", None), *((path,None) for path in GUIDES), ("/organizations/",None)]
    urls.extend((f"/items/{item_id}/", modified.isoformat()) for item_id, modified in rows)
    content = '<?xml version="1.0" encoding="UTF-8"?><urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">' + ''.join(f'<url><loc>{ORIGIN}{path}</loc>'+(f'<lastmod>{modified}</lastmod>' if modified else '')+'</url>' for path,modified in urls) + '</urlset>'
    return Response(content, media_type="application/xml", headers={"Cache-Control":"no-cache"})
