import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moose/app/app.dart';
import 'package:moose/app/router.dart';
import 'package:moose/data/models.dart';
import 'package:moose/data/providers.dart';
import 'package:moose/features/doodles/board_page.dart';

/// Doodles end to end: make a board, draw, undo and redo, erase, lasso.
void main() {
  Future<void> frames(WidgetTester t, [int ms = 700]) async {
    for (var i = 0; i < ms; i += 50) {
      await t.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> stroke(WidgetTester t, Offset from, List<Offset> steps) async {
    final g = await t.startGesture(from);
    for (final d in steps) {
      for (var i = 0; i < 8; i++) {
        await g.moveBy(d / 8);
        await t.pump(const Duration(milliseconds: 16));
      }
    }
    await g.up();
    await frames(t, 200);
  }

  testWidgets('a new board: draw, undo, redo, erase, lasso and delete', (
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
        child: const MooseApp(initialRoute: Routes.doodles),
      ),
    );
    await frames(t);

    await t.tap(find.bySemanticsLabel('New doodle').first);
    await frames(t);
    await t.enterText(find.byType(EditableText), 'Weekend');
    await t.tap(find.text('Create'));
    await frames(t);
    expect(find.byType(BoardPage), findsOneWidget);
    final id = c.read(doodlesProvider).first.id;
    List<Stroke> strokes() =>
        c.read(doodlesProvider).firstWhere((d) => d.id == id).strokes;
    expect(c.read(messagesProvider).last.body, isA<SystemBody>());

    await stroke(t, const Offset(100, 400), [const Offset(150, 40)]);
    await stroke(t, const Offset(100, 600), [const Offset(150, 0)]);
    expect(strokes().length, 2);
    expect(strokes().first.tool, PenTool.brush);

    await t.tap(find.bySemanticsLabel('Undo'));
    await frames(t, 200);
    expect(strokes().length, 1);
    await t.tap(find.bySemanticsLabel('Redo'));
    await frames(t, 200);
    expect(strokes().length, 2);

    // The eraser takes the stroke it crosses.
    await t.tap(find.bySemanticsLabel('Eraser'));
    await frames(t, 200);
    await stroke(t, const Offset(175, 560), [const Offset(0, 80)]);
    expect(strokes().length, 1);

    // The lasso picks the first stroke; Delete takes it away.
    await t.tap(find.bySemanticsLabel('Lasso'));
    await frames(t, 200);
    await stroke(t, const Offset(70, 340), [
      const Offset(220, 0),
      const Offset(0, 140),
      const Offset(-220, 0),
      const Offset(0, -140),
    ]);
    expect(find.text('1 stroke selected'), findsOneWidget);
    await t.tap(find.bySemanticsLabel('Delete'));
    await frames(t, 200);
    expect(strokes(), isEmpty);
    expect(t.takeException(), isNull);

    await t.pumpWidget(const SizedBox.shrink());
    await t.pump(const Duration(seconds: 5));
  });
}
