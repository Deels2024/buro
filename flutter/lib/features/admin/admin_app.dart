import 'package:flutter/material.dart';

import '../../core/api_widgets.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../data/app_controller.dart';
import '../../data/bureau_api_client.dart';

class AdminShell extends StatefulWidget {
  const AdminShell({super.key});
  @override
  State<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends State<AdminShell> {
  int _index = 0;
  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    if (!app.isAdmin) {
      return const BureauPage(
        title: 'Доступ запрещён',
        subtitle: 'Нужна роль moderator или admin',
        child: NoticeCard(
          'Backend не разрешит административные запросы этому аккаунту.',
          color: BureauColors.red,
          background: BureauColors.redSoft,
        ),
      );
    }
    const pages = [
      AdminDashboardPage(),
      ModerationQueuePage(),
      RiskAndDisputesPage(),
      AdminOrganizationsPage(),
      FraudAnalyticsPage(),
    ];
    return Scaffold(
      body: IndexedStack(index: _index, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) => setState(() => _index = value),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard_rounded),
            label: 'Обзор',
          ),
          NavigationDestination(
            icon: Icon(Icons.fact_check_outlined),
            label: 'Контент',
          ),
          NavigationDestination(
            icon: Icon(Icons.gpp_maybe_outlined),
            label: 'Риски',
          ),
          NavigationDestination(
            icon: Icon(Icons.business_outlined),
            label: 'Орг.',
          ),
          NavigationDestination(
            icon: Icon(Icons.analytics_outlined),
            label: 'Аналитика',
          ),
        ],
      ),
    );
  }
}

class _AdminHeader extends StatelessWidget {
  const _AdminHeader(this.title, {this.actions = const []});
  final String title;
  final List<Widget> actions;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: BureauColors.amber,
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Icon(
          Icons.admin_panel_settings_rounded,
          color: Colors.white,
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            Text(
              'Реальные данные backend',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(fontSize: 10),
            ),
          ],
        ),
      ),
      ...actions,
    ],
  );
}

class AdminDashboardPage extends StatefulWidget {
  const AdminDashboardPage({super.key});
  @override
  State<AdminDashboardPage> createState() => _AdminDashboardPageState();
}

class _AdminDashboardPageState extends State<AdminDashboardPage> {
  late Future<List<dynamic>> _future;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final api = AppScope.of(context, listen: false).api;
    _future = Future.wait([
      api.adminGet('/dashboard'),
      api.adminGet('/audit', query: {'limit': 10}),
    ]);
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: ListView(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
      children: [
        _AdminHeader(
          'Центр модерации',
          actions: [
            IconButton(
              onPressed: () => pushPage(context, const AdsAdminPage()),
              icon: const Icon(Icons.campaign_outlined),
            ),
          ],
        ),
        const SizedBox(height: 18),
        ApiFutureBuilder<List<dynamic>>(
          future: _future,
          builder: (context, values) {
            final data = Map<String, dynamic>.from(values[0] as Map);
            final audit = Map<String, dynamic>.from(values[1] as Map);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: MetricCard(
                        value: '${data['pending_listings']}',
                        label: 'публикаций',
                        color: BureauColors.amber,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: MetricCard(
                        value: '${data['risky_claims']}',
                        label: 'риск-заявлений',
                        color: BureauColors.red,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: MetricCard(
                        value: '${data['open_cases']}',
                        label: 'споров',
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: MetricCard(
                        value: '${data['pending_organizations']}',
                        label: 'организаций',
                      ),
                    ),
                  ],
                ),
                const SectionTitle('Последние действия'),
                for (final item in List<JsonMap>.from(
                  audit['items'] as List,
                )) ...[
                  SettingRow(
                    icon: Icons.history_rounded,
                    title: item['action']?.toString() ?? '',
                    subtitle: '${item['entity_type']} · ${item['created_at']}',
                  ),
                  const SizedBox(height: 10),
                ],
              ],
            );
          },
        ),
      ],
    ),
  );
}

class ModerationQueuePage extends StatefulWidget {
  const ModerationQueuePage({super.key});
  @override
  State<ModerationQueuePage> createState() => _ModerationQueuePageState();
}

class _ModerationQueuePageState extends State<ModerationQueuePage> {
  late Future<List<JsonMap>> _future;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reload();
  }

  void _reload() {
    _future = AppScope.of(context, listen: false).api
        .adminGet('/moderation/listings', query: {'limit': 100})
        .then((value) => List<JsonMap>.from(value as List));
  }

  Future<void> _decide(JsonMap item) async {
    final api = AppScope.of(context, listen: false).api;
    var decision = 'approve';
    final reason = TextEditingController(
      text: 'Публикация соответствует правилам',
    );
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(item['title']?.toString() ?? 'Публикация'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: decision,
                items: const ['approve', 'reject', 'block', 'request_changes']
                    .map(
                      (value) =>
                          DropdownMenuItem(value: value, child: Text(value)),
                    )
                    .toList(),
                onChanged: (value) =>
                    setDialogState(() => decision = value ?? 'approve'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: reason,
                maxLines: 4,
                decoration: const InputDecoration(labelText: 'Причина'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Применить'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) {
      reason.dispose();
      return;
    }
    if (ok == true) {
      await api.adminPost(
        '/moderation/listings/${item['id']}',
        body: {'decision': decision, 'reason': reason.text},
      );
      setState(_reload);
    }
    reason.dispose();
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: ListView(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
      children: [
        const _AdminHeader('Проверка публикаций'),
        const SizedBox(height: 18),
        ApiFutureBuilder<List<JsonMap>>(
          future: _future,
          empty: const NoticeCard(
            'Очередь модерации пуста.',
            color: BureauColors.green,
            background: BureauColors.greenSoft,
          ),
          builder: (context, items) => Column(
            children: [
              for (final item in items) ...[
                SettingRow(
                  icon: item['kind'] == 'found'
                      ? Icons.volunteer_activism_outlined
                      : Icons.search_off_rounded,
                  title: item['title']?.toString() ?? '',
                  subtitle: '${item['category']} · ${item['created_at']}',
                  color: BureauColors.amber,
                  background: BureauColors.amberSoft,
                  onTap: () => _decide(item),
                ),
                const SizedBox(height: 10),
              ],
            ],
          ),
        ),
      ],
    ),
  );
}

class RiskAndDisputesPage extends StatefulWidget {
  const RiskAndDisputesPage({super.key});
  @override
  State<RiskAndDisputesPage> createState() => _RiskAndDisputesPageState();
}

class _RiskAndDisputesPageState extends State<RiskAndDisputesPage> {
  late Future<List<dynamic>> _future;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reload();
  }

  void _reload() {
    final api = AppScope.of(context, listen: false).api;
    _future = Future.wait([
      api.adminGet('/claims/risk', query: {'limit': 100}),
      api.adminGet('/disputes', query: {'limit': 100}),
    ]);
  }

  Future<void> _resolve(JsonMap item) async {
    final api = AppScope.of(context, listen: false).api;
    var decision = 'request_changes';
    final reason = TextEditingController(
      text: 'Требуется дополнительная проверка доказательств',
    );
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Решение по спору'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: decision,
                items: const ['approve', 'reject', 'request_changes']
                    .map(
                      (value) =>
                          DropdownMenuItem(value: value, child: Text(value)),
                    )
                    .toList(),
                onChanged: (value) =>
                    setDialogState(() => decision = value ?? 'request_changes'),
              ),
              const SizedBox(height: 12),
              TextField(controller: reason, maxLines: 4),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Решить'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) {
      reason.dispose();
      return;
    }
    if (ok == true) {
      await api.adminPost(
        '/disputes/${item['id']}/resolve',
        body: {'decision': decision, 'reason': reason.text},
      );
      setState(_reload);
    }
    reason.dispose();
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: ListView(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
      children: [
        const _AdminHeader('Риски и споры'),
        const SizedBox(height: 18),
        ApiFutureBuilder<List<dynamic>>(
          future: _future,
          builder: (context, values) {
            final risks = List<JsonMap>.from(values[0] as List);
            final disputes = List<JsonMap>.from(values[1] as List);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SectionTitle('Рискованные заявления'),
                for (final item in risks) ...[
                  SettingRow(
                    icon: Icons.gpp_maybe_outlined,
                    title: 'Заявление ${item['id'].toString().substring(0, 8)}',
                    subtitle:
                        'Риск ${((((item['risk_score'] as num?) ?? 0) * 100)).round()}% · ${item['status']}',
                    color: BureauColors.red,
                    background: BureauColors.redSoft,
                  ),
                  const SizedBox(height: 10),
                ],
                const SectionTitle('Апелляции'),
                for (final item in disputes) ...[
                  SettingRow(
                    icon: Icons.gavel_rounded,
                    title: item['reason']?.toString() ?? '',
                    subtitle:
                        'Приоритет ${item['priority']} · ${item['created_at']}',
                    color: BureauColors.amber,
                    background: BureauColors.amberSoft,
                    onTap: () => _resolve(item),
                  ),
                  const SizedBox(height: 10),
                ],
                if (disputes.isEmpty)
                  const NoticeCard('Открытых апелляций нет.'),
              ],
            );
          },
        ),
      ],
    ),
  );
}

class AdminOrganizationsPage extends StatefulWidget {
  const AdminOrganizationsPage({super.key});
  @override
  State<AdminOrganizationsPage> createState() => _AdminOrganizationsPageState();
}

class _AdminOrganizationsPageState extends State<AdminOrganizationsPage> {
  late Future<JsonMap> _future;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reload();
  }

  void _reload() => _future = AppScope.of(context, listen: false).api
      .adminGet('/organizations', query: {'limit': 100})
      .then((value) => Map<String, dynamic>.from(value as Map));
  Future<void> _verify(JsonMap item, String decision) async {
    await AppScope.of(context, listen: false).api.adminPost(
      '/organizations/${item['id']}/verify',
      body: {
        'decision': decision,
        'reason': decision == 'approve'
            ? 'Реквизиты подтверждены'
            : 'Реквизиты не прошли проверку',
      },
    );
    setState(_reload);
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: ListView(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
      children: [
        const _AdminHeader('Проверка организаций'),
        const SizedBox(height: 18),
        ApiFutureBuilder<JsonMap>(
          future: _future,
          builder: (context, data) => Column(
            children: [
              for (final item in List<JsonMap>.from(data['items'] as List)) ...[
                SoftCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item['name']?.toString() ?? '',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text('ИНН ${item['inn']} · ${item['status']}'),
                      if (item['status'] == 'pending') ...[
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () => _verify(item, 'reject'),
                                child: const Text('Отклонить'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: FilledButton(
                                onPressed: () => _verify(item, 'approve'),
                                child: const Text('Подтвердить'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 10),
              ],
            ],
          ),
        ),
      ],
    ),
  );
}

class FraudAnalyticsPage extends StatefulWidget {
  const FraudAnalyticsPage({super.key});
  @override
  State<FraudAnalyticsPage> createState() => _FraudAnalyticsPageState();
}

class _FraudAnalyticsPageState extends State<FraudAnalyticsPage> {
  late Future<List<dynamic>> _future;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final api = AppScope.of(context, listen: false).api;
    _future = Future.wait([
      api.adminGet('/analytics/overview'),
      api.adminGet('/matches', query: {'min_score': 0, 'limit': 20}),
      api.adminGet('/users', query: {'limit': 20}),
    ]);
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: ListView(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
      children: [
        const _AdminHeader('Антифрод-аналитика'),
        const SizedBox(height: 18),
        ApiFutureBuilder<List<dynamic>>(
          future: _future,
          builder: (context, values) {
            final overview = Map<String, dynamic>.from(values[0] as Map);
            final kpi = Map<String, dynamic>.from(overview['kpi'] as Map);
            final operations = Map<String, dynamic>.from(
              overview['operations'] as Map,
            );
            final matches = Map<String, dynamic>.from(values[1] as Map);
            final users = Map<String, dynamic>.from(values[2] as Map);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: MetricCard(
                        value: '${kpi['returned']}',
                        label: 'возвращено',
                        color: BureauColors.green,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: MetricCard(
                        value: '${kpi['claim_approval_rate']}%',
                        label: 'одобрено заявлений',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: MetricCard(
                        value: '${operations['webhook_failures']}',
                        label: 'ошибок вебхуков',
                        color: BureauColors.red,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: MetricCard(
                        value: '${operations['support_open']}',
                        label: 'поддержка',
                      ),
                    ),
                  ],
                ),
                const SectionTitle('Воронка'),
                for (final item in List<JsonMap>.from(
                  overview['funnel'] as List,
                )) ...[
                  SettingRow(
                    icon: Icons.filter_alt_outlined,
                    title: item['stage']?.toString() ?? '',
                    subtitle: '${item['value']}',
                  ),
                  const SizedBox(height: 8),
                ],
                const SectionTitle('Сводка контроля'),
                SettingRow(
                  icon: Icons.people_outline_rounded,
                  title: '${users['total']} пользователей',
                  subtitle:
                      'Последние ${List.from(users['items'] as List).length} загружены',
                ),
                const SizedBox(height: 10),
                SettingRow(
                  icon: Icons.auto_awesome_rounded,
                  title: '${matches['total']} совпадений',
                  subtitle: 'Проверяется качество и аномалии',
                ),
              ],
            );
          },
        ),
      ],
    ),
  );
}

class AdsAdminPage extends StatefulWidget {
  const AdsAdminPage({super.key});
  @override
  State<AdsAdminPage> createState() => _AdsAdminPageState();
}

class _AdsAdminPageState extends State<AdsAdminPage> {
  late Future<List<JsonMap>> _future;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reload();
  }

  void _reload() => _future = AppScope.of(context, listen: false).api
      .adminGet('/ads', query: {'limit': 100})
      .then((value) => List<JsonMap>.from(value as List));
  Future<void> _create() async {
    final api = AppScope.of(context, listen: false).api;
    final advertiser = TextEditingController();
    final title = TextEditingController();
    final body = TextEditingController();
    final url = TextEditingController(text: 'https://example.com');
    final erid = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Новая кампания'),
        content: SizedBox(
          width: 500,
          child: ListView(
            shrinkWrap: true,
            children: [
              TextField(
                controller: advertiser,
                decoration: const InputDecoration(labelText: 'Рекламодатель'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: title,
                decoration: const InputDecoration(labelText: 'Заголовок'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: body,
                decoration: const InputDecoration(labelText: 'Текст'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: url,
                decoration: const InputDecoration(labelText: 'Ссылка'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: erid,
                decoration: const InputDecoration(labelText: 'ERID'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Создать'),
          ),
        ],
      ),
    );
    if (!mounted) {
      for (final controller in [advertiser, title, body, url, erid]) {
        controller.dispose();
      }
      return;
    }
    if (ok == true) {
      final now = DateTime.now().toUtc();
      await api.adminPost(
        '/ads',
        body: {
          'advertiser_name': advertiser.text,
          'title': title.text,
          'body': body.text,
          'action_label': 'Открыть',
          'action_url': url.text,
          'placements': ['home_feed', 'search_results'],
          'targeting': <String, dynamic>{},
          'erid': erid.text,
          'age_rating': '0+',
          'starts_at': now.toIso8601String(),
          'ends_at': now.add(const Duration(days: 30)).toIso8601String(),
          'daily_budget_kopecks': 100000,
        },
      );
      setState(_reload);
    }
    for (final controller in [advertiser, title, body, url, erid]) {
      controller.dispose();
    }
  }

  Future<void> _stats(JsonMap ad) async {
    final data = await AppScope.of(
      context,
      listen: false,
    ).api.adminGet('/ads/${ad['id']}/stats');
    if (mounted) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(ad['title']?.toString() ?? ''),
          content: Text(
            'Показы: ${data['impressions']}\nКлики: ${data['clicks']}\nCTR: ${data['ctr']}%',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Закрыть'),
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => BureauPage(
    title: 'Реклама и партнёры',
    subtitle: 'Нативные размещения с ERID',
    actions: [
      IconButton(onPressed: _create, icon: const Icon(Icons.add_rounded)),
    ],
    child: ApiFutureBuilder<List<JsonMap>>(
      future: _future,
      empty: const NoticeCard('Кампаний пока нет.'),
      builder: (context, items) => Column(
        children: [
          for (final item in items) ...[
            SettingRow(
              icon: Icons.campaign_outlined,
              title: item['title']?.toString() ?? '',
              subtitle:
                  '${item['advertiser_name']} · ${item['status']} · ERID ${item['erid']}',
              color: BureauColors.amber,
              background: BureauColors.amberSoft,
              onTap: () => _stats(item),
            ),
            const SizedBox(height: 10),
          ],
        ],
      ),
    ),
  );
}
