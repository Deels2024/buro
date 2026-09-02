import 'package:bureau_nakhodok/app.dart';
import 'package:bureau_nakhodok/data/app_controller.dart';
import 'package:bureau_nakhodok/data/bureau_api_client.dart';
import 'package:bureau_nakhodok/data/screen_catalog.dart';
import 'package:bureau_nakhodok/features/user/user_app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _MemoryTokenStore implements BureauTokenStore {
  BureauTokens? tokens;
  @override
  Future<BureauTokens?> read() async => tokens;
  @override
  Future<void> write(BureauTokens? value) async => tokens = value;
}

void main() {
  test('catalog contains all approved screens', () {
    expect(userScreenSpecs, hasLength(40));
    expect(organizationScreenSpecs, hasLength(20));
    expect(adminScreenSpecs, hasLength(7));
    expect(allScreenSpecs, hasLength(67));
    expect(allScreenSpecs.map((screen) => screen.id).toSet(), hasLength(67));
  });

  testWidgets('app starts with onboarding', (tester) async {
    final controller = AppController(
      api: BureauApiClient(
        baseUrl: 'https://example.invalid/v1',
        tokenStore: _MemoryTokenStore(),
      ),
    )..state = AppSessionState.signedOut;
    await tester.pumpWidget(BureauNakhodokApp(controller: controller));
    expect(find.text('Бюро находок'), findsOneWidget);
    expect(find.text('Одна сеть для всей России'), findsOneWidget);
    expect(find.text('Далее'), findsOneWidget);
  });

  testWidgets('SMS resend stays disabled until retry-after expires', (
    tester,
  ) async {
    final controller = AppController(
      api: BureauApiClient(
        baseUrl: 'https://example.invalid/v1',
        tokenStore: _MemoryTokenStore(),
      ),
    )..pendingPhone = '+79991234567';
    await tester.pumpWidget(
      MaterialApp(
        home: AppScope(
          controller: controller,
          child: const VerifyPhonePage(initialRetryAfter: 2),
        ),
      ),
    );

    expect(find.text('Отправить повторно через 2 с'), findsOneWidget);
    expect(tester.widget<TextButton>(find.byType(TextButton)).onPressed, isNull);

    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Отправить повторно через 1 с'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Отправить код повторно'), findsOneWidget);
    expect(tester.widget<TextButton>(find.byType(TextButton)).onPressed, isNotNull);

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  test('every approved screen has an API mapping', () {
    expect(screenApiRoutes, hasLength(67));
    for (final screen in allScreenSpecs) {
      expect(apiRoutesFor(screen), isNotEmpty, reason: screen.id);
    }
  });
}
