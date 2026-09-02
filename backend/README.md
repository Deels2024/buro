# Бюро находок — backend

Integration-ready backend единой поисковой сети пропаж и находок России. Проект рассчитан на Flutter-клиент, веб-админку, кабинеты организаций, административную модерацию и безопасную выдачу вещи подтверждённому владельцу.

## Что реализовано

- вход по SMS-коду, короткий access token и сменяемый refresh token;
- роли `user`, `operator`, `manager`, `moderator`, `admin`;
- публикации «потеряно» и «найдено», приватная и публичная геопозиция;
- прямая загрузка фото/видео в S3 без проксирования больших файлов через API;
- GPT-описание вещи по фотографии через OpenAI Responses API и Structured Outputs;
- отдельный OpenCLIP-сервис и векторный поиск через PostgreSQL/pgvector;
- объяснимый рейтинг совпадения: фото, теги, категория, дата и расстояние;
- заявление владельца, контрольные ответы и приватные доказательства;
- защищённый чат без раскрытия телефона и точного адреса;
- взаимное согласие на контакты и двухстороннее подтверждение QR-выдачи;
- кабинет организации: инвентарь, заявления, филиалы и роли команды;
- кабинет модератора: очередь публикаций, риск заявлений и проверка организаций;
- лаконичная нативная реклама только в `home_feed` и `search_results`;
- фоновые задачи, уведомления, миграции, Docker Compose и тесты.
- полный API веб-админки: пользователи, организации, реестр, совпадения, заявления, выдачи, поддержка, аудит, настройки и CSV-экспорт;
- управленческая аналитика: KPI, воронка, динамика, категории, регионы, очередь поддержки и состояние вебхуков;
- push-устройства, управление сессиями и отметки прочтения уведомлений;
- встроенная поддержка с обращениями, сообщениями, приоритетами, назначением и SLA-полями;
- TOTP-2FA для администраторов и модераторов;
- подписанные вебхуки организаций с журналом доставок и защитой от SSRF;
- публичный bootstrap-контракт приложения, `X-Request-ID` и безопасный повтор операций через `Idempotency-Key`;
- готовые клиенты `clients/admin/bureau-api.ts` и `clients/flutter/bureau_api_client.dart`.

## Стек

| Задача | Компонент |
| --- | --- |
| HTTP и WebSocket API | FastAPI, Python 3.12 |
| Основная база | PostgreSQL 16 + pgvector |
| Кэш, OTP и очередь | Redis 7 |
| Фото и видео | любое S3-совместимое хранилище |
| Описание по фото | OpenAI Responses API, заменяемый адаптер |
| Массовый визуальный поиск | OpenCLIP, отдельный CPU/GPU-контейнер |
| Миграции | Alembic |

CDN не требуется: клиент получает временные подписанные S3-ссылки. Позже CDN можно поставить перед S3, не меняя бизнес-API.

## Быстрый запуск

Нужны Docker и Docker Compose.

```bash
cp .env.example .env
docker compose up -d --build
docker compose run --rm api python scripts/seed.py
```

API будет доступен на `http://localhost:8080`, Swagger — на `http://localhost:8080/docs`, MinIO — на `http://localhost:9001`.

OpenCLIP тяжёлый и включается отдельным профилем:

```bash
docker compose --profile ai up -d --build
```

На первом старте OpenCLIP скачивает веса модели. Для закрытого production-контура положите веса в образ или подключите подготовленный cache volume.

Если вы включаете OpenAI при локальном запуске, `BN_S3_PUBLIC_ENDPOINT` должен быть доступен из интернета: облачная модель не сможет открыть ссылку вида `localhost`. В production Yandex Object Storage уже имеет внешний HTTPS endpoint.

Production-ключ OpenAI не передаётся через Compose или `.env`. Создайте защищённое GitHub Environment `production`, добавьте в него secret `BN_OPENAI_API_KEY` и вручную запустите workflow `Configure OpenAI production key`. Workflow получает одноразовый GitHub OIDC-токен, production API проверяет ключ минимальным Responses API запросом и сохраняет его в приватный Docker volume как файл с режимом `0400`.

## Первый вход

В development SMS-провайдер отключён, поэтому `POST /v1/auth/request-code` возвращает поле `dev_code`. Номер из `BN_BOOTSTRAP_ADMIN_PHONE` при первом подтверждении получает роль `admin`.

В production обязательно:

1. установите `BN_ENVIRONMENT=production`;
2. замените `BN_APP_SECRET`, задайте отдельный стабильный `BN_LOOKUP_PEPPER`, пароли БД/S3 и `BN_PII_FERNET_KEY`;
3. подключите SMS-провайдера;
4. ограничьте CORS реальными доменами;
5. отключите публичный MinIO и используйте приватный bucket;
6. храните секреты в Secret Manager, а не в `.env` внутри образа.

### SMSC

Для SMS-авторизации задайте на сервере логин и пароль из личного кабинета SMSC:

```dotenv
BN_SMSC_LOGIN=<логин SMSC>
BN_SMSC_PASSWORD=<пароль SMSC>
# Необязательно: зарегистрированное в SMSC имя отправителя.
BN_SMSC_SENDER=EDINBURO
```

После изменения переменных пересоберите `api` и `worker`:
`docker compose up -d --build --force-recreate api worker`.

## Основные API

| Контур | Маршруты |
| --- | --- |
| Авторизация | `/v1/auth/request-code`, `/verify-code`, `/refresh`, `/logout` |
| Профиль | `/v1/users/me`, `/me/notifications`, `/me/saved`, `DELETE /me` |
| Медиа | `/v1/media/presign`, `/complete` |
| Публикации | `/v1/listings`, `/mine`, `/{id}`, `/ai/describe`, `/ai/search`, `/{id}/matches` |
| Владение | `/v1/claims`, `/{id}/answers`, `/evidence`, `/submit`, `/decision` |
| Контакты и выдача | `/{id}/contact-consent`, `/contacts`, `/handover`, `/handover/scan` |
| Чат | `/v1/chat/{conversation_id}/messages`, `/ws` |
| Организации | `/v1/organizations`, `/dashboard`, `/inventory`, `/claims`, `/team` |
| Реклама | `/v1/ads/current`, `/events` |
| Модерация | `/v1/admin/dashboard`, `/moderation/listings`, `/claims/risk`, `/ads` |
| Админ-аналитика | `/v1/admin/analytics/overview`, `/exports/overview.csv` |
| Реестры админки | `/v1/admin/users`, `/organizations`, `/listings`, `/claims`, `/matches`, `/handovers` |
| Поддержка | `/v1/support/tickets`, `/v1/admin/support/tickets` |
| Интеграции | `/v1/organizations/{id}/webhooks`, `/webhook-deliveries` |
| Конфигурация приложения | `/v1/app/bootstrap` |

Полная схема запросов и ответов автоматически публикуется в OpenAPI.

Для подключения веб-админки скопируйте `clients/admin/bureau-api.ts`, задайте `baseUrl` вида `https://api.example.ru/v1` и реализуйте `TokenStore`. Для Flutter готовый клиент уже включён в архив приложения. Таблица соответствия всех разделов находится в `docs/ADMIN_INTEGRATION.md` и `docs/FLUTTER_INTEGRATION.md`.

Организационная интеграция использует заголовок `X-Organization-Key`; ключ с правом `inventory:write` может вызывать `POST /v1/organizations/{id}/external/inventory`. Исходный ключ показывается только один раз при создании.

## Загрузка медиа из Flutter

1. Flutter вызывает `POST /v1/media/presign`.
2. Приложение делает `PUT` файла напрямую по `upload_url` с указанными заголовками.
3. Flutter вычисляет SHA-256 и вызывает `POST /v1/media/complete`.
4. Worker проверяет файл, строит OpenCLIP-вектор и меняет статус на `ready`.
5. Полученный `media_id` передаётся в `POST /v1/listings` или в доказательство заявления.

## Безопасность данных

- Телефон хранится в зашифрованном виде, а для поиска используется необратимый HMAC.
- Точный адрес, скрытые признаки, ответы, доказательства и чат шифруются прикладным ключом.
- Публичные координаты округляются; точка не входит в обычный ответ публикации.
- Контакты возвращаются только после одобрения заявления и согласия обеих сторон.
- QR хранится только как HMAC; исходный код выдаётся однократно и живёт 20 минут.
- Refresh tokens хранятся только в виде HMAC и ротируются при каждом обновлении.
- Рекламное отслеживание без согласия не сохраняет идентификатор пользователя и контекст.

Перед production-запуском всё равно нужны внешний security-аудит, DPIA/модель угроз, регламент удаления данных, резервного восстановления и юридическая проверка обработки персональных данных.

## Развёртывание в Яндекс Облаке

Минимальная схема без CDN:

- Managed PostgreSQL или VM с PostgreSQL/pgvector;
- Managed Redis;
- Yandex Object Storage с приватным bucket;
- два контейнера: `api` и `worker`;
- отдельный OpenCLIP CPU/GPU-хост по мере нагрузки;
- Application Load Balancer с TLS;
- Lockbox для секретов и Cloud Logging/любая совместимая система логирования.

Для Object Storage укажите:

```env
BN_S3_ENDPOINT=https://storage.yandexcloud.net
BN_S3_PUBLIC_ENDPOINT=https://storage.yandexcloud.net
BN_S3_REGION=ru-central1
BN_S3_BUCKET=your-private-bucket
BN_S3_ACCESS_KEY=...
BN_S3_SECRET_KEY=...
```

Добавьте `storage.yandexcloud.net` в `OPENCLIP_ALLOWED_IMAGE_HOSTS`.

## Проверка

```bash
python scripts/validate_project.py
python -m compileall -q app scripts tests openclip_service
ruff check app scripts tests openclip_service
pytest -q
```

Локальный валидатор не требует запущенной базы и проверяет синтаксис, ключевые маршруты и наличие не менее 20 таблиц. Интеграционные тесты выполняйте после `docker compose up`.

## Масштабирование

Worker использует Redis AOF, processing-очередь, три попытки и dead-letter список `bureau:jobs:dead`. Перед высокой нагрузкой добавьте метрики очереди и автоматический возврат зависших processing-задач. WebSocket manager работает внутри одного API-процесса; при нескольких репликах подключите Redis Pub/Sub либо выделенный realtime gateway. Фоновое сопоставление берёт до 1000 предварительно отфильтрованных кандидатов, а прямой поиск по фотографии уже выполняет top-K оператором pgvector.

Интеграция GPT следует официальным примерам [Responses API для изображений](https://developers.openai.com/api/docs/guides/images-vision) и [Structured Outputs](https://developers.openai.com/api/docs/guides/structured-outputs). Модель задаётся через `BN_OPENAI_MODEL`, поэтому её можно менять без правки кода.
