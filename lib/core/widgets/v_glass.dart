import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

import '../icons/v_icons.dart';
import '../theme/v_colors.dart';
import '../theme/v_palette.dart';
import '../theme/v_text.dart';
import '../theme/v_tokens.dart';
import 'v_ink.dart';
import 'v_surface.dart';

/// A panel over the wallpaper: sheets, cards, the composer, chips.
///
/// No blur: it is see-through (a semi-transparent paper) or solid, as the
/// person picks in Settings ([VPanels]). Only the tab pill is [frosted]:
/// it blurs what is behind it, with the tint over it.
class VGlass extends StatelessWidget {
  const VGlass({
    super.key,
    required this.child,
    required this.radius,
    this.tint,
    this.blur,
    this.border = true,
    this.borderRadius,
    this.frosted = false,
  });

  final Widget child;
  final double radius;

  /// One of the palette's glass tints (bar, card, sheet), which picks how
  /// see-through it is, or any other colour, used as it is.
  final Color? tint;

  /// How strong a [frosted] blur is; defaults to the layout's glass.
  final double? blur;
  final bool border;

  /// Overrides [radius] for shapes like a sheet with only top corners.
  final BorderRadius? borderRadius;

  /// A live blur behind it (the tab pill only).
  final bool frosted;

  /// The fill for [tint] in the current panel style.
  static Color fill(BuildContext context, Color? tint) {
    final palette = VPalette.of(context);
    final paper = VInk.surfaceOf(context);
    final t = tint ?? palette.glassBar;
    final sheet = t == palette.glassSheet;
    final glass = sheet || t == palette.glassBar || t == palette.glassCard;
    if (!glass) return t;
    // Sheets sit over text, which would only ghost through: always solid.
    // Cards and the rest let the wallpaper through unless solid is picked.
    if (sheet || VPanels.solid(context)) return paper;
    return paper.withValues(alpha: 0.55);
  }

  @override
  Widget build(BuildContext context) {
    final shape = borderRadius ?? BorderRadius.circular(radius);
    final box = DecoratedBox(
      decoration: BoxDecoration(
        color: frosted
            ? (tint ?? VPalette.of(context).glassBar)
            : fill(context, tint),
        borderRadius: shape,
        border: border
            ? Border.all(color: VInk.of(context), width: VSpace.hairline)
            : null,
      ),
      child: child,
    );
    // Clipped to its shape either way, so what's inside (a sheet's top
    // border) follows the round corners.
    if (!frosted) return ClipRRect(borderRadius: shape, child: box);
    // The tab pill: frosted glass, a live blur of what is behind it. It sits
    // in the shell, never inside a fade, so it draws the same every frame.
    return ClipRRect(
      borderRadius: shape,
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: blur ?? VPalette.of(context).blur,
          sigmaY: blur ?? VPalette.of(context).blur,
        ),
        child: box,
      ),
    );
  }
}

/// How panels ([VGlass]) are filled: see-through or solid. Set over the
/// app from the person's settings.
class VPanels extends InheritedWidget {
  const VPanels({super.key, required this.isSolid, required super.child});

  final bool isSolid;

  static bool solid(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<VPanels>()?.isSolid ?? false;

  @override
  bool updateShouldNotify(VPanels old) => old.isSolid != isSolid;
}

/// One tab of [VTabBar].
class VTabItem {
  const VTabItem(this.label, this.icon);

  final String label;
  final VIcon icon;
}

/// The floating glass capsule tab bar.
///
/// A single white pill slides and stretches to the active tab. The bar is
/// drawn twice: white icons on the glass, and a black copy (with the label)
/// clipped to the pill, so ink and label only ever appear inside the pill as
/// it moves.
class VTabBar extends StatefulWidget {
  const VTabBar({
    super.key,
    required this.items,
    required this.index,
    required this.onTap,
    this.position,
    this.stretch = false,
  });

  final List<VTabItem> items;

  /// Moose's pill: the full width less 12 on each side, with the tabs spread
  /// to its ends (the canvas's A10). Otherwise the bar hugs its tabs and
  /// centres, as in Cariño.
  final bool stretch;
  final int index;
  final ValueChanged<int> onTap;

  /// The page position while swiping (0 = first tab). When set, the pill
  /// follows it instead of animating on its own.
  final double? position;

  static const Duration duration = Duration(milliseconds: 420);
  static const Curve curve = Curves.easeInOutCubic;

  @override
  State<VTabBar> createState() => _VTabBarState();
}

/// Where each tab sits, how selected it is (0–1) and where the pill is.
class _TabFrame {
  const _TabFrame(this.lefts, this.widths, this.sel, this.pill);

  final List<double> lefts;
  final List<double> widths;
  final List<double> sel;
  final Rect pill;

  static _TabFrame lerp(_TabFrame a, _TabFrame b, double t) {
    double l(double x, double y) => x + (y - x) * t;
    return _TabFrame(
      [for (var i = 0; i < b.lefts.length; i++) l(a.lefts[i], b.lefts[i])],
      [for (var i = 0; i < b.widths.length; i++) l(a.widths[i], b.widths[i])],
      [for (var i = 0; i < b.sel.length; i++) l(a.sel[i], b.sel[i])],
      Rect.lerp(a.pill, b.pill, t)!,
    );
  }
}

class _VTabBarState extends State<VTabBar> with SingleTickerProviderStateMixin {
  static const double _barHeight = 62;
  static const double _pillHeight = 44;
  static const double _iconOnlyWidth = 44;
  static const double _padX = 14;
  static const double _iconGap = 6;

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: VTabBar.duration,
    value: 1,
  );
  late final Animation<double> _t = CurvedAnimation(
    parent: _controller,
    curve: VTabBar.curve,
  );

  /// The frame the current animation starts from, and the last one drawn.
  _TabFrame? _from;
  _TabFrame? _shown;

  @override
  void didUpdateWidget(VTabBar old) {
    super.didUpdateWidget(old);
    if (old.index != widget.index && widget.position == null) {
      // Start from wherever the pill is now, even mid-flight.
      _from = _shown;
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  TextStyle get _labelStyle => VText.inter(12, weight: 600);

  /// Label widths, measured once per text scale (not on every frame of a
  /// swipe).
  final Map<(int, TextScaler), double> _labelWidths = {};

  double _labelWidth(int i, TextScaler scaler) =>
      _labelWidths.putIfAbsent((i, scaler), () {
        final label = TextPainter(
          text: TextSpan(text: widget.items[i].label, style: _labelStyle),
          textDirection: TextDirection.ltr,
          textScaler: scaler,
        )..layout();
        final w = label.width.ceilToDouble();
        label.dispose();
        return w;
      });

  _TabFrame _target(int selected, double maxWidth, TextScaler scaler) {
    final widths = <double>[];
    for (var i = 0; i < widget.items.length; i++) {
      if (i != selected) {
        // The canvas gives idle tabs 22 px either side of the icon.
        widths.add(widget.stretch ? 68 : _iconOnlyWidth);
        continue;
      }
      widths.add(_padX * 2 + 18 + _iconGap + _labelWidth(i, scaler));
    }
    final used = widths.fold<double>(0, (s, w) => s + w);
    final spread = widget.stretch && widths.length > 1;
    final gap =
        ((maxWidth - used) / (spread ? widths.length - 1 : widths.length))
            .clamp(0.0, double.infinity);
    final lefts = <double>[];
    var x = spread ? 0.0 : gap / 2;
    for (final w in widths) {
      lefts.add(x);
      x += w + gap;
    }
    const top = (_barHeight - _pillHeight) / 2;
    return _TabFrame(lefts, widths, [
      for (var i = 0; i < widths.length; i++) i == selected ? 1.0 : 0.0,
    ], Rect.fromLTWH(lefts[selected], top, widths[selected], _pillHeight));
  }

  /// Room between tabs in the compact bar.
  static const double _gap = 12;

  /// The bar's width: just enough for its tabs with [_gap] between them,
  /// for whichever tab has the longest label, so it never resizes as you
  /// switch tabs. (Veronica's five tabs filled the screen; three would sit
  /// far apart, so the bar hugs them and centres instead.)
  double _naturalWidth(TextScaler scaler) {
    var widest = 0.0;
    for (var i = 0; i < widget.items.length; i++) {
      final f = _target(i, 0, scaler);
      final used = f.widths.fold<double>(0, (s, w) => s + w);
      if (used > widest) widest = used;
    }
    return widest + _gap * widget.items.length + 12;
  }

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: widget.stretch ? 12 : 0),
      child: Center(
        child: SizedBox(
          width: widget.stretch ? double.infinity : _naturalWidth(scaler),
          child: VGlass(
            radius: _barHeight / 2,
            frosted: true,
            child: SizedBox(
              height: _barHeight,
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: widget.stretch ? 7 : 6,
                ),
                child: LayoutBuilder(
                  builder: (context, box) {
                    final to = _target(widget.index, box.maxWidth, scaler);
                    final position = widget.position;
                    if (position != null) {
                      // Track a swipe 1:1: the pill sits between the two
                      // tabs the pages sit between.
                      final p = position.clamp(0.0, widget.items.length - 1.0);
                      final a = p.floor();
                      final b = p.ceil();
                      final frame = _TabFrame.lerp(
                        _target(a, box.maxWidth, scaler),
                        _target(b, box.maxWidth, scaler),
                        p - a,
                      );
                      _shown = frame;
                      return _frame(frame, to);
                    }
                    return AnimatedBuilder(
                      animation: _t,
                      builder: (context, _) {
                        final frame = _from == null
                            ? to
                            : _TabFrame.lerp(_from!, to, _t.value);
                        _shown = frame;
                        return _frame(frame, to);
                      },
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _frame(_TabFrame f, _TabFrame to) {
    const top = (_barHeight - _pillHeight) / 2;
    final ink = VInk.of(context);
    final paper = VInk.surfaceOf(context);
    final n = widget.items.length;
    final lefts = f.lefts;
    final widths = f.widths;
    final sel = f.sel;
    final pill = f.pill;

    Widget layer({required Color ink, required bool labels}) {
      return Stack(
        children: [
          for (var i = 0; i < n; i++)
            Positioned(
              left: lefts[i],
              top: top,
              width: widths[i],
              height: _pillHeight,
              child: _TabContent(
                item: widget.items[i],
                selected: sel[i],
                ink: ink,
                showLabel: labels,
                labelStyle: _labelStyle,
              ),
            ),
        ],
      );
    }

    return Stack(
      children: [
        Positioned.fromRect(
          rect: pill,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: ink,
              borderRadius: const BorderRadius.all(
                Radius.circular(_pillHeight / 2),
              ),
            ),
          ),
        ),
        Positioned.fill(
          child: ExcludeSemantics(
            child: ClipPath(
              clipper: _OutsideClipper(pill),
              child: layer(ink: ink, labels: false),
            ),
          ),
        ),
        Positioned.fill(
          child: ExcludeSemantics(
            child: ClipRRect(
              clipper: _PillClipper(pill),
              child: layer(ink: paper, labels: true),
            ),
          ),
        ),
        // Tap targets on top, one per tab at its final place.
        for (var i = 0; i < n; i++)
          Positioned(
            left: to.lefts[i],
            top: 0,
            width: to.widths[i],
            height: _barHeight,
            child: Semantics(
              selected: i == widget.index,
              button: true,
              label: widget.items[i].label,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  if (i != widget.index) HapticFeedback.selectionClick();
                  widget.onTap(i);
                },
              ),
            ),
          ),
      ],
    );
  }
}

/// One tab's icon (and, inside the pill, its label). [selected] slides the
/// icon from the centre to the start as the tab becomes active.
class _TabContent extends StatelessWidget {
  const _TabContent({
    required this.item,
    required this.selected,
    required this.ink,
    required this.showLabel,
    required this.labelStyle,
  });

  final VTabItem item;
  final double selected;
  final Color ink;
  final bool showLabel;
  final TextStyle labelStyle;

  @override
  Widget build(BuildContext context) {
    final s = selected;
    return ClipRect(
      child: OverflowBox(
        minWidth: 0,
        maxWidth: double.infinity,
        alignment: Alignment.lerp(Alignment.center, Alignment.centerLeft, s)!,
        child: Padding(
          padding: EdgeInsets.only(left: _VTabBarState._padX * s),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              VIconView(
                item.icon,
                size: 20 - 2 * s,
                strokeWidth: 1.5 + 0.5 * s,
                color: ink,
              ),
              SizedBox(width: _VTabBarState._iconGap * s),
              Align(
                alignment: Alignment.centerLeft,
                widthFactor: s,
                child: showLabel && s > 0
                    ? Text(
                        item.label,
                        maxLines: 1,
                        softWrap: false,
                        style: labelStyle.copyWith(color: ink),
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PillClipper extends CustomClipper<RRect> {
  _PillClipper(this.pill);

  final Rect pill;

  @override
  RRect getClip(Size size) =>
      RRect.fromRectAndRadius(pill, Radius.circular(pill.height / 2));

  @override
  bool shouldReclip(_PillClipper old) => old.pill != pill;
}

/// Everything except the pill.
class _OutsideClipper extends CustomClipper<Path> {
  _OutsideClipper(this.pill);

  final Rect pill;

  @override
  Path getClip(Size size) => Path()
    ..fillType = PathFillType.evenOdd
    ..addRect(Offset.zero & size)
    ..addRRect(RRect.fromRectAndRadius(pill, Radius.circular(pill.height / 2)));

  @override
  bool shouldReclip(_OutsideClipper old) => old.pill != pill;
}

/// Shows a glass bottom sheet with a handle and an eyebrow title.
Future<T?> showVSheet<T>(
  BuildContext context, {
  required String title,
  required WidgetBuilder builder,
}) {
  // Away with the keyboard, and the focus, so closing the sheet doesn't
  // bring the keyboard back.
  FocusManager.instance.primaryFocus?.unfocus();
  return showCupertinoModalPopup<T>(
    context: context,
    barrierColor: VPalette.of(context).popupScrim,
    builder: (context) => VSheet(title: title, child: builder(context)),
  );
}

/// The glass bottom sheet used by [showVSheet].
class VSheet extends StatelessWidget {
  const VSheet({super.key, required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    final screen = MediaQuery.sizeOf(context).height;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: ConstrainedBox(
        // At most 85 % of the screen above the keyboard; the rest scrolls.
        constraints: BoxConstraints(maxHeight: (screen - bottom) * 0.85),
        child: Builder(
          builder: (context) => VGlass(
            radius: VRadius.sheet,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(VRadius.sheet),
            ),
            tint: VPalette.of(context).glassSheet,
            blur: 14,
            border: false,
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: VInk.of(context))),
              ),
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: Container(
                          width: 36,
                          height: 4,
                          decoration: BoxDecoration(
                            color: VInk.of(context),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(title.toUpperCase(), style: VText.eyebrow),
                      const SizedBox(height: 14),
                      // Long lists (apps, sounds) scroll inside the sheet.
                      Flexible(child: SingleChildScrollView(child: child)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A text field in an outlined (or dashed) box, for sheets and editors.
class VTextField extends StatelessWidget {
  const VTextField({
    super.key,
    required this.controller,
    this.placeholder,
    this.dashed = false,
    this.autofocus = false,
    this.maxLines = 1,
    this.style,
    this.onSubmitted,
    this.onChanged,
  });

  final TextEditingController controller;
  final String? placeholder;
  final bool dashed;
  final bool autofocus;
  final int maxLines;
  final TextStyle? style;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    final ink = VInk.of(context);
    return VOutlined(
      radius: 16,
      outline: dashed ? VOutline.dashed : VOutline.solid,
      child: CupertinoTextField(
        controller: controller,
        autofocus: autofocus,
        maxLines: maxLines,
        minLines: 1,
        onSubmitted: onSubmitted,
        onChanged: onChanged,
        cursorColor: ink,
        padding: const EdgeInsets.all(14),
        placeholder: placeholder,
        placeholderStyle: VText.inter(14, weight: 300).copyWith(color: ink),
        style: (style ?? VText.inter(17)).copyWith(color: ink),
        decoration: const BoxDecoration(color: VColors.transparent),
      ),
    );
  }
}

/// Which screen edge a [VEdgeBlur] sits on.
enum VEdge { top, bottom }

/// Progressive blur along a screen edge, as on iOS: strongest at the edge
/// and easing smoothly to nothing [fade] away from it, with no seam, so
/// content can scroll underneath while what sits on the edge stays readable.
///
/// A fragment shader (`shaders/progressive_blur.frag`) varies the blur
/// radius with distance from the edge. Where shader filters are not
/// supported, a single light blur covers just [solid]. A soft paper-coloured
/// gradient sits on top.
class VEdgeBlur extends StatefulWidget {
  const VEdgeBlur({
    super.key,
    required this.edge,
    required this.solid,
    this.fade = VEdgeBlur.standardFade,
    this.maxRadius = 18,
  });

  final VEdge edge;

  /// The part right at the edge (the status bar, or the tab bar and gesture
  /// area) where the blur is at or near its strongest.
  final double solid;

  /// How far beyond [solid] the blur eases out.
  final double fade;

  /// Blur radius at the edge, in logical pixels.
  final double maxRadius;

  /// The one fade every edge uses, top and bottom, on every tab, so the
  /// blur reads the same wherever you are.
  static const standardFade = 40.0;

  static Future<FragmentProgram>? _program;

  @override
  State<VEdgeBlur> createState() => _VEdgeBlurState();
}

class _VEdgeBlurState extends State<VEdgeBlur> {
  FragmentShader? _shader;

  @override
  void initState() {
    super.initState();
    if (ImageFilter.isShaderFilterSupported) {
      VEdgeBlur._program ??= FragmentProgram.fromAsset(
        'shaders/progressive_blur.frag',
      );
      VEdgeBlur._program!.then((p) {
        if (mounted) setState(() => _shader = p.fragmentShader());
      }, onError: (Object _) {});
    }
  }

  @override
  void dispose() {
    _shader?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.solid <= 0) return const SizedBox.shrink();
    final top = widget.edge == VEdge.top;
    final height = widget.solid + widget.fade;
    final ratio = MediaQuery.devicePixelRatioOf(context);
    final paper = VInk.surfaceOf(context);

    final shader = _shader;
    final ImageFilter filter;
    if (shader != null) {
      // Uniforms 0–1 (the texture size) are set by the engine.
      shader
        ..setFloat(2, height * ratio)
        ..setFloat(3, widget.maxRadius * ratio)
        ..setFloat(4, top ? 0 : 1);
      filter = ImageFilter.shader(shader);
    } else {
      filter = ImageFilter.blur(sigmaX: 4, sigmaY: 4);
    }
    // Without the shader the fallback blur covers only the solid part.
    final inset = shader == null ? widget.fade : 0.0;

    return IgnorePointer(
      child: SizedBox(
        height: height,
        child: Stack(
          children: [
            Positioned.fill(
              top: top ? 0 : inset,
              bottom: top ? inset : 0,
              child: ClipRect(
                child: BackdropFilter(
                  filter: filter,
                  child: const SizedBox.expand(),
                ),
              ),
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: top ? Alignment.topCenter : Alignment.bottomCenter,
                    end: top ? Alignment.bottomCenter : Alignment.topCenter,
                    colors: [
                      paper.withValues(alpha: 0.55),
                      paper.withValues(alpha: 0.25),
                      paper.withValues(alpha: 0),
                    ],
                    stops: [0, widget.solid / height, 1],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// [VEdgeBlur] behind the status bar. Page titles start 16 below the bar,
/// where the blur is already close to nothing.
///
/// Inside the app shell ([VShellEdges]) the shell draws it once, over every
/// tab, so pages there draw none: one blur that never comes and goes.
class VStatusBarBlur extends StatelessWidget {
  const VStatusBarBlur({super.key, this.always = false});

  /// Draw it even under [VShellEdges] (the shell's own).
  final bool always;

  @override
  Widget build(BuildContext context) {
    if (!always && VShellEdges.within(context)) return const SizedBox.shrink();
    // Fades out just under the bar, clear of headers and titles below it
    // (Chat's header sits 8 below the bar), so no text there is blurred.
    return VEdgeBlur(
      edge: VEdge.top,
      solid: MediaQuery.paddingOf(context).top,
      fade: 8,
    );
  }
}

/// Marks what the app shell draws its edges over (see [VStatusBarBlur]).
class VShellEdges extends InheritedWidget {
  const VShellEdges({super.key, required super.child});

  static bool within(BuildContext context) =>
      context.getInheritedWidgetOfExactType<VShellEdges>() != null;

  @override
  bool updateShouldNotify(VShellEdges old) => false;
}
