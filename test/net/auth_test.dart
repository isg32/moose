import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:moose/net/auth.dart';
import 'package:moose/net/vault.dart';

String jwt(String sub, DateTime exp) {
  String part(Map<String, Object?> j) =>
      base64Url.encode(utf8.encode(jsonEncode(j))).replaceAll('=', '');
  return '${part({'alg': 'EdDSA'})}.${part({'sub': sub, 'exp': exp.millisecondsSinceEpoch ~/ 1000})}.sig';
}

void main() {
  late List<String> calls;
  late bool sessionValid;
  late MemoryVault vault;

  MockClient server() => MockClient((req) async {
    calls.add('${req.method} ${req.url.path.split('/auth').last}');
    switch (req.url.path.split('/auth').last) {
      case '/sign-up/email' || '/sign-in/email':
        expect(req.headers['origin'], 'http://localhost');
        sessionValid = true;
        return http.Response(
          '{}',
          200,
          headers: {
            'set-cookie': '__Secure-neon-auth.session_token=tok.sig; Path=/; HttpOnly, other=1',
          },
        );
      case '/token':
        if (!sessionValid ||
            req.headers['cookie'] !=
                '__Secure-neon-auth.session_token=tok.sig') {
          return http.Response('{"code":"UNAUTHORIZED"}', 401);
        }
        return http.Response(
          jsonEncode({
            'token': jwt('u1', DateTime.now().add(const Duration(minutes: 15))),
          }),
          200,
        );
    }
    return http.Response('nope', 404);
  });

  setUp(() {
    calls = [];
    sessionValid = false;
    vault = MemoryVault();
  });

  NeonAuth auth() =>
      NeonAuth(base: 'https://x/neondb/auth', vault: vault, client: server());

  test('the first launch makes a hidden account and a token', () async {
    final a = auth();
    final t = await a.token();
    expect(t.split('.'), hasLength(3));
    expect(a.userId, 'u1');
    expect(calls, ['POST /sign-up/email', 'GET /token']);
    expect(
      vault.values['auth.email'],
      matches(RegExp(r'^p-[0-9a-f]{24}@moose\.app$')),
    );
    expect(vault.values['auth.password'], hasLength(48));
    // Cached until it's nearly expired, and shared by concurrent callers.
    expect(await Future.wait([a.token(), a.token()]), [t, t]);
    expect(calls, hasLength(2));
  });

  test(
    'a later launch reuses the session, and signs in when it has expired',
    () async {
      await auth().token();
      calls.clear();
      await auth().token();
      expect(calls, ['GET /token']);
      calls.clear();
      sessionValid = false;
      await auth().token();
      expect(calls, ['GET /token', 'POST /sign-in/email', 'GET /token']);
    },
  );

  test('an account gone from the server is made again', () async {
    vault.values
      ..['auth.email'] = 'p-old@moose.app'
      ..['auth.password'] = 'old';
    final seen = <String>[];
    final a = NeonAuth(
      base: 'https://x/neondb/auth',
      vault: vault,
      client: MockClient((req) async {
        final path = req.url.path.split('/auth').last;
        seen.add(path);
        if (path == '/sign-in/email') {
          return http.Response('{"code":"INVALID_EMAIL_OR_PASSWORD"}', 401);
        }
        if (path == '/sign-up/email') {
          return http.Response(
            '{}',
            200,
            headers: {
              'set-cookie': '__Secure-neon-auth.session_token=new.sig; Path=/',
            },
          );
        }
        if (req.headers['cookie'] ==
            '__Secure-neon-auth.session_token=new.sig') {
          return http.Response(
            jsonEncode({
              'token': jwt(
                'u2',
                DateTime.now().add(const Duration(minutes: 15)),
              ),
            }),
            200,
          );
        }
        return http.Response('{}', 401);
      }),
    );
    await a.token();
    expect(seen, ['/sign-in/email', '/sign-up/email', '/token']);
    expect(a.userId, 'u2');
    expect(vault.values['auth.email'], isNot('p-old@moose.app'));
  });

  test('no network is a NetError the app can show', () async {
    final a = NeonAuth(
      base: 'https://x',
      vault: vault,
      client: MockClient((_) async => throw http.ClientException('offline')),
    );
    await expectLater(
      a.token(),
      throwsA(isA<NetError>().having((e) => e.offline, 'offline', isTrue)),
    );
  });
}
