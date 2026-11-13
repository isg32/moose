import 'package:flutter/cupertino.dart';
import 'package:go_router/go_router.dart';

import '../core/widgets/v_motion_blur.dart';

import '../features/chat/chat_page.dart';
import '../features/doodles/doodles_page.dart';
import '../features/onboarding/onboarding_pages.dart';
import '../features/settings/settings_page.dart';
import 'shell.dart';

/// Every path in the app.
abstract final class Routes {
  static const chat = '/chat';
  static const doodles = '/doodles';
  static const settings = '/settings';
}

final _rootKey = GlobalKey<NavigatorState>(debugLabel: 'root');

/// The app's routes: three tabs under the pill (as Idris), and onboarding
/// until this phone is paired ([paired], re-checked when [refresh] fires).
GoRouter buildRouter({
  String initial = Routes.chat,
  Listenable? refresh,
  bool Function()? paired,
}) => GoRouter(
  navigatorKey: _rootKey,
  initialLocation: initial,
  refreshListenable: refresh,
  redirect: (context, state) {
    if (paired == null) return null;
    final loc = state.matchedLocation;
    final onboarding = loc.startsWith(OnboardingRoutes.welcome);
    if (!paired() && !onboarding && loc != OnboardingRoutes.paired) {
      return OnboardingRoutes.welcome;
    }
    if (paired() && onboarding) return Routes.chat;
    return null;
  },
  routes: [
    GoRoute(
      path: OnboardingRoutes.welcome,
      pageBuilder: (context, state) => fadePage(state, const WelcomePage()),
      routes: [
        GoRoute(
          path: 'name',
          pageBuilder: (context, state) => fadePage(
            state,
            NamePage(join: state.uri.queryParameters['join'] == '1'),
          ),
        ),
        GoRoute(
          path: 'background',
          pageBuilder: (context, state) => fadePage(
            state,
            BackgroundPage(join: state.uri.queryParameters['join'] == '1'),
          ),
        ),
        GoRoute(
          path: 'pair',
          pageBuilder: (context, state) =>
              fadePage(state, const CreatePairPage()),
        ),
        GoRoute(
          path: 'join',
          pageBuilder: (context, state) => fadePage(state, const JoinPage()),
        ),
        GoRoute(
          path: 'scan',
          pageBuilder: (context, state) => fadePage(state, const ScanPage()),
        ),
        GoRoute(
          path: 'waiting',
          pageBuilder: (context, state) =>
              fadePage(state, const RepairWaitingPage()),
        ),
      ],
    ),
    GoRoute(
      path: OnboardingRoutes.paired,
      pageBuilder: (context, state) => fadePage(state, const PairedPage()),
    ),
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

/// Onboarding's pages: they slide in the iOS way, and swipe back.
/// A setup or pairing step: the old step blurs out to the left and is gone
/// by half way, then the new one blurs in from the right (see
/// [stepTransition]); they never show their text over each other.
Page<void> fadePage(GoRouterState state, Widget child) =>
    CustomTransitionPage<void>(
      key: state.pageKey,
      child: child,
      transitionDuration: const Duration(milliseconds: 420),
      reverseTransitionDuration: const Duration(milliseconds: 380),
      transitionsBuilder: (context, animation, secondary, child) =>
          stepTransition(animation, secondary, child),
    );
