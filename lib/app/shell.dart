import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../core/icons/v_icons.dart';
import '../core/theme/v_text.dart';
import '../core/theme/v_tokens.dart';
import '../core/widgets/v_glass.dart';
import '../core/widgets/v_ink.dart';

/// The three tabs with the floating glass pill over them, and Cariño's
/// progressive blur along the bottom edge (as Idris's shell).
///
/// Back on any tab goes to Chat. Back on Chat shows "Swipe back again to
/// exit"; a second back within [exitWindow] closes the app.
class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  static const tabs = [
    VTabItem('Chat', VIcon.chat),
    VTabItem('Doodles', VIcon.doodle),
    VTabItem('Settings', VIcon.gear),
  ];

  static const exitWindow = Duration(seconds: 2);

  /// Height of the pill and its gap from the bottom (DESIGN.md › Layout).
  static const pillHeight = 62.0;
  static const pillBottom = 22.0;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  DateTime? _lastBack;
  bool _showExitHint = false;
  Timer? _hintTimer;

  @override
  void dispose() {
    _hintTimer?.cancel();
    super.dispose();
  }

  void _onBack() {
    final shell = widget.shell;
    if (shell.currentIndex != 0) {
      shell.goBranch(0);
      return;
    }
    final now = DateTime.now();
    if (_lastBack != null && now.difference(_lastBack!) < AppShell.exitWindow) {
      SystemNavigator.pop();
      return;
    }
    _lastBack = now;
    HapticFeedback.selectionClick();
    setState(() => _showExitHint = true);
    _hintTimer?.cancel();
    _hintTimer = Timer(AppShell.exitWindow, () {
      if (mounted) setState(() => _showExitHint = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final shell = widget.shell;
    final bottom = MediaQuery.paddingOf(context).bottom;
    const bar = AppShell.pillBottom + AppShell.pillHeight;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onBack();
      },
      child: Stack(
        children: [
          Positioned.fill(child: shell),
          // Content scrolling under the pill softens into a blur that is
          // strongest at the bottom edge.
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: VEdgeBlur(edge: VEdge.bottom, solid: bottom + bar, fade: 32),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: bottom + bar + 12,
            child: IgnorePointer(
              child: Center(
                child: AnimatedOpacity(
                  opacity: _showExitHint ? 1 : 0,
                  duration: VMotion.standard,
                  curve: VMotion.curve,
                  child: VGlass(
                    radius: VRadius.pill,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      child: Text(
                        'Swipe back again to exit',
                        style: VText.inter(
                          13,
                          weight: 500,
                        ).copyWith(color: VInk.of(context)),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: bottom + AppShell.pillBottom,
            child: VTabBar(
              stretch: true,
              items: AppShell.tabs,
              index: shell.currentIndex,
              onTap: (i) =>
                  shell.goBranch(i, initialLocation: i == shell.currentIndex),
            ),
          ),
        ],
      ),
    );
  }
}
