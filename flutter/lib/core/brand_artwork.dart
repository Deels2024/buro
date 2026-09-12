import 'package:flutter/material.dart';

import 'theme.dart';

enum BureauArtwork { belongings, handover }

/// Decorative artwork is never used in place of a user's listing photograph.
class BureauIllustration extends StatelessWidget {
  const BureauIllustration({super.key, required this.artwork, this.size = 128});

  final BureauArtwork artwork;
  final double size;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: Image.asset(
        artwork == BureauArtwork.belongings
            ? 'assets/illustrations/belongings.webp'
            : 'assets/illustrations/return.webp',
        width: size,
        height: size,
        cacheWidth: 512,
        fit: BoxFit.cover,
        errorBuilder: (_, error, stack) => SizedBox(
          width: size,
          height: size,
          child: Icon(
            artwork == BureauArtwork.belongings
                ? Icons.backpack_outlined
                : Icons.volunteer_activism_outlined,
            size: size * .45,
            color: BureauColors.blue,
          ),
        ),
      ),
    ),
  );
}

class DiscoveryHero extends StatelessWidget {
  const DiscoveryHero({super.key, required this.onSearch});
  final VoidCallback onSearch;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: const Color(0xFFF0F5F8),
      borderRadius: BorderRadius.circular(28),
      border: Border.all(color: const Color(0xFFE4EDF2)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(builder: (context, constraints) {
          final stacked = constraints.maxWidth < 295 ||
              MediaQuery.textScalerOf(context).scale(16) > 20;
          final copy = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Найдём то,\nчто вам дорого',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontSize: 24)),
              const SizedBox(height: 10),
              Text('Пропажи и находки.\nЛюди помогают людям.',
                style: Theme.of(context).textTheme.bodyMedium),
            ],
          );
          if (stacked) {
            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              copy,
              const SizedBox(height: 12),
              const Align(alignment: Alignment.centerRight,
                child: BureauIllustration(artwork: BureauArtwork.belongings, size: 108)),
            ]);
          }
          return Row(children: [
            Expanded(child: copy),
            const SizedBox(width: 8),
            BureauIllustration(artwork: BureauArtwork.belongings,
              size: constraints.maxWidth >= 450 ? 164 : 112),
          ]);
        }),
        const SizedBox(height: 20),
        Material(
          color: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: BureauColors.line)),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onSearch,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              child: Row(children: [
                const Icon(Icons.search_rounded, size: 22, color: BureauColors.blue),
                const SizedBox(width: 10),
                Expanded(child: Text('Найти вещь', style: Theme.of(context).textTheme.bodyLarge)),
                const Icon(Icons.arrow_forward_rounded, size: 20, color: BureauColors.slate),
              ]),
            ),
          ),
        ),
      ],
    ),
  );
}

class ReturnWelcome extends StatelessWidget {
  const ReturnWelcome({super.key});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(color: const Color(0xFFF0F5F8),
      borderRadius: BorderRadius.circular(24)),
    child: Row(children: [
      const BureauIllustration(artwork: BureauArtwork.handover, size: 96),
      const SizedBox(width: 16),
      Expanded(child: Text('Найти своё.\nВернуть чужое.',
        style: Theme.of(context).textTheme.titleMedium)),
    ]),
  );
}
