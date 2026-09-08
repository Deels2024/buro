import 'dart:convert';

import 'package:bureau_nakhodok/data/bureau_api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _Tokens implements BureauTokenStore {
  @override
  Future<BureauTokens?> read() async => const BureauTokens('access', 'refresh', 900);
  @override
  Future<void> write(BureauTokens? tokens) async {}
}

void main() {
  test('photo processing is retried before requesting the description', () async {
    var calls = 0;
    final keys = <String?>[];
    final api = BureauApiClient(
      baseUrl: 'https://example.invalid/v1',
      tokenStore: _Tokens(),
      httpClient: MockClient((request) async {
        calls++;
        keys.add(request.headers['Idempotency-Key']);
        return calls == 1
            ? http.Response(jsonEncode({'detail': 'Фото обрабатывается'}), 409)
            : http.Response(jsonEncode({'title': 'Рюкзак'}), 200);
      }),
    );
    expect((await api.describeMedia('photo', 'found'))['title'], 'Рюкзак');
    expect(calls, 2);
    expect(keys.toSet().length, 2);
    api.close();
  });

  test('OpenAI error is shown without repeating paid requests', () async {
    var calls = 0;
    final api = BureauApiClient(
      baseUrl: 'https://example.invalid/v1',
      tokenStore: _Tokens(),
      httpClient: MockClient((request) async {
        calls++;
        return http.Response(jsonEncode({'detail': 'ИИ недоступен. [AI_ACCESS]'}), 503);
      }),
    );
    await expectLater(api.describeMedia('photo', 'found'),
        throwsA(isA<BureauApiException>().having((e) => e.detail, 'detail', contains('AI_ACCESS'))));
    expect(calls, 1);
    api.close();
  });

  test('non-JSON gateway failure reports HTTP status, not upstream HTML', () async {
    final api = BureauApiClient(
      baseUrl: 'https://example.invalid/v1',
      tokenStore: _Tokens(),
      httpClient: MockClient((_) async => http.Response('<html>private proxy details</html>', 502)),
    );
    await expectLater(api.describeMedia('photo', 'found'),
        throwsA(isA<BureauApiException>()
            .having((e) => e.detail, 'status', contains('HTTP 502'))
            .having((e) => e.detail, 'safe message', isNot(contains('private')))));
    api.close();
  });
}
