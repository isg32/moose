import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moose/app/app.dart';
import 'package:moose/core/icons/v_icons.dart';
import 'package:moose/data/models.dart';
import 'package:moose/data/providers.dart';

/// Stickers, GIFs and songs end to end on the mock.
void main() {
  Future<void> frames(WidgetTester t, [int ms = 700]) async {
    for (var i = 0; i < ms; i += 50) {
      await t.pump(const Duration(milliseconds: 50));
    }
  }

  Future<ProviderContainer> open(WidgetTester t) async {
    t.view.physicalSize = const Size(1170, 2532);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    final c = ProviderContainer();
    addTearDown(c.dispose);
    c
        .read(sessionProvider.notifier)
        .set(c.read(sessionProvider).copyWith(locked: false));
    await t.pumpWidget(
      UncontrolledProviderScope(container: c, child: const MooseApp()),
    );
    await frames(t);
    return c;
  }

  Future<void> close(WidgetTester t) async {
    await t.pumpWidget(const SizedBox.shrink());
    await t.pump(const Duration(seconds: 5));
  }

  testWidgets('send a favourite sticker, then a GIF', (t) async {
    final c = await open(t);
    final tray = find.bySemanticsLabel('Stickers, GIFs and memes');
    await t.tap(tray);
    await frames(t);
    await t.tap(find.bySemanticsLabel('Sticker').first);
    await frames(t);
    expect(c.read(messagesProvider).last.body, isA<StickerBody>());

    await t.tap(tray);
    await frames(t);
    await t.tap(find.text('GIFs'));
    await frames(t, 1000);
    await t.tap(find.bySemanticsLabel(RegExp('sleepy cat')).first);
    await frames(t, 300);
    expect(find.text('Send this GIF?'), findsOneWidget);
    await t.tap(find.bySemanticsLabel('Send').last);
    await frames(t);
    expect(c.read(messagesProvider).last.body, isA<MemeBody>());
    expect(t.takeException(), isNull);
    await close(t);
  });

  testWidgets('search a song and send 15 seconds of it', (t) async {
    final c = await open(t);
    await t.tap(
      find
          .byWidgetPredicate((w) => w is VIconView && w.icon == VIcon.plus)
          .first,
    );
    await frames(t);
    await t.tap(find.text('Music'));
    await frames(t);
    await t.enterText(find.byType(EditableText).last, 'sienna');
    await frames(t, 1000);
    await t.tap(find.text('Sienna').first);
    await frames(t);
    expect(find.text('0:41'), findsOneWidget);
    expect(find.text('0:56'), findsOneWidget);
    await t.tap(find.text('Send to Aatika'));
    await frames(t);
    final body = c.read(messagesProvider).last.body as MusicBody;
    expect(body.song.title, 'Sienna');
    expect(body.start, const Duration(seconds: 41));
    expect(t.takeException(), isNull);
    await close(t);
  });
}
