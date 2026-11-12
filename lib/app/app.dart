import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/theme/v_theme.dart';
import '../data/providers.dart';
import '../features/crash_overlay.dart';
import 'moose_theme.dart';
import 'router.dart';

/// The app root: the shared theme's wallpaper, ink and glass apply
/// everywhere.
class MooseApp extends ConsumerStatefulWidget {
  const MooseApp({super.key});

  @override
  ConsumerState<MooseApp> createState() => _MooseAppState();
}

class _MooseAppState extends ConsumerState<MooseApp> {
  late final GoRouter _router = buildRouter();

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(chatThemeProvider);
    return CupertinoApp.router(
      title: 'Moose',
      debugShowCheckedModeBanner: false,
      theme: VTheme.of(theme.palette),
      routerConfig: _router,
      builder: (context, child) => MooseTheme(
        theme: theme,
        child: CrashOverlay(child: child!),
      ),
    );
  }
}
