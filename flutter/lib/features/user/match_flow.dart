import 'dart:convert';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../core/api_widgets.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../core/production_widgets.dart';
import '../../data/app_controller.dart';
import '../../data/bureau_api_client.dart';
import 'user_app.dart';

class MatchFlowPage extends StatefulWidget {
  const MatchFlowPage({
    super.key,
    required this.listingId,
    this.claimId,
    this.targetListing,
  });

  final String listingId;
  final String? claimId;
  final JsonMap? targetListing;

  @override
  State<MatchFlowPage> createState() => _MatchFlowPageState();
}

class _MatchFlowPageState extends State<MatchFlowPage> {
  int _step = 0;
  bool _initialized = false;
  bool _loading = true;
  Object? _error;
  JsonMap? _sourceListing;
  List<JsonMap> _matches = const [];
  JsonMap? _selectedMatch;
  JsonMap? _claim;
  JsonMap? _contact;
  JsonMap? _handover;
  UploadedMedia? _evidence;
  final _answer1 = TextEditingController();
  final _answer2 = TextEditingController();
  final _answer3 = TextEditingController();
  final _handoverPlace = TextEditingController();
  String _handoverMethod = 'safe_point';

  static const _titles = [
    'Центр совпадений',
    'Сравнение совпадения',
    'Подтверждение владельца',
    'Контрольные вопросы',
    'Доказательства',
    'Проверка заявления',
    'Защищённый чат',
    'Согласие на контакты',
    'Способ передачи',
    'QR передачи',
    'Вещь возвращена',
  ];

  BureauApiClient get _api => AppScope.of(context, listen: false).api;

  bool get _qrNeedsRefresh {
    final token = _handover?['qr_token']?.toString();
    final expiry = DateTime.tryParse(_handover?['qr_expires_at']?.toString() ?? '');
    return token == null || token.isEmpty || expiry == null || !expiry.isAfter(DateTime.now());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _initialized = true;
      _initialize();
    }
  }

  @override
  void dispose() {
    for (final controller in [_answer1, _answer2, _answer3, _handoverPlace]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _initialize() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      _sourceListing =
          widget.targetListing ?? (widget.claimId != null ? await _api.claimListing(widget.claimId!) : await _api.listing(widget.listingId));
      if (widget.claimId != null) {
        _claim = await _api.claim(widget.claimId!);
        _step = _stepForStatus(_claim!['status']?.toString());
        if (_step >= 7) await _loadApprovedState();
      } else if (_sourceListing!['kind'] == 'lost') {
        _matches = await _api.matches(widget.listingId);
        if (_matches.isNotEmpty) _selectedMatch = _matches.first;
        _step = 0;
      } else {
        _step = 1;
      }
    } catch (error) {
      _error = error;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  int _stepForStatus(String? status) => switch (status) {
    'draft' => 3,
    'under_review' => 6,
    'needs_more_info' => 3,
    'approved' => 7,
    'completed' => 10,
    'rejected' => 5,
    _ => 2,
  };

  JsonMap get _claimListing {
    final candidate = _selectedMatch?['candidate'];
    if (candidate is Map) return Map<String, dynamic>.from(candidate);
    return _sourceListing!;
  }

  Future<void> _loadApprovedState() async {
    if (_claim == null) return;
    _contact = await _api.contacts(_claim!['id'].toString());
    try {
      _handover = await _api.handover(_claim!['id'].toString());
      if (_handover != null) {
        _step = _handover!['completed_at'] == null ? 9 : 10;
      }
    } on BureauApiException catch (error) {
      if (error.statusCode != 404) rethrow;
    }
  }

  Future<void> _next() async {
    switch (_step) {
      case 0:
        if (_selectedMatch == null) {
          await _api.rematch(widget.listingId);
          if (!mounted) return;
          showApiSuccess(context, 'Повторный поиск запущен');
          await _initialize();
          return;
        }
        setState(() => _step = 1);
        return;
      case 1:
        await _ensureClaim();
        setState(() => _step = 2);
        return;
      case 2:
        setState(() => _step = 3);
        return;
      case 3:
        if ([
          _answer1,
          _answer2,
          _answer3,
        ].any((item) => item.text.trim().isEmpty)) {
          throw BureauApiException(
            422,
            'Ответьте на все три контрольных вопроса',
          );
        }
        _claim = await _api.saveClaimAnswers(_claim!['id'].toString(), {
          'lining_color': _answer1.text.trim(),
          'hidden_contents': _answer2.text.trim(),
          'unique_mark': _answer3.text.trim(),
        });
        setState(() => _step = 4);
        return;
      case 4:
        if (_evidence != null) {
          _claim = await _api.addEvidence(
            _claim!['id'].toString(),
            _evidence!,
            'old_photo',
          );
        }
        setState(() => _step = 5);
        return;
      case 5:
        if (_claim!['status'] == 'rejected') {
          await _showAppeal();
          return;
        }
        _claim = await _api.submitClaim(_claim!['id'].toString());
        setState(() => _step = 6);
        return;
      case 6:
        _claim = await _api.claim(_claim!['id'].toString());
        final next = _stepForStatus(_claim!['status']?.toString());
        _step = next;
        if (next == 7) await _loadApprovedState();
        if (mounted) setState(() {});
        return;
      case 7:
        _contact = await _api.setContactConsent(_claim!['id'].toString(), true);
        setState(() => _step = 8);
        return;
      case 8:
        if (_handoverPlace.text.trim().length < 3) {
          throw BureauApiException(422, 'Укажите место передачи');
        }
        _handover = await _api.createHandover(
          _claim!['id'].toString(),
          _handoverMethod,
          _handoverPlace.text.trim(),
        );
        if (_qrNeedsRefresh) {
          _handover = await _api.regenerateHandover(_claim!['id'].toString());
        }
        setState(() => _step = 9);
        return;
      case 9:
        final token = _handover?['qr_token']?.toString();
        if (_qrNeedsRefresh) {
          _handover = await _api.regenerateHandover(_claim!['id'].toString());
          setState(() {});
          return;
        }
        _handover = {...await _api.scanHandover(token!, claimId: _claim!['id'].toString()), 'qr_token': token};
        if (_handover!['completed_at'] != null) {
          _claim = await _api.claim(_claim!['id'].toString());
          setState(() => _step = 10);
        } else {
          if (!mounted) return;
          showApiSuccess(
            context,
            'Ваша сторона подтверждена. Ожидаем вторую сторону.',
          );
          setState(() {});
        }
        return;
      default:
        Navigator.pop(context);
    }
  }

  Future<void> _ensureClaim() async {
    if (_claim != null) return;
    final listingId = _claimListing['kind'] == 'found'
        ? _claimListing['id'].toString()
        : widget.listingId;
    final matchId = _selectedMatch?['id']?.toString();
    _claim = await _api.createClaim(listingId, matchId: matchId);
  }

  Future<void> _pickEvidence() async {
    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 88,
      maxWidth: 2048,
    );
    if (file == null) return;
    final bytes = await file.readAsBytes();
    final mime =
        file.mimeType ??
        (file.name.toLowerCase().endsWith('.png') ? 'image/png' : 'image/jpeg');
    _evidence = await _api.uploadMedia(
      bytes: bytes,
      filename: file.name,
      mimeType: mime,
      purpose: 'evidence',
    );
    if (mounted) setState(() {});
  }

  Future<void> _showAppeal() async {
    final controller = TextEditingController();
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Обжаловать решение'),
        content: TextField(
          controller: controller,
          maxLines: 5,
          decoration: const InputDecoration(
            hintText: 'Почему решение нужно пересмотреть?',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Отправить'),
          ),
        ],
      ),
    );
    if (approved == true) {
      await _api.appealClaim(_claim!['id'].toString(), controller.text);
      if (mounted) showApiSuccess(context, 'Апелляция зарегистрирована');
    }
    controller.dispose();
  }

  String get _subtitle => switch (_step) {
    0 => '${_matches.length} возможных совпадений',
    1 => 'Сравните данные перед заявлением',
    2 => 'Безопасная проверка за несколько шагов',
    3 => 'Ответы хранятся в зашифрованном виде',
    4 => 'Добавьте то, что существовало до пропажи',
    5 => 'Проверьте данные перед отправкой',
    6 => 'Статус: ${_claim?['status'] ?? ''}',
    7 => 'Обе стороны должны дать согласие',
    8 => 'Выберите безопасный способ',
    9 => 'Обе стороны сканируют один код',
    _ => 'Передача подтверждена обеими сторонами',
  };

  String get _buttonLabel => switch (_step) {
    0 => _matches.isEmpty ? 'Запустить повторный поиск' : 'Сравнить совпадение',
    1 => 'Это может быть моё',
    2 => 'Начать подтверждение',
    3 => 'Сохранить ответы',
    4 => 'Продолжить',
    5 =>
      _claim?['status'] == 'rejected'
          ? 'Подать апелляцию'
          : 'Отправить заявление',
    6 => 'Обновить статус',
    7 => 'Разрешить открыть контакты',
    8 => 'Создать QR передачи',
    9 =>
      _qrNeedsRefresh ? 'Обновить QR' : 'Подтвердить получение',
    _ => 'Готово',
  };

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_error != null) {
      return BureauPage(
        title: 'Совпадения',
        subtitle: 'Не удалось загрузить сценарий',
        bottom: FilledButton(
          onPressed: _initialize,
          child: const Text('Повторить'),
        ),
        child: NoticeCard(
          apiErrorText(_error!),
          color: BureauColors.red,
          background: BureauColors.redSoft,
        ),
      );
    }
    return BureauPage(
      title: _titles[_step],
      subtitle: _subtitle,
      bottom: ApiButton(
        label: _buttonLabel,
        backgroundColor: _step >= 6 ? BureauColors.green : BureauColors.blue,
        onPressed: _next,
      ),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        child: KeyedSubtree(key: ValueKey(_step), child: _body(context)),
      ),
    );
  }

  Widget _body(BuildContext context) => switch (_step) {
    0 => _matchHub(context),
    1 => _compare(context),
    2 => _claimStart(context),
    3 => _questions(context),
    4 => _evidenceStep(context),
    5 => _review(context),
    6 => _chatAndStatus(context),
    7 => _consent(context),
    8 => _handoverStep(context),
    9 => _qr(context),
    _ => _complete(context),
  };

  Widget _matchHub(BuildContext context) {
    if (_matches.isEmpty) {
      return const Column(
        children: [
          Icon(Icons.search_off_rounded, size: 90, color: BureauColors.muted),
          SizedBox(height: 18),
          NoticeCard(
            'Совпадения ещё не рассчитаны. Запустите повторный поиск — worker обработает запись в фоне.',
          ),
        ],
      );
    }
    return Column(
      children: [
        for (final match in _matches) ...[
          _MatchCandidateCard(
            match: match,
            selected: match['id'] == _selectedMatch?['id'],
            onTap: () => setState(() => _selectedMatch = match),
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }

  Widget _compare(BuildContext context) {
    final listing = _claimListing;
    final factors = Map<String, dynamic>.from(
      _selectedMatch?['factors'] as Map? ?? const {},
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: _MiniListing(listing: _sourceListing!)),
            const SizedBox(width: 10),
            Expanded(child: _MiniListing(listing: listing)),
          ],
        ),
        const SectionTitle('Совпавшие признаки'),
        if (factors.isEmpty)
          const NoticeCard(
            'Для прямого заявления по находке оценка совпадения не требуется.',
          ),
        for (final factor in factors.entries) ...[
          Row(
            children: [
              const Icon(
                Icons.check_circle_rounded,
                color: BureauColors.green,
                size: 19,
              ),
              const SizedBox(width: 9),
              Expanded(child: Text(factor.key)),
              Text(
                '${(((factor.value as num?) ?? 0) * 100).round()}%',
                style: const TextStyle(
                  color: BureauColors.green,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
        ],
        if (factors.isNotEmpty)
          OutlinedButton(
            onPressed: () =>
                pushPage(context, MatchExplanationPage(factors: factors)),
            child: const Text('Подробное объяснение ИИ'),
          ),
        const SizedBox(height: 14),
        const NoticeCard(
          'ИИ помогает выбрать кандидата, но право собственности подтверждается отдельно.',
        ),
      ],
    );
  }

  Widget _claimStart(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _MiniListing(listing: _claimListing, large: true),
      const SectionTitle('Как проходит проверка'),
      ...const [
        (
          Icons.quiz_outlined,
          'Ответьте на вопросы',
          'О скрытых деталях, которых нет в публикации.',
        ),
        (
          Icons.photo_library_outlined,
          'Добавьте доказательство',
          'Старое фото, чек или упаковка — если есть.',
        ),
        (
          Icons.chat_bubble_outline_rounded,
          'Уточните детали в чате',
          'Контакты останутся скрыты до решения.',
        ),
      ].map(
        (entry) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: SettingRow(
            icon: entry.$1,
            title: entry.$2,
            subtitle: entry.$3,
          ),
        ),
      ),
      const NoticeCard(
        'Не сообщайте паспортные данные, коды из SMS и данные банковских карт.',
      ),
    ],
  );

  Widget _questions(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const BureauPill('3 КОНТРОЛЬНЫХ ВОПРОСА'),
      const SizedBox(height: 18),
      TextField(
        controller: _answer1,
        maxLines: 2,
        decoration: const InputDecoration(
          labelText: 'Какого цвета внутренняя часть?',
        ),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _answer2,
        maxLines: 2,
        decoration: const InputDecoration(labelText: 'Что находилось внутри?'),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _answer3,
        maxLines: 2,
        decoration: const InputDecoration(
          labelText: 'Какая уникальная метка или дефект?',
        ),
      ),
      const SizedBox(height: 14),
      const NoticeCard(
        'Ответы шифруются backend и доступны только проверяющей стороне.',
      ),
    ],
  );

  Widget _evidenceStep(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      GestureDetector(
        onTap: _pickEvidence,
        child: Container(
          height: 230,
          width: double.infinity,
          decoration: BoxDecoration(
            color: _evidence == null
                ? BureauColors.blueSoft
                : BureauColors.greenSoft,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: _evidence == null ? BureauColors.blue : BureauColors.green,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                _evidence == null
                    ? Icons.add_photo_alternate_outlined
                    : Icons.check_circle_rounded,
                color: _evidence == null
                    ? BureauColors.blue
                    : BureauColors.green,
                size: 54,
              ),
              const SizedBox(height: 10),
              Text(
                _evidence == null
                    ? 'Добавить старое фото'
                    : 'Доказательство загружено',
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 14),
      const NoticeCard(
        'Можно продолжить без документов. В этом случае backend повысит оценку риска и проверяющая сторона задаст больше вопросов.',
      ),
    ],
  );

  Widget _review(BuildContext context) {
    final rejected = _claim?['status'] == 'rejected';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (rejected)
          NoticeCard(
            _claim?['decision_reason']?.toString() ?? 'Заявление отклонено',
            color: BureauColors.red,
            background: BureauColors.redSoft,
            icon: Icons.gavel_rounded,
          )
        else ...[
          const SettingRow(
            icon: Icons.quiz_outlined,
            title: '3 ответа заполнены',
            subtitle: 'Скрытые признаки готовы к проверке',
          ),
          const SizedBox(height: 10),
          SettingRow(
            icon: Icons.photo_library_outlined,
            title: _evidence == null
                ? 'Без медиа-доказательства'
                : 'Старое фото добавлено',
            subtitle: _evidence == null
                ? 'Риск будет выше'
                : 'Файл сохранён в защищённом хранилище',
            color: _evidence == null ? BureauColors.amber : BureauColors.green,
            background: _evidence == null
                ? BureauColors.amberSoft
                : BureauColors.greenSoft,
          ),
          const SizedBox(height: 14),
          const NoticeCard(
            'После отправки заявление получит нашедший вещь или сотрудник организации. Контакты останутся скрыты.',
          ),
        ],
      ],
    );
  }

  Widget _chatAndStatus(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SettingRow(
        icon: Icons.hourglass_top_rounded,
        title: 'Статус: ${_claim?['status'] ?? ''}',
        subtitle:
            'Риск: ${(((_claim?['risk_score'] as num?) ?? 0) * 100).round()}%',
        color: BureauColors.amber,
        background: BureauColors.amberSoft,
      ),
      const SizedBox(height: 14),
      if (_claim != null)
        SizedBox(
          height: 430,
          child: ClaimChat(claimId: _claim!['id'].toString()),
        ),
      const SizedBox(height: 14),
      const NoticeCard(
        'Следующий шаг откроется после решения держателя вещи. Кнопка ниже обновляет статус с backend.',
      ),
    ],
  );

  Widget _consent(BuildContext context) => Column(
    children: [
      const Icon(Icons.lock_open_rounded, size: 90, color: BureauColors.green),
      const SizedBox(height: 18),
      Text(
        'Владелец подтверждён',
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      const SizedBox(height: 14),
      NoticeCard(
        _contact?['unlocked'] == true
            ? 'Обе стороны согласились. Контакты доступны.'
            : 'Ваш телефон откроется только после согласия второй стороны.',
        color: BureauColors.green,
        background: BureauColors.greenSoft,
      ),
      if (_contact?['unlocked'] == true) ...[
        const SizedBox(height: 14),
        SettingRow(
          icon: Icons.phone_outlined,
          title: _contact?['holder_phone']?.toString() ?? 'Контакт держателя',
          subtitle: 'Защищённое раскрытие',
        ),
      ],
    ],
  );

  Widget _handoverStep(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      DropdownButtonFormField<String>(
        initialValue: _handoverMethod,
        items: const [
          DropdownMenuItem(
            value: 'safe_point',
            child: Text('Безопасный пункт'),
          ),
          DropdownMenuItem(value: 'meeting', child: Text('Личная встреча')),
          DropdownMenuItem(value: 'delivery', child: Text('Доставка')),
        ],
        onChanged: (value) => _handoverMethod = value ?? 'safe_point',
        decoration: const InputDecoration(labelText: 'Способ передачи'),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _handoverPlace,
        maxLines: 3,
        decoration: const InputDecoration(
          prefixIcon: Icon(Icons.location_on_outlined),
          labelText: 'Место и детали передачи',
        ),
      ),
      const SizedBox(height: 14),
      const NoticeCard(
        'QR действует 20 минут. Для завершения его подтверждают обе стороны.',
      ),
    ],
  );

  Widget _qr(BuildContext context) {
    final token = _handover?['qr_token']?.toString();
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: BureauColors.green),
          ),
          child: _qrNeedsRefresh
              ? const Icon(
                  Icons.qr_code_rounded,
                  size: 180,
                  color: BureauColors.muted,
                )
              : QrImageView(
                  data: token!,
                  size: 220,
                  eyeStyle: const QrEyeStyle(
                    color: BureauColors.green,
                    eyeShape: QrEyeShape.square,
                  ),
                ),
        ),
        const SizedBox(height: 14),
        if (_qrNeedsRefresh) const NoticeCard('Обновите QR, чтобы продолжить передачу. Уже полученные подтверждения сохранятся.'),
        SettingRow(
          icon: Icons.schedule_rounded,
          title: 'Действует до ${_handover?['qr_expires_at'] ?? ''}',
          subtitle: _handover?['completed_at'] == null
              ? 'Ожидаются подтверждения обеих сторон'
              : 'Передача завершена',
        ),
        const SizedBox(height: 14),
        const NoticeCard(
          'Не отправляйте QR посторонним. Он подтверждает физическую передачу вещи.',
        ),
      ],
    );
  }

  Widget _complete(BuildContext context) => Column(
    children: [
      Container(
        width: 150,
        height: 150,
        decoration: const BoxDecoration(
          color: BureauColors.greenSoft,
          shape: BoxShape.circle,
        ),
        child: const Icon(
          Icons.favorite_rounded,
          color: BureauColors.green,
          size: 76,
        ),
      ),
      const SizedBox(height: 24),
      Text('Вещь возвращена', style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 12),
      const NoticeCard(
        'Обе стороны подтвердили передачу. Публикация закрыта; подтверждение сохранено в истории заявления.',
        color: BureauColors.green,
        background: BureauColors.greenSoft,
      ),
    ],
  );
}

class ClaimChat extends StatefulWidget {
  const ClaimChat({super.key, required this.claimId});
  final String claimId;
  @override
  State<ClaimChat> createState() => _ClaimChatState();
}

class _ClaimChatState extends State<ClaimChat> {
  final _message = TextEditingController();
  final List<JsonMap> _messages = [];
  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  String? _conversationId;
  Object? _error;
  bool _loading = true;
  bool _connecting = false, _sending = false;
  Timer? _poll;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_conversationId == null && _loading && !_connecting) _connect();
  }

  Future<void> _connect() async {
    _connecting = true;
    final api = AppScope.of(context, listen: false).api;
    try {
      final conversation = await api.claimConversation(widget.claimId);
      _conversationId = conversation['conversation_id'].toString();
      _messages.addAll(await api.chatMessages(_conversationId!));
      _poll ??= Timer.periodic(const Duration(seconds: 8), (_) async {
        if (!mounted || _conversationId == null) return;
        try {
          final fresh = await api.chatMessages(_conversationId!);
          if (mounted) setState(() { for (final m in fresh) { if (!_messages.any((old) => old['id'] == m['id'])) _messages.add(m); } });
        } catch (_) { /* The next poll retries without discarding the conversation. */ }
      });
      _channel = await api.connectChat(_conversationId!);
      _subscription = _channel!.stream.listen((event) {
        try {
          final decoded = event is String ? jsonDecode(event) : event;
          final map = decoded is Map ? Map<String, dynamic>.from(decoded) : null;
          if (map != null &&
              map['id'] != null &&
              !_messages.any((item) => item['id'] == map['id'])) {
            if (mounted) setState(() => _messages.add(map));
          }
        } catch (_) {}
      }, onError: (Object error) { /* HTTP polling keeps the chat available. */ });
    } catch (error) {
      if (_conversationId == null) _error = error;
    } finally {
      _connecting = false;
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _send() async {
    final text = _message.text.trim();
    if (text.isEmpty || _conversationId == null || _sending) return;
    setState(() => _sending = true);
    try {
      final sent = await AppScope.of(
        context,
        listen: false,
      ).api.sendChatMessage(_conversationId!, text);
      _message.clear();
      if (mounted && !_messages.any((item) => item['id'] == sent['id'])) {
        setState(() => _messages.add(sent));
      }
    } catch (error) {
      if (mounted) showApiError(context, error);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    _subscription?.cancel();
    _channel?.sink.close();
    _message.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return NoticeCard(
        apiErrorText(_error!),
        color: BureauColors.red,
        background: BureauColors.redSoft,
      );
    }
    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            itemCount: _messages.length,
            itemBuilder: (context, index) {
              final item = _messages[index];
              return Align(
                alignment: item['sender_id'] == AppScope.of(context).currentUser?['id'] ? Alignment.centerRight : Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: SoftCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(item['body']?.toString() ?? ''), Text(item['created_at']?.toString().substring(11,16) ?? '', style: Theme.of(context).textTheme.bodySmall)])),
                ),
              );
            },
          ),
        ),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _message,
                decoration: const InputDecoration(hintText: 'Сообщение…'),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: _sending ? null : _send,
              icon: const Icon(Icons.send_rounded),
            ),
          ],
        ),
      ],
    );
  }
}

class _MatchCandidateCard extends StatelessWidget {
  const _MatchCandidateCard({
    required this.match,
    required this.selected,
    required this.onTap,
  });
  final JsonMap match;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final candidate = Map<String, dynamic>.from(match['candidate'] as Map);
    final score = ((match['score'] as num?)?.toDouble() ?? 0);
    return SoftCard(
      onTap: onTap,
      color: selected ? BureauColors.greenSoft : Colors.white,
      borderColor: selected ? BureauColors.green : BureauColors.line,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              BureauPill(
                selected ? 'ВЫБРАНО' : 'КАНДИДАТ',
                color: BureauColors.green,
                background: Colors.white,
              ),
              Text(
                '${matchPercent(score)}%',
                style: const TextStyle(
                  color: BureauColors.green,
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            candidate['title']?.toString() ?? '',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 5),
          Text(
            '${candidate['public_region'] ?? ''} · ${candidate['category'] ?? ''}',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}

class _MiniListing extends StatelessWidget {
  const _MiniListing({required this.listing, this.large = false});
  final JsonMap listing;
  final bool large;
  @override
  Widget build(BuildContext context) {
    final found = listing['kind'] == 'found';
    final media = listing['media'] as List? ?? const [];
    final url = media.isEmpty
        ? null
        : (media.first as Map)['download_url']?.toString();
    return SoftCard(
      color: found ? BureauColors.greenSoft : BureauColors.blueSoft,
      borderColor: found ? BureauColors.greenSoft : BureauColors.blueSoft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: large ? 190 : 120,
            width: double.infinity,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
            ),
            child: url == null
                ? Icon(
                    found
                        ? Icons.volunteer_activism_rounded
                        : Icons.search_off_rounded,
                    color: found ? BureauColors.green : BureauColors.blue,
                    size: 54,
                  )
                : Image.network(url, fit: BoxFit.cover),
          ),
          const SizedBox(height: 10),
          Text(
            listing['title']?.toString() ?? '',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            listing['public_region']?.toString() ?? '',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(fontSize: 9),
          ),
        ],
      ),
    );
  }
}
