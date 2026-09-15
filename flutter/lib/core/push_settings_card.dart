import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../data/app_controller.dart';
import 'push_notifications.dart';

class PushSettingsCard extends StatefulWidget {
  const PushSettingsCard({super.key});
  @override
  State<PushSettingsCard> createState() => _PushSettingsCardState();
}

class _PushSettingsCardState extends State<PushSettingsCard> {
  bool _loaded = false, _busy = false, _enabled = false;
  String? _publicKey, _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_loaded && pushSupported) { _loaded = true; _load(); }
  }

  Future<void> _load() async {
    final api = AppScope.of(context, listen: false).api;
    setState(() => _busy = true);
    try {
      final config = await api.request('GET', '/users/me/push/config') as Map;
      final subscription = await pushSubscription();
      // Reconcile a permission/subscription that outlived a temporary API failure.
      if (subscription.isNotEmpty) {
        final device = await api.request('PUT', '/users/me/push/subscription', body: jsonDecode(subscription)) as Map;
        rememberPushDevice(device['id'].toString());
      }
      if (mounted) setState(() { _publicKey = config['public_key'].toString(); _enabled = subscription.isNotEmpty; _error = null; });
    } catch (_) {
      if (mounted) setState(() => _error = 'Не удалось проверить уведомления. Нажмите, чтобы повторить.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toggle() async {
    final api = AppScope.of(context, listen: false).api;
    setState(() { _busy = true; _error = null; });
    try {
      if (_enabled) {
        final id = await unsubscribePush();
        if (id.isNotEmpty) await api.request('DELETE', '/users/me/devices/$id');
      } else {
        // No network await before requesting the browser permission.
        final subscription = await subscribePush(_publicKey!);
        final device = await api.request('PUT', '/users/me/push/subscription', body: jsonDecode(subscription)) as Map;
        rememberPushDevice(device['id'].toString());
      }
      if (mounted) setState(() => _enabled = !_enabled);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb) return const SizedBox.shrink();
    return Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Не пропустите свою вещь', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        const Text('Сообщим о совпадении и ответах, даже когда приложение закрыто.'),
        if (!pushSupported) const Padding(padding: EdgeInsets.only(top: 8), child: Text(
          'На iPhone добавьте приложение на экран «Домой» через Safari и откройте его оттуда.')),
        if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!)),
        if (pushSupported) Padding(padding: const EdgeInsets.only(top: 12), child: FilledButton(
          onPressed: _busy ? null : _publicKey == null ? _load : _toggle,
          child: Text(_busy ? 'Подождите…' : _publicKey == null ? 'Проверить уведомления' :
            _enabled ? 'Отключить на этом устройстве' : 'Включить уведомления'),
        )),
      ],
    )));
  }
}
