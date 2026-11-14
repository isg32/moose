import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moose/app/app.dart';
import 'package:moose/core/icons/v_icons.dart';
import 'package:moose/data/models.dart';
import 'package:moose/data/providers.dart';
import 'package:moose/features/chat/composer.dart';
import 'package:moose/features/media/media_viewer.dart';

/// Attachments end to end: attach, pick two in the gallery, caption, send;
/// then open a photo in the viewer.
void main() {
  Future<void> frames(WidgetTester t, [int ms = 700]) async {
    for (var i = 0; i < ms; i += 50) {
      await t.pump(const Duration(milliseconds: 50));
    }
  }

  testWidgets('pick two photos from the gallery and send them', (t) async {
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

    await t.tap(
      find
          .byWidgetPredicate((w) => w is VIconView && w.icon == VIcon.plus)
          .first,
    );
    await frames(t);
    await t.tap(find.text('Gallery'));
    await frames(t);
    await t.tap(find.bySemanticsLabel('Photo').at(0));
    await t.tap(find.bySemanticsLabel('Photo').at(2));
    await frames(t, 200);
    await t.tap(find.text('Send 2'));
    await frames(t);
    expect(find.text('1 / 2'), findsOneWidget);
    await t.enterText(find.byType(EditableText).last, 'the lake');
    await t.tap(find.bySemanticsLabel('Send to Aatika'));
    // Going up: each photo shows how much of it has gone.
    await frames(t, 300);
    expect(find.textContaining('Sending ·'), findsWidgets);
    await frames(t, 400);
    expect(find.textContaining('Sending ·'), findsNothing);

    final sent = c.read(messagesProvider).last;
    expect(sent.body, isA<PhotoBody>());
    expect((sent.body as PhotoBody).photos.length, 2);
    expect((sent.body as PhotoBody).caption, 'the lake');
    expect(find.text('the lake'), findsOneWidget);

    await t.tap(find.text('the lake'));
    await t.tapAt(t.getTopLeft(find.text('the lake')) - const Offset(-20, 60));
    await frames(t);
    expect(find.byType(MediaViewer), findsOneWidget);
    expect(t.takeException(), isNull);

    // Reply's circle answers a tap (it used to swallow it): the viewer
    // closes and the composer quotes the photo.
    await t.tap(
      find.descendant(
        of: find.byType(MediaViewer),
        matching: find.byWidgetPredicate(
          (w) => w is VIconView && w.icon == VIcon.reply,
        ),
      ),
    );
    await frames(t);
    expect(find.byType(MediaViewer), findsNothing);
    expect(t.widget<Composer>(find.byType(Composer)).replyTo?.id, sent.id);

    await t.pumpWidget(const SizedBox.shrink());
    await t.pump(const Duration(seconds: 5));
  });
}
