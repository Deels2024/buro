import 'dart:convert';

import 'package:bureau_nakhodok/core/theme.dart';
import 'package:bureau_nakhodok/data/app_controller.dart';
import 'package:bureau_nakhodok/data/bureau_api_client.dart';
import 'package:bureau_nakhodok/features/user/access_help.dart';
import 'package:bureau_nakhodok/features/user/create_flow.dart';
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

http.Response json(Object value, [int status = 200]) => http.Response(
  jsonEncode(value),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

const item = <String, dynamic>{
  'id': 'listing',
  'owner_id': 'holder',
  'kind': 'found',
  'title': 'Рюкзак',
  'description': 'Синий рюкзак',
  'category': 'bags',
  'status': 'active',
  'public_region': 'Москва',
  'media': [],
  'public_features': [],
};

Future<void> openPage(
  WidgetTester tester,
  Widget page,
  Future<http.Response> Function(http.Request) handler,
) async {
  tester.view.physicalSize = const Size(1100, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final controller =
      AppController(
          api: BureauApiClient(
            baseUrl: 'https://test.invalid/v1',
            tokenStore: _Tokens(),
            httpClient: MockClient(handler),
          ),
        )
        ..state = AppSessionState.signedIn
        ..currentUser = {'id': 'viewer'};
  await tester.pumpWidget(
    AppScope(
      controller: controller,
      child: MaterialApp(
        theme: BureauTheme.light,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () =>
                  Navigator.of(context)
                      .push(MaterialPageRoute<void>(builder: (_) => page)),
              child: const Text('Открыть'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Открыть'));
  await tester.pumpAndSettle();
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });
}

Future<void> next(WidgetTester tester) async {
  await tester.tap(find.text('Продолжить'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'back and preview edits preserve description and place; closing asks before discarding',
    (tester) async {
      var requests = 0;
      await openPage(tester, const CreateFlowPage(initialFound: false), (
        _,
      ) async {
        requests++;
        return json({});
      });
      expect(
        find.text(
          'Пропажу можно опубликовать без фото и дополнить фотографией позже.',
        ),
        findsOneWidget,
      );
      await next(tester);
      await tester.enterText(find.byType(TextField).at(0), 'Тестовый рюкзак');
      await tester.enterText(
        find.byType(TextField).at(1),
        'Описание тестовой пропажи для проверки возврата.',
      );
      await next(tester);
      await tester.enterText(find.byType(TextField).first, 'Санкт-Петербург');
      await next(tester);
      expect(find.text('Тестовый рюкзак'), findsOneWidget);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        'Санкт-Петербург',
      );
      await next(tester);
      await tester.ensureVisible(find.text('Изменить описание'));
      await tester.tap(find.text('Изменить описание'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        'Тестовый рюкзак',
      );
      await tester.tap(find.byTooltip('Закрыть форму'));
      await tester.pumpAndSettle();
      expect(find.text('Выйти из формы?'), findsOneWidget);
      await tester.tap(find.text('Продолжить заполнение'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        'Тестовый рюкзак',
      );
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Добавьте фото потерянной вещи'), findsOneWidget);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Выйти без сохранения'));
      await tester.pumpAndSettle();
      expect(find.text('Открыть'), findsOneWidget);
      expect(requests, 0); // Navigating and editing never publishes a listing.
    },
  );

  testWidgets(
    'saved state loads from server and a tap removes an existing bookmark',
    (tester) async {
      final methods = <String>[];
      await openPage(tester, const ItemDetailPage(listing: item), (
        request,
      ) async {
        methods.add(request.method);
        return request.method == 'GET' ? json([item]) : json({'message': 'ok'});
      });
      expect(find.byTooltip('Удалить из сохранённого'), findsOneWidget);
      expect(find.text('Сумки и рюкзаки'), findsOneWidget);
      await tester.tap(find.byTooltip('Удалить из сохранённого'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Сохранить'), findsOneWidget);
      expect(methods, ['GET', 'DELETE']);
    },
  );

  testWidgets(
    'failed swipe keeps a saved card; successful swipe shows empty state',
    (tester) async {
      var fail = true;
      await openPage(
        tester,
        const SavedPage(),
        (request) async => request.method == 'GET'
            ? json([item])
            : fail
            ? json({'detail': 'Ошибка сети'}, 503)
            : json({'message': 'ok'}),
      );
      await tester.drag(find.byKey(const ValueKey('listing')), const Offset(-1000, 0));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('listing')), findsOneWidget);
      fail = false;
      await tester.drag(find.byKey(const ValueKey('listing')), const Offset(-1000, 0));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('listing')), findsNothing);
      expect(find.text('Сохранённых публикаций пока нет.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('support notification opens its ticket after marking it read', (
    tester,
  ) async {
    var read = false;
    await openPage(tester, const NotificationsPage(), (request) async {
      final path = request.url.path;
      if (path.endsWith('/notifications')) {
        return json([
          {
            'id': 'note',
            'kind': 'support_reply',
            'title': 'Ответ поддержки',
            'body': 'Есть ответ',
            'data': {'ticket_id': 'ticket'},
          },
        ]);
      }
      if (path.endsWith('/read')) {
        read = true;
        return json({});
      }
      if (path.endsWith('/tickets/ticket')) {
        return json({
          'id': 'ticket',
          'subject': 'Помощь со входом',
          'status': 'open',
        });
      }
      if (path.endsWith('/messages')) return json([]);
      return json({});
    });
    await tester.tap(find.text('Ответ поддержки'));
    await tester.pumpAndSettle();
    expect(read, isTrue);
    expect(find.byType(SupportChatPage), findsOneWidget, reason: tester.widgetList<Text>(find.byType(Text)).map((t) => t.data).join(' | '));
    expect(find.text('Помощь со входом'), findsOneWidget);
    expect(find.byType(SupportChatPage), findsOneWidget);
  });

  testWidgets(
    'login exposes readable documents and an unauthenticated help form',
    (tester) async {
      await openPage(tester, const AuthPage(), (_) async => json({}));
      await tester.ensureVisible(find.text('Правила сервиса'));
      await tester.tap(find.text('Правила сервиса'));
      await tester.pumpAndSettle();
      expect(find.byType(ServiceDocumentPage), findsOneWidget);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Не получается войти?'));
      await tester.tap(find.text('Не получается войти?'));
      await tester.pumpAndSettle();
      expect(find.byType(GuestSupportPage), findsOneWidget);
    },
  );
}
