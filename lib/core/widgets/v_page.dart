import 'dart:ui' show ImageFilter;

import 'package:flutter/cupertino.dart';

import '../icons/v_icons.dart';
import '../theme/v_colors.dart';
import '../theme/v_palette.dart';
import '../theme/v_text.dart';
import '../theme/v_tokens.dart';
import 'v_buttons.dart';
import 'v_glass.dart';

/// Page title row: large Doto title with an optional trailing action, and an
/// optional eyebrow above it (the date on Today).
class VPageTitle extends StatelessWidget {
  const VPageTitle(
    this.title, {
    super.key,
    this.eyebrow,
    this.trailing,
    this.style,
  });

  final String title;
  final String? eyebrow;
  final Widget? trailing;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        VSpace.titleGutter,
        16,
        VSpace.titleGutter,
        14,
      ),
      child: Row(
        crossAxisAlignment: eyebrow == null
            ? CrossAxisAlignment.center
            : CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (eyebrow != null) ...[
                  Text(eyebrow!.toUpperCase(), style: VText.eyebrow),
                  const SizedBox(height: 8),
                ],
                Text(title, style: style ?? VText.title),
              ],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 12), trailing!],
        ],
      ),
    );
  }
}

/// "‹ Parent" link at the top of a detail page.
class VBackLink extends StatelessWidget {
  const VBackLink(this.label, {super.key, this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return VTappable(
      onTap: onTap ?? () => Navigator.of(context).maybePop(),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const VIconView(VIcon.back, size: 18, strokeWidth: 1.6),
            const SizedBox(width: 4),
            Text(label, style: VText.inter(14)),
          ],
        ),
      ),
    );
  }
}

/// Extra room at the bottom of pages for something floating over them
/// (the mini player), set by the shell or a page that shows one.
class VBottomInset extends InheritedWidget {
  const VBottomInset({super.key, required this.extra, required super.child});

  final double extra;

  static double of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<VBottomInset>()?.extra ?? 0;

  @override
  bool updateShouldNotify(VBottomInset old) => old.extra != extra;
}

/// Frame for a tab page: title, then scrolling content that clears the
/// floating tab bar.
class VTabPage extends StatelessWidget {
  const VTabPage({
    super.key,
    required this.title,
    required this.children,
    this.eyebrow,
    this.trailing,
    this.titleStyle,
    this.header,
    this.onRefresh,
    this.veil = false,
  });

  final String title;

  /// Lays the page veil (blur 30 + veil tint) over the shared wallpaper, for
  /// full pages like Settings. Otherwise the wallpaper shows through.
  final bool veil;
  final String? eyebrow;
  final Widget? trailing;
  final TextStyle? titleStyle;

  /// Pull to refresh (sync), when set.
  final Future<void> Function()? onRefresh;

  /// Widget between the title and the cards (e.g. a segmented control).
  final Widget? header;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: VColors.transparent,
      child: _UnderStatusBar(
        veil: veil,
        child: CustomScrollView(
          physics: _physics(onRefresh),
          slivers: [
            const _StatusBarSpace(),
            ?_refresh(onRefresh),
            SliverToBoxAdapter(
              child: VPageTitle(
                title,
                eyebrow: eyebrow,
                trailing: trailing,
                style: titleStyle,
              ),
            ),
            if (header != null)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: VSpace.gutter,
                  ),
                  child: header,
                ),
              ),
            SliverPadding(
              padding: EdgeInsets.fromLTRB(
                VSpace.gutter,
                0,
                VSpace.gutter,
                VSpace.tabBarClearance + VBottomInset.of(context),
              ),
              sliver: SliverList.list(children: _gapped(children)),
            ),
          ],
        ),
      ),
    );
  }
}

/// Frame for a pushed detail page: back link, title, optional action, then
/// scrolling content.
class VDetailPage extends StatelessWidget {
  const VDetailPage({
    super.key,
    required this.backLabel,
    required this.title,
    required this.children,
    this.action,
    this.titleStyle,
    this.onRefresh,
    this.veil = true,
  });

  final String backLabel;

  /// Lays the page veil over the shared wallpaper (on by default: detail
  /// pages are full pages).
  final bool veil;
  final String title;
  final Widget? action;
  final TextStyle? titleStyle;

  /// Pull to refresh (sync), when set.
  final Future<void> Function()? onRefresh;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: VColors.transparent,
      child: _UnderStatusBar(
        veil: veil,
        bottomSafe: true,
        child: CustomScrollView(
          physics: _physics(onRefresh),
          slivers: [
            const _StatusBarSpace(),
            ?_refresh(onRefresh),
            SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  VBackLink(backLabel),
                  Padding(
                    padding: const EdgeInsets.only(top: 0),
                    child: Transform.translate(
                      offset: const Offset(0, -6),
                      child: VPageTitle(
                        title,
                        trailing: action,
                        style: titleStyle,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SliverPadding(
              padding: EdgeInsets.fromLTRB(
                VSpace.gutter,
                0,
                VSpace.gutter,
                40 + VBottomInset.of(context),
              ),
              sliver: SliverList.list(children: _gapped(children)),
            ),
          ],
        ),
      ),
    );
  }
}

/// Lets [child] run under the status bar, with [VStatusBarBlur] over it.
class _UnderStatusBar extends StatelessWidget {
  const _UnderStatusBar({
    required this.child,
    this.bottomSafe = false,
    this.veil = false,
  });

  final Widget child;
  final bool bottomSafe;
  final bool veil;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        if (veil) const Positioned.fill(child: VVeil()),
        Positioned.fill(
          child: SafeArea(top: false, bottom: bottomSafe, child: child),
        ),
        const Positioned(left: 0, right: 0, top: 0, child: VStatusBarBlur()),
      ],
    );
  }
}

/// Room for the status bar at the start of a scroll view.
class _StatusBarSpace extends StatelessWidget {
  const _StatusBarSpace();

  @override
  Widget build(BuildContext context) => SliverToBoxAdapter(
    child: SizedBox(height: MediaQuery.paddingOf(context).top),
  );
}

List<Widget> _gapped(List<Widget> children) => [
  for (var i = 0; i < children.length; i++) ...[
    if (i > 0) const SizedBox(height: VSpace.cardGap),
    children[i],
  ],
];

ScrollPhysics? _physics(Future<void> Function()? onRefresh) => onRefresh == null
    ? null
    : const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics());

Widget? _refresh(Future<void> Function()? onRefresh) => onRefresh == null
    ? null
    : CupertinoSliverRefreshControl(onRefresh: onRefresh);

/// The page veil: the shared wallpaper blurred (30) under the veil tint, so
/// full pages read clearly while the wallpaper still shows through.
class VVeil extends StatelessWidget {
  const VVeil({super.key});

  @override
  Widget build(BuildContext context) {
    final entry = VEntrance.of(context);
    Widget veil(double t) => ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 30 * t, sigmaY: 30 * t),
        child: ColoredBox(
          color: VPalette.of(context).veil
              .withValues(alpha: VPalette.of(context).veil.a * t),
        ),
      ),
    );
    if (entry == null) return veil(1);
    // A blur can't be faded by fading what's above it: grow its strength
    // (and the veil's tint) with the page coming in.
    return AnimatedBuilder(
      animation: entry,
      builder: (context, _) => veil(entry.value.clamp(0.0, 1.0)),
    );
  }
}

/// How far a page has come in (0–1), for what has to animate itself, like
/// [VVeil]'s blur. The app shell sets it when a tab is switched to.
class VEntrance extends InheritedNotifier<Animation<double>> {
  const VEntrance({
    super.key,
    required Animation<double> animation,
    required super.child,
  }) : super(notifier: animation);

  static Animation<double>? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<VEntrance>()?.notifier;
}
