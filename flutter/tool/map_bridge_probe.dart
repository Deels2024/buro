import 'dart:js_interop';

import 'package:bureau_nakhodok/core/yandex_map_message.dart';
import 'package:web/web.dart' as web;

@JS('mapTestFrame')
external web.HTMLIFrameElement get frame;
@JS('mapTestEvents')
external JSArray<web.MessageEvent> get events;

void main() {
  final inputs = events.toDart;
  final accepted = decodeMapMessage(inputs.first, frame.contentWindow, 'https://edinburo.ru');
  if (accepted?['type'] != 'ready') throw StateError('The map iframe ready message was lost');
  for (final event in inputs.skip(1)) {
    if (decodeMapMessage(event, frame.contentWindow, 'https://edinburo.ru') != null) {
      throw StateError('Untrusted or malformed frame message was accepted');
    }
  }
  // This executable probe reports its result to the Node test runner.
  // ignore: avoid_print
  print('Dart web bridge: real JS source identity and message validation passed');
}
