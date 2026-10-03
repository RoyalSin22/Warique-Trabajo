import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persists the server address and the session token on the device.
///
/// The JWT is kept in SharedPreferences (localStorage on web). It is not encrypted, so a shared
/// device should log out at the end of the shift; the token also expires (12 h by default).
class SettingsStore {
  SettingsStore(this._prefs);

  final SharedPreferences _prefs;

  static const _serverUrlKey = 'serverUrl';
  static const _tokenKey = 'accessToken';

  /// Build-time default: `flutter run --dart-define=API_URL=http://192.168.1.50:3000`
  static const _buildDefault = String.fromEnvironment('API_URL');

  String get serverUrl {
    final saved = _prefs.getString(_serverUrlKey);
    if (saved != null && saved.isNotEmpty) return saved;
    if (_buildDefault.isNotEmpty) return _buildDefault;
    // Web build served from the restaurant PC: same host, API on port 3000
    if (kIsWeb && Uri.base.host.isNotEmpty) return '${Uri.base.scheme}://${Uri.base.host}:3000';
    return '';
  }

  Future<void> setServerUrl(String url) => _prefs.setString(_serverUrlKey, normalizeServerUrl(url));

  String? get token => _prefs.getString(_tokenKey);

  Future<void> setToken(String? token) =>
      token == null ? _prefs.remove(_tokenKey) : _prefs.setString(_tokenKey, token);
}

/// "192.168.1.50:3000/" -> "http://192.168.1.50:3000"
String normalizeServerUrl(String input) {
  var url = input.trim();
  while (url.endsWith('/')) {
    url = url.substring(0, url.length - 1);
  }
  if (url.endsWith('/api')) url = url.substring(0, url.length - 4);
  if (url.isNotEmpty && !url.contains('://')) url = 'http://$url';
  return url;
}

/// Returns an error message, or null when the URL is usable.
String? validateServerUrl(String? value) {
  final input = value ?? '';
  final uri = Uri.tryParse(normalizeServerUrl(input));
  if (input.trim().isEmpty) return 'Ingresa la dirección del servidor';
  if (uri == null || !(uri.scheme == 'http' || uri.scheme == 'https') || uri.host.isEmpty) {
    return 'Dirección inválida. Ejemplo: 192.168.1.50:3000';
  }
  return null;
}
