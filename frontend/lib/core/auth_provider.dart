import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';
import '../services/api_service.dart';
import '../services/chat_push_service.dart';

class AuthState {
  final User? user;
  final bool isLoading;

  final bool teacherMode;

  const AuthState({this.user, this.isLoading = true, this.teacherMode = false});

  bool get isAuthenticated => user != null;

  AuthState copyWith({User? user, bool? isLoading}) => AuthState(
        user: user ?? this.user,
        isLoading: isLoading ?? this.isLoading,
        teacherMode: teacherMode,
      );
}

class AuthNotifier extends StateNotifier<AuthState> {
  final ApiService _api;
  final ChatPushService? _push;
  Future<bool>? _refreshing;
  String? _lastRotatedToken;
  bool _signingOut = false;

  AuthNotifier(this._api, {ChatPushService? push})
      : _push = push,
        super(const AuthState(isLoading: true)) {
    _api.refreshSession = _refreshAfterUnauthorized;
  }

  Future<bool> _refreshAfterUnauthorized(String failedToken) async {
    if (_api.accessToken != failedToken) {
      return !_signingOut &&
          _api.accessToken != null &&
          failedToken == _lastRotatedToken;
    }
    if (_signingOut) return false;
    if (_refreshing case final pending?) return pending;
    final pending = _refreshCurrentSession(failedToken);
    _refreshing = pending;
    try {
      return await pending;
    } finally {
      _refreshing = null;
    }
  }

  Future<bool> _refreshCurrentSession(String failedToken) async {
    final prefs = await SharedPreferences.getInstance();
    final refresh = prefs.getString('refreshToken');
    if (refresh == null) return false;
    try {
      final res = await _api.refresh(refresh);
      if (_signingOut || !mounted || _api.accessToken != failedToken) {
        return false;
      }
      _lastRotatedToken = failedToken;
      await _save(res.accessToken, res.refreshToken, res.user,
          refreshing: failedToken);
      return _api.accessToken == res.accessToken;
    } catch (_) {
      return false;
    }
  }

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    if (token != null && token.isNotEmpty) {
      _api.setToken(token);
      try {
        final user = await _api.getMe();
        state = AuthState(user: user, isLoading: false, teacherMode: prefs.getBool('teacherMode') ?? false);
      } catch (e) {
        // Access token likely expired; try refreshing before giving up.
        final refreshed = await _tryRefresh(prefs);
        if (!refreshed) {
          await logout();
        }
      }
    } else {
      state = const AuthState(isLoading: false);
    }
  }

  /// Attempts to obtain a new access token using the stored refresh token.
  /// Returns true and updates state on success.
  Future<bool> _tryRefresh(SharedPreferences prefs) async {
    final refreshToken = prefs.getString('refreshToken');
    if (refreshToken == null || refreshToken.isEmpty) return false;
    try {
      final res = await _api.refresh(refreshToken);
      await _save(res.accessToken, res.refreshToken, res.user);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> login(String email, String password, {bool teacher = false}) async {
    final res = await _api.login(email, password, teacher: teacher);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('teacherMode', teacher);
    _lastRotatedToken = null;
    await _save(res.accessToken, res.refreshToken, res.user);
  }

  Future<void> register(String name, String email, String password,
      {required String username,
      required String phone,
      required String firebaseIdToken,
      String? unit,
      String? churchId}) async {
    final res = await _api.register(
      name: name,
      username: username,
      email: email,
      password: password,
      phone: phone,
      firebaseIdToken: firebaseIdToken,
      unit: unit,
      churchId: churchId,
    );
    await _save(res.accessToken, res.refreshToken, res.user);
  }

  Future<void> logout() async {
    _signingOut = true;
    await _push?.signOut();
    final prefs = await SharedPreferences.getInstance();
    final refreshToken = prefs.getString('refreshToken');
    // Best-effort server-side revocation; ignore network/validation errors.
    if (refreshToken != null && refreshToken.isNotEmpty) {
      try {
        await _api.logout(refreshToken);
      } catch (_) {}
    }
    await prefs.remove('token');
    await prefs.remove('teacherMode');
    await prefs.remove('refreshToken');
    _api.setToken(null);
    _lastRotatedToken = null;
    state = const AuthState(isLoading: false);
    _signingOut = false;
  }

  /// Revokes every refresh token for the user server-side (all devices), then
  /// clears the local session. Requires a valid access token for the call, so
  /// it runs before local tokens are cleared.
  Future<void> logoutEverywhere() async {
    await _api.logoutAll();
    await _push?.signOut();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('token');
    await prefs.remove('teacherMode');
    await prefs.remove('refreshToken');
    _api.setToken(null);
    _lastRotatedToken = null;
    state = const AuthState(isLoading: false);
  }

  Future<void> _save(String token, String? refreshToken, User user,
      {String? refreshing}) async {
    final prefs = await SharedPreferences.getInstance();
    if (refreshing != null && (_signingOut || _api.accessToken != refreshing)) {
      return;
    }
    await prefs.setString('token', token);
    if (refreshToken != null && refreshToken.isNotEmpty) {
      await prefs.setString('refreshToken', refreshToken);
    }
    if (refreshing != null && (_signingOut || _api.accessToken != refreshing)) {
      return;
    }
    _api.setToken(token, rotated: refreshing != null);
    state = AuthState(user: user, isLoading: false, teacherMode: prefs.getBool('teacherMode') ?? false);
  }

  Future<void> verifyPhone(String phone, String token) async {
    await _api.verifyAccountPhone(phone, token);
    await refreshUser();
  }

  Future<void> updateProfile(Map<String, dynamic> body) async {
    final user = await _api.updateMe(body);
    state = state.copyWith(user: user, isLoading: false);
  }

  /// Re-fetches the current user (e.g. to pick up a changed emailVerified flag).
  Future<void> refreshUser() async {
    final user = await _api.getMe();
    state = state.copyWith(user: user, isLoading: false);
  }

  /// Requests an email verification code for the current user's address.
  Future<void> resendVerification() async {
    final email = state.user?.email;
    if (email == null) return;
    await _api.resendVerification(email);
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  final api = ref.watch(apiServiceProvider);
  return AuthNotifier(api, push: ref.watch(chatPushProvider));
});
