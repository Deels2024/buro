import 'package:flutter/material.dart';

import 'theme.dart';

class BureauPage extends StatelessWidget {
  const BureauPage({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.actions,
    this.bottom,
    this.padding = const EdgeInsets.fromLTRB(20, 8, 20, 28),
  });

  final String title;
  final String? subtitle;
  final Widget child;
  final List<Widget>? actions;
  final Widget? bottom;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: BureauColors.canvas,
        surfaceTintColor: Colors.transparent,
        titleSpacing: Navigator.canPop(context) ? 0 : 20,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            if (subtitle != null)
              Text(
                subtitle!,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 11),
              ),
          ],
        ),
        actions: actions,
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: padding,
                child: child,
              ),
            ),
            if (bottom != null)
              Container(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  border: Border(top: BorderSide(color: BureauColors.line)),
                ),
                child: bottom,
              ),
          ],
        ),
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 12),
      child: Row(
        children: [
          Expanded(child: Text(text, style: Theme.of(context).textTheme.titleMedium)),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

class BureauPill extends StatelessWidget {
  const BureauPill(
    this.label, {
    super.key,
    this.color = BureauColors.blue,
    this.background = BureauColors.blueSoft,
    this.icon,
  });

  final String label;
  final Color color;
  final Color background;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(99)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class SoftCard extends StatelessWidget {
  const SoftCard({
    super.key,
    required this.child,
    this.color = Colors.white,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
    this.borderColor = BureauColors.line,
  });

  final Widget child;
  final Color color;
  final EdgeInsets padding;
  final VoidCallback? onTap;
  final Color borderColor;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: borderColor),
        borderRadius: BorderRadius.circular(22),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

class IconTile extends StatelessWidget {
  const IconTile({
    super.key,
    required this.icon,
    this.color = BureauColors.blue,
    this.background = BureauColors.blueSoft,
    this.size = 52,
  });

  final IconData icon;
  final Color color;
  final Color background;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(17)),
      child: Icon(icon, color: color, size: size * .45),
    );
  }
}

class MetricCard extends StatelessWidget {
  const MetricCard({
    super.key,
    required this.value,
    required this.label,
    this.color = BureauColors.navy,
  });

  final String value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: color, fontSize: 23),
          ),
          const SizedBox(height: 7),
          Text(label, style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 10)),
        ],
      ),
    );
  }
}

class NoticeCard extends StatelessWidget {
  const NoticeCard(
    this.text, {
    super.key,
    this.color = BureauColors.green,
    this.background = BureauColors.greenSoft,
    this.icon = Icons.verified_user_rounded,
  });

  final String text;
  final Color color;
  final Color background;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(17)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 19, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: color, fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }
}

class ItemArtwork extends StatelessWidget {
  const ItemArtwork({
    super.key,
    this.icon = Icons.backpack_rounded,
    this.color = BureauColors.blue,
    this.background = BureauColors.blueSoft,
    this.height = 220,
  });

  final IconData icon;
  final Color color;
  final Color background;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: height,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [background, Colors.white],
        ),
        borderRadius: BorderRadius.circular(26),
      ),
      child: Center(
        child: Container(
          width: height * .52,
          height: height * .52,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(30),
            boxShadow: [
              BoxShadow(
                color: BureauColors.navy.withOpacity(.08),
                blurRadius: 30,
                offset: const Offset(0, 16),
              ),
            ],
          ),
          child: Icon(icon, size: height * .27, color: color),
        ),
      ),
    );
  }
}

class LostItemCard extends StatelessWidget {
  const LostItemCard({
    super.key,
    required this.title,
    required this.meta,
    required this.score,
    this.icon = Icons.backpack_rounded,
    this.found = true,
    this.onTap,
  });

  final String title;
  final String meta;
  final int score;
  final IconData icon;
  final bool found;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final accent = found ? BureauColors.green : BureauColors.amber;
    final soft = found ? BureauColors.greenSoft : BureauColors.amberSoft;
    return SoftCard(
      onTap: onTap,
      padding: const EdgeInsets.all(11),
      child: Row(
        children: [
          Container(
            width: 92,
            height: 92,
            decoration: BoxDecoration(color: soft, borderRadius: BorderRadius.circular(18)),
            child: Icon(icon, color: accent, size: 42),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 6),
                Text(meta, style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 11)),
                const SizedBox(height: 12),
                BureauPill(
                  '$score% совпадение',
                  color: score >= 90 ? BureauColors.green : BureauColors.blue,
                  background: score >= 90 ? BureauColors.greenSoft : BureauColors.blueSoft,
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded, color: BureauColors.muted),
        ],
      ),
    );
  }
}

class NativeAdCard extends StatelessWidget {
  const NativeAdCard({super.key});

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      color: const Color(0xFFF8FAFD),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'РЕКЛАМА · ПАРТНЁР СЕТИ',
                style: TextStyle(color: BureauColors.muted, fontSize: 8, fontWeight: FontWeight.w800),
              ),
              Icon(Icons.more_horiz_rounded, color: BureauColors.muted, size: 18),
            ],
          ),
          const SizedBox(height: 11),
          Row(
            children: [
              const IconTile(
                icon: Icons.shield_outlined,
                color: BureauColors.green,
                background: BureauColors.greenSoft,
                size: 46,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('SafePoint рядом', style: Theme.of(context).textTheme.titleMedium),
                    Text(
                      'Безопасное хранение и передача вещей',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 10),
                    ),
                  ],
                ),
              ),
              TextButton(onPressed: () {}, child: const Text('Открыть')),
            ],
          ),
          const SizedBox(height: 7),
          const Text(
            'erid: 2VtzqwX7M3 · 0+ · Почему эта реклама',
            style: TextStyle(color: BureauColors.muted, fontSize: 8),
          ),
        ],
      ),
    );
  }
}

class SettingRow extends StatelessWidget {
  const SettingRow({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.color = BureauColors.blue,
    this.background = BureauColors.blueSoft,
    this.trailing,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final Color background;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      onTap: onTap,
      child: Row(
        children: [
          IconTile(icon: icon, color: color, background: background),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(subtitle, style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 10)),
              ],
            ),
          ),
          trailing ?? const Icon(Icons.chevron_right_rounded, color: BureauColors.muted),
        ],
      ),
    );
  }
}

void pushPage(BuildContext context, Widget page) {
  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
}
