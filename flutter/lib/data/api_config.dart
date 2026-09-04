import 'package:flutter/foundation.dart';

class ApiConfig {
  const ApiConfig._();
  static String get baseUrl => kIsWeb
      ? Uri.base.resolve('/v1').toString()
      : const String.fromEnvironment('BUREAU_API_URL', defaultValue: 'https://edinburo.ru/v1');
}
