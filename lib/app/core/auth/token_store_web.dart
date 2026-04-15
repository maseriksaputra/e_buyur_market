import 'dart:html' as html;

class TokenStore {
  static const _key = 'auth_token';

  static Future<void> write(String token) async {
    html.window.localStorage[_key] = token;
  }

  static Future<String?> read() async {
    return html.window.localStorage[_key];
  }

  static Future<void> clear() async {
    html.window.localStorage.remove(_key);
  }
}
