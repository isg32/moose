import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moose/app/app.dart';
import 'package:moose/data/models.dart';
import 'package:moose/data/providers.dart';
import 'package:moose/data/repositories.dart';
import 'package:moose/mock/mock_repositories.dart';
import 'package:moose/features/chat/composer.dart';

void main() {
  Future<ProviderContainer> open(WidgetTester t) async {
    t.view.physicalSize = const Size(1080, 2400);
    t.view.devicePixelRatio = 2.625;
    addTearDown(t.view.reset);
    final c = ProviderContainer();
    addTearDown(c.dispose);
    c
        .read(sessionProvider.notifier)
        .set(c.read(sessionProvider).copyWith(locked: false));
    await t.pumpWidget(
      UncontrolledProviderScope(container: c, child: const MooseApp()),
    );
    await t.pump(const Duration(milliseconds: 600));
    return c;
  }

  Message hers(String text) => Message(
    id: text,
    fromMe: false,
    at: DateTime.now(),
    body: TextBody(text),
  );

  testWidgets('a new message a little way up glides into view', (t) async {
    final c = await open(t);
    final list = t.widget<ListView>(find.byType(ListView).first);
    list.controller!.jumpTo(120);
    await t.pump();
    final repo = c.read(chatRepositoryProvider) as MockChatRepository;
    repo.push(Incoming(hers('look up')));
    for (var i = 0; i < 20; i++) {
      await t.pump(const Duration(milliseconds: 50));
    }
    expect(list.controller!.offset, 0);
    await t.pumpWidget(const SizedBox.shrink());
    await t.pump(const Duration(seconds: 5));
  });

  testWidgets('far up, it waits on the jump arrow with a count', (t) async {
    final c = await open(t);
    final list = t.widget<ListView>(find.byType(ListView).first);
    list.controller!.jumpTo(900);
    await t.pump();
    await t.pump(const Duration(milliseconds: 100));
    final repo = c.read(chatRepositoryProvider) as MockChatRepository;
    repo.push(Incoming(hers('one')));
    repo.push(Incoming(hers('two')));
    for (var i = 0; i < 10; i++) {
      await t.pump(const Duration(milliseconds: 50));
    }
    expect(list.controller!.offset, 900, reason: 'stays where you were');
    expect(find.text('2'), findsWidgets);
    await t.pumpWidget(const SizedBox.shrink());
    await t.pump(const Duration(seconds: 5));
  });

  testWidgets('the composer rides on top of the keyboard', (t) async {
    t.view.physicalSize = const Size(1080, 2400);
    t.view.devicePixelRatio = 2.625;
    addTearDown(t.view.reset);
    final c = ProviderContainer();
    addTearDown(c.dispose);
    c
        .read(sessionProvider.notifier)
        .set(c.read(sessionProvider).copyWith(locked: false));
    await t.pumpWidget(
      UncontrolledProviderScope(container: c, child: const MooseApp()),
    );
    await t.pump(const Duration(milliseconds: 600));
    final screen = t.view.physicalSize.height / t.view.devicePixelRatio;
    final closed = t.getRect(find.byType(Composer)).bottom;
    expect(closed, lessThan(screen - 80), reason: 'above the tab pill');

    final last = find.text("call me when you're up ☀️");
    expect(last, findsOneWidget);
    final lastBefore = t.getRect(last.first);

    // The keyboard starts to rise: still shorter than where the composer
    // rests, so the composer doesn't move (no dip).
    t.view.viewInsets = const FakeViewPadding(bottom: 40 * 2.625);
    await t.pump(const Duration(milliseconds: 16));
    expect(t.getRect(find.byType(Composer)).bottom, closed);

    // All the way up: 336 dp.
    t.view.viewInsets = const FakeViewPadding(bottom: 336 * 2.625);
    await t.pump(const Duration(milliseconds: 100));
    final open = t.getRect(find.byType(Composer)).bottom;
    expect(open, lessThanOrEqualTo(screen - 336));
    expect(open, greaterThan(screen - 336 - 30), reason: 'right on top of it');
    // The conversation didn't move.
    expect(t.getRect(last.first), lastBefore);

    t.view.resetViewInsets();
    await t.pump(const Duration(milliseconds: 100));
    expect(t.getRect(find.byType(Composer)).bottom, closed);
    await t.pumpWidget(const SizedBox.shrink());
    await t.pump(const Duration(seconds: 5));
  });
}
