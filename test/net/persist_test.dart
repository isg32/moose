import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moose/data/models.dart';
import 'package:moose/data/providers.dart';
import 'package:moose/net/config.dart';
import 'package:moose/net/neon_backend.dart';
import 'package:moose/net/vault.dart';

void main() {
  test('the app lock and settings survive a restart', () async {
    final dir = await Directory.systemTemp.createTemp('moose-keep');
    addTearDown(() => dir.delete(recursive: true));
    final vault = MemoryVault();
    const config = NeonConfig(api: 'https://x', auth: 'https://y');

    var b = await NeonBackend.open(config, vault: vault, dir: dir);
    var c = ProviderContainer(overrides: b.overrides());
    expect(c.read(sessionProvider).locked, isFalse, reason: 'no PIN yet');
    c.read(sessionProvider.notifier)
      ..setPin('7391')
      ..setDecoy('2580', 'Riya');
    c
        .read(settingsProvider.notifier)
        .update((s) => s.copyWith(enterSends: true, lockAfter: LockAfter.m5));
    await b.store.flush();
    await Future<void>.delayed(Duration.zero);
    c.dispose();

    b = await NeonBackend.open(config, vault: vault, dir: dir);
    c = ProviderContainer(overrides: b.overrides());
    addTearDown(c.dispose);
    final s = c.read(sessionProvider);
    expect(s.locked, isTrue, reason: 'opens locked');
    expect(s.pin, '7391');
    expect(s.decoyPin, '2580');
    expect(s.decoyName, 'Riya');
    expect(c.read(settingsProvider).enterSends, isTrue);
    expect(c.read(settingsProvider).lockAfter, LockAfter.m5);

    // Turning the lock off is kept too.
    c.read(sessionProvider.notifier).removeLock();
    await Future<void>.delayed(Duration.zero);
    final again = await NeonBackend.open(config, vault: vault, dir: dir);
    final c2 = ProviderContainer(overrides: again.overrides());
    addTearDown(c2.dispose);
    expect(c2.read(sessionProvider).pin, isEmpty);
    expect(c2.read(sessionProvider).locked, isFalse);
  });
}
