import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'vault.dart';

/// This phone's identity: an X25519 key pair made on first launch and kept
/// in the vault. A new phone is a new identity (no recovery, by design).
class Identity {
  Identity._(this._pair, this.publicKey);

  final SimpleKeyPair _pair;

  /// Base64, as the server and the partner see it.
  final String publicKey;

  static const _key = 'identity.x25519';
  static final _x25519 = X25519();

  static Future<Identity> load(Vault vault) async {
    final saved = await vault.read(_key);
    final SimpleKeyPair pair;
    if (saved == null) {
      pair = await _x25519.newKeyPair();
      final seed = await pair.extractPrivateKeyBytes();
      await vault.write(_key, base64Encode(seed));
    } else {
      pair = await _x25519.newKeyPairFromSeed(base64Decode(saved));
    }
    final pub = await pair.extractPublicKey();
    return Identity._(pair, base64Encode(pub.bytes));
  }

  /// The sealed channel to [partnerKey] (base64 X25519).
  Future<Channel> channelTo(String partnerKey) async {
    final theirs = SimplePublicKey(
      base64Decode(partnerKey),
      type: KeyPairType.x25519,
    );
    final shared = await _x25519.sharedSecretKey(
      keyPair: _pair,
      remotePublicKey: theirs,
    );
    final keys = [publicKey, partnerKey]..sort();
    final key = await Hkdf(hmac: Hmac.sha256(), outputLength: 32).deriveKey(
      secretKey: shared,
      nonce: utf8.encode(keys.join('|')),
      info: utf8.encode('moose/v1/mail'),
    );
    return Channel._(key);
  }
}

/// XChaCha20-Poly1305 between the two phones. A sealed box is
/// base64(nonce ‖ ciphertext ‖ mac); the server only ever stores these.
class Channel {
  Channel._(this._key);

  final SecretKey _key;
  static final _aead = Xchacha20.poly1305Aead();

  Future<String> seal(List<int> plain) async {
    final box = await _aead.encrypt(plain, secretKey: _key);
    return base64Encode(box.concatenation());
  }

  /// Throws [SecretBoxAuthenticationError] if the box was not sealed by the
  /// partner, or was changed on the way.
  Future<Uint8List> open(String sealed) async {
    final box = SecretBox.fromConcatenation(
      base64Decode(sealed),
      nonceLength: _aead.nonceLength,
      macLength: _aead.macAlgorithm.macLength,
    );
    return Uint8List.fromList(await _aead.decrypt(box, secretKey: _key));
  }

  Future<String> sealJson(Map<String, Object?> json) =>
      seal(utf8.encode(jsonEncode(json)));

  Future<Map<String, Object?>> openJson(String sealed) async =>
      (jsonDecode(utf8.decode(await open(sealed))) as Map)
          .cast<String, Object?>();

  /// Encrypts media with a fresh key of its own, so a blob's key travels
  /// inside a sealed message and the bucket holds only noise.
  static Future<({Uint8List bytes, String key})> sealBlob(
    List<int> plain,
  ) async {
    final key = await _aead.newSecretKey();
    final box = await _aead.encrypt(plain, secretKey: key);
    return (
      bytes: box.concatenation(),
      key: base64Encode(await key.extractBytes()),
    );
  }

  static Future<Uint8List> openBlob(List<int> sealed, String key) async {
    final box = SecretBox.fromConcatenation(
      sealed,
      nonceLength: _aead.nonceLength,
      macLength: _aead.macAlgorithm.macLength,
    );
    final plain = await _aead.decrypt(
      box,
      secretKey: SecretKey(base64Decode(key)),
    );
    return Uint8List.fromList(plain);
  }
}

/// The twelve five-digit groups both phones show (C8, C37): the same on
/// both sides only if each holds the other's real key.
Future<List<String>> securityCode(String a, String b) async {
  final keys = [a, b]..sort();
  final hash = await Sha512().hash(
    utf8.encode('moose/v1/code|${keys.join('|')}'),
  );
  final bytes = hash.bytes;
  return [
    for (var i = 0; i < 12; i++)
      (((bytes[i * 5] << 32) |
                  (bytes[i * 5 + 1] << 24) |
                  (bytes[i * 5 + 2] << 16) |
                  (bytes[i * 5 + 3] << 8) |
                  bytes[i * 5 + 4]) %
              100000)
          .toString()
          .padLeft(5, '0'),
  ];
}
