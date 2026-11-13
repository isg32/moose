import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moose/app/app.dart';
import 'package:moose/core/icons/v_icons.dart';
import 'package:moose/core/theme/v_colors.dart';
import 'package:moose/core/widgets/v_ink.dart';
import 'package:moose/data/chat_theme.dart';
import 'package:moose/data/providers.dart';
import 'package:moose/features/lock/lock_pages.dart';
import 'package:moose/mock/mock_data.dart';

/// Opens Moose as a phone would (locked), unlocks it, walks the three
/// tabs on a dark wallpaper and a light one, and fails on any exception or
/// overflow.
void main() {
  Future<void> frames(WidgetTester t, [int ms = 600]) async {
    for (var i = 0; i < ms; i += 50) {
      await t.pump(const Duration(milliseconds: 50));
    }
  }

  for (final (wallpaper, ink) in [
    ('night', VColors.white),
    ('paper', VColors.black),
  ]) {
    testWidgets(
      '$wallpaper wallpaper: unlock, then the tabs in the right ink',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 2.625;
        addTearDown(tester.view.reset);

        final container = ProviderContainer();
        addTearDown(container.dispose);
        container
            .read(chatThemeProvider.notifier)
            .set(ChatTheme(wallpaper: WallpaperRef.builtin(wallpaper)));

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const MooseApp(),
          ),
        );
        await frames(tester);
        expect(find.byType(LockScreen), findsOneWidget);
        for (final d in MockData.pin.split('')) {
          await tester.tap(find.bySemanticsLabel(d));
          await tester.pump(const Duration(milliseconds: 50));
        }
        await frames(tester);
        expect(find.byType(LockScreen), findsNothing);

        // The chat opens first, in the ink the wallpaper asks for.
        final name = find.text('Aatika').first;
        expect(VInk.of(tester.element(name)), ink);

        // Inactive tabs show only their icon in the pill.
        for (final (icon, title) in [
          (VIcon.doodle, 'Doodles'),
          (VIcon.gear, 'Settings'),
          (VIcon.chat, 'Aatika'),
        ]) {
          // The bar takes taps for itself and picks the tab by position, so
          // the icon is never the hit target.
          await tester.tap(
            find
                .byWidgetPredicate((w) => w is VIconView && w.icon == icon)
                .last,
            warnIfMissed: false,
          );
          await frames(tester);
          expect(tester.takeException(), isNull);
          expect(find.text(title), findsWidgets);
        }

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 5));
      },
    );
  }

  test('the ink follows the wallpaper, and a photo can be flipped', () {
    expect(const ChatTheme().isLight, isFalse);
    expect(
      const ChatTheme(wallpaper: WallpaperRef.builtin('paper')).isLight,
      isTrue,
    );
    // A light palette dimmed past 30 % goes back to white ink.
    expect(
      const ChatTheme(
        wallpaper: WallpaperRef.builtin('white'),
        dim: 0.4,
      ).isLight,
      isFalse,
    );
    expect(
      const ChatTheme(
        wallpaper: WallpaperRef.photo('/x.jpg'),
        ink: InkChoice.black,
      ).isLight,
      isTrue,
    );
  });
}
