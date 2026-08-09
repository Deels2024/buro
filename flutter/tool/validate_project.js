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
  'lib/data/screen_catalog.dart',
  'lib/data/api_config.dart',
  'lib/data/bureau_api_client.dart',
  'lib/features/user/user_app.dart',
  'lib/features/user/create_flow.dart',
  'lib/features/user/match_flow.dart',
  'lib/features/organization/organization_app.dart',
  'lib/features/admin/admin_app.dart',
  'lib/features/catalog/catalog_page.dart',
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
const ids = [...catalog.matchAll(/ScreenSpec\('([UOA]\d{2})'/g)].map(
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
  'NativeAdCard',
];
const missingMarkers = criticalMarkers.filter(
  (marker) => !featureSources.includes(marker),
);

const apiClient = fs.readFileSync(
  path.join(root, 'lib/data/bureau_api_client.dart'),
  'utf8',
);
for (const marker of ['Idempotency-Key', '/auth/refresh', 'X-Request-ID', '/app/bootstrap']) {
  if (!apiClient.includes(marker)) {
    throw new Error(`API-клиент не содержит обязательный контракт: ${marker}`);
  }
}

if (missingMarkers.length > 0) {
  throw new Error(`Не найдены ключевые сценарии: ${missingMarkers.join(', ')}`);
}

console.log('Проверка пройдена.');
console.log(`Экраны: ${ids.length} (пользователь ${counts.U}, организация ${counts.O}, админ ${counts.A})`);
console.log(`Обязательные файлы: ${requiredFiles.length}`);
