import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

import 'vault.dart';

/// Thrown when the server can't be reached or says no.
class NetError implements Exception {
  const NetError(this.status, this.message);

  /// HTTP status, or 0 when there was no answer.
  final int status;
  final String message;

  bool get offline => status == 0;

  @override
  String toString() => 'NetError($status, $message)';
}

/// The phone's hidden Neon Managed Auth account (anonymous identity: no
/// email or password is ever shown). Keeps the session cookie in the vault
/// and mints the 15-minute JWT the API wants.
class NeonAuth {
  NeonAuth({
    required this.base,
    required this.vault,
    http.Client? client,
    this.label = 'p',
  }) : _http = client ?? http.Client();

  final String base;
  final Vault vault;
  final http.Client _http;

  /// The hidden email's prefix; end-to-end runs use their own, so their
  /// accounts can be found and deleted.
  final String label;

  String? _jwt;
  DateTime _expires = DateTime.fromMillisecondsSinceEpoch(0);
  Future<String>? _pending;

  /// The Neon Auth user id (the JWT `sub`), once signed in.
  String? userId;

  // Managed Auth checks Origin on sign-up and sign-in; a phone has none,
  // and localhost is trusted by default.
  static const _origin = 'http://localhost';
  static const _kEmail = 'auth.email';
  static const _kPassword = 'auth.password';
  static const _kCookie = 'auth.cookie';

  /// A valid JWT, minting (and signing up, the first time) as needed.
  /// Concurrent callers share one round trip.
  Future<String> token() {
    final jwt = _jwt;
    if (jwt != null &&
        DateTime.now().isBefore(
          _expires.subtract(const Duration(minutes: 1)),
        )) {
      return Future.value(jwt);
    }
    return _pending ??= _mint().whenComplete(() => _pending = null);
  }

  /// Drops the cached JWT, e.g. after the API answered 401.
  void expire() => _jwt = null;

  Future<String> _mint() async {
    var cookie = await vault.read(_kCookie);
    if (cookie != null) {
      final jwt = await _token(cookie);
      if (jwt != null) return jwt;
    }
    cookie = await _signIn();
    final jwt = await _token(cookie);
    if (jwt == null) throw const NetError(401, 'no token after sign-in');
    return jwt;
  }

  Future<String?> _token(String cookie) async {
    final res = await _send(
      http.Request('GET', Uri.parse('$base/token'))..headers['cookie'] = cookie,
    );
    if (res.statusCode == 401) return null;
    _check(res);
    final jwt = (_json(res)['token'] as String?) ?? '';
    final claims = _claims(jwt);
    _jwt = jwt;
    _expires = DateTime.fromMillisecondsSinceEpoch(
      ((claims['exp'] as num?) ?? 0).toInt() * 1000,
    );
    userId = claims['sub'] as String?;
    return jwt;
  }

  /// Signs in with the hidden credentials, or makes them the first time.
  Future<String> _signIn() async {
    var email = await vault.read(_kEmail);
    var password = await vault.read(_kPassword);
    final fresh = email == null || password == null;
    if (fresh) {
      final rnd = Random.secure();
      String hex(int n) => List.generate(
        n,
        (_) => rnd.nextInt(256).toRadixString(16).padLeft(2, '0'),
      ).join();
      email = '$label-${hex(12)}@moose.app';
      password = hex(24);
      await vault.write(_kEmail, email);
      await vault.write(_kPassword, password);
    }
    final res = await _post(fresh ? '/sign-up/email' : '/sign-in/email', {
      'email': email,
      'password': password,
      if (fresh) 'name': 'moose',
    });
    if (!fresh && res.statusCode == 401) {
      // The account is gone from the server: start a new one rather than
      // stay locked out (the partner re-pairs, as with a new phone).
      for (final k in [_kEmail, _kPassword, _kCookie]) {
        await vault.write(k, null);
      }
      return _signIn();
    }
    _check(res);
    final cookie = _cookie(res);
    if (cookie == null) throw const NetError(500, 'no session cookie');
    await vault.write(_kCookie, cookie);
    return cookie;
  }

  /// Forgets this phone's account (after unpair, or "start over").
  Future<void> forget() async {
    final cookie = await vault.read(_kCookie);
    if (cookie != null) {
      try {
        await _post('/sign-out', const {}, cookie: cookie);
      } on Object {
        // Signing out is a courtesy; the vault is what matters.
      }
    }
    for (final k in [_kEmail, _kPassword, _kCookie]) {
      await vault.write(k, null);
    }
    _jwt = null;
    userId = null;
  }

  Future<http.Response> _post(
    String path,
    Map<String, Object?> body, {
    String? cookie,
  }) => _send(
    http.Request('POST', Uri.parse('$base$path'))
      ..headers['content-type'] = 'application/json'
      ..headers['origin'] = _origin
      ..headers.addAll({'cookie': ?cookie})
      ..body = jsonEncode(body),
  );

  Future<http.Response> _send(http.BaseRequest req) async {
    try {
      return await http.Response.fromStream(
        await _http.send(req).timeout(const Duration(seconds: 20)),
      );
    } on Exception catch (e) {
      throw NetError(0, '$e');
    }
  }

  static void _check(http.Response res) {
    if (res.statusCode >= 300) throw NetError(res.statusCode, res.body);
  }

  static Map<String, Object?> _json(http.Response res) =>
      (jsonDecode(res.body) as Map).cast<String, Object?>();

  /// `name=value` of the session cookie. dart:io folds several Set-Cookie
  /// headers into one, comma-joined.
  static String? _cookie(http.Response res) {
    final raw = res.headers['set-cookie'];
    if (raw == null) return null;
    final m = RegExp(r'([\w.-]*session_token)=([^;,\s]+)').firstMatch(raw);
    return m == null ? null : '${m[1]}=${m[2]}';
  }

  static Map<String, Object?> _claims(String jwt) {
    final parts = jwt.split('.');
    if (parts.length != 3) throw const NetError(500, 'bad token');
    final json = utf8.decode(base64Url.decode(base64Url.normalize(parts[1])));
    return (jsonDecode(json) as Map).cast<String, Object?>();
  }
}
