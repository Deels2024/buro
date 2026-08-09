enum BureauRole { user, organization, admin }

class ScreenSpec {
  const ScreenSpec(this.id, this.title, this.template, this.role);

  final String id;
  final String title;
  final String template;
  final BureauRole role;
}

const userScreenSpecs = <ScreenSpec>[
  ScreenSpec('U01', 'Запуск', 'splash', BureauRole.user),
  ScreenSpec('U02', 'Онбординг — единая сеть', 'onboarding', BureauRole.user),
  ScreenSpec('U03', 'Онбординг — безопасность', 'onboarding', BureauRole.user),
  ScreenSpec('U04', 'Онбординг — ИИ-поиск', 'onboarding', BureauRole.user),
  ScreenSpec('U05', 'Вход', 'auth', BureauRole.user),
  ScreenSpec('U06', 'Подтверждение телефона', 'verify', BureauRole.user),
  ScreenSpec('U07', 'Главная', 'home', BureauRole.user),
  ScreenSpec('U08', 'Поиск', 'search', BureauRole.user),
  ScreenSpec('U09', 'Фильтры поиска', 'filters', BureauRole.user),
  ScreenSpec('U10', 'ИИ-поиск по фото', 'photoSearch', BureauRole.user),
  ScreenSpec('U11', 'Результаты — список', 'results', BureauRole.user),
  ScreenSpec('U12', 'Результаты — карта', 'map', BureauRole.user),
  ScreenSpec('U13', 'Карточка находки', 'detailFound', BureauRole.user),
  ScreenSpec('U14', 'Карточка пропажи', 'detailLost', BureauRole.user),
  ScreenSpec('U15', 'Почему ИИ считает похожим', 'explain', BureauRole.user),
  ScreenSpec('U16', 'Что вы хотите разместить', 'choice', BureauRole.user),
  ScreenSpec('U17', 'Пропажа — фото и видео', 'lostMedia', BureauRole.user),
  ScreenSpec('U18', 'Пропажа — описание', 'lostDetails', BureauRole.user),
  ScreenSpec('U19', 'Пропажа — место и время', 'lostLocation', BureauRole.user),
  ScreenSpec('U20', 'Пропажа — предпросмотр', 'lostPreview', BureauRole.user),
  ScreenSpec('U21', 'Находка — фото и видео', 'foundMedia', BureauRole.user),
  ScreenSpec('U22', 'Находка — описание', 'foundDetails', BureauRole.user),
  ScreenSpec('U23', 'Находка — безопасное место', 'foundLocation', BureauRole.user),
  ScreenSpec('U24', 'Находка — предпросмотр', 'foundPreview', BureauRole.user),
  ScreenSpec('U25', 'Публикация создана', 'publicationSuccess', BureauRole.user),
  ScreenSpec('U26', 'Центр совпадений', 'matchHub', BureauRole.user),
  ScreenSpec('U27', 'Сравнение совпадения', 'compare', BureauRole.user),
  ScreenSpec('U28', 'Начало подтверждения', 'claimStart', BureauRole.user),
  ScreenSpec('U29', 'Контрольные вопросы', 'qna', BureauRole.user),
  ScreenSpec('U30', 'Доказательства', 'evidence', BureauRole.user),
  ScreenSpec('U31', 'Проверка заявления', 'review', BureauRole.user),
  ScreenSpec('U32', 'Защищённый чат', 'chat', BureauRole.user),
  ScreenSpec('U33', 'Согласие на контакты', 'consent', BureauRole.user),
  ScreenSpec('U34', 'Способ передачи', 'handover', BureauRole.user),
  ScreenSpec('U35', 'QR передачи', 'qr', BureauRole.user),
  ScreenSpec('U36', 'Вещь возвращена', 'complete', BureauRole.user),
  ScreenSpec('U37', 'Мои обращения', 'cases', BureauRole.user),
  ScreenSpec('U38', 'Уведомления', 'notifications', BureauRole.user),
  ScreenSpec('U39', 'Сохранённое', 'saved', BureauRole.user),
  ScreenSpec('U40', 'Профиль и безопасность', 'profile', BureauRole.user),
];

const organizationScreenSpecs = <ScreenSpec>[
  ScreenSpec('O01', 'Вход организации', 'orgAuth', BureauRole.organization),
  ScreenSpec('O02', 'Проверка организации', 'orgVerify', BureauRole.organization),
  ScreenSpec('O03', 'Операционный обзор', 'orgDashboard', BureauRole.organization),
  ScreenSpec('O04', 'Приём находки — сканер', 'scanner', BureauRole.organization),
  ScreenSpec('O05', 'Новая вещь — медиа', 'orgMedia', BureauRole.organization),
  ScreenSpec('O06', 'Новая вещь — описание', 'orgDetails', BureauRole.organization),
  ScreenSpec('O07', 'Место хранения', 'storage', BureauRole.organization),
  ScreenSpec('O08', 'Инвентарь', 'inventory', BureauRole.organization),
  ScreenSpec('O09', 'Фильтры инвентаря', 'inventoryFilters', BureauRole.organization),
  ScreenSpec('O10', 'Карточка вещи', 'record', BureauRole.organization),
  ScreenSpec('O11', 'Очередь заявлений', 'claims', BureauRole.organization),
  ScreenSpec('O12', 'Проверка владельца', 'claimDetail', BureauRole.organization),
  ScreenSpec('O13', 'Защищённый чат', 'orgChat', BureauRole.organization),
  ScreenSpec('O14', 'Одобрение владельца', 'approve', BureauRole.organization),
  ScreenSpec('O15', 'Выдача по QR', 'orgQr', BureauRole.organization),
  ScreenSpec('O16', 'Массовый импорт', 'bulk', BureauRole.organization),
  ScreenSpec('O17', 'Команда и роли', 'team', BureauRole.organization),
  ScreenSpec('O18', 'Филиалы', 'branches', BureauRole.organization),
  ScreenSpec('O19', 'Аналитика возвратов', 'analytics', BureauRole.organization),
  ScreenSpec('O20', 'Настройки и API', 'settings', BureauRole.organization),
];

const adminScreenSpecs = <ScreenSpec>[
  ScreenSpec('A01', 'Центр модерации', 'adminDashboard', BureauRole.admin),
  ScreenSpec('A02', 'Проверка публикации', 'flagged', BureauRole.admin),
  ScreenSpec('A03', 'Риск заявления', 'riskClaim', BureauRole.admin),
  ScreenSpec('A04', 'Споры и апелляции', 'disputes', BureauRole.admin),
  ScreenSpec('A05', 'Проверка организации', 'adminOrg', BureauRole.admin),
  ScreenSpec('A06', 'Антифрод-аналитика', 'fraud', BureauRole.admin),
  ScreenSpec('A07', 'Реклама и партнёры', 'adsAdmin', BureauRole.admin),
];

const allScreenSpecs = <ScreenSpec>[
  ...userScreenSpecs,
  ...organizationScreenSpecs,
  ...adminScreenSpecs,
];
