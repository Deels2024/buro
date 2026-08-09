# Подключение Flutter-клиента

## Конфигурация

В Flutter задайте один `baseUrl`, например `https://api.buronahodok.ru/v1`. Access token передавайте как `Authorization: Bearer <token>`. Refresh token храните только в Keychain/Android Keystore и не пишите в логи.

## Переходы экранов в API

| Flutter-сценарий | API |
| --- | --- |
| Вход и SMS | `POST /auth/request-code`, `POST /auth/verify-code` |
| Конфигурация и feature flags | `GET /app/bootstrap` |
| Главная и поиск | `GET /listings` |
| Поиск по фотографии | загрузка media → `POST /listings/ai/describe` и `POST /listings/ai/search` |
| Создание пропажи/находки | media presign/complete → `POST /listings` |
| Центр совпадений | `GET /listings/{id}/matches` |
| Подтверждение владельца | `POST /claims`, answers, evidence, submit |
| Решение нашедшего/организации | `POST /claims/{id}/decision` |
| Защищённый чат | HTTP history/send + WebSocket updates |
| Раскрытие контактов | `PUT /claims/{id}/contact-consent`, затем `GET /contacts` |
| QR-передача | `POST /claims/{id}/handover`, обе стороны вызывают `/handover/scan` |
| Кабинет организации | `/organizations/{id}/dashboard`, `/inventory`, `/claims`, `/team` |
| Модератор | `/admin/*` |
| Нативная реклама | `GET /ads/current?placement=home_feed|search_results` |
| Push-устройство | `PUT /users/me/devices`, удаление при logout |
| Уведомления | `/users/me/notifications`, `/read`, `/read-all` |
| Поддержка | `/support/tickets`, сообщения обращения |
| Активные сессии | `/users/me/sessions`, удаление сессии |

## Обновление токена

При HTTP 401 выполните один синхронизированный `POST /auth/refresh`, сохраните новую пару токенов и повторите исходный запрос один раз. Не запускайте параллельное обновление из каждого запроса.

Готовая реализация находится в `clients/flutter/bureau_api_client.dart` и уже добавлена в Flutter-архив. Реализацию `BureauTokenStore` подключите к Keychain/Android Keystore через `flutter_secure_storage`.

## WebSocket

Сначала получите одноразовый билет через `POST /chat/{conversation_id}/ticket`, затем подключитесь к `wss://api.example/v1/chat/{conversation_id}/ws?ticket=<ticket>`. Билет живёт 60 секунд и удаляется при первом использовании, поэтому access token не попадает в URL и журналы прокси. Историю и отправку сообщений делайте через HTTP; WebSocket предназначен для мгновенных событий и heartbeat `ping/pong`.

## Ошибки

FastAPI возвращает `{"detail": "..."}`. Клиенту следует отдельно обрабатывать 401, 403, 409, 413, 422 и 429. Каждый ответ содержит `X-Request-ID`.

Для повторяемых `POST`, `PUT`, `PATCH`, `DELETE` используйте случайный `Idempotency-Key` длиной 8–128 символов. Сервер хранит результат 24 часа: повтор запроса с тем же телом вернёт прежний ответ, а с другим телом — 409. Это особенно важно для создания публикации, заявления, выдачи и обращения поддержки.
