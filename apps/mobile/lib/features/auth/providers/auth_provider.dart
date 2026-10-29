import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import '../../../core/storage/token_storage.dart';
import '../../../core/platform/onesignal_login.dart';
import '../models/auth_model.dart';
import '../repositories/auth_repository.dart';

enum AuthStatus { loading, authenticated, unauthenticated }

class AuthState {
  final AuthStatus status;
  final AuthUser? user;
  final String? token;
  final String? error;
  final bool userDetailsLoaded;

  const AuthState._(
      {required this.status,
      this.user,
      this.token,
      this.error,
      this.userDetailsLoaded = false});

  const AuthState.loading() : this._(status: AuthStatus.loading);

  const AuthState.unauthenticated({String? error})
      : this._(status: AuthStatus.unauthenticated, error: error);

  AuthState.authenticated(
      {required String token,
      required AuthUser user,
      bool userDetailsLoaded = true})
      : this._(
            status: AuthStatus.authenticated,
            token: token,
            user: user,
            userDetailsLoaded: userDetailsLoaded);

  bool get isAuthenticated => status == AuthStatus.authenticated;
  bool get isLoading => status == AuthStatus.loading;
}

class AuthNotifier extends StateNotifier<AuthState> {
  AuthNotifier(this._repo) : super(const AuthState.loading()) {
    _tryRestoreSession();
  }

  final AuthRepository _repo;

  /// Restaure la session depuis le localStorage (web) / SharedPreferences.
  /// Vérifie l'expiration du JWT avant de restaurer la session.
  Future<void> _tryRestoreSession() async {
    final session = await TokenStorage.getSession();
    if (session.token != null && session.email != null) {
      // Vérifier si le token est expiré avant de restaurer la session
      if (_isTokenExpired(session.token!)) {
        await TokenStorage.clear();
        state = const AuthState.unauthenticated();
        return;
      }
      final user = AuthUser(
        id: session.userId ?? 0,
        email: session.email!,
        name: session.name,
        phone: session.phone,
        role: 'user',
      );
      state = AuthState.authenticated(
          token: session.token!, user: user, userDetailsLoaded: false);
      try {
        final currentUser = await _repo.getCurrentUser();
        if (state.token == session.token) {
          state =
              AuthState.authenticated(token: session.token!, user: currentUser);
        }
      } catch (_) {
        // Conserver la session locale ; ne pas présenter les réglages par défaut
        // comme des préférences confirmées par le serveur.
      }
      // Ré-enregistre l'utilisateur dans OneSignal après redémarrage de l'app
      if (user.id != 0) _linkOneSignal(user.id);
    } else {
      state = const AuthState.unauthenticated();
    }
  }

  /// Décode le payload JWT et vérifie si le token est expiré.
  /// Retourne true si expiré ou invalide (fail-safe : on exige un nouveau login).
  static bool _isTokenExpired(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return true;
      // Base64url → base64 standard
      var payload = parts[1].replaceAll('-', '+').replaceAll('_', '/');
      final mod = payload.length % 4;
      if (mod != 0) payload = payload.padRight(payload.length + (4 - mod), '=');
      final decoded = utf8.decode(base64Decode(payload));
      final data = jsonDecode(decoded) as Map<String, dynamic>;
      final exp = data['exp'];
      if (exp == null) return false; // Pas de champ exp → on fait confiance
      // Comparer en secondes UTC
      return DateTime.now().millisecondsSinceEpoch ~/ 1000 >= (exp as int);
    } catch (_) {
      return true; // En cas de doute, forcer un nouveau login
    }
  }

  void clearError() {
    if (state.error == null) return;
    state = const AuthState.unauthenticated();
  }

  Future<void> login(String identifier, String password) async {
    state = const AuthState.loading();
    try {
      final response = await _repo.login(identifier, password);
      await _openSession(response);
    } on DioException catch (e) {
      state = AuthState.unauthenticated(error: _parseError(e));
    } catch (_) {
      state = const AuthState.unauthenticated(error: 'Erreur inattendue');
    }
  }

  Future<bool> register({
    required String name,
    required String email,
    required String phone,
    required String password,
  }) async {
    try {
      await _repo.register(
        name: name,
        email: email,
        phone: phone,
        password: password,
      );
      return true;
    } on DioException catch (e) {
      state = AuthState.unauthenticated(error: _parseError(e));
      return false;
    } catch (_) {
      state = const AuthState.unauthenticated(error: 'Erreur inattendue');
      return false;
    }
  }

  Future<bool> forgotPassword(String email) async {
    try {
      await _repo.forgotPassword(email.trim().toLowerCase());
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> resendVerification(String email) async {
    try {
      await _repo.resendVerification(email.trim().toLowerCase());
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _openSession(AuthResponse response) async {
    await TokenStorage.saveSession(
      token: response.accessToken,
      email: response.user.email,
      userId: response.user.id,
      name: response.user.name,
      phone: response.user.phone,
    );
    state = AuthState.authenticated(
      token: response.accessToken,
      user: response.user,
    );
    _linkOneSignal(response.user.id);
  }

  Future<void> logout() async {
    await _clearSession();
  }

  Future<void> deleteAccount(String password) async {
    await _repo.deleteAccount(password);
    await _clearSession();
  }

  Future<void> _clearSession() async {
    // La déconnexion de l'app ne doit jamais dépendre du SDK push. Sur PWA,
    // OneSignal peut ne pas être initialisé ou garder une Promise en attente.
    await TokenStorage.clear();
    state = const AuthState.unauthenticated();

    // Nettoyage push best-effort, après avoir rendu la déconnexion effective.
    try {
      oneSignalLogoutPlatform();
    } catch (_) {
      // La session ioeh est déjà supprimée.
    }
    try {
      await OneSignal.logout().timeout(const Duration(seconds: 2));
    } catch (_) {
      // Ne jamais reconnecter l'utilisateur à cause d'un SDK tiers indisponible.
    }
  }

  /// Lie cet utilisateur à OneSignal pour recevoir les push ciblés.
  void _linkOneSignal(int userId) {
    OneSignal.login(userId.toString()); // mobile (natif)
    oneSignalLoginPlatform(
      userId.toString(),
    ); // web (JS direct — le plugin ne bridge pas login sur web)
    _tryRegisterPushToken(); // Enregistre le subscription ID côté backend (fire & forget)
  }

  /// Met à jour le profil utilisateur (name, phone).
  Future<void> updateProfile({String? name, String? phone}) async {
    final updatedUser = await _repo.updateProfile(name: name, phone: phone);
    state = AuthState.authenticated(token: state.token!, user: updatedUser);
    await TokenStorage.saveSession(
      token: state.token!,
      email: updatedUser.email,
      userId: updatedUser.id,
      name: updatedUser.name,
      phone: updatedUser.phone,
    );
  }

  /// Met à jour les paramètres d'alerte.
  Future<void> updateAlertSettings({
    bool? alertsEnabled,
    bool? alertSos,
    bool? alertLowBattery,
    bool? alertSpeedLimit,
    bool? alertViaPush,
    bool? alertViaWhatsapp,
    bool? alertViaEmail,
  }) async {
    final updatedUser = await _repo.updateAlertSettings(
      alertsEnabled: alertsEnabled,
      alertSos: alertSos,
      alertLowBattery: alertLowBattery,
      alertSpeedLimit: alertSpeedLimit,
      alertViaPush: alertViaPush,
      alertViaWhatsapp: alertViaWhatsapp,
      alertViaEmail: alertViaEmail,
    );
    state = AuthState.authenticated(token: state.token!, user: updatedUser);
  }

  /// Lit le subscription ID OneSignal (web) et l'enregistre côté backend.
  /// Attend 3s pour laisser le SDK OneSignal finir son initialisation.
  /// Fire & forget — les erreurs sont ignorées silencieusement.
  Future<void> _tryRegisterPushToken() async {
    // Attente : OneSignal init + login peuvent être asynchrones
    await Future.delayed(const Duration(seconds: 3));

    final subId = getOneSignalSubId(); // null sur mobile (stub no-op)
    if (subId == null || subId.isEmpty) return;

    try {
      await _repo.registerPushToken(subId);
    } catch (_) {
      // Best-effort — la prochaine ouverture de session réessaiera
    }
  }

  /// Lance le prompt navigateur depuis l'action utilisateur et relie la
  /// subscription créée au compte connecté.
  Future<bool> subscribeToPush() async {
    final user = state.user;
    if (user == null) return false;

    final subId = await requestOneSignalSubscription(user.id.toString());
    if (subId == null || subId.isEmpty) return false;

    await _repo.registerPushToken(subId);
    return true;
  }

  String get pushPermissionStatus => getOneSignalPermissionStatus();

  String _parseError(DioException e) {
    final data = e.response?.data;
    if (data is Map && data['message'] != null) {
      final message = data['message'];
      if (message is List && message.isNotEmpty) {
        return message.first.toString();
      }
      return message.toString();
    }
    return 'Identifiant ou mot de passe incorrect';
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier(ref.watch(authRepositoryProvider));
});
