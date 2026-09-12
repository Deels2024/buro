import 'dart:async';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import '../data/app_controller.dart';
import '../data/bureau_api_client.dart';
import 'production_widgets.dart';
import 'widgets.dart';

class MapsTextField extends StatefulWidget {
  const MapsTextField({super.key, required this.controller, required this.label,
    this.cityOnly = false, this.prefix, this.onEdited, this.onSelected});
  final TextEditingController controller;
  final String label;
  final bool cityOnly;
  final String Function()? prefix;
  final VoidCallback? onEdited;
  final Future<void> Function(JsonMap)? onSelected;
  @override
  State<MapsTextField> createState() => _MapsTextFieldState();
}

class _MapsTextFieldState extends State<MapsTextField> {
  Timer? _timer;
  int _version = 0;
  bool _loading = false;
  List<JsonMap> _suggestions = [];
  String? _error;
  String _lastText = '';
  @override
  void initState() {
    super.initState();
    _lastText = widget.controller.text;
    widget.controller.addListener(_controllerChanged);
  }
  void _controllerChanged() {
    if (_lastText == widget.controller.text) return;
    _lastText = widget.controller.text;
    ++_version;
    _timer?.cancel();
    if (mounted) setState(() { _suggestions = []; _error = null; _loading = false; });
  }
  @override
  void didUpdateWidget(covariant MapsTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_controllerChanged);
      widget.controller.addListener(_controllerChanged);
      _controllerChanged();
    }
  }
  void _changed(String text) {
    widget.onEdited?.call();
    _timer?.cancel();
    final version = ++_version;
    setState(() { _suggestions = []; _error = null; _loading = false; });
    final scope = AppScope.of(context, listen: false);
    if (text.trim().length < 3 || (scope.bootstrap['maps'] as Map?)?['suggest'] != true) return;
    _timer = Timer(const Duration(milliseconds: 650), () async {
      if (!mounted) return;
      setState(() => _loading = true);
      try {
        final query = [widget.prefix?.call().trim() ?? '', text.trim()].where((v) => v.isNotEmpty).join(', ');
        final result = await scope.api.request('POST', '/maps/suggest',
          body: {'query': query, 'kind': widget.cityOnly ? 'city' : 'address'}, timeout: const Duration(seconds: 12));
        if (!mounted || version != _version) return;
        setState(() => _suggestions = (result as List).map((v) => Map<String, dynamic>.from(v as Map)).toList());
      } catch (error) {
        if (!mounted || version != _version) return;
        setState(() => _error = error is BureauApiException ? error.detail : 'Подсказки недоступны. Введите вручную.');
      } finally {
        if (mounted && version == _version) setState(() => _loading = false);
      }
    });
  }
  Future<void> _select(JsonMap suggestion) async {
    ++_version; _timer?.cancel();
    final city = suggestion['city']?.toString() ?? '';
    widget.controller.text = widget.cityOnly
        ? (city.isNotEmpty ? city : suggestion['title'].toString())
        : suggestion['query'].toString();
    setState(() { _suggestions = []; _error = null; _loading = false; });
    await widget.onSelected?.call(suggestion);
  }
  @override
  void dispose() { ++_version; _timer?.cancel(); widget.controller.removeListener(_controllerChanged); super.dispose(); }
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    BureauField(label: widget.label, child: TextField(controller: widget.controller, onChanged: _changed,
      minLines: 1, maxLines: 3,
      decoration: InputDecoration(
        prefixIcon: Icon(widget.cityOnly ? Icons.location_city_outlined : Icons.location_on_outlined),
        suffixIcon: _loading ? const Padding(padding: EdgeInsets.all(14), child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))) : null))),
    if (_error != null) Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Text(_error!, style: const TextStyle(fontSize: 13))),
    for (final suggestion in _suggestions) ListTile(dense: true,
      title: Text(suggestion['title'].toString()), subtitle: Text(suggestion['subtitle']?.toString() ?? ''),
      onTap: () => _select(suggestion)),
    if (_suggestions.isNotEmpty) const Align(alignment: Alignment.centerRight, child: Text('Подсказки Яндекса', style: TextStyle(fontSize: 11))),
  ]);
}

class LocationEditor extends StatefulWidget {
  const LocationEditor({super.key, required this.region, required this.address, required this.onPoint,
    this.selected, this.onResolvingChanged});
  final TextEditingController region;
  final TextEditingController address;
  final LatLng? selected;
  final ValueChanged<LatLng?> onPoint;
  final ValueChanged<bool>? onResolvingChanged;
  @override
  State<LocationEditor> createState() => _LocationEditorState();
}

class _LocationEditorState extends State<LocationEditor> {
  int _version = 0;
  bool _resolving = false;
  String? _message;
  void _edited() {
    ++_version;
    widget.onPoint(null);
    setState(() { _resolving = false; _message = null; });
    widget.onResolvingChanged?.call(false);
  }
  Future<void> _resolve({JsonMap? suggestion, LatLng? point, bool cityOnly = false}) async {
    final version = ++_version;
    // A newly chosen point is authoritative even if reverse geocoding fails.
    widget.onPoint(point);
    if (point != null || cityOnly) widget.address.clear();
    if (point != null) widget.region.clear();
    setState(() { _resolving = true; _message = null; });
    widget.onResolvingChanged?.call(true);
    try {
      final uri = suggestion?['uri']?.toString() ?? '';
      final result = await AppScope.of(context, listen: false).api.request('POST', '/maps/resolve',
        body: point != null ? {'latitude': point.latitude, 'longitude': point.longitude}
          : {if (uri.isNotEmpty) 'uri': uri else 'query': suggestion!['query'], 'city_only': cityOnly},
        timeout: const Duration(seconds: 12));
      if (!mounted || version != _version) return;
      final data = Map<String, dynamic>.from(result as Map);
      if ((data['region']?.toString() ?? '').isNotEmpty) widget.region.text = data['region'].toString();
      if (!cityOnly) widget.address.text = data['address']?.toString() ?? '';
      widget.onPoint(point ?? LatLng((data['latitude'] as num).toDouble(), (data['longitude'] as num).toDouble()));
      setState(() => _message = cityOnly ? 'Город выбран. Уточните адрес или место на карте.' : 'Адрес определён. Проверьте его перед продолжением.');
    } catch (error) {
      if (!mounted || version != _version) return;
      setState(() => _message = error is BureauApiException ? error.detail : 'Введите город и адрес вручную.');
    } finally {
      if (mounted && version == _version) {
        setState(() => _resolving = false);
        widget.onResolvingChanged?.call(false);
      }
    }
  }
  @override
  void dispose() { ++_version; super.dispose(); }
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    MapsTextField(controller: widget.region, label: 'Город или населённый пункт', cityOnly: true,
      onEdited: () { widget.address.clear(); _edited(); },
      onSelected: (s) => _resolve(suggestion: s, cityOnly: true)),
    const SizedBox(height: 20),
    MapsTextField(controller: widget.address, label: 'Адрес или ориентир (скрыт от других)',
      prefix: () => widget.region.text, onEdited: _edited, onSelected: (s) => _resolve(suggestion: s)),
    const SizedBox(height: 20),
    ListingMap(listings: const [], selected: widget.selected, onPick: (p) => _resolve(point: p)),
    if (_resolving) const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: LinearProgressIndicator()),
    if (_message != null) Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text(_message!)),
  ]);
}
