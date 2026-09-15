// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;
import 'dart:js_util' as js;

Object? get _bridge => js.getProperty<Object?>(html.window, 'bureauPush');
bool get pushSupported => _bridge != null && js.getProperty<bool>(_bridge!, 'supported');
Future<String> _call(String method, [List<Object> args = const []]) async {
  final bridge = _bridge;
  if (bridge == null) return '';
  return js.promiseToFuture<String>(js.callMethod<Object>(bridge, method, args));
}
Future<String> pushSubscription() => _call('subscription');
Future<String> subscribePush(String publicKey) => _call('subscribe', [publicKey]);
void rememberPushDevice(String id) {
  final bridge = _bridge;
  if (bridge != null) js.callMethod<void>(bridge, 'saveDevice', [id]);
}
Future<String> unsubscribePush() => _call('unsubscribe');
