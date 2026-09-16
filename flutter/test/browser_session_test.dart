import 'dart:async';
import 'dart:convert';

import 'package:bureau_nakhodok/data/app_controller.dart';
import 'package:bureau_nakhodok/data/bureau_api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const tokens = BureauTokens('access', 'refresh', 900);

class LegacyStore implements BureauTokenStore {
  BureauTokens? value;
  bool unavailable = false;
  int reads = 0;

  @override
  Future<BureauTokens?> read() async {
    reads++;
    if (unavailable) throw StateError('Browser storage unavailable');
    return value;
  }

  @override
  Future<void> write(BureauTokens? tokens) async {
    if (unavailable) throw StateError('Browser storage unavailable');
    value = tokens;
  }
}

http.Response response(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status);

class SessionServer {
  bool cookie = false;
  bool offline = false;
  bool expiredAccess = false;
  int smsVerifications = 0;
  int restores = 0;
  int migrations = 0;

  Future<http.Response> handle(http.Request request) async {
    if (offline) throw http.ClientException('Offline');
    final path = request.url.path;
    if (path.contains('/auth/')) {
      expect(request.headers['X-Bureau-Web-Session'], '1');
    }
    if (path.endsWith('/app/bootstrap')) return response({});
    if (path.endsWith('/auth/verify-code')) {
      smsVerifications++;
      cookie = true;
      return response(tokens.toJson());
    }
    if (path.endsWith('/auth/refresh')) {
      migrations++;
      expect(jsonDecode(request.body)['refresh_token'], 'legacy-refresh');
      expect(request.headers['X-Refresh-Operation'], 'saved-operation');
      cookie = true;
      return response(tokens.toJson());
    }
    if (path.endsWith('/auth/session')) {
      expect(request.headers['Authorization'], isNull);
      if (request.method == 'DELETE') {
        cookie = false;
        return response({'message': 'Signed out'});
      }
      restores++;
      if (!cookie) return response({'detail': 'No session'}, 401);
      expiredAccess = false;
      return response(tokens.toJson());
    }
    if (path.endsWith('/users/me') || path.endsWith('/organizations/mine')) {
      if (!cookie || expiredAccess) return response({'detail': 'Expired'}, 401);
      expect(request.headers['Authorization'], 'Bearer access');
      return response(path.endsWith('/users/me') ? {'id': 'user', 'role': 'user'} : []);
    }
    throw StateError('Unexpected request ${request.method} $path');
  }

  AppController open({LegacyStore? legacy}) => AppController(api: BureauApiClient(
    baseUrl: 'https://edinburo.ru/v1',
    tokenStore: MemoryBureauTokenStore(),
    legacyTokenStore: legacy,
    browserSession: true,
    httpClient: MockClient(handle),
  ));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('SMS login survives new controllers with no JS storage or access token', () async {
    final server = SessionServer();
    final legacy = LegacyStore()..unavailable = true;
    final first = server.open(legacy: legacy)..pendingPhone = '+79991234567';
    expect(await first.verifyCode('123456'), isTrue);
    expect(first.state, AppSessionState.signedIn);
    first.dispose();
    for (var restart = 0; restart < 3; restart++) {
      final reopened = server.open(legacy: legacy);
      expect(await reopened.api.tokenStore.read(), isNull);
      await reopened.initialize();
      expect(reopened.state, AppSessionState.signedIn);
      reopened.dispose();
    }
    expect(server.smsVerifications, 1);
    expect(legacy.reads, 0);
  });

  test('an existing encrypted session migrates without requesting SMS', () async {
    final server = SessionServer();
    final legacy = LegacyStore()..value = const BureauTokens(
      'legacy-access', 'legacy-refresh', 900, refreshOperation: 'saved-operation');
    final controller = server.open(legacy: legacy);
    await controller.initialize();
    expect(controller.state, AppSessionState.signedIn);
    expect(server.migrations, 1);
    expect(server.smsVerifications, 0);
    expect(legacy.value, isNull);
    controller.dispose();
  });

  test('expired access renews with the cookie rather than a stored refresh token', () async {
    final server = SessionServer()..cookie = true;
    final controller = server.open();
    await controller.initialize();
    server.expiredAccess = true;
    await controller.refreshIdentity();
    expect(controller.state, AppSessionState.signedIn);
    expect(server.restores, 2);
    expect(server.migrations, 0);
    controller.dispose();
  });

  test('offline startup retries the cookie without showing the SMS screen', () async {
    final server = SessionServer()..cookie = true..offline = true;
    final controller = server.open();
    await controller.initialize();
    expect(controller.state, AppSessionState.unavailable);
    server.offline = false;
    await controller.initialize();
    expect(controller.state, AppSessionState.signedIn);
    expect(server.smsVerifications, 0);
    controller.dispose();
  });

  test('explicit logout stays signed out after closing and reopening', () async {
    final server = SessionServer()..cookie = true;
    final controller = server.open();
    await controller.initialize();
    await controller.logout();
    expect(controller.state, AppSessionState.signedOut);
    controller.dispose();
    final reopened = server.open();
    await reopened.initialize();
    expect(reopened.state, AppSessionState.signedOut);
    reopened.dispose();
  });

  test('offline logout reports failure instead of pretending the cookie is cleared', () async {
    final server = SessionServer()..cookie = true;
    final controller = server.open();
    await controller.initialize();
    server.offline = true;
    await expectLater(controller.logout(), throwsA(isA<BureauApiException>()));
    expect(controller.state, AppSessionState.signedIn);
    expect(await controller.api.tokenStore.read(), isNotNull);
    controller.dispose();
  });

  test('a revoked cookie requires login', () async {
    final controller = SessionServer().open();
    await controller.initialize();
    expect(controller.state, AppSessionState.signedOut);
    controller.dispose();
  });

  test('a late restore cannot undo an explicit logout', () async {
    final pending = Completer<http.Response>();
    final started = Completer<void>();
    final api = BureauApiClient(
      baseUrl: 'https://edinburo.ru/v1', tokenStore: MemoryBureauTokenStore(),
      browserSession: true, httpClient: MockClient((request) async {
        if (request.method == 'DELETE') return response({'message': 'Signed out'});
        started.complete();
        return pending.future;
      }),
    );
    final restoring = api.restoreSession();
    await started.future;
    await api.logout();
    pending.complete(response(tokens.toJson()));
    expect(await restoring, isNull);
    expect(await api.tokenStore.read(), isNull);
    api.close();
  });
}
