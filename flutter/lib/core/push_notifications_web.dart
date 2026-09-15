import 'dart:js_interop';

@JS('bureauPush')
external JSObject? get _bridge;
@JS('bureauPush.supported')
external bool get _supported;
@JS('bureauPush.subscription')
external JSPromise<JSString> _subscription();
@JS('bureauPush.subscribe')
external JSPromise<JSString> _subscribe(JSString publicKey);
@JS('bureauPush.saveDevice')
external void _saveDevice(JSString id);
@JS('bureauPush.unsubscribe')
external JSPromise<JSString> _unsubscribe();

bool get pushSupported => _bridge != null && _supported;
Future<String> pushSubscription() async => _bridge == null ? '' : (await _subscription().toDart).toDart;
Future<String> subscribePush(String publicKey) async => (await _subscribe(publicKey.toJS).toDart).toDart;
void rememberPushDevice(String id) {
  if (_bridge != null) _saveDevice(id.toJS);
}
Future<String> unsubscribePush() async => _bridge == null ? '' : (await _unsubscribe().toDart).toDart;
