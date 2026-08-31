#!/usr/bin/env node

const fs = require('fs');
const path = require('path');

const root = path.resolve(__dirname, '..');
const requiredFiles = [
  'pubspec.yaml',
  'lib/main.dart',
  'lib/app.dart',
  'lib/core/theme.dart',
  'lib/core/widgets.dart',
  'lib/core/api_widgets.dart',
  'lib/data/screen_catalog.dart',
  'lib/data/api_config.dart',
  'lib/data/bureau_api_client.dart',
  'lib/data/app_controller.dart',
  'lib/data/secure_token_store.dart',
  'lib/features/user/user_app.dart',
  'lib/features/user/create_flow.dart',
  'lib/features/user/match_flow.dart',
  'lib/features/organization/organization_app.dart',
  'lib/features/admin/admin_app.dart',
  'lib/features/catalog/catalog_page.dart',
  'web/index.html',
  'web/robots.txt',
  'web/sitemap.xml',
  'web/site.webmanifest',
  'web/favicon.svg',
  'web/icons/icon-180.png',
  'web/icons/icon-192.png',
  'web/icons/icon-512.png',
  'web/og-image.png',
  'web/seo.css',
  'web/poteryal-veshch/index.html',
  'web/nashel-veshch/index.html',
  'web/poteryannye-veshchi/index.html',
  'web/naydennye-veshchi/index.html',
  'web/byuro-nahodok-moskva/index.html',
  'web/byuro-nahodok-sankt-peterburg/index.html',
];

const missingFiles = requiredFiles.filter(
  (file) => !fs.existsSync(path.join(root, file)),
);

if (missingFiles.length > 0) {
  throw new Error(`Не найдены обязательные файлы: ${missingFiles.join(', ')}`);
}

const catalog = fs.readFileSync(
  path.join(root, 'lib/data/screen_catalog.dart'),
  'utf8',
);
const ids = [...catalog.matchAll(/ScreenSpec\s*\(\s*'([UOA]\d{2})'/g)].map(
  (match) => match[1],
);
const uniqueIds = new Set(ids);
const counts = ids.reduce(
  (result, id) => {
    result[id[0]] += 1;
    return result;
  },
  { U: 0, O: 0, A: 0 },
);

if (ids.length !== 67 || uniqueIds.size !== 67) {
  throw new Error(
    `Каталог должен содержать 67 уникальных экранов, найдено ${ids.length}/${uniqueIds.size}`,
  );
}

if (counts.U !== 40 || counts.O !== 20 || counts.A !== 7) {
  throw new Error(
    `Неверное распределение экранов: U=${counts.U}, O=${counts.O}, A=${counts.A}`,
  );
}

const featureSources = requiredFiles
  .filter((file) => file.endsWith('.dart'))
  .map((file) => fs.readFileSync(path.join(root, file), 'utf8'))
  .join('\n');

const criticalMarkers = [
  'Защищённый чат',
  'QR передачи',
  'Кабинет организации',
  'Центр модерации',
  '_LiveAdCard',
];
const missingMarkers = criticalMarkers.filter(
  (marker) => !featureSources.includes(marker),
);

const apiClient = fs.readFileSync(
  path.join(root, 'lib/data/bureau_api_client.dart'),
  'utf8',
);
for (const marker of ['Idempotency-Key', '/auth/refresh', 'x-request-id', '/app/bootstrap']) {
  if (!apiClient.includes(marker)) {
    throw new Error(`API-клиент не содержит обязательный контракт: ${marker}`);
  }
}

if (missingMarkers.length > 0) {
  throw new Error(`Не найдены ключевые сценарии: ${missingMarkers.join(', ')}`);
}

const webIndex = fs.readFileSync(path.join(root, 'web/index.html'), 'utf8');
for (const marker of [
  '<link rel="canonical" href="https://edinburo.ru/">',
  '<meta name="robots" content="index, follow,',
  '<meta property="og:image" content="https://edinburo.ru/og-image.png">',
  'application/ld+json',
]) {
  if (!webIndex.includes(marker)) {
    throw new Error(`Главная страница не содержит обязательный SEO-маркер: ${marker}`);
  }
}

const robots = fs.readFileSync(path.join(root, 'web/robots.txt'), 'utf8');
for (const marker of [
  'User-agent: *',
  'Allow: /',
  'Disallow: /v1/',
  'Sitemap: https://edinburo.ru/sitemap.xml',
]) {
  if (!robots.includes(marker)) {
    throw new Error(`robots.txt не содержит обязательную директиву: ${marker}`);
  }
}

const sitemap = fs.readFileSync(path.join(root, 'web/sitemap.xml'), 'utf8');
for (const url of [
  'https://edinburo.ru/',
  'https://edinburo.ru/poteryal-veshch/',
  'https://edinburo.ru/nashel-veshch/',
  'https://edinburo.ru/poteryannye-veshchi/',
  'https://edinburo.ru/naydennye-veshchi/',
  'https://edinburo.ru/byuro-nahodok-moskva/',
  'https://edinburo.ru/byuro-nahodok-sankt-peterburg/',
]) {
  if (!sitemap.includes(`<loc>${url}</loc>`)) {
    throw new Error(`sitemap.xml не содержит индексируемый адрес: ${url}`);
  }
}

const buildRoot = path.join(root, 'build/web');
if (fs.existsSync(buildRoot)) {
  for (const file of [
    'robots.txt',
    'sitemap.xml',
    'site.webmanifest',
    'favicon.svg',
    'og-image.png',
    'icons/icon-180.png',
    'icons/icon-192.png',
    'icons/icon-512.png',
    'seo.css',
    'poteryal-veshch/index.html',
    'nashel-veshch/index.html',
    'poteryannye-veshchi/index.html',
    'naydennye-veshchi/index.html',
    'byuro-nahodok-moskva/index.html',
    'byuro-nahodok-sankt-peterburg/index.html',
  ]) {
    if (!fs.existsSync(path.join(buildRoot, file))) {
      throw new Error(`Production web-сборка не содержит SEO-файл: ${file}`);
    }
  }
}

const mappedIds = [...catalog.matchAll(/^\s*'([UOA]\d{2})': \[/gm)].map((match) => match[1]);
if (mappedIds.length !== 67 || new Set(mappedIds).size !== 67) {
  throw new Error(`Карта API должна содержать 67 экранов, найдено ${mappedIds.length}/${new Set(mappedIds).size}`);
}

console.log('Проверка пройдена.');
console.log(`Экраны: ${ids.length} (пользователь ${counts.U}, организация ${counts.O}, админ ${counts.A})`);
console.log(`Обязательные файлы: ${requiredFiles.length}`);
