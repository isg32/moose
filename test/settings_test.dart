import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moose/app/app.dart';
import 'package:moose/app/router.dart';
import 'package:moose/data/models.dart';
import 'package:moose/data/providers.dart';
import 'package:moose/features/onboarding/onboarding_pages.dart';
import 'package:moose/features/settings/settings_pages.dart';

/// Settings end to end: storage, lock after, About, and unpairing.
void main() {
  Future<void> frames(WidgetTester t, [int ms = 700]) async {
    for (var i = 0; i < ms; i += 50) {
      await t.pump(const Duration(milliseconds: 50));
    }
  }

  testWidgets('clear photos, set lock after, read About, then unpair', (
    t,
  ) async {
    t.view.physicalSize = const Size(1170, 2532);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    final c = ProviderContainer();
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

    // Storage: clearing photos frees them.
    await t.scrollUntilVisible(
      find.text('Media on this phone'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await t.tap(find.text('Media on this phone'));
    await frames(t);
    await t.tap(find.text('Clear').first);
    await frames(t, 200);
    expect(c.read(storageProvider).first.bytes, 0);
    await t.tap(find.text('Settings').last);
    await frames(t);

    // Privacy › Lock after.
    await t.scrollUntilVisible(
      find.text('Lock after'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await t.tap(find.text('Lock after'));
    await frames(t);
    await t.tap(find.text('1 min'));
    await frames(t);
    expect(c.read(settingsProvider).lockAfter, LockAfter.m1);

    // About: Idris's layout, with the developer.
    await t.scrollUntilVisible(
      find.text('Version 0.14.1 · licences, developer'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await t.tap(find.text('Version 0.14.1 · licences, developer'));
    await frames(t);
    expect(find.text('Moose'), findsWidgets);
    await t.scrollUntilVisible(
      find.text('Sapan Gajjar'),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('isg32'), findsOneWidget);
    Navigator.of(t.element(find.byType(AboutPage))).pop();
    await frames(t);

    // Partner › Unpair, typed to confirm, lands on Welcome.
    await t.scrollUntilVisible(
      find.text('Aatika'),
      -300,
      scrollable: find.byType(Scrollable).first,
    );
    await t.tap(find.text('Aatika'));
    await frames(t);
    await t.scrollUntilVisible(
      find.bySemanticsLabel('Unpair'),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    await t.tap(find.bySemanticsLabel('Unpair'));
    await frames(t);
    await t.enterText(find.byType(EditableText).last, 'unpair');
    await frames(t, 100);
    await t.tap(find.text('Unpair').last);
    await frames(t, 1000);
    expect(c.read(sessionProvider).paired, isFalse);
    expect(find.byType(WelcomePage), findsOneWidget);
    expect(t.takeException(), isNull);

    await t.pumpWidget(const SizedBox.shrink());
    await t.pump(const Duration(seconds: 5));
  });
}
