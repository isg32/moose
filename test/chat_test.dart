import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moose/app/app.dart';
import 'package:moose/core/icons/v_icons.dart';
import 'package:moose/core/theme/v_colors.dart';
import 'package:moose/data/chat_theme.dart';
import 'package:moose/data/models.dart';
import 'package:moose/data/providers.dart';
import 'package:moose/features/chat/chat_page.dart';
import 'package:moose/features/moments/moment_burst.dart';
import 'package:moose/mock/mock_repositories.dart';

/// The chat end to end on the mock: send, Aatika replies, react, reply,
/// change the theme for both, poke, and a moment coming back.
void main() {
  Future<ProviderContainer> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final c = ProviderContainer(
      overrides: [
        chatRepositoryProvider.overrideWith((ref) {
          final repo = MockChatRepository(
            replyDelay: const Duration(milliseconds: 300),
          );
          ref.onDispose(repo.dispose);
          return repo;
        }),
      ],
    );
    addTearDown(c.dispose);
    c
        .read(sessionProvider.notifier)
        .set(c.read(sessionProvider).copyWith(locked: false));
    await tester.pumpWidget(
      UncontrolledProviderScope(container: c, child: const MooseApp()),
    );
    await tester.pump(const Duration(milliseconds: 600));
    return c;
  }

  /// Lets [ms] pass a frame at a time, so animations run to their end.
  Future<void> settle(WidgetTester tester, [int ms = 600]) async {
    for (var t = 0; t < ms; t += 50) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 5));
  }

  testWidgets('send a message; it is seen and Aatika replies', (tester) async {
    final c = await open(tester);
    expect(find.byType(ChatPage), findsOneWidget);
    await tester.enterText(find.byType(EditableText), 'dinner at 8?');
    await settle(tester);
    await tester.tap(
      find.byWidgetPredicate((w) => w is VIconView && w.icon == VIcon.send),
    );
    await settle(tester);
    expect(find.text('dinner at 8?'), findsOneWidget);
    await settle(tester, 2500);
    final last = c.read(messagesProvider).lastWhere((m) => m.fromMe);
    expect(last.delivery, Delivery.seen);
    expect(c.read(messagesProvider).last.fromMe, isFalse);
    expect(tester.takeException(), isNull);
    await close(tester);
  });

  testWidgets('long-press a message to react and to reply', (tester) async {
    final c = await open(tester);
    await tester.longPress(find.text('that was the best call omg'));
    await settle(tester);
    expect(find.text('Delete for me'), findsOneWidget);
    await tester.tap(find.text('🔥'));
    await settle(tester);
    final m = c
        .read(messagesProvider)
        .firstWhere(
          (m) =>
              m.body is TextBody &&
              (m.body as TextBody).text == 'that was the best call omg',
        );
    expect(m.reactions.single.emoji, '🔥');

    await tester.longPress(find.text('that was the best call omg'));
    await settle(tester);
    await tester.tap(find.text('Reply'));
    await settle(tester);
    // The quote sits above the field until sent or cancelled: the message
    // shows twice, in the chat and in the quote.
    expect(find.text('that was the best call omg'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
    await close(tester);
  });

  testWidgets('the theme sheet changes the wallpaper for both', (tester) async {
    final c = await open(tester);
    // The wallpaper beside one of Aatika's messages (hers sit on the left).
    final chat = tester.getRect(find.byType(ChatPage));
    final beside = Offset(
      chat.right - 12,
      tester.getCenter(find.text('that was the best call omg')).dy,
    );
    await tester.longPressAt(beside);
    await settle(tester);
    expect(find.text('Apply for both'), findsOneWidget);
    await tester.tap(find.text('paper'));
    await settle(tester);
    // Shown live behind the sheet…
    expect(c.read(chatThemeProvider).wallpaper.builtin, 'paper');
    await tester.tap(find.text('Apply for both'));
    await settle(tester);
    // …kept, with a note in the chat.
    expect(c.read(chatThemeProvider).isLight, isTrue);
    final note = c.read(messagesProvider).last.body as SystemBody;
    expect(note.text, 'You changed the theme to Paper');
    expect(tester.takeException(), isNull);

    // Dismissing without Apply puts the old theme back.
    await tester.longPressAt(beside);
    await settle(tester);
    await tester.tap(find.text('moss'));
    await settle(tester);
    await tester.tapAt(Offset(chat.center.dx, chat.top + 80));
    await settle(tester);
    expect(
      c.read(chatThemeProvider).wallpaper,
      const WallpaperRef.builtin('paper'),
    );
    await close(tester);
  });

  testWidgets('poke, then a hug from the picker, and one comes back', (
    tester,
  ) async {
    final c = await open(tester);
    final poke = find.byWidgetPredicate(
      (w) => w is VIconView && w.icon == VIcon.poke,
    );
    await tester.tap(poke.first);
    await settle(tester);
    expect(c.read(messagesProvider).last.body, isA<MomentBody>());
    // Aatika pokes back: close her burst first.
    await settle(tester, 900);
    expect(find.text('POKE'), findsOneWidget);
    await tester.tap(find.text('Close'));
    await settle(tester);

    await tester.longPress(poke.first);
    await settle(tester);
    expect(find.text('Hug'), findsOneWidget);
    await tester.tap(find.text('Hug'));
    await settle(tester);
    expect(
      (c.read(messagesProvider).last.body as MomentBody).moment,
      VMoment.hug,
    );
    // Aatika sends it back while the app is open: the burst.
    await settle(tester, 900);
    expect(find.byType(MomentBurst), findsOneWidget);
    expect(find.text('HUG'), findsOneWidget);
    await tester.tap(find.text('Close'));
    await settle(tester);
    expect(find.byType(MomentBurst), findsNothing);
    expect(tester.takeException(), isNull);
    await close(tester);
  });

  testWidgets('a burst takes the keyboard down, then gives it back', (
    tester,
  ) async {
    final c = await open(tester);
    await tester.tap(find.byType(EditableText).first);
    await settle(tester);
    expect(tester.testTextInput.isVisible, isTrue);

    // A hug lands while typing: the system keyboard would cover it.
    c.read(incomingMomentProvider.notifier).show(VMoment.hug);
    await settle(tester);
    expect(find.byType(MomentBurst), findsOneWidget);
    expect(tester.testTextInput.isVisible, isFalse);
    expect(find.byType(BackdropFilter), findsWidgets);

    await tester.tap(find.text('Close'));
    await settle(tester);
    expect(find.byType(MomentBurst), findsNothing);
    expect(tester.testTextInput.isVisible, isTrue);
    expect(tester.takeException(), isNull);
    await close(tester);
  });

  testWidgets('the decoy chat is empty and sends nothing', (tester) async {
    final c = await open(tester);
    c
        .read(sessionProvider.notifier)
        .set(c.read(sessionProvider).copyWith(decoy: true));
    await settle(tester);
    expect(find.text('Say hi to Neha'), findsOneWidget);
    expect(find.text('that was the best call omg'), findsNothing);
    await close(tester);
  });
}
