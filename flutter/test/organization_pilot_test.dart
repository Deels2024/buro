import 'dart:convert';

import 'package:bureau_nakhodok/core/theme.dart';
import 'package:bureau_nakhodok/data/app_controller.dart';
import 'package:bureau_nakhodok/data/bureau_api_client.dart';
import 'package:bureau_nakhodok/features/organization/organization_app.dart';
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

const _organization = {
  'id': 'mall',
  'name': 'Тестовый ТЦ',
  'status': 'verified',
};
const _listing = {
  'id': 'item',
  'title': 'Складной зонт',
  'category': 'other',
  'storage_code': 'Полка A',
  'status': 'active',
  'moderation_status': 'approved',
};

http.Response _json(Object data) => http.Response(
  jsonEncode(data), 200, headers: {'content-type': 'application/json; charset=utf-8'},
);

Future<void> _open(WidgetTester tester, Widget screen, MockClient server) async {
  final controller = AppController(api: BureauApiClient(
    baseUrl: 'https://example.invalid/v1', httpClient: server, tokenStore: _Tokens(),
  ));
  addTearDown(controller.dispose);
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 844);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(AppScope(controller: controller, child: MaterialApp(
    theme: BureauTheme.light, home: screen,
  )));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('next shift sees a match on a narrow screen, but not manager-only issue', (tester) async {
    await _open(tester, const OrganizationRecordPage(
      organization: {..._organization, 'member_role': 'operator'}, listing: _listing,
    ), MockClient((request) async {
      expect(request.url.path, '/v1/listings/item/matches');
      return _json([{'candidate': {'title': 'Потерян зонт', 'public_region': 'Петербург'}}]);
    }));
    expect(find.text('Потерян зонт'), findsOneWidget);
    expect(find.textContaining('Полка A'), findsOneWidget);
    expect(find.text('Оформить выдачу без телефона'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('desk issue requires a selected proof method and physical handover', (tester) async {
    final posts = <Object>[];
    await _open(tester, const OrganizationRecordPage(
      organization: {..._organization, 'member_role': 'manager'}, listing: _listing,
    ), MockClient((request) async {
      final path = request.url.path;
      if (path.endsWith('/matches')) return _json([]);
      if (path.endsWith('/manage')) return _json({'hidden_features': ['тестовая метка']});
      expect(path, '/v1/organizations/mall/inventory/item/counter-return');
      expect(request.method, 'POST');
      posts.add(jsonDecode(request.body) as Object);
      return _json({'listing_id': 'item', 'completed_at': '2026-11-27T20:00:00Z'});
    }));
    await tester.tap(find.text('Оформить выдачу без телефона'));
    await tester.pumpAndSettle();
    expect(find.textContaining('тестовая метка'), findsOneWidget);
    final submit = find.widgetWithText(FilledButton, 'Зафиксировать выдачу');
    expect(tester.widget<FilledButton>(submit).onPressed, isNull);

    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Непубличная примета').last);
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(submit).onPressed, isNull);
    await tester.ensureVisible(find.byType(CheckboxListTile));
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();
    await tester.tap(submit);
    await tester.pumpAndSettle();
    expect(posts.single, {'verification': 'private_feature', 'confirmed': true});
    expect(find.text('Выдано владельцу на стойке.'), findsOneWidget);
    expect(find.text('Оформить выдачу без телефона'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
