import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../data/app_controller.dart';
import 'yandex_map.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/bureau_api_client.dart';
import 'widgets.dart';

const categoryLabels = <String, String>{
  'bags': 'Сумки и рюкзаки', 'documents': 'Документы', 'keys': 'Ключи',
  'electronics': 'Электроника', 'clothing': 'Одежда', 'jewelry': 'Украшения',
  'pets': 'Животные', 'toys': 'Игрушки', 'sport': 'Спорт', 'other': 'Другое',
};
const stateLabels = <String, String>{
  'draft':'Черновик', 'active':'Опубликовано', 'pending':'На модерации',
  'approved':'Подтверждено', 'auto_approved':'Подтверждено', 'under_review':'На проверке',
  'needs_more_info':'Нужны уточнения', 'rejected':'Отклонено', 'closed':'Закрыто',
  'completed':'Вещь возвращена', 'paused':'Приостановлено', 'blocked':'Заблокировано',
  'changes_requested':'Нужны исправления', 'ready':'Проверено', 'processing':'Проверяется',
};
String stateLabel(dynamic value) => stateLabels[value?.toString()] ?? value?.toString() ?? '';
int matchPercent(dynamic value) {
  final number = (value as num?)?.toDouble() ?? 0;
  return (number <= 1 ? number * 100 : number).clamp(0, 100).round();
}

class PhotoGallery extends StatelessWidget {
  const PhotoGallery({super.key, required this.media});
  final List<JsonMap> media;

  @override
  Widget build(BuildContext context) {
    if (media.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(builder: (context, constraints) {
      final columns = ((constraints.maxWidth + 12) / 292).floor().clamp(1, 3);
      final width = (constraints.maxWidth - 12 * (columns - 1)) / columns;
      return Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          for (var index = 0; index < media.length; index++)
            SizedBox(
              width: width,
              child: _GalleryPhoto(item: media[index], number: index + 1),
            ),
        ],
      );
    });
  }
}

class _GalleryPhoto extends StatelessWidget {
  const _GalleryPhoto({required this.item, required this.number});
  final JsonMap item;
  final int number;

  @override
  Widget build(BuildContext context) {
    final url = item['download_url']?.toString();
    final isImage = url != null && item['mime_type'].toString().startsWith('image/');
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AspectRatio(
            aspectRatio: 16 / 10,
            child: isImage
                ? InkWell(
                    onTap: () => showDialog<void>(
                      context: context,
                      builder: (dialogContext) => Dialog(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Align(
                              alignment: Alignment.topRight,
                              child: IconButton(
                                tooltip: 'Закрыть фото',
                                icon: const Icon(Icons.close),
                                onPressed: () => Navigator.pop(dialogContext),
                              ),
                            ),
                            Flexible(
                              child: InteractiveViewer(
                                child: Image.network(url, fit: BoxFit.contain,
                                  errorBuilder: (_, error, stack) => const Center(child: Text('Не удалось загрузить фото'))),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    child: Image.network(
                      url,
                      fit: BoxFit.contain,
                      semanticLabel: 'Фото $number',
                      errorBuilder: (_, error, stack) => const Center(child: Text('Не удалось загрузить фото')),
                    ),
                  )
                : const Center(child: Icon(Icons.insert_drive_file_outlined, size: 40)),
          ),
          if (item['status'] != null && item['status'] != 'ready')
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(stateLabel(item['status'])),
            ),
        ],
      ),
    );
  }
}

class ListingMap extends StatelessWidget {
  const ListingMap({super.key, required this.listings, this.selected, this.onPick, this.onOpen});
  final List<JsonMap> listings;
  final LatLng? selected;
  final ValueChanged<LatLng>? onPick;
  final ValueChanged<JsonMap>? onOpen;
  @override
  Widget build(BuildContext context) {
    final located = listings.where((l) => l['approx_latitude'] is num && l['approx_longitude'] is num).toList();
    if (located.isEmpty && onPick == null) return const NoticeCard('В этих объявлениях нет координат. Посмотрите указанные города и районы в списке.');
    final maps = context.dependOnInheritedWidgetOfExactType<AppScope>()?.notifier?.bootstrap['maps'] as Map?;
    final jsKey = maps?['javascript_key']?.toString() ?? '';
    if (kIsWeb && jsKey.isNotEmpty) {
      return yandexMap(apiKey: jsKey, listings: listings, selected: selected, onPick: onPick, onOpen: onOpen);
    }
    LatLng point(JsonMap l) => LatLng((l['approx_latitude'] as num).toDouble(), (l['approx_longitude'] as num).toDouble());
    final center = selected ?? (located.isEmpty ? const LatLng(55.75, 37.62) : point(located.first));
    return Column(children: [
      SizedBox(height: 340, child: FlutterMap(options: MapOptions(initialCenter: center, initialZoom: located.isEmpty && selected == null ? 4 : 11,
        onTap: onPick == null ? null : (_, position) => onPick!(position)), children: [
        TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'ru.edinburo.app', maxNativeZoom: 19),
        MarkerLayer(markers: [
          for (final item in located) Marker(point: point(item), width: 48, height: 48, child: IconButton(
            tooltip: item['title']?.toString(), onPressed: onOpen == null ? null : () => onOpen!(item), icon: const Icon(Icons.location_on, color: Colors.red, size: 38))),
          if (selected != null) Marker(point: selected!, width: 48, height: 48, child: const Icon(Icons.location_on, color: Colors.blue, size: 40)),
        ]),
      ])),
      TextButton(onPressed: () => launchUrl(Uri.parse('https://www.openstreetmap.org/copyright')), child: const Text('© OpenStreetMap contributors')),
      Text(onPick != null ? 'Нажмите на карте, чтобы указать место. Публичная точка округляется.' : 'Показаны только объявления с координатами. Точки приблизительные.'),
    ]);
  }
}

class ScanHandoverPage extends StatefulWidget {
  const ScanHandoverPage({super.key});
  @override
  State<ScanHandoverPage> createState() => _ScanHandoverPageState();
}
class _ScanHandoverPageState extends State<ScanHandoverPage> {
  bool _done = false;
  @override
  Widget build(BuildContext context) => BureauPage(title: 'Сканировать QR передачи', child: Column(children: [
    const Text('Наведите камеру на QR-код владельца. После распознавания проверьте заявку перед подтверждением передачи.'),
    const SizedBox(height: 16),
    SizedBox(height: 360, child: MobileScanner(onDetect: (capture) {
      final codes = capture.barcodes.where((b) => b.rawValue?.isNotEmpty == true);
      if (!_done && codes.isNotEmpty && Navigator.canPop(context)) { _done = true; Navigator.pop(context, codes.first.rawValue); }
    })),
    const SizedBox(height: 12),
    const Text('Разрешите доступ к камере. Если камера недоступна, закройте экран и введите код вручную.'),
  ]));
}

