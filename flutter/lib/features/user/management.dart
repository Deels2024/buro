import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/api_widgets.dart';
import '../../core/production_widgets.dart';
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
  final _title = TextEditingController(), _description = TextEditingController(), _region = TextEditingController(), _storage = TextEditingController();
  String _category = 'other';
  JsonMap? _listing;
  Object? _error;
  List<JsonMap> _media = [];
  bool _started = false, _uploading = false;
  BureauApiClient get api => AppScope.of(context, listen: false).api;
  @override
  void didChangeDependencies() { super.didChangeDependencies(); if (!_started) { _started = true; _load(); } }
  Future<void> _load() async {
    try {
      final item = await api.managedListing(widget.listingId);
      if (!mounted) return;
      _title.text = item['title'].toString(); _description.text = item['description'].toString();
      _region.text = item['public_region'].toString(); _storage.text = item['storage_code']?.toString() ?? '';
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
    if (_uploading) throw BureauApiException(409, 'Дождитесь загрузки фотографий');
    final body = <String,dynamic>{'title':_title.text.trim(), 'description':_description.text.trim(), 'category':_category, 'storage_code':_storage.text.trim(), 'media_ids':_media.map((m)=>m['id']).toList(), 'status':status};
    if (_region.text.trim() != _listing!['public_region']) body['location'] = {'region':_region.text.trim()};
    final updated = await api.updateListing(widget.listingId, body);
    if (!mounted) return;
    setState(() => _listing = updated);
    showApiSuccess(context, status == 'active' ? 'Сохранено и отправлено на модерацию' : 'Черновик сохранён');
  }
  @override
  void dispose() { for (final c in [_title,_description,_region,_storage]) { c.dispose(); } super.dispose(); }
  @override
  Widget build(BuildContext context) => BureauPage(title:'Моя публикация', child: _error != null ? Column(children:[NoticeCard(apiErrorText(_error!)),TextButton(onPressed:_load, child:const Text('Повторить'))]) : _listing == null ? const Center(child:CircularProgressIndicator()) : Column(crossAxisAlignment:CrossAxisAlignment.start, children:[
    Text('${stateLabel(_listing!['status'])} · ${stateLabel(_listing!['moderation_status'])}'),
    const SizedBox(height:16),
    if (_media.isNotEmpty) ...[
      PhotoGallery(media:_media),
      Wrap(children:[for (var i=0;i<_media.length;i++) TextButton(onPressed:()=>setState(()=>_media.removeAt(i)), child:Text('Удалить фото ${i+1}'))]),
    ],
    OutlinedButton.icon(onPressed:_uploading ? null : _photos, icon:const Icon(Icons.add_a_photo_outlined), label:Text(_uploading ? 'Загружаем…' : 'Добавить фотографии')),
    TextField(controller:_title,maxLength:180,decoration:const InputDecoration(labelText:'Название')),
    TextField(controller:_description,minLines:3,maxLines:8,maxLength:5000,decoration:const InputDecoration(labelText:'Описание без личных данных')),
    DropdownButtonFormField<String>(initialValue:_category, items:categoryLabels.entries.map((e)=>DropdownMenuItem(value:e.key,child:Text(e.value))).toList(),onChanged:(v)=>setState(()=>_category=v??'other'),decoration:const InputDecoration(labelText:'Категория')),
    TextField(controller:_region,decoration:const InputDecoration(labelText:'Город или район')),
    TextField(controller:_storage,decoration:const InputDecoration(labelText:'Место хранения — видно только вам и сотрудникам')),
    const SizedBox(height:20),
    if (!['closed','blocked'].contains(_listing!['status'])) ...[
      ApiButton(label:'Сохранить черновик',outlined:true,onPressed:()=>_save('draft')),
      const SizedBox(height:12), ApiButton(label:'Отправить на модерацию',onPressed:()=>_save('active')),
    ],
    if (_listing!['kind']=='lost') TextButton(onPressed:()=>pushPage(context,MatchFlowPage(listingId:widget.listingId,targetListing:_listing)),child:const Text('Посмотреть совпадения')),
    const NoticeCard('Изменения опубликованной карточки проходят повторную проверку. Находке нужна фотография; пропажу можно описать без неё.'),
  ]));
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
      Text(listing['title'].toString(),style:Theme.of(context).textTheme.headlineSmall),Text(stateLabel(claim['status'])),
      PhotoGallery(media:(listing['media'] as List).map((m)=>Map<String,dynamic>.from(m as Map)).toList()),
      const SectionTitle('Скрытые признаки находки'),Text((data['hidden_features'] as List).join(', ').isEmpty?'Не указаны':(data['hidden_features'] as List).join(', ')),
      const SectionTitle('Ответы заявителя'),for(final e in answers.entries)Padding(padding:const EdgeInsets.only(bottom:12),child:Text('${e.key}\n${e.value}')),
      const SectionTitle('Доказательства'),
      if((data['evidence'] as List).isEmpty)const NoticeCard('Медиа-доказательства не приложены. Оцените ответы и при необходимости запросите уточнение.'),
      for(final raw in data['evidence'] as List) ...[
        Text('${raw['evidence_type']} · ${stateLabel(raw['status'])}'),Text(raw['note']?.toString()??''),
        if(raw['media'] is Map)PhotoGallery(media:[Map<String,dynamic>.from(raw['media'] as Map)]),const SizedBox(height:12),
      ],
      const NoticeCard('Автоматическая оценка риска — подсказка. Сравните реальные признаки и доказательства перед решением.'),
      if(['under_review','needs_more_info'].contains(claim['status'])) ...[
        TextField(controller:_reason,minLines:2,maxLines:5,decoration:const InputDecoration(labelText:'Причина решения или вопрос заявителю')),
        const SizedBox(height:12),ApiButton(label:'Подтвердить владельца',onPressed:()=>_decide('approved')),
        const SizedBox(height:8),ApiButton(label:'Запросить уточнение',outlined:true,onPressed:()=>_decide('needs_more_info')),
        const SizedBox(height:8),ApiButton(label:'Отклонить заявление',outlined:true,onPressed:()=>_decide('rejected')),
      ],
      TextButton.icon(onPressed:()=>pushPage(context,Scaffold(appBar:AppBar(title:const Text('Чат по заявлению')),body:Padding(padding:const EdgeInsets.all(16),child:ClaimChat(claimId:widget.claimId)))),icon:const Icon(Icons.chat_outlined),label:const Text('Открыть чат')),
      if(claim['status']=='approved') ...[
        const SectionTitle('Передача вещи'),
        if (_contact?['unlocked'] == true) SelectableText('Телефон владельца: ${_contact?['claimant_phone'] ?? ''}'),
        ApiButton(label:'Разрешить обмен телефонами',outlined:true,onPressed:()async{final c=await api.setContactConsent(widget.claimId,true);if(context.mounted){setState(()=>_contact=c);showApiSuccess(context,c['unlocked']==true?'Телефон владельца открыт':'Ваше согласие сохранено. Ожидаем владельца.');}}),
        TextButton.icon(onPressed:()async{final code=await Navigator.push<String>(context,MaterialPageRoute(builder:(_)=>const ScanHandoverPage()));if(code!=null&&mounted)setState(()=>_token.text=code);},icon:const Icon(Icons.qr_code_scanner),label:const Text('Сканировать QR владельца')),
        TextField(controller:_token,decoration:const InputDecoration(labelText:'Код передачи')),const SizedBox(height:12),
        ApiButton(label:'Подтвердить передачу владельцу',onPressed:()async{_handover=await api.scanHandover(_token.text.trim(),claimId:widget.claimId);if(context.mounted){showApiSuccess(context,_handover!['completed_at']!=null?'Возврат завершён':'Вы подтвердили передачу. Ожидаем владельца.');_refresh();}}),
      ],
    ]);
  }));
}
