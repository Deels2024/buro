import 'dart:convert';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

Map<String, dynamic>? decodeMapMessage(web.MessageEvent event, web.Window? frameWindow, String origin) {
  // dart:html converts cross-frame MessageEvent.source to null. package:web
  // preserves the real JS window, so verify its identity without a wrapper.
  if (frameWindow == null || event.origin != origin ||
      !event.source.strictEquals(frameWindow).toDart || !event.data.isA<JSString>()) {
    return null;
  }
  try {
    final value = jsonDecode((event.data as JSString).toDart);
    if (value is Map<String, dynamic> && value['source'] == 'bureau-yandex') return value;
  } on FormatException {
    // Unrelated or malformed messages never affect the map or navigation.
  }
  return null;
}
