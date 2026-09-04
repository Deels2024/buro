import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

typedef JsonMap = Map<String, dynamic>;

class BureauApiException implements Exception {
  BureauApiException(this.statusCode, this.detail, {this.requestId});

  final int statusCode;
  final String detail;
  final String? requestId;

  bool get isUnauthorized => statusCode == 401;
  bool get isForbidden => statusCode == 403;
  bool get isConflict => statusCode == 409;
  bool get isValidation => statusCode == 422;
  bool get isRateLimited => statusCode == 429;

  @override
  String toString() =>
      requestId == null ? detail : '$detail · запрос $requestId';
}

class BureauTokens {
  const BureauTokens(this.accessToken, this.refreshToken, this.expiresIn);

  final String accessToken;
  final String refreshToken;
  final int expiresIn;

  factory BureauTokens.fromJson(JsonMap json) => BureauTokens(
    json['access_token'] as String,
    json['refresh_token'] as String,
    (json['expires_in'] as num).toInt(),
  );

  JsonMap toJson() => {
    'access_token': accessToken,
    'refresh_token': refreshToken,
    'expires_in': expiresIn,
  };
}

abstract interface class BureauTokenStore {
  Future<BureauTokens?> read();
  Future<void> write(BureauTokens? tokens);
}

class UploadedMedia {
  const UploadedMedia({
    required this.id,
    required this.url,
    required this.mimeType,
  });

  final String id;
  final String url;
  final String mimeType;

  factory UploadedMedia.fromJson(JsonMap json) => UploadedMedia(
    id: json['id'].toString(),
    url: json['download_url']?.toString() ?? '',
    mimeType: json['mime_type']?.toString() ?? 'application/octet-stream',
  );
}

class BureauApiClient {
  BureauApiClient({
    required String baseUrl,
    required this.tokenStore,
    http.Client? httpClient,
  }) : baseUrl = baseUrl.replaceFirst(RegExp(r'/+$'), ''),
       _http = httpClient ?? http.Client();

  final String baseUrl;
  final BureauTokenStore tokenStore;
  final http.Client _http;
  Future<BureauTokens>? _refreshInFlight;

  Uri _uri(String path, [Map<String, Object?>? query]) {
    final uri = Uri.parse('$baseUrl${path.startsWith('/') ? path : '/$path'}');
    if (query == null) return uri;
    return uri.replace(
      queryParameters: {
        for (final entry in query.entries)
          if (entry.value != null && entry.value.toString().isNotEmpty)
            entry.key: entry.value.toString(),
      },
    );
  }

  Future<dynamic> request(
    String method,
    String path, {
    Object? body,
    Map<String, Object?>? query,
    bool authenticated = true,
    bool retry401 = true,
    String? idempotencyKey,
  }) async {
    final headers = <String, String>{'Accept': 'application/json'};
    if (body != null) {
      headers['Content-Type'] = 'application/json; charset=utf-8';
    }
    if (idempotencyKey != null) headers['Idempotency-Key'] = idempotencyKey;
    final tokens = await tokenStore.read();
    if (authenticated && tokens != null) {
      headers['Authorization'] = 'Bearer ${tokens.accessToken}';
    }

    late http.Response response;
    try {
      response = await _http
          .send(
            http.Request(method, _uri(path, query))
              ..headers.addAll(headers)
              ..body = body == null ? '' : jsonEncode(body),
          )
          .then(http.Response.fromStream)
          .timeout(const Duration(seconds: 30));
    } on TimeoutException {
      throw BureauApiException(
        0,
        'Сервер не ответил вовремя. Проверьте соединение.',
      );
    } on http.ClientException catch (error) {
      throw BureauApiException(
        0,
        'Не удалось подключиться к серверу: ${error.message}',
      );
    }

    if (response.statusCode == 401 &&
        authenticated &&
        retry401 &&
        tokens != null) {
      try {
        await _refresh();
      } on BureauApiException {
        await tokenStore.write(null);
        rethrow;
      }
      return request(
        method,
        path,
        body: body,
        query: query,
        authenticated: authenticated,
        retry401: false,
        idempotencyKey: idempotencyKey,
      );
    }

    final decoded = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw BureauApiException(
        response.statusCode,
        _errorDetail(decoded),
        requestId: response.headers['x-request-id'],
      );
    }
    return decoded;
  }

  dynamic _decode(String text) {
    if (text.trim().isEmpty) return null;
    try {
      return jsonDecode(text);
    } on FormatException {
      return text;
    }
  }

  String _errorDetail(dynamic decoded) {
    if (decoded is! JsonMap) return 'Ошибка API';
    final detail = decoded['detail'];
    if (detail is String) return detail;
    if (detail is List) {
      return detail
          .map(
            (item) =>
                item is JsonMap ? item['msg']?.toString() : item.toString(),
          )
          .whereType<String>()
          .join('\n');
    }
    return detail?.toString() ?? 'Ошибка API';
  }

  JsonMap _map(dynamic value) => Map<String, dynamic>.from(value as Map);
  List<JsonMap> _maps(dynamic value) =>
      (value as List).map((item) => _map(item)).toList();

  String newIdempotencyKey() {
    final bytes = List<int>.generate(24, (_) => Random.secure().nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  Future<BureauTokens> _refresh() async {
    if (_refreshInFlight != null) return _refreshInFlight!;
    final future = () async {
      final current = await tokenStore.read();
      if (current == null) throw BureauApiException(401, 'Сессия отсутствует');
      final json = _map(
        await request(
          'POST',
          '/auth/refresh',
          body: {'refresh_token': current.refreshToken},
          authenticated: false,
          retry401: false,
        ),
      );
      final tokens = BureauTokens.fromJson(json);
      await tokenStore.write(tokens);
      return tokens;
    }();
    _refreshInFlight = future;
    try {
      return await future;
    } finally {
      _refreshInFlight = null;
    }
  }

  Future<JsonMap> bootstrap() async =>
      _map(await request('GET', '/app/bootstrap', authenticated: false));

  Future<JsonMap> requestCode(String phone) async => _map(
    await request(
      'POST',
      '/auth/request-code',
      body: {'phone': phone},
      authenticated: false,
      idempotencyKey: newIdempotencyKey(),
    ),
  );

  Future<JsonMap> verifyCode(
    String phone,
    String code, {
    String? deviceName,
  }) async => _map(
    await request(
      'POST',
      '/auth/verify-code',
      body: {'phone': phone, 'code': code, 'device_name': deviceName},
      authenticated: false,
      idempotencyKey: newIdempotencyKey(),
    ),
  );

  Future<JsonMap> verifyAdmin2fa(
    String ticket,
    String code, {
    String? deviceName,
  }) async => _map(
    await request(
      'POST',
      '/auth/verify-admin-2fa',
      body: {'mfa_ticket': ticket, 'code': code, 'device_name': deviceName},
      authenticated: false,
      idempotencyKey: newIdempotencyKey(),
    ),
  );

  Future<JsonMap> me() async => _map(await request('GET', '/users/me'));
  Future<JsonMap> updateMe(String name) async =>
      _map(await request('PATCH', '/users/me', body: {'display_name': name}));

  Future<void> acceptTokens(JsonMap json) async =>
      tokenStore.write(BureauTokens.fromJson(json));

  Future<void> logout() async {
    final tokens = await tokenStore.read();
    try {
      if (tokens != null) {
        await request(
          'POST',
          '/auth/logout',
          body: {'refresh_token': tokens.refreshToken},
          idempotencyKey: newIdempotencyKey(),
        );
      }
    } finally {
      await tokenStore.write(null);
    }
  }

  Future<JsonMap> search({
    int limit = 20,
    int offset = 0,
    String? query,
    String? kind,
    String? category,
    String? region,
    DateTime? since,
  }) async => _map(
    await request(
      'GET',
      '/listings',
      authenticated: false,
      query: {
        'limit': limit,
        'offset': offset,
        'query': query,
        'kind': kind,
        'category': category,
        'region': region,
        'since': since?.toUtc().toIso8601String(),
      },
    ),
  );

  Future<JsonMap> listing(String id) async =>
      _map(await request('GET', '/listings/$id', authenticated: false));
  Future<JsonMap> managedListing(String id) async => _map(await request('GET', '/listings/$id/manage'));
  Future<List<JsonMap>> incomingClaims() async => _maps(await request('GET', '/claims/incoming'));
  Future<JsonMap> reviewClaim(String id) async => _map(await request('GET', '/claims/$id/review'));
  Future<JsonMap> claimListing(String id) async => _map(await request('GET', '/claims/$id/listing'));
  Future<List<JsonMap>> myListings() async =>
      _maps(await request('GET', '/listings/mine'));
  Future<JsonMap> createListing(JsonMap body) async => _map(
    await request(
      'POST',
      '/listings',
      body: body,
      idempotencyKey: newIdempotencyKey(),
    ),
  );
  Future<JsonMap> updateListing(String id, JsonMap body) async =>
      _map(await request('PATCH', '/listings/$id', body: body));
  Future<JsonMap> describeMedia(
    String mediaId,
    String kind, {
    String hint = '',
  }) async => _map(
    await request(
      'POST',
      '/listings/ai/describe',
      body: {'media_id': mediaId, 'kind': kind, 'user_hint': hint},
      idempotencyKey: newIdempotencyKey(),
    ),
  );
  Future<List<JsonMap>> photoSearch(
    String mediaId, {
    String? targetKind,
    String? category,
    String? region,
  }) async => _maps(
    await request(
      'POST',
      '/listings/ai/search',
      body: {
        'media_id': mediaId,
        'target_kind': targetKind,
        'category': category,
        'region': region,
        'limit': 20,
      },
      idempotencyKey: newIdempotencyKey(),
    ),
  );
  Future<List<JsonMap>> matches(String listingId) async =>
      _maps(await request('GET', '/listings/$listingId/matches'));
  Future<JsonMap> decideMatch(
    String listingId,
    String matchId,
    String status,
  ) async => _map(
    await request(
      'PATCH',
      '/listings/$listingId/matches/$matchId',
      body: {'status': status},
    ),
  );
  Future<void> rematch(String listingId) async => request(
    'POST',
    '/listings/$listingId/rematch',
    idempotencyKey: newIdempotencyKey(),
  );

  Future<UploadedMedia> uploadMedia({
    required Uint8List bytes,
    required String filename,
    required String mimeType,
    required String purpose,
    String? listingId,
    int? width,
    int? height,
    double? durationSeconds,
  }) async {
    final presigned = _map(
      await request(
        'POST',
        '/media/presign',
        body: {
          'filename': filename,
          'mime_type': mimeType,
          'size_bytes': bytes.length,
          'purpose': purpose,
        },
        idempotencyKey: newIdempotencyKey(),
      ),
    );
    final upload =
        http.Request('PUT', Uri.parse(presigned['upload_url'].toString()))
          ..headers.addAll(
            (presigned['required_headers'] as Map? ?? const {}).map(
              (key, value) => MapEntry(key.toString(), value.toString()),
            ),
          )
          ..bodyBytes = bytes;
    final uploadResponse = await _http
        .send(upload)
        .then(http.Response.fromStream)
        .timeout(const Duration(minutes: 2));
    if (uploadResponse.statusCode < 200 || uploadResponse.statusCode >= 300) {
      throw BureauApiException(
        uploadResponse.statusCode,
        'Не удалось загрузить файл',
      );
    }
    final completed = _map(
      await request(
        'POST',
        '/media/complete',
        body: {
          'object_key': presigned['object_key'],
          'mime_type': mimeType,
          'size_bytes': bytes.length,
          'sha256': sha256.convert(bytes).toString(),
          'purpose': purpose,
          'listing_id': listingId,
          'width': width,
          'height': height,
          'duration_seconds': durationSeconds,
        },
        idempotencyKey: newIdempotencyKey(),
      ),
    );
    return UploadedMedia.fromJson(completed);
  }

  Future<List<JsonMap>> myClaims() async =>
      _maps(await request('GET', '/claims/mine'));
  Future<JsonMap> claim(String id) async =>
      _map(await request('GET', '/claims/$id'));
  Future<JsonMap> claimConversation(String id) async =>
      _map(await request('GET', '/claims/$id/conversation'));
  Future<JsonMap> createClaim(String listingId, {String? matchId}) async =>
      _map(
        await request(
          'POST',
          '/claims',
          body: {'listing_id': listingId, 'match_id': matchId},
          idempotencyKey: newIdempotencyKey(),
        ),
      );
  Future<JsonMap> saveClaimAnswers(
    String id,
    Map<String, String> answers,
  ) async => _map(
    await request('PUT', '/claims/$id/answers', body: {'answers': answers}),
  );
  Future<JsonMap> addEvidence(
    String id,
    UploadedMedia media,
    String type, {
    String note = '',
  }) async => _map(
    await request(
      'POST',
      '/claims/$id/evidence',
      body: {'media_id': media.id, 'evidence_type': type, 'note': note},
      idempotencyKey: newIdempotencyKey(),
    ),
  );
  Future<JsonMap> submitClaim(String id) async => _map(
    await request(
      'POST',
      '/claims/$id/submit',
      idempotencyKey: newIdempotencyKey(),
    ),
  );
  Future<JsonMap> decideClaim(
    String id,
    String decision,
    String reason,
  ) async => _map(
    await request(
      'POST',
      '/claims/$id/decision',
      body: {'decision': decision, 'reason': reason},
      idempotencyKey: newIdempotencyKey(),
    ),
  );
  Future<JsonMap> appealClaim(String id, String reason) async => _map(
    await request(
      'POST',
      '/claims/$id/appeal',
      body: {'reason': reason},
      idempotencyKey: newIdempotencyKey(),
    ),
  );
  Future<JsonMap> setContactConsent(String id, bool consent) async => _map(
    await request(
      'PUT',
      '/claims/$id/contact-consent',
      body: {'consent': consent},
    ),
  );
  Future<JsonMap> contacts(String id) async =>
      _map(await request('GET', '/claims/$id/contacts'));
  Future<JsonMap> createHandover(
    String id,
    String method,
    String place, {
    DateTime? scheduledAt,
  }) async => _map(
    await request(
      'POST',
      '/claims/$id/handover',
      body: {
        'method': method,
        'place': place,
        'scheduled_at': scheduledAt?.toUtc().toIso8601String(),
      },
      idempotencyKey: newIdempotencyKey(),
    ),
  );
  Future<JsonMap> handover(String id) async =>
      _map(await request('GET', '/claims/$id/handover'));
  Future<JsonMap> regenerateHandover(String id) async => _map(
    await request(
      'POST',
      '/claims/$id/handover/regenerate',
      idempotencyKey: newIdempotencyKey(),
    ),
  );
  Future<JsonMap> scanHandover(String token, {String? claimId}) async => _map(
    await request(
      'POST',
      '/claims/handover/scan',
      body: {'token': token, if (claimId != null) 'claim_id': claimId},
      idempotencyKey: newIdempotencyKey(),
    ),
  );

  Future<List<JsonMap>> chatMessages(String conversationId) async =>
      _maps(await request('GET', '/chat/$conversationId/messages'));
  Future<JsonMap> sendChatMessage(
    String conversationId,
    String body, {
    List<String> attachments = const [],
  }) async => _map(
    await request(
      'POST',
      '/chat/$conversationId/messages',
      body: {'body': body, 'attachment_ids': attachments},
      idempotencyKey: newIdempotencyKey(),
    ),
  );
  Future<WebSocketChannel> connectChat(String conversationId) async {
    final ticket = _map(await request('POST', '/chat/$conversationId/ticket'));
    final api = Uri.parse(baseUrl);
    final ws = api.replace(
      scheme: api.scheme == 'https' ? 'wss' : 'ws',
      path: '${api.path}/chat/$conversationId/ws',
      queryParameters: {'ticket': ticket['ticket'].toString()},
    );
    return WebSocketChannel.connect(ws);
  }

  Future<List<JsonMap>> notifications({int limit = 50}) async => _maps(
    await request('GET', '/users/me/notifications', query: {'limit': limit}),
  );
  Future<void> readAllNotifications() async =>
      request('PUT', '/users/me/notifications/read-all');
  Future<JsonMap> readNotification(String id) async =>
      _map(await request('PUT', '/users/me/notifications/$id/read'));
  Future<List<JsonMap>> savedListings() async =>
      _maps(await request('GET', '/users/me/saved'));
  Future<void> saveListing(String id) async =>
      request('PUT', '/users/me/saved/$id');
  Future<void> unsaveListing(String id) async =>
      request('DELETE', '/users/me/saved/$id');
  Future<List<JsonMap>> sessions() async =>
      _maps(await request('GET', '/users/me/sessions'));
  Future<void> revokeSession(String id) async =>
      request('DELETE', '/users/me/sessions/$id');
  Future<JsonMap> registerDevice(JsonMap body) async =>
      _map(await request('PUT', '/users/me/devices', body: body));
  Future<void> unregisterDevice(String id) async =>
      request('DELETE', '/users/me/devices/$id');
  Future<void> deleteAccount() async =>
      request('DELETE', '/users/me', body: {'confirmation': 'УДАЛИТЬ'});

  Future<JsonMap?> currentAd(String placement) async {
    final value = await request(
      'GET',
      '/ads/current',
      query: {'placement': placement},
      authenticated: false,
    );
    return value == null ? null : _map(value);
  }

  Future<void> trackAd(
    String campaignId,
    String event,
    String placement,
  ) async => request(
    'POST',
    '/ads/events',
    body: {
      'campaign_id': campaignId,
      'event_type': event,
      'placement': placement,
      'tracking_consent': false,
      'context': <String, dynamic>{},
    },
    authenticated: false,
    idempotencyKey: newIdempotencyKey(),
  );

  Future<List<JsonMap>> organizations() async =>
      _maps(await request('GET', '/organizations/mine'));
  Future<JsonMap> createOrganization(
    String name,
    String inn, {
    String? ogrn,
  }) async => _map(
    await request(
      'POST',
      '/organizations',
      body: {'name': name, 'inn': inn, 'ogrn': ogrn},
      idempotencyKey: newIdempotencyKey(),
    ),
  );
  Future<JsonMap> organization(String id) async =>
      _map(await request('GET', '/organizations/$id'));
  Future<JsonMap> organizationDashboard(String id) async =>
      _map(await request('GET', '/organizations/$id/dashboard'));
  Future<List<JsonMap>> inventory(String id, {String? status}) async => _maps(
    await request(
      'GET',
      '/organizations/$id/inventory',
      query: {'status': status, 'limit': 100},
    ),
  );
  Future<List<JsonMap>> organizationClaims(String id) async => _maps(
    await request('GET', '/organizations/$id/claims', query: {'limit': 100}),
  );
  Future<List<JsonMap>> branches(String id) async =>
      _maps(await request('GET', '/organizations/$id/branches'));
  Future<JsonMap> createBranch(String id, JsonMap body) async => _map(
    await request(
      'POST',
      '/organizations/$id/branches',
      body: body,
      idempotencyKey: newIdempotencyKey(),
    ),
  );
  Future<List<JsonMap>> team(String id) async =>
      _maps(await request('GET', '/organizations/$id/team'));
  Future<JsonMap> inviteMember(String id, String phone, String role) async =>
      _map(
        await request(
          'POST',
          '/organizations/$id/team/invite',
          body: {'phone': phone, 'role': role},
          idempotencyKey: newIdempotencyKey(),
        ),
      );
  Future<JsonMap> bulkImport(String id, List<JsonMap> items) async => _map(
    await request(
      'POST',
      '/organizations/$id/bulk-import',
      body: {'items': items},
      idempotencyKey: newIdempotencyKey(),
    ),
  );
  Future<JsonMap> organizationAnalytics(String id) async =>
      _map(await request('GET', '/organizations/$id/analytics'));
  Future<JsonMap> updateOrganizationSettings(
    String id,
    bool apiEnabled,
  ) async => _map(
    await request(
      'PATCH',
      '/organizations/$id/settings',
      body: {'api_enabled': apiEnabled},
    ),
  );
  Future<List<JsonMap>> apiKeys(String id) async =>
      _maps(await request('GET', '/organizations/$id/api-keys'));
  Future<JsonMap> createApiKey(
    String id,
    String name,
    List<String> permissions,
  ) async => _map(
    await request(
      'POST',
      '/organizations/$id/api-keys',
      body: {'name': name, 'permissions': permissions, 'expires_at': null},
      idempotencyKey: newIdempotencyKey(),
    ),
  );
  Future<void> revokeApiKey(String id, String keyId) async =>
      request('DELETE', '/organizations/$id/api-keys/$keyId');
  Future<List<JsonMap>> webhooks(String id) async =>
      _maps(await request('GET', '/organizations/$id/webhooks'));
  Future<JsonMap> createWebhook(
    String id,
    String name,
    String url,
    List<String> events,
  ) async => _map(
    await request(
      'POST',
      '/organizations/$id/webhooks',
      body: {'name': name, 'url': url, 'events': events},
      idempotencyKey: newIdempotencyKey(),
    ),
  );
  Future<void> deleteWebhook(String id, String webhookId) async =>
      request('DELETE', '/organizations/$id/webhooks/$webhookId');
  Future<JsonMap> testWebhook(String id, String webhookId) async => _map(
    await request(
      'POST',
      '/organizations/$id/webhooks/$webhookId/test',
      idempotencyKey: newIdempotencyKey(),
    ),
  );

  Future<List<JsonMap>> supportTickets() async =>
      _maps(await request('GET', '/support/tickets'));
  Future<JsonMap> createSupportTicket(JsonMap body) async => _map(
    await request(
      'POST',
      '/support/tickets',
      body: body,
      idempotencyKey: newIdempotencyKey(),
    ),
  );
  Future<List<JsonMap>> supportMessages(String id) async =>
      _maps(await request('GET', '/support/tickets/$id/messages'));
  Future<JsonMap> sendSupportMessage(String id, String body) async => _map(
    await request(
      'POST',
      '/support/tickets/$id/messages',
      body: {'body': body, 'attachment_ids': <String>[], 'internal': false},
      idempotencyKey: newIdempotencyKey(),
    ),
  );

  Future<dynamic> adminGet(String path, {Map<String, Object?>? query}) =>
      request('GET', '/admin$path', query: query);
  Future<dynamic> adminPost(String path, {Object? body}) => request(
    'POST',
    '/admin$path',
    body: body,
    idempotencyKey: newIdempotencyKey(),
  );
  Future<dynamic> adminPatch(String path, Object body) =>
      request('PATCH', '/admin$path', body: body);
  Future<dynamic> adminPut(String path, Object body) =>
      request('PUT', '/admin$path', body: body);

  void close() => _http.close();
}
