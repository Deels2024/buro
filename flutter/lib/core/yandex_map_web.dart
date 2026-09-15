import 'dart:convert';
import 'dart:js_interop';

import 'package:flutter/widgets.dart';
import 'package:latlong2/latlong.dart';
import 'package:web/web.dart' as web;

import '../data/bureau_api_client.dart';
import 'yandex_map_message.dart';

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
  web.HTMLIFrameElement? _frame;
  late final JSFunction _messages;
  late final JSFunction _loaded;

  @override
  void initState() {
    super.initState();
    _loaded = ((web.Event event) { if (mounted) _send(); }).toJS;
    _messages = ((web.MessageEvent event) {
      if (!mounted) return;
      final data = decodeMapMessage(event, _frame?.contentWindow, Uri.base.origin);
      if (data == null) return;
      if (data['type'] == 'ready') _send();
      if (data['type'] == 'pick' && data['lat'] is num && data['lon'] is num) {
        final lat = (data['lat'] as num).toDouble(), lon = (data['lon'] as num).toDouble();
        if (lat.isFinite && lon.isFinite && lat.abs() <= 90 && lon.abs() <= 180) widget.onPick?.call(LatLng(lat, lon));
      }
      if (data['type'] == 'open' && data['index'] is int) {
        final index = data['index'] as int;
        if (index >= 0 && index < widget.listings.length) widget.onOpen?.call(widget.listings[index]);
      }
    }).toJS;
    web.window.addEventListener('message', _messages);
  }

  void _send() {
    _frame?.contentWindow?.postMessage(jsonEncode({
      'source': 'bureau-flutter', 'key': widget.apiKey, 'editable': widget.onPick != null,
      'selected': widget.selected == null ? null : [widget.selected!.latitude, widget.selected!.longitude],
      'markers': [for (var i = 0; i < widget.listings.length; i++)
        if (widget.listings[i]['approx_latitude'] is num && widget.listings[i]['approx_longitude'] is num)
          {'index': i, 'lat': widget.listings[i]['approx_latitude'], 'lon': widget.listings[i]['approx_longitude']}],
    }).toJS, Uri.base.origin.toJS);
  }

  @override
  void didUpdateWidget(covariant _YandexMap oldWidget) { super.didUpdateWidget(oldWidget); _send(); }
  @override
  void dispose() {
    web.window.removeEventListener('message', _messages);
    _frame?.removeEventListener('load', _loaded);
    super.dispose();
  }
  @override
  Widget build(BuildContext context) => SizedBox(height: 400, child: HtmlElementView.fromTagName(
    tagName: 'iframe',
    onElementCreated: (element) {
      _frame?.removeEventListener('load', _loaded);
      final frame = element as web.HTMLIFrameElement;
      _frame = frame;
      frame.title = 'Яндекс Карта';
      frame.style.border = '0'; frame.style.width = '100%'; frame.style.height = '100%';
      frame.setAttribute('allow', 'geolocation');
      // Flutter creates the element before attaching it to the DOM. Re-send
      // on load as well as ready, so a missed handshake cannot leave it blank.
      frame.addEventListener('load', _loaded);
      frame.src = Uri.base.resolve('yandex-map.html').toString();
    },
  ));
}
