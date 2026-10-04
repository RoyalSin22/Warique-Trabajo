import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/api_client.dart';
import '../core/api_exception.dart';
import '../data/admin_repository.dart';
import '../data/inventory_repository.dart';
import '../data/repositories.dart';
import '../data/settings_store.dart';
import '../models/user.dart';

/// Overridden in `main()` once SharedPreferences is loaded.
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('sharedPreferencesProvider must be overridden'),
);

final settingsStoreProvider = Provider<SettingsStore>(
  (ref) => SettingsStore(ref.watch(sharedPreferencesProvider)),
);

class Session {
  const Session({required this.serverUrl, required this.token, required this.user});

  final String serverUrl;
  final String token;
  final AppUser user;
}

/// `null` = logged out. Restores the saved token on start and validates it with `/auth/me`.
final sessionProvider = AsyncNotifierProvider<SessionNotifier, Session?>(SessionNotifier.new);

class SessionNotifier extends AsyncNotifier<Session?> {
  SettingsStore get _settings => ref.read(settingsStoreProvider);

  @override
  Future<Session?> build() async {
    final token = _settings.token;
    final serverUrl = _settings.serverUrl;
    if (token == null || serverUrl.isEmpty) return null;

    try {
      final user = await AuthRepository(ApiClient(baseUrl: serverUrl, token: token)).me();
      return Session(serverUrl: serverUrl, token: token, user: user);
    } on ApiException catch (error) {
      if (!error.isUnauthorized) rethrow; // server down: the UI offers retry
      await _settings.setToken(null);
      return null;
    }
  }

  Future<void> login({required String serverUrl, required String username, required String password}) async {
    final url = normalizeServerUrl(serverUrl);
    final result = await AuthRepository(ApiClient(baseUrl: url)).login(username.trim(), password);
    await _settings.setServerUrl(url);
    await _settings.setToken(result.token);
    state = AsyncData(Session(serverUrl: url, token: result.token, user: result.user));
  }

  Future<void> logout() async {
    await _settings.setToken(null);
    state = const AsyncData(null);
  }

  void retry() => ref.invalidateSelf();
}

/// Requires a logged-in session; screens that use it are only built after login.
final currentSessionProvider = Provider<Session>((ref) {
  final session = ref.watch(sessionProvider).value;
  if (session == null) throw StateError('No active session');
  return session;
});

final currentUserProvider = Provider<AppUser>((ref) => ref.watch(currentSessionProvider).user);

final apiClientProvider = Provider<ApiClient>((ref) {
  final session = ref.watch(currentSessionProvider);
  return ApiClient(
    baseUrl: session.serverUrl,
    token: session.token,
    // Expired or deactivated account: back to the login screen
    onUnauthorized: () => ref.read(sessionProvider.notifier).logout(),
  );
});

final authRepositoryProvider = Provider((ref) => AuthRepository(ref.watch(apiClientProvider)));
final menuRepositoryProvider = Provider((ref) => MenuRepository(ref.watch(apiClientProvider)));
final ordersRepositoryProvider = Provider((ref) => OrdersRepository(ref.watch(apiClientProvider)));
final adminRepositoryProvider = Provider((ref) => AdminRepository(ref.watch(apiClientProvider)));
final inventoryRepositoryProvider = Provider((ref) => InventoryRepository(ref.watch(apiClientProvider)));
