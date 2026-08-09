import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../core/widgets.dart';

class AdminShell extends StatefulWidget {
  const AdminShell({super.key});

  @override
  State<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends State<AdminShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    const pages = [
      _AdminDashboard(),
      _RiskQueue(),
      _DisputesView(),
      _OrganizationQueue(),
      _FraudAnalytics(),
    ];
    return Theme(
      data: Theme.of(context).copyWith(
        navigationBarTheme: Theme.of(context).navigationBarTheme.copyWith(
              indicatorColor: BureauColors.amberSoft,
              labelTextStyle: WidgetStateProperty.resolveWith(
                (states) => TextStyle(
                  color: states.contains(WidgetState.selected) ? BureauColors.amber : BureauColors.muted,
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
            NavigationDestination(icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard_rounded), label: 'Центр'),
            NavigationDestination(icon: Icon(Icons.warning_amber_rounded), label: 'Риски'),
            NavigationDestination(icon: Icon(Icons.balance_outlined), selectedIcon: Icon(Icons.balance_rounded), label: 'Споры'),
            NavigationDestination(icon: Icon(Icons.business_outlined), selectedIcon: Icon(Icons.business_rounded), label: 'Орг.'),
            NavigationDestination(icon: Icon(Icons.query_stats_rounded), label: 'Фрод'),
          ],
        ),
      ),
    );
  }
}

class _AdminHeader extends StatelessWidget {
  const _AdminHeader(this.title, this.subtitle);

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(color: BureauColors.amber, borderRadius: BorderRadius.circular(14)),
          child: const Icon(Icons.admin_panel_settings_rounded, color: Colors.white),
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
        const BureauPill('СМЕНА', color: BureauColors.amber, background: BureauColors.amberSoft),
      ],
    );
  }
}

class _AdminDashboard extends StatelessWidget {
  const _AdminDashboard();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _AdminHeader('Центр модерации', 'Россия · текущая смена'),
            const SizedBox(height: 22),
            const Row(
              children: [
                Expanded(child: MetricCard(value: '128', label: 'в очереди', color: BureauColors.amber)),
                SizedBox(width: 10),
                Expanded(child: MetricCard(value: '14', label: 'высокий риск', color: BureauColors.red)),
              ],
            ),
            const SizedBox(height: 10),
            const Row(
              children: [
                Expanded(child: MetricCard(value: '4,8 мин', label: 'среднее решение')),
                SizedBox(width: 10),
                Expanded(child: MetricCard(value: '97%', label: 'SLA сегодня', color: BureauColors.green)),
              ],
            ),
            const SectionTitle('Очереди'),
            SettingRow(
              icon: Icons.visibility_off_outlined,
              title: 'Публикации с данными',
              subtitle: '31 материал · самое старое 18 мин',
              color: BureauColors.red,
              background: BureauColors.redSoft,
              trailing: const BureauPill('31', color: BureauColors.red, background: BureauColors.redSoft),
              onTap: () => pushPage(context, const AdminDetailPage(type: AdminDetailType.flagged)),
            ),
            const SizedBox(height: 10),
            SettingRow(
              icon: Icons.campaign_outlined,
              title: 'Реклама и партнёры',
              subtitle: 'Доход, жалобы и ограничения показов',
              color: BureauColors.amber,
              background: BureauColors.amberSoft,
              onTap: () => pushPage(context, const AdminDetailPage(type: AdminDetailType.ads)),
            ),
            const SizedBox(height: 10),
            const SettingRow(
              icon: Icons.health_and_safety_outlined,
              title: 'Состояние системы',
              subtitle: 'Все критические сервисы работают',
              color: BureauColors.green,
              background: BureauColors.greenSoft,
              trailing: BureauPill('НОРМА', color: BureauColors.green, background: BureauColors.greenSoft),
            ),
          ],
        ),
      ),
    );
  }
}

class _RiskQueue extends StatelessWidget {
  const _RiskQueue();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _AdminHeader('Риск заявлений', '14 высокого риска'),
            const SizedBox(height: 20),
            const Wrap(
              spacing: 8,
              children: [
                BureauPill('Высокий · 14', color: BureauColors.red, background: BureauColors.redSoft),
                BureauPill('Средний · 38', color: BureauColors.amber, background: BureauColors.amberSoft),
              ],
            ),
            const SectionTitle('Сначала критические'),
            ...[
              ('#C-4829', '4 заявления за 24 часа', '86/100'),
              ('#C-4811', 'Фото найдено в интернете', '81/100'),
              ('#C-4798', 'География не совпадает', '76/100'),
            ].map(
              (row) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: SettingRow(
                  icon: Icons.warning_amber_rounded,
                  title: row.$2,
                  subtitle: '${row.$1} · требует проверки',
                  color: BureauColors.red,
                  background: BureauColors.redSoft,
                  trailing: BureauPill(row.$3, color: BureauColors.red, background: BureauColors.redSoft),
                  onTap: () => pushPage(context, const AdminDetailPage(type: AdminDetailType.risk)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DisputesView extends StatelessWidget {
  const _DisputesView();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _AdminHeader('Споры и апелляции', '23 открытых дела'),
            const SizedBox(height: 20),
            const Wrap(
              spacing: 8,
              children: [
                BureauPill('Новые · 7', color: BureauColors.amber, background: BureauColors.amberSoft),
                BureauPill('В работе · 12', color: BureauColors.slate, background: Colors.white),
                BureauPill('Просрочено · 4', color: BureauColors.red, background: BureauColors.redSoft),
              ],
            ),
            const SectionTitle('Очередь'),
            ...[
              ('D-1082', 'Передача не состоялась', '24 мин'),
              ('D-1079', 'Организация отказала', '1 ч'),
              ('D-1074', 'Два возможных владельца', '3 ч'),
            ].map(
              (row) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: SettingRow(
                  icon: Icons.balance_outlined,
                  title: row.$2,
                  subtitle: '${row.$1} · ${row.$3}',
                  color: BureauColors.amber,
                  background: BureauColors.amberSoft,
                  onTap: () => pushPage(context, const AdminDetailPage(type: AdminDetailType.dispute)),
                ),
              ),
            ),
            const SectionTitle('SLA решений'),
            const LinearProgressIndicator(value: .78, minHeight: 7, color: BureauColors.amber, backgroundColor: BureauColors.line, borderRadius: BorderRadius.all(Radius.circular(99))),
          ],
        ),
      ),
    );
  }
}

class _OrganizationQueue extends StatelessWidget {
  const _OrganizationQueue();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _AdminHeader('Организации', '9 заявок на проверку'),
            const SectionTitle('Новые'),
            ...[
              ('ТЦ «Галерея»', 'Санкт-Петербург · ORG-9182'),
              ('Аэропорт Кольцово', 'Екатеринбург · ORG-9181'),
              ('РЖД · вокзал Казань', 'Казань · ORG-9178'),
            ].map(
              (row) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: SettingRow(
                  icon: Icons.business_outlined,
                  title: row.$1,
                  subtitle: row.$2,
                  color: BureauColors.amber,
                  background: BureauColors.amberSoft,
                  trailing: const BureauPill('ПРОВЕРКА', color: BureauColors.amber, background: BureauColors.amberSoft),
                  onTap: () => pushPage(context, const AdminDetailPage(type: AdminDetailType.organization)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FraudAnalytics extends StatelessWidget {
  const _FraudAnalytics();

  @override
  Widget build(BuildContext context) {
    const values = [94.0, 82.0, 104.0, 71.0, 58.0, 65.0, 48.0];
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _AdminHeader('Антифрод-аналитика', 'Последние 30 дней'),
            const SizedBox(height: 20),
            const Row(
              children: [
                Expanded(child: MetricCard(value: '1,8%', label: 'подозрительных', color: BureauColors.red)),
                SizedBox(width: 10),
                Expanded(child: MetricCard(value: '−24%', label: 'к прошлому месяцу', color: BureauColors.green)),
              ],
            ),
            const SectionTitle('Динамика риска'),
            SoftCard(
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
                              decoration: const BoxDecoration(color: BureauColors.red, borderRadius: BorderRadius.vertical(top: Radius.circular(8))),
                            ),
                          ),
                        ),
                      )
                      .toList(),
                ),
              ),
            ),
            const SectionTitle('Главные паттерны'),
            ...const [
              ('Повторные фото', '184 случая', '↑ 8%'),
              ('Мультиаккаунты', '96 случаев', '↓ 14%'),
              ('Чужие документы', '42 случая', '→'),
            ].map(
              (row) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: SoftCard(
                  child: Row(
                    children: [
                      Expanded(child: Text(row.$1, style: const TextStyle(fontWeight: FontWeight.w800))),
                      Text(row.$2, style: const TextStyle(color: BureauColors.slate, fontSize: 10)),
                      const SizedBox(width: 16),
                      Text(row.$3, style: const TextStyle(color: BureauColors.red, fontWeight: FontWeight.w900)),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum AdminDetailType { flagged, risk, dispute, organization, ads }

class AdminDetailPage extends StatelessWidget {
  const AdminDetailPage({super.key, required this.type});

  final AdminDetailType type;

  String get title => switch (type) {
        AdminDetailType.flagged => 'Проверка публикации',
        AdminDetailType.risk => 'Риск заявления',
        AdminDetailType.dispute => 'Разбор спора',
        AdminDetailType.organization => 'Проверка организации',
        AdminDetailType.ads => 'Реклама и партнёры',
      };

  @override
  Widget build(BuildContext context) {
    return BureauPage(
      title: title,
      subtitle: 'Служебный защищённый контур',
      bottom: FilledButton(
        style: FilledButton.styleFrom(backgroundColor: type == AdminDetailType.organization ? BureauColors.green : BureauColors.amber),
        onPressed: () => Navigator.pop(context),
        child: Text(type == AdminDetailType.organization ? 'Одобрить организацию' : 'Сохранить решение'),
      ),
      child: switch (type) {
        AdminDetailType.flagged => _flagged(context),
        AdminDetailType.risk => _risk(context),
        AdminDetailType.dispute => _dispute(context),
        AdminDetailType.organization => _organization(context),
        AdminDetailType.ads => _ads(context),
      },
    );
  }

  Widget _flagged(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const ItemArtwork(height: 220, icon: Icons.phone_iphone_rounded, color: BureauColors.amber, background: BureauColors.amberSoft),
          const SizedBox(height: 14),
          const Wrap(spacing: 8, children: [BureauPill('СКРЫТЫЕ ДАННЫЕ', color: BureauColors.red, background: BureauColors.redSoft), BureauPill('2 ЖАЛОБЫ', color: BureauColors.slate, background: Colors.white)]),
          const SizedBox(height: 16),
          Text('Найден смартфон', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text('В описании автор указал полный IMEI и точный адрес.', style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: BureauColors.slate)),
          const SectionTitle('Нарушения'),
          const SettingRow(icon: Icons.visibility_off_outlined, title: 'Опубликован идентификатор', subtitle: 'Полный IMEI', color: BureauColors.red, background: BureauColors.redSoft),
          const SizedBox(height: 10),
          const SettingRow(icon: Icons.location_off_outlined, title: 'Раскрыта точная геолокация', subtitle: 'Адрес доступен публично', color: BureauColors.red, background: BureauColors.redSoft),
        ],
      );

  Widget _risk(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SoftCard(
            color: BureauColors.redSoft,
            borderColor: BureauColors.redSoft,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('86/100', style: TextStyle(color: BureauColors.red, fontSize: 30, fontWeight: FontWeight.w900)), Text('риск мошенничества', style: TextStyle(color: BureauColors.slate, fontSize: 10))]),
                BureauPill('ВЫСОКИЙ', color: BureauColors.red, background: Colors.white),
              ],
            ),
          ),
          const SectionTitle('Сигналы модели'),
          ...const [
            ('4 заявления за 24 часа', '+28'),
            ('География не совпадает', '+21'),
            ('Фото найдено в интернете', '+19'),
            ('Новый аккаунт', '+18'),
          ].map(
            (row) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: SettingRow(icon: Icons.warning_amber_rounded, title: row.$1, subtitle: 'Вклад в риск ${row.$2}', color: BureauColors.red, background: BureauColors.redSoft),
            ),
          ),
          const NoticeCard('Рекомендуется ручная проверка и дополнительный вопрос владельцу.', color: BureauColors.red, background: BureauColors.redSoft, icon: Icons.gpp_maybe_outlined),
        ],
      );

  Widget _dispute(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SoftCard(
            color: BureauColors.amberSoft,
            borderColor: BureauColors.amberSoft,
            child: Row(children: [IconTile(icon: Icons.balance_outlined, color: BureauColors.amber, background: Colors.white), SizedBox(width: 12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Передача не состоялась', style: TextStyle(fontWeight: FontWeight.w900)), Text('D-1082 · открыт 24 мин назад', style: TextStyle(color: BureauColors.slate, fontSize: 10))]))]),
          ),
          const SectionTitle('Хронология'),
          ...const [
            ('18:10', 'Владелец подтверждён'),
            ('18:24', 'Обе стороны открыли контакты'),
            ('19:02', 'Встреча отменена нашедшим'),
            ('19:08', 'Владелец открыл спор'),
          ].map(
            (row) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: SoftCard(child: Row(children: [BureauPill(row.$1, color: BureauColors.amber, background: BureauColors.amberSoft), const SizedBox(width: 12), Expanded(child: Text(row.$2, style: const TextStyle(fontWeight: FontWeight.w700)))])),
            ),
          ),
          const SectionTitle('Решение'),
          const TextField(maxLines: 4, decoration: InputDecoration(hintText: 'Комментарий модератора…')),
        ],
      );

  Widget _organization(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SoftCard(
            child: Row(children: [IconTile(icon: Icons.business_rounded, color: BureauColors.green, background: BureauColors.greenSoft, size: 62), SizedBox(width: 13), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('ТЦ «Галерея»', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17)), Text('ИНН 7812345678 · Санкт-Петербург', style: TextStyle(color: BureauColors.slate, fontSize: 10))]))]),
          ),
          const SectionTitle('Автопроверки'),
          ...const ['ИНН найден в ЕГРЮЛ', 'Домен подтверждён', 'Подписант имеет полномочия'].map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: SettingRow(icon: Icons.check_rounded, title: item, subtitle: 'Проверено автоматически', color: BureauColors.green, background: BureauColors.greenSoft, trailing: const Icon(Icons.verified_rounded, color: BureauColors.green)),
            ),
          ),
          const SettingRow(icon: Icons.location_searching_rounded, title: 'Проверить адрес филиала', subtitle: 'Лиговский пр., 30А', color: BureauColors.amber, background: BureauColors.amberSoft, trailing: BureauPill('НУЖНА ПРОВЕРКА', color: BureauColors.amber, background: BureauColors.amberSoft)),
        ],
      );

  Widget _ads(BuildContext context) => const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: MetricCard(value: '₽184К', label: 'доход за месяц', color: BureauColors.green)),
              SizedBox(width: 10),
              Expanded(child: MetricCard(value: '71%', label: 'видимость блоков', color: BureauColors.blue)),
            ],
          ),
          SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: MetricCard(value: '0,08%', label: 'жалобы')),
              SizedBox(width: 10),
              Expanded(child: MetricCard(value: '1 / 5', label: 'частота в ленте', color: BureauColors.amber)),
            ],
          ),
          SectionTitle('Безопасные ограничения'),
          NoticeCard('Критические сценарии — 0 рекламы: доказательства, чат, контакты, QR и передача.'),
          SizedBox(height: 10),
          SettingRow(icon: Icons.ads_click_rounded, title: 'Контекстная реклама', subtitle: 'Без межприложного трекинга', color: BureauColors.green, background: BureauColors.greenSoft, trailing: BureauPill('ВКЛ', color: BureauColors.green, background: BureauColors.greenSoft)),
          SizedBox(height: 10),
          SettingRow(icon: Icons.tune_rounded, title: 'Персонализация', subtitle: 'Только после системного согласия', color: BureauColors.amber, background: BureauColors.amberSoft, trailing: BureauPill('OPT-IN', color: BureauColors.amber, background: BureauColors.amberSoft)),
          SectionTitle('Качество'),
          SettingRow(icon: Icons.verified_outlined, title: 'ERID и маркировка', subtitle: '100% рекламных событий', color: BureauColors.green, background: BureauColors.greenSoft, trailing: BureauPill('НОРМА', color: BureauColors.green, background: BureauColors.greenSoft)),
        ],
      );
}
