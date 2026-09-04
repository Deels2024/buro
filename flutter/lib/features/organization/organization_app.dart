import 'package:file_selector/file_selector.dart';

import 'package:flutter/material.dart';

import '../../core/api_widgets.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../core/production_widgets.dart';
import '../user/management.dart';
import '../../data/app_controller.dart';
import '../../data/bureau_api_client.dart';
import '../user/create_flow.dart';

class OrganizationAuthPage extends StatelessWidget {
  const OrganizationAuthPage({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return BureauPage(
      title: 'Организации',
      subtitle: 'Доступ определяется членством backend',
      bottom: OutlinedButton.icon(
        onPressed: () => pushPage(context, const OrganizationCreatePage()),
        icon: const Icon(Icons.add_business_rounded),
        label: const Text('Подать заявку на подключение'),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const NoticeCard(
            'Отдельного пароля организации нет: сотрудник входит по телефону, а backend проверяет его роль и членство.',
            color: BureauColors.green,
            background: BureauColors.greenSoft,
          ),
          const SectionTitle('Доступные организации'),
          for (final organization in app.organizations) ...[
            SettingRow(
              icon: Icons.business_rounded,
              title: organization['name']?.toString() ?? 'Организация',
              subtitle:
                  'ИНН ${organization['inn']} · ${organization['status']}',
              color: BureauColors.green,
              background: BureauColors.greenSoft,
              onTap: () {
                app.selectOrganization(organization);
                pushPage(
                  context,
                  OrganizationVerifyPage(organization: organization),
                );
              },
            ),
            const SizedBox(height: 10),
          ],
          if (app.organizations.isEmpty)
            const NoticeCard('У аккаунта пока нет членства в организации.'),
        ],
      ),
    );
  }
}

class OrganizationCreatePage extends StatefulWidget {
  const OrganizationCreatePage({super.key});
  @override
  State<OrganizationCreatePage> createState() => _OrganizationCreatePageState();
}

class _OrganizationCreatePageState extends State<OrganizationCreatePage> {
  final _name = TextEditingController();
  final _inn = TextEditingController();
  final _ogrn = TextEditingController();
  @override
  Widget build(BuildContext context) => BureauPage(
    title: 'Подключить организацию',
    subtitle: 'Заявка на проверку',
    bottom: ApiButton(
      label: 'Отправить заявку',
      backgroundColor: BureauColors.green,
      onPressed: () async {
        final app = AppScope.of(context, listen: false);
        final org = await app.api.createOrganization(
          _name.text,
          _inn.text,
          ogrn: _ogrn.text.trim().isEmpty ? null : _ogrn.text.trim(),
        );
        await app.refreshIdentity();
        if (!context.mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => OrganizationVerifyPage(organization: org),
          ),
        );
      },
    ),
    child: Column(
      children: [
        TextField(
          controller: _name,
          decoration: const InputDecoration(labelText: 'Название'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _inn,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'ИНН'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _ogrn,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'ОГРН — необязательно'),
        ),
        const SizedBox(height: 14),
        const NoticeCard(
          'После отправки организация получит статус pending. Проверку завершает модератор.',
          color: BureauColors.amber,
          background: BureauColors.amberSoft,
        ),
      ],
    ),
  );
}

class OrganizationVerifyPage extends StatelessWidget {
  const OrganizationVerifyPage({super.key, required this.organization});
  final JsonMap organization;

  @override
  Widget build(BuildContext context) {
    final verified = organization['status'] == 'verified';
    return BureauPage(
      title: 'Проверка организации',
      subtitle: organization['name']?.toString() ?? '',
      bottom: FilledButton(
        style: FilledButton.styleFrom(backgroundColor: BureauColors.green),
        onPressed: () =>
            pushPage(context, OrganizationShell(organization: organization)),
        child: Text(
          verified ? 'Открыть кабинет' : 'Открыть ограниченный кабинет',
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SoftCard(
            color: verified ? BureauColors.greenSoft : BureauColors.amberSoft,
            borderColor: verified
                ? BureauColors.greenSoft
                : BureauColors.amberSoft,
            child: Row(
              children: [
                IconTile(
                  icon: verified
                      ? Icons.verified_rounded
                      : Icons.hourglass_top_rounded,
                  color: verified ? BureauColors.green : BureauColors.amber,
                  background: Colors.white,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    verified
                        ? 'Организация подтверждена'
                        : 'Заявка ожидает проверки',
                    style: TextStyle(
                      color: verified ? BureauColors.green : BureauColors.amber,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SectionTitle('Данные заявки'),
          SettingRow(
            icon: Icons.business_outlined,
            title: organization['name']?.toString() ?? '',
            subtitle: 'ИНН ${organization['inn']}',
          ),
          const SizedBox(height: 10),
          SettingRow(
            icon: Icons.api_rounded,
            title: 'API интеграция',
            subtitle: organization['api_enabled'] == true
                ? 'Включена'
                : 'Выключена',
            color: BureauColors.green,
            background: BureauColors.greenSoft,
          ),
        ],
      ),
    );
  }
}

class OrganizationShell extends StatefulWidget {
  const OrganizationShell({super.key, required this.organization});
  final JsonMap organization;
  @override
  State<OrganizationShell> createState() => _OrganizationShellState();
}

class _OrganizationShellState extends State<OrganizationShell> {
  int _index = 0;
  @override
  Widget build(BuildContext context) {
    final pages = [
      OrgDashboardPage(organization: widget.organization),
      OrgInventoryPage(organization: widget.organization),
      OrgClaimsPage(organization: widget.organization),
      OrgTeamPage(organization: widget.organization),
      OrgAnalyticsPage(organization: widget.organization),
    ];
    return Theme(
      data: Theme.of(context).copyWith(
        navigationBarTheme: Theme.of(
          context,
        ).navigationBarTheme.copyWith(indicatorColor: BureauColors.greenSoft),
      ),
      child: Scaffold(
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
              icon: Icon(Icons.inventory_2_outlined),
              selectedIcon: Icon(Icons.inventory_2_rounded),
              label: 'Склад',
            ),
            NavigationDestination(
              icon: Icon(Icons.fact_check_outlined),
              selectedIcon: Icon(Icons.fact_check_rounded),
              label: 'Заявки',
            ),
            NavigationDestination(
              icon: Icon(Icons.groups_outlined),
              selectedIcon: Icon(Icons.groups_rounded),
              label: 'Команда',
            ),
            NavigationDestination(
              icon: Icon(Icons.analytics_outlined),
              selectedIcon: Icon(Icons.analytics_rounded),
              label: 'Отчёт',
            ),
          ],
        ),
      ),
    );
  }
}

class _OrgHeader extends StatelessWidget {
  const _OrgHeader(this.title, this.organization, {this.actions = const []});
  final String title;
  final JsonMap organization;
  final List<Widget> actions;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: BureauColors.green,
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Icon(Icons.business_rounded, color: Colors.white),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            Text(
              organization['name']?.toString() ?? '',
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

class OrgDashboardPage extends StatefulWidget {
  const OrgDashboardPage({super.key, required this.organization});
  final JsonMap organization;
  @override
  State<OrgDashboardPage> createState() => _OrgDashboardPageState();
}

class _OrgDashboardPageState extends State<OrgDashboardPage> {
  late Future<JsonMap> _future;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _future = AppScope.of(
      context,
      listen: false,
    ).api.organizationDashboard(widget.organization['id'].toString());
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: ListView(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
      children: [
        _OrgHeader(
          'Операционный обзор',
          widget.organization,
          actions: [
            IconButton(
              onPressed: () => pushPage(
                context,
                OrganizationSettingsPage(organization: widget.organization),
              ),
              icon: const Icon(Icons.settings_outlined),
            ),
          ],
        ),
        const SizedBox(height: 22),
        ApiFutureBuilder<JsonMap>(
          future: _future,
          builder: (context, data) => Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: MetricCard(
                      value: '${data['active_inventory']}',
                      label: 'на хранении',
                      color: BureauColors.green,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: MetricCard(
                      value: '${data['open_claims']}',
                      label: 'открытых заявлений',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: MetricCard(
                      value: '${data['returned_30d']}',
                      label: 'возвращено за 30 дней',
                      color: BureauColors.green,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: MetricCard(
                      value: data['median_return_hours']?.toString() ?? '—',
                      label: 'медиана, часов',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SectionTitle('Быстрые действия'),
        SettingRow(
          icon: Icons.add_a_photo_outlined,
          title: 'Принять новую находку',
          subtitle: 'Фото → описание → ячейка',
          color: BureauColors.green,
          background: BureauColors.greenSoft,
          onTap: () => pushPage(
            context,
            CreateFlowPage(
              initialFound: true,
              organizationId: widget.organization['id'].toString(),
            ),
          ),
        ),
        const SizedBox(height: 10),
        SettingRow(
          icon: Icons.qr_code_scanner_rounded,
          title: 'Сканировать QR передачи',
          subtitle: 'Подтвердить выдачу',
          color: BureauColors.green,
          background: BureauColors.greenSoft,
          onTap: () => pushPage(
            context,
            OrganizationQrScanPage(organization: widget.organization),
          ),
        ),
        const SizedBox(height: 10),
        SettingRow(
          icon: Icons.upload_file_rounded,
          title: 'Массовый импорт',
          subtitle: 'JSON/CSV из учётной системы',
          onTap: () => pushPage(
            context,
            OrganizationBulkImportPage(organization: widget.organization),
          ),
        ),
      ],
    ),
  );
}

class OrgInventoryPage extends StatefulWidget {
  const OrgInventoryPage({super.key, required this.organization});
  final JsonMap organization;
  @override
  State<OrgInventoryPage> createState() => _OrgInventoryPageState();
}

class _OrgInventoryPageState extends State<OrgInventoryPage> {
  String? _status;
  late Future<List<JsonMap>> _future;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reload();
  }

  void _reload() => _future = AppScope.of(
    context,
    listen: false,
  ).api.inventory(widget.organization['id'].toString(), status: _status);
  @override
  Widget build(BuildContext context) => SafeArea(
    child: Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
          child: Column(
            children: [
              _OrgHeader('Инвентарь', widget.organization),
              const SizedBox(height: 14),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'active', label: Text('Активные')),
                  ButtonSegment(value: 'draft', label: Text('Черновики')),
                  ButtonSegment(value: 'closed', label: Text('Закрытые')),
                ],
                selected: _status == null ? <String>{} : {_status!},
                emptySelectionAllowed: true,
                onSelectionChanged: (value) {
                  setState(() {
                    _status = value.firstOrNull;
                    _reload();
                  });
                },
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
            children: [
              ApiFutureBuilder<List<JsonMap>>(
                future: _future,
                empty: const NoticeCard('В выбранном статусе вещей нет.'),
                builder: (context, items) => Column(
                  children: [
                    for (final item in items) ...[
                      SettingRow(
                        icon: Icons.inventory_2_outlined,
                        title: item['title']?.toString() ?? '',
                        subtitle:
                            '${item['storage_code'] ?? 'Без ячейки'} · ${item['status']}',
                        color: BureauColors.green,
                        background: BureauColors.greenSoft,
                        onTap: () => pushPage(
                          context,
                          OrganizationRecordPage(
                            organization: widget.organization,
                            listing: item,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class OrganizationRecordPage extends StatefulWidget {
  const OrganizationRecordPage({
    super.key,
    required this.organization,
    required this.listing,
  });
  final JsonMap organization;
  final JsonMap listing;
  @override
  State<OrganizationRecordPage> createState() => _OrganizationRecordPageState();
}

class _OrganizationRecordPageState extends State<OrganizationRecordPage> {
  @override
  Widget build(BuildContext context) => EditListingPage(listingId: widget.listing['id'].toString());
}

class OrgClaimsPage extends StatefulWidget {
  const OrgClaimsPage({super.key, required this.organization});
  final JsonMap organization;
  @override
  State<OrgClaimsPage> createState() => _OrgClaimsPageState();
}

class _OrgClaimsPageState extends State<OrgClaimsPage> {
  late Future<List<JsonMap>> _future;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _future = AppScope.of(
      context,
      listen: false,
    ).api.organizationClaims(widget.organization['id'].toString());
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: ListView(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
      children: [
        _OrgHeader('Очередь заявлений', widget.organization),
        const SizedBox(height: 18),
        ApiFutureBuilder<List<JsonMap>>(
          future: _future,
          empty: const NoticeCard('Заявлений пока нет.'),
          builder: (context, claims) => Column(
            children: [
              for (final claim in claims) ...[
                SettingRow(
                  icon: Icons.fact_check_outlined,
                  title: 'Заявление ${claim['id'].toString().substring(0, 8)}',
                  subtitle:
                      '${claim['status']} · риск ${(((claim['risk_score'] as num?) ?? 0) * 100).round()}%',
                  color: claim['status'] == 'approved'
                      ? BureauColors.green
                      : BureauColors.amber,
                  background: claim['status'] == 'approved'
                      ? BureauColors.greenSoft
                      : BureauColors.amberSoft,
                  onTap: () => pushPage(
                    context,
                    OrganizationClaimPage(
                      organization: widget.organization,
                      claim: claim,
                    ),
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

class OrganizationClaimPage extends StatefulWidget {
  const OrganizationClaimPage({
    super.key,
    required this.organization,
    required this.claim,
  });
  final JsonMap organization;
  final JsonMap claim;
  @override
  State<OrganizationClaimPage> createState() => _OrganizationClaimPageState();
}

class _OrganizationClaimPageState extends State<OrganizationClaimPage> {
  @override
  Widget build(BuildContext context) => ClaimReviewPage(claimId: widget.claim['id'].toString());
}

class OrgTeamPage extends StatefulWidget {
  const OrgTeamPage({super.key, required this.organization});
  final JsonMap organization;
  @override
  State<OrgTeamPage> createState() => _OrgTeamPageState();
}

class _OrgTeamPageState extends State<OrgTeamPage> {
  late Future<List<JsonMap>> _future;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reload();
  }

  void _reload() => _future = AppScope.of(
    context,
    listen: false,
  ).api.team(widget.organization['id'].toString());
  Future<void> _invite() async {
    final api = AppScope.of(context, listen: false).api;
    final phone = TextEditingController(text: '+7');
    var role = 'operator';
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Пригласить сотрудника'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: phone,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'Телефон'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: role,
                items: const ['manager', 'operator', 'viewer']
                    .map(
                      (item) =>
                          DropdownMenuItem(value: item, child: Text(item)),
                    )
                    .toList(),
                onChanged: (value) =>
                    setDialogState(() => role = value ?? 'operator'),
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
              child: const Text('Пригласить'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) {
      phone.dispose();
      return;
    }
    if (ok == true) {
      await api.inviteMember(
        widget.organization['id'].toString(),
        phone.text,
        role,
      );
      setState(_reload);
    }
    phone.dispose();
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: ListView(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
      children: [
        _OrgHeader(
          'Команда и роли',
          widget.organization,
          actions: [
            IconButton(
              onPressed: _invite,
              icon: const Icon(Icons.person_add_alt_rounded),
            ),
          ],
        ),
        const SizedBox(height: 18),
        ApiFutureBuilder<List<JsonMap>>(
          future: _future,
          empty: const NoticeCard('Сотрудников нет.'),
          builder: (context, members) => Column(
            children: [
              for (final member in members) ...[
                SettingRow(
                  icon: Icons.person_outline_rounded,
                  title: member['display_name']?.toString() ?? '',
                  subtitle: '${member['role']} · ${member['status']}',
                  color: BureauColors.green,
                  background: BureauColors.greenSoft,
                ),
                const SizedBox(height: 10),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () => pushPage(
            context,
            OrganizationBranchesPage(organization: widget.organization),
          ),
          icon: const Icon(Icons.storefront_outlined),
          label: const Text('Филиалы'),
        ),
      ],
    ),
  );
}

class OrgAnalyticsPage extends StatefulWidget {
  const OrgAnalyticsPage({super.key, required this.organization});
  final JsonMap organization;
  @override
  State<OrgAnalyticsPage> createState() => _OrgAnalyticsPageState();
}

class _OrgAnalyticsPageState extends State<OrgAnalyticsPage> {
  late Future<JsonMap> _future;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _future = AppScope.of(
      context,
      listen: false,
    ).api.organizationAnalytics(widget.organization['id'].toString());
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: ListView(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
      children: [
        _OrgHeader('Аналитика возвратов', widget.organization),
        const SizedBox(height: 18),
        ApiFutureBuilder<JsonMap>(
          future: _future,
          builder: (context, data) => Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: MetricCard(
                      value: '${data['registered']}',
                      label: 'зарегистрировано',
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: MetricCard(
                      value: '${data['returned']}',
                      label: 'возвращено',
                      color: BureauColors.green,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              MetricCard(
                value: '${data['return_rate']}%',
                label: 'доля возврата за ${data['period_days']} дней',
                color: BureauColors.green,
              ),
              const SectionTitle('Категории'),
              for (final category in List<JsonMap>.from(
                data['categories'] as List,
              )) ...[
                SettingRow(
                  icon: Icons.category_outlined,
                  title: category['category']?.toString() ?? '',
                  subtitle: '${category['count']} вещей',
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

class OrganizationQrScanPage extends StatefulWidget {
  const OrganizationQrScanPage({super.key, required this.organization});
  final JsonMap organization;
  @override
  State<OrganizationQrScanPage> createState() => _OrganizationQrScanPageState();
}

class _OrganizationQrScanPageState extends State<OrganizationQrScanPage> {
  final _token = TextEditingController();
  JsonMap? _result;
  @override
  Widget build(BuildContext context) => BureauPage(
    title: 'Выдача по QR',
    subtitle: widget.organization['name']?.toString() ?? '',
    bottom: ApiButton(
      label: 'Подтвердить выдачу',
      backgroundColor: BureauColors.green,
      onPressed: () async {
        _result = await AppScope.of(
          context,
          listen: false,
        ).api.scanHandover(_token.text.trim());
        setState(() {});
      },
    ),
    child: Column(
      children: [
        Container(
          height: 240,
          decoration: BoxDecoration(
            color: BureauColors.greenSoft,
            borderRadius: BorderRadius.circular(26),
          ),
          child: const Center(
            child: Icon(
              Icons.qr_code_scanner_rounded,
              size: 110,
              color: BureauColors.green,
            ),
          ),
        ),
        const SizedBox(height: 14),
        TextButton.icon(onPressed: () async {
          final code = await Navigator.push<String>(context,MaterialPageRoute(builder: (_) => const ScanHandoverPage()));
          if (mounted && code != null) setState(() => _token.text=code);
        }, icon: const Icon(Icons.camera_alt_outlined),label: const Text('Открыть камеру')),
        TextField(
          controller: _token,
          maxLines: 3,
          decoration: const InputDecoration(labelText: 'Данные QR-кода'),
        ),
        if (_result != null) ...[
          const SizedBox(height: 14),
          NoticeCard(
            _result!['completed_at'] == null
                ? 'Сторона организации подтверждена. Ожидаем владельца.'
                : 'Передача завершена.',
            color: BureauColors.green,
            background: BureauColors.greenSoft,
          ),
        ],
      ],
    ),
  );
}

class OrganizationBulkImportPage extends StatefulWidget {
  const OrganizationBulkImportPage({super.key, required this.organization});
  final JsonMap organization;
  @override
  State<OrganizationBulkImportPage> createState() =>
      _OrganizationBulkImportPageState();
}

class _OrganizationBulkImportPageState
    extends State<OrganizationBulkImportPage> {
  final _json = TextEditingController(text: 'title;description;category;region;event_at;storage_code\nЗонт;Чёрный складной зонт;other;Санкт-Петербург;${DateTime.now().toUtc().toIso8601String()};A-01\n');
  @override
  void dispose() { _json.dispose(); super.dispose(); }
  JsonMap? _result;
  @override
  Widget build(BuildContext context) => BureauPage(
    title: 'Массовый импорт',
    subtitle: 'До 1000 записей за запрос',
    bottom: ApiButton(
      label: 'Импортировать',
      backgroundColor: BureauColors.green,
      onPressed: () async {
        _result = Map<String,dynamic>.from(await AppScope.of(context,listen:false).api.request('POST','/organizations/${widget.organization['id']}/bulk-import-csv',body:{'csv':_json.text}) as Map);
        setState(() {});
      },
    ),
    child: Column(
      children: [
        const NoticeCard('CSV в UTF-8: title, description, category, region, event_at. Дополнительно storage_code, branch_id. Записи создаются как черновики.'),
        TextButton.icon(icon: const Icon(Icons.upload_file),label: const Text('Выбрать CSV-файл'),onPressed: () async {
          try {
            final file = await openFile(acceptedTypeGroups: [const XTypeGroup(label:'CSV',extensions:['csv'],uniformTypeIdentifiers:['public.comma-separated-values-text'],mimeTypes:['text/csv'])]);
            if(file==null)return;
            if(await file.length()>1024*1024)throw BureauApiException(413,'Файл больше 1 МБ');
            final content=await file.readAsString();
            if(mounted)setState(()=>_json.text=content);
          } catch(e) { if(context.mounted)showApiError(context,e); }
        }),
        TextField(
          controller: _json,
          maxLines: 16,
          decoration: const InputDecoration(
            labelText: 'Содержимое CSV',
            alignLabelWithHint: true,
          ),
        ),
        if (_result != null) ...[
          const SizedBox(height: 14),
          NoticeCard(
            'Создано черновиков: ${_result!['processed']} из ${_result!['total']}. Ошибки: ${_result!['errors']}',
            color: BureauColors.green,
            background: BureauColors.greenSoft,
          ),
        ],
      ],
    ),
  );
}

class OrganizationBranchesPage extends StatefulWidget {
  const OrganizationBranchesPage({super.key, required this.organization});
  final JsonMap organization;
  @override
  State<OrganizationBranchesPage> createState() =>
      _OrganizationBranchesPageState();
}

class _OrganizationBranchesPageState extends State<OrganizationBranchesPage> {
  late Future<List<JsonMap>> _future;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reload();
  }

  void _reload() => _future = AppScope.of(
    context,
    listen: false,
  ).api.branches(widget.organization['id'].toString());
  Future<void> _add() async {
    final api = AppScope.of(context, listen: false).api;
    final name = TextEditingController();
    final address = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Новый филиал'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              decoration: const InputDecoration(labelText: 'Название'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: address,
              decoration: const InputDecoration(labelText: 'Публичный адрес'),
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
            child: const Text('Добавить'),
          ),
        ],
      ),
    );
    if (!mounted) {
      name.dispose();
      address.dispose();
      return;
    }
    if (ok == true) {
      await api.createBranch(widget.organization['id'].toString(), {
        'name': name.text,
        'public_address': address.text,
        'exact_location': null,
        'timezone': 'Europe/Moscow',
      });
      setState(_reload);
    }
    name.dispose();
    address.dispose();
  }

  @override
  Widget build(BuildContext context) => BureauPage(
    title: 'Филиалы',
    subtitle: widget.organization['name']?.toString() ?? '',
    actions: [IconButton(onPressed: _add, icon: const Icon(Icons.add_rounded))],
    child: ApiFutureBuilder<List<JsonMap>>(
      future: _future,
      empty: const NoticeCard('Филиалов пока нет.'),
      builder: (context, items) => Column(
        children: [
          for (final item in items) ...[
            SettingRow(
              icon: Icons.storefront_outlined,
              title: item['name']?.toString() ?? '',
              subtitle:
                  '${item['public_address']} · ${item['active'] == true ? 'активен' : 'выключен'}',
              color: BureauColors.green,
              background: BureauColors.greenSoft,
            ),
            const SizedBox(height: 10),
          ],
        ],
      ),
    ),
  );
}

class OrganizationSettingsPage extends StatefulWidget {
  const OrganizationSettingsPage({super.key, required this.organization});
  final JsonMap organization;
  @override
  State<OrganizationSettingsPage> createState() =>
      _OrganizationSettingsPageState();
}

class _OrganizationSettingsPageState extends State<OrganizationSettingsPage> {
  late bool _enabled = widget.organization['api_enabled'] == true;
  late Future<List<dynamic>> _future;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reload();
  }

  void _reload() {
    final api = AppScope.of(context, listen: false).api;
    final id = widget.organization['id'].toString();
    _future = Future.wait([api.apiKeys(id), api.webhooks(id)]);
  }

  Future<void> _createKey() async {
    final value = await AppScope.of(context, listen: false).api.createApiKey(
      widget.organization['id'].toString(),
      'Mobile integration',
      ['inventory:read', 'inventory:write', 'claims:read'],
    );
    if (mounted) {
      await showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Сохраните ключ сейчас'),
          content: SelectableText(value['api_key']?.toString() ?? ''),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Готово'),
            ),
          ],
        ),
      );
      setState(_reload);
    }
  }

  Future<void> _createWebhook() async {
    final api = AppScope.of(context, listen: false).api;
    final url = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Новый вебхук'),
        content: TextField(
          controller: url,
          decoration: const InputDecoration(labelText: 'HTTPS URL'),
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
      url.dispose();
      return;
    }
    if (ok == true) {
      final result = await api.createWebhook(
        widget.organization['id'].toString(),
        'Mobile webhook',
        url.text,
        ['listing.created', 'claim.submitted', 'handover.completed'],
      );
      if (mounted) {
        await showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Секрет подписи'),
            content: SelectableText(result['signing_secret']?.toString() ?? ''),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Готово'),
              ),
            ],
          ),
        );
        setState(_reload);
      }
    }
    url.dispose();
  }

  @override
  Widget build(BuildContext context) => BureauPage(
    title: 'Настройки и API',
    subtitle: widget.organization['name']?.toString() ?? '',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          value: _enabled,
          title: const Text('Разрешить API'),
          subtitle: const Text('Только для подтверждённой организации'),
          onChanged: (value) async {
            final result = await AppScope.of(context, listen: false).api
                .updateOrganizationSettings(
                  widget.organization['id'].toString(),
                  value,
                );
            setState(() => _enabled = result['api_enabled'] == true);
          },
        ),
        ApiFutureBuilder<List<dynamic>>(
          future: _future,
          builder: (context, data) {
            final keys = data[0] as List<JsonMap>;
            final hooks = data[1] as List<JsonMap>;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SectionTitle('API-ключи'),
                for (final key in keys) ...[
                  SettingRow(
                    icon: Icons.key_rounded,
                    title: key['name']?.toString() ?? '',
                    subtitle: '${key['key_prefix']} · ${key['status']}',
                  ),
                  const SizedBox(height: 10),
                ],
                OutlinedButton.icon(
                  onPressed: _enabled ? _createKey : null,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Создать API-ключ'),
                ),
                const SectionTitle('Вебхуки'),
                for (final hook in hooks) ...[
                  SettingRow(
                    icon: Icons.webhook_rounded,
                    title: hook['name']?.toString() ?? '',
                    subtitle: '${hook['url']} · ${hook['status']}',
                  ),
                  const SizedBox(height: 10),
                ],
                OutlinedButton.icon(
                  onPressed: _createWebhook,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Добавить вебхук'),
                ),
              ],
            );
          },
        ),
      ],
    ),
  );
}
