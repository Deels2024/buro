import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../core/widgets.dart';

class MatchFlowPage extends StatefulWidget {
  const MatchFlowPage({super.key});

  @override
  State<MatchFlowPage> createState() => _MatchFlowPageState();
}

class _MatchFlowPageState extends State<MatchFlowPage> {
  int _step = 0;

  static const _titles = [
    'Центр совпадений',
    'Сравнение',
    'Подтверждение владельца',
    'Контрольные вопросы',
    'Доказательства',
    'Проверка заявления',
    'Защищённый чат',
    'Открытие контактов',
    'Способ передачи',
    'QR передачи',
    'Вещь возвращена',
  ];

  void _next() => setState(
        () => _step = (_step + 1).clamp(0, _titles.length - 1).toInt(),
      );

  @override
  Widget build(BuildContext context) {
    if (_step == 10) {
      return _CompletePage(onDone: () => Navigator.pop(context));
    }
    return BureauPage(
      title: _titles[_step],
      subtitle: _subtitle,
      bottom: FilledButton(
        style: FilledButton.styleFrom(backgroundColor: _step >= 6 ? BureauColors.green : BureauColors.blue),
        onPressed: _next,
        child: Text(_buttonLabel),
      ),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        child: KeyedSubtree(key: ValueKey(_step), child: _body(context)),
      ),
    );
  }

  String get _subtitle => switch (_step) {
        0 => 'Найдено 8 возможных совпадений',
        1 => 'ИИ оценивает сходство в 93%',
        2 => 'Безопасная проверка за несколько шагов',
        3 => 'Ответы не увидят другие пользователи',
        4 => 'Добавьте то, что существовало до пропажи',
        5 => 'Проверим данные перед отправкой',
        6 => 'Контакты пока скрыты',
        7 => 'Обе стороны должны согласиться',
        8 => 'Выберите удобный и безопасный вариант',
        9 => 'Покажите код при получении',
        _ => '',
      };

  String get _buttonLabel => switch (_step) {
        0 => 'Сравнить совпадение',
        1 => 'Это может быть моё',
        2 => 'Начать подтверждение',
        3 => 'Продолжить',
        4 => 'Отправить доказательства',
        5 => 'Отправить заявление',
        6 => 'Данных достаточно',
        7 => 'Разрешить открыть контакты',
        8 => 'Создать QR передачи',
        9 => 'Подтвердить получение',
        _ => 'Продолжить',
      };

  Widget _body(BuildContext context) {
    switch (_step) {
      case 0:
        return _matchHub(context);
      case 1:
        return _compare(context);
      case 2:
        return _claimStart(context);
      case 3:
        return _questions(context);
      case 4:
        return _evidence(context);
      case 5:
        return _review(context);
      case 6:
        return _chat(context);
      case 7:
        return _consent(context);
      case 8:
        return _handover(context);
      default:
        return _qr(context);
    }
  }

  Widget _matchHub(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SoftCard(
          color: BureauColors.greenSoft,
          borderColor: BureauColors.greenSoft,
          child: Column(
            children: [
              const Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  BureauPill('ЛУЧШЕЕ СОВПАДЕНИЕ', color: BureauColors.green, background: Colors.white),
                  Text('93%', style: TextStyle(color: BureauColors.green, fontWeight: FontWeight.w900, fontSize: 30)),
                ],
              ),
              const SizedBox(height: 18),
              const ItemArtwork(height: 200, color: BureauColors.green, background: Colors.white),
              const SizedBox(height: 16),
              Text('Рюкзак с красной молнией', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 5),
              Text('Москва · Тверская · найден сегодня', style: Theme.of(context).textTheme.bodyMedium),
            ],
          ),
        ),
        const SectionTitle('Ещё варианты'),
        const LostItemCard(title: 'Городской рюкзак', meta: 'Арбат · вчера', score: 81),
        const SizedBox(height: 10),
        const LostItemCard(title: 'Чёрная спортивная сумка', meta: 'Хамовники · 3 дня назад', score: 68, icon: Icons.luggage_rounded),
      ],
    );
  }

  Widget _compare(BuildContext context) {
    const features = [('Форма', 96), ('Цвет', 94), ('Красная молния', 91), ('Место', 82), ('Дата', 78)];
    return Column(
      children: [
        const Row(
          children: [
            Expanded(child: ItemArtwork(height: 160)),
            SizedBox(width: 10),
            Expanded(child: ItemArtwork(height: 160, color: BureauColors.green, background: BureauColors.greenSoft)),
          ],
        ),
        const SectionTitle('Совпавшие признаки'),
        SoftCard(
          child: Column(
            children: features
                .map(
                  (item) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      children: [
                        const Icon(Icons.check_circle_rounded, color: BureauColors.green, size: 19),
                        const SizedBox(width: 9),
                        Expanded(child: Text(item.$1, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontSize: 13))),
                        Text('${item.$2}%', style: const TextStyle(color: BureauColors.green, fontWeight: FontWeight.w900)),
                      ],
                    ),
                  ),
                )
                .toList(),
          ),
        ),
        const SizedBox(height: 14),
        const NoticeCard('ИИ помогает найти кандидата, но не подтверждает право собственности.'),
      ],
    );
  }

  Widget _claimStart(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const ItemArtwork(height: 190, color: BureauColors.green, background: BureauColors.greenSoft),
        const SectionTitle('Как проходит проверка'),
        ...[
          (Icons.quiz_outlined, 'Ответьте на вопросы', 'О скрытых деталях, которых нет в публикации.'),
          (Icons.photo_library_outlined, 'Добавьте доказательство', 'Старое фото, чек или упаковка — если есть.'),
          (Icons.chat_bubble_outline_rounded, 'Уточните детали в чате', 'Контакты останутся скрыты до решения.'),
        ].asMap().entries.map(
          (entry) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: SettingRow(
              icon: entry.value.$1,
              title: '${entry.key + 1}. ${entry.value.$2}',
              subtitle: entry.value.$3,
              trailing: const Icon(Icons.check_rounded, color: BureauColors.green),
            ),
          ),
        ),
        const SizedBox(height: 6),
        const NoticeCard('Не сообщайте паспортные данные, коды из SMS и данные банковских карт.'),
      ],
    );
  }

  Widget _questions(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const BureauPill('ВОПРОС 1 ИЗ 3'),
        const SizedBox(height: 18),
        Text('Какого цвета внутренняя подкладка?', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 18),
        const TextField(maxLines: 3, decoration: InputDecoration(hintText: 'Напишите ответ…')),
        const SectionTitle('Вопрос 2'),
        Text('Что находится во внутреннем кармане?', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 10),
        const TextField(maxLines: 2, decoration: InputDecoration(hintText: 'Опишите уникальную деталь…')),
        const SectionTitle('Вопрос 3'),
        Text('Какой бренд указан на ярлыке?', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 10),
        const TextField(decoration: InputDecoration(hintText: 'Название или первые буквы')),
        const SizedBox(height: 14),
        const NoticeCard('Ответы сравниваются со скрытой карточкой находки.'),
      ],
    );
  }

  Widget _evidence(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Подтвердите, что вещь была у вас до пропажи', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 18),
        Container(
          width: double.infinity,
          height: 220,
          decoration: BoxDecoration(
            color: BureauColors.blueSoft,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: BureauColors.blue, width: 1.2),
          ),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.add_photo_alternate_outlined, color: BureauColors.blue, size: 50),
                const SizedBox(height: 10),
                Text('Добавить старое фото', style: Theme.of(context).textTheme.titleMedium?.copyWith(color: BureauColors.blue)),
                Text('Метаданные помогут проверить дату', style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 10)),
              ],
            ),
          ),
        ),
        const SectionTitle('Дополнительно'),
        const SettingRow(icon: Icons.receipt_long_outlined, title: 'Чек или гарантия', subtitle: 'Скройте платёжные данные'),
        const SizedBox(height: 10),
        const SettingRow(icon: Icons.inventory_2_outlined, title: 'Упаковка или серийный номер', subtitle: 'Будет виден только проверяющему'),
        const SizedBox(height: 14),
        const NoticeCard('Можно продолжить без документов — тогда организация задаст больше вопросов.'),
      ],
    );
  }

  Widget _review(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SoftCard(
          color: BureauColors.greenSoft,
          borderColor: BureauColors.greenSoft,
          child: Row(
            children: [
              Text('93%', style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: BureauColors.green)),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Высокая уверенность', style: Theme.of(context).textTheme.titleMedium),
                    Text('Риск заявления низкий', style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 10)),
                  ],
                ),
              ),
              const BureauPill('НИЗКИЙ РИСК', color: BureauColors.green, background: Colors.white),
            ],
          ),
        ),
        const SectionTitle('Ваши ответы'),
        const SettingRow(icon: Icons.quiz_outlined, title: '3 ответа заполнены', subtitle: 'Скрытые признаки указаны'),
        const SizedBox(height: 10),
        const SettingRow(
          icon: Icons.photo_library_outlined,
          title: 'Старое фото добавлено',
          subtitle: 'Дата раньше публикации находки',
          color: BureauColors.green,
          background: BureauColors.greenSoft,
        ),
        const SectionTitle('Что произойдёт'),
        const NoticeCard('Заявление получит нашедший вещь или сотрудник организации. Контакты пока останутся скрыты.'),
      ],
    );
  }

  Widget _chat(BuildContext context) {
    return Column(
      children: [
        const NoticeCard('Чат защищён. Телефон, фамилия и точное место скрыты.'),
        const SizedBox(height: 20),
        const _Bubble(
          text: 'Уточните, пожалуйста, цвет внутренней подкладки.',
          time: '12:40',
        ),
        const SizedBox(height: 10),
        const _Bubble(
          text: 'Тёмно-синяя. Возле зелёного ярлыка есть белая строчка.',
          time: '12:42 ✓✓',
          outgoing: true,
        ),
        const SizedBox(height: 10),
        const _Bubble(
          text: 'Описание совпадает. Можно переходить к передаче.',
          time: '12:44',
        ),
        const SizedBox(height: 22),
        const TextField(
          decoration: InputDecoration(
            hintText: 'Сообщение…',
            suffixIcon: Icon(Icons.send_rounded, color: BureauColors.blue),
          ),
        ),
      ],
    );
  }

  Widget _consent(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 130,
          height: 130,
          decoration: const BoxDecoration(color: BureauColors.greenSoft, shape: BoxShape.circle),
          child: const Icon(Icons.handshake_outlined, color: BureauColors.green, size: 62),
        ),
        const SizedBox(height: 26),
        Text('Владелец подтверждён', style: Theme.of(context).textTheme.headlineSmall, textAlign: TextAlign.center),
        const SizedBox(height: 10),
        Text(
          'Откройте контакты только если готовы договориться о безопасной передаче.',
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: BureauColors.slate),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 22),
        const SettingRow(
          icon: Icons.phone_outlined,
          title: 'Телефон',
          subtitle: '+7 999 •••-42-10',
          trailing: BureauPill('СКРЫТ'),
        ),
        const SizedBox(height: 10),
        const SettingRow(
          icon: Icons.location_on_outlined,
          title: 'Точная точка',
          subtitle: 'Откроется после согласия обеих сторон',
          trailing: BureauPill('СКРЫТА'),
        ),
        const SizedBox(height: 16),
        const NoticeCard('Сервис сохранит факт взаимного согласия в журнале безопасности.'),
      ],
    );
  }

  Widget _handover(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Как удобнее получить вещь?', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 18),
        const SettingRow(
          icon: Icons.storefront_outlined,
          title: 'В безопасном пункте',
          subtitle: 'SafePoint · 600 м · ежедневно до 22:00',
          color: BureauColors.green,
          background: BureauColors.greenSoft,
          trailing: BureauPill('РЕКОМЕНДУЕМ', color: BureauColors.green, background: BureauColors.greenSoft),
        ),
        const SizedBox(height: 10),
        const SettingRow(icon: Icons.people_outline_rounded, title: 'Личная встреча', subtitle: 'Выберите людное место и дневное время'),
        const SizedBox(height: 10),
        const SettingRow(icon: Icons.delivery_dining_outlined, title: 'Доставка', subtitle: 'После согласования стоимости и адреса'),
        const SizedBox(height: 16),
        const NoticeCard('Не переводите деньги за «подтверждение» и не сообщайте коды из SMS.'),
      ],
    );
  }

  Widget _qr(BuildContext context) {
    return Column(
      children: [
        const _QrPattern(),
        const SizedBox(height: 18),
        Text('BN-4829-7314', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 6),
        Text('Код действует 20 минут', style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: 22),
        const NoticeCard('Покажите QR только при фактическом получении вещи.'),
        const SizedBox(height: 14),
        const SettingRow(
          icon: Icons.storefront_outlined,
          title: 'SafePoint · Тверская, 18',
          subtitle: 'Сегодня · 18:30–19:00',
          color: BureauColors.green,
          background: BureauColors.greenSoft,
        ),
      ],
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.text, required this.time, this.outgoing = false});

  final String text;
  final String time;
  final bool outgoing;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: outgoing ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 300),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: outgoing ? BureauColors.blue : Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(19),
            topRight: const Radius.circular(19),
            bottomLeft: Radius.circular(outgoing ? 19 : 5),
            bottomRight: Radius.circular(outgoing ? 5 : 19),
          ),
          border: outgoing ? null : Border.all(color: BureauColors.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(text, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: outgoing ? Colors.white : BureauColors.navy)),
            const SizedBox(height: 6),
            Text(time, style: TextStyle(color: outgoing ? Colors.white70 : BureauColors.muted, fontSize: 8)),
          ],
        ),
      ),
    );
  }
}

class _QrPattern extends StatelessWidget {
  const _QrPattern();

  static const _active = {
    0, 1, 2, 4, 5, 6, 7, 9, 13, 14, 16, 17, 18, 20, 21, 23, 25, 27, 28, 29, 30, 32,
    33, 34, 36, 37, 39, 41, 42, 43, 44, 46, 48,
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 270,
      height: 270,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(28)),
      child: GridView.builder(
        physics: const NeverScrollableScrollPhysics(),
        itemCount: 49,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 7, crossAxisSpacing: 5, mainAxisSpacing: 5),
        itemBuilder: (_, index) => DecoratedBox(
          decoration: BoxDecoration(
            color: _active.contains(index) ? BureauColors.navy : Colors.transparent,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
    );
  }
}

class _CompletePage extends StatelessWidget {
  const _CompletePage({required this.onDone});

  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const Spacer(),
              Container(
                width: 150,
                height: 150,
                decoration: const BoxDecoration(color: BureauColors.greenSoft, shape: BoxShape.circle),
                child: const Icon(Icons.favorite_rounded, color: BureauColors.green, size: 72),
              ),
              const SizedBox(height: 30),
              Text('Вещь вернулась домой', style: Theme.of(context).textTheme.headlineSmall, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              Text(
                'Передача подтверждена обеими сторонами. Публикация закрыта, контакты снова скрыты.',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: BureauColors.slate),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              const BureauPill('ВОЗВРАЩЕНО', color: BureauColors.green, background: BureauColors.greenSoft, icon: Icons.check_rounded),
              const Spacer(),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: BureauColors.green),
                onPressed: onDone,
                child: const Text('На главную'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
