class ApiConfig {
  const ApiConfig._();

  static const baseUrl = String.fromEnvironment(
    'BUREAU_API_URL',
    defaultValue: 'http://10.0.2.2/v1',
  );
}
