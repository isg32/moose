import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:moose/app/app.dart';
import 'package:moose/core/theme/v_colors.dart';
import 'package:moose/data/providers.dart';
import 'package:moose/features/chat/composer.dart';

/// Things only a real phone shows: the real keyboard under the composer,
/// and the moment burst moving (three frames apart).
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('keyboard and motion', (t) async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    c
        .read(sessionProvider.notifier)
        .set(c.read(sessionProvider).copyWith(locked: false));
    await binding.convertFlutterSurfaceToImage();
    await t.pumpWidget(
      UncontrolledProviderScope(container: c, child: const MooseApp()),
    );
    await t.pump(const Duration(seconds: 1));

    final view = t.view;
    final screen = view.physicalSize.height / view.devicePixelRatio;
    await t.tap(find.byType(EditableText).first);
    for (var i = 0; i < 30; i++) {
      await t.pump(const Duration(milliseconds: 50));
    }
    final keyboard = view.viewInsets.bottom / view.devicePixelRatio;
    expect(keyboard, greaterThan(100), reason: 'the keyboard opened');
    final bottom = t.getRect(find.byType(Composer)).bottom;
    expect(bottom, lessThanOrEqualTo(screen - keyboard));
    await binding.takeScreenshot('look-keyboard');
    FocusManager.instance.primaryFocus?.unfocus();
    for (var i = 0; i < 20; i++) {
      await t.pump(const Duration(milliseconds: 50));
    }

    c.read(incomingMomentProvider.notifier).show(VMoment.hug);
    for (final n in [1, 2, 3]) {
      for (var i = 0; i < 8; i++) {
        await t.pump(const Duration(milliseconds: 50));
      }
      await binding.takeScreenshot('look-burst-$n');
    }
  });
}
