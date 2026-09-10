import 'dart:async';
import 'dart:convert';

import 'package:bureau_nakhodok/app.dart';
import 'package:bureau_nakhodok/data/app_controller.dart';
import 'package:bureau_nakhodok/data/bureau_api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const oldTokens = BureauTokens('old-access', 'old-refresh', 900);
const newTokens = BureauTokens('new-access', 'new-refresh', 900);

class SavedTokens implements BureauTokenStore {
  SavedTokens([this.tokens = oldTokens]);
  BureauTokens? tokens;
  bool unavailable = false;

  @override
  Future<BureauTokens?> read() async {
    if (unavailable) throw StateError('Storage unavailable');
    return tokens;
  }

  @override
  Future<void> write(BureauTokens? value) async => tokens = value;
}

http.Response jsonResponse(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status,
        headers: {'content-type': 'application/json'});

BureauApiClient client(SavedTokens store,
        Future<http.Response> Function(http.Request) handler) =>
    BureauApiClient(
      baseUrl: 'https://example.invalid/v1',
      tokenStore: store,
      httpClient: MockClient(handler),
    );

void main() {
  test('SMS calls do not depend on reading old credentials', () async {
    final saved = SavedTokens()..unavailable = true;
    var calls = 0;
    final api = client(saved, (request) async {
      calls++;
      return jsonResponse({'expires_in': 300, 'retry_after': 60});
    });
    await api.bootstrap();
    await api.requestCode('+79991234567');
    await api.verifyCode('+79991234567', '123456');
    expect(calls, 3);
    api.close();
  });

  test('an unrelated 401 never erases persisted credentials', () async {
    final saved = SavedTokens();
    final controller = AppController(api: client(saved, (request) async {
      if (request.url.path.endsWith('/app/bootstrap')) return jsonResponse({});
      if (request.url.path.endsWith('/auth/refresh')) return jsonResponse(newTokens.toJson());
      return jsonResponse({'detail': 'Upstream rejected request'}, 401);
    }));
    await controller.initialize();
    expect(controller.state, AppSessionState.unavailable);
    expect(saved.tokens?.refreshToken, 'new-refresh');
    controller.dispose();
  });

  test('reopening recovers the same refresh operation after a lost response', () async {
    final saved = SavedTokens();
    String? operation;
    var refreshCalls = 0;
    Future<http.Response> handler(http.Request request) async {
      if (request.url.path.endsWith('/app/bootstrap')) return jsonResponse({});
      if (request.url.path.endsWith('/auth/refresh')) {
        refreshCalls++;
        final incoming = request.headers['X-Refresh-Operation'];
        expect(incoming, isNotNull);
        expect(saved.tokens?.refreshOperation, incoming);
        if (operation == null) {
          operation = incoming;
          throw http.ClientException('Response lost after server committed');
        }
        expect(incoming, operation);
        return jsonResponse(newTokens.toJson());
      }
      if (request.headers['Authorization'] == 'Bearer old-access') {
        return jsonResponse({'detail': 'Expired'}, 401);
      }
      if (request.url.path.endsWith('/organizations/mine')) return jsonResponse([]);
      return jsonResponse({'id': 'user-1', 'role': 'user'});
    }
    final first = AppController(api: client(saved, handler));
    await first.initialize();
    expect(first.state, AppSessionState.unavailable);
    first.dispose();
    final reopened = AppController(api: client(saved, handler));
    await reopened.initialize();
    expect(reopened.state, AppSessionState.signedIn);
    expect(refreshCalls, 2);
    expect(saved.tokens?.refreshToken, 'new-refresh');
    reopened.dispose();
  });

  test('profile outage after verification preserves the completed SMS login', () async {
    final saved = SavedTokens(null);
    var profileDown = true;
    var verificationCalls = 0;
    final controller = AppController(api: client(saved, (request) async {
      if (request.url.path.endsWith('/auth/verify-code')) {
        verificationCalls++;
        return jsonResponse(newTokens.toJson());
      }
      if (request.url.path.endsWith('/app/bootstrap')) return jsonResponse({});
      if (request.url.path.endsWith('/organizations/mine')) return jsonResponse([]);
      return profileDown ? jsonResponse({'detail': 'Unavailable'}, 503)
          : jsonResponse({'id': 'user-1', 'role': 'user'});
    }));
    controller.pendingPhone = '+79991234567';
    await expectLater(controller.verifyCode('123456'), throwsA(isA<BureauApiException>()));
    expect(controller.state, AppSessionState.unavailable);
    expect(saved.tokens?.refreshToken, 'new-refresh');
    profileDown = false;
    await controller.initialize();
    expect(controller.state, AppSessionState.signedIn);
    expect(verificationCalls, 1);
    controller.dispose();
  });

  for (final failure in [0, 429, 500, 503]) {
    test('refresh failure $failure preserves login across reopening', () async {
      final saved = SavedTokens();
      var failing = true;
      var smsCalls = 0;
      Future<http.Response> handler(http.Request request) async {
        final path = request.url.path;
        if (path.contains('request-code')) smsCalls++;
        if (path.endsWith('/app/bootstrap')) return jsonResponse({});
        if (path.endsWith('/auth/refresh')) {
          if (failing) {
            if (failure == 0) throw http.ClientException('Offline');
            return jsonResponse({'detail': 'Temporary failure'}, failure);
          }
          return jsonResponse(newTokens.toJson());
        }
        if (path.endsWith('/users/me')) {
          if (request.headers['Authorization'] == 'Bearer old-access') {
            return jsonResponse({'detail': 'Expired access token'}, 401);
          }
          return jsonResponse({'id': 'user-1', 'role': 'user'});
        }
        if (path.endsWith('/organizations/mine')) return jsonResponse([]);
        throw StateError('Unexpected request: $path');
      }

      final first = AppController(api: client(saved, handler));
      await first.initialize();
      expect(first.state, AppSessionState.unavailable);
      expect(saved.tokens?.refreshToken, 'old-refresh');
      first.dispose();

      failing = false;
      final reopened = AppController(api: client(saved, handler));
      await reopened.initialize();
      expect(reopened.state, AppSessionState.signedIn);
      expect(reopened.currentUser?['id'], 'user-1');
      expect(saved.tokens?.refreshToken, 'new-refresh');
      expect(smsCalls, 0);
      reopened.dispose();
    });
  }

  test('revoked refresh token requires a new login', () async {
    final saved = SavedTokens();
    final controller = AppController(api: client(saved, (request) async {
      if (request.url.path.endsWith('/app/bootstrap')) return jsonResponse({});
      return jsonResponse({'detail': 'Invalid session'}, 401);
    }));
    await controller.initialize();
    expect(controller.state, AppSessionState.signedOut);
    expect(saved.tokens, isNull);
    controller.dispose();
  });

  test('profile failure keeps saved tokens and can be retried', () async {
    final saved = SavedTokens();
    var failing = true;
    final controller = AppController(api: client(saved, (request) async {
      if (request.url.path.endsWith('/app/bootstrap')) return jsonResponse({});
      if (request.url.path.endsWith('/users/me')) {
        return jsonResponse({'id': 'user-1', 'role': 'user'});
      }
      if (failing) return jsonResponse({'detail': 'Unavailable'}, 503);
      return jsonResponse([]);
    }));
    await controller.initialize();
    expect(controller.state, AppSessionState.unavailable);
    expect(saved.tokens, oldTokens);
    failing = false;
    await controller.initialize();
    expect(controller.state, AppSessionState.signedIn);
    controller.dispose();
  });

  test('storage failure allows recovery instead of requesting SMS', () async {
    final saved = SavedTokens()..unavailable = true;
    final controller = AppController(api: client(saved, (request) async {
      if (request.url.path.endsWith('/organizations/mine')) return jsonResponse([]);
      return jsonResponse({'id': 'user-1', 'role': 'user'});
    }));
    await controller.initialize();
    expect(controller.state, AppSessionState.unavailable);
    saved.unavailable = false;
    await controller.initialize();
    expect(controller.state, AppSessionState.signedIn);
    expect(saved.tokens, oldTokens);
    controller.dispose();
  });

  test('explicit logout clears the saved login', () async {
    final saved = SavedTokens();
    var logoutCalls = 0;
    final controller = AppController(api: client(saved, (request) async {
      expect(request.url.path, '/v1/auth/logout');
      logoutCalls++;
      return jsonResponse({'message': 'Signed out'});
    }));
    await controller.logout();
    expect(logoutCalls, 1);
    expect(saved.tokens, isNull);
    expect(controller.state, AppSessionState.signedOut);
    controller.dispose();
  });

  test('a late 401 reuses tokens already refreshed by another request', () async {
    final saved = SavedTokens();
    final first401 = Completer<http.Response>();
    final late401 = Completer<http.Response>();
    var oldRequests = 0;
    var refreshCalls = 0;
    final api = client(saved, (request) async {
      if (request.url.path.endsWith('/auth/refresh')) {
        refreshCalls++;
        return jsonResponse(newTokens.toJson());
      }
      if (request.headers['Authorization'] == 'Bearer old-access') {
        oldRequests++;
        return oldRequests == 1 ? first401.future : late401.future;
      }
      return jsonResponse({'id': 'user-1'});
    });
    final first = api.me();
    final second = api.me();
    await Future<void>.delayed(Duration.zero);
    expect(oldRequests, 2);
    first401.complete(jsonResponse({'detail': 'Expired'}, 401));
    await first;
    late401.complete(jsonResponse({'detail': 'Expired'}, 401));
    await second;
    expect(refreshCalls, 1);
    expect(saved.tokens?.refreshToken, 'new-refresh');
    api.close();
  });

  testWidgets('startup failure offers reconnect without an SMS form', (tester) async {
    final saved = SavedTokens();
    final controller = AppController(api: client(saved, (request) async =>
        jsonResponse({'detail': 'Unavailable'}, 503)));
    await controller.initialize();
    await tester.pumpWidget(BureauNakhodokApp(controller: controller));
    expect(find.text('Повторить подключение'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    await tester.tap(find.text('Повторить подключение'));
    await tester.pumpAndSettle();
    expect(find.text('Повторить подключение'), findsOneWidget);
    expect(saved.tokens, oldTokens);
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets('forgetting an unreadable login requires explicit confirmation', (tester) async {
    final saved = SavedTokens()..unavailable = true;
    final controller = AppController(api: client(saved, (request) async => jsonResponse({})));
    await controller.initialize();
    await tester.pumpWidget(BureauNakhodokApp(controller: controller));
    await tester.tap(find.text('Войти заново'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Отмена'));
    await tester.pumpAndSettle();
    expect(saved.tokens, oldTokens);
    expect(controller.state, AppSessionState.unavailable);
    await tester.tap(find.text('Войти заново'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Сбросить вход'));
    await tester.pumpAndSettle();
    expect(saved.tokens, isNull);
    expect(controller.state, AppSessionState.signedOut);
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });
}
