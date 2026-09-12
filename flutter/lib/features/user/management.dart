import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';
import '../../core/api_widgets.dart';
import '../../core/location_editor.dart';
import '../../core/production_widgets.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../data/app_controller.dart';
import '../../data/bureau_api_client.dart';
import 'match_flow.dart';

class EditListingPage extends StatefulWidget {
  const EditListingPage({super.key, required this.listingId});
  final String listingId;
  @override
  State<EditListingPage> createState() => _EditListingPageState();
}
class _EditListingPageState extends State<EditListingPage> {
  final _title = TextEditingController(), _description = TextEditingController(), _region = TextEditingController(),
      _address = TextEditingController(), _storage = TextEditingController();
  String _category = 'other';
  JsonMap? _listing;
  Object? _error;
  List<JsonMap> _media = [];
  bool _started = false, _uploading = false;
  bool _locationChanged = false, _resolvingLocation = false, _saving = false;
  LatLng? _point;
  BureauApiClient get api => AppScope.of(context, listen: false).api;
  @override
  void didChangeDependencies() { super.didChangeDependencies(); if (!_started) { _started = true; _load(); } }
  Future<void> _load() async {
    try {
      final item = await api.managedListing(widget.listingId);
      if (!mounted) return;
      _title.text = item['title'].toString(); _description.text = item['description'].toString();
      _region.text = item['public_region'].toString(); _storage.text = item['storage_code']?.toString() ?? '';
      final location = item['location'] as Map?;
      _address.text = location?['exact_address']?.toString() ?? '';
      final latitude = location?['latitude'], longitude = location?['longitude'];
      _point = latitude is num && longitude is num ? LatLng(latitude.toDouble(), longitude.toDouble()) : null;
      _locationChanged = false;
      _category = categoryLabels.containsKey(item['category']) ? item['category'].toString() : 'other';
      setState(() { _listing = item; _media = (item['media'] as List).map((m) => Map<String, dynamic>.from(m as Map)).toList(); _error = null; });
    } catch (e) { if (mounted) setState(() => _error = e); }
  }
  Future<void> _photos() async {
    if (_media.length >= 9 || _uploading) return;
    setState(() => _uploading = true);
    try {
      final files = await ImagePicker().pickMultiImage(maxWidth: 2048, imageQuality: 88);
      for (final file in files.take(9-_media.length)) {
        final uploaded = await api.uploadMedia(bytes: await file.readAsBytes(), filename: file.name, mimeType: file.mimeType ?? (file.name.toLowerCase().endsWith('.png') ? 'image/png' : 'image/jpeg'), purpose: 'listing');
        if (!mounted) return;
        setState(() => _media.add({'id':uploaded.id, 'download_url':uploaded.url, 'mime_type':uploaded.mimeType, 'status':'processing'}));
      }
    } catch (e) { if (mounted) showApiError(context,e); }
    finally { if (mounted) setState(() => _uploading = false); }
  }
  Future<void> _save(String status) async {
    if (_saving) return;
    if (_uploading) throw BureauApiException(409, 'Дождитесь загрузки фотографий');
    if (_resolvingLocation) throw BureauApiException(409, 'Дождитесь определения адреса');
    if (_region.text.trim().length < 2) throw BureauApiException(422, 'Укажите город или населённый пункт');
    final body = <String,dynamic>{'title':_title.text.trim(), 'description':_description.text.trim(), 'category':_category, 'storage_code':_storage.text.trim(), 'media_ids':_media.map((m)=>m['id']).toList(), 'status':status};
    if (_locationChanged) {
      body['location'] = {
        'region': _region.text.trim(),
        'latitude': _point?.latitude,
        'longitude': _point?.longitude,
        'exact_address': _address.text.trim().isEmpty ? null : _address.text.trim(),
      };
    }
    setState(() => _saving = true);
    try {
      final updated = await api.updateListing(widget.listingId, body);
      if (!mounted) return;
      setState(() { _listing = updated; _locationChanged = false; });
      showApiSuccess(context, status == 'active' ? 'Сохранено и отправлено на модерацию' : 'Черновик сохранён');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
  @override
  void dispose() { for (final c in [_title,_description,_region,_address,_storage]) { c.dispose(); } super.dispose(); }
  @override
  Widget build(BuildContext context) => BureauPage(
    title: 'Моя публикация',
    child: AbsorbPointer(absorbing: _saving, child: _error != null
        ? Column(children: [
            NoticeCard(apiErrorText(_error!)),
            TextButton(onPressed: _load, child: const Text('Повторить')),
          ])
        : _listing == null
            ? const Center(child: CircularProgressIndicator())
            : ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 600),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '${stateLabel(_listing!['status'])} · ${stateLabel(_listing!['moderation_status'])}',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 20),
                    Text('Фотографии', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 12),
                    if (_media.isNotEmpty) ...[
                      for (var i = 0; i < _media.length; i++) ...[
                        _ListingPhotoCard(
                          media: _media[i],
                          number: i + 1,
                          onRemove: () => setState(() => _media.removeAt(i)),
                        ),
                        const SizedBox(height: 12),
                      ],
                    ],
                    OutlinedButton.icon(
                      onPressed: _uploading || _media.length >= 9 ? null : _photos,
                      icon: const Icon(Icons.add_a_photo_outlined),
                      label: Text(_uploading ? 'Загружаем…' : 'Добавить фотографии'),
                    ),
                    const SizedBox(height: 28),
                    BureauField(
                      label: 'Название',
                      child: TextField(
                        controller: _title,
                        minLines: 1,
                        maxLines: 2,
                        maxLength: 180,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(hintText: 'Что это за вещь?'),
                      ),
                    ),
                    const SizedBox(height: 20),
                    BureauField(
                      label: 'Описание без личных данных',
                      child: TextField(
                        controller: _description,
                        minLines: 3,
                        maxLines: 8,
                        maxLength: 5000,
                        decoration: const InputDecoration(hintText: 'Цвет, бренд и отличительные признаки'),
                      ),
                    ),
                    const SizedBox(height: 20),
                    BureauField(
                      label: 'Категория',
                      child: DropdownButtonFormField<String>(
                        initialValue: _category,
                        isExpanded: true,
                        items: categoryLabels.entries.map((e) => DropdownMenuItem(
                          value: e.key,
                          child: Text(e.value, maxLines: 1, overflow: TextOverflow.ellipsis),
                        )).toList(),
                        onChanged: (v) => setState(() => _category = v ?? 'other'),
                        decoration: const InputDecoration(),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(_listing!['kind'] == 'lost' ? 'Место пропажи' : 'Место хранения',
                      style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 12),
                    LocationEditor(
                      region: _region, address: _address, selected: _point,
                      onPoint: (point) => setState(() { _point = point; _locationChanged = true; }),
                      onResolvingChanged: (value) => setState(() => _resolvingLocation = value),
                    ),
                    const SizedBox(height: 12),
                    const Text('Точный адрес виден только вам и сотрудникам. Публичная точка округляется.'),
                    if (_listing!['organization_id'] != null || _storage.text.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      BureauField(
                        label: 'Код ячейки хранения',
                        child: TextField(
                          controller: _storage,
                          maxLength: 80,
                          decoration: const InputDecoration(hintText: 'Номер ячейки или внутренний код'),
                        ),
                      ),
                    ],
                    const SizedBox(height: 28),
                    if (!['closed', 'blocked'].contains(_listing!['status'])) ...[
                      ApiButton(label: 'Сохранить черновик', outlined: true, onPressed: () => _save('draft')),
                      const SizedBox(height: 12),
                      ApiButton(label: 'Отправить на модерацию', onPressed: () => _save('active')),
                      const SizedBox(height: 20),
                    ],
                    if (_listing!['kind'] == 'lost') ...[
                      TextButton(
                        onPressed: () => pushPage(context, MatchFlowPage(listingId: widget.listingId, targetListing: _listing)),
                        child: const Text('Посмотреть совпадения'),
                      ),
                      const SizedBox(height: 12),
                    ],
                    const NoticeCard('Изменения опубликованной карточки проходят повторную проверку. Находке нужна фотография; пропажу можно описать без неё.'),
                  ],
                ),
              )),
  );
}

class _ListingPhotoCard extends StatelessWidget {
  const _ListingPhotoCard({required this.media, required this.number, required this.onRemove});
  final JsonMap media;
  final int number;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final url = media['download_url']?.toString();
    final isImage = url != null && media['mime_type'].toString().startsWith('image/');
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AspectRatio(
            aspectRatio: 16 / 10,
            child: isImage
                ? InkWell(
                    onTap: () => showDialog<void>(context: context, builder: (_) => Dialog(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Align(alignment: Alignment.topRight, child: IconButton(
                          tooltip: 'Закрыть фото', icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(context),
                        )),
                        Flexible(child: InteractiveViewer(child: Image.network(url, fit: BoxFit.contain))),
                      ]),
                    )),
                    child: Image.network(
                      url,
                      fit: BoxFit.contain,
                      errorBuilder: (_, error, stack) => const Center(child: Text('Не удалось загрузить фото')),
                    ),
                  )
                : const Center(child: Icon(Icons.insert_drive_file_outlined, size: 40)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 4, 6, 4),
            child: Row(children: [
              Expanded(child: Text('Фото $number', style: Theme.of(context).textTheme.bodyMedium)),
              IconButton(
                tooltip: 'Удалить фото $number',
                onPressed: onRemove,
                icon: const Icon(Icons.delete_outline, color: BureauColors.red),
              ),
            ]),
          ),
          if (media['status'] != 'ready')
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
              child: Text(stateLabel(media['status']), style: Theme.of(context).textTheme.bodyMedium),
            ),
        ],
      ),
    );
  }
}

class ClaimReviewPage extends StatefulWidget {
  const ClaimReviewPage({super.key,required this.claimId});
  final String claimId;
  @override
  State<ClaimReviewPage> createState()=>_ClaimReviewPageState();
}
class _ClaimReviewPageState extends State<ClaimReviewPage> {
  final _reason=TextEditingController(), _token=TextEditingController();
  Future<JsonMap>? _future;
  JsonMap? _handover;
  JsonMap? _contact;
  BureauApiClient get api=>AppScope.of(context,listen:false).api;
  @override
  void didChangeDependencies(){super.didChangeDependencies();_future??=_load();}
  Future<JsonMap> _load() async {
    final data = await api.reviewClaim(widget.claimId);
    _contact = data['claim']['status'] == 'approved' ? await api.contacts(widget.claimId) : null;
    return data;
  }
  void _refresh()=>setState(()=>_future=_load());
  Future<void> _decide(String decision) async {await api.decideClaim(widget.claimId,decision,_reason.text.trim());if(mounted){showApiSuccess(context,'Решение сохранено');_refresh();}}
  @override
  void dispose(){_reason.dispose();_token.dispose();super.dispose();}
  @override
  Widget build(BuildContext context)=>BureauPage(title:'Проверка владельца',actions:[IconButton(onPressed:_refresh,tooltip:'Обновить',icon:const Icon(Icons.refresh))],child:FutureBuilder<JsonMap>(future:_future,builder:(context,snapshot){
    if(snapshot.hasError)return NoticeCard(apiErrorText(snapshot.error!));
    if(!snapshot.hasData)return const Center(child:CircularProgressIndicator());
    final data=snapshot.data!, claim=Map<String,dynamic>.from(data['claim'] as Map), listing=Map<String,dynamic>.from(data['listing'] as Map);
    final answers=Map<String,dynamic>.from(data['answers'] as Map);
    return Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Text(listing['title'].toString(),style:Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 8),
      Text(stateLabel(claim['status'])),
      const SizedBox(height: 16),
      PhotoGallery(media:(listing['media'] as List).map((m)=>Map<String,dynamic>.from(m as Map)).toList()),
      const SectionTitle('Скрытые признаки находки'),Text((data['hidden_features'] as List).join(', ').isEmpty?'Не указаны':(data['hidden_features'] as List).join(', ')),
      const SectionTitle('Ответы заявителя'),for(final e in answers.entries)Padding(padding:const EdgeInsets.only(bottom:12),child:Text('${e.key}\n${e.value}')),
      const SectionTitle('Доказательства'),
      if((data['evidence'] as List).isEmpty)const NoticeCard('Медиа-доказательства не приложены. Оцените ответы и при необходимости запросите уточнение.'),
      for(final raw in data['evidence'] as List) ...[
        Text('${raw['evidence_type']} · ${stateLabel(raw['status'])}'),
        if ((raw['note']?.toString() ?? '').isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(raw['note'].toString()),
        ],
        const SizedBox(height: 12),
        if(raw['media'] is Map)PhotoGallery(media:[Map<String,dynamic>.from(raw['media'] as Map)]),const SizedBox(height:12),
      ],
      const SizedBox(height: 16),
      const NoticeCard('Автоматическая оценка риска — подсказка. Сравните реальные признаки и доказательства перед решением.'),
      if(['under_review','needs_more_info'].contains(claim['status'])) ...[
        const SizedBox(height: 20),
        BureauField(label: 'Причина решения или вопрос заявителю',
          child: TextField(controller:_reason,minLines:2,maxLines:5)),
        const SizedBox(height:12),ApiButton(label:'Подтвердить владельца',onPressed:()=>_decide('approved')),
        const SizedBox(height:8),ApiButton(label:'Запросить уточнение',outlined:true,onPressed:()=>_decide('needs_more_info')),
        const SizedBox(height:8),ApiButton(label:'Отклонить заявление',outlined:true,onPressed:()=>_decide('rejected')),
      ],
      const SizedBox(height: 12),
      TextButton.icon(onPressed:()=>pushPage(context,Scaffold(appBar:AppBar(title:const Text('Чат по заявлению')),body:Padding(padding:const EdgeInsets.all(16),child:ClaimChat(claimId:widget.claimId)))),icon:const Icon(Icons.chat_outlined),label:const Text('Открыть чат')),
      if(claim['status']=='approved') ...[
        const SectionTitle('Передача вещи'),
        if (_contact?['unlocked'] == true) ...[
          SelectableText('Телефон владельца: ${_contact?['claimant_phone'] ?? ''}'),
          const SizedBox(height: 16),
        ],
        ApiButton(label:'Разрешить обмен телефонами',outlined:true,onPressed:()async{final c=await api.setContactConsent(widget.claimId,true);if(context.mounted){setState(()=>_contact=c);showApiSuccess(context,c['unlocked']==true?'Телефон владельца открыт':'Ваше согласие сохранено. Ожидаем владельца.');}}),
        const SizedBox(height: 12),
        TextButton.icon(onPressed:()async{final code=await Navigator.push<String>(context,MaterialPageRoute(builder:(_)=>const ScanHandoverPage()));if(code!=null&&mounted)setState(()=>_token.text=code);},icon:const Icon(Icons.qr_code_scanner),label:const Text('Сканировать QR владельца')),
        const SizedBox(height: 20),
        BureauField(label: 'Код передачи', child: TextField(controller:_token)),
        const SizedBox(height: 20),
        ApiButton(label:'Подтвердить передачу владельцу',onPressed:()async{_handover=await api.scanHandover(_token.text.trim(),claimId:widget.claimId);if(context.mounted){showApiSuccess(context,_handover!['completed_at']!=null?'Возврат завершён':'Вы подтвердили передачу. Ожидаем владельца.');_refresh();}}),
      ],
    ]);
  }));
}
