import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moose/app/app.dart';
import 'package:moose/core/icons/v_icons.dart';
import 'package:moose/core/theme/v_colors.dart';
import 'package:moose/core/widgets/v_ink.dart';
import 'package:moose/data/chat_theme.dart';
import 'package:moose/data/providers.dart';

/// Opens the shell on a phone-sized view on a dark wallpaper and a light
/// one, walks the three tabs, and fails on any exception or overflow.
void main() {
  for (final (wallpaper, ink) in [
    ('night', VColors.white),
    ('paper', VColors.black),
  ]) {
    testWidgets('$wallpaper wallpaper: tabs open in the right ink', (
      tester,
    ) async {
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
      await tester.pump(const Duration(milliseconds: 600));
      expect(tester.takeException(), isNull);

      // The Chat tab opens first, and the page title is drawn in the ink the
      // wallpaper asks for.
      final title = find.text('Chat').last;
      expect(title, findsOneWidget);
      expect(VInk.of(tester.element(title)), ink);

      // Inactive tabs show only their icon in the pill.
      for (final (icon, title) in [
        (VIcon.doodle, 'Doodles'),
        (VIcon.gear, 'Settings'),
        (VIcon.chat, 'Chat'),
      ]) {
        await tester.tap(
          find.byWidgetPredicate((w) => w is VIconView && w.icon == icon).first,
        );
        await tester.pump(const Duration(milliseconds: 600));
        expect(tester.takeException(), isNull);
        expect(find.text(title), findsWidgets);
      }

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
    });
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
