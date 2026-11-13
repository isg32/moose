import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moose/app/app.dart';
import 'package:moose/data/models.dart';
import 'package:moose/data/providers.dart';

void main() {
  Future<ProviderContainer> open(WidgetTester t) async {
    t.view.physicalSize = const Size(1080, 2400);
    t.view.devicePixelRatio = 2.625;
    addTearDown(t.view.reset);
    final c = ProviderContainer();
    addTearDown(c.dispose);
    c
        .read(sessionProvider.notifier)
        .set(c.read(sessionProvider).copyWith(locked: false));
    await t.pumpWidget(
      UncontrolledProviderScope(container: c, child: const MooseApp()),
    );
    await t.pump(const Duration(milliseconds: 600));
    return c;
  }

  // The recording row replaces the mic button under the finger; letting go
  // must still send (it used to be lost with the button).
  testWidgets('hold the mic, let go: a voice note goes', (t) async {
    final c = await open(t);
    final before = c.read(messagesProvider).length;
    final hold = await t.startGesture(
      t.getCenter(find.bySemanticsLabel('Hold to record, tap for round video')),
    );
    for (var i = 0; i < 30; i++) {
      await t.pump(const Duration(milliseconds: 50));
    }
    expect(find.text('0:01'), findsOneWidget, reason: 'recording');
    await hold.up();
    await t.pump(const Duration(milliseconds: 300));
    expect(c.read(messagesProvider).length, before + 1);
    expect(c.read(messagesProvider).last.body, isA<VoiceBody>());
    await t.pumpWidget(const SizedBox.shrink());
    await t.pump(const Duration(seconds: 5));
  });

  testWidgets('slide left while holding: nothing goes', (t) async {
    final c = await open(t);
    final before = c.read(messagesProvider).length;
    final hold = await t.startGesture(
      t.getCenter(find.bySemanticsLabel('Hold to record, tap for round video')),
    );
    for (var i = 0; i < 20; i++) {
      await t.pump(const Duration(milliseconds: 50));
    }
    for (var i = 0; i < 10; i++) {
      await hold.moveBy(const Offset(-16, 0));
      await t.pump(const Duration(milliseconds: 16));
    }
    await hold.up();
    await t.pump(const Duration(milliseconds: 300));
    expect(c.read(messagesProvider).length, before);
    await t.pumpWidget(const SizedBox.shrink());
    await t.pump(const Duration(seconds: 5));
  });
}
