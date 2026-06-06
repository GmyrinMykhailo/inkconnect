import 'dart:html' as html;

class SessionTokenStore {
  const SessionTokenStore._();

  static const _key = 'inkconnect.session_token';

  static String? read() {
    final value = html.window.localStorage[_key]?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  static void write(String token) {
    final value = token.trim();
    if (value.isEmpty) {
      clear();
      return;
    }
    html.window.localStorage[_key] = value;
  }

  static void clear() {
    html.window.localStorage.remove(_key);
  }
}
