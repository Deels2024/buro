import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../core/widgets.dart';

class OrganizationAuthPage extends StatelessWidget {
  const OrganizationAuthPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BureauPage(
      title: 'Вход для организаций',
      subtitle: 'Единый инвентарь находок',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 26),
          Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(color: BureauColors.greenSoft, borderRadius: BorderRadius.circular(26)),
            child: const Icon(Icons.business_rounded, color: BureauColors.green, size: 44),
          ),
          const SizedBox(height: 24),
          Text('Подключите точку к поисковой сети', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 12),
          Text(
            'Принимайте находки, проверяйте владельцев и контролируйте выдачу в одном кабинете.',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: BureauColors.slate),
          ),
          const SizedBox(height: 26),
          const TextField(decoration: InputDecoration(prefixIcon: Icon(Icons.mail_outline_rounded), hintText: 'Рабочая почта')),
          const SizedBox(height: 12),
          const TextField(obscureText: true, decoration: InputDecoration(prefixIcon: Icon(Icons.lock_outline_rounded), hintText: 'Пароль')),
          const SizedBox(height: 14),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: BureauColors.green),
            onPressed: () => pushPage(context, const OrganizationVerifyPage()),
            child: const Text('Войти'),
          ),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: () {}, child: const Text('Подать заявку на подключение')),
          const SizedBox(height: 20),
          const NoticeCard('Двухфакторный вход обязателен для администраторов организации.'),
        ],
      ),
    );
  }
}

class OrganizationVerifyPage extends StatelessWidget {
  const OrganizationVerifyPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BureauPage(
      title: 'Проверка организации',
      subtitle: 'ООО «Галерея Сервис»',
      bottom: FilledButton(
        style: FilledButton.styleFrom(backgroundColor: BureauColors.green),
        onPressed: () => pushPage(context, const OrganizationShell()),
        child: const Text('Открыть кабинет'),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SoftCard(
            color: BureauColors.greenSoft,
            borderColor: BureauColors.greenSoft,
            child: Row(
              children: [
                IconTile(icon: Icons.verified_rounded, color: BureauColors.green, background: Colors.white),
                SizedBox(width: 12),
                Expanded(child: Text('Организация подтверждена', style: TextStyle(color: BureauColors.green, fontWeight: FontWeight.w900))),
                BureauPill('ГОТОВО', color: BureauColors.green, background: Colors.white),
              ],
            ),
          ),
          const SectionTitle('Автопроверки'),
          ...const [
            ('ИНН найден в ЕГРЮЛ', '7812345678'),
            ('Домен подтверждён', 'galeria.spb.ru'),
            ('Подписант проверен', 'Полномочия действуют'),
            ('Филиал подтверждён', 'Лиговский пр., 30А'),
          ].map(
            (row) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: SettingRow(
                icon: Icons.check_rounded,
                title: row.$1,
                subtitle: row.$2,
                color: BureauColors.green,
                background: BureauColors.greenSoft,
                trailing: const Icon(Icons.verified_rounded, color: BureauColors.green),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class OrganizationShell extends StatefulWidget {
  const OrganizationShell({super.key});

  @override
  State<OrganizationShell> createState() => _OrganizationShellState();
}

class _OrganizationShellState extends State<OrganizationShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    const pages = [
      _OrgDashboard(),
      _InventoryView(),
      _ClaimsView(),
      _TeamView(),
      _AnalyticsView(),
    ];
    return Theme(
      data: Theme.of(context).copyWith(
        navigationBarTheme: Theme.of(context).navigationBarTheme.copyWith(
              indicatorColor: BureauColors.greenSoft,
              labelTextStyle: WidgetStateProperty.resolveWith(
                (states) => TextStyle(
                  color: states.contains(WidgetState.selected) ? BureauColors.green : BureauColors.muted,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
      ),
      child: Scaffold(
        body: IndexedStack(index: _index, children: pages),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (value) => setState(() => _index = value),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard_rounded), label: 'Обзор'),
            NavigationDestination(icon: Icon(Icons.inventory_2_outlined), selectedIcon: Icon(Icons.inventory_2_rounded), label: 'Склад'),
            NavigationDestination(icon: Icon(Icons.fact_check_outlined), selectedIcon: Icon(Icons.fact_check_rounded), label: 'Заявки'),
            NavigationDestination(icon: Icon(Icons.groups_outlined), selectedIcon: Icon(Icons.groups_rounded), label: 'Команда'),
            NavigationDestination(icon: Icon(Icons.analytics_outlined), selectedIcon: Icon(Icons.analytics_rounded), label: 'Отчёт'),
          ],
        ),
      ),
    );
  }
}

class _OrgHeader extends StatelessWidget {
  const _OrgHeader(this.title, {this.subtitle = 'ТЦ «Галерея»'});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(color: BureauColors.green, borderRadius: BorderRadius.circular(14)),
          child: const Center(child: Text('ТЦ', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900))),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              Text(subtitle, style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 10)),
            ],
          ),
        ),
        const BureauPill('СМЕНА', color: BureauColors.green, background: BureauColors.greenSoft),
      ],
    );
  }
}

class _OrgDashboard extends StatelessWidget {
  const _OrgDashboard();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _OrgHeader('Операционный обзор'),
            const SizedBox(height: 22),
            const Row(
              children: [
                Expanded(child: MetricCard(value: '148', label: 'вещей на хранении')),
                SizedBox(width: 10),
                Expanded(child: MetricCard(value: '17', label: 'новых заявлений', color: BureauColors.green)),
              ],
            ),
            const SizedBox(height: 10),
            const Row(
              children: [
                Expanded(child: MetricCard(value: '68%', label: 'возвращено за месяц', color: BureauColors.green)),
                SizedBox(width: 10),
                Expanded(child: MetricCard(value: '4,8 мин', label: 'средняя приёмка')),
              ],
            ),
            const SectionTitle('Быстрые действия'),
            Row(
              children: [
                Expanded(
                  child: _OrgQuick(
                    icon: Icons.qr_code_scanner_rounded,
                    title: 'Принять вещь',
                    onTap: () => pushPage(context, const OrganizationDetailPage(type: OrgDetailType.scanner)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _OrgQuick(
                    icon: Icons.upload_file_rounded,
                    title: 'Массовый импорт',
                    onTap: () => pushPage(context, const OrganizationDetailPage(type: OrgDetailType.bulk)),
                  ),
                ),
              ],
            ),
            const SectionTitle('Требуют внимания'),
            SettingRow(
              icon: Icons.fact_check_outlined,
              title: '7 заявлений ждут решения',
              subtitle: 'Самое старое · 1 ч 24 мин',
              color: BureauColors.amber,
              background: BureauColors.amberSoft,
              trailing: const BureauPill('7', color: BureauColors.amber, background: BureauColors.amberSoft),
              onTap: () => pushPage(context, const OrganizationDetailPage(type: OrgDetailType.claimDetail)),
            ),
            const SizedBox(height: 10),
            SettingRow(
              icon: Icons.location_on_outlined,
              title: 'Ячейка B-24 заполнена',
              subtitle: 'Назначьте новое место хранения',
              onTap: () => pushPage(context, const OrganizationDetailPage(type: OrgDetailType.storage)),
            ),
          ],
        ),
      ),
    );
  }
}

class _OrgQuick extends StatelessWidget {
  const _OrgQuick({required this.icon, required this.title, required this.onTap});

  final IconData icon;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      onTap: onTap,
      color: BureauColors.greenSoft,
      borderColor: BureauColors.greenSoft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: BureauColors.green, size: 29),
          const SizedBox(height: 20),
          Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(color: BureauColors.green)),
        ],
      ),
    );
  }
}

class _InventoryView extends StatelessWidget {
  const _InventoryView();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 14, 20, 10),
            child: _OrgHeader('Инвентарь', subtitle: '148 вещей · 3 филиала'),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 28),
              child: Column(
                children: [
                  Row(
                    children: [
                      const Expanded(child: TextField(decoration: InputDecoration(prefixIcon: Icon(Icons.search_rounded), hintText: 'ID, вещь или ячейка'))),
                      const SizedBox(width: 9),
                      IconButton.filledTonal(
                        onPressed: () => pushPage(context, const OrganizationDetailPage(type: OrgDetailType.inventoryFilters)),
                        icon: const Icon(Icons.tune_rounded),
                      ),
                    ],
                  ),
                  const SectionTitle('Сегодня'),
                  ...[
                    ('BN-4829', 'Чёрный рюкзак', 'B-24', Icons.backpack_rounded),
                    ('BN-4828', 'Серебристый ноутбук', 'A-11', Icons.laptop_mac_rounded),
                    ('BN-4827', 'Связка ключей', 'C-07', Icons.key_rounded),
                  ].map(
                    (item) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: SettingRow(
                        icon: item.$4,
                        title: item.$2,
                        subtitle: '${item.$1} · ячейка ${item.$3}',
                        color: BureauColors.green,
                        background: BureauColors.greenSoft,
                        trailing: const BureauPill('НА ХРАНЕНИИ', color: BureauColors.green, background: BureauColors.greenSoft),
                        onTap: () => pushPage(context, const OrganizationDetailPage(type: OrgDetailType.record)),
                      ),
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => pushPage(context, const OrganizationDetailPage(type: OrgDetailType.media)),
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Добавить вещь вручную'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ClaimsView extends StatelessWidget {
  const _ClaimsView();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _OrgHeader('Очередь заявлений', subtitle: '17 новых · SLA 94%'),
            const SizedBox(height: 20),
            const Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                BureauPill('Новые · 17', color: BureauColors.green, background: BureauColors.greenSoft),
                BureauPill('В работе · 8', color: BureauColors.slate, background: Colors.white),
                BureauPill('Риск · 2', color: BureauColors.red, background: BureauColors.redSoft),
              ],
            ),
            const SectionTitle('Сначала лучшие совпадения'),
            ...[
              ('Анна С.', 'Рюкзак BN-4829', '93%', BureauColors.green),
              ('Илья К.', 'Ноутбук BN-4828', '86%', BureauColors.green),
              ('Мария П.', 'Часы BN-4791', '74%', BureauColors.amber),
            ].map(
              (claim) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: SettingRow(
                  icon: Icons.person_search_outlined,
                  title: claim.$1,
                  subtitle: claim.$2,
                  color: claim.$4,
                  background: claim.$4 == BureauColors.green ? BureauColors.greenSoft : BureauColors.amberSoft,
                  trailing: BureauPill(claim.$3, color: claim.$4, background: claim.$4 == BureauColors.green ? BureauColors.greenSoft : BureauColors.amberSoft),
                  onTap: () => pushPage(context, const OrganizationDetailPage(type: OrgDetailType.claimDetail)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TeamView extends StatelessWidget {
  const _TeamView();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _OrgHeader('Команда и филиалы', subtitle: '12 сотрудников · 3 точки'),
            const SectionTitle('Сейчас на смене'),
            ...const [
              ('МК', 'Мария Козлова', 'Администратор'),
              ('АС', 'Алексей Смирнов', 'Оператор склада'),
              ('НИ', 'Наталья Иванова', 'Выдача'),
            ].map(
              (person) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: SoftCard(
                  child: Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: BureauColors.greenSoft,
                        child: Text(person.$1, style: const TextStyle(color: BureauColors.green, fontWeight: FontWeight.w900)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(person.$2, style: const TextStyle(fontWeight: FontWeight.w800)),
                            Text(person.$3, style: const TextStyle(color: BureauColors.slate, fontSize: 10)),
                          ],
                        ),
                      ),
                      const BureauPill('ОНЛАЙН', color: BureauColors.green, background: BureauColors.greenSoft),
                    ],
                  ),
                ),
              ),
            ),
            const SectionTitle('Управление'),
            const SettingRow(icon: Icons.manage_accounts_outlined, title: 'Роли и права', subtitle: '3 группы доступа'),
            const SizedBox(height: 10),
            SettingRow(
              icon: Icons.account_tree_outlined,
              title: 'Филиалы',
              subtitle: '3 точки в единой сети',
              color: BureauColors.green,
              background: BureauColors.greenSoft,
              onTap: () => pushPage(context, const OrganizationDetailPage(type: OrgDetailType.branches)),
            ),
          ],
        ),
      ),
    );
  }
}

class _AnalyticsView extends StatelessWidget {
  const _AnalyticsView();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _OrgHeader('Аналитика возвратов', subtitle: '1–31 июля'),
            const SizedBox(height: 20),
            const Row(
              children: [
                Expanded(child: MetricCard(value: '214', label: 'принято вещей')),
                SizedBox(width: 10),
                Expanded(child: MetricCard(value: '68%', label: 'возвращено', color: BureauColors.green)),
              ],
            ),
            const SectionTitle('Динамика'),
            const _BarChart(color: BureauColors.green),
            const SectionTitle('По категориям'),
            ...const [
              ('Документы', '72', '82%'),
              ('Электроника', '46', '74%'),
              ('Сумки', '38', '61%'),
            ].map(
              (row) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: SoftCard(
                  child: Row(
                    children: [
                      Expanded(child: Text(row.$1, style: const TextStyle(fontWeight: FontWeight.w800))),
                      Text('${row.$2} найдено', style: const TextStyle(color: BureauColors.slate, fontSize: 10)),
                      const SizedBox(width: 16),
                      BureauPill(row.$3, color: BureauColors.green, background: BureauColors.greenSoft),
                    ],
                  ),
                ),
              ),
            ),
            const SectionTitle('Настройки'),
            SettingRow(
              icon: Icons.settings_outlined,
              title: 'Настройки и API',
              subtitle: 'Интеграции, вебхуки и безопасность',
              onTap: () => pushPage(context, const OrganizationDetailPage(type: OrgDetailType.settings)),
            ),
          ],
        ),
      ),
    );
  }
}

class _BarChart extends StatelessWidget {
  const _BarChart({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    const values = [42.0, 66.0, 54.0, 83.0, 71.0, 94.0, 106.0];
    return SoftCard(
      child: SizedBox(
        height: 150,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: values
              .map(
                (value) => Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 5),
                    child: Container(
                      height: value,
                      decoration: BoxDecoration(color: color, borderRadius: const BorderRadius.vertical(top: Radius.circular(8))),
                    ),
                  ),
                ),
              )
              .toList(),
        ),
      ),
    );
  }
}

enum OrgDetailType {
  scanner,
  media,
  details,
  storage,
  inventoryFilters,
  record,
  claimDetail,
  chat,
  approve,
  qr,
  bulk,
  branches,
  settings,
}

class OrganizationDetailPage extends StatelessWidget {
  const OrganizationDetailPage({super.key, required this.type});

  final OrgDetailType type;

  String get title => switch (type) {
        OrgDetailType.scanner => 'Приём находки',
        OrgDetailType.media => 'Новая вещь — медиа',
        OrgDetailType.details => 'Описание вещи',
        OrgDetailType.storage => 'Место хранения',
        OrgDetailType.inventoryFilters => 'Фильтры инвентаря',
        OrgDetailType.record => 'Карточка вещи',
        OrgDetailType.claimDetail => 'Проверка владельца',
        OrgDetailType.chat => 'Защищённый чат',
        OrgDetailType.approve => 'Одобрить владельца',
        OrgDetailType.qr => 'Выдача по QR',
        OrgDetailType.bulk => 'Массовый импорт',
        OrgDetailType.branches => 'Филиалы',
        OrgDetailType.settings => 'Настройки и API',
      };

  @override
  Widget build(BuildContext context) {
    return BureauPage(
      title: title,
      subtitle: 'ТЦ «Галерея» · защищённый контур',
      bottom: FilledButton(
        style: FilledButton.styleFrom(backgroundColor: BureauColors.green),
        onPressed: () => _next(context),
        child: Text(_button),
      ),
      child: _content(context),
    );
  }

  String get _button => switch (type) {
        OrgDetailType.scanner => 'Продолжить приёмку',
        OrgDetailType.media => 'Создать описание с ИИ',
        OrgDetailType.details => 'Выбрать ячейку',
        OrgDetailType.storage => 'Сохранить вещь',
        OrgDetailType.inventoryFilters => 'Показать 148 вещей',
        OrgDetailType.record => 'Открыть заявления',
        OrgDetailType.claimDetail => 'Открыть чат',
        OrgDetailType.chat => 'Одобрить владельца',
        OrgDetailType.approve => 'Одобрить и продолжить',
        OrgDetailType.qr => 'Подтвердить выдачу',
        OrgDetailType.bulk => 'Загрузить файл',
        OrgDetailType.branches => 'Добавить филиал',
        OrgDetailType.settings => 'Сохранить настройки',
      };

  void _next(BuildContext context) {
    final next = switch (type) {
      OrgDetailType.scanner => OrgDetailType.media,
      OrgDetailType.media => OrgDetailType.details,
      OrgDetailType.details => OrgDetailType.storage,
      OrgDetailType.record => OrgDetailType.claimDetail,
      OrgDetailType.claimDetail => OrgDetailType.chat,
      OrgDetailType.chat => OrgDetailType.approve,
      OrgDetailType.approve => OrgDetailType.qr,
      _ => null,
    };
    if (next == null) {
      Navigator.pop(context);
    } else {
      pushPage(context, OrganizationDetailPage(type: next));
    }
  }

  Widget _content(BuildContext context) {
    return switch (type) {
      OrgDetailType.scanner => _scanner(context),
      OrgDetailType.media => _media(context),
      OrgDetailType.details => _details(context),
      OrgDetailType.storage => _storage(context),
      OrgDetailType.inventoryFilters => _filters(context),
      OrgDetailType.record => _record(context),
      OrgDetailType.claimDetail => _claim(context),
      OrgDetailType.chat => _chat(context),
      OrgDetailType.approve => _approve(context),
      OrgDetailType.qr => _qr(context),
      OrgDetailType.bulk => _bulk(context),
      OrgDetailType.branches => _branches(context),
      OrgDetailType.settings => _settings(context),
    };
  }

  Widget _scanner(BuildContext context) => Column(
        children: [
          Container(
            height: 330,
            decoration: BoxDecoration(
              color: BureauColors.greenSoft,
              borderRadius: BorderRadius.circular(26),
              border: Border.all(color: BureauColors.green, width: 1.5),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 210,
                  height: 210,
                  decoration: BoxDecoration(border: Border.all(color: BureauColors.green, width: 3), borderRadius: BorderRadius.circular(28)),
                ),
                Positioned(left: 55, right: 55, child: Container(height: 3, color: BureauColors.green)),
                const Positioned(bottom: 24, child: BureauPill('QR ИЛИ ШТРИХКОД', color: BureauColors.green, background: Colors.white)),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const NoticeCard('Если этикетки нет, создайте новую карточку вручную.'),
        ],
      );

  Widget _media(BuildContext context) => const Column(
        children: [
          ItemArtwork(height: 260, color: BureauColors.green, background: BureauColors.greenSoft),
          SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _OrgMediaButton(Icons.add_a_photo_outlined, 'Ещё фото')),
              SizedBox(width: 10),
              Expanded(child: _OrgMediaButton(Icons.videocam_outlined, 'Видео')),
            ],
          ),
          SizedBox(height: 16),
          NoticeCard('Зафиксируйте состояние вещи и не публикуйте скрытые признаки.'),
        ],
      );

  Widget _details(BuildContext context) => const Column(
        children: [
          NoticeCard('ИИ определил категорию, цвет и основные признаки.'),
          SizedBox(height: 16),
          TextField(decoration: InputDecoration(hintText: 'Чёрный городской рюкзак')),
          SizedBox(height: 12),
          TextField(maxLines: 4, decoration: InputDecoration(hintText: 'Матовый, два отделения, красная молния…')),
          SizedBox(height: 12),
          TextField(maxLines: 3, decoration: InputDecoration(prefixIcon: Icon(Icons.lock_outline_rounded), hintText: 'Скрытый признак для проверки')),
        ],
      );

  Widget _storage(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const TextField(decoration: InputDecoration(prefixIcon: Icon(Icons.search_rounded), hintText: 'Найти ячейку')),
          const SectionTitle('Свободные рядом'),
          ...['B-24', 'B-27', 'C-03'].map(
            (cell) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: SettingRow(
                icon: Icons.inventory_2_outlined,
                title: 'Ячейка $cell',
                subtitle: 'Секция сумок · средний размер',
                color: BureauColors.green,
                background: BureauColors.greenSoft,
                trailing: cell == 'B-24' ? const BureauPill('ВЫБРАНО', color: BureauColors.green, background: BureauColors.greenSoft) : null,
              ),
            ),
          ),
          const NoticeCard('Внешняя этикетка содержит только служебный ID без персональных данных.'),
        ],
      );

  Widget _filters(BuildContext context) => const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionTitle('Статус'),
          Wrap(spacing: 8, runSpacing: 8, children: [BureauPill('Все'), BureauPill('На хранении', background: Colors.white), BureauPill('Есть заявление', background: Colors.white)]),
          SectionTitle('Категория'),
          Wrap(spacing: 8, runSpacing: 8, children: [BureauPill('Сумки', color: BureauColors.green, background: BureauColors.greenSoft), BureauPill('Документы', background: Colors.white), BureauPill('Электроника', background: Colors.white)]),
          SectionTitle('Филиал'),
          TextField(readOnly: true, decoration: InputDecoration(prefixIcon: Icon(Icons.business_outlined), hintText: 'ТЦ «Галерея»')),
        ],
      );

  Widget _record(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const ItemArtwork(height: 210, color: BureauColors.green, background: BureauColors.greenSoft),
          const SizedBox(height: 14),
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              BureauPill('BN-4829', color: BureauColors.green, background: BureauColors.greenSoft),
              BureauPill('B-24', color: BureauColors.slate, background: Colors.white),
            ],
          ),
          const SizedBox(height: 15),
          Text('Чёрный городской рюкзак', style: Theme.of(context).textTheme.headlineSmall),
          const SectionTitle('Состояние'),
          const SettingRow(icon: Icons.inventory_2_outlined, title: 'На хранении', subtitle: 'Принято сегодня · Мария К.'),
          const SizedBox(height: 10),
          const SettingRow(
            icon: Icons.person_search_outlined,
            title: '3 заявления владельцев',
            subtitle: 'Лучшее совпадение · 93%',
            color: BureauColors.green,
            background: BureauColors.greenSoft,
          ),
        ],
      );

  Widget _claim(BuildContext context) => const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SoftCard(
            color: BureauColors.greenSoft,
            borderColor: BureauColors.greenSoft,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('93%', style: TextStyle(color: BureauColors.green, fontSize: 30, fontWeight: FontWeight.w900)), Text('уверенность ИИ', style: TextStyle(color: BureauColors.slate, fontSize: 10))]),
                BureauPill('НИЗКИЙ РИСК', color: BureauColors.green, background: Colors.white),
              ],
            ),
          ),
          SectionTitle('Скрытый признак'),
          SoftCard(child: Text('Зелёный ярлык AK во внутреннем кармане', style: TextStyle(fontWeight: FontWeight.w800))),
          SectionTitle('Доказательство'),
          SettingRow(icon: Icons.photo_library_outlined, title: 'Старое фото', subtitle: 'Создано до даты находки', color: BureauColors.green, background: BureauColors.greenSoft),
          SizedBox(height: 10),
          SettingRow(icon: Icons.quiz_outlined, title: '3 контрольных ответа', subtitle: 'Все совпадают с карточкой'),
        ],
      );

  Widget _chat(BuildContext context) => const Column(
        children: [
          NoticeCard('Контакты владельца скрыты до одобрения.'),
          SizedBox(height: 18),
          _OrgBubble('Уточните цвет внутренней подкладки.'),
          SizedBox(height: 10),
          _OrgBubble('Тёмно-синяя, рядом с ярлыком белая строчка.', outgoing: true),
          SizedBox(height: 10),
          _OrgBubble('Совпадает с карточкой приёмки.'),
          SizedBox(height: 18),
          TextField(decoration: InputDecoration(hintText: 'Сообщение…', suffixIcon: Icon(Icons.send_rounded, color: BureauColors.green))),
        ],
      );

  Widget _approve(BuildContext context) => Column(
        children: [
          Container(
            width: 130,
            height: 130,
            decoration: const BoxDecoration(color: BureauColors.greenSoft, shape: BoxShape.circle),
            child: const Icon(Icons.verified_rounded, color: BureauColors.green, size: 65),
          ),
          const SizedBox(height: 22),
          Text('Данных достаточно', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 18),
          ...const ['Скрытый признак совпал', 'Старое фото подтверждено', 'Риск мошенничества низкий'].map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: SettingRow(icon: Icons.check_rounded, title: item, subtitle: 'Проверено системой и сотрудником', color: BureauColors.green, background: BureauColors.greenSoft, trailing: const Icon(Icons.verified_rounded, color: BureauColors.green)),
            ),
          ),
          const NoticeCard('После одобрения стороны выберут способ передачи.'),
        ],
      );

  Widget _qr(BuildContext context) => Column(
        children: [
          Container(
            height: 310,
            decoration: BoxDecoration(color: BureauColors.greenSoft, borderRadius: BorderRadius.circular(26)),
            child: Center(
              child: Container(
                width: 210,
                height: 210,
                decoration: BoxDecoration(border: Border.all(color: BureauColors.green, width: 4), borderRadius: BorderRadius.circular(28)),
                child: const Icon(Icons.qr_code_scanner_rounded, color: BureauColors.green, size: 100),
              ),
            ),
          ),
          const SizedBox(height: 14),
          const SettingRow(icon: Icons.inventory_2_outlined, title: 'Ячейка B-24', subtitle: 'Рюкзак · BN-4829', trailing: BureauPill('ГОТОВО', color: BureauColors.green, background: BureauColors.greenSoft)),
        ],
      );

  Widget _bulk(BuildContext context) => const Column(
        children: [
          SoftCard(
            color: BureauColors.greenSoft,
            borderColor: BureauColors.greenSoft,
            padding: EdgeInsets.symmetric(vertical: 50, horizontal: 20),
            child: Column(children: [Icon(Icons.upload_file_rounded, color: BureauColors.green, size: 54), SizedBox(height: 12), Text('Перетащите CSV или XLSX', style: TextStyle(fontWeight: FontWeight.w900)), SizedBox(height: 5), Text('до 10 000 записей · 50 МБ', style: TextStyle(color: BureauColors.slate, fontSize: 10))]),
          ),
          SizedBox(height: 14),
          NoticeCard('Поля: название, категория, дата, филиал, ячейка и служебный ID.'),
        ],
      );

  Widget _branches(BuildContext context) => Column(
        children: [
          Container(
            height: 230,
            decoration: BoxDecoration(color: const Color(0xFFE9EEF4), borderRadius: BorderRadius.circular(24)),
            child: const Stack(children: [Positioned(left: 65, top: 60, child: _BranchPin('84')), Positioned(right: 65, top: 100, child: _BranchPin('41')), Positioned(left: 155, bottom: 35, child: _BranchPin('23'))]),
          ),
          const SectionTitle('Точки'),
          ...const [('ТЦ «Галерея»', '84 вещи · SLA 92%'), ('ТЦ «Невский центр»', '41 вещь · SLA 96%'), ('Пункт «Сенная»', '23 вещи · SLA 88%')].map(
            (row) => Padding(padding: const EdgeInsets.only(bottom: 10), child: SettingRow(icon: Icons.storefront_outlined, title: row.$1, subtitle: row.$2, color: BureauColors.green, background: BureauColors.greenSoft)),
          ),
        ],
      );

  Widget _settings(BuildContext context) => const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionTitle('Интеграции'),
          SettingRow(icon: Icons.api_rounded, title: 'API Бюро находок', subtitle: 'Подключено · v2', color: BureauColors.green, background: BureauColors.greenSoft, trailing: BureauPill('АКТИВНО', color: BureauColors.green, background: BureauColors.greenSoft)),
          SizedBox(height: 10),
          SettingRow(icon: Icons.print_outlined, title: 'Печать этикеток', subtitle: 'Zebra ZD421'),
          SizedBox(height: 10),
          SettingRow(icon: Icons.sync_alt_rounded, title: 'Вебхуки', subtitle: '3 активных события'),
          SectionTitle('Безопасность'),
          SettingRow(icon: Icons.security_rounded, title: 'Двухфакторный вход', subtitle: 'Обязателен для администраторов', trailing: BureauPill('ВКЛ', color: BureauColors.green, background: BureauColors.greenSoft)),
          SizedBox(height: 10),
          SettingRow(icon: Icons.history_rounded, title: 'Журнал действий', subtitle: 'Хранение 365 дней'),
        ],
      );
}

class _OrgMediaButton extends StatelessWidget {
  const _OrgMediaButton(this.icon, this.label);

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      child: Column(children: [Icon(icon, color: BureauColors.green), const SizedBox(height: 7), Text(label, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800))]),
    );
  }
}

class _OrgBubble extends StatelessWidget {
  const _OrgBubble(this.text, {this.outgoing = false});

  final String text;
  final bool outgoing;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: outgoing ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 300),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: outgoing ? BureauColors.green : Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: outgoing ? null : Border.all(color: BureauColors.line),
        ),
        child: Text(text, style: TextStyle(color: outgoing ? Colors.white : BureauColors.navy, fontSize: 12, height: 1.4)),
      ),
    );
  }
}

class _BranchPin extends StatelessWidget {
  const _BranchPin(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 50,
      height: 50,
      decoration: BoxDecoration(color: BureauColors.green, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 4)),
      child: Center(child: Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900))),
    );
  }
}
