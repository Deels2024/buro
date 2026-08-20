# Бюро находок — единый установочный комплект

В комплекте находятся:

- FastAPI backend и фоновый worker;
- PostgreSQL + pgvector;
- Redis;
- MinIO для фотографий и файлов;
- пользовательский Flutter Web, подключённый к реальным API;
- отдельная веб-админка, подключённая к реальным API;
- Nginx как единая точка входа;
- Flutter-приложение на 67 экранов с готовым API-клиентом;
- OpenAPI-контракт, миграции и начальные данные.

## Запуск одной командой

Требуются Docker Engine, Docker Compose 2.20+ и OpenSSL.

```bash
chmod +x install.sh scripts/check.sh
./install.sh
```

Установщик:

1. создаст локальный `.env`;
2. сгенерирует отдельные случайные ключи и пароли;
3. соберёт контейнеры;
4. применит миграции;
5. создаст начальные данные и первого администратора;
6. запустит весь комплекс.
7. дождётся готовности сервисов и в режиме development выполнит сквозную
   проверку входа администратора и доступа к dashboard API.

После запуска в production:

- пользовательский сайт: `https://edinburo.ru`;
- админка: `https://admin.edinburo.ru`;
- API: `https://edinburo.ru/v1`;
- Swagger: `https://edinburo.ru/docs`;
- MinIO API: `http://localhost:9000`;
- MinIO Console: `http://localhost:9001`.

В локальной среде те же контуры выбираются по заголовку `Host`: основной
домен обслуживает Flutter Web, а `admin.edinburo.ru` — Next.js-админку.

Телефон первого администратора задаётся в `.env` переменной
`BN_BOOTSTRAP_ADMIN_PHONE`. В режиме `development` SMS не отправляется:
одноразовый код отображается на экране входа админки.

## Что реально подключено в админке

Через защищённый серверный прокси подключены:

- SMS-вход, обновление сессии и TOTP-2FA;
- управленческий дашборд и аналитика;
- находки и CSV-экспорт;
- заявления и решения по ним;
- ИИ-совпадения и принятие/отклонение;
- организации и их проверка;
- пользователи и ограничения аккаунтов;
- очередь модерации;
- обращения поддержки;
- техническое состояние backend, PostgreSQL, Redis и вебхуков;
- системные настройки;
- журнал аудита.

Форма добавления создаёт корректный черновик находки. Публикация выполняется
после добавления фотографии — backend не допускает публичную карточку без фото.

Access и refresh tokens хранятся только в HttpOnly cookies и недоступны
JavaScript-коду браузера.

## Пользовательский сайт и мобильное приложение

Исходники находятся в папке `flutter/`. Адрес API передаётся при сборке:

```bash
flutter run --dart-define=BUREAU_API_URL=http://10.0.2.2/v1
```

Для физического телефона укажите IP или домен сервера:

```bash
flutter run --dart-define=BUREAU_API_URL=https://api.example.ru/v1
```

Полный OpenAPI-контракт находится в `backend/openapi.json`, Flutter-клиент — в
`flutter/lib/data/bureau_api_client.dart`, а карта 67 экранов к маршрутам — в
`flutter/lib/data/screen_catalog.dart`.

Flutter Web собирается отдельным Docker-контейнером и публикуется на главном
домене. В web-интерфейсе скрыты внутренний каталог разработки и кабинет
модератора: административная работа выполняется только на отдельном домене.
Для App Store и Google Play остаётся настроить подписи, разрешения камеры и
галереи, push FCM/APNs и выполнить device-тесты на production-домене.

## Автоматическая проверка

В `.github/workflows/ci.yml` настроены проверки backend, админки и Flutter.
Локально исходники можно проверить командами из соответствующих папок:

```bash
cd backend && pytest && ruff check . && python scripts/export_openapi.py --check
cd ../admin && npm ci && npm test && npm run lint && npm run build
cd ../flutter && node tool/validate_project.js
```

## Подготовка production

Перед публичным запуском измените `.env`:

1. `PUBLIC_BASE_URL=https://edinburo.ru`;
2. `ADMIN_BASE_URL=https://admin.edinburo.ru`;
3. `S3_PUBLIC_URL=https://файлы.ваш-домен.ru`;
4. `BN_ENVIRONMENT=production`;
5. `ADMIN_COOKIE_SECURE=true`;
6. заполните параметры SMS-провайдера;
7. направьте DNS-записи `@` и `admin` на production-сервер и выпустите TLS для
   обоих имён;
8. замените локальный MinIO на объектное хранилище, если это требуется;
9. настройте резервные копии PostgreSQL и файлов;
10. проведите security-аудит и проверку требований 152-ФЗ.

При `BN_ENVIRONMENT=production` backend специально откажется запускаться,
если обязательные секреты или SMS-провайдер не настроены.

## Управление

```bash
make status
make logs
make down
make ai
```

Повторный `make up` безопасен: существующие данные и секреты сохраняются.
Команда `make status` проверяет конфигурацию, API, админку и состояние сервисов.

`make ai` дополнительно запускает тяжёлый OpenCLIP-сервис. Без него backend
работает с безопасным fallback и подключаемой моделью OpenAI.

Данные PostgreSQL, Redis и MinIO хранятся в Docker volumes и не удаляются
обычной командой `make down`.

## Структура

```text
backend/                 FastAPI, worker, миграции, OpenAPI
admin/                   Next.js веб-админка
flutter/                 Android, iOS и пользовательский Flutter Web
flutter/Dockerfile.web   production-сборка пользовательского сайта
nginx/default.conf       разделение главного и административного доменов
docker-compose.yml       запуск всего комплекса
install.sh               установка одной командой
```
