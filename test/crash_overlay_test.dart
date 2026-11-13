import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moose/features/crash_overlay.dart';
import 'package:moose/platform/crash_log.dart';

void main() {
  testWidgets('a report shows over the app, and Close dismisses it', (t) async {
    await t.pumpWidget(
      const CupertinoApp(home: CrashOverlay(child: Text('app'))),
    );
    expect(find.text('Something broke'), findsNothing);
    CrashLog.instance.report(StateError('boom'), StackTrace.current);
    await t.pump();
    expect(find.text('Something broke'), findsOneWidget);
    expect(find.text('Copy details'), findsOneWidget);
    expect(find.text('Save to Downloads'), findsOneWidget);
    await t.tap(find.text('Back to Moose'));
    await t.pump();
    expect(find.text('Something broke'), findsNothing);
  });
}
