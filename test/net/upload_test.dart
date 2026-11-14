import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:moose/net/api.dart';
import 'package:moose/net/auth.dart';
import 'package:moose/net/vault.dart';

/// Uploads report how far they've got, and only give up when they stall
/// (a video can take longer than any fixed deadline).
void main() {
  String jwt() {
    String part(Map<String, Object?> j) =>
        base64Url.encode(utf8.encode(jsonEncode(j))).replaceAll('=', '');
    final exp = DateTime.now().add(const Duration(minutes: 15));
    return '${part({'alg': 'EdDSA'})}.${part({'sub': 'u1', 'exp': exp.millisecondsSinceEpoch ~/ 1000})}.sig';
  }

  /// Managed Auth, the API's /v1/blobs, and storage's PUT ([put]).
  MooseApi api(
    Future<http.StreamedResponse> Function(
      http.BaseRequest req,
      Stream<List<int>> body,
    )
    put,
  ) {
    final client = MockClient.streaming((req, body) async {
      final path = req.url.path;
      if (path.endsWith('/sign-up/email') || path.endsWith('/sign-in/email')) {
        return http.StreamedResponse(
          Stream.value(utf8.encode('{}')),
          200,
          headers: {'set-cookie': '__Secure-neon-auth.session_token=t.s; Path=/'},
        );
      }
      if (path.endsWith('/token')) {
        return http.StreamedResponse(
          Stream.value(utf8.encode(jsonEncode({'token': jwt()}))),
          200,
        );
      }
      if (path == '/v1/blobs') {
        return http.StreamedResponse(
          Stream.value(
            utf8.encode(
              jsonEncode({'key': 'c/x/y', 'url': 'https://store/c/x/y?sig'}),
            ),
          ),
          200,
        );
      }
      if (req.method == 'PUT') return put(req, body);
      return http.StreamedResponse(const Stream.empty(), 404);
    });
    return MooseApi(
      base: 'https://api',
      auth: NeonAuth(
        base: 'https://auth/neondb/auth',
        vault: MemoryVault(),
        client: client,
      ),
      client: client,
    );
  }

  test('progress climbs to the whole size, in order', () async {
    final bytes = Uint8List(300 * 1024 + 17);
    var received = 0;
    int? announced;
    final a = api((req, body) async {
      announced = req.contentLength;
      await for (final chunk in body) {
        received += chunk.length;
      }
      return http.StreamedResponse(const Stream.empty(), 200);
    });

    final seen = <int>[];
    final key = await a.upload(
      bytes,
      onProgress: (sent, total) {
        expect(total, bytes.length);
        seen.add(sent);
      },
    );

    expect(key, 'c/x/y');
    expect(received, bytes.length);
    // Storage wants the length up front, not chunked encoding.
    expect(announced, bytes.length);
    expect(seen.first, 0);
    expect(seen.last, bytes.length);
    expect(seen.length, greaterThan(3));
    for (var i = 1; i < seen.length; i++) {
      expect(seen[i], greaterThanOrEqualTo(seen[i - 1]));
    }
  });

  test('a refused upload is an error', () async {
    final a = api((req, body) async {
      await body.drain<void>();
      return http.StreamedResponse(const Stream.empty(), 403);
    });
    await expectLater(
      a.upload(Uint8List(10)),
      throwsA(isA<NetError>().having((e) => e.status, 'status', 403)),
    );
  });

  test('an upload that stops moving gives up', () async {
    // Storage never reads the body or answers.
    final a = api((req, body) => Completer<http.StreamedResponse>().future);
    await expectLater(
      a.upload(Uint8List(10), stall: const Duration(seconds: 2)),
      throwsA(isA<NetError>().having((e) => e.status, 'status', 0)),
    );
  });
}
