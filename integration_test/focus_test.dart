import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:moose/app/app.dart';
import 'package:moose/core/icons/v_icons.dart';
import 'package:moose/data/providers.dart';
import 'package:moose/features/chat/composer.dart';

/// After every kind of sheet, overlay and page the chat opens, typing in
/// the composer still lands (real keyboard, real phone).
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('typing lands after each sheet and page', (t) async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    c
        .read(sessionProvider.notifier)
        .set(c.read(sessionProvider).copyWith(locked: false));
    await t.pumpWidget(
      UncontrolledProviderScope(container: c, child: const MooseApp()),
    );
    Future<void> frames([int ms = 700]) async {
      for (var i = 0; i < ms; i += 50) {
        await t.pump(const Duration(milliseconds: 50));
      }
    }

    await frames(1000);
    final field = find.descendant(
      of: find.byType(Composer),
      matching: find.byType(EditableText),
    );
    final log = <String>[];
    Future<void> typeAndSend(String step) async {
      // As a person does: tap the field, then type.
      await t.tap(field);
      await frames(300);
      await t.enterText(field, 'after $step');
      await frames(300);
      final e = t.widget<EditableText>(field);
      final line =
          '$step: text="${e.controller.text}" focus=${e.focusNode.hasFocus}';
      log.add(line);
      // ignore: avoid_print
      print('FOCUS $line');
      if (find.bySemanticsLabel('Send').evaluate().isNotEmpty) {
        await t.tap(find.bySemanticsLabel('Send'));
      }
      await frames(500);
    }

    await typeAndSend('start');
    await typeAndSend('a send');

    await t.longPress(find.text('after start').last);
    await frames();
    await t.binding.handlePopRoute(); // Android's Back closes it
    await frames();
    await typeAndSend('message actions');

    await t.longPress(find.bySemanticsLabel('Poke, hold for more'));
    await frames();
    await t.binding.handlePopRoute(); // Android's Back closes it
    await frames();
    await typeAndSend('poke picker');

    await t.tap(find.bySemanticsLabel('Stickers, GIFs and memes'));
    await frames();
    await t.binding.handlePopRoute(); // Android's Back closes it
    await frames();
    await typeAndSend('sticker tray');

    await t.tap(
      find
          .byWidgetPredicate((w) => w is VIconView && w.icon == VIcon.plus)
          .first,
    );
    await frames();
    await t.tap(find.text('Gallery'));
    await frames(1000);
    await t.binding.handlePopRoute();
    await frames(1000);
    await typeAndSend('gallery page');

    // ignore: avoid_print
    print('FOCUS LOG\n${log.join('\n')}');
    expect(
      log.where((l) => !l.contains('focus=true') || l.contains('text=""')),
      isEmpty,
      reason: log.join('\n'),
    );
  });
}
