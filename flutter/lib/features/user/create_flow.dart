import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../core/widgets.dart';

class CreateFlowPage extends StatefulWidget {
  const CreateFlowPage({super.key, required this.initialFound});

  final bool initialFound;

  @override
  State<CreateFlowPage> createState() => _CreateFlowPageState();
}

class _CreateFlowPageState extends State<CreateFlowPage> {
  int _step = 0;
  late bool _found = widget.initialFound;

  List<String> get _titles => _found
      ? ['Фото и видео', 'Описание находки', 'Безопасное место', 'Предпросмотр']
      : ['Фото и видео', 'Описание пропажи', 'Место и время', 'Предпросмотр'];

  void _next() {
    if (_step == 3) {
      setState(() => _step = 4);
      return;
    }
    setState(() => _step += 1);
  }

  void _back() {
    if (_step == 0) {
      Navigator.pop(context);
      return;
    }
    setState(() => _step -= 1);
  }

  @override
  Widget build(BuildContext context) {
    if (_step == 4) {
      return _SuccessPage(found: _found);
    }

    final accent = _found ? BureauColors.green : BureauColors.blue;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: BureauColors.canvas,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(onPressed: _back, icon: const Icon(Icons.arrow_back_rounded)),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_titles[_step], style: Theme.of(context).textTheme.titleLarge),
            Text('Шаг ${_step + 1} из 4', style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 10)),
          ],
        ),
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            LinearProgressIndicator(
              value: (_step + 1) / 4,
              minHeight: 4,
              backgroundColor: BureauColors.line,
              color: accent,
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 22, 20, 28),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  child: KeyedSubtree(key: ValueKey(_step), child: _body(context)),
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(top: BorderSide(color: BureauColors.line)),
              ),
              child: FilledButton(
                style: FilledButton.styleFrom(backgroundColor: accent),
                onPressed: _next,
                child: Text(_step == 3 ? 'Опубликовать' : 'Продолжить'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _body(BuildContext context) {
    switch (_step) {
      case 0:
        return _MediaStep(found: _found);
      case 1:
        return _DetailsStep(found: _found);
      case 2:
        return _LocationStep(found: _found);
      default:
        return _PreviewStep(
          found: _found,
          onChangeType: () => setState(() => _found = !_found),
        );
    }
  }
}

class _MediaStep extends StatelessWidget {
  const _MediaStep({required this.found});

  final bool found;

  @override
  Widget build(BuildContext context) {
    final accent = found ? BureauColors.green : BureauColors.blue;
    final soft = found ? BureauColors.greenSoft : BureauColors.blueSoft;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          found ? 'Покажите вещь с разных сторон' : 'Добавьте фото потерянной вещи',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        Text(
          'До 8 фотографий и одно видео до 30 секунд. ИИ поможет заполнить описание.',
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: BureauColors.slate),
        ),
        const SizedBox(height: 22),
        Container(
          height: 300,
          decoration: BoxDecoration(color: soft, borderRadius: BorderRadius.circular(26)),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.add_a_photo_rounded, size: 54, color: accent),
                const SizedBox(height: 12),
                Text('Добавить фото', style: Theme.of(context).textTheme.titleMedium?.copyWith(color: accent)),
                const SizedBox(height: 5),
                Text('Камера или галерея', style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 10)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _MediaSlot(icon: Icons.add_rounded, label: 'Ещё фото', color: accent),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _MediaSlot(icon: Icons.videocam_outlined, label: 'Видео', color: accent),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _MediaSlot(icon: Icons.auto_fix_high_rounded, label: 'Улучшить', color: accent),
            ),
          ],
        ),
        const SizedBox(height: 18),
        NoticeCard(
          found
              ? 'Не показывайте серийные номера и уникальные детали — они пригодятся для проверки владельца.'
              : 'Если старого фото нет, добавьте похожее изображение или пропустите этот шаг.',
          color: accent,
          background: soft,
          icon: Icons.auto_awesome_rounded,
        ),
      ],
    );
  }
}

class _MediaSlot extends StatelessWidget {
  const _MediaSlot({required this.icon, required this.label, required this.color});

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 88,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: BureauColors.line),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color),
          const SizedBox(height: 7),
          Text(label, style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 9)),
        ],
      ),
    );
  }
}

class _DetailsStep extends StatelessWidget {
  const _DetailsStep({required this.found});

  final bool found;

  @override
  Widget build(BuildContext context) {
    final accent = found ? BureauColors.green : BureauColors.blue;
    final soft = found ? BureauColors.greenSoft : BureauColors.blueSoft;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SoftCard(
          color: soft,
          borderColor: soft,
          child: Row(
            children: [
              IconTile(icon: Icons.auto_awesome_rounded, color: accent, background: Colors.white),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('ИИ подготовил черновик', style: Theme.of(context).textTheme.titleMedium),
                    Text('Проверьте описание перед публикацией', style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 10)),
                  ],
                ),
              ),
              BureauPill('ГОТОВО', color: accent, background: Colors.white),
            ],
          ),
        ),
        const SectionTitle('Название'),
        const TextField(decoration: InputDecoration(hintText: 'Чёрный городской рюкзак')),
        const SectionTitle('Категория'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            BureauPill('Сумки', color: accent, background: soft),
            const BureauPill('Документы', color: BureauColors.slate, background: Colors.white),
            const BureauPill('Электроника', color: BureauColors.slate, background: Colors.white),
          ],
        ),
        const SectionTitle('Описание'),
        const TextField(
          maxLines: 5,
          decoration: InputDecoration(
            hintText: 'Матовый материал, два отделения, красная молния…',
            alignLabelWithHint: true,
          ),
        ),
        SectionTitle(found ? 'Скрытая деталь' : 'Особые приметы'),
        TextField(
          maxLines: 3,
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.lock_outline_rounded),
            hintText: found
                ? 'Например: зелёный ярлык внутри кармана'
                : 'Например: потёртость на левой лямке',
          ),
        ),
        const SizedBox(height: 12),
        NoticeCard(
          found ? 'Скрытую деталь увидят только сотрудники проверки.' : 'Особые приметы помогают ИИ повысить точность поиска.',
          color: accent,
          background: soft,
        ),
      ],
    );
  }
}

class _LocationStep extends StatelessWidget {
  const _LocationStep({required this.found});

  final bool found;

  @override
  Widget build(BuildContext context) {
    final accent = found ? BureauColors.green : BureauColors.blue;
    final soft = found ? BureauColors.greenSoft : BureauColors.blueSoft;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          found ? 'Где вещь находится сейчас?' : 'Где вы видели вещь в последний раз?',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 16),
        const TextField(
          decoration: InputDecoration(prefixIcon: Icon(Icons.location_on_outlined), hintText: 'Москва, Тверской район'),
        ),
        const SizedBox(height: 12),
        Container(
          height: 260,
          decoration: BoxDecoration(color: const Color(0xFFE9EEF4), borderRadius: BorderRadius.circular(24)),
          child: Center(
            child: Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(color: accent, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 4)),
              child: const Icon(Icons.location_on_rounded, color: Colors.white),
            ),
          ),
        ),
        const SectionTitle('Дата и время'),
        const Row(
          children: [
            Expanded(child: TextField(readOnly: true, decoration: InputDecoration(prefixIcon: Icon(Icons.calendar_today_outlined), hintText: 'Сегодня'))),
            SizedBox(width: 10),
            Expanded(child: TextField(readOnly: true, decoration: InputDecoration(prefixIcon: Icon(Icons.schedule_rounded), hintText: 'Около 14:30'))),
          ],
        ),
        if (found) ...[
          const SectionTitle('Место хранения'),
          const SettingRow(
            icon: Icons.home_work_outlined,
            title: 'У меня',
            subtitle: 'Адрес не публикуется',
            trailing: BureauPill('ВЫБРАНО', color: BureauColors.green, background: BureauColors.greenSoft),
          ),
        ],
        const SizedBox(height: 14),
        NoticeCard(
          'Пользователи увидят только примерный район. Точная точка откроется после подтверждения.',
          color: accent,
          background: soft,
        ),
      ],
    );
  }
}

class _PreviewStep extends StatelessWidget {
  const _PreviewStep({required this.found, required this.onChangeType});

  final bool found;
  final VoidCallback onChangeType;

  @override
  Widget build(BuildContext context) {
    final accent = found ? BureauColors.green : BureauColors.blue;
    final soft = found ? BureauColors.greenSoft : BureauColors.blueSoft;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const ItemArtwork(),
        const SizedBox(height: 14),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            BureauPill(found ? 'НАХОДКА' : 'ПРОПАЖА', color: accent, background: soft),
            TextButton(onPressed: onChangeType, child: const Text('Изменить тип')),
          ],
        ),
        Text('Чёрный городской рюкзак', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 10),
        Text(
          'Матовый материал, два отделения, красная молния. Есть скрытая уникальная деталь.',
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: BureauColors.slate),
        ),
        const SectionTitle('Публикация увидит'),
        const SettingRow(
          icon: Icons.location_on_outlined,
          title: 'Москва · Тверской район',
          subtitle: 'Точная точка скрыта',
        ),
        const SizedBox(height: 10),
        const SettingRow(
          icon: Icons.schedule_rounded,
          title: 'Сегодня · около 14:30',
          subtitle: 'Время можно уточнить позже',
        ),
        const SizedBox(height: 14),
        NoticeCard(
          found ? 'Контакты будут скрыты до проверки владельца.' : 'ИИ начнёт искать совпадения сразу после публикации.',
          color: accent,
          background: soft,
        ),
      ],
    );
  }
}

class _SuccessPage extends StatelessWidget {
  const _SuccessPage({required this.found});

  final bool found;

  @override
  Widget build(BuildContext context) {
    final accent = found ? BureauColors.green : BureauColors.blue;
    final soft = found ? BureauColors.greenSoft : BureauColors.blueSoft;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const Spacer(),
              Container(
                width: 140,
                height: 140,
                decoration: BoxDecoration(color: soft, shape: BoxShape.circle),
                child: Icon(Icons.check_rounded, color: accent, size: 70),
              ),
              const SizedBox(height: 30),
              Text('Публикация создана', textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 12),
              Text(
                found
                    ? 'ИИ уже ищет возможного владельца. Мы сообщим о хорошем совпадении.'
                    : 'ИИ уже сравнивает объявление с находками по всей сети.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: BureauColors.slate),
              ),
              const SizedBox(height: 24),
              SoftCard(
                color: soft,
                borderColor: soft,
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('ID публикации', style: TextStyle(color: BureauColors.slate, fontSize: 10)),
                        SizedBox(height: 4),
                        Text('BN-4829', style: TextStyle(color: BureauColors.navy, fontWeight: FontWeight.w900)),
                      ],
                    ),
                    BureauPill('АКТИВНА'),
                  ],
                ),
              ),
              const Spacer(),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: accent),
                onPressed: () => Navigator.of(context).popUntil((route) => route.isFirst),
                child: const Text('Готово'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
