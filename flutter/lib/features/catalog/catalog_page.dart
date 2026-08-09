import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../data/screen_catalog.dart';

class ScreenCatalogPage extends StatefulWidget {
  const ScreenCatalogPage({super.key});

  @override
  State<ScreenCatalogPage> createState() => _ScreenCatalogPageState();
}

class _ScreenCatalogPageState extends State<ScreenCatalogPage> {
  int _role = 0;
  String _query = '';

  List<ScreenSpec> get _screens {
    final role = switch (_role) {
      1 => BureauRole.user,
      2 => BureauRole.organization,
      3 => BureauRole.admin,
      _ => null,
    };
    return allScreenSpecs.where((screen) {
      final matchesRole = role == null || screen.role == role;
      final query = _query.trim().toLowerCase();
      final matchesQuery = query.isEmpty || '${screen.id} ${screen.title} ${screen.template}'.toLowerCase().contains(query);
      return matchesRole && matchesQuery;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: BureauColors.canvas,
        surfaceTintColor: Colors.transparent,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Все экраны', style: Theme.of(context).textTheme.titleLarge),
            Text('67 сценариев · Flutter', style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 10)),
          ],
        ),
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: Column(
                children: [
                  TextField(
                    onChanged: (value) => setState(() => _query = value),
                    decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded), hintText: 'ID или название экрана'),
                  ),
                  const SizedBox(height: 12),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _FilterChip('Все · 67', 0, BureauColors.blue),
                        _FilterChip('Пользователь · 40', 1, BureauColors.blue),
                        _FilterChip('Организация · 20', 2, BureauColors.green),
                        _FilterChip('Модерация · 7', 3, BureauColors.amber),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
                itemCount: _screens.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final screen = _screens[index];
                  final (accent, soft, icon) = _roleStyle(screen.role);
                  return SettingRow(
                    icon: icon,
                    title: screen.title,
                    subtitle: '${screen.id} · ${screen.template}',
                    color: accent,
                    background: soft,
                    trailing: BureauPill(screen.id, color: accent, background: soft),
                    onTap: () => pushPage(context, CatalogPreviewPage(screen: screen)),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _FilterChip(String label, int value, Color color) {
    final active = _role == value;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: active,
        onSelected: (_) => setState(() => _role = value),
        selectedColor: color,
        backgroundColor: Colors.white,
        side: const BorderSide(color: BureauColors.line),
        labelStyle: TextStyle(
          color: active ? Colors.white : BureauColors.slate,
          fontSize: 10,
          fontWeight: FontWeight.w800,
        ),
        showCheckmark: false,
      ),
    );
  }
}

(Color, Color, IconData) _roleStyle(BureauRole role) {
  return switch (role) {
    BureauRole.user => (BureauColors.blue, BureauColors.blueSoft, Icons.person_outline_rounded),
    BureauRole.organization => (BureauColors.green, BureauColors.greenSoft, Icons.business_outlined),
    BureauRole.admin => (BureauColors.amber, BureauColors.amberSoft, Icons.admin_panel_settings_outlined),
  };
}

class CatalogPreviewPage extends StatelessWidget {
  const CatalogPreviewPage({super.key, required this.screen});

  final ScreenSpec screen;

  @override
  Widget build(BuildContext context) {
    final (accent, soft, _) = _roleStyle(screen.role);
    return BureauPage(
      title: screen.title,
      subtitle: '${screen.id} · ${screen.template}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [accent, Color.lerp(accent, Colors.white, .18)!]),
              borderRadius: BorderRadius.circular(28),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                BureauPill(screen.id, color: accent, background: Colors.white),
                const SizedBox(height: 24),
                Text(screen.title, style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: Colors.white)),
                const SizedBox(height: 8),
                Text(_roleLabel(screen.role), style: const TextStyle(color: Colors.white70, fontSize: 12)),
              ],
            ),
          ),
          const SizedBox(height: 18),
          _templatePreview(context, accent, soft),
          const SizedBox(height: 16),
          NoticeCard(
            'Экран включён в общий Flutter-каталог и использует компоненты единой дизайн-системы.',
            color: accent,
            background: soft,
            icon: Icons.widgets_outlined,
          ),
        ],
      ),
    );
  }

  String _roleLabel(BureauRole role) => switch (role) {
        BureauRole.user => 'Пользовательское приложение',
        BureauRole.organization => 'Кабинет организации',
        BureauRole.admin => 'Модерация и антифрод',
      };

  Widget _templatePreview(BuildContext context, Color accent, Color soft) {
    final template = screen.template.toLowerCase();
    if (template.contains('chat')) {
      return Column(
        children: [
          const Align(alignment: Alignment.centerLeft, child: _PreviewBubble('Уточните скрытую деталь вещи.')),
          const SizedBox(height: 10),
          Align(alignment: Alignment.centerRight, child: _PreviewBubble('Она находится во внутреннем кармане.', color: accent)),
          const SizedBox(height: 14),
          const TextField(decoration: InputDecoration(hintText: 'Сообщение…', suffixIcon: Icon(Icons.send_rounded))),
        ],
      );
    }
    if (template.contains('qr') || template.contains('scanner')) {
      return Container(
        height: 290,
        decoration: BoxDecoration(color: soft, borderRadius: BorderRadius.circular(26)),
        child: Center(child: Icon(Icons.qr_code_scanner_rounded, color: accent, size: 120)),
      );
    }
    if (template.contains('dashboard') || template.contains('analytics') || template.contains('fraud')) {
      return Column(
        children: [
          Row(
            children: [
              Expanded(child: MetricCard(value: '148', label: 'объектов', color: accent)),
              const SizedBox(width: 10),
              Expanded(child: MetricCard(value: '93%', label: 'качество', color: accent)),
            ],
          ),
          const SizedBox(height: 10),
          SoftCard(
            child: SizedBox(
              height: 130,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [42.0, 76.0, 58.0, 96.0, 70.0, 108.0]
                    .map((value) => Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 5), child: Container(height: value, decoration: BoxDecoration(color: accent, borderRadius: const BorderRadius.vertical(top: Radius.circular(7)))))))
                    .toList(),
              ),
            ),
          ),
        ],
      );
    }
    if (template.contains('media') || template.contains('detail') || template.contains('record') || template.contains('preview')) {
      return ItemArtwork(height: 240, color: accent, background: soft);
    }
    return Column(
      children: [
        SettingRow(icon: Icons.auto_awesome_rounded, title: 'Умный сценарий', subtitle: 'ИИ помогает заполнить данные', color: accent, background: soft),
        const SizedBox(height: 10),
        SettingRow(icon: Icons.shield_outlined, title: 'Защищённые данные', subtitle: 'Контакты и точное место скрыты', color: accent, background: soft),
        const SizedBox(height: 10),
        SettingRow(icon: Icons.notifications_none_rounded, title: 'Статус и уведомления', subtitle: 'Изменения приходят в реальном времени', color: accent, background: soft),
      ],
    );
  }
}

class _PreviewBubble extends StatelessWidget {
  const _PreviewBubble(this.text, {this.color = Colors.white});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final outgoing = color != Colors.white;
    return Container(
      constraints: const BoxConstraints(maxWidth: 290),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(18), border: outgoing ? null : Border.all(color: BureauColors.line)),
      child: Text(text, style: TextStyle(color: outgoing ? Colors.white : BureauColors.navy, fontSize: 12)),
    );
  }
}
