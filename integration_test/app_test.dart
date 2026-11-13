import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:moose/app/app.dart';
import 'package:moose/core/icons/v_icons.dart';
import 'package:moose/core/theme/v_colors.dart';
import 'package:moose/data/models.dart';
import 'package:moose/data/providers.dart';
import 'package:moose/features/chat/chat_page.dart';
import 'package:moose/features/doodles/board_page.dart';
import 'package:moose/features/lock/lock_pages.dart';
import 'package:moose/features/moments/moment_burst.dart';
import 'package:moose/features/onboarding/onboarding_pages.dart';
import 'package:moose/mock/mock_data.dart';
import 'package:moose/mock/mock_repositories.dart';

/// Moose end to end on a phone, against the mock partner (Phase 3): a new
/// phone pairs, chats, pokes, calls, sends stickers and songs, draws, and
/// locks. Phase 4 runs the same journey against Neon and a second phone.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> frames(WidgetTester t, [int ms = 700]) async {
    for (var i = 0; i < ms; i += 50) {
      await t.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> shot(String name) async {
    try {
      await binding.takeScreenshot(name);
    } on Object {
      // Screenshots are a bonus; the journey is the test.
    }
  }

  /// Taps a tab in the pill, as a person would.
  Future<void> tab(WidgetTester t, VIcon icon) async {
    await t.tap(
      find.byWidgetPredicate((w) => w is VIconView && w.icon == icon).last,
      warnIfMissed: false,
    );
    await frames(t);
  }

  Future<void> pin(WidgetTester t, String digits) async {
    for (final d in digits.split('')) {
      await t.tap(find.bySemanticsLabel(d));
      await t.pump(const Duration(milliseconds: 80));
    }
    await frames(t);
  }

  testWidgets('the whole journey on a phone', (t) async {
    final c = ProviderContainer(
      overrides: [
        chatRepositoryProvider.overrideWith((ref) {
          final repo = MockChatRepository(
            replyDelay: const Duration(milliseconds: 600),
          );
          ref.onDispose(repo.dispose);
          return repo;
        }),
      ],
    );
    addTearDown(c.dispose);
    // A brand-new phone: not paired, no lock yet.
    c
        .read(sessionProvider.notifier)
        .set(c.read(sessionProvider).copyWith(paired: false, locked: false));
    await binding.convertFlutterSurfaceToImage();
    await t.pumpWidget(
      UncontrolledProviderScope(container: c, child: const MooseApp()),
    );
    await frames(t, 1000);

    // 1 · Onboarding and pairing (C2–C8).
    expect(find.byType(WelcomePage), findsOneWidget);
    await shot('01-welcome');
    await t.tap(find.text('Start'));
    await frames(t);
    await t.enterText(find.byType(EditableText), 'Sapan');
    await frames(t, 200);
    await t.tap(find.text('Continue'));
    await frames(t);
    await t.tap(find.text('Allow'));
    await frames(t, 300);
    await t.tap(find.text('Continue'));
    await frames(t);
    expect(find.text(MockData.inviteCode), findsOneWidget);
    await shot('02-pair');
    await frames(t, 4600);
    expect(find.byType(PairedPage), findsOneWidget);
    await shot('03-paired');
    await t.tap(find.text('Start chatting'));
    await frames(t, 1000);
    expect(find.byType(ChatPage), findsOneWidget);
    await shot('04-chat');

    // 2 · Chat: send, Aatika reads and replies (C15, C16).
    final before = c.read(messagesProvider).length;
    await t.enterText(find.byType(EditableText).first, 'dinner at 8?');
    await frames(t, 200);
    await t.tap(find.bySemanticsLabel('Send'));
    await frames(t, 3500);
    final sent = c.read(messagesProvider).lastWhere((m) => m.fromMe);
    expect(sent.delivery, Delivery.seen);
    expect(c.read(messagesProvider).length, greaterThan(before + 1));
    await shot('05-reply');

    // React to her last message (B13).
    final hers = c
        .read(messagesProvider)
        .lastWhere((m) => !m.fromMe && m.body is TextBody);
    await t.longPress(find.text((hers.body as TextBody).text).last);
    await frames(t);
    await shot('06-actions');
    await t.tap(find.bySemanticsLabel(RegExp('^React ❤️')));
    await frames(t);
    expect(
      c
          .read(messagesProvider)
          .firstWhere((m) => m.id == hers.id)
          .reactions
          .any((r) => r.mine),
      isTrue,
    );

    // 3 · A hug from the picker, and one back as a burst (C24, C25).
    await t.longPress(find.bySemanticsLabel('Poke, hold for more'));
    await frames(t);
    await shot('07-poke-picker');
    await t.tap(find.bySemanticsLabel(RegExp('^Send a Hug')));
    await frames(t, 1800);
    expect(find.byType(MomentBurst), findsOneWidget);
    await shot('08-hug-burst');
    await t.tap(find.text('Close'));
    await frames(t);

    // 4 · A call: Aatika answers, then hang up (K1, K3, K5).
    await t.tap(find.bySemanticsLabel('Voice call'));
    await frames(t, 4000);
    expect(find.text('Direct, phone to phone · encrypted'), findsOneWidget);
    await shot('09-voice-call');
    await t.tap(find.bySemanticsLabel('End'));
    await frames(t);
    expect(
      (c.read(messagesProvider).last.body as CallBody).outcome,
      CallOutcome.answered,
    );

    // 5 · A sticker from the tray, and 15 s of a song (S1, C27, C28).
    await t.tap(find.bySemanticsLabel('Stickers, GIFs and memes'));
    await frames(t);
    await shot('10-stickers');
    await t.tap(find.bySemanticsLabel('Sticker').first);
    await frames(t);
    expect(c.read(messagesProvider).last.body, isA<StickerBody>());
    await t.tap(
      find
          .byWidgetPredicate((w) => w is VIconView && w.icon == VIcon.plus)
          .first,
    );
    await frames(t);
    await t.tap(find.text('Music'));
    await frames(t);
    await t.enterText(find.byType(EditableText).last, 'sienna');
    await frames(t, 1200);
    await t.tap(find.text('Sienna').first);
    await frames(t);
    await shot('11-range');
    await t.tap(find.text('Send to Aatika'));
    await frames(t);
    expect(
      (c.read(messagesProvider).last.body as MusicBody).song.title,
      'Sienna',
    );

    // 6 · Doodles: a new board, and draw on it (C29–C31).
    await tab(t, VIcon.doodle);
    await shot('12-doodles');
    await t.tap(find.bySemanticsLabel('Sunday plans'));
    await frames(t);
    expect(find.byType(BoardPage), findsOneWidget);
    final strokes = c
        .read(doodlesProvider)
        .firstWhere((d) => d.id == 'sunday')
        .strokes
        .length;
    final g = await t.startGesture(const Offset(80, 600));
    for (var i = 0; i < 24; i++) {
      await g.moveBy(const Offset(10, -5));
      await t.pump(const Duration(milliseconds: 16));
    }
    await g.up();
    await frames(t, 300);
    expect(
      c
          .read(doodlesProvider)
          .firstWhere((d) => d.id == 'sunday')
          .strokes
          .length,
      strokes + 1,
    );
    await shot('13-board');
    await t.tap(find.bySemanticsLabel('Back'));
    await frames(t);

    // 7 · Settings: turn on the app lock with a PIN (C36, C11).
    await tab(t, VIcon.gear);
    await shot('14-settings');
    c.read(sessionProvider.notifier).setPin(MockData.pin);
    c
        .read(sessionProvider.notifier)
        .setDecoy(MockData.decoyPin, MockData.decoyName);

    // 8 · Locked: a wrong PIN, the decoy, then the real one (C13, C14).
    c.read(sessionProvider.notifier).lock();
    await frames(t);
    expect(find.byType(LockScreen), findsOneWidget);
    await pin(t, '0000');
    expect(find.textContaining('Wrong PIN'), findsOneWidget);
    await shot('15-lock-wrong');
    await pin(t, MockData.decoyPin);
    await tab(t, VIcon.chat);
    expect(find.text('Say hi to ${MockData.decoyName}'), findsOneWidget);
    await shot('16-decoy');
    c.read(sessionProvider.notifier).lock();
    await frames(t);
    await pin(t, MockData.pin);
    expect(find.text('Aatika'), findsWidgets);
    expect(VMoment.hug.color, isNot(VColors.white));
    await shot('17-unlocked');
  });
}
