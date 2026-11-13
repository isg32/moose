import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

import 'auth.dart';

/// A member as the server knows them: a name and a public key.
class Member {
  const Member({required this.id, required this.name, required this.pubkey});

  factory Member.fromJson(Map<String, Object?> j) => Member(
    id: j['id'] as String,
    name: (j['name'] as String?) ?? '',
    pubkey: (j['pubkey'] as String?) ?? '',
  );

  final String id;
  final String name;
  final String pubkey;
}

/// You, and your partner once paired.
class Me {
  const Me({required this.member, this.coupleId, this.since, this.partner});

  factory Me.fromJson(Map<String, Object?> j) => Me(
    member: Member.fromJson(j),
    coupleId: j['coupleId'] as String?,
    since: j['since'] == null ? null : DateTime.parse(j['since'] as String),
    partner: j['partner'] == null
        ? null
        : Member.fromJson((j['partner'] as Map).cast<String, Object?>()),
  );

  final Member member;
  final String? coupleId;
  final DateTime? since;
  final Member? partner;

  bool get paired => partner != null;
}

/// One sealed envelope waiting for this phone.
class Mail {
  const Mail({
    required this.id,
    required this.sender,
    required this.kind,
    required this.body,
    required this.at,
  });

  factory Mail.fromJson(Map<String, Object?> j) => Mail(
    id: j['id'] as String,
    sender: j['sender'] as String,
    kind: j['kind'] as String,
    body: j['body'] as String,
    at: DateTime.parse(j['created_at'] as String),
  );

  final String id;
  final String sender;
  final String kind;
  final String body;
  final DateTime at;
}

/// What the server lets mail be (it routes; it can't read).
enum MailKind { msg, receipt, typing, moment, theme, doodle, rtc, call }

/// The Moose API Function (see backend/src/api.ts).
class MooseApi {
  MooseApi({required this.base, required this.auth, http.Client? client})
    : _http = client ?? http.Client();

  final String base;
  final NeonAuth auth;
  final http.Client _http;

  Future<Me> me() async => Me.fromJson(await _call('GET', '/v1/me'));

  /// [fcm] is this phone's push token ('' forgets it).
  Future<Me> setMe({String? name, String? pubkey, String? fcm}) async =>
      Me.fromJson(
        await _call('PUT', '/v1/me', {
          'name': ?name,
          'pubkey': ?pubkey,
          'fcm': ?fcm,
        }),
      );

  /// A fresh six-character code, good for 10 minutes.
  Future<({String code, Duration expiresIn})> invite() async {
    final j = await _call('POST', '/v1/invites');
    return (
      code: j['code'] as String,
      expiresIn: Duration(seconds: (j['expiresIn'] as num).toInt()),
    );
  }

  /// Who made [code] (name and public key), without joining it.
  Future<Member> peek(String code) async {
    final j = await _call('GET', '/v1/invites/${Uri.encodeComponent(code)}');
    return Member(
      id: '',
      name: (j['name'] as String?) ?? '',
      pubkey: (j['pubkey'] as String?) ?? '',
    );
  }

  /// Joins [code]; throws [NetError] 404 when it has expired or was used.
  Future<Me> join(String code) async =>
      Me.fromJson(await _call('POST', '/v1/join', {'code': code}));

  Future<void> unpair() => _call('POST', '/v1/unpair');

  /// Leaves a sealed envelope for the partner. [id] is a UUID; sending the
  /// same one twice stores it once.
  Future<void> send(String id, MailKind kind, String sealed) =>
      _call('POST', '/v1/mail', {'id': id, 'kind': kind.name, 'body': sealed});

  Future<List<Mail>> inbox() async {
    final list = await _callList('GET', '/v1/mail');
    return [for (final j in list) Mail.fromJson(j)];
  }

  Future<void> ack(List<String> ids) async {
    if (ids.isEmpty) return;
    await _call('POST', '/v1/mail/ack', {'ids': ids});
  }

  /// Uploads an already-sealed blob; returns its key.
  Future<String> upload(Uint8List sealed) async {
    final j = await _call('POST', '/v1/blobs');
    final res = await _raw(
      http.Request('PUT', Uri.parse(j['url'] as String))..bodyBytes = sealed,
    );
    if (res.statusCode >= 300) throw NetError(res.statusCode, 'upload');
    return j['key'] as String;
  }

  Future<Uint8List> download(String key) async {
    final j = await _call(
      'GET',
      '/v1/blobs?key=${Uri.encodeQueryComponent(key)}',
    );
    final res = await _raw(http.Request('GET', Uri.parse(j['url'] as String)));
    if (res.statusCode >= 300) throw NetError(res.statusCode, 'download');
    return res.bodyBytes;
  }

  Future<void> deleteBlob(String key) =>
      _call('DELETE', '/v1/blobs?key=${Uri.encodeQueryComponent(key)}');

  /// Live mail, pushed by Neon Realtime through the API. The stream ends
  /// when the socket drops; the caller reconnects.
  Future<Stream<Mail>> live() async {
    final token = await auth.token();
    final uri = Uri.parse('${base.replaceFirst(RegExp('^http'), 'ws')}/v1/live')
        .replace(queryParameters: {'token': token});
    final socket = WebSocketChannel.connect(uri);
    await socket.ready.timeout(const Duration(seconds: 20));
    return socket.stream
        .map((e) => (jsonDecode(e as String) as Map).cast<String, Object?>())
        .where((j) => j['type'] == 'mail')
        .map(Mail.fromJson);
  }

  Future<Map<String, Object?>> _call(
    String method,
    String path, [
    Map<String, Object?>? body,
  ]) async => (await _json(method, path, body) as Map).cast<String, Object?>();

  Future<List<Map<String, Object?>>> _callList(
    String method,
    String path,
  ) async => [
    for (final e in await _json(method, path, null) as List)
      (e as Map).cast<String, Object?>(),
  ];

  Future<Object?> _json(
    String method,
    String path,
    Map<String, Object?>? body,
  ) async {
    for (var attempt = 0; ; attempt++) {
      final req = http.Request(method, Uri.parse('$base$path'))
        ..headers['authorization'] = 'Bearer ${await auth.token()}';
      if (body != null) {
        req
          ..headers['content-type'] = 'application/json'
          ..body = jsonEncode(body);
      }
      final res = await _raw(req);
      if (res.statusCode == 401 && attempt == 0) {
        auth.expire();
        continue;
      }
      if (res.statusCode >= 300) {
        var message = res.body;
        try {
          message =
              ((jsonDecode(res.body) as Map)['error'] as String?) ?? message;
        } on Object {
          // Not JSON: keep the body.
        }
        throw NetError(res.statusCode, message);
      }
      return jsonDecode(res.body);
    }
  }

  Future<http.Response> _raw(http.BaseRequest req) async {
    try {
      return await http.Response.fromStream(
        await _http.send(req).timeout(const Duration(seconds: 30)),
      );
    } on Exception catch (e) {
      throw NetError(0, '$e');
    }
  }
}
