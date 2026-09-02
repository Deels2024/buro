import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'bureau_api_client.dart';

class SecureBureauTokenStore implements BureauTokenStore {
  SecureBureauTokenStore({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            aOptions: AndroidOptions(),
            iOptions: IOSOptions(
              accessibility: KeychainAccessibility.first_unlock_this_device,
            ),
          );

  static const _key = 'bureau.auth.tokens.v1';
  final FlutterSecureStorage _storage;
  BureauTokens? _cached;
  bool _loaded = false;

  // flutter_secure_storage deliberately rejects plain HTTP on web. Keep an
  // in-memory session for temporary IP-based access instead of weakening token
  // protection by persisting credentials in localStorage.
  bool get _usesMemoryOnlyWebSession =>
      kIsWeb && Uri.base.scheme != 'https' && Uri.base.host != 'localhost';

  @override
  Future<BureauTokens?> read() async {
    if (_loaded) return _cached;
    _loaded = true;
    if (_usesMemoryOnlyWebSession) return null;
    final raw = await _storage.read(key: _key);
    if (raw == null || raw.isEmpty) return null;
    try {
      _cached = BureauTokens.fromJson(
        Map<String, dynamic>.from(jsonDecode(raw) as Map),
      );
    } on FormatException {
      await _storage.delete(key: _key);
    }
    return _cached;
  }

  @override
  Future<void> write(BureauTokens? tokens) async {
    _loaded = true;
    _cached = tokens;
    if (_usesMemoryOnlyWebSession) return;
    if (tokens == null) {
      await _storage.delete(key: _key);
    } else {
      await _storage.write(key: _key, value: jsonEncode(tokens.toJson()));
    }
  }
}
