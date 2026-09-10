import 'dart:async';
import 'dart:convert';

import 'package:bureau_nakhodok/core/location_editor.dart';
import 'package:bureau_nakhodok/data/app_controller.dart';
import 'package:bureau_nakhodok/data/bureau_api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _Tokens implements BureauTokenStore {
  @override
  Future<BureauTokens?> read() async => null;
  @override
  Future<void> write(BureauTokens? tokens) async {}
}

void main() {
  for (final clearBeforeResponse in [false, true]) {
    testWidgets('city suggestions respect external edits: $clearBeforeResponse', (tester) async {
      final reply = Completer<http.Response>();
      var calls = 0;
      final controller = AppController(api: BureauApiClient(
        baseUrl: 'https://example.invalid/v1', tokenStore: _Tokens(),
        httpClient: MockClient((request) async {
          calls++;
          expect(request.url.path, '/v1/maps/suggest');
          expect(jsonDecode(request.body)['kind'], 'city');
          return reply.future;
        }),
      ));
      controller.bootstrap = {'maps': {'suggest': true}};
      final field = TextEditingController();
      await tester.pumpWidget(AppScope(controller: controller, child: MaterialApp(
        home: Scaffold(body: MapsTextField(controller: field, label: 'Город', cityOnly: true)),
      )));
      await tester.enterText(find.byType(TextField), 'Выб');
      await tester.pump(const Duration(milliseconds: 300));
      expect(calls, 0);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      expect(calls, 1);
      if (clearBeforeResponse) field.clear();
      reply.complete(http.Response(jsonEncode([{
        'title': 'Выборг', 'city': 'Выборг', 'subtitle': 'Ленинградская область',
        'query': 'Россия, Ленинградская область, Выборг', 'uri': 'ymapsbm1://geo?test',
      }]), 200, headers: {'content-type': 'application/json; charset=utf-8'}));
      await tester.pumpAndSettle();
      if (clearBeforeResponse) {
        expect(find.text('Ленинградская область'), findsNothing);
        expect(field.text, isEmpty);
      } else {
        await tester.tap(find.text('Ленинградская область'));
        await tester.pumpAndSettle();
        expect(field.text, 'Выборг');
        expect(find.text('Ленинградская область'), findsNothing);
      }
      expect(calls, 1);
      await tester.pumpWidget(const SizedBox.shrink());
      field.dispose();
      controller.dispose();
    });
  }
}
