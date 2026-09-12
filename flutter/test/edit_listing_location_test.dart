import 'dart:async';
import 'dart:convert';

import 'package:bureau_nakhodok/core/location_editor.dart';
import 'package:bureau_nakhodok/core/production_widgets.dart';
import 'package:bureau_nakhodok/core/theme.dart';
import 'package:bureau_nakhodok/data/app_controller.dart';
import 'package:bureau_nakhodok/data/bureau_api_client.dart';
import 'package:bureau_nakhodok/features/user/management.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';

class _Tokens implements BureauTokenStore {
  @override
  Future<BureauTokens?> read() async => null;
  @override
  Future<void> write(BureauTokens? tokens) async {}
}

const _originalLocation = {
  'region': 'Санкт-Петербург', 'latitude': 59.934281, 'longitude': 30.335098,
  'exact_address': 'Невский проспект, 1',
};

class _Server {
  JsonMap listing = {
    'id': 'listing-1', 'kind': 'found', 'title': 'Серебристый ноутбук',
    'description': 'Ноутбук с чёрной клавиатурой', 'category': 'electronics',
    'status': 'draft', 'moderation_status': 'pending', 'media': <JsonMap>[],
    'public_region': 'Санкт-Петербург', 'storage_code': 'ЯЧ-12',
    'approx_latitude': 59.93, 'approx_longitude': 30.34,
    'location': Map<String, dynamic>.from(_originalLocation),
  };
  final patches = <JsonMap>[];
  final suggestions = <JsonMap>[];
  Completer<http.Response>? geocode;

  http.Response json(Object? data, [int status = 200]) => http.Response(
    jsonEncode(data), status, headers: {'content-type': 'application/json; charset=utf-8'},
  );

  Future<http.Response> handle(http.Request request) async {
    if (request.method == 'GET' && request.url.path.endsWith('/manage')) return json(listing);
    final body = jsonDecode(request.body) as Map<String, dynamic>;
    if (request.url.path.endsWith('/maps/suggest')) {
      suggestions.add(body);
      return json([{
        'title': 'Невский проспект, 20', 'subtitle': 'Санкт-Петербург',
        'city': 'Санкт-Петербург', 'query': 'Санкт-Петербург, Невский проспект, 20',
        'uri': 'ymapsbm1://geo?test',
      }]);
    }
    if (request.url.path.endsWith('/maps/resolve')) {
      return geocode?.future ?? Future.value(json({
        'region': 'Санкт-Петербург', 'address': 'Невский проспект, 20',
        'latitude': 59.935271, 'longitude': 30.322891,
      }));
    }
    expect(request.method, 'PATCH');
    expect(request.url.path, '/v1/listings/listing-1');
    patches.add(body);
    listing = {...listing, ...body};
    if (body['location'] case final Map location) listing['public_region'] = location['region'];
    return json(listing);
  }
}

Future<AppController> _open(WidgetTester tester, _Server server) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 844);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final controller = AppController(api: BureauApiClient(
    baseUrl: 'https://example.invalid/v1', tokenStore: _Tokens(), httpClient: MockClient(server.handle),
  ));
  controller.bootstrap = {'maps': {'suggest': true}};
  await tester.pumpWidget(AppScope(controller: controller, child: MaterialApp(
    theme: BureauTheme.light, home: const EditListingPage(listingId: 'listing-1'),
  )));
  await tester.pumpAndSettle();
  return controller;
}

Future<void> _save(WidgetTester tester) async {
  // Let EditableText finish revealing its caret before scrolling to the action.
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.text('Сохранить черновик'));
  await tester.pumpAndSettle();
  expect(find.text('Сохранить черновик').hitTestable(), findsOneWidget);
  await tester.tap(find.text('Сохранить черновик'));
  await tester.pumpAndSettle();
}

Future<void> _close(WidgetTester tester, AppController controller) async {
  await tester.pumpWidget(const SizedBox.shrink());
  controller.dispose();
}

void main() {
  testWidgets('editing a title preserves the exact location and separate storage code', (tester) async {
    final server = _Server();
    final controller = await _open(tester, server);
    final editor = tester.widget<LocationEditor>(find.byType(LocationEditor));
    expect(editor.address.text, _originalLocation['exact_address']);
    expect(editor.selected, const LatLng(59.934281, 30.335098));
    expect(find.byType(ListingMap), findsOneWidget);
    expect(find.text('Код ячейки хранения'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, 'Другой заголовок ноутбука');
    await _save(tester);
    expect(server.patches.single.containsKey('location'), isFalse);
    expect(server.patches.single['storage_code'], 'ЯЧ-12');
    expect(server.listing['location'], _originalLocation);
    expect(tester.takeException(), isNull);
    await _close(tester, controller);
  });

  testWidgets('address suggestion in the same city saves exact coordinates and reopens', (tester) async {
    final server = _Server();
    final controller = await _open(tester, server);
    final address = find.descendant(of: find.byType(MapsTextField).last, matching: find.byType(TextField));
    await tester.ensureVisible(address);
    await tester.enterText(address, 'Невский');
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();
    expect(server.suggestions.single, {'query': 'Санкт-Петербург, Невский', 'kind': 'address'});
    await tester.ensureVisible(find.text('Невский проспект, 20'));
    await tester.tap(find.text('Невский проспект, 20'));
    await tester.pumpAndSettle();
    await _save(tester);
    expect(server.patches.single['location'], {
      'region': 'Санкт-Петербург', 'latitude': 59.935271, 'longitude': 30.322891,
      'exact_address': 'Невский проспект, 20',
    });
    expect(server.patches.single['storage_code'], 'ЯЧ-12');
    await _close(tester, controller);
    final reopened = await _open(tester, server);
    final editor = tester.widget<LocationEditor>(find.byType(LocationEditor));
    expect(editor.address.text, 'Невский проспект, 20');
    expect(editor.selected, const LatLng(59.935271, 30.322891));
    expect(tester.takeException(), isNull);
    await _close(tester, reopened);
  });

  testWidgets('manual city edit clears the former address and coordinates', (tester) async {
    final server = _Server();
    final controller = await _open(tester, server);
    final city = find.descendant(of: find.byType(MapsTextField).first, matching: find.byType(TextField));
    await tester.ensureVisible(city);
    await tester.enterText(city, 'Выборг');
    await _save(tester);
    expect(server.patches.single['location'], {
      'region': 'Выборг', 'latitude': null, 'longitude': null, 'exact_address': null,
    });
    expect(tester.takeException(), isNull);
    await _close(tester, controller);
  });

  testWidgets('map selection waits for its address and then saves the chosen point', (tester) async {
    final server = _Server()..geocode = Completer<http.Response>();
    final controller = await _open(tester, server);
    const point = LatLng(60.710456, 28.749812);
    tester.widget<ListingMap>(find.byType(ListingMap)).onPick!(point);
    await tester.pump();
    // A progress indicator keeps animating while the geocoder is pending.
    await tester.ensureVisible(find.text('Сохранить черновик'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('Сохранить черновик'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(server.patches, isEmpty);
    expect(find.textContaining('Дождитесь определения адреса'), findsOneWidget);
    server.geocode!.complete(server.json({
      'region': 'Выборг', 'address': 'Крепостная улица, 1',
      'latitude': 60.7104, 'longitude': 28.7498,
    }));
    await tester.pumpAndSettle();
    await _save(tester);
    expect(server.patches.single['location'], {
      'region': 'Выборг', 'latitude': point.latitude, 'longitude': point.longitude,
      'exact_address': 'Крепостная улица, 1',
    });
    expect(tester.takeException(), isNull);
    await _close(tester, controller);
  });
}
