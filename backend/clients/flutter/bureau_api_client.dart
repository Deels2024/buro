import 'dart:convert';
import 'dart:io';

class BureauApiException implements Exception {
  BureauApiException(this.statusCode, this.detail, {this.requestId});
  final int statusCode;
  final String detail;
  final String? requestId;

  @override
  String toString() => 'BureauApiException($statusCode, $detail, requestId: $requestId)';
}

class BureauTokens {
  const BureauTokens({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresIn,
  });

  final String accessToken;
  final String refreshToken;
  final int expiresIn;

  factory BureauTokens.fromJson(Map<String, dynamic> json) => BureauTokens(
        accessToken: json['access_token'] as String,
        refreshToken: json['refresh_token'] as String,
        expiresIn: json['expires_in'] as int,
      );
}

abstract interface class BureauTokenStore {
  Future<BureauTokens?> read();
  Future<void> write(BureauTokens? tokens);
}

class BureauApiClient {
  BureauApiClient({
    required this.baseUrl,
    required this.tokenStore,
    HttpClient? httpClient,
  }) : _http = httpClient ?? HttpClient();

  final String baseUrl;
  final BureauTokenStore tokenStore;
  final HttpClient _http;
  Future<BureauTokens>? _refreshInFlight;

  Future<dynamic> request(
    String method,
    String path, {
    Object? body,
    bool authenticated = true,
    bool retry401 = true,
    String? idempotencyKey,
  }) async {
    final request = await _http.openUrl(method, Uri.parse('$baseUrl$path'));
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    if (body != null) request.headers.contentType = ContentType.json;
    if (idempotencyKey != null) request.headers.set('Idempotency-Key', idempotencyKey);
    final tokens = await tokenStore.read();
    if (authenticated && tokens != null) {
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer ${tokens.accessToken}');
    }
    if (body != null) request.write(jsonEncode(body));
    final response = await request.close();
    final text = await utf8.decoder.bind(response).join();
    if (response.statusCode == 401 && authenticated && retry401 && tokens != null) {
      await _refresh();
      return request(
        method,
        path,
        body: body,
        authenticated: authenticated,
        retry401: false,
        idempotencyKey: idempotencyKey,
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final decoded = text.isEmpty ? <String, dynamic>{} : jsonDecode(text) as Map<String, dynamic>;
      throw BureauApiException(
        response.statusCode,
        decoded['detail']?.toString() ?? 'Ошибка API',
        requestId: response.headers.value('X-Request-ID'),
      );
    }
    if (text.isEmpty) return null;
    return jsonDecode(text);
  }

  Future<BureauTokens> _refresh() async {
    final existing = _refreshInFlight;
    if (existing != null) return existing;
    final future = () async {
      final current = await tokenStore.read();
      if (current == null) throw BureauApiException(401, 'Сессия отсутствует');
      final json = await request(
        'POST',
        '/auth/refresh',
        body: {'refresh_token': current.refreshToken},
        authenticated: false,
        retry401: false,
      ) as Map<String, dynamic>;
      final next = BureauTokens.fromJson(json);
      await tokenStore.write(next);
      return next;
    }();
    _refreshInFlight = future;
    try {
      return await future;
    } finally {
      _refreshInFlight = null;
    }
  }

  Future<Map<String, dynamic>> bootstrap() async =>
      await request('GET', '/app/bootstrap', authenticated: false) as Map<String, dynamic>;

  Future<Map<String, dynamic>> requestCode(String phone) async =>
      await request('POST', '/auth/request-code', body: {'phone': phone}, authenticated: false)
          as Map<String, dynamic>;

  Future<Map<String, dynamic>> verifyCode(String phone, String code, {String? deviceName}) async =>
      await request(
        'POST',
        '/auth/verify-code',
        body: {'phone': phone, 'code': code, 'device_name': deviceName},
        authenticated: false,
      ) as Map<String, dynamic>;

  Future<Map<String, dynamic>> me() async =>
      await request('GET', '/users/me') as Map<String, dynamic>;

  Future<Map<String, dynamic>> listings({int limit = 20, int offset = 0, String? query}) async {
    final params = {'limit': '$limit', 'offset': '$offset', if (query != null) 'query': query};
    final uri = Uri(path: '/listings', queryParameters: params);
    return await request('GET', uri.toString(), authenticated: false) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> createListing(Map<String, dynamic> payload, String idempotencyKey) async =>
      await request('POST', '/listings', body: payload, idempotencyKey: idempotencyKey)
          as Map<String, dynamic>;

  Future<List<dynamic>> matches(String listingId) async =>
      await request('GET', '/listings/$listingId/matches') as List<dynamic>;

  Future<Map<String, dynamic>> createClaim(Map<String, dynamic> payload, String idempotencyKey) async =>
      await request('POST', '/claims', body: payload, idempotencyKey: idempotencyKey)
          as Map<String, dynamic>;

  Future<List<dynamic>> notifications() async =>
      await request('GET', '/users/me/notifications') as List<dynamic>;

  Future<List<dynamic>> supportTickets() async =>
      await request('GET', '/support/tickets') as List<dynamic>;

  Future<Map<String, dynamic>> createSupportTicket(
    Map<String, dynamic> payload,
    String idempotencyKey,
  ) async =>
      await request('POST', '/support/tickets', body: payload, idempotencyKey: idempotencyKey)
          as Map<String, dynamic>;

  void close() => _http.close(force: true);
}
