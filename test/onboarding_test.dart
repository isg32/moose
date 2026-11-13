import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moose/app/app.dart';
import 'package:moose/data/providers.dart';
import 'package:moose/features/chat/chat_page.dart';
import 'package:moose/features/lock/lock_pages.dart';
import 'package:moose/features/onboarding/onboarding_pages.dart';
import 'package:moose/mock/mock_data.dart';

/// Onboarding and the lock end to end on the mock.
void main() {
  Future<void> frames(WidgetTester t, [int ms = 700]) async {
    for (var i = 0; i < ms; i += 50) {
      await t.pump(const Duration(milliseconds: 50));
    }
  }

  Future<ProviderContainer> open(
    WidgetTester t, {
    bool paired = false,
    bool locked = false,
  }) async {
    t.view.physicalSize = const Size(1170, 2532);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    final c = ProviderContainer();
    addTearDown(c.dispose);
    c
        .read(sessionProvider.notifier)
        .set(c.read(sessionProvider).copyWith(paired: paired, locked: locked));
    await t.pumpWidget(
      UncontrolledProviderScope(container: c, child: const MooseApp()),
    );
    await frames(t);
    return c;
  }

  Future<void> close(WidgetTester t) async {
    await t.pumpWidget(const SizedBox.shrink());
    await t.pump(const Duration(seconds: 6));
  }

  testWidgets('a new phone: welcome, name, background, pair, chat', (t) async {
    final c = await open(t);
    expect(find.byType(WelcomePage), findsOneWidget);
    await t.tap(find.text('Start'));
    await frames(t);
    await t.enterText(find.byType(EditableText), 'Sapan');
    await frames(t, 100);
    await t.tap(find.text('Continue'));
    await frames(t);
    expect(find.text('Staying in touch'), findsOneWidget);
    await t.tap(find.text('Allow'));
    await frames(t, 200);
    expect(find.text('2 of 2 allowed'), findsOneWidget);
    await t.tap(find.text('Continue'));
    await frames(t);
    expect(find.text(MockData.inviteCode), findsOneWidget);
    // Aatika joins.
    await frames(t, 4500);
    expect(find.byType(PairedPage), findsOneWidget);
    expect(find.text('Sapan & Aatika'), findsOneWidget);
    await t.tap(find.text('Start chatting'));
    await frames(t);
    expect(find.byType(ChatPage), findsOneWidget);
    expect(c.read(sessionProvider).paired, isTrue);
    expect(t.takeException(), isNull);
    await close(t);
  });

  testWidgets('a wrong code says so; the right one pairs', (t) async {
    await open(t);
    await t.tap(find.text('I have a code'));
    await frames(t);
    await t.tap(find.text('Continue'));
    await frames(t);
    await t.tap(find.text('Allow'));
    await frames(t, 200);
    await t.tap(find.text('Continue'));
    await frames(t);
    await t.enterText(find.byType(EditableText), 'ABC123');
    await frames(t, 100);
    await t.tap(find.text('Join'));
    await frames(t, 200);
    expect(
      find.text('That code has expired. Ask for a new one.'),
      findsOneWidget,
    );
    await t.enterText(find.byType(EditableText), MockData.inviteCode);
    await frames(t, 100);
    await t.tap(find.text('Join'));
    await frames(t);
    expect(find.byType(PairedPage), findsOneWidget);
    expect(t.takeException(), isNull);
    await close(t);
  });

  testWidgets('the decoy PIN opens the decoy chat', (t) async {
    await open(t, paired: true, locked: true);
    expect(find.byType(LockScreen), findsOneWidget);
    for (final d in MockData.decoyPin.split('')) {
      await t.tap(find.bySemanticsLabel(d));
      await t.pump(const Duration(milliseconds: 50));
    }
    await frames(t);
    expect(find.text('Say hi to ${MockData.decoyName}'), findsOneWidget);
    expect(t.takeException(), isNull);
    await close(t);
  });
}
