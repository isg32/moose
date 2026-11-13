import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/icons/v_icons.dart';
import '../core/theme/v_text.dart';
import '../core/theme/v_tokens.dart';
import '../core/widgets/v_glass.dart';
import '../core/widgets/v_ink.dart';
import '../data/providers.dart';
import '../data/models.dart';
import '../features/calls/call_page.dart';
import '../features/common/overlay.dart';
import '../features/onboarding/onboarding_pages.dart';
import '../features/moments/moment_burst.dart';

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
    // viewPadding: steady while the keyboard comes and goes.
    final bottom = MediaQuery.viewPaddingOf(context).bottom;
    const bar = AppShell.pillBottom + AppShell.pillHeight;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onBack();
      },
      child: Stack(
        children: [
          Positioned.fill(
            child: _TabSwap(index: shell.currentIndex, child: shell),
          ),
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
              items: AppShell.tabs,
              index: shell.currentIndex,
              onTap: (i) {
                // A field on the tab being left keeps no keyboard.
                FocusManager.instance.primaryFocus?.unfocus();
                shell.goBranch(i, initialLocation: i == shell.currentIndex);
              },
            ),
          ),
          // A call ringing opens the incoming call screen (K2).
          const _CallListener(),
          // A hug, poke, kiss or miss-you arriving covers everything (C25).
          Consumer(
            builder: (context, ref, _) {
              final moment = ref.watch(incomingMomentProvider);
              // On a call the moment flies over the call instead (K3).
              if (moment == null || ref.watch(inCallProvider)) {
                return const SizedBox.shrink();
              }
              final partner = ref.read(pairingProvider).partner.name;
              void close() =>
                  ref.read(incomingMomentProvider.notifier).dismiss();
              return Positioned.fill(
                child: MomentBurst(
                  key: ValueKey(moment),
                  moment: moment,
                  from: partner,
                  onClose: close,
                  onBack: () {
                    close();
                    ref.read(momentCooldownProvider.notifier).send(moment);
                  },
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _CallListener extends ConsumerWidget {
  const _CallListener();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(repairRequestProvider, (_, asked) async {
      if (!asked) return;
      ref.read(repairRequestProvider.notifier).set(false);
      final ok = await pushPage<bool>(
        context,
        (_) => const RepairRequestPage(),
      );
      final partner = ref.read(pairingProvider).partner.name;
      ref
          .read(messagesProvider.notifier)
          .send(
            SystemBody(
              SystemKind.paired,
              ok == true
                  ? "Paired with $partner's new phone"
                  : "You didn't approve a new phone",
            ),
          );
    });
    ref.listen(incomingCallProvider, (_, video) {
      if (video == null) return;
      ref.read(incomingCallProvider.notifier).clear();
      answerCall(context, ref, video: video);
    });
    return const SizedBox.shrink();
  }
}

/// Switching tabs: the new tab fades up and settles in, not a hard cut.
class _TabSwap extends StatefulWidget {
  const _TabSwap({required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  State<_TabSwap> createState() => _TabSwapState();
}

class _TabSwapState extends State<_TabSwap>
    with SingleTickerProviderStateMixin {
  late final _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 280),
    value: 1,
  );

  @override
  void didUpdateWidget(_TabSwap old) {
    super.didUpdateWidget(old);
    if (old.index != widget.index) _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _c,
    child: widget.child,
    builder: (context, child) {
      if (_c.value == 1) return child!;
      final t = Curves.easeOutCubic.transform(_c.value);
      return Opacity(
        opacity: 0.35 + 0.65 * t,
        child: Transform.scale(scale: 0.98 + 0.02 * t, child: child),
      );
    },
  );
}
