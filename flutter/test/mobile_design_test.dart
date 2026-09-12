import 'dart:convert';
import 'dart:ui' as ui;

import 'package:bureau_nakhodok/core/brand_artwork.dart';
import 'package:bureau_nakhodok/core/theme.dart';
import 'package:bureau_nakhodok/data/app_controller.dart';
import 'package:bureau_nakhodok/data/bureau_api_client.dart';
import 'package:bureau_nakhodok/features/user/create_flow.dart';
import 'package:bureau_nakhodok/features/user/user_app.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _Tokens implements BureauTokenStore {
  @override
  Future<BureauTokens?> read() async => null;
  @override
  Future<void> write(BureauTokens? tokens) async {}
}

const _screenKey = Key('design-screen');
http.Response _json(Object? data) => http.Response(jsonEncode(data), 200,
  headers: {'content-type':'application/json; charset=utf-8'});

Future<http.Response> _handle(http.Request request) async {
  if (request.url.path == '/v1/listings') {
    return _json({'total':1, 'limit':24, 'offset':0, 'items':[
    {'id':'preview-listing', 'kind':'found', 'title':'Чёрный рюкзак', 'category':'bags',
      'public_region':'Санкт-Петербург', 'event_at':'2026-09-12T12:00:00Z', 'media':<JsonMap>[]},
    ]});
  }
  if (request.url.path == '/v1/ads/current') return _json(null);
  if (request.url.path == '/v1/auth/request-code') return _json({'retry_after':60});
  return _json(<JsonMap>[]);
}

Future<AppController> _open(WidgetTester tester, Widget page, {double width=390, double height=844, double scale=1}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width,height);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final controller = AppController(api:BureauApiClient(baseUrl:'https://example.invalid/v1',
    tokenStore:_Tokens(), httpClient:MockClient(_handle)))
    ..state = AppSessionState.signedIn
    ..currentUser = {'id':'preview-user', 'display_name':'', 'role':'user'};
  await tester.pumpWidget(AppScope(controller:controller, child:MaterialApp(
    theme:BureauTheme.light,
    builder:(context, child) => MediaQuery(data:MediaQuery.of(context).copyWith(
      textScaler:TextScaler.linear(scale)), child:RepaintBoundary(key:_screenKey, child:child!)),
    home:page,
  )));
  await tester.runAsync(() async {
    final context = tester.element(find.byType(MaterialApp));
    await precacheImage(const AssetImage('assets/illustrations/belongings.webp'), context);
    await precacheImage(const AssetImage('assets/illustrations/return.webp'), context);
  });
  await tester.pumpAndSettle();
  addTearDown(() async { await tester.pumpWidget(const SizedBox.shrink()); controller.dispose(); });
  return controller;
}

/// Optional review output from the actual Flutter renderer, with synthetic fixtures only.
Future<void> _preview(WidgetTester tester, String name) async {
  if (!const bool.fromEnvironment('BUREAU_CAPTURE_DESIGN')) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(_screenKey));
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio:1);
    final bytes = await image.toByteData(format:ui.ImageByteFormat.png);
    image.dispose();
    final encoded = base64Encode(bytes!.buffer.asUint8List());
    for (var offset=0; offset<encoded.length; offset+=6000) {
      final end = (offset+6000).clamp(0,encoded.length).toInt();
      // ignore: avoid_print
      print('BUREAU_PREVIEW $name ${offset~/6000} ${encoded.substring(offset,end)}');
    }
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final loader=FontLoader('BureauSans');
    for (final weight in [400,500,600,700]) {
      loader.addFont(rootBundle.load('assets/fonts/BureauSans-$weight.ttf'));
    }
    await loader.load();
  });

  testWidgets('home artwork and phone typography preserve search and creation actions', (tester) async {
    await _open(tester, const UserShell());
    expect(tester.takeException(), isNull);
    expect(find.byType(BureauIllustration), findsOneWidget);
    await _preview(tester,'home-390');
    await tester.tap(find.text('Найти вещь'));
    await tester.pumpAndSettle();
    expect(tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,1);
    await tester.tap(find.text('Главная'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Я нашёл'));
    await tester.tap(find.text('Я нашёл'));
    await tester.pumpAndSettle();
    expect(tester.widget<CreateFlowPage>(find.byType(CreateFlowPage)).initialFound,isTrue);
    expect(tester.takeException(),isNull);
  });

  for (final (width,height,scale) in [(320.0,568.0,1.0),(320.0,568.0,2.0),(430.0,932.0,1.3)]) {
    testWidgets('home actions fit width $width with text scale $scale', (tester) async {
      await _open(tester, Scaffold(body:HomeView(onSearch:() {})),width:width,height:height,scale:scale);
      expect(tester.takeException(),isNull);
      for (final label in ['Найти вещь','Я потерял','Я нашёл']) {
        await tester.ensureVisible(find.text(label));
        await tester.pumpAndSettle();
        expect(find.text(label).hitTestable(),findsOneWidget);
        final bounds=tester.getRect(find.text(label));
        expect(bounds.left,greaterThanOrEqualTo(20));
        expect(bounds.right,lessThanOrEqualTo(width-20));
      }
      expect(tester.takeException(),isNull);
    });
  }

  testWidgets('sign in stays usable with keyboard and does not change SMS request', (tester) async {
    final controller=await _open(tester,const AuthPage());
    await _preview(tester,'sign-in-390');
    await tester.enterText(find.byType(TextField),'+7 (999) 123-45-67');
    tester.view.viewInsets=const FakeViewPadding(bottom:300);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Получить код'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Получить код'));
    await tester.pumpAndSettle();
    expect(controller.pendingPhone,'+79991234567');
    expect(find.byType(VerifyPhonePage),findsOneWidget);
    expect(tester.takeException(),isNull);
  });

  testWidgets('intro remains scrollable on a short phone with large text', (tester) async {
    await _open(tester,const OnboardingPage(),width:320,height:568,scale:2);
    expect(tester.takeException(),isNull);
    await tester.tap(find.text('Далее'));
    await tester.pumpAndSettle();
    expect(find.text('Контакты под защитой'),findsOneWidget);
    expect(tester.takeException(),isNull);
  });

  test('primary and secondary copy and action colors keep readable contrast', () {
    double contrast(Color a, Color b) {
      final x=a.computeLuminance(), y=b.computeLuminance();
      return ((x>y ? x : y)+.05)/((x<y ? x : y)+.05);
    }
    for (final color in [BureauColors.navy,BureauColors.slate,BureauColors.muted,BureauColors.blue,BureauColors.green]) {
      expect(contrast(color,Colors.white),greaterThanOrEqualTo(4.5));
    }
  });
}
