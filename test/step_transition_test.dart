import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:moose/app/router.dart';

/// A step that remembers it was built once.
class _Step extends StatefulWidget {
  const _Step(this.label);
  final String label;

  @override
  State<_Step> createState() => _StepState();
}

class _StepState extends State<_Step> {
  static final alive = <String>{};

  @override
  void initState() {
    super.initState();
    alive.add(widget.label);
  }

  @override
  void dispose() {
    alive.remove(widget.label);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Center(child: Text(widget.label));
}

/// A setup step covered by another (the code page under the QR scanner)
/// stays alive, so it's there to take what the page on top hands back.
void main() {
  testWidgets('a covered step stays alive and gets the result', (t) async {
    String? got;
    final router = GoRouter(
      initialLocation: '/join',
      routes: [
        GoRoute(
          path: '/join',
          pageBuilder: (context, state) => fadePage(state, const _Step('join')),
        ),
        GoRoute(
          path: '/scan',
          pageBuilder: (context, state) => fadePage(state, const _Step('scan')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await t.pumpWidget(CupertinoApp.router(routerConfig: router));
    await t.pumpAndSettle();

    final ctx = t.element(find.text('join'));
    final result = GoRouter.of(ctx).push<String>('/scan').then((r) => got = r);
    await t.pumpAndSettle();
    expect(_StepState.alive, containsAll(['join', 'scan']));

    router.pop('F9VA95');
    await t.pumpAndSettle();
    await result;
    expect(got, 'F9VA95');
    expect(_StepState.alive, contains('join'));
    expect(find.text('join'), findsOneWidget);
  });
}
