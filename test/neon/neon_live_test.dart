import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:moose/core/theme/v_colors.dart';
import 'package:moose/data/models.dart';
import 'package:moose/data/repositories.dart';
import 'package:moose/net/config.dart';
import 'package:moose/net/crypto.dart';
import 'package:moose/net/neon_backend.dart';
import 'package:moose/net/vault.dart';

/// Two pretend phones pair and talk through the deployed Neon backend:
/// Managed Auth, the API Function, Postgres, Realtime and storage.
///
///   MOOSE_API_URL=… MOOSE_AUTH_URL=… flutter test test/neon
///   (cd backend && npm run cleanup)   # deletes the e2e- accounts
void main() {
  final env = Platform.environment;
  final api = env['MOOSE_API_URL'] ?? '';
  final authUrl = env['MOOSE_AUTH_URL'] ?? '';
  final skip = api.isEmpty || authUrl.isEmpty
      ? 'set MOOSE_API_URL and MOOSE_AUTH_URL to run against Neon'
      : null;

  // flutter_test answers every HTTP request with 400; this test wants the
  // real network.
  setUpAll(() => HttpOverrides.global = null);

  Future<NeonBackend> phone() async {
    final dir = await Directory.systemTemp.createTemp('moose-e2e');
    addTearDown(() => dir.delete(recursive: true));
    final b = await NeonBackend.open(
      NeonConfig(api: api, auth: authUrl),
      vault: MemoryVault(),
      dir: dir,
      label: 'e2e',
    );
    addTearDown(b.store.flush);
    return b..isOpen = () => true;
  }

  Future<T> next<T extends ChatEvent>(
    Stream<ChatEvent> s, {
    bool Function(T)? where,
  }) => s
      .where((e) => e is T && (where?.call(e) ?? true))
      .cast<T>()
      .first
      .timeout(const Duration(seconds: 30));

  test('pair, then talk end to end through Neon', skip: skip, () async {
    final sapan = await phone();
    final aatika = await phone();
    final pairS = NeonPairRepository(sapan);
    final pairA = NeonPairRepository(aatika);

    // Pairing (C5, C6, C8).
    await pairS.setName('Sapan');
    await pairA.setName('Aatika');
    final code = await pairS.invite();
    expect(code, matches(RegExp(r'^[A-Z2-9]{6}$')));
    final waiting = pairS.waitForPartner(mockAfter: Duration.zero).first;
    expect(await pairA.join('ZZZZZZ'), isNull);
    final a = (await pairA.join(code))!;
    final s = await waiting.timeout(const Duration(seconds: 20));
    expect(a.partner.name, 'Sapan');
    expect(s.partner.name, 'Aatika');
    expect(a.securityCode, s.securityCode);
    expect(a.securityCode, hasLength(12));

    final chatS = NeonChatRepository(sapan);
    final chatA = NeonChatRepository(aatika);
    addTearDown(chatS.dispose);
    addTearDown(chatA.dispose);
    final eventsS = chatS.events.asBroadcastStream();
    final eventsA = chatA.events.asBroadcastStream();
    await Future<void>.delayed(const Duration(seconds: 4)); // sockets up

    // A sealed text, live, then ✓ and seen (C15).
    final hello = Message(
      id: 'out-1',
      fromMe: true,
      at: DateTime.now(),
      body: const TextBody('dinner at 8?'),
      delivery: Delivery.pending,
    );
    final arrived = next<Incoming>(eventsA);
    final sent = next<DeliveryUpdate>(
      eventsS,
      where: (e) => e.delivery == Delivery.sent,
    );
    final seen = next<DeliveryUpdate>(
      eventsS,
      where: (e) => e.delivery == Delivery.seen,
    );
    chatS.send(hello);
    final got = (await arrived).message;
    expect((got.body as TextBody).text, 'dinner at 8?');
    expect(got.fromMe, isFalse);
    expect((await sent).id, 'out-1');
    expect((await seen).id, 'out-1');

    // A reply with a quote, a reaction, typing and a hug.
    final typing = next<TypingChanged>(eventsS);
    chatA.typing(true);
    expect((await typing).typing, isTrue);
    final react = next<ReactionChanged>(eventsS);
    chatA.react('out-1', '❤️');
    expect((await react).emoji, '❤️');
    final reply = next<Incoming>(eventsS);
    chatA.send(
      Message(
        id: 'out-a1',
        fromMe: true,
        at: DateTime.now(),
        body: const TextBody('yes!'),
        reply: got.quote(),
      ),
    );
    final r = (await reply).message;
    expect((r.body as TextBody).text, 'yes!');
    expect(r.reply!.fromMe, isTrue, reason: 'it quotes my own message');
    final hug = next<MomentArrived>(eventsA);
    chatS.send(
      Message(
        id: 'out-2',
        fromMe: true,
        at: DateTime.now(),
        body: const MomentBody(VMoment.hug),
      ),
    );
    expect((await hug).moment, VMoment.hug);

    // Sealed media through the bucket.
    final photo = utf8.encode('pretend jpeg ' * 1000);
    final sealed = await Channel.sealBlob(photo);
    final key = await sapan.api.upload(sealed.bytes);
    final down = await aatika.api.download(key);
    expect(await Channel.openBlob(down, sealed.key), photo);
    await aatika.api.deleteBlob(key);

    // Delivered mail is gone from the server.
    await Future<void>.delayed(const Duration(seconds: 2));
    expect(await sapan.api.inbox(), isEmpty);
    expect(await aatika.api.inbox(), isEmpty);

    // Unpair ends it for both.
    await pairS.unpair();
    expect((await aatika.api.me()).paired, isFalse);
  }, timeout: const Timeout(Duration(minutes: 3)));
}
