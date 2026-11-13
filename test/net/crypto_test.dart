import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moose/net/crypto.dart';
import 'package:moose/net/vault.dart';

void main() {
  late Identity sapan, aatika, stranger;
  late MemoryVault vault;

  setUp(() async {
    vault = MemoryVault();
    sapan = await Identity.load(vault);
    aatika = await Identity.load(MemoryVault());
    stranger = await Identity.load(MemoryVault());
  });

  test('the identity key is made once and kept', () async {
    final again = await Identity.load(vault);
    expect(again.publicKey, sapan.publicKey);
    expect(base64Decode(sapan.publicKey), hasLength(32));
    expect(aatika.publicKey, isNot(sapan.publicKey));
  });

  test('a sealed box opens on the other phone, both ways', () async {
    final s2a = await sapan.channelTo(aatika.publicKey);
    final a2s = await aatika.channelTo(sapan.publicKey);
    final box = await s2a.sealJson({'text': 'dinner at 8?'});
    expect(box, isNot(contains('dinner')));
    expect(await a2s.openJson(box), {'text': 'dinner at 8?'});
    expect(
      utf8.decode(await s2a.open(await a2s.seal(utf8.encode('yes')))),
      'yes',
    );
  });

  test('the same message seals differently each time', () async {
    final ch = await sapan.channelTo(aatika.publicKey);
    expect(await ch.seal([1, 2, 3]), isNot(await ch.seal([1, 2, 3])));
  });

  test('a stranger or a changed box does not open', () async {
    final s2a = await sapan.channelTo(aatika.publicKey);
    final box = await s2a.seal(utf8.encode('hi'));
    final wrong = await stranger.channelTo(sapan.publicKey);
    await expectLater(
      wrong.open(box),
      throwsA(isA<SecretBoxAuthenticationError>()),
    );
    final bytes = base64Decode(box)..[30] ^= 1;
    final a2s = await aatika.channelTo(sapan.publicKey);
    await expectLater(
      a2s.open(base64Encode(bytes)),
      throwsA(isA<SecretBoxAuthenticationError>()),
    );
  });

  test('media seals with a key of its own', () async {
    final plain = List.generate(5000, (i) => i % 251);
    final sealed = await Channel.sealBlob(plain);
    expect(sealed.bytes.length, plain.length + 24 + 16);
    expect(await Channel.openBlob(sealed.bytes, sealed.key), plain);
  });

  test('both phones show the same security code, a stranger another', () async {
    final a = await securityCode(sapan.publicKey, aatika.publicKey);
    final b = await securityCode(aatika.publicKey, sapan.publicKey);
    expect(a, b);
    expect(a, hasLength(12));
    expect(a.every((g) => RegExp(r'^\d{5}$').hasMatch(g)), isTrue);
    expect(await securityCode(sapan.publicKey, stranger.publicKey), isNot(a));
  });
}
