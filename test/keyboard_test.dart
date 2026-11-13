import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moose/app/app.dart';
import 'package:moose/data/providers.dart';
import 'package:moose/features/chat/composer.dart';

void main() {
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

    // A 336 dp keyboard.
    t.view.viewInsets = const FakeViewPadding(bottom: 336 * 2.625);
    await t.pump(const Duration(milliseconds: 100));
    final open = t.getRect(find.byType(Composer)).bottom;
    expect(open, lessThanOrEqualTo(screen - 336));
    expect(open, greaterThan(screen - 336 - 30), reason: 'right on top of it');

    t.view.resetViewInsets();
    await t.pump(const Duration(milliseconds: 100));
    expect(t.getRect(find.byType(Composer)).bottom, closed);
    await t.pumpWidget(const SizedBox.shrink());
    await t.pump(const Duration(seconds: 5));
  });
}
