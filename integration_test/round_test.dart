import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:moose/app/app.dart';
import 'package:moose/data/models.dart';
import 'package:moose/data/providers.dart';
import 'package:moose/net/phone_round.dart';
import 'package:path_provider/path_provider.dart';

/// A round video from the real front camera, held and let go (C16).
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('hold for a round video', (t) async {
    final dir = await getTemporaryDirectory();
    final c = ProviderContainer(
      overrides: [roundCameraProvider.overrideWithValue(PhoneRound(dir))],
    );
    addTearDown(c.dispose);
    c
        .read(sessionProvider.notifier)
        .set(c.read(sessionProvider).copyWith(locked: false));
    await t.pumpWidget(
      UncontrolledProviderScope(container: c, child: const MooseApp()),
    );
    for (var i = 0; i < 20; i++) {
      await t.pump(const Duration(milliseconds: 50));
    }
    await t.tap(find.bySemanticsLabel('Hold to record, tap for round video'));
    for (var i = 0; i < 6; i++) {
      await t.pump(const Duration(milliseconds: 50));
    }
    final hold = await t.startGesture(
      t.getCenter(
        find.bySemanticsLabel('Hold to record a round video, tap for voice'),
      ),
    );
    for (var i = 0; i < 80; i++) {
      await t.pump(const Duration(milliseconds: 50));
    }
    await hold.up();
    final end = DateTime.now().add(const Duration(seconds: 15));
    while (c.read(messagesProvider).last.body is! RoundVideoBody) {
      if (DateTime.now().isAfter(end)) fail('no round video');
      await t.pump(const Duration(milliseconds: 100));
    }
    final v = (c.read(messagesProvider).last.body as RoundVideoBody).video;
    expect(v.path, isNotNull);
    expect(File(v.path!).lengthSync(), greaterThan(10000));
  });
}
