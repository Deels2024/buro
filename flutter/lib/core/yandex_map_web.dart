// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;
import 'package:flutter/widgets.dart';
import 'package:latlong2/latlong.dart';
import '../data/bureau_api_client.dart';

Widget yandexMap({required String apiKey, required List<JsonMap> listings,
  LatLng? selected, ValueChanged<LatLng>? onPick, ValueChanged<JsonMap>? onOpen}) =>
    _YandexMap(apiKey: apiKey, listings: listings, selected: selected, onPick: onPick, onOpen: onOpen);

class _YandexMap extends StatefulWidget {
  const _YandexMap({required this.apiKey, required this.listings, this.selected, this.onPick, this.onOpen});
  final String apiKey;
  final List<JsonMap> listings;
  final LatLng? selected;
  final ValueChanged<LatLng>? onPick;
  final ValueChanged<JsonMap>? onOpen;
  @override
  State<_YandexMap> createState() => _YandexMapState();
}

class _YandexMapState extends State<_YandexMap> {
  html.IFrameElement? _frame;
  StreamSubscription<html.MessageEvent>? _messages;
  @override
  void initState() {
    super.initState();
    _messages = html.window.onMessage.listen((event) {
      if (!mounted || _frame == null || event.origin != Uri.base.origin || event.source != _frame!.contentWindow || event.data is! String) return;
      try {
        final data = jsonDecode(event.data as String);
        if (data is! Map || data['source'] != 'bureau-yandex') return;
        if (data['type'] == 'ready') _send();
        if (data['type'] == 'pick' && data['lat'] is num && data['lon'] is num) {
          final lat = (data['lat'] as num).toDouble(), lon = (data['lon'] as num).toDouble();
          if (lat.isFinite && lon.isFinite && lat.abs() <= 90 && lon.abs() <= 180) widget.onPick?.call(LatLng(lat, lon));
        }
        if (data['type'] == 'open' && data['index'] is int) {
          final index = data['index'] as int;
          if (index >= 0 && index < widget.listings.length) widget.onOpen?.call(widget.listings[index]);
        }
      } on FormatException {
        // Ignore unrelated messages from embedded content.
      }
    });
  }
  void _send() {
    _frame?.contentWindow?.postMessage(jsonEncode({
      'source': 'bureau-flutter', 'key': widget.apiKey, 'editable': widget.onPick != null,
      'selected': widget.selected == null ? null : [widget.selected!.latitude, widget.selected!.longitude],
      'markers': [for (var i = 0; i < widget.listings.length; i++)
        if (widget.listings[i]['approx_latitude'] is num && widget.listings[i]['approx_longitude'] is num)
          {'index': i, 'lat': widget.listings[i]['approx_latitude'], 'lon': widget.listings[i]['approx_longitude']}],
    }), Uri.base.origin);
  }
  @override
  void didUpdateWidget(covariant _YandexMap oldWidget) { super.didUpdateWidget(oldWidget); _send(); }
  @override
  void dispose() { _messages?.cancel(); super.dispose(); }
  @override
  Widget build(BuildContext context) => SizedBox(height: 400, child: HtmlElementView.fromTagName(
    tagName: 'iframe',
    onElementCreated: (element) {
      final frame = element as html.IFrameElement;
      _frame = frame;
      frame.title = 'Яндекс Карта';
      frame.style.border = '0'; frame.style.width = '100%'; frame.style.height = '100%';
      frame.setAttribute('allow', 'geolocation');
      frame.src = Uri.base.resolve('yandex-map.html').toString();
    },
  ));
}
