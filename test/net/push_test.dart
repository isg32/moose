import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:moose/core/theme/v_colors.dart';
import 'package:moose/data/models.dart';
import 'package:moose/net/api.dart';
import 'package:moose/net/crypto.dart';
import 'package:moose/net/local_store.dart';
import 'package:moose/net/push.dart';
import 'package:moose/net/vault.dart';
import 'package:moose/net/wire.dart';

void main() {
  late MemoryVault mine;
  late LocalStore store;
  late Channel fromAatika;

  setUp(() async {
    mine = MemoryVault();
    final me = await Identity.load(mine);
    final aatika = await Identity.load(MemoryVault());
    final dir = await Directory.systemTemp.createTemp('moose-push');
    addTearDown(() => dir.delete(recursive: true));
    store = await LocalStore.open(dir)
      ..partner = Member(id: 'a', name: 'Aatika', pubkey: aatika.publicKey);
    fromAatika = await aatika.channelTo(me.publicKey);
  });

  Future<String> seal(Body body) async => fromAatika.sealJson(
    MessageEnvelope(
      Message(id: 'm', fromMe: true, at: DateTime.now(), body: body),
    ).toJson(),
  );

  test('a message says only that something came', () async {
    final n = await Push.describe(
      {'kind': 'msg', 'body': await seal(const TextBody('the secret'))},
      vault: mine,
      store: store,
    );
    expect(n!.title, 'Aatika');
    expect(n.body, 'New message');
    expect(n.body, isNot(contains('secret')));
    expect(n.moment, isFalse);
  });

  test('a moment is opened and named, on the loud channel', () async {
    final n = await Push.describe(
      {'kind': 'moment', 'body': await seal(const MomentBody(VMoment.hug))},
      vault: mine,
      store: store,
    );
    expect(n!.body, '${VMoment.hug.emoji} Aatika sent a hug');
    expect(n.moment, isTrue);
  });

  test('too big to ride along: said from the kind alone', () async {
    final n = await Push.describe({'kind': 'call'}, vault: mine, store: store);
    expect(n!.body, 'Calling you');
  });

  test('not sealed by the partner, or not paired: nothing shows', () async {
    final stranger = await (await Identity.load(MemoryVault()))
        .channelTo((await Identity.load(mine)).publicKey);
    final forged = await stranger.sealJson({'type': 'msg'});
    expect(
      await Push.describe(
        {'kind': 'msg', 'body': forged},
        vault: mine,
        store: store,
      ),
      isNull,
    );
    store.partner = null;
    expect(
      await Push.describe({'kind': 'msg'}, vault: mine, store: store),
      isNull,
    );
  });
}
