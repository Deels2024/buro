import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/api_widgets.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../data/app_controller.dart';
import '../../data/bureau_api_client.dart';
import 'match_flow.dart';
import 'user_app.dart';

class CreateFlowPage extends StatefulWidget {
  const CreateFlowPage({
    super.key,
    required this.initialFound,
    this.organizationId,
    this.branchId,
    this.initialStorageCode,
  });

  final bool initialFound;
  final String? organizationId;
  final String? branchId;
  final String? initialStorageCode;

  @override
  State<CreateFlowPage> createState() => _CreateFlowPageState();
}

class _CreateFlowPageState extends State<CreateFlowPage> {
  int _step = 0;
  late bool _found = widget.initialFound;
  final _title = TextEditingController();
  final _description = TextEditingController();
  final _category = TextEditingController();
  final _features = TextEditingController();
  final _hidden = TextEditingController();
  final _region = TextEditingController();
  final _address = TextEditingController();
  late final TextEditingController _storage = TextEditingController(
    text: widget.initialStorageCode,
  );
  DateTime _eventAt = DateTime.now();
  final List<UploadedMedia> _media = [];
  final List<XFile> _files = [];
  bool _uploading = false;
  bool _describing = false;

  Color get _accent => _found ? BureauColors.green : BureauColors.blue;
  Color get _soft => _found ? BureauColors.greenSoft : BureauColors.blueSoft;

  @override
  void dispose() {
    for (final controller in [
      _title,
      _description,
      _category,
      _features,
      _hidden,
      _region,
      _address,
      _storage,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _pickImages() async {
    final files = await ImagePicker().pickMultiImage(
      imageQuality: 88,
      maxWidth: 2048,
      limit: 8 - _files.length,
    );
    if (files.isEmpty || !mounted) return;
    setState(() => _uploading = true);
    final api = AppScope.of(context, listen: false).api;
    try {
      for (final file in files) {
        final bytes = await file.readAsBytes();
        final mime =
            file.mimeType ??
            (file.name.toLowerCase().endsWith('.png')
                ? 'image/png'
                : 'image/jpeg');
        final media = await api.uploadMedia(
          bytes: bytes,
          filename: file.name,
          mimeType: mime,
          purpose: 'listing',
        );
        _files.add(file);
        _media.add(media);
      }
      if (_media.isNotEmpty && _title.text.trim().isEmpty) await _describe();
    } catch (error) {
      if (mounted) showApiError(context, error);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _describe() async {
    if (_media.isEmpty || _describing) return;
    setState(() => _describing = true);
    try {
      final result = await AppScope.of(
        context,
        listen: false,
      ).api.describeMedia(_media.first.id, _found ? 'found' : 'lost');
      _title.text = result['title']?.toString() ?? _title.text;
      _description.text =
          result['description']?.toString() ?? _description.text;
      _category.text = result['category']?.toString() ?? _category.text;
      _features.text = (result['distinctive_features'] as List? ?? const [])
          .join(', ');
      _hidden.text = (result['sensitive_details_to_hide'] as List? ?? const [])
          .join(', ');
      if (mounted) showApiSuccess(context, 'ИИ подготовил описание');
    } catch (error) {
      if (mounted) showApiError(context, error);
    } finally {
      if (mounted) setState(() => _describing = false);
    }
  }

  bool _validateStep() {
    if (_step == 1 &&
        (_title.text.trim().length < 3 ||
            _description.text.trim().length < 10 ||
            _category.text.trim().length < 2)) {
      showApiError(
        context,
        BureauApiException(
          422,
          'Заполните название, категорию и описание не короче 10 символов',
        ),
      );
      return false;
    }
    if (_step == 2 && _region.text.trim().length < 2) {
      showApiError(
        context,
        BureauApiException(422, 'Укажите регион или город'),
      );
      return false;
    }
    return true;
  }

  Future<void> _next() async {
    if (!_validateStep()) return;
    if (_step < 3) {
      setState(() => _step++);
      return;
    }
    await _submit();
  }

  Future<void> _submit() async {
    final publish = _media.isNotEmpty;
    final body = <String, dynamic>{
      'kind': _found ? 'found' : 'lost',
      'title': _title.text.trim(),
      'description': _description.text.trim(),
      'category': _category.text.trim(),
      'tags': _split(_features.text),
      'public_features': _split(_features.text),
      'hidden_features': _split(_hidden.text),
      'event_at': _eventAt.toUtc().toIso8601String(),
      'location': {
        'region': _region.text.trim(),
        'latitude': null,
        'longitude': null,
        'exact_address': _address.text.trim().isEmpty
            ? null
            : _address.text.trim(),
      },
      'media_ids': _media.map((item) => item.id).toList(),
      'organization_id': widget.organizationId,
      'branch_id': widget.branchId,
      'storage_code': _storage.text.trim().isEmpty
          ? null
          : _storage.text.trim(),
      'publish': publish,
    };
    final listing = await AppScope.of(
      context,
      listen: false,
    ).api.createListing(body);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) =>
            PublicationSuccessPage(listing: listing, published: publish),
      ),
    );
  }

  List<String> _split(String value) => value
      .split(',')
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toList();

  @override
  Widget build(BuildContext context) {
    final titles = _found
        ? ['Фото находки', 'Описание находки', 'Место хранения', 'Предпросмотр']
        : ['Фото пропажи', 'Описание пропажи', 'Место и время', 'Предпросмотр'];
    return BureauPage(
      title: titles[_step],
      subtitle: 'Шаг ${_step + 1} из 4 · ${_found ? 'находка' : 'пропажа'}',
      actions: [
        TextButton(
          onPressed: () => setState(() => _found = !_found),
          child: Text(_found ? 'Это пропажа' : 'Это находка'),
        ),
      ],
      bottom: ApiButton(
        label: _step == 3
            ? (_media.isEmpty ? 'Сохранить черновик' : 'Опубликовать')
            : 'Продолжить',
        backgroundColor: _accent,
        onPressed: _next,
      ),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        child: KeyedSubtree(key: ValueKey(_step), child: _body(context)),
      ),
    );
  }

  Widget _body(BuildContext context) => switch (_step) {
    0 => _mediaStep(context),
    1 => _detailsStep(context),
    2 => _locationStep(context),
    _ => _previewStep(context),
  };

  Widget _mediaStep(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        _found
            ? 'Покажите вещь с разных сторон'
            : 'Добавьте фото потерянной вещи',
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      const SizedBox(height: 8),
      Text(
        'До 8 фотографий. После загрузки ИИ предложит название, категорию и признаки.',
        style: Theme.of(
          context,
        ).textTheme.bodyLarge?.copyWith(color: BureauColors.slate),
      ),
      const SizedBox(height: 22),
      GestureDetector(
        onTap: _uploading ? null : _pickImages,
        child: Container(
          height: 280,
          width: double.infinity,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: _soft,
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: _accent),
          ),
          child: _files.isEmpty
              ? Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.add_a_photo_rounded, size: 54, color: _accent),
                    const SizedBox(height: 12),
                    Text(
                      'Камера или галерея',
                      style: TextStyle(
                        color: _accent,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                )
              : FutureBuilder(
                  future: _files.first.readAsBytes(),
                  builder: (context, snapshot) => snapshot.hasData
                      ? Image.memory(snapshot.data!, fit: BoxFit.cover)
                      : const Center(child: CircularProgressIndicator()),
                ),
        ),
      ),
      if (_uploading)
        const Padding(
          padding: EdgeInsets.all(18),
          child: LinearProgressIndicator(),
        ),
      if (_files.isNotEmpty) ...[
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (var index = 0; index < _files.length; index++)
              BureauPill(
                'Фото ${index + 1}',
                color: _accent,
                background: _soft,
              ),
          ],
        ),
        const SizedBox(height: 12),
        ApiButton(
          label: _describing ? 'ИИ анализирует…' : 'Обновить описание с ИИ',
          outlined: true,
          onPressed: _describe,
        ),
      ],
      const SizedBox(height: 18),
      NoticeCard(
        _found
            ? 'Не показывайте серийные номера публично — добавьте их как скрытый признак.'
            : 'Если фото нет, запись сохранится как черновик и её можно дополнить позже.',
        color: _accent,
        background: _soft,
        icon: Icons.shield_outlined,
      ),
    ],
  );

  Widget _detailsStep(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (_media.isNotEmpty)
        NoticeCard(
          'ИИ заполнил черновик. Проверьте данные перед продолжением.',
          color: _accent,
          background: _soft,
          icon: Icons.auto_awesome_rounded,
        ),
      const SectionTitle('Название'),
      TextField(
        controller: _title,
        decoration: const InputDecoration(hintText: 'Чёрный городской рюкзак'),
      ),
      const SectionTitle('Категория'),
      TextField(
        controller: _category,
        decoration: const InputDecoration(hintText: 'Сумки'),
      ),
      const SectionTitle('Описание'),
      TextField(
        controller: _description,
        maxLines: 5,
        decoration: const InputDecoration(
          hintText: 'Материал, цвет, состояние и заметные детали…',
        ),
      ),
      const SectionTitle('Публичные признаки'),
      TextField(
        controller: _features,
        maxLines: 2,
        decoration: const InputDecoration(
          hintText: 'чёрный, красная молния, два отделения',
        ),
      ),
      const SectionTitle('Скрытые признаки'),
      TextField(
        controller: _hidden,
        maxLines: 2,
        decoration: const InputDecoration(
          prefixIcon: Icon(Icons.lock_outline_rounded),
          hintText: 'Серийный номер, содержимое кармана…',
        ),
      ),
    ],
  );

  Widget _locationStep(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      TextField(
        controller: _region,
        decoration: const InputDecoration(
          prefixIcon: Icon(Icons.location_city_outlined),
          labelText: 'Город или регион',
        ),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _address,
        decoration: const InputDecoration(
          prefixIcon: Icon(Icons.location_on_outlined),
          labelText: 'Точное место (будет зашифровано)',
        ),
      ),
      const SizedBox(height: 12),
      SettingRow(
        icon: Icons.calendar_today_outlined,
        title: 'Дата события',
        subtitle:
            '${_eventAt.day.toString().padLeft(2, '0')}.${_eventAt.month.toString().padLeft(2, '0')}.${_eventAt.year}',
        onTap: () async {
          final value = await showDatePicker(
            context: context,
            firstDate: DateTime.now().subtract(const Duration(days: 3650)),
            lastDate: DateTime.now(),
            initialDate: _eventAt,
          );
          if (value != null) setState(() => _eventAt = value);
        },
      ),
      if (widget.organizationId != null) ...[
        const SectionTitle('Организация'),
        TextField(
          controller: _storage,
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.inventory_2_outlined),
            labelText: 'Код ячейки хранения',
          ),
        ),
      ],
      const SizedBox(height: 18),
      NoticeCard(
        'Публично показывается только регион и округлённая точка. Точный адрес хранится в зашифрованном виде.',
        color: _accent,
        background: _soft,
      ),
    ],
  );

  Widget _previewStep(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (_files.isNotEmpty)
        FutureBuilder(
          future: _files.first.readAsBytes(),
          builder: (context, snapshot) => Container(
            height: 240,
            width: double.infinity,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: _soft,
              borderRadius: BorderRadius.circular(24),
            ),
            child: snapshot.hasData
                ? Image.memory(snapshot.data!, fit: BoxFit.cover)
                : const Center(child: CircularProgressIndicator()),
          ),
        )
      else
        ItemArtwork(height: 240, color: _accent, background: _soft),
      const SizedBox(height: 14),
      BureauPill(
        _found ? 'НАХОДКА' : 'ПРОПАЖА',
        color: _accent,
        background: _soft,
      ),
      const SizedBox(height: 14),
      Text(_title.text, style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 8),
      Text(
        _description.text,
        style: Theme.of(
          context,
        ).textTheme.bodyLarge?.copyWith(color: BureauColors.slate),
      ),
      const SectionTitle('Место'),
      SettingRow(
        icon: Icons.location_on_outlined,
        title: _region.text,
        subtitle: _address.text.isEmpty
            ? 'Точная точка не указана'
            : 'Точная точка защищена',
      ),
      if (_media.isEmpty)
        const Padding(
          padding: EdgeInsets.only(top: 14),
          child: NoticeCard(
            'Без фотографии backend сохранит запись как черновик. Опубликовать её можно после добавления медиа.',
            color: BureauColors.amber,
            background: BureauColors.amberSoft,
          ),
        ),
    ],
  );
}

class PublicationSuccessPage extends StatelessWidget {
  const PublicationSuccessPage({
    super.key,
    required this.listing,
    required this.published,
  });
  final JsonMap listing;
  final bool published;

  @override
  Widget build(BuildContext context) => BureauPage(
    title: published ? 'Публикация создана' : 'Черновик сохранён',
    subtitle: listing['id']?.toString() ?? '',
    bottom: FilledButton(
      onPressed: () => Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute<void>(
          builder: (_) => const UserShell(initialIndex: 3),
        ),
        (_) => false,
      ),
      child: const Text('Открыть мои обращения'),
    ),
    child: Column(
      children: [
        Container(
          width: 140,
          height: 140,
          decoration: BoxDecoration(
            color: published ? BureauColors.greenSoft : BureauColors.amberSoft,
            shape: BoxShape.circle,
          ),
          child: Icon(
            published ? Icons.check_rounded : Icons.edit_note_rounded,
            size: 70,
            color: published ? BureauColors.green : BureauColors.amber,
          ),
        ),
        const SizedBox(height: 24),
        Text(
          listing['title']?.toString() ?? '',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 12),
        NoticeCard(
          published
              ? 'Backend запустил поиск совпадений. Новые варианты появятся в центре совпадений.'
              : 'Добавьте фотографию, затем переведите запись в активный статус.',
          color: published ? BureauColors.green : BureauColors.amber,
          background: published
              ? BureauColors.greenSoft
              : BureauColors.amberSoft,
        ),
        if (published && listing['kind'] == 'lost') ...[
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: () => pushPage(
              context,
              MatchFlowPage(listingId: listing['id'].toString()),
            ),
            icon: const Icon(Icons.auto_awesome_rounded),
            label: const Text('Проверить совпадения'),
          ),
        ],
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: () => pushPage(context, ItemDetailPage(listing: listing)),
          icon: const Icon(Icons.visibility_outlined),
          label: const Text('Открыть карточку'),
        ),
      ],
    ),
  );
}
