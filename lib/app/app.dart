import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/theme/v_theme.dart';
import '../data/providers.dart';
import '../features/crash_overlay.dart';
import '../features/lock/lock_pages.dart';
import '../features/onboarding/onboarding_pages.dart';
import '../platform/secure_window.dart';
import 'moose_theme.dart';
import 'router.dart';

/// The app root: the shared theme's wallpaper, ink and glass apply
/// everywhere.
class MooseApp extends ConsumerStatefulWidget {
  const MooseApp({super.key, this.initialRoute, this.splash = false});

  /// Where to start (tests and previews); the chat otherwise.
  final String? initialRoute;

  /// Show the wordmark while starting (C1); on for a real start.
  final bool splash;

  @override
  ConsumerState<MooseApp> createState() => _MooseAppState();
}

class _MooseAppState extends ConsumerState<MooseApp> {
  /// Tells the router when pairing changes.
  final _paired = ValueNotifier(true);

  late final GoRouter _router = buildRouter(
    initial: widget.initialRoute ?? Routes.chat,
    refresh: _paired,
    paired: () => _paired.value,
  );

  late bool _splash = widget.splash;
  late final AppLifecycleListener _life;
  DateTime? _left;

  @override
  void initState() {
    super.initState();
    _paired.value = ref.read(sessionProvider).paired;
    if (_splash) {
      Future<void>.delayed(const Duration(milliseconds: 900), () {
        if (mounted) setState(() => _splash = false);
      });
    }
    // "Hide in recent apps": now, and whenever it's switched.
    unawaited(SecureWindow.set(ref.read(settingsProvider).hideInRecents));
    ref.listenManual(
      settingsProvider.select((s) => s.hideInRecents),
      (_, on) => unawaited(SecureWindow.set(on)),
    );
    // Leaving Moose for longer than "Lock after" locks it (C36).
    _life = AppLifecycleListener(
      onHide: () => _left = DateTime.now(),
      onShow: () {
        final left = _left;
        _left = null;
        if (left == null) return;
        final after = ref.read(settingsProvider).lockAfter.duration;
        if (DateTime.now().difference(left) >= after) {
          ref.read(sessionProvider.notifier).lock();
        }
      },
    );
  }

  @override
  void dispose() {
    _life.dispose();
    _router.dispose();
    _paired.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(chatThemeProvider);
    final session = ref.watch(sessionProvider);
    _paired.value = session.paired;
    final locked = session.paired && session.locked && session.pin.isNotEmpty;
    return CupertinoApp.router(
      title: 'Moose',
      debugShowCheckedModeBanner: false,
      theme: VTheme.of(theme.palette),
      routerConfig: _router,
      builder: (context, child) => MooseTheme(
        theme: theme,
        child: CrashOverlay(
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Locked or starting, the app stays alive underneath but is
              // neither shown nor reachable.
              Offstage(
                offstage: locked || _splash,
                child: TickerMode(enabled: !locked && !_splash, child: child!),
              ),
              if (_splash)
                const SplashView()
              else if (locked)
                const LockScreen(),
            ],
          ),
        ),
      ),
    );
  }
}
