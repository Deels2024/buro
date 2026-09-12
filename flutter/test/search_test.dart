import 'dart:async';
import 'dart:convert';

import 'package:bureau_nakhodok/core/theme.dart';
import 'package:bureau_nakhodok/data/app_controller.dart';
import 'package:bureau_nakhodok/data/bureau_api_client.dart';
import 'package:bureau_nakhodok/features/user/user_app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _Tokens implements BureauTokenStore {
  int reads = 0;
  @override
  Future<BureauTokens?> read() async { reads++; return null; }
  @override
  Future<void> write(BureauTokens? tokens) async {}
}

http.Response _json(Object data, [int status = 200]) => http.Response(
  jsonEncode(data), status, headers: {'content-type': 'application/json; charset=utf-8'},
);
http.Response _page([String? title]) => _json({'total': title == null ? 0 : 1,
  'items': [if (title != null) {'id':'item', 'kind':'found', 'title':title, 'media':[], 'public_region':'Москва'}],
  'limit':24, 'offset':0});

Future<AppController> _open(WidgetTester tester, Future<http.Response> Function(http.Request) handle, {_Tokens? tokens}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 844);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final controller = AppController(api: BureauApiClient(baseUrl:'https://example.invalid/v1',
    tokenStore:tokens ?? _Tokens(), httpClient:MockClient(handle)));
  await tester.pumpWidget(AppScope(controller:controller, child:MaterialApp(
    theme:BureauTheme.light, home:const Scaffold(body:SearchView()),
  )));
  await tester.pump();
  addTearDown(() async { await tester.pumpWidget(const SizedBox.shrink()); controller.dispose(); });
  return controller;
}

void main() {
  testWidgets('inherited theme change does not restart an active search', (tester) async {
    final response = Completer<http.Response>();
    var calls = 0;
    final controller = await _open(tester, (_) { calls++; return response.future; });
    expect(calls, 1);
    await tester.pumpWidget(AppScope(controller:controller, child:MaterialApp(
      theme:BureauTheme.light.copyWith(scaffoldBackgroundColor:Colors.white),
      home:const Scaffold(body:SearchView()),
    )));
    await tester.pump();
    expect(calls, 1);
    response.complete(_page('Чёрный рюкзак'));
    await tester.pumpAndSettle();
    expect(find.text('Чёрный рюкзак'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('slow search ends with a retry and late result cannot replace it', (tester) async {
    final slow = Completer<http.Response>();
    var calls = 0;
    await _open(tester, (_) { calls++; return calls == 1 ? slow.future : Future.value(_page('Найденный рюкзак')); });
    await tester.pump(const Duration(seconds:16));
    await tester.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await tester.ensureVisible(find.text('Повторить поиск'));
    await tester.tap(find.text('Повторить поиск'));
    await tester.pumpAndSettle();
    slow.complete(_page('Старый ответ'));
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(find.text('Найденный рюкзак'), findsOneWidget);
    expect(find.text('Старый ответ'), findsNothing);
  });

  testWidgets('search submit cancels debounce and ignores older query results', (tester) async {
    final old = Completer<http.Response>();
    final queries = <String?>[];
    await _open(tester, (request) {
      final query = request.url.queryParameters['query']; queries.add(query);
      return query == 'старый' ? old.future : Future.value(_page(query ?? 'Все вещи'));
    });
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'старый');
    await tester.pump(const Duration(milliseconds:400));
    await tester.enterText(find.byType(TextField), 'рюкзак');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    old.complete(_page('Старый ответ'));
    await tester.pumpAndSettle();
    expect(queries, [null, 'старый', 'рюкзак']);
    expect(find.text('рюкзак'), findsNWidgets(2)); // Input plus the resulting card.
    expect(find.text('Старый ответ'), findsNothing);
  });

  testWidgets('lost and found intent chooses counterpart without reading session and carries to photo search', (tester) async {
    final tokens = _Tokens();
    final kinds = <String?>[];
    await _open(tester, (request) async { kinds.add(request.url.queryParameters['kind']); return _page(); }, tokens:tokens);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Я потерял'));
    await tester.pumpAndSettle();
    expect(kinds.last, 'found');
    await tester.tap(find.text('Я нашёл'));
    await tester.pumpAndSettle();
    expect(kinds.last, 'lost');
    await tester.tap(find.text('Фото'));
    await tester.pumpAndSettle();
    expect(tester.widget<PhotoSearchPage>(find.byType(PhotoSearchPage)).filters.kind, 'lost');
    expect(tokens.reads, 0);
    expect(tester.takeException(), isNull);
  });

  test('photo search retries processing only and preserves filters', () async {
    final bodies = <JsonMap>[];
    final keys = <String?>[];
    final since = DateTime.utc(2026, 9, 1);
    final api = BureauApiClient(baseUrl:'https://example.invalid/v1', tokenStore:_Tokens(),
      httpClient:MockClient((request) async {
        bodies.add(jsonDecode(request.body) as JsonMap); keys.add(request.headers['Idempotency-Key']);
        return bodies.length == 1 ? _json({'detail':'Фото обрабатывается'},409) : _json([]);
      }));
    expect(await api.photoSearch('photo', targetKind:'lost', category:'bags', region:'Москва', since:since), isEmpty);
    expect(bodies.length, 2);
    expect(bodies.first, bodies.last);
    expect(bodies.last, containsPair('target_kind','lost'));
    expect(bodies.last, containsPair('since',since.toIso8601String()));
    expect(keys.toSet().length, 2);
    api.close();
  });

  for (final status in [422, 503]) {
    test('photo search does not retry HTTP $status', () async {
      var calls = 0;
      final api = BureauApiClient(baseUrl:'https://example.invalid/v1', tokenStore:_Tokens(),
        httpClient:MockClient((_) async { calls++; return _json({'detail':'Недоступно'},status); }));
      await expectLater(api.photoSearch('photo'), throwsA(isA<BureauApiException>()));
      expect(calls, 1);
      api.close();
    });
  }
}
