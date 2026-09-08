import 'package:bureau_nakhodok/data/bureau_api_client.dart';
import 'package:bureau_nakhodok/data/secure_token_store.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  const tokens = BureauTokens('test-access', 'test-refresh', 900);
  const key = 'bureau.auth.tokens.v1';
  late Map<String, String> persisted;
  late bool unreadable;
  late bool failWrite;

  setUp(() {
    persisted = {};
    unreadable = false;
    failWrite = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      final arguments = Map<String, dynamic>.from(call.arguments as Map);
      final recordKey = arguments['key'] as String;
      switch (call.method) {
        case 'read':
          return unreadable ? null : persisted[recordKey];
        case 'containsKey':
          return persisted.containsKey(recordKey);
        case 'write':
          if (failWrite) throw PlatformException(code: 'storage_unavailable');
          persisted[recordKey] = arguments['value'] as String;
          return null;
        case 'delete':
          persisted.remove(recordKey);
          return null;
        default:
          throw StateError('Unexpected storage call: ${call.method}');
      }
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('a new store restores persisted tokens; logout survives reopening', () async {
    await SecureBureauTokenStore().write(tokens);
    final reopened = SecureBureauTokenStore();
    expect((await reopened.read())?.refreshToken, tokens.refreshToken);
    await reopened.write(null);
    expect(await SecureBureauTokenStore().read(), isNull);
    expect(persisted, isEmpty);
  });

  test('null from decryption failure preserves the record and is retryable', () async {
    await SecureBureauTokenStore().write(tokens);
    final saved = persisted[key];
    unreadable = true;
    final reopened = SecureBureauTokenStore();
    await expectLater(reopened.read(), throwsStateError);
    expect(persisted[key], saved);
    unreadable = false;
    expect((await reopened.read())?.refreshToken, tokens.refreshToken);
  });

  test('missing tokens are a signed-out session', () async {
    expect(await SecureBureauTokenStore().read(), isNull);
  });

  test('malformed saved data is retained rather than silently logged out', () async {
    persisted[key] = '{invalid';
    final reopened = SecureBureauTokenStore();
    await expectLater(reopened.read(), throwsFormatException);
    expect(persisted[key], '{invalid');
    await SecureBureauTokenStore().write(tokens);
    expect((await reopened.read())?.refreshToken, tokens.refreshToken);
  });

  test('failed persistence does not create an in-memory login', () async {
    final store = SecureBureauTokenStore();
    failWrite = true;
    await expectLater(store.write(tokens), throwsA(isA<PlatformException>()));
    expect(await store.read(), isNull);
    expect(await SecureBureauTokenStore().read(), isNull);
    failWrite = false;
    await store.write(tokens);
    expect((await SecureBureauTokenStore().read())?.refreshToken, tokens.refreshToken);
  });
}
