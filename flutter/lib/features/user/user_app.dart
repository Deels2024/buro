import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../core/widgets.dart';
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
      icon: Icons.hub_rounded,
      title: 'Одна сеть для всей России',
      text: 'Ищите среди публикаций людей, транспорта, торговых центров, вузов и городских служб.',
      color: BureauColors.blue,
      soft: BureauColors.blueSoft,
    ),
    (
      icon: Icons.verified_user_rounded,
      title: 'Контакты под защитой',
      text: 'Сначала доказательство владения. Точное место и контакты откроются только после подтверждения.',
      color: BureauColors.green,
      soft: BureauColors.greenSoft,
    ),
    (
      icon: Icons.auto_awesome_rounded,
      title: 'ИИ видит похожее',
      text: 'Загрузите фото — система опишет вещь, создаст теги и предложит вероятные совпадения.',
      color: BureauColors.blue,
      soft: BureauColors.blueSoft,
    ),
  ];

  void _next() {
    if (_index == _slides.length - 1) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(builder: (_) => const AuthPage()),
      );
      return;
    }
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
                      child: Text('БН', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
                    ),
                  ),
                  const SizedBox(width: 11),
                  Text('Бюро находок', style: Theme.of(context).textTheme.titleMedium),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.of(context).pushReplacement(
                      MaterialPageRoute<void>(builder: (_) => const AuthPage()),
                    ),
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
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Container(
                            width: double.infinity,
                            decoration: BoxDecoration(
                              color: slide.soft,
                              borderRadius: BorderRadius.circular(32),
                            ),
                            child: Center(
                              child: Container(
                                width: 150,
                                height: 150,
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(42),
                                  boxShadow: [
                                    BoxShadow(
                                      color: slide.color.withValues(alpha: .14),
                                      blurRadius: 42,
                                      offset: const Offset(0, 20),
                                    ),
                                  ],
                                ),
                                child: Icon(slide.icon, color: slide.color, size: 70),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 30),
                        BureauPill('${index + 1} / ${_slides.length}', color: slide.color, background: slide.soft),
                        const SizedBox(height: 16),
                        Text(slide.title, style: Theme.of(context).textTheme.headlineSmall),
                        const SizedBox(height: 12),
                        Text(slide.text, style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: BureauColors.slate)),
                      ],
                    ),
                  );
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

class AuthPage extends StatelessWidget {
  const AuthPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BureauPage(
      title: 'Войти в аккаунт',
      subtitle: 'Совпадения и обращения всегда под рукой',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 28),
          const TextField(
            keyboardType: TextInputType.phone,
            decoration: InputDecoration(
              prefixIcon: Icon(Icons.phone_rounded),
              hintText: '+7 (___) ___-__-__',
            ),
          ),
          const SizedBox(height: 14),
          FilledButton(
            onPressed: () => pushPage(context, const VerifyPhonePage()),
            child: const Text('Получить код'),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.account_balance_outlined),
            label: const Text('Войти через Госуслуги'),
          ),
          const SizedBox(height: 26),
          const NoticeCard('Номер телефона не показывается другим пользователям и используется только для входа.'),
          const SizedBox(height: 22),
          Text(
            'Продолжая, вы принимаете правила сервиса и политику конфиденциальности.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 10),
          ),
        ],
      ),
    );
  }
}

class VerifyPhonePage extends StatelessWidget {
  const VerifyPhonePage({super.key});

  @override
  Widget build(BuildContext context) {
    return BureauPage(
      title: 'Введите код',
      subtitle: 'Отправили SMS на +7 999 •••-42-10',
      child: Column(
        children: [
          const SizedBox(height: 35),
          Row(
            children: List.generate(
              4,
              (index) => Expanded(
                child: Padding(
                  padding: EdgeInsets.only(right: index == 3 ? 0 : 10),
                  child: TextField(
                    textAlign: TextAlign.center,
                    maxLength: 1,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(counterText: '', hintText: index < 3 ? '${[2, 8, 4][index]}' : ''),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: () => Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute<void>(builder: (_) => const UserShell()),
              (_) => false,
            ),
            child: const Text('Подтвердить'),
          ),
          const SizedBox(height: 18),
          Text('Новый код через 00:42', style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }
}

class UserShell extends StatefulWidget {
  const UserShell({super.key, this.initialIndex = 0});

  final int initialIndex;

  @override
  State<UserShell> createState() => _UserShellState();
}

class _UserShellState extends State<UserShell> {
  late int _index = widget.initialIndex;

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      HomeView(onSearch: () => setState(() => _index = 1)),
      const SearchView(),
      const CreateEntryView(),
      const CasesView(),
      const ProfileView(),
    ];
    return Scaffold(
      body: IndexedStack(index: _index, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) => setState(() => _index = value),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home_rounded), label: 'Главная'),
          NavigationDestination(icon: Icon(Icons.search_rounded), label: 'Поиск'),
          NavigationDestination(icon: Icon(Icons.add_circle_outline_rounded), selectedIcon: Icon(Icons.add_circle_rounded), label: 'Добавить'),
          NavigationDestination(icon: Icon(Icons.forum_outlined), selectedIcon: Icon(Icons.forum_rounded), label: 'Обращения'),
          NavigationDestination(icon: Icon(Icons.person_outline_rounded), selectedIcon: Icon(Icons.person_rounded), label: 'Профиль'),
        ],
      ),
    );
  }
}

class HomeView extends StatelessWidget {
  const HomeView({super.key, required this.onSearch});

  final VoidCallback onSearch;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              margin: const EdgeInsets.all(12),
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [BureauColors.blueDark, Color(0xFF277BFF)],
                ),
                borderRadius: BorderRadius.circular(30),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const CircleAvatar(
                        backgroundColor: Colors.white,
                        child: Text('А', style: TextStyle(color: BureauColors.blue, fontWeight: FontWeight.w900)),
                      ),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text('Доброе утро, Анна', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                      ),
                      IconButton(
                        onPressed: () => pushPage(context, const NotificationsPage()),
                        icon: const Icon(Icons.notifications_none_rounded, color: Colors.white),
                      ),
                    ],
                  ),
                  const SizedBox(height: 28),
                  Text(
                    'Что вы хотите\nвернуть?',
                    style: Theme.of(context).textTheme.displaySmall?.copyWith(color: Colors.white),
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    readOnly: true,
                    onTap: onSearch,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search_rounded),
                      hintText: 'Фото, описание или место',
                      border: InputBorder.none,
                      enabledBorder: OutlineInputBorder(borderSide: BorderSide.none, borderRadius: BorderRadius.all(Radius.circular(18))),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _QuickAction(
                          icon: Icons.search_off_rounded,
                          title: 'Я потерял',
                          subtitle: 'Создать пропажу',
                          color: BureauColors.blue,
                          soft: BureauColors.blueSoft,
                          onTap: () => pushPage(context, const CreateFlowPage(initialFound: false)),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _QuickAction(
                          icon: Icons.volunteer_activism_rounded,
                          title: 'Я нашёл',
                          subtitle: 'Помочь вернуть',
                          color: BureauColors.green,
                          soft: BureauColors.greenSoft,
                          onTap: () => pushPage(context, const CreateFlowPage(initialFound: true)),
                        ),
                      ),
                    ],
                  ),
                  const SectionTitle('Рядом с вами'),
                  LostItemCard(
                    title: 'Чёрный городской рюкзак',
                    meta: 'Москва · 1,2 км · сегодня',
                    score: 93,
                    onTap: () => pushPage(context, const ItemDetailPage(found: true)),
                  ),
                  const SizedBox(height: 12),
                  const NativeAdCard(),
                  const SizedBox(height: 12),
                  LostItemCard(
                    title: 'Связка ключей с брелоком',
                    meta: 'Арбат · 3,8 км · вчера',
                    score: 81,
                    icon: Icons.key_rounded,
                    onTap: () => pushPage(context, const ItemDetailPage(found: true)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.soft,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final Color soft;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      onTap: onTap,
      color: soft,
      borderColor: soft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(height: 22),
          Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(color: color, fontSize: 17)),
          const SizedBox(height: 4),
          Text(subtitle, style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 10)),
        ],
      ),
    );
  }
}

class SearchView extends StatefulWidget {
  const SearchView({super.key});

  @override
  State<SearchView> createState() => _SearchViewState();
}

class _SearchViewState extends State<SearchView> {
  bool _map = false;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
            child: Row(
              children: [
                Expanded(child: Text('Поиск', style: Theme.of(context).textTheme.headlineSmall)),
                IconButton(
                  onPressed: () => pushPage(context, const SavedPage()),
                  icon: const Icon(Icons.bookmark_border_rounded),
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const TextField(
                    decoration: InputDecoration(prefixIcon: Icon(Icons.search_rounded), hintText: 'Чёрный рюкзак'),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      BureauPill(_map ? 'Список' : 'Карта', icon: _map ? Icons.view_list_rounded : Icons.map_outlined),
                      GestureDetector(
                        onTap: () => pushPage(context, const SearchFiltersPage()),
                        child: const BureauPill('Фильтры · 2', icon: Icons.tune_rounded),
                      ),
                      GestureDetector(
                        onTap: () => pushPage(context, const PhotoSearchPage()),
                        child: const BureauPill('Фото', icon: Icons.camera_alt_outlined),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SoftCard(
                    color: BureauColors.blueSoft,
                    borderColor: BureauColors.blueSoft,
                    onTap: () => pushPage(context, const PhotoSearchPage()),
                    child: Row(
                      children: [
                        const IconTile(icon: Icons.auto_awesome_rounded),
                        const SizedBox(width: 13),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('ИИ-поиск по фотографии', style: Theme.of(context).textTheme.titleMedium),
                              Text('Сравним форму, цвет и уникальные детали', style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 10)),
                            ],
                          ),
                        ),
                        const Icon(Icons.chevron_right_rounded, color: BureauColors.blue),
                      ],
                    ),
                  ),
                  SectionTitle(_map ? 'На карте' : '8 результатов'),
                  if (_map)
                    _MapPreview(onList: () => setState(() => _map = false))
                  else ...[
                    LostItemCard(
                      title: 'Рюкзак с красной молнией',
                      meta: 'Тверская · сегодня',
                      score: 93,
                      onTap: () => pushPage(context, const ItemDetailPage(found: true)),
                    ),
                    const SizedBox(height: 12),
                    LostItemCard(
                      title: 'Городской рюкзак',
                      meta: 'Арбат · вчера',
                      score: 81,
                      onTap: () => pushPage(context, const ItemDetailPage(found: true)),
                    ),
                    const SizedBox(height: 12),
                    const NativeAdCard(),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () => setState(() => _map = true),
                      icon: const Icon(Icons.map_outlined),
                      label: const Text('Показать на карте'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MapPreview extends StatelessWidget {
  const _MapPreview({required this.onList});

  final VoidCallback onList;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          height: 390,
          decoration: BoxDecoration(
            color: const Color(0xFFE9EEF4),
            borderRadius: BorderRadius.circular(26),
          ),
          child: Stack(
            children: [
              ...const [
                Positioned(left: 54, top: 70, child: _MapPin('93', BureauColors.green)),
                Positioned(right: 60, top: 130, child: _MapPin('81', BureauColors.blue)),
                Positioned(left: 150, bottom: 70, child: _MapPin('68', BureauColors.blue)),
              ],
              Positioned(
                left: 18,
                right: 18,
                bottom: 18,
                child: FilledButton.tonal(onPressed: onList, child: const Text('Показать списком')),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        const NoticeCard('Точные адреса скрыты до подтверждения владельца.'),
      ],
    );
  }
}

class _MapPin extends StatelessWidget {
  const _MapPin(this.label, this.color);

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 54,
      height: 54,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 4),
        boxShadow: [BoxShadow(color: color.withValues(alpha: .24), blurRadius: 18, offset: const Offset(0, 8))],
      ),
      child: Center(child: Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900))),
    );
  }
}

class CreateEntryView extends StatelessWidget {
  const CreateEntryView({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Новая публикация', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text('Что произошло с вещью?', style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: BureauColors.slate)),
            const SizedBox(height: 28),
            Expanded(
              child: Row(
                children: [
                  Expanded(
                    child: _ChoiceCard(
                      icon: Icons.search_off_rounded,
                      title: 'Я потерял',
                      text: 'Расскажите, где и когда видели вещь в последний раз.',
                      color: BureauColors.blue,
                      soft: BureauColors.blueSoft,
                      onTap: () => pushPage(context, const CreateFlowPage(initialFound: false)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _ChoiceCard(
                      icon: Icons.volunteer_activism_rounded,
                      title: 'Я нашёл',
                      text: 'Скройте важные детали — по ним мы проверим владельца.',
                      color: BureauColors.green,
                      soft: BureauColors.greenSoft,
                      onTap: () => pushPage(context, const CreateFlowPage(initialFound: true)),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            const NoticeCard('Публикация бесплатна. Контакты и точное место защищены.'),
          ],
        ),
      ),
    );
  }
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
  Widget build(BuildContext context) {
    return SoftCard(
      onTap: onTap,
      color: soft,
      borderColor: soft,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconTile(icon: icon, color: color, background: Colors.white, size: 60),
          const Spacer(),
          Text(title, style: Theme.of(context).textTheme.titleLarge?.copyWith(color: color)),
          const SizedBox(height: 10),
          Text(text, style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 11)),
          const SizedBox(height: 18),
          Icon(Icons.arrow_forward_rounded, color: color),
        ],
      ),
    );
  }
}

class CasesView extends StatelessWidget {
  const CasesView({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text('Мои обращения', style: Theme.of(context).textTheme.headlineSmall)),
                const BureauPill('2 активных'),
              ],
            ),
            const SectionTitle('Лучшее совпадение'),
            SoftCard(
              color: BureauColors.greenSoft,
              borderColor: BureauColors.greenSoft,
              onTap: () => pushPage(context, const MatchFlowPage()),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      BureauPill('НОВОЕ', color: BureauColors.green, background: Colors.white),
                      Text('93%', style: TextStyle(color: BureauColors.green, fontSize: 26, fontWeight: FontWeight.w900)),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Text('Похожий рюкзак найден на Тверской', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 7),
                  Text('Совпали форма, цвет, молния и временной интервал.', style: Theme.of(context).textTheme.bodyMedium),
                  const SizedBox(height: 18),
                  const Row(
                    children: [
                      Icon(Icons.arrow_forward_rounded, color: BureauColors.green),
                      SizedBox(width: 8),
                      Text('Проверить совпадение', style: TextStyle(color: BureauColors.green, fontWeight: FontWeight.w800)),
                    ],
                  ),
                ],
              ),
            ),
            const SectionTitle('Активные'),
            const SettingRow(
              icon: Icons.search_rounded,
              title: 'Чёрный городской рюкзак',
              subtitle: 'Ищем · 8 возможных совпадений',
              trailing: BureauPill('В ПОИСКЕ'),
            ),
            const SizedBox(height: 12),
            const SettingRow(
              icon: Icons.key_rounded,
              title: 'Связка ключей',
              subtitle: 'Заявление проверяет организация',
              color: BureauColors.amber,
              background: BureauColors.amberSoft,
              trailing: BureauPill('ПРОВЕРКА', color: BureauColors.amber, background: BureauColors.amberSoft),
            ),
          ],
        ),
      ),
    );
  }
}

class ProfileView extends StatelessWidget {
  const ProfileView({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Профиль', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 20),
            SoftCard(
              child: Row(
                children: [
                  const CircleAvatar(
                    radius: 29,
                    backgroundColor: BureauColors.blueSoft,
                    child: Text('АС', style: TextStyle(color: BureauColors.blue, fontWeight: FontWeight.w900)),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Анна Смирнова', style: Theme.of(context).textTheme.titleLarge),
                        Text('+7 999 •••-42-10 · подтверждён', style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 10)),
                      ],
                    ),
                  ),
                  const BureauPill('✓', color: BureauColors.green, background: BureauColors.greenSoft),
                ],
              ),
            ),
            const SectionTitle('Моё'),
            SettingRow(
              icon: Icons.notifications_none_rounded,
              title: 'Уведомления',
              subtitle: '3 новых события',
              onTap: () => pushPage(context, const NotificationsPage()),
            ),
            const SizedBox(height: 10),
            SettingRow(
              icon: Icons.bookmark_border_rounded,
              title: 'Сохранённое',
              subtitle: '6 публикаций',
              onTap: () => pushPage(context, const SavedPage()),
            ),
            const SizedBox(height: 10),
            const SettingRow(
              icon: Icons.shield_outlined,
              title: 'Безопасность',
              subtitle: 'Телефон, устройства и согласия',
              color: BureauColors.green,
              background: BureauColors.greenSoft,
            ),
            const SectionTitle('Демонстрация кабинетов'),
            SettingRow(
              icon: Icons.business_rounded,
              title: 'Кабинет организации',
              subtitle: 'Инвентарь, заявления и выдача',
              color: BureauColors.green,
              background: BureauColors.greenSoft,
              onTap: () => pushPage(context, const OrganizationAuthPage()),
            ),
            const SizedBox(height: 10),
            SettingRow(
              icon: Icons.admin_panel_settings_outlined,
              title: 'Кабинет модератора',
              subtitle: 'Риски, споры и антифрод',
              color: BureauColors.amber,
              background: BureauColors.amberSoft,
              onTap: () => pushPage(context, const AdminShell()),
            ),
            const SizedBox(height: 10),
            SettingRow(
              icon: Icons.grid_view_rounded,
              title: 'Все 67 экранов',
              subtitle: 'Каталог пользовательских и служебных сценариев',
              onTap: () => pushPage(context, const ScreenCatalogPage()),
            ),
          ],
        ),
      ),
    );
  }
}

class ItemDetailPage extends StatelessWidget {
  const ItemDetailPage({super.key, required this.found});

  final bool found;

  @override
  Widget build(BuildContext context) {
    final accent = found ? BureauColors.green : BureauColors.amber;
    final soft = found ? BureauColors.greenSoft : BureauColors.amberSoft;
    return BureauPage(
      title: found ? 'Найдена вещь' : 'Потеряна вещь',
      subtitle: found ? 'Публикация подтверждена' : 'Владелец ищет похожую',
      actions: [IconButton(onPressed: () {}, icon: const Icon(Icons.bookmark_border_rounded))],
      bottom: FilledButton(
        style: FilledButton.styleFrom(backgroundColor: accent),
        onPressed: () => pushPage(context, const MatchFlowPage()),
        child: Text(found ? 'Это может быть моё' : 'Я нашёл похожее'),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ItemArtwork(color: accent, background: soft),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              BureauPill(found ? 'НАХОДКА' : 'ПРОПАЖА', color: accent, background: soft),
              const BureauPill('сегодня', color: BureauColors.slate, background: Colors.white),
            ],
          ),
          const SizedBox(height: 16),
          Text('Чёрный городской рюкзак', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 10),
          Text(
            'Матовый, два отделения, красная молния. Есть уникальная деталь, скрытая для безопасной проверки владельца.',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: BureauColors.slate),
          ),
          const SectionTitle('Место'),
          const SettingRow(
            icon: Icons.location_on_outlined,
            title: 'Москва · район Тверской',
            subtitle: 'Точная точка скрыта',
          ),
          const SectionTitle('Почему подходит'),
          SoftCard(
            color: BureauColors.greenSoft,
            borderColor: BureauColors.greenSoft,
            onTap: () => pushPage(context, const MatchExplanationPage()),
            child: Row(
              children: [
                Text('93%', style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: BureauColors.green)),
                const SizedBox(width: 14),
                Expanded(child: Text('ИИ нашёл 5 совпавших признаков', style: Theme.of(context).textTheme.titleMedium)),
                const Icon(Icons.chevron_right_rounded, color: BureauColors.green),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class MatchExplanationPage extends StatelessWidget {
  const MatchExplanationPage({super.key});

  @override
  Widget build(BuildContext context) {
    const rows = [('Форма и силуэт', .96), ('Основной цвет', .94), ('Красная молния', .91), ('Район', .82), ('Дата', .78)];
    return BureauPage(
      title: 'Почему 93%',
      subtitle: 'ИИ объясняет совпадение',
      child: Column(
        children: [
          const Row(
            children: [
              Expanded(child: ItemArtwork(height: 155)),
              SizedBox(width: 10),
              Expanded(child: ItemArtwork(height: 155, color: BureauColors.green, background: BureauColors.greenSoft)),
            ],
          ),
          const SectionTitle('Совпавшие признаки'),
          ...rows.map(
            (row) => Padding(
              padding: const EdgeInsets.only(bottom: 15),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(row.$1, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontSize: 13)),
                      Text('${(row.$2 * 100).round()}%', style: const TextStyle(color: BureauColors.green, fontWeight: FontWeight.w900)),
                    ],
                  ),
                  const SizedBox(height: 7),
                  LinearProgressIndicator(
                    value: row.$2,
                    backgroundColor: BureauColors.line,
                    color: BureauColors.green,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ],
              ),
            ),
          ),
          const NoticeCard('Процент — подсказка, а не доказательство владения. Решение принимается после проверки.'),
        ],
      ),
    );
  }
}

class SearchFiltersPage extends StatelessWidget {
  const SearchFiltersPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BureauPage(
      title: 'Фильтры',
      subtitle: 'Только релевантные публикации',
      bottom: FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Показать 8 результатов')),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionTitle('Тип публикации'),
          const Wrap(spacing: 8, runSpacing: 8, children: [BureauPill('Все'), BureauPill('Находки', background: Colors.white), BureauPill('Пропажи', background: Colors.white)]),
          const SectionTitle('Категория'),
          const Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              BureauPill('Сумки'),
              BureauPill('Документы', background: Colors.white),
              BureauPill('Электроника', background: Colors.white),
              BureauPill('Ключи', background: Colors.white),
            ],
          ),
          const SectionTitle('Радиус · 25 км'),
          Slider(value: 25, min: 1, max: 50, onChanged: (_) {}),
          const SectionTitle('Период'),
          const TextField(readOnly: true, decoration: InputDecoration(prefixIcon: Icon(Icons.calendar_today_outlined), hintText: 'Последние 30 дней')),
        ],
      ),
    );
  }
}

class PhotoSearchPage extends StatelessWidget {
  const PhotoSearchPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BureauPage(
      title: 'Поиск по фото',
      subtitle: 'Форма, цвет и уникальные детали',
      bottom: FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Найти совпадения')),
      child: Column(
        children: [
          Container(
            height: 330,
            decoration: BoxDecoration(
              color: BureauColors.blueSoft,
              borderRadius: BorderRadius.circular(26),
              border: Border.all(color: BureauColors.blue, width: 1.4),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                const ItemArtwork(height: 250),
                Positioned(left: 38, right: 38, child: Container(height: 3, color: BureauColors.blue)),
                const Positioned(bottom: 20, child: BureauPill('Фото добавлено', background: Colors.white)),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const SettingRow(
            icon: Icons.location_on_outlined,
            title: 'Учитывать место и дату',
            subtitle: 'Москва · последние 3 месяца',
            trailing: BureauPill('ВКЛ'),
          ),
        ],
      ),
    );
  }
}

class NotificationsPage extends StatelessWidget {
  const NotificationsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const BureauPage(
      title: 'Уведомления',
      subtitle: '3 новых события',
      child: Column(
        children: [
          SettingRow(
            icon: Icons.auto_awesome_rounded,
            title: 'Новое совпадение · 93%',
            subtitle: 'Похожий рюкзак найден на Тверской · 5 мин',
            color: BureauColors.green,
            background: BureauColors.greenSoft,
          ),
          SizedBox(height: 10),
          SettingRow(icon: Icons.chat_bubble_outline_rounded, title: 'Новое сообщение', subtitle: 'Организация уточнила скрытую деталь · 1 ч'),
          SizedBox(height: 10),
          SettingRow(
            icon: Icons.qr_code_rounded,
            title: 'Владелец подтверждён',
            subtitle: 'Выберите способ передачи вещи · 3 ч',
            color: BureauColors.green,
            background: BureauColors.greenSoft,
          ),
        ],
      ),
    );
  }
}

class SavedPage extends StatelessWidget {
  const SavedPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BureauPage(
      title: 'Сохранённое',
      subtitle: '6 публикаций',
      child: Column(
        children: [
          LostItemCard(title: 'Чёрный городской рюкзак', meta: 'Тверская · сегодня', score: 93, onTap: () => pushPage(context, const ItemDetailPage(found: true))),
          const SizedBox(height: 12),
          LostItemCard(title: 'Серебристый ноутбук', meta: 'Аэропорт · вчера', score: 76, icon: Icons.laptop_mac_rounded, onTap: () {}),
          const SizedBox(height: 12),
          LostItemCard(title: 'Паспорт в синей обложке', meta: 'Метро · 2 дня назад', score: 68, icon: Icons.badge_outlined, onTap: () {}),
        ],
      ),
    );
  }
}
