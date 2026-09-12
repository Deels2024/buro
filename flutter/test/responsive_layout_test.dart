import 'package:bureau_nakhodok/core/api_widgets.dart';
import 'package:bureau_nakhodok/core/production_widgets.dart';
import 'package:bureau_nakhodok/core/theme.dart';
import 'package:bureau_nakhodok/core/widgets.dart';
import 'package:bureau_nakhodok/data/app_controller.dart';
import 'package:bureau_nakhodok/data/bureau_api_client.dart';
import 'package:bureau_nakhodok/features/organization/organization_app.dart';
import 'package:bureau_nakhodok/features/user/user_app.dart';
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

Widget _app(Widget page, {double textScale = 1}) => MaterialApp(
  theme: BureauTheme.light,
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
    child: child!,
  ),
  home: page,
);

void _viewport(WidgetTester tester, Size size) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  for (final width in [320.0, 390.0]) {
    testWidgets('long actions and features fit at $width with large text', (tester) async {
      _viewport(tester, Size(width, 740));
      const action = 'Подтвердить передачу владельцу';
      const feature = 'Красная молния на внутреннем кармане и длинный ремень через плечо';
      await tester.pumpWidget(_app(BureauPage(
        title: 'Вещь',
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          ApiButton(label: action, icon: Icons.check, onPressed: () async {}),
          const SizedBox(height: 20),
          const Wrap(children: [BureauPill(feature)]),
        ]),
      ), textScale: 2));
      expect(tester.takeException(), isNull);
      for (final label in [action, feature]) {
        final bounds = tester.getRect(find.text(label));
        expect(bounds.left, greaterThanOrEqualTo(20));
        expect(bounds.right, lessThanOrEqualTo(width - 20));
      }
      expect(tester.getRect(find.byType(FilledButton)).contains(
        tester.getRect(find.text(action)).bottomRight), isTrue);
    });
  }

  testWidgets('footer and form keep the same edges on a wide screen', (tester) async {
    _viewport(tester, const Size(1200, 800));
    const formKey = Key('form');
    const actionKey = Key('action');
    await tester.pumpWidget(_app(BureauPage(
      title: 'Форма',
      bottom: FilledButton(key: actionKey, onPressed: () {}, child: const Text('Продолжить')),
      child: const SizedBox(key: formKey, width: double.infinity, height: 100),
    )));
    final form = tester.getRect(find.byKey(formKey));
    final action = tester.getRect(find.byKey(actionKey));
    expect(action.left, form.left);
    expect(action.right, form.right);
    expect(tester.takeException(), isNull);
  });

  testWidgets('creation choices remain reachable on a short narrow screen', (tester) async {
    _viewport(tester, const Size(320, 480));
    await tester.pumpWidget(_app(const Scaffold(body: CreateEntryView()), textScale: 1.6));
    expect(tester.takeException(), isNull);
    final lost = tester.getRect(find.byType(SoftCard).at(0));
    final found = tester.getRect(find.byType(SoftCard).at(1));
    expect(found.top, greaterThan(lost.bottom));
    await tester.ensureVisible(find.text('Я нашёл'));
    await tester.pumpAndSettle();
    expect(find.text('Я нашёл').hitTestable(), findsOneWidget);
    await tester.ensureVisible(find.byType(NoticeCard));
    await tester.pumpAndSettle();
    expect(find.byType(NoticeCard).hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('gallery fills a phone and wraps each attachment', (tester) async {
    _viewport(tester, const Size(390, 800));
    await tester.pumpWidget(_app(const BureauPage(
      title: 'Фото',
      child: PhotoGallery(media: [
        {'mime_type': 'application/pdf', 'status': 'ready'},
        {'mime_type': 'application/pdf', 'status': 'ready'},
      ]),
    )));
    final first = tester.getRect(find.byType(Card).at(0));
    final second = tester.getRect(find.byType(Card).at(1));
    expect(first.width, 350);
    expect(second.left, first.left);
    expect(second.top, greaterThan(first.bottom));
    expect(tester.takeException(), isNull);
  });

  testWidgets('branch dialog fields remain reachable above the keyboard', (tester) async {
    _viewport(tester, const Size(390, 700));
    addTearDown(tester.view.resetViewInsets);
    final controller = AppController(api: BureauApiClient(
      baseUrl: 'https://example.invalid/v1', tokenStore: _Tokens(),
      httpClient: MockClient((_) async => http.Response('[]', 200)),
    ));
    await tester.pumpWidget(AppScope(controller: controller, child: _app(
      const OrganizationBranchesPage(organization: {'id': 'org-1', 'name': 'Бюро'}),
      textScale: 1.5,
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.add_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(TextField).last);
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byType(TextField).last);
    await tester.pumpAndSettle();
    expect(find.byType(TextField).last.hitTestable(), findsOneWidget);
    expect(find.text('Добавить').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Отмена'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets('public listing renders each photo once', (tester) async {
    _viewport(tester, const Size(390, 844));
    final controller = AppController(api: BureauApiClient(
      baseUrl: 'https://example.invalid/v1', tokenStore: _Tokens(),
    ));
    await tester.pumpWidget(AppScope(controller: controller, child: _app(const ItemDetailPage(listing: {
      'id': 'listing-1', 'owner_id': 'owner-1', 'kind': 'found', 'status': 'active',
      'title': 'Рюкзак', 'description': 'Чёрный рюкзак', 'category': 'bags',
      'public_region': 'Санкт-Петербург', 'event_at': '2026-09-12T12:00:00Z',
      'media': [{'mime_type': 'image/jpeg', 'download_url': 'https://example.invalid/photo.jpg', 'status': 'ready'}],
    }))));
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });
}
