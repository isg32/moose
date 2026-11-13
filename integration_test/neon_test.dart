import 'dart:async';
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
import 'package:moose/features/common/video_frame.dart';
import 'package:moose/features/media/media_viewer.dart';
import 'package:moose/features/moments/moment_burst.dart';
import 'package:moose/features/onboarding/onboarding_pages.dart';
import 'package:moose/net/config.dart';
import 'package:moose/net/local_store.dart';
import 'package:moose/net/background_check.dart';
import 'package:moose/net/neon_backend.dart';
import 'package:moose/net/neon_calls.dart';
import 'package:moose/net/phone_media.dart';
import 'package:moose/net/phone_voice.dart';
import 'package:moose/net/push.dart';
import 'package:moose/net/vault.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

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
    // The app's real storage and Keystore (the background check reads
    // them), wiped first so this is a brand-new phone.
    final dir = await getApplicationSupportDirectory();
    for (final name in [
      'moose.json',
      'moose.json.tmp',
      'background-check.json',
    ]) {
      final f = File('${dir.path}/$name');
      if (f.existsSync()) f.deleteSync();
    }
    const vault = SecureVault();
    for (final k in [
      'auth.email',
      'auth.password',
      'auth.cookie',
      'identity.x25519',
      'lock.pin',
      'lock.decoy',
      'lock.decoyName',
    ]) {
      await vault.write(k, null);
    }
    final backend = await NeonBackend.open(
      config!,
      vault: vault,
      dir: dir,
      label: 'e2e',
    );
    // The gallery answers with a photo drawn here; Firebase is real.
    final photos = _DrawnPhotos(backend.mediaDir);
    backend
      ..media = photos
      ..voice = PhoneVoice(backend.mediaDir)
      ..calls = NeonCalls(backend)
      ..notifyAway = (data) async {
        final n = await Push.describe(
          data,
          vault: backend.vault,
          store: backend.store,
        );
        if (n != null) await Push.show(n, id: n.moment ? 2 : 1);
      }
      ..pushToken = Push.token
      ..askNotifications = Push.ask;
    await Push.init(onWake: () => backend.wake?.call());
    expect(await Push.token(), isNotNull, reason: 'Firebase gave a token');
    var c = ProviderContainer(overrides: backend.overrides());
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

    // 6½ · A voice note, held on the mic and recorded for real, and one
    // back from her that plays to the end (C16, B7).
    final mic = find.bySemanticsLabel('Hold to record, tap for round video');
    final hold = await t.startGesture(t.getCenter(mic));
    for (var i = 0; i < 50; i++) {
      await t.pump(const Duration(milliseconds: 50));
    }
    await hold.up();
    await until(
      t,
      'our voice note',
      () => c.read(messagesProvider).last.body is VoiceBody,
      within: const Duration(seconds: 10),
    );
    final note = c.read(messagesProvider).lastWhere((m) => m.fromMe);
    expect(note.body, isA<VoiceBody>());
    final notePath = (note.body as VoiceBody).path;
    expect(notePath, isNotNull, reason: 'recorded to a file');
    expect(
      File(notePath!).readAsBytesSync().sublist(4, 8),
      'ftyp'.codeUnits,
      reason: 'an AAC (.m4a) recording',
    );
    await until(
      t,
      'her voice note, down and opened',
      () => c
          .read(messagesProvider)
          .any(
            (m) =>
                !m.fromMe &&
                m.body is VoiceBody &&
                (m.body as VoiceBody).path != null,
          ),
      within: const Duration(seconds: 60),
    );
    final hersVoice = c
        .read(messagesProvider)
        .lastWhere((m) => !m.fromMe && m.body is VoiceBody);
    final played = Completer<void>();
    await c
        .read(voiceProvider)!
        .play((hersVoice.body as VoiceBody).path!, onDone: played.complete);
    final started = DateTime.now();
    while (!played.isCompleted) {
      if (DateTime.now().difference(started).inSeconds > 8) {
        fail('her voice note never finished playing');
      }
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(
      DateTime.now().difference(started).inMilliseconds,
      greaterThan(1500),
      reason: 'it played its 2 s',
    );
    await frames(t);
    await shot('06b-voice');

    // 6¾ · Her video: its first frame in the bubble, playing in the viewer;
    // then a video from our gallery back to her (B5, C21).
    await until(
      t,
      'her video, down and opened',
      () => c
          .read(messagesProvider)
          .any(
            (m) =>
                !m.fromMe &&
                m.body is VideoBody &&
                (m.body as VideoBody).video.path != null,
          ),
      within: const Duration(seconds: 60),
    );
    final herVideo =
        (c
                    .read(messagesProvider)
                    .lastWhere((m) => !m.fromMe && m.body is VideoBody)
                    .body
                as VideoBody)
            .video;
    expect(
      File(herVideo.path!).readAsBytesSync().sublist(4, 8),
      'ftyp'.codeUnits,
    );
    await frames(t, 1000);
    await t.tap(find.byType(VideoFrame).last);
    await frames(t, 1000);
    expect(find.byType(MediaViewer), findsOneWidget);
    await t.tap(find.bySemanticsLabel('Play'));
    await until(
      t,
      'the video playing',
      () =>
          find.byType(VideoPlayer).evaluate().isNotEmpty &&
          find.bySemanticsLabel('Pause').evaluate().isNotEmpty,
      within: const Duration(seconds: 10),
    );
    await frames(t, 1200);
    await shot('06c-video');
    await t.binding.handlePopRoute();
    await frames(t);
    final copy = File('${backend.mediaDir.path}/ours.mp4')
      ..writeAsBytesSync(File(herVideo.path!).readAsBytesSync());
    photos.nextVideo = await videoOf(copy, id: 'ours-video');
    expect(photos.nextVideo!.duration!.inMilliseconds, greaterThan(2500));
    await t.tap(
      find
          .byWidgetPredicate((w) => w is VIconView && w.icon == VIcon.plus)
          .first,
    );
    await frames(t);
    await t.tap(find.text('Gallery'));
    await frames(t, 1000);
    await t.tap(find.bySemanticsLabel(RegExp('^Send')).last);
    await frames(t, 1000);
    expect(c.read(messagesProvider).last.body, isA<VideoBody>());

    // 6⅞ · Calls, phone to phone over WebRTC (K1–K5). We video-call her:
    // she picks up, her picture arrives, we hang up.
    await t.tap(find.bySemanticsLabel('Video call'));
    await until(
      t,
      'her video on our screen',
      () => (backend.calls! as NeonCalls).receivingVideo,
      within: const Duration(seconds: 45),
    );
    await frames(t, 2500);
    await shot('06d-video-call');
    await t.tap(find.bySemanticsLabel('End call'));
    await until(
      t,
      'the call row',
      () => c.read(messagesProvider).last.body is CallBody,
    );
    final row = c.read(messagesProvider).last.body as CallBody;
    expect(row.outcome, CallOutcome.answered);
    expect(row.video, isTrue);
    expect(row.length.inSeconds, greaterThanOrEqualTo(2));

    // She calls us back: it rings here, we answer, she hangs up.
    await type(t, 'call me');
    await frames(t, 200);
    await t.tap(find.bySemanticsLabel('Send'));
    await until(
      t,
      'her call ringing',
      () => find.text('Accept').evaluate().isNotEmpty,
      within: const Duration(seconds: 30),
    );
    await frames(t);
    await shot('06e-ringing');
    await t.tap(find.text('Accept'));
    await until(
      t,
      'her call connected',
      () =>
          find.text('Direct, phone to phone · encrypted').evaluate().isNotEmpty,
      within: const Duration(seconds: 30),
    );
    await until(
      t,
      'her hanging up',
      () => find.text('Direct, phone to phone · encrypted').evaluate().isEmpty,
      within: const Duration(seconds: 30),
    );
    await frames(t);

    // 7 · Doodles: her board, then ours, drawn on by both (C29–C31).
    await t.tap(
      find
          .byWidgetPredicate((w) => w is VIconView && w.icon == VIcon.doodle)
          .last,
    );
    await frames(t);
    await until(
      t,
      'her board',
      () => c
          .read(doodlesProvider)
          .any(
            (d) =>
                d.name == "Aatika's board" &&
                d.strokes.any((s) => s.by == 'partner'),
          ),
    );
    await frames(t);
    expect(find.text("Aatika's board"), findsWidgets);
    await t.tap(find.text('New doodle').first);
    await frames(t);
    await type(t, 'Sunday plans');
    await frames(t, 300);
    await t.tap(find.text('Create'));
    await frames(t, 1000);
    final board = c
        .read(doodlesProvider)
        .firstWhere((d) => d.name == 'Sunday plans');
    final g = await t.startGesture(const Offset(100, 500));
    for (var i = 0; i < 24; i++) {
      await g.moveBy(const Offset(9, -6));
      await t.pump(const Duration(milliseconds: 16));
    }
    await g.up();
    await until(
      t,
      'her heart on our board',
      () => c
          .read(doodlesProvider)
          .firstWhere((d) => d.id == board.id)
          .strokes
          .any((s) => s.by == 'partner'),
    );
    final ours = c.read(doodlesProvider).firstWhere((d) => d.id == board.id);
    expect(ours.strokes.where((s) => s.by == 'me'), hasLength(1));
    await frames(t, 800);
    await shot('07-doodle');
    await t.tap(find.bySemanticsLabel('Back'));
    await frames(t);
    await t.tap(
      find
          .byWidgetPredicate((w) => w is VIconView && w.icon == VIcon.chat)
          .last,
    );
    await frames(t);

    // 8 · Away: Home is pressed, a message comes, Firebase wakes the
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

    // 9 · Aatika loses her phone: her new one shows a code, we approve it
    // from Settings › Partner, and she's back under a new key (C9, C37).
    final oldPartner = c.read(pairingProvider).partner.id;
    final oldCode = c.read(pairingProvider).securityCode;
    await type(t, 'lost your phone?');
    await frames(t, 200);
    await t.tap(find.bySemanticsLabel('Send'));
    await until(
      t,
      'her new phone\'s code',
      () => c
          .read(messagesProvider)
          .any(
            (m) => !m.fromMe && m.quote().text.startsWith('new phone code '),
          ),
      within: const Duration(seconds: 60),
    );
    final newCode = c
        .read(messagesProvider)
        .lastWhere((m) => m.quote().text.startsWith('new phone code '))
        .quote()
        .text
        .substring('new phone code '.length);
    await t.tap(
      find
          .byWidgetPredicate((w) => w is VIconView && w.icon == VIcon.gear)
          .last,
    );
    await frames(t);
    await t.tap(find.text('Aatika').first);
    await frames(t);
    await t.tap(find.text('Their new phone'));
    await frames(t);
    await t.enterText(find.byType(EditableText).last, newCode);
    await frames(t, 300);
    await t.tap(find.text('Join'));
    await until(
      t,
      'the approve page',
      () => find.byType(RepairRequestPage).evaluate().isNotEmpty,
    );
    await frames(t);
    await shot('09-new-phone');
    await t.tap(find.text("It's Aatika, approve"));
    await until(
      t,
      'the new pairing',
      () => c.read(pairingProvider).partner.id != oldPartner,
    );
    expect(c.read(pairingProvider).securityCode, isNot(oldCode));
    await until(
      t,
      'hello from her new phone',
      () => c
          .read(messagesProvider)
          .any(
            (m) => !m.fromMe && m.quote().text == "it's me, on my new phone 📱",
          ),
      within: const Duration(seconds: 60),
    );
    await t.binding.handlePopRoute(); // Android's Back, off the Partner page
    await frames(t);
    await t.tap(
      find
          .byWidgetPredicate((w) => w is VIconView && w.icon == VIcon.chat)
          .last,
    );
    await frames(t);

    // 9½ · Moose is closed: the background check (every 15 s in this
    // build) finds her message and notifies, without taking it. Opened
    // again, Moose takes it.
    await type(t, 'closing');
    await frames(t, 200);
    await t.tap(find.bySemanticsLabel('Send'));
    await until(t, '"closing" sent', () {
      final last = c.read(messagesProvider).lastWhere((m) => m.fromMe);
      return last.quote().text == 'closing' &&
          last.delivery != Delivery.pending;
    });
    await Push.clear();
    await t.pumpWidget(const SizedBox.shrink());
    await t.pump(const Duration(seconds: 1));
    c.dispose(); // the live socket is gone with it
    BackgroundCheck.init();
    await BackgroundCheck.start();
    expect(await BackgroundCheck.running, isTrue);
    final closedAt = DateTime.now();
    while (DateTime.now().difference(closedAt).inSeconds < 70) {
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    expect(await BackgroundCheck.lastCheck(), isNotNull, reason: 'it checked');
    expect(
      (await backend.api.inbox()).length,
      greaterThan(0),
      reason: 'the check only peeks: her message still waits',
    );
    await BackgroundCheck.stop();
    final reopened = await NeonBackend.open(
      config,
      vault: vault,
      dir: dir,
      label: 'e2e',
    );
    c = ProviderContainer(overrides: reopened.overrides());
    await t.pumpWidget(
      UncontrolledProviderScope(container: c, child: const MooseApp()),
    );
    await until(
      t,
      'her message from while we were closed',
      () => c
          .read(messagesProvider)
          .any((m) => !m.fromMe && m.quote().text == 'while you were closed'),
      within: const Duration(seconds: 40),
    );
    await frames(t);

    // 10 · Bye.
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
    await shot('08-bye');

    // 6 · The conversation is on the phone, and the server holds nothing.
    final all = c.read(messagesProvider);
    await reopened.store.flush();
    final again = await LocalStore.open(dir);
    expect(again.messages.length, all.length);
    expect(again.partner?.name, 'Aatika');
    expect(again.theme.wallpaper.builtin, 'moss', reason: 'the theme is kept');
    expect(
      again.doodles.map((d) => d.name),
      containsAll(["Aatika's board", 'Sunday plans']),
      reason: 'the boards are kept',
    );
    expect(await reopened.api.inbox(), isEmpty);
    await t.pumpWidget(const SizedBox.shrink());
    c.dispose();
    File('${dir.path}/moose.json').deleteSync();
  }, timeout: const Timeout(Duration(minutes: 9)));
}

/// The gallery, for the test: one photo, drawn on the phone.
class _DrawnPhotos implements MediaSource {
  _DrawnPhotos(this.dir);
  final Directory dir;

  /// Picked next instead of a drawn photo.
  Media? nextVideo;

  @override
  Future<List<Media>> gallery() async {
    final video = nextVideo;
    if (video != null) {
      nextVideo = null;
      return [video];
    }
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
