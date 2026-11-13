import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moose/app/app.dart';
import 'package:moose/app/router.dart';
import 'package:moose/data/chat_theme.dart';
import 'package:moose/data/providers.dart';
import 'package:moose/net/updater.dart';

/// An updater held at one state, for drawing the card and sheet.
class _Held extends Updater {
  _Held(this.held);
  final UpdateState held;
  final calls = <String>[];

  @override
  UpdateState build() => held;

  @override
  Future<void> download() async => calls.add('download');

  @override
  Future<void> install() async => calls.add('install');

  @override
  Future<void> allowInstalls() async => calls.add('allow');
}

const _release = UpdateRelease(
  version: '0.32.0',
  notes: ['Moose updates itself', 'Smoother tabs'],
  url: 'u',
  sha256: 's',
  size: 44 * 1024 * 1024,
  versionCode: 2038,
);

/// The update card in Chat and Settings, and its sheet in every state, on
/// a dark wallpaper and a light one.
void main() {
  Future<void> frames(WidgetTester t, [int ms = 700]) async {
    for (var i = 0; i < ms; i += 50) {
      await t.pump(const Duration(milliseconds: 50));
    }
  }

  final states = <String, (UpdateState, String)>{
    'available': (const UpdateAvailable(_release), 'Update · 44 MB'),
    'downloading': (
      const UpdateDownloading(_release, 11 * 1024 * 1024),
      '11 MB of 44 MB',
    ),
    'ready': (const UpdateReady(_release, '/x.apk'), 'Install'),
    'needs permission': (
      const UpdateNeedsPermission(_release, '/x.apk'),
      'Allow',
    ),
    'installing': (
      const UpdateInstalling(_release, '/x.apk', confirming: true),
      'Confirm on the screen Android shows',
    ),
    'failed': (
      const UpdateFailed(
        'The download was damaged. Try again.',
        release: _release,
      ),
      'Try again',
    ),
    'signed differently': (
      const UpdateFailed('Reinstall once', release: _release, reinstall: true),
      'Open GitHub',
    ),
  };

  for (final wallpaper in ['night', 'paper']) {
    for (final MapEntry(:key, value: (held, button)) in states.entries) {
      testWidgets('$wallpaper: $key', (t) async {
        t.view.physicalSize = const Size(1170, 2532);
        t.view.devicePixelRatio = 3;
        addTearDown(t.view.reset);
        final updater = _Held(held);
        final c = ProviderContainer(
          overrides: [updaterProvider.overrideWith(() => updater)],
        );
        addTearDown(c.dispose);
        c
            .read(sessionProvider.notifier)
            .set(c.read(sessionProvider).copyWith(locked: false));
        c
            .read(chatThemeProvider.notifier)
            .set(ChatTheme(wallpaper: WallpaperRef.builtin(wallpaper)));
        await t.pumpWidget(
          UncontrolledProviderScope(container: c, child: const MooseApp()),
        );
        await frames(t);

        // Chat: the card under the header.
        expect(find.text('Moose 0.32.0 is out'), findsOneWidget);
        await t.tap(find.text('Moose 0.32.0 is out'));
        await frames(t);
        expect(find.text('Moose 0.32.0'), findsOneWidget);
        expect(find.text('Smoother tabs'), findsOneWidget);
        expect(find.textContaining(button), findsWidgets);
        if (held is UpdateAvailable) {
          await t.tap(find.text('Update · 44 MB'));
          expect(updater.calls, ['download']);
        }
        if (held is UpdateReady) {
          await t.tap(find.text('Install'));
          expect(updater.calls, ['install']);
        }
        expect(t.takeException(), isNull);

        await t.pumpWidget(const SizedBox.shrink());
        await t.pump(const Duration(seconds: 5));
      });
    }
  }

  testWidgets('Settings shows the card and Check for updates', (t) async {
    t.view.physicalSize = const Size(1170, 2532);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    final c = ProviderContainer(
      overrides: [
        updaterProvider.overrideWith(
          () => _Held(const UpdateAvailable(_release)),
        ),
      ],
    );
    addTearDown(c.dispose);
    c
        .read(sessionProvider.notifier)
        .set(c.read(sessionProvider).copyWith(locked: false));
    await t.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: const MooseApp(initialRoute: Routes.settings),
      ),
    );
    await frames(t);
    await t.scrollUntilVisible(
      find.text('Check for updates'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    // Settings' card, and Chat's (its tab stays alive behind).
    expect(find.text('Moose 0.32.0 is out'), findsNWidgets(2));
    expect(find.text('Check for updates'), findsOneWidget);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox.shrink());
    await t.pump(const Duration(seconds: 5));
  });
}
