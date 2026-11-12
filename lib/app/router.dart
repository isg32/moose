import 'package:flutter/cupertino.dart';
import 'package:go_router/go_router.dart';

import '../core/theme/v_tokens.dart';
import '../features/chat/chat_page.dart';
import '../features/doodles/doodles_page.dart';
import '../features/settings/settings_page.dart';
import 'shell.dart';

/// Every path in the app.
abstract final class Routes {
  static const chat = '/chat';
  static const doodles = '/doodles';
  static const settings = '/settings';
}

final _rootKey = GlobalKey<NavigatorState>(debugLabel: 'root');

/// The app's routes: three tabs under the pill (as Idris).
GoRouter buildRouter({String initial = Routes.chat}) => GoRouter(
  navigatorKey: _rootKey,
  initialLocation: initial,
  routes: [
    StatefulShellRoute.indexedStack(
      builder: (context, state, shell) => AppShell(shell: shell),
      branches: [
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: Routes.chat,
              pageBuilder: (context, state) =>
                  const NoTransitionPage(child: ChatPage()),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: Routes.doodles,
              pageBuilder: (context, state) =>
                  const NoTransitionPage(child: DoodlesPage()),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: Routes.settings,
              pageBuilder: (context, state) =>
                  const NoTransitionPage(child: SettingsPage()),
            ),
          ],
        ),
      ],
    ),
  ],
);

/// Full-screen pages fade in; nothing slides or bounces.
Page<void> fadePage(GoRouterState state, Widget child) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    child: child,
    transitionDuration: VMotion.standard,
    reverseTransitionDuration: VMotion.standard,
    transitionsBuilder: (context, animation, _, child) => FadeTransition(
      opacity: CurvedAnimation(parent: animation, curve: VMotion.curve),
      child: child,
    ),
  );
}
