import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:moose/app/app.dart';
import 'package:moose/data/models.dart';
import 'package:moose/data/providers.dart';
import 'package:moose/features/chat/chat_page.dart';
import 'package:moose/features/moments/moment_burst.dart';
import 'package:moose/features/onboarding/onboarding_pages.dart';
import 'package:moose/net/config.dart';
import 'package:moose/net/local_store.dart';
import 'package:moose/net/neon_backend.dart';
import 'package:moose/net/vault.dart';
import 'package:path_provider/path_provider.dart';

/// Moose on this phone against the real Neon backend, with the partner
/// bot (test/neon/partner_bot_test.dart) on the computer as Aatika.
/// tool/e2e_neon.sh starts the bot and passes its code as PARTNER_CODE.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const code = String.fromEnvironment('PARTNER_CODE');

  Future<void> shot(String name) async {
    try {
      await binding.takeScreenshot('neon-$name');
    } on Object {
      // Screenshots are a bonus; the journey is the test.
    }
  }

  /// Pumps frames until [done] holds, failing after [within].
  Future<void> until(
    WidgetTester t,
    String what,
    bool Function() done, {
    Duration within = const Duration(seconds: 30),
  }) async {
    final end = DateTime.now().add(within);
    while (!done()) {
      if (DateTime.now().isAfter(end)) fail('timed out waiting for $what');
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> frames(WidgetTester t, [int ms = 700]) async {
    for (var i = 0; i < ms; i += 50) {
      await t.pump(const Duration(milliseconds: 50));
    }
  }

  testWidgets('pair with the bot and talk through Neon', skip: code.isEmpty, (
    t,
  ) async {
    final config = NeonConfig.fromEnvironment;
    expect(config, isNotNull, reason: 'build with env.json');
    final dir = await (await getTemporaryDirectory()).createTemp('moose-e2e');
    final backend = await NeonBackend.open(
      config!,
      vault: MemoryVault(),
      dir: dir,
      label: 'e2e',
    );
    final c = ProviderContainer(overrides: backend.overrides());
    addTearDown(c.dispose);
    await binding.convertFlutterSurfaceToImage();
    await t.pumpWidget(
      UncontrolledProviderScope(container: c, child: const MooseApp()),
    );
    await frames(t, 1000);

    // 1 · A new phone joins Aatika's code (C2, C3, C4, C6, C8).
    expect(find.byType(WelcomePage), findsOneWidget);
    await t.tap(find.text('I have a code'));
    await frames(t);
    await t.enterText(find.byType(EditableText), 'Sapan');
    await frames(t, 200);
    await t.tap(find.text('Continue'));
    await frames(t);
    await t.tap(find.text('Continue'));
    await frames(t);
    expect(find.byType(JoinPage), findsOneWidget);
    await t.enterText(find.byType(EditableText), code);
    await frames(t, 300);
    await shot('01-code');
    await t.tap(find.text('Join'));
    await until(
      t,
      'pairing',
      () => find.byType(PairedPage).evaluate().isNotEmpty,
    );
    await frames(t);
    final pairing = c.read(pairingProvider);
    expect(pairing.partner.name, 'Aatika');
    expect(pairing.securityCode, hasLength(12));
    await shot('02-paired');
    await t.tap(find.text('Start chatting'));
    await frames(t, 1000);
    expect(find.byType(ChatPage), findsOneWidget);

    // 2 · A text: Aatika types, hearts it, sees it and replies (C15).
    await t.enterText(find.byType(EditableText).first, 'dinner at 8?');
    await frames(t, 200);
    await t.tap(find.bySemanticsLabel('Send'));
    var typed = false;
    await until(t, 'her reply', () {
      typed |= c.read(pairingProvider).presence == Presence.typing;
      return c
          .read(messagesProvider)
          .any((m) => !m.fromMe && m.body is TextBody);
    });
    final mine = c.read(messagesProvider).firstWhere((m) => m.fromMe);
    await until(t, 'seen and ❤️', () {
      final m = c.read(messagesProvider).firstWhere((x) => x.id == mine.id);
      return m.delivery == Delivery.seen &&
          m.reactions.any((r) => r.emoji == '❤️' && !r.mine);
    });
    final reply = c.read(messagesProvider).lastWhere((m) => !m.fromMe);
    expect((reply.body as TextBody).text, 'on it 🥰');
    expect(reply.reply?.fromMe, isTrue, reason: 'she quoted my message');
    expect(reply.reply?.text, 'dinner at 8?');
    expect(typed, isTrue, reason: 'her typing dots showed');
    await frames(t);
    await shot('03-reply');

    // React back to her reply (B13).
    await t.longPress(find.text('on it 🥰').last);
    await frames(t);
    await t.tap(find.bySemanticsLabel(RegExp('^React ❤️')));
    await frames(t);

    // 3 · A hug, and one back as a burst (C24, C25).
    await t.longPress(find.bySemanticsLabel('Poke, hold for more'));
    await frames(t);
    await t.tap(find.bySemanticsLabel(RegExp('^Send a Hug')));
    await until(
      t,
      'her hug back',
      () => find.byType(MomentBurst).evaluate().isNotEmpty,
    );
    await frames(t, 1500);
    await shot('04-hug-back');
    await t.tap(find.text('Close'));
    await frames(t);

    // 4 · A sticker (S1).
    final before = c.read(messagesProvider).length;
    await t.tap(find.bySemanticsLabel('Stickers, GIFs and memes'));
    await frames(t);
    await t.tap(find.bySemanticsLabel('Sticker').first);
    await until(
      t,
      '"cute" for the sticker',
      () => c
          .read(messagesProvider)
          .skip(before)
          .any((m) => !m.fromMe && m.quote().text == 'cute 🥺'),
    );
    await frames(t);
    await shot('05-sticker');

    // 5 · Bye.
    await t.enterText(find.byType(EditableText).first, 'bye');
    await frames(t, 200);
    await t.tap(find.bySemanticsLabel('Send'));
    await until(
      t,
      'her bye',
      () => c
          .read(messagesProvider)
          .any((m) => !m.fromMe && m.quote().text == 'bye 👋'),
    );
    await frames(t);
    await shot('06-bye');

    // 6 · The conversation is on the phone, and the server holds nothing.
    final all = c.read(messagesProvider);
    await backend.store.flush();
    final again = await LocalStore.open(dir);
    expect(again.messages.length, all.length);
    expect(again.partner?.name, 'Aatika');
    expect(await backend.api.inbox(), isEmpty);
    await dir.delete(recursive: true);
    expect(File('${dir.path}/moose.json').existsSync(), isFalse);
  }, timeout: const Timeout(Duration(minutes: 5)));
}
