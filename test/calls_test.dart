import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moose/app/app.dart';
import 'package:moose/data/models.dart';
import 'package:moose/data/providers.dart';
import 'package:moose/features/calls/call_page.dart';
import 'package:moose/mock/mock_repositories.dart';

/// Calls end to end on the mock: you call and Aatika answers; she calls
/// back when asked.
void main() {
  Future<void> frames(WidgetTester t, [int ms = 700]) async {
    for (var i = 0; i < ms; i += 50) {
      await t.pump(const Duration(milliseconds: 50));
    }
  }

  Future<ProviderContainer> open(WidgetTester t) async {
    t.view.physicalSize = const Size(1170, 2532);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    final c = ProviderContainer(
      overrides: [
        chatRepositoryProvider.overrideWith((ref) {
          final repo = MockChatRepository(
            replyDelay: const Duration(milliseconds: 200),
          );
          ref.onDispose(repo.dispose);
          return repo;
        }),
      ],
    );
    addTearDown(c.dispose);
    c
        .read(sessionProvider.notifier)
        .set(c.read(sessionProvider).copyWith(locked: false));
    await t.pumpWidget(
      UncontrolledProviderScope(container: c, child: const MooseApp()),
    );
    await frames(t);
    return c;
  }

  Future<void> close(WidgetTester t) async {
    await t.pumpWidget(const SizedBox.shrink());
    await t.pump(const Duration(seconds: 5));
  }

  testWidgets('call Aatika; she answers; hang up and the call is logged', (
    t,
  ) async {
    final c = await open(t);
    await t.tap(find.bySemanticsLabel('Voice call'));
    await frames(t);
    expect(find.text('Ringing…'), findsOneWidget);
    await frames(t, 4500);
    expect(find.text('Direct, phone to phone · encrypted'), findsOneWidget);
    await t.tap(find.bySemanticsLabel('End'));
    await frames(t);
    final row = c.read(messagesProvider).last.body as CallBody;
    expect(row.outcome, CallOutcome.answered);
    expect(row.length, greaterThan(Duration.zero));
    expect(t.takeException(), isNull);
    await close(t);
  });

  testWidgets('"call me" makes Aatika call back', (t) async {
    await open(t);
    await t.enterText(find.byType(EditableText), 'call me?');
    await frames(t, 200);
    await t.tap(find.bySemanticsLabel('Send'));
    await frames(t, 800);
    expect(find.byType(CallPage), findsOneWidget);
    expect(find.text('is calling you'), findsOneWidget);
    await t.tap(find.bySemanticsLabel('Accept'));
    await frames(t, 600);
    // A video call: her picture and the control bar.
    expect(find.bySemanticsLabel('End call'), findsOneWidget);
    await t.tap(find.bySemanticsLabel('End call'));
    await frames(t);
    expect(find.byType(CallPage), findsNothing);
    expect(t.takeException(), isNull);
    await close(t);
  });
}
