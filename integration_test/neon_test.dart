import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:moose/app/app.dart';
import 'package:moose/core/icons/v_icons.dart';
import 'package:moose/data/chat_theme.dart';
import 'package:moose/data/models.dart';
import 'package:moose/data/providers.dart';
import 'package:moose/features/chat/chat_page.dart';
import 'package:moose/features/moments/moment_burst.dart';
import 'package:moose/features/onboarding/onboarding_pages.dart';
import 'package:moose/net/config.dart';
import 'package:moose/net/local_store.dart';
import 'package:moose/net/neon_backend.dart';
import 'package:moose/net/phone_media.dart';
import 'package:moose/net/push.dart';
import 'package:moose/net/vault.dart';
import 'package:path_provider/path_provider.dart';

/// Moose on this phone against the real Neon backend and Firebase, with
/// Aatika emulated in Python on the computer (tool/partner/partner.py).
/// tool/e2e_neon.sh starts her and passes her code as PARTNER_CODE.
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

  /// Taps the composer, then types into it, as a person would. (enterText
  /// alone can't focus a field on a real-keyboard device.)
  Future<void> type(WidgetTester t, String text) async {
    final field = find.byType(EditableText).first;
    await t.tap(field);
    for (var i = 0; i < 6; i++) {
      await t.pump(const Duration(milliseconds: 50));
    }
    await t.enterText(field, text);
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
    // The gallery answers with a photo drawn here; Firebase is real.
    backend
      ..media = _DrawnPhotos(backend.mediaDir)
      ..pushToken = Push.token
      ..askNotifications = Push.ask;
    await Push.init(onWake: () => backend.wake?.call());
    expect(await Push.token(), isNotNull, reason: 'Firebase gave a token');
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

    // Aatika changed the shared theme as soon as we paired (C22).
    await until(
      t,
      'her theme',
      () => c.read(chatThemeProvider).wallpaper.builtin == 'dune',
    );
    expect(c.read(chatThemeProvider).glass, 0.6);

    // 2 · A text: Aatika types, hearts it, sees it and replies (C15).
    await type(t, 'dinner at 8?');
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

    // 5 · A photo from the gallery, and one back (C17–C19, B4).
    await t.tap(
      find
          .byWidgetPredicate((w) => w is VIconView && w.icon == VIcon.plus)
          .first,
    );
    await frames(t);
    await t.tap(find.text('Gallery'));
    await frames(t, 1000);
    await t.tap(find.bySemanticsLabel(RegExp('^Send')).last);
    await frames(t);
    final sentPhoto = c.read(messagesProvider).lastWhere((m) => m.fromMe);
    expect(sentPhoto.body, isA<PhotoBody>());
    await until(
      t,
      'her photo, down and opened',
      () => c
          .read(messagesProvider)
          .any(
            (m) =>
                !m.fromMe &&
                m.body is PhotoBody &&
                (m.body as PhotoBody).photos.single.path != null,
          ),
      within: const Duration(seconds: 60),
    );
    final hers = c
        .read(messagesProvider)
        .lastWhere((m) => !m.fromMe && m.body is PhotoBody);
    final photo = (hers.body as PhotoBody).photos.single;
    final bytes = File(photo.path!).readAsBytesSync();
    expect(bytes.sublist(0, 3), [0xFF, 0xD8, 0xFF], reason: 'a JPEG');
    expect(photo.aspect, closeTo(800 / 600, 0.01));
    expect((hers.body as PhotoBody).caption, 'for you 📸');
    await until(
      t,
      '"cute pic"',
      () => c
          .read(messagesProvider)
          .any((m) => !m.fromMe && m.quote().text == 'cute pic'),
    );
    await frames(t, 1000);
    await shot('06-photos');

    // 6 · Our theme for both of us.
    const moss = ChatTheme(wallpaper: WallpaperRef.builtin('moss'));
    c.read(chatThemeProvider.notifier).set(moss);
    c.read(chatRepositoryProvider).shareTheme(moss);
    await frames(t, 1500);

    // 7 · Away: Home is pressed, a message comes, Firebase wakes the
    // phone and a notification shows; then Moose is opened again.
    await type(t, 'brb');
    await frames(t, 200);
    if (find.bySemanticsLabel('Send').evaluate().isEmpty) {
      fail(
        [
          for (final e in find.byType(EditableText).evaluate())
            '${(e.widget as EditableText).controller.text} '
                'focus=${(e.widget as EditableText).focusNode.hasFocus} '
                'at ${t.getRect(find.byWidget(e.widget))}',
        ].join(' | '),
      );
    }
    await t.tap(find.bySemanticsLabel('Send'));
    // No frames while in the background: wait on the data, not the UI.
    final end = DateTime.now().add(const Duration(seconds: 120));
    while (!c
        .read(messagesProvider)
        .any((m) => !m.fromMe && m.quote().text == 'you there?')) {
      if (DateTime.now().isAfter(end)) fail('no "you there?" in 2 min');
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    await Future<void>.delayed(const Duration(seconds: 8)); // back in front
    await frames(t, 1000);
    await type(t, 'back!');
    await frames(t, 200);
    await t.tap(find.bySemanticsLabel('Send'));
    await frames(t, 1500);

    // 8 · Bye.
    await type(t, 'bye');
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
    await shot('07-bye');

    // 6 · The conversation is on the phone, and the server holds nothing.
    final all = c.read(messagesProvider);
    await backend.store.flush();
    final again = await LocalStore.open(dir);
    expect(again.messages.length, all.length);
    expect(again.partner?.name, 'Aatika');
    expect(again.theme.wallpaper.builtin, 'moss', reason: 'the theme is kept');
    expect(await backend.api.inbox(), isEmpty);
    await dir.delete(recursive: true);
    expect(File('${dir.path}/moose.json').existsSync(), isFalse);
  }, timeout: const Timeout(Duration(minutes: 5)));
}

/// The gallery, for the test: one photo, drawn on the phone.
class _DrawnPhotos implements MediaSource {
  _DrawnPhotos(this.dir);
  final Directory dir;

  @override
  Future<List<Media>> gallery() async {
    final rec = ui.PictureRecorder();
    ui.Canvas(rec)
      ..drawRect(
        const ui.Rect.fromLTWH(0, 0, 600, 800),
        ui.Paint()..color = const ui.Color(0xFF9DB2FF),
      )
      ..drawCircle(
        const ui.Offset(300, 400),
        200,
        ui.Paint()..color = const ui.Color(0xFFFFFFFF),
      );
    final image = await rec.endRecording().toImage(600, 800);
    final png = (await image.toByteData(format: ui.ImageByteFormat.png))!;
    await dir.create(recursive: true);
    final id = NeonChatRepository.uuid();
    final file = File('${dir.path}/$id')
      ..writeAsBytesSync(png.buffer.asUint8List());
    return [
      Media(
        id: id,
        art: 2,
        aspect: await aspectOf(file.readAsBytesSync()),
        bytes: file.lengthSync(),
        path: file.path,
      ),
    ];
  }

  @override
  Future<Media?> camera() async => (await gallery()).first;
}
