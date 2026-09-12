import '../../core/location_editor.dart';
import '../../core/brand_artwork.dart';
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/api_widgets.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../core/production_widgets.dart';
import 'management.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../data/app_controller.dart';
import '../../data/bureau_api_client.dart';
import '../admin/admin_app.dart';
import '../catalog/catalog_page.dart';
import '../organization/organization_app.dart';
import 'create_flow.dart';
import 'match_flow.dart';

class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key});

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  final _controller = PageController();
  int _index = 0;

  static const _slides = [
    (
      Icons.hub_rounded,
      'Одна сеть для всей России',
      'Ищите среди публикаций людей, транспорта, торговых центров, вузов и городских служб.',
      BureauColors.blue,
      BureauColors.blueSoft,
    ),
    (
      Icons.verified_user_rounded,
      'Контакты под защитой',
      'Сначала доказательство владения. Точное место и контакты откроются только после подтверждения.',
      BureauColors.green,
      BureauColors.greenSoft,
    ),
    (
      Icons.auto_awesome_rounded,
      'ИИ видит похожее',
      'Загрузите фото — система опишет вещь, создаст теги и предложит вероятные совпадения.',
      BureauColors.blue,
      BureauColors.blueSoft,
    ),
  ];

  void _openAuth() => Navigator.of(
    context,
  ).pushReplacement(MaterialPageRoute<void>(builder: (_) => const AuthPage()));

  void _next() {
    if (_index == _slides.length - 1) return _openAuth();
    _controller.nextPage(
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: BureauColors.blue,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Center(
                      child: Text(
                        'БН',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 11),
                  Expanded(child: Text(
                    'Бюро находок',
                    style: Theme.of(context).textTheme.titleMedium,
                  )),
                  TextButton(
                    onPressed: _openAuth,
                    child: const Text('Пропустить'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _slides.length,
                onPageChanged: (value) => setState(() => _index = value),
                itemBuilder: (context, index) {
                  final slide = _slides[index];
                  return LayoutBuilder(builder: (context, constraints) {
                    final artSize = (constraints.maxHeight * .42).clamp(100.0, 250.0).toDouble();
                    return SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                      child: Center(child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 520),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Center(child: BureauIllustration(
                            artwork: index == 1 ? BureauArtwork.handover : BureauArtwork.belongings,
                            size: artSize,
                          )),
                          const SizedBox(height: 24),
                          BureauPill('${index + 1} / ${_slides.length}', color: slide.$4, background: slide.$5),
                          const SizedBox(height: 16),
                          Text(slide.$2, style: Theme.of(context).textTheme.headlineSmall),
                          const SizedBox(height: 12),
                          Text(slide.$3, style: Theme.of(context).textTheme.bodyLarge
                            ?.copyWith(color: BureauColors.slate)),
                        ]),
                      )),
                    );
                  });
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 22),
              child: FilledButton(
                onPressed: _next,
                child: Text(_index == _slides.length - 1 ? 'Начать' : 'Далее'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AuthPage extends StatefulWidget {
  const AuthPage({super.key});

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final _phone = TextEditingController(text: '+7');

  @override
  void dispose() {
    _phone.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BureauPage(
      title: 'Войти в аккаунт',
      subtitle: 'Совпадения и обращения всегда под рукой',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 12),
          const ReturnWelcome(),
          const SizedBox(height: 24),
          TextField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            autofillHints: const [AutofillHints.telephoneNumber],
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.phone_rounded),
              hintText: '+7 (___) ___-__-__',
            ),
          ),
          const SizedBox(height: 14),
          ApiButton(
            label: 'Получить код',
            onPressed: () async {
              final controller = AppScope.of(context, listen: false);
              final result = await controller.requestCode(_phone.text);
              if (!context.mounted) return;
              pushPage(
                context,
                VerifyPhonePage(
                  initialRetryAfter: _retryAfterFromResult(result),
                ),
              );
            },
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: null,
            icon: const Icon(Icons.account_balance_outlined),
            label: const Text('Госуслуги — после подключения ЕСИА'),
          ),
          const SizedBox(height: 26),
          const NoticeCard(
            'Номер телефона не показывается другим пользователям и используется только для входа.',
          ),
          const SizedBox(height: 22),
          Text(
            'Продолжая, вы принимаете правила сервиса и политику конфиденциальности.',
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class VerifyPhonePage extends StatefulWidget {
  const VerifyPhonePage({super.key, this.initialRetryAfter = 60});

  final int initialRetryAfter;

  @override
  State<VerifyPhonePage> createState() => _VerifyPhonePageState();
}

class _VerifyPhonePageState extends State<VerifyPhonePage> {
  final _code = TextEditingController();
  Timer? _retryTimer;
  late int _retryAfter;
  bool _resending = false;

  @override
  void initState() {
    super.initState();
    _retryAfter = widget.initialRetryAfter;
    _scheduleRetryTimer();
  }

  void _scheduleRetryTimer() {
    _retryTimer?.cancel();
    if (_retryAfter <= 0) return;
    _retryTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return timer.cancel();
      setState(() {
        if (_retryAfter <= 1) {
          _retryAfter = 0;
          timer.cancel();
        } else {
          _retryAfter -= 1;
        }
      });
    });
  }

  void _restartRetryTimer(int seconds) {
    setState(() => _retryAfter = seconds);
    _scheduleRetryTimer();
  }

  Future<void> _resendCode(AppController controller) async {
    if (_retryAfter > 0 || _resending) return;
    setState(() => _resending = true);
    try {
      final result = await controller.requestCode(controller.pendingPhone ?? '');
      if (!mounted) return;
      _restartRetryTimer(_retryAfterFromResult(result));
      showApiSuccess(context, 'Новый код отправлен');
    } catch (error) {
      if (mounted) showApiError(context, error);
    } finally {
      if (mounted) setState(() => _resending = false);
    }
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final mfa = controller.mfaTicket != null;
    final recovering = controller.state == AppSessionState.unavailable;
    return BureauPage(
      title: recovering ? 'Вход подтверждён' : mfa ? 'Двухфакторная защита' : 'Введите код',
      subtitle: recovering ? 'Не удалось загрузить профиль. Повторите подключение без нового SMS.' : mfa
          ? 'Код из приложения-аутентификатора'
          : 'SMS отправлено на ${controller.pendingPhone ?? 'ваш телефон'}',
      child: Column(
        children: [
          const SizedBox(height: 35),
          if (!recovering) TextField(
            controller: _code,
            autofocus: true,
            textAlign: TextAlign.center,
            maxLength: 6,
            keyboardType: TextInputType.number,
            autofillHints: const [AutofillHints.oneTimeCode],
            decoration: const InputDecoration(
              counterText: '',
              hintText: '••••••',
            ),
          ),
          const SizedBox(height: 20),
          ApiButton(
            label: recovering ? 'Повторить подключение' : 'Подтвердить',
            onPressed: () async {
              if (recovering) {
                await controller.initialize();
                if (!controller.isSignedIn) {
                  throw BureauApiException(0, controller.lastError ?? 'Не удалось восстановить вход');
                }
              } else if (controller.mfaTicket != null) {
                await controller.verifyAdmin2fa(_code.text);
              } else {
                final complete = await controller.verifyCode(_code.text);
                if (!complete) {
                  _code.clear();
                  return;
                }
              }
              if (!context.mounted) return;
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute<void>(builder: (_) => const UserShell()),
                (route) => false,
              );
            },
          ),
          const SizedBox(height: 18),
          if (!mfa && !recovering)
            TextButton(
              onPressed: _retryAfter > 0 || _resending
                  ? null
                  : () => _resendCode(controller),
              child: Text(
                _resending
                    ? 'Отправляем код…'
                    : _retryAfter > 0
                    ? 'Отправить повторно через $_retryAfter с'
                    : 'Отправить код повторно',
              ),
            ),
        ],
      ),
    );
  }
}

int _retryAfterFromResult(JsonMap result) {
  final value = result['retry_after'];
  final seconds = value is num ? value.toInt() : 60;
  return seconds > 0 ? seconds : 60;
}

class UserShell extends StatefulWidget {
  const UserShell({super.key, this.initialIndex = 0});

  final int initialIndex;

  @override
  State<UserShell> createState() => _UserShellState();
}

class _UserShellState extends State<UserShell> {
  late int _index = widget.initialIndex;
  bool _opened = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final app = AppScope.of(context, listen: false);
    if (_opened || app.initialActionHandled) return;
    _opened = true;
    final params = Uri.base.queryParameters;
    final action = params['action'], id = params['listing'];
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || app.initialActionHandled) return;
      app.initialActionHandled = true;
      Widget? target;
      if (action == 'found' || action == 'lost') target = CreateFlowPage(initialFound: action == 'found');
      if (action == 'claim' && id != null) target = MatchFlowPage(listingId: id);
      if (action == 'listing' && id != null) target = ItemDetailPage(listingId: id);
      if (action == 'support') target = const SupportCreatePage();
      if (action == 'organization') target = const OrganizationAuthPage();
      if (target != null) pushPage(context, target);
    });
  }


  @override
  Widget build(BuildContext context) {
    if (!AppScope.of(context).isSignedIn) return const AuthPage();
    final pages = <Widget>[
      HomeView(onSearch: () => setState(() => _index = 1)),
      const SearchView(),
      const CreateEntryView(),
      const CasesView(),
      const ProfileView(),
    ];
    return Scaffold(
      body: Row(children: [
        if (MediaQuery.sizeOf(context).width >= 900) NavigationRail(
          selectedIndex: _index, onDestinationSelected: (i) => setState(() => _index = i),
          labelType: NavigationRailLabelType.all,
          destinations: const [
            NavigationRailDestination(icon: Icon(Icons.home_outlined), label: Text('Главная')),
            NavigationRailDestination(icon: Icon(Icons.search), label: Text('Поиск')),
            NavigationRailDestination(icon: Icon(Icons.add_circle_outline), label: Text('Добавить')),
            NavigationRailDestination(icon: Icon(Icons.forum_outlined), label: Text('Обращения')),
            NavigationRailDestination(icon: Icon(Icons.person_outline), label: Text('Профиль')),
          ],
        ),
        Expanded(child: IndexedStack(index: _index, children: pages)),
      ]),
      bottomNavigationBar: MediaQuery.sizeOf(context).width >= 900 ? null : NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) => setState(() => _index = value),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: 'Главная',
          ),
          NavigationDestination(
            icon: Icon(Icons.search_rounded),
            label: 'Поиск',
          ),
          NavigationDestination(
            icon: Icon(Icons.add_circle_outline_rounded),
            selectedIcon: Icon(Icons.add_circle_rounded),
            label: 'Добавить',
          ),
          NavigationDestination(
            icon: Icon(Icons.forum_outlined),
            selectedIcon: Icon(Icons.forum_rounded),
            label: 'Обращения',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline_rounded),
            selectedIcon: Icon(Icons.person_rounded),
            label: 'Профиль',
          ),
        ],
      ),
    );
  }
}

class HomeView extends StatefulWidget {
  const HomeView({super.key, required this.onSearch});
  final VoidCallback onSearch;

  @override
  State<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<HomeView> {
  Future<List<dynamic>>? _future;

  Future<List<dynamic>> _load() {
    final api = AppScope.of(context, listen: false).api;
    return Future.wait([
      api.search(limit: 6),
      api.notifications(limit: 10).catchError((_) => <JsonMap>[]),
      api.currentAd('home_feed').catchError((_) => null),
    ]);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _future ??= _load();
  }

  Future<void> _refresh() async {
    final future = _load();
    setState(() => _future = future);
    await future;
  }

  @override
  Widget build(BuildContext context) {
    final user = AppScope.of(context).currentUser ?? const <String, dynamic>{};
    final name = user['display_name']?.toString().trim() ?? '';
    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
          child: RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
              children: [
                Row(children: [
                  Container(
                    width: 44, height: 44,
                    decoration: BoxDecoration(color: BureauColors.blue,
                      borderRadius: BorderRadius.circular(15)),
                    child: const Center(child: Text('БН', textScaler: TextScaler.noScaling, style: TextStyle(
                      color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700))),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Бюро находок', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 3),
                    Text(name.isEmpty ? 'Здравствуйте!' : 'Здравствуйте, $name',
                      maxLines: 2, overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall),
                  ])),
                  IconButton(tooltip: 'Уведомления',
                    onPressed: () => pushPage(context, const NotificationsPage()),
                    icon: const Icon(Icons.notifications_none_rounded, color: BureauColors.navy)),
                ]),
                const SizedBox(height: 22),
                DiscoveryHero(onSearch: widget.onSearch),
                const SizedBox(height: 16),
                LayoutBuilder(builder: (context, constraints) {
                  final actions = [
                    _QuickAction(icon: Icons.search_off_rounded, title: 'Я потерял',
                      subtitle: 'Рассказать о пропаже', color: BureauColors.blue,
                      onTap: () => pushPage(context, const CreateFlowPage(initialFound: false))),
                    _QuickAction(icon: Icons.volunteer_activism_outlined, title: 'Я нашёл',
                      subtitle: 'Помочь вернуть вещь', color: BureauColors.green,
                      onTap: () => pushPage(context, const CreateFlowPage(initialFound: true))),
                  ];
                  if (constraints.maxWidth < 300 || MediaQuery.textScalerOf(context).scale(16) > 20) {
                    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      actions[0], const SizedBox(height: 12), actions[1],
                    ]);
                  }
                  return IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Expanded(child: actions[0]), const SizedBox(width: 12), Expanded(child: actions[1]),
                  ]));
                }),
                const SizedBox(height: 16),
                const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(Icons.shield_outlined, color: BureauColors.green, size: 18),
                  SizedBox(width: 8),
                  Expanded(child: Text('Контакты и точный адрес не публикуются.',
                    style: TextStyle(color: BureauColors.slate, fontSize: 12, height: 1.45))),
                ]),
                const SectionTitle('Последние объявления'),
                FutureBuilder<List<dynamic>>(
                  future: _future,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState != ConnectionState.done) {
                      return const Padding(padding: EdgeInsets.all(24),
                        child: Center(child: CircularProgressIndicator()));
                    }
                    if (snapshot.hasError) {
                      return NoticeCard(apiErrorText(snapshot.error!),
                        color: BureauColors.red, background: BureauColors.redSoft);
                    }
                    final response = snapshot.data!;
                    final items = List<JsonMap>.from((response[0] as JsonMap)['items'] as List);
                    final ad = response[2] as JsonMap?;
                    return Column(children: [
                      for (var index = 0; index < items.length; index++) ...[
                        _ListingCard(listing: items[index]),
                        const SizedBox(height: 12),
                        if (index == 0 && ad != null) ...[
                          _LiveAdCard(ad: ad, placement: 'home_feed'),
                          const SizedBox(height: 12),
                        ],
                      ],
                      if (items.isEmpty) const NoticeCard(
                        'Активных публикаций пока нет. Создайте первую запись.'),
                    ]);
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({required this.icon, required this.title,
    required this.subtitle, required this.color, required this.onTap});
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => SoftCard(
    onTap: onTap,
    padding: const EdgeInsets.all(16),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, color: color, size: 26),
      const SizedBox(height: 14),
      Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(color: color)),
      const SizedBox(height: 5),
      Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
    ]),
  );
}

class SearchView extends StatefulWidget {
  const SearchView({super.key});

  @override
  State<SearchView> createState() => _SearchViewState();
}

class _SearchViewState extends State<SearchView> {
  final _query = TextEditingController();
  Timer? _debounce;
  bool _map = false;
  int _offset = 0;
  SearchFilters _filters = const SearchFilters();
  Future<JsonMap>? _results;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Keyboard, theme and accessibility changes must not restart an active request.
    _results ??= _search();
  }

  Future<JsonMap> _search() => AppScope.of(context, listen: false).api.search(
    query: _query.text.trim().isEmpty ? null : _query.text.trim(),
    kind: _filters.kind,
    category: _filters.category,
    region: _filters.region,
    since: _filters.since,
    limit: 24,
    offset: _offset,
  );

  void _reload() {
    _debounce?.cancel();
    if (!mounted) return;
    setState(() { _offset = 0; _results = _search(); });
  }

  void _reset() {
    _query.clear();
    _filters = const SearchFilters();
    _reload();
  }

  void _setKind(String? kind) {
    _filters = SearchFilters(kind: kind, category: _filters.category, region: _filters.region, since: _filters.since);
    _reload();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Поиск',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ),
                IconButton(
                  onPressed: () => pushPage(context, const SavedPage()),
                  icon: const Icon(Icons.bookmark_border_rounded),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
              children: [
                TextField(
                  controller: _query,
                  maxLength: 200,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) { FocusScope.of(context).unfocus(); _reload(); },
                  onChanged: (_) {
                    _debounce?.cancel();
                    _debounce = Timer(
                      const Duration(milliseconds: 350),
                      _reload,
                    );
                  },
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search_rounded),
                    hintText: 'Вещь, цвет, бренд или особая примета',
                    counterText: '',
                    suffixIcon: _query.text.isEmpty ? null : IconButton(
                      tooltip: 'Очистить запрос', icon: const Icon(Icons.close),
                      onPressed: () { _query.clear(); _reload(); },
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  ChoiceChip(label: const Text('Всё'), selected: _filters.kind == null, onSelected: (_) => _setKind(null)),
                  ChoiceChip(label: const Text('Я потерял'), selected: _filters.kind == 'found', onSelected: (_) => _setKind('found')),
                  ChoiceChip(label: const Text('Я нашёл'), selected: _filters.kind == 'lost', onSelected: (_) => _setKind('lost')),
                ]),
                const SizedBox(height: 8),
                Text(_filters.kind == 'found' ? 'Ищем среди найденных вещей'
                  : _filters.kind == 'lost' ? 'Ищем объявления тех, кто потерял вещь' : 'Ищем среди пропаж и находок'),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    GestureDetector(
                      onTap: () => setState(() => _map = !_map),
                      child: BureauPill(
                        _map ? 'Список' : 'Карта',
                        icon: _map
                            ? Icons.view_list_rounded
                            : Icons.map_outlined,
                      ),
                    ),
                    GestureDetector(
                      onTap: () async {
                        final value = await Navigator.push<SearchFilters>(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                SearchFiltersPage(initial: _filters),
                          ),
                        );
                        if (value != null && mounted) {
                          _filters = value;
                          _reload();
                        }
                      },
                      child: BureauPill(
                        'Фильтры · ${_filters.count}',
                        icon: Icons.tune_rounded,
                      ),
                    ),
                    GestureDetector(
                      onTap: () => pushPage(context, PhotoSearchPage(filters: _filters)),
                      child: const BureauPill(
                        'Фото',
                        icon: Icons.camera_alt_outlined,
                      ),
                    ),
                    if (_filters.count > 0) TextButton(onPressed: () {
                      _filters = const SearchFilters(); _reload();
                    }, child: const Text('Сбросить фильтры')),
                  ],
                ),
                const SizedBox(height: 16),
                FutureBuilder<JsonMap>(
                  future: _results,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState != ConnectionState.done) {
                      return const Center(
                        child: Padding(
                          padding: EdgeInsets.all(40),
                          child: Column(children: [CircularProgressIndicator(), SizedBox(height: 16), Text('Ищем объявления…')]),
                        ),
                      );
                    }
                    if (snapshot.hasError) {
                      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        NoticeCard(apiErrorText(snapshot.error!), color: BureauColors.red, background: BureauColors.redSoft),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(onPressed: _reload, icon: const Icon(Icons.refresh), label: const Text('Повторить поиск')),
                      ]);
                    }
                    final data = snapshot.requireData;
                    final items = List<JsonMap>.from(data['items'] as List);
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SectionTitle('${data['total']} результатов'),
                        const Padding(padding: EdgeInsets.only(bottom: 12), child: Text('Опубликованные объявления после модерации')),
                        if (_map)
                          _MapPreview(
                            items: items,
                            onList: () => setState(() => _map = false),
                          )
                        else
                          for (final item in items) ...[
                            _ListingCard(listing: item),
                            const SizedBox(height: 12),
                          ],
                        Row(mainAxisAlignment:MainAxisAlignment.spaceBetween,children:[
                          TextButton(onPressed:_offset==0?null:()=>setState((){_offset-=24;_results=_search();}),child:const Text('Назад')),
                          Text('Страница ${_offset~/24+1}'),
                          TextButton(onPressed:_offset+items.length >= (data['total'] as num)?null:()=>setState((){_offset+=24;_results=_search();}),child:const Text('Далее')),
                        ]),
                        if (items.isEmpty) ...[
                          const NoticeCard('Пока ничего не найдено. Попробуйте другие слова или уберите фильтры.'),
                          const SizedBox(height: 12),
                          OutlinedButton(onPressed: _reset, child: const Text('Показать все объявления')),
                          const SizedBox(height: 12),
                          FilledButton(onPressed: () => pushPage(context, CreateFlowPage(initialFound: _filters.kind == 'lost')),
                            child: Text(_filters.kind == 'lost' ? 'Сообщить о находке' : 'Сообщить о пропаже')),
                        ],
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MapPreview extends StatelessWidget {
  const _MapPreview({required this.items, required this.onList});
  final List<JsonMap> items;
  final VoidCallback onList;
  @override
  Widget build(BuildContext context) => ListingMap(listings: items, onOpen: (item) => pushPage(context, ItemDetailPage(listing: item)));
}

class CreateEntryView extends StatelessWidget {
  const CreateEntryView({super.key});

  @override
  Widget build(BuildContext context) => SafeArea(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Новая публикация', style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 8),
              Text('Что произошло с вещью?',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: BureauColors.slate)),
              const SizedBox(height: 28),
              LayoutBuilder(builder: (context, constraints) {
                final cards = [
                  _ChoiceCard(
                    icon: Icons.search_off_rounded,
                    title: 'Я потерял',
                    text: 'Расскажите, где и когда видели вещь в последний раз.',
                    color: BureauColors.blue,
                    soft: BureauColors.blueSoft,
                    onTap: () => pushPage(context, const CreateFlowPage(initialFound: false)),
                  ),
                  _ChoiceCard(
                    icon: Icons.volunteer_activism_rounded,
                    title: 'Я нашёл',
                    text: 'Скройте важные детали — по ним мы проверим владельца.',
                    color: BureauColors.green,
                    soft: BureauColors.greenSoft,
                    onTap: () => pushPage(context, const CreateFlowPage(initialFound: true)),
                  ),
                ];
                final stacked = constraints.maxWidth < 600 ||
                    MediaQuery.textScalerOf(context).scale(14) > 20;
                if (stacked) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [cards[0], const SizedBox(height: 16), cards[1]],
                  );
                }
                return IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: cards[0]),
                      const SizedBox(width: 16),
                      Expanded(child: cards[1]),
                    ],
                  ),
                );
              }),
              const SizedBox(height: 20),
              const NoticeCard('Публикация бесплатна. Контакты и точное место защищены.'),
            ],
          ),
        ),
      ),
    ),
  );
}

class _ChoiceCard extends StatelessWidget {
  const _ChoiceCard({
    required this.icon,
    required this.title,
    required this.text,
    required this.color,
    required this.soft,
    required this.onTap,
  });
  final IconData icon;
  final String title;
  final String text;
  final Color color;
  final Color soft;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => SoftCard(
    onTap: onTap,
    color: soft,
    borderColor: soft,
    padding: const EdgeInsets.all(18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        IconTile(icon: icon, color: color, background: Colors.white, size: 60),
        const SizedBox(height: 24),
        Text(
          title,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(color: color),
        ),
        const SizedBox(height: 10),
        Text(
          text,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 18),
        Icon(Icons.arrow_forward_rounded, color: color),
      ],
    ),
  );
}

class CasesView extends StatefulWidget {
  const CasesView({super.key});

  @override
  State<CasesView> createState() => _CasesViewState();
}

class _CasesViewState extends State<CasesView> {
  late Future<List<dynamic>> _future;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final api = AppScope.of(context, listen: false).api;
    _future = Future.wait([
      api.myListings(),
      api.myClaims(),
      api.supportTickets(),
      api.incomingClaims(),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: FutureBuilder<List<dynamic>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Padding(
              padding: const EdgeInsets.all(20),
              child: NoticeCard(
                apiErrorText(snapshot.error!),
                color: BureauColors.red,
                background: BureauColors.redSoft,
              ),
            );
          }
          final listings = snapshot.data![0] as List<JsonMap>;
          final claims = snapshot.data![1] as List<JsonMap>;
          final tickets = snapshot.data![2] as List<JsonMap>;
          final incoming = snapshot.data![3] as List<JsonMap>;
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Мои обращения',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  ),
                  BureauPill('${listings.length + claims.length} записей'),
                ],
              ),
              TextButton.icon(onPressed: () => setState(() { final api=AppScope.of(context,listen:false).api; _future=Future.wait([api.myListings(),api.myClaims(),api.supportTickets(),api.incomingClaims()]); }), icon: const Icon(Icons.refresh), label: const Text('Обновить')),
              const SectionTitle('Заявки на мои находки'),
              if(incoming.isEmpty) const NoticeCard('Входящих заявок пока нет.'),
              for(final claim in incoming) ...[
                SettingRow(icon:Icons.fact_check_outlined, title:claim['listing_title'].toString(), subtitle:stateLabel(claim['status']), onTap:()=>pushPage(context,ClaimReviewPage(claimId:claim['id'].toString()))),
                const SizedBox(height: 10),
              ],
              const SectionTitle('Мои публикации'),
              for (final listing in listings) ...[
                SettingRow(
                  icon: listing['kind'] == 'lost'
                      ? Icons.search_rounded
                      : Icons.volunteer_activism_rounded,
                  title: listing['title']?.toString() ?? 'Без названия',
                  subtitle:
                      '${listing['public_region']} · ${stateLabel(listing['status'])}',
                  color: listing['kind'] == 'found'
                      ? BureauColors.green
                      : BureauColors.blue,
                  background: listing['kind'] == 'found'
                      ? BureauColors.greenSoft
                      : BureauColors.blueSoft,
                  onTap: () => pushPage(context, EditListingPage(listingId: listing['id'].toString())),
                ),
                const SizedBox(height: 10),
              ],
              if (listings.isEmpty)
                const NoticeCard('У вас пока нет публикаций.'),
              const SectionTitle('Заявления владельца'),
              for (final claim in claims) ...[
                SettingRow(
                  icon: Icons.fact_check_outlined,
                  title: 'Заявление ${claim['id'].toString().substring(0, 8)}',
                  subtitle: 'Статус: ${stateLabel(claim['status'])}',
                  color: claim['status'] == 'approved'
                      ? BureauColors.green
                      : BureauColors.amber,
                  background: claim['status'] == 'approved'
                      ? BureauColors.greenSoft
                      : BureauColors.amberSoft,
                  onTap: () => pushPage(
                    context,
                    MatchFlowPage(
                      claimId: claim['id'].toString(),
                      listingId: claim['listing_id'].toString(),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
              ],
              const SectionTitle('Поддержка'),
              for (final ticket in tickets) ...[
                SettingRow(
                  icon: Icons.support_agent_rounded,
                  title: ticket['subject']?.toString() ?? 'Обращение',
                  subtitle: '${ticket['status']} · ${ticket['category']}',
                  onTap: () =>
                      pushPage(context, SupportChatPage(ticket: ticket)),
                ),
                const SizedBox(height: 10),
              ],
              OutlinedButton.icon(
                onPressed: () => pushPage(context, const SupportCreatePage()),
                icon: const Icon(Icons.add_rounded),
                label: const Text('Написать в поддержку'),
              ),
            ],
          );
        },
      ),
    );
  }
}

class ProfileView extends StatelessWidget {
  const ProfileView({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final user = controller.currentUser ?? const <String, dynamic>{};
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
        children: [
          Text('Профиль', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 20),
          SoftCard(
            child: Row(
              children: [
                CircleAvatar(
                  radius: 29,
                  backgroundColor: BureauColors.blueSoft,
                  child: Text(
                    _initials(user['display_name']?.toString()),
                    style: const TextStyle(
                      color: BureauColors.blue,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user['display_name']?.toString() ?? 'Пользователь',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      Text(
                        '${user['phone_masked'] ?? ''} · ${user['status'] ?? ''}',
                        style: Theme.of(
                          context,
                        ).textTheme.bodyMedium?.copyWith(fontSize: 12),
                      ),
                    ],
                  ),
                ),
                const BureauPill(
                  '✓',
                  color: BureauColors.green,
                  background: BureauColors.greenSoft,
                ),
              ],
            ),
          ),
          const SectionTitle('Моё'),
          SettingRow(
            icon: Icons.notifications_none_rounded,
            title: 'Уведомления',
            subtitle: 'Все события backend',
            onTap: () => pushPage(context, const NotificationsPage()),
          ),
          const SizedBox(height: 10),
          SettingRow(
            icon: Icons.bookmark_border_rounded,
            title: 'Сохранённое',
            subtitle: 'Ваши отложенные публикации',
            onTap: () => pushPage(context, const SavedPage()),
          ),
          const SizedBox(height: 10),
          SettingRow(
            icon: Icons.shield_outlined,
            title: 'Профиль и безопасность',
            subtitle: 'Имя, активные сессии и выход',
            color: BureauColors.green,
            background: BureauColors.greenSoft,
            onTap: () => pushPage(context, const ProfileSecurityPage()),
          ),
          if (controller.hasOrganization) ...[
            const SectionTitle('Организация'),
            SettingRow(
              icon: Icons.business_rounded,
              title: 'Кабинет организации',
              subtitle:
                  controller.selectedOrganization?['name']?.toString() ??
                  'Выбрать организацию',
              color: BureauColors.green,
              background: BureauColors.greenSoft,
              onTap: () => pushPage(context, const OrganizationAuthPage()),
            ),
          ],
          if (controller.isAdmin && !kIsWeb) ...[
            const SizedBox(height: 10),
            SettingRow(
              icon: Icons.admin_panel_settings_outlined,
              title: 'Кабинет модератора',
              subtitle: 'Риски, споры и антифрод',
              color: BureauColors.amber,
              background: BureauColors.amberSoft,
              onTap: () => pushPage(context, const AdminShell()),
            ),
          ],
          if (!kIsWeb) ...[
            const SectionTitle('Разработка'),
            SettingRow(
              icon: Icons.grid_view_rounded,
              title: 'Все 67 экранов',
              subtitle: 'Каталог и карта API',
              onTap: () => pushPage(context, const ScreenCatalogPage()),
            ),
          ],
        ],
      ),
    );
  }
}

class ItemDetailPage extends StatefulWidget {
  const ItemDetailPage({super.key, this.listing, this.listingId, this.found});

  final JsonMap? listing;
  final String? listingId;
  final bool? found;

  @override
  State<ItemDetailPage> createState() => _ItemDetailPageState();
}

class _ItemDetailPageState extends State<ItemDetailPage> {
  late Future<JsonMap> _future;
  bool _saved = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _future = widget.listing != null
        ? Future.value(widget.listing)
        : AppScope.of(context, listen: false).api.listing(widget.listingId!);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<JsonMap>(
      future: _future,
      builder: (context, snapshot) {
        final listing = snapshot.data;
        final found =
            listing?['kind'] == 'found' ||
            (listing == null && widget.found == true);
        final own = listing != null && listing['owner_id'] == AppScope.of(context).currentUser?['id'];
        final accent = found ? BureauColors.green : BureauColors.blue;
        final soft = found ? BureauColors.greenSoft : BureauColors.blueSoft;
        return BureauPage(
          title: found ? 'Найдена вещь' : 'Потеряна вещь',
          subtitle: listing == null
              ? 'Загрузка публикации'
              : '${listing['public_region']} · ${stateLabel(listing['status'])}',
          actions: [
            if (listing != null) IconButton(tooltip:'Поделиться ссылкой', icon:const Icon(Icons.link), onPressed:()=>launchUrl(Uri.parse('https://edinburo.ru/items/${listing['id']}/'))),
            IconButton(
              onPressed: listing == null
                  ? null
                  : () async {
                      final api = AppScope.of(context, listen: false).api;
                      try {
                        if (_saved) {
                          await api.unsaveListing(listing['id'].toString());
                        } else {
                          await api.saveListing(listing['id'].toString());
                        }
                        if (mounted) setState(() => _saved = !_saved);
                      } catch (error) {
                        if (!context.mounted) return;
                        showApiError(context, error);
                      }
                    },
              icon: Icon(
                _saved ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
              ),
            ),
          ],
          bottom: listing == null
              ? null
              : FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: accent),
                  onPressed: () => pushPage(context, own
                    ? EditListingPage(listingId: listing['id'].toString())
                    : found ? MatchFlowPage(listingId: listing['id'].toString(), targetListing: listing)
                    : const CreateFlowPage(initialFound: true)),
                  child: Text(own ? 'Управлять публикацией' : found ? 'Это может быть моё' : 'Сообщить о находке'),
                ),
          child: snapshot.connectionState != ConnectionState.done
              ? const Center(child: CircularProgressIndicator())
              : snapshot.hasError
              ? NoticeCard(
                  apiErrorText(snapshot.error!),
                  color: BureauColors.red,
                  background: BureauColors.redSoft,
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if ((listing!['media'] as List? ?? []).isEmpty)
                      _ListingArtwork(
                        listing: listing,
                        color: accent,
                        background: soft,
                        height: 300,
                      )
                    else
                      PhotoGallery(media: (listing['media'] as List).map((m)=>Map<String,dynamic>.from(m as Map)).toList()),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        BureauPill(
                          found ? 'НАХОДКА' : 'ПРОПАЖА',
                          color: accent,
                          background: soft,
                        ),
                        BureauPill(
                          listing['category']?.toString() ?? '',
                          background: Colors.white,
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      listing['title']?.toString() ?? '',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      listing['description']?.toString() ?? '',
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: BureauColors.slate,
                      ),
                    ),
                    const SectionTitle('Место и дата'),
                    SettingRow(
                      icon: Icons.location_on_outlined,
                      title:
                          listing['public_region']?.toString() ??
                          'Регион не указан',
                      subtitle:
                          'Точная точка скрыта · ${_shortDate(listing['event_at'])}',
                    ),
                    if ((listing['public_features'] as List? ?? const [])
                        .isNotEmpty) ...[
                      const SectionTitle('Признаки'),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: (listing['public_features'] as List)
                            .map(
                              (item) => BureauPill(
                                item.toString(),
                                color: accent,
                                background: soft,
                              ),
                            )
                            .toList(),
                      ),
                    ],
                  ],
                ),
        );
      },
    );
  }
}

class MatchExplanationPage extends StatelessWidget {
  const MatchExplanationPage({super.key, this.factors = const {}});
  final Map<String, dynamic> factors;

  @override
  Widget build(BuildContext context) {
    final rows = factors;
    return BureauPage(
      title: 'Почему совпадает',
      subtitle: 'ИИ объясняет оценку',
      child: Column(
        children: [
          for (final row in rows.entries) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    row.key,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Text(
                  '${matchPercent(row.value)}%',
                  style: const TextStyle(
                    color: BureauColors.green,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 7),
            LinearProgressIndicator(
              value: matchPercent(row.value) / 100,
              backgroundColor: BureauColors.line,
              color: BureauColors.green,
              borderRadius: BorderRadius.circular(99),
            ),
            const SizedBox(height: 15),
          ],
          const NoticeCard(
            'Процент — подсказка, а не доказательство владения. Решение принимается после проверки.',
          ),
        ],
      ),
    );
  }
}

class SearchFilters {
  const SearchFilters({this.kind, this.category, this.region, this.since});
  final String? kind;
  final String? category;
  final String? region;
  final DateTime? since;
  int get count =>
      [kind, category, region, since].where((item) => item != null).length;
}

class SearchFiltersPage extends StatefulWidget {
  const SearchFiltersPage({super.key, this.initial = const SearchFilters()});
  final SearchFilters initial;

  @override
  State<SearchFiltersPage> createState() => _SearchFiltersPageState();
}

class _SearchFiltersPageState extends State<SearchFiltersPage> {
  String? _kind;
  String? _category;
  late final TextEditingController _region;
  int? _days;

  @override
  void initState() {
    super.initState();
    _kind = widget.initial.kind;
    _category = widget.initial.category;
    _region = TextEditingController(text: widget.initial.region);
    _days = widget.initial.since == null
        ? null
        : DateTime.now().difference(widget.initial.since!).inDays;
    if (_days != null) _days = [7, 30, 90, 365].firstWhere((days) => days >= _days!, orElse: () => 365);
  }

  @override
  void dispose() {
    _region.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => BureauPage(
    title: 'Фильтры',
    subtitle: 'Только релевантные публикации',
    bottom: FilledButton(
      onPressed: () => Navigator.pop(
        context,
        SearchFilters(
          kind: _kind,
          category: _category,
          region: _region.text.trim().isEmpty ? null : _region.text.trim(),
          since: _days == null
              ? null
              : DateTime.now().subtract(Duration(days: _days!)),
        ),
      ),
      child: const Text('Применить'),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionTitle('Тип публикации'),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'lost', label: Text('Пропажи')),
            ButtonSegment(value: 'found', label: Text('Находки')),
          ],
          selected: _kind == null ? <String>{} : {_kind!},
          emptySelectionAllowed: true,
          onSelectionChanged: (value) =>
              setState(() => _kind = value.firstOrNull),
        ),
        const SectionTitle('Категория'),
        DropdownButtonFormField<String>(
          key: ValueKey('category-$_category'),
          initialValue: _category,
          isExpanded: true,
          items: [const DropdownMenuItem<String>(value: '', child: Text('Все категории')), ...categoryLabels.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))],
          onChanged: (value) => setState(() => _category = value == '' ? null : value),
          decoration: const InputDecoration(hintText: 'Любая категория'),
        ),
        const SectionTitle('Регион'),
        MapsTextField(controller: _region, label: 'Город или населённый пункт', cityOnly: true),
        const SectionTitle('Период'),
        DropdownButtonFormField<int>(
          key: ValueKey('period-$_days'),
          initialValue: _days ?? 0,
          isExpanded: true,
          items: const [0, 7, 30, 90, 365]
              .map(
                (days) =>
                    DropdownMenuItem(value: days, child: Text(days == 0 ? 'За всё время' : '$days дней')),
              )
              .toList(),
          onChanged: (value) => setState(() => _days = value == 0 ? null : value),
          decoration: const InputDecoration(hintText: 'За всё время'),
        ),
        const SizedBox(height: 16),
        TextButton(onPressed: () => setState(() {
          _kind = null; _category = null; _days = null; _region.clear();
        }), child: const Text('Сбросить все фильтры')),
      ],
    ),
  );
}

class PhotoSearchPage extends StatefulWidget {
  const PhotoSearchPage({super.key, this.filters = const SearchFilters()});
  final SearchFilters filters;

  @override
  State<PhotoSearchPage> createState() => _PhotoSearchPageState();
}

class _PhotoSearchPageState extends State<PhotoSearchPage> {
  XFile? _image;
  List<JsonMap>? _results;
  bool _loading = false;
  String? _mediaId;
  Object? _error;

  Future<void> _pickAndSearch() async {
    if (_loading) return;
    final image = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 88,
      maxWidth: 2048,
    );
    if (image == null || !mounted) return;
    setState(() {
      _image = image;
      _mediaId = null;
      _results = null;
      _error = null;
    });
    await _searchPhoto();
  }

  Future<void> _searchPhoto() async {
    if (_loading || _image == null) return;
    final api = AppScope.of(context, listen: false).api;
    final image = _image!;
    setState(() { _loading = true; _error = null; _results = null; });
    try {
      if (_mediaId == null) {
      final bytes = await image.readAsBytes();
      final mime =
          image.mimeType ??
          (image.name.toLowerCase().endsWith('.png')
              ? 'image/png'
              : 'image/jpeg');
      final media = await api.uploadMedia(
        bytes: bytes,
        filename: image.name,
        mimeType: mime,
        purpose: 'listing',
      );
        _mediaId = media.id;
      }
      final results = await api.photoSearch(_mediaId!, targetKind: widget.filters.kind,
        category: widget.filters.category, region: widget.filters.region, since: widget.filters.since);
      if (mounted) setState(() => _results = results);
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => BureauPage(
    title: 'Поиск по фото',
    subtitle: 'Форма, цвет и уникальные детали',
    bottom: ApiButton(
      label: _image == null ? 'Выбрать фотографию' : 'Выбрать другое фото',
      onPressed: _pickAndSearch,
    ),
    child: Column(
      children: [
        if (widget.filters.count > 0) Padding(padding: const EdgeInsets.only(bottom: 16),
          child: Text('Применены фильтры поиска: ${widget.filters.count}')),
        Container(
          height: 280,
          width: double.infinity,
          decoration: BoxDecoration(
            color: BureauColors.blueSoft,
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: BureauColors.blue),
          ),
          child: _image == null
              ? const Icon(
                  Icons.add_a_photo_outlined,
                  size: 70,
                  color: BureauColors.blue,
                )
              : FutureBuilder(
                  future: _image!.readAsBytes(),
                  builder: (context, snapshot) => snapshot.hasData
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(25),
                          child: Image.memory(
                            snapshot.data!,
                            fit: BoxFit.cover,
                          ),
                        )
                      : const Center(child: CircularProgressIndicator()),
                ),
        ),
        if (_loading)
          const Padding(
            padding: EdgeInsets.all(24),
            child: CircularProgressIndicator(),
          ),
        if (_error != null) ...[
          const SizedBox(height: 16),
          NoticeCard(apiErrorText(_error!), color: BureauColors.red, background: BureauColors.redSoft),
          OutlinedButton(onPressed: _loading ? null : _searchPhoto, child: const Text('Повторить поиск по фото')),
        ],
        if (_results != null) ...[
          SectionTitle('${_results!.length} визуальных совпадений'),
          for (final result in _results!) ...[
            _ListingCard(
              listing: Map<String, dynamic>.from(result['listing'] as Map),
              score: ((result['visual_score'] as num?)?.toDouble() ?? 0),
            ),
            const SizedBox(height: 12),
          ],
          if (_results!.isEmpty)
            const NoticeCard('Визуальных совпадений пока нет.'),
        ],
      ],
    ),
  );
}

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  late Future<List<JsonMap>> _future;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _future = AppScope.of(context, listen: false).api.notifications();
  }

  void _reload() => setState(
    () => _future = AppScope.of(context, listen: false).api.notifications(),
  );

  @override
  Widget build(BuildContext context) => BureauPage(
    title: 'Уведомления',
    subtitle: 'События из backend',
    actions: [
      IconButton(
        onPressed: () async {
          await AppScope.of(context, listen: false).api.readAllNotifications();
          _reload();
        },
        icon: const Icon(Icons.done_all_rounded),
      ),
    ],
    child: ApiFutureBuilder<List<JsonMap>>(
      future: _future,
      empty: const NoticeCard('Новых уведомлений нет.'),
      builder: (context, items) => Column(
        children: [
          for (final item in items) ...[
            SettingRow(
              icon: _notificationIcon(item['kind']?.toString()),
              title: item['title']?.toString() ?? 'Событие',
              subtitle:
                  '${item['body'] ?? ''} · ${_shortDate(item['created_at'])}',
              color: item['read_at'] == null
                  ? BureauColors.green
                  : BureauColors.slate,
              background: item['read_at'] == null
                  ? BureauColors.greenSoft
                  : Colors.white,
              onTap: () async {
                await AppScope.of(
                  context,
                  listen: false,
                ).api.readNotification(item['id'].toString());
                _reload();
              },
            ),
            const SizedBox(height: 10),
          ],
        ],
      ),
    ),
  );
}

class SavedPage extends StatefulWidget {
  const SavedPage({super.key});

  @override
  State<SavedPage> createState() => _SavedPageState();
}

class _SavedPageState extends State<SavedPage> {
  late Future<List<JsonMap>> _future;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _future = AppScope.of(context, listen: false).api.savedListings();
  }

  @override
  Widget build(BuildContext context) => BureauPage(
    title: 'Сохранённое',
    subtitle: 'Отложенные публикации',
    child: ApiFutureBuilder<List<JsonMap>>(
      future: _future,
      empty: const NoticeCard('Сохранённых публикаций пока нет.'),
      builder: (context, items) => Column(
        children: [
          for (final item in items) ...[
            Dismissible(
              key: ValueKey(item['id']),
              background: Container(
                color: BureauColors.redSoft,
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.all(20),
                child: const Icon(
                  Icons.delete_outline_rounded,
                  color: BureauColors.red,
                ),
              ),
              onDismissed: (_) => AppScope.of(
                context,
                listen: false,
              ).api.unsaveListing(item['id'].toString()),
              child: _ListingCard(listing: item),
            ),
            const SizedBox(height: 12),
          ],
        ],
      ),
    ),
  );
}

class ProfileSecurityPage extends StatefulWidget {
  const ProfileSecurityPage({super.key});

  @override
  State<ProfileSecurityPage> createState() => _ProfileSecurityPageState();
}

class _ProfileSecurityPageState extends State<ProfileSecurityPage> {
  final TextEditingController _name = TextEditingController();
  bool _initialized = false;
  late Future<List<JsonMap>> _sessions;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final app = AppScope.of(context, listen: false);
    if (_initialized) return;
    _initialized = true;
    _name.text = app.currentUser?['display_name']?.toString() ?? '';
    _sessions = app.api.sessions();
  }

  @override
  void dispose() { _name.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => BureauPage(
    title: 'Профиль и безопасность',
    subtitle: 'Данные аккаунта и активные устройства',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _name,
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.person_outline_rounded),
            labelText: 'Имя',
          ),
        ),
        const SizedBox(height: 12),
        ApiButton(
          label: 'Сохранить имя',
          onPressed: () async {
            final controller = AppScope.of(context, listen: false);
            await controller.updateProfile(_name.text);
            if (!context.mounted) return;
            showApiSuccess(context, 'Профиль обновлён');
          },
        ),
        const SectionTitle('Активные сессии'),
        ApiFutureBuilder<List<JsonMap>>(
          future: _sessions,
          empty: const NoticeCard('Активных сессий нет.'),
          builder: (context, items) => Column(
            children: [
              for (final item in items) ...[
                SettingRow(
                  icon: Icons.devices_rounded,
                  title: item['device_name']?.toString() ?? 'Устройство',
                  subtitle: 'Создано ${_shortDate(item['created_at'])}',
                  trailing: IconButton(
                    onPressed: () async {
                      await AppScope.of(
                        context,
                        listen: false,
                      ).api.revokeSession(item['id'].toString());
                      if (mounted) {
                        setState(
                          () => _sessions = AppScope.of(
                            context,
                            listen: false,
                          ).api.sessions(),
                        );
                      }
                    },
                    icon: const Icon(Icons.logout_rounded),
                  ),
                ),
                const SizedBox(height: 10),
              ],
            ],
          ),
        ),
        const SectionTitle('Сеанс'),
        ApiButton(
          label: 'Выйти из аккаунта',
          outlined: true,
          onPressed: () async {
            final controller = AppScope.of(context, listen: false);
            await controller.logout();
            if (!context.mounted) return;
            Navigator.of(context).popUntil((route) => route.isFirst);
          },
        ),
      ],
    ),
  );
}

class SupportCreatePage extends StatefulWidget {
  const SupportCreatePage({super.key});
  @override
  State<SupportCreatePage> createState() => _SupportCreatePageState();
}

class _SupportCreatePageState extends State<SupportCreatePage> {
  final _subject = TextEditingController();
  final _message = TextEditingController();
  String _category = 'technical';
  @override
  Widget build(BuildContext context) => BureauPage(
    title: 'Новое обращение',
    subtitle: 'Служба поддержки',
    bottom: ApiButton(
      label: 'Отправить',
      onPressed: () async {
        final api = AppScope.of(context, listen: false).api;
        await api.createSupportTicket({
          'subject': _subject.text,
          'category': _category,
          'message': _message.text,
          'organization_id': null,
          'attachment_ids': <String>[],
        });
        if (!context.mounted) return;
        Navigator.pop(context);
      },
    ),
    child: Column(
      children: [
        TextField(
          controller: _subject,
          decoration: const InputDecoration(labelText: 'Тема'),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: _category,
          items:
              const [
                    'search',
                    'claim',
                    'handover',
                    'organization',
                    'technical',
                    'other',
                  ]
                  .map(
                    (item) => DropdownMenuItem(value: item, child: Text(item)),
                  )
                  .toList(),
          onChanged: (value) => _category = value ?? 'other',
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _message,
          maxLines: 7,
          decoration: const InputDecoration(labelText: 'Сообщение'),
        ),
      ],
    ),
  );
}

class SupportChatPage extends StatefulWidget {
  const SupportChatPage({super.key, required this.ticket});
  final JsonMap ticket;
  @override
  State<SupportChatPage> createState() => _SupportChatPageState();
}

class _SupportChatPageState extends State<SupportChatPage> {
  final _message = TextEditingController();
  late Future<List<JsonMap>> _future;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _future = AppScope.of(
      context,
      listen: false,
    ).api.supportMessages(widget.ticket['id'].toString());
  }

  void _reload() => setState(
    () => _future = AppScope.of(
      context,
      listen: false,
    ).api.supportMessages(widget.ticket['id'].toString()),
  );
  @override
  Widget build(BuildContext context) => BureauPage(
    title: widget.ticket['subject']?.toString() ?? 'Поддержка',
    subtitle: widget.ticket['status']?.toString() ?? '',
    bottom: Row(
      children: [
        Expanded(
          child: TextField(
            controller: _message,
            decoration: const InputDecoration(hintText: 'Сообщение…'),
          ),
        ),
        const SizedBox(width: 8),
        IconButton.filled(
          onPressed: () async {
            if (_message.text.trim().isEmpty) return;
            try {
            await AppScope.of(context, listen: false).api.sendSupportMessage(
              widget.ticket['id'].toString(),
              _message.text,
            );
            _message.clear();
            if (mounted) _reload();
            } catch(e) { if(context.mounted)showApiError(context,e); }
          },
          icon: const Icon(Icons.send_rounded),
        ),
      ],
    ),
    child: ApiFutureBuilder<List<JsonMap>>(
      future: _future,
      empty: const NoticeCard('Сообщений пока нет.'),
      builder: (context, items) => Column(
        children: [
          for (final item in items)
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: SoftCard(child: Text(item['body']?.toString() ?? '')),
              ),
            ),
        ],
      ),
    ),
  );
}

class _ListingCard extends StatelessWidget {
  const _ListingCard({required this.listing, this.score});
  final JsonMap listing;
  final double? score;
  @override
  Widget build(BuildContext context) => SoftCard(
    onTap: () => pushPage(context, ItemDetailPage(listing: listing)),
    child: Row(
      children: [
        SizedBox(
          width: 86,
          height: 86,
          child: _ListingArtwork(
            listing: listing,
            height: 86,
            color: listing['kind'] == 'found'
                ? BureauColors.green
                : BureauColors.blue,
            background: listing['kind'] == 'found'
                ? BureauColors.greenSoft
                : BureauColors.blueSoft,
          ),
        ),
        const SizedBox(width: 13),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                listing['title']?.toString() ?? 'Без названия',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 6),
              Text(
                '${listing['public_region'] ?? ''} · ${_shortDate(listing['event_at'])}',
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(fontSize: 12),
              ),
              if (score != null) ...[
                const SizedBox(height: 8),
                BureauPill(
                  '${(score! * 100).round()}% сходства',
                  color: BureauColors.green,
                  background: BureauColors.greenSoft,
                ),
              ],
            ],
          ),
        ),
        const Icon(Icons.chevron_right_rounded),
      ],
    ),
  );
}

class _ListingArtwork extends StatelessWidget {
  const _ListingArtwork({
    required this.listing,
    required this.color,
    required this.background,
    this.height = 220,
  });
  final JsonMap listing;
  final Color color;
  final Color background;
  final double height;
  @override
  Widget build(BuildContext context) {
    final media = listing['media'] as List? ?? const [];
    final url = media.isEmpty
        ? null
        : (media.first as Map)['download_url']?.toString();
    return Container(
      height: height,
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(20),
      ),
      child: url == null || url.isEmpty
          ? Icon(
              _categoryIcon(listing['category']?.toString()),
              color: color,
              size: height * .42,
            )
          : Image.network(
              url,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Icon(
                _categoryIcon(listing['category']?.toString()),
                color: color,
                size: height * .42,
              ),
            ),
    );
  }
}

class _LiveAdCard extends StatefulWidget {
  const _LiveAdCard({required this.ad, required this.placement});
  final JsonMap ad;
  final String placement;
  @override
  State<_LiveAdCard> createState() => _LiveAdCardState();
}

class _LiveAdCardState extends State<_LiveAdCard> {
  bool _tracked = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_tracked) {
      _tracked = true;
      AppScope.of(context, listen: false).api
          .trackAd(widget.ad['id'].toString(), 'impression', widget.placement)
          .catchError((_) {});
    }
  }

  @override
  Widget build(BuildContext context) => SoftCard(
    color: BureauColors.amberSoft,
    borderColor: BureauColors.amberSoft,
    onTap: () => AppScope.of(context, listen: false).api
        .trackAd(widget.ad['id'].toString(), 'click', widget.placement)
        .catchError((_) {}),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const BureauPill(
              'РЕКЛАМА',
              color: BureauColors.amber,
              background: Colors.white,
            ),
            const Spacer(),
            Text(widget.ad['age_rating']?.toString() ?? '0+'),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          widget.ad['title']?.toString() ?? '',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 6),
        Text(widget.ad['body']?.toString() ?? ''),
        const SizedBox(height: 8),
        Text(
          'ERID: ${widget.ad['erid'] ?? ''}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    ),
  );
}

String _initials(String? name) {
  final parts = (name ?? '')
      .trim()
      .split(RegExp(r'\s+'))
      .where((item) => item.isNotEmpty)
      .take(2);
  final value = parts.map((item) => item[0].toUpperCase()).join();
  return value.isEmpty ? 'БН' : value;
}

String _shortDate(dynamic value) {
  final date = DateTime.tryParse(value?.toString() ?? '');
  if (date == null) return '';
  return '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}';
}

IconData _categoryIcon(String? category) {
  final value = category?.toLowerCase() ?? '';
  if (value.contains('ключ')) return Icons.key_rounded;
  if (value.contains('документ')) return Icons.badge_outlined;
  if (value.contains('элект')) return Icons.devices_rounded;
  if (value.contains('одеж')) return Icons.checkroom_rounded;
  return Icons.inventory_2_outlined;
}

IconData _notificationIcon(String? kind) {
  if (kind?.contains('match') == true) return Icons.auto_awesome_rounded;
  if (kind?.contains('claim') == true) return Icons.fact_check_outlined;
  if (kind?.contains('handover') == true) return Icons.qr_code_rounded;
  return Icons.notifications_none_rounded;
}
