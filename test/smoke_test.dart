import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moose/app/app.dart';
import 'package:moose/core/theme/v_colors.dart';
import 'package:moose/data/chat_theme.dart';
import 'package:moose/data/models.dart';
import 'package:moose/data/providers.dart';
import 'package:moose/features/calls/call_page.dart';
import 'package:moose/features/chat/chat_page.dart';
import 'package:moose/features/chat/composer.dart';
import 'package:moose/features/chat/message_actions.dart';
import 'package:moose/features/chat/theme_sheet.dart';
import 'package:moose/features/common/overlay.dart';
import 'package:moose/features/doodles/board_page.dart';
import 'package:moose/features/doodles/doodle_sheets.dart';
import 'package:moose/features/doodles/doodles_page.dart';
import 'package:moose/features/lock/lock_pages.dart';
import 'package:moose/features/media/attach_sheet.dart';
import 'package:moose/features/media/media_pages.dart';
import 'package:moose/features/media/media_viewer.dart';
import 'package:moose/features/moments/moment_burst.dart';
import 'package:moose/features/moments/poke_picker.dart';
import 'package:moose/features/music/music_pages.dart';
import 'package:moose/features/onboarding/onboarding_pages.dart';
import 'package:moose/features/settings/settings_page.dart';
import 'package:moose/features/settings/settings_pages.dart';
import 'package:moose/features/stickers/sticker_maker.dart';
import 'package:moose/features/stickers/tray.dart';
import 'package:moose/mock/mock_data.dart';

/// Opens every screen on a small phone and a regular one, on a dark
/// wallpaper and a light one, and fails on any exception or overflow.
void main() {
  final screens = <String, Widget Function()>{
    // Onboarding, pairing and lock (C1–C14).
    'Splash': () => const SplashView(),
    'Welcome': () => const WelcomePage(),
    'Your name': () => const NamePage(),
    'Background': () => const BackgroundPage(),
    'Create pair': () => const CreatePairPage(joinsAfter: Duration(hours: 1)),
    'Enter code': () => const JoinPage(),
    'Scanner': () => const ScanPage(),
    'Paired': () => const PairedPage(),
    'Re-pair request': () => const RepairRequestPage(),
    'Re-pair waiting': () =>
        const RepairWaitingPage(approvesAfter: Duration(hours: 1)),
    'Lock': () => const LockScreen(),
    'Set PIN': () => const PinEntryPage(eyebrow: 'App lock', back: 'Privacy'),
    'Decoy PIN': () => const DecoyPinPage(),
    // Chat and its sheets (C15–C28, B13).
    'Message actions': () =>
        MessageActions(message: MockData.messages()[4], partner: 'Aatika'),
    'Theme sheet': () => const ThemeSheet(),
    'Wallpaper crop': () => const WallpaperCrop(photo: 'mock:3'),
    'Poke picker': () => const PokePicker(partner: 'Aatika'),
    for (final m in VMoment.values)
      'Burst · ${m.label}': () => MomentBurst(
        moment: m,
        from: 'Aatika',
        onBack: () {},
        onClose: () {},
        buzz: false,
      ),
    'Round recorder': () => RoundRecorder(
      length: ValueNotifier(const Duration(seconds: 9)),
      onCancel: () {},
      onStop: () {},
    ),
    'Attach sheet': () => const AttachSheet(),
    'Gallery': () => const GalleryPage(),
    'Preview': () => MediaPreview(media: MockData.gallery().take(3).toList()),
    'Camera': () => const CameraPage(),
    'Viewer': () => MediaViewer(
      items: [
        for (final m in MockData.gallery())
          ViewerItem(media: m, from: 'Aatika', at: MockData.mockNow),
      ],
      start: 2,
    ),
    'Sticker tray': () => const Tray(),
    'GIFs': () => const Tray(start: TrayTab.gifs),
    'Memes': () => const Tray(start: TrayTab.memes),
    'Photo sticker': () => const PhotoStickerPage(art: 7),
    'Sticker library': () => const StickerLibraryPage(),
    'Music search': () => const MusicSearchPage(),
    'Range picker': () => const RangePickerPage(song: MockData.sienna),
    // Calls (K1–K4).
    'Calling': () =>
        const CallPage(video: false, answersAfter: Duration(hours: 1)),
    'Incoming call': () => const CallPage(video: true, incoming: true),
    // Doodles (C29–C35).
    'Doodles': () => const DoodlesPage(),
    'Board': () => const BoardPage(id: 'sunday'),
    // Settings (C36–C41).
    'Settings': () => const SettingsPage(),
    'Partner': () => const PartnerPage(),
    'Storage': () => const StoragePage(),
    'Notifications': () => const NotificationsPage(),
    'About': () => const AboutPage(),
  };

  /// Sheets that need a screen under them, opened over the chat.
  final overChat = <String, Future<void> Function(BuildContext, WidgetRef)>{
    'Tool options': (c, r) async => showToolOptions(
      c,
      tool: PenTool.calligraphy,
      pen: const PenSettings(),
      argb: 0xFFFF5C7A,
    ),
    'Colour': (c, r) async =>
        showColourSheet(c, argb: 0xFFFF5C7A, recent: const [0xFF5BC0EB]),
    'New doodle': (c, r) async => showNewDoodle(c, partner: 'Aatika'),
    'Doodle sticker': (c, r) async =>
        showDoodleStickerSheet(c, r, MockData.sundayPlans()),
    'Received sticker': (c, r) async =>
        showReceivedSticker(c, r, MockData.stickerPacks()[2].stickers.first),
    'Unpair': (c, r) async => showUnpair(c, r),
    'Voice call': (c, r) async => pushPage<void>(
      c,
      (_) => const CallPage(video: false, answersAfter: Duration.zero),
    ),
    'Video call': (c, r) async => pushPage<void>(
      c,
      (_) => const CallPage(video: true, answersAfter: Duration.zero),
    ),
  };

  for (final (label, size, ratio) in [
    ('small phone', const Size(1080, 2220), 3.0),
    ('phone', const Size(1080, 2400), 2.625),
  ]) {
    for (final wallpaper in ['night', 'paper']) {
      group('$label, $wallpaper', () {
        Future<ProviderContainer> start(WidgetTester t) async {
          t.view.physicalSize = size;
          t.view.devicePixelRatio = ratio;
          addTearDown(t.view.reset);
          final c = ProviderContainer();
          addTearDown(c.dispose);
          c
              .read(chatThemeProvider.notifier)
              .set(ChatTheme(wallpaper: WallpaperRef.builtin(wallpaper)));
          c
              .read(sessionProvider.notifier)
              .set(c.read(sessionProvider).copyWith(locked: false));
          await t.pumpWidget(
            UncontrolledProviderScope(container: c, child: const MooseApp()),
          );
          await t.pump(const Duration(milliseconds: 600));
          return c;
        }

        Future<void> settle(WidgetTester t) async {
          for (var i = 0; i < 16; i++) {
            await t.pump(const Duration(milliseconds: 50));
          }
        }

        Future<void> close(WidgetTester t) async {
          await t.pumpWidget(const SizedBox.shrink());
          await t.pump(const Duration(seconds: 5));
        }

        testWidgets('Chat', (t) async {
          await start(t);
          expect(find.byType(ChatPage), findsOneWidget);
          expect(t.takeException(), isNull);
          await close(t);
        });

        for (final MapEntry(:key, :value) in screens.entries) {
          testWidgets(key, (t) async {
            await start(t);
            final chat = t.element(find.byType(ChatPage));
            unawaited(pushPage<void>(chat, (_) => value()));
            await settle(t);
            expect(t.takeException(), isNull, reason: key);
            await close(t);
          });
        }

        for (final MapEntry(:key, :value) in overChat.entries) {
          testWidgets(key, (t) async {
            await start(t);
            final chat = t.element(find.byType(ChatPage));
            unawaited(
              value(
                chat,
                t.state<ConsumerState<ChatPage>>(find.byType(ChatPage)).ref,
              ),
            );
            await settle(t);
            await settle(t);
            expect(t.takeException(), isNull, reason: key);
            await close(t);
          });
        }
      });
    }
  }

  test('VColors keeps the moment colours apart from the inks', () {
    for (final m in VMoment.values) {
      expect(m.color, isNot(VColors.white));
      expect(m.color, isNot(VColors.black));
    }
  });
}
