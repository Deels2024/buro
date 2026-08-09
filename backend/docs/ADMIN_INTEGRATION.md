# Подключение веб-админки

## Базовая конфигурация

- API URL: `https://api.example.ru/v1`.
- Авторизация: `Authorization: Bearer <access_token>`.
- Для администратора после SMS может вернуться `mfa_required=true`; тогда запросите TOTP и вызовите `POST /auth/verify-admin-2fa`.
- Access token живёт 15 минут. Refresh token ротируется при каждом `/auth/refresh`.
- Каждый ответ содержит `X-Request-ID`; показывайте его оператору и прикладывайте к обращению об ошибке.
- Для повторяемых `POST`, `PUT`, `PATCH`, `DELETE` передавайте уникальный `Idempotency-Key`.

Готовый TypeScript-клиент находится в `clients/admin/bureau-api.ts`. Он синхронизирует refresh, повторяет запрос после 401 и преобразует ошибки API в `BureauApiError`.

## Разделы админки

| Раздел | Получение данных | Основные действия |
| --- | --- | --- |
| Дашборд | `GET /admin/dashboard` | быстрые очереди |
| Аналитика | `GET /admin/analytics/overview` | период, day/week/month |
| Пользователи | `GET /admin/users` | `PATCH /admin/users/{id}` |
| Организации | `GET /admin/organizations` | проверка `/admin/organizations/{id}/verify` |
| Находки и пропажи | `GET /admin/listings` | модерация `/admin/moderation/listings/{id}` |
| ИИ-совпадения | `GET /admin/matches` | статус `/listings/{id}/matches/{match_id}` |
| Заявления | `GET /admin/claims` | решение `/claims/{id}/decision` |
| Споры | `GET /admin/disputes` | `/admin/disputes/{id}/resolve` |
| Выдачи | `GET /admin/handovers` | контроль подтверждений |
| Поддержка | `GET /admin/support/tickets` | назначение и статус |
| Реклама | `/admin/ads*` | создание, пауза, статистика |
| Аудит | `GET /admin/audit` | фильтры actor/action/entity |
| Настройки | `GET /admin/settings` | `PUT /admin/settings/{key}` |
| Выгрузка | `GET /admin/exports/overview.csv` | CSV с BOM для Excel |

Все реестры используют `limit`/`offset` и возвращают `{items,total,limit,offset}`. Фильтры передаются query-параметрами; для текстовых полей используйте задержку 300–500 мс, чтобы не отправлять запрос на каждую клавишу.

## Безопасное хранение токенов

Для production-админки предпочтителен небольшой BFF: браузер получает защищённую `HttpOnly; Secure; SameSite=Strict` cookie, а BFF хранит refresh token и вызывает этот API. Если BFF пока нет, держите токены только в памяти вкладки; не сохраняйте refresh token в `localStorage`.

## Данные и графики

`/admin/analytics/overview` возвращает:

- `kpi` — новые пользователи, публикации, совпадения, заявления, подтверждения и возвраты;
- `funnel` — готовый порядок этапов;
- `series` — даты и значения lost/found;
- `categories` и `regions` — топ-12;
- `operations` — поддержка и вебхуки.

Числа считаются на сервере в одном часовом формате UTC. Интерфейс переводит даты в локальную зону оператора.

## Порядок подключения

1. Поднять backend и выполнить миграции.
2. Войти bootstrap-администратором и включить TOTP-2FA.
3. Задать API URL админки и проверить `/health/live` и `/app/bootstrap`.
4. Заменить демонстрационные массивы в админке вызовами готового клиента по таблице выше.
5. Проверить 401→refresh, 403, 422, 429 и отображение `X-Request-ID`.
6. Прогнать роли moderator/admin и заблокированного пользователя.
7. После этого отключить демо-данные и публиковать админку.
