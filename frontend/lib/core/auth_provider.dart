import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';
import '../services/api_service.dart';

class AuthState {
  final User? user;
  final bool isLoading;

  const AuthState({this.user, this.isLoading = true});

  bool get isAuthenticated => user != null;

  AuthState copyWith({User? user, bool? isLoading}) => AuthState(
        user: user ?? this.user,
        isLoading: isLoading ?? this.isLoading,
      );
}

class AuthNotifier extends StateNotifier<AuthState> {
  final ApiService _api;

  AuthNotifier(this._api) : super(const AuthState(isLoading: true));

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    if (token != null && token.isNotEmpty) {
      _api.setToken(token);
      try {
        final user = await _api.getMe();
        state = AuthState(user: user, isLoading: false);
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

  Future<void> login(String email, String password) async {
    final res = await _api.login(email, password);
    await _save(res.accessToken, res.refreshToken, res.user);
  }

  Future<void> register(String name, String email, String password,
      {String? phone, String? unit, String? churchId}) async {
    final res = await _api.register(
      name: name,
      email: email,
      password: password,
      phone: phone,
      unit: unit,
      churchId: churchId,
    );
    await _save(res.accessToken, res.refreshToken, res.user);
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    final refreshToken = prefs.getString('refreshToken');
    // Best-effort server-side revocation; ignore network/validation errors.
    if (refreshToken != null && refreshToken.isNotEmpty) {
      try {
        await _api.logout(refreshToken);
      } catch (_) {}
    }
    await prefs.remove('token');
    await prefs.remove('refreshToken');
    _api.setToken(null);
    state = const AuthState(isLoading: false);
  }

  /// Revokes every refresh token for the user server-side (all devices), then
  /// clears the local session. Requires a valid access token for the call, so
  /// it runs before local tokens are cleared.
  Future<void> logoutEverywhere() async {
    await _api.logoutAll();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('token');
    await prefs.remove('refreshToken');
    _api.setToken(null);
    state = const AuthState(isLoading: false);
  }

  Future<void> _save(String token, String? refreshToken, User user) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('token', token);
    if (refreshToken != null && refreshToken.isNotEmpty) {
      await prefs.setString('refreshToken', refreshToken);
    }
    _api.setToken(token);
    state = AuthState(user: user, isLoading: false);
  }

  Future<void> updateProfile(Map<String, dynamic> body) async {
    final user = await _api.updateMe(body);
    state = AuthState(user: user, isLoading: false);
  }

  /// Re-fetches the current user (e.g. to pick up a changed emailVerified flag).
  Future<void> refreshUser() async {
    final user = await _api.getMe();
    state = AuthState(user: user, isLoading: false);
  }

  /// Requests a new email verification link for the current user's address.
  Future<void> resendVerification() async {
    final email = state.user?.email;
    if (email == null) return;
    await _api.resendVerification(email);
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  final api = ref.watch(apiServiceProvider);
  return AuthNotifier(api);
});
