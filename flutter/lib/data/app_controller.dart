import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'api_config.dart';
import 'bureau_api_client.dart';
import 'secure_token_store.dart';

enum AppSessionState { initializing, signedOut, signedIn }

class AppController extends ChangeNotifier {
  AppController({BureauApiClient? api})
    : api =
          api ??
          BureauApiClient(
            baseUrl: ApiConfig.baseUrl,
            tokenStore: SecureBureauTokenStore(),
          );

  final BureauApiClient api;
  AppSessionState state = AppSessionState.initializing;
  JsonMap bootstrap = const {};
  JsonMap? currentUser;
  List<JsonMap> organizations = const [];
  JsonMap? selectedOrganization;
  String? pendingPhone;
  String? mfaTicket;
  String? lastError;
  bool initialActionHandled = false;

  bool get isSignedIn => state == AppSessionState.signedIn;
  bool get isAdmin => {'admin', 'moderator'}.contains(currentUser?['role']);
  bool get hasOrganization => organizations.isNotEmpty;

  Future<void> initialize() async {
    try {
      bootstrap = await api.bootstrap();
    } catch (error) {
      lastError = _message(error);
    }
    final tokens = await api.tokenStore.read();
    if (tokens == null) {
      state = AppSessionState.signedOut;
      notifyListeners();
      return;
    }
    try {
      await refreshIdentity();
      state = AppSessionState.signedIn;
    } on BureauApiException catch (error) {
      if (error.isUnauthorized) await api.tokenStore.write(null);
      lastError = _message(error);
      state = AppSessionState.signedOut;
    }
    notifyListeners();
  }

  Future<JsonMap> requestCode(String phone) async {
    lastError = null;
    final normalized = phone.replaceAll(RegExp(r'[^\d+]'), '');
    final result = await api.requestCode(normalized);
    pendingPhone = normalized;
    notifyListeners();
    return result;
  }

  Future<bool> verifyCode(String code) async {
    if (pendingPhone == null) {
      throw BureauApiException(422, 'Сначала запросите SMS-код');
    }
    final result = await api.verifyCode(
      pendingPhone!,
      code,
      deviceName: defaultTargetPlatform.name,
    );
    if (result['mfa_required'] == true) {
      mfaTicket = result['mfa_ticket']?.toString();
      notifyListeners();
      return false;
    }
    await _finishLogin(result);
    return true;
  }

  Future<void> verifyAdmin2fa(String code) async {
    if (mfaTicket == null) throw BureauApiException(422, 'Сессия 2FA истекла');
    final result = await api.verifyAdmin2fa(
      mfaTicket!,
      code,
      deviceName: defaultTargetPlatform.name,
    );
    mfaTicket = null;
    await _finishLogin(result);
  }

  Future<void> _finishLogin(JsonMap tokens) async {
    await api.acceptTokens(tokens);
    await refreshIdentity();
    state = AppSessionState.signedIn;
    pendingPhone = null;
    lastError = null;
    notifyListeners();
  }

  Future<void> refreshIdentity() async {
    currentUser = await api.me();
    organizations = await api.organizations();
    if (selectedOrganization == null ||
        !organizations.any(
          (item) => item['id'] == selectedOrganization?['id'],
        )) {
      selectedOrganization = organizations.isEmpty ? null : organizations.first;
    }
    notifyListeners();
  }

  void selectOrganization(JsonMap organization) {
    selectedOrganization = organization;
    notifyListeners();
  }

  Future<void> updateProfile(String name) async {
    currentUser = await api.updateMe(name);
    notifyListeners();
  }

  Future<void> logout() async {
    await api.logout();
    currentUser = null;
    organizations = const [];
    selectedOrganization = null;
    state = AppSessionState.signedOut;
    notifyListeners();
  }

  String _message(Object error) => error is BureauApiException
      ? error.toString()
      : 'Неизвестная ошибка: $error';

  @override
  void dispose() {
    api.close();
    super.dispose();
  }
}

class AppScope extends InheritedNotifier<AppController> {
  const AppScope({
    super.key,
    required AppController controller,
    required super.child,
  }) : super(notifier: controller);

  static AppController of(BuildContext context, {bool listen = true}) {
    final scope = listen
        ? context.dependOnInheritedWidgetOfExactType<AppScope>()
        : context.getInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope is missing above this context');
    return scope!.notifier!;
  }
}
