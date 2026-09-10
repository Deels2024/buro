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
    if (_loaded && (!kIsWeb || _usesMemoryOnlyWebSession)) return _cached;
    if (_usesMemoryOnlyWebSession) return null;
    final raw = await _storage.read(key: _key);
    // The web plugin also returns null when decryption fails. An existing
    // encrypted record is not a logout; leave it intact and allow a retry.
    if (raw == null) {
      if (await _storage.containsKey(key: _key)) {
        throw StateError('Saved session could not be read');
      }
      _loaded = true;
      return null;
    }
    _cached = BureauTokens.fromJson(
      Map<String, dynamic>.from(jsonDecode(raw) as Map),
    );
    _loaded = true;
    return _cached;
  }

  @override
  Future<void> write(BureauTokens? tokens) async {
    if (!_usesMemoryOnlyWebSession) {
      if (tokens == null) {
        await _storage.delete(key: _key);
      } else {
        await _storage.write(key: _key, value: jsonEncode(tokens.toJson()));
      }
    }
    // Never expose a successful in-memory login before persistence succeeds.
    _cached = tokens;
    _loaded = true;
  }
}
