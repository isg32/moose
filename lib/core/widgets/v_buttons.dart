import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../icons/v_icons.dart';
import '../theme/v_colors.dart';
import '../theme/v_text.dart';
import '../theme/v_tokens.dart';
import 'v_ink.dart';
import 'v_surface.dart';

/// Fill style shared by buttons, pills and chips.
enum VFill {
  /// Inverted: ink-coloured fill, surface-coloured label.
  filled,

  /// 1 px outline.
  outline,

  /// 1 px dashed outline, for optional, skip and "add" actions.
  dashed,

  /// No outline (text only, or a selected segment's neighbours).
  plain,
}

/// Wraps [child] in a tap target that gives a light haptic and settles to
/// a lower opacity while pressed. Nothing moves or scales.
class VTappable extends StatefulWidget {
  const VTappable({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.haptic = true,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool haptic;

  @override
  State<VTappable> createState() => _VTappableState();
}

class _VTappableState extends State<VTappable> {
  bool _down = false;

  bool get _enabled => widget.onTap != null || widget.onLongPress != null;

  void _set(bool down) {
    if (_down != down && mounted) setState(() => _down = down);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: _enabled ? (_) => _set(true) : null,
      onTapUp: _enabled ? (_) => _set(false) : null,
      onTapCancel: () => _set(false),
      onTap: widget.onTap == null
          ? null
          : () {
              if (widget.haptic) HapticFeedback.lightImpact();
              widget.onTap!();
            },
      onLongPress: widget.onLongPress == null
          ? null
          : () {
              HapticFeedback.mediumImpact();
              widget.onLongPress!();
            },
      child: AnimatedOpacity(
        opacity: _down ? 0.6 : 1,
        duration: const Duration(milliseconds: 120),
        child: widget.child,
      ),
    );
  }
}

/// A full-width pill button.
///
/// `primary` is the white pill (one per screen), `secondary` an outline,
/// `ghost` a dashed outline for optional or skip actions.
class VButton extends StatelessWidget {
  const VButton.primary(
    this.label, {
    super.key,
    this.onPressed,
    this.enabled = true,
  }) : fill = VFill.filled;

  const VButton.secondary(
    this.label, {
    super.key,
    this.onPressed,
    this.enabled = true,
  }) : fill = VFill.outline;

  const VButton.ghost(
    this.label, {
    super.key,
    this.onPressed,
    this.enabled = true,
  }) : fill = VFill.dashed;

  final String label;
  final VoidCallback? onPressed;
  final bool enabled;
  final VFill fill;

  @override
  Widget build(BuildContext context) {
    final ink = VInk.of(context);
    final isFilled = fill == VFill.filled;
    final button = VOutlined(
      radius: VRadius.pill,
      outline: switch (fill) {
        VFill.outline => VOutline.solid,
        VFill.dashed => VOutline.dashed,
        _ => VOutline.none,
      },
      fill: isFilled ? ink : VColors.transparent,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: (isFilled ? VText.button : VText.buttonSecondary).copyWith(
              color: isFilled ? VColors.onColor(ink) : ink,
            ),
          ),
        ),
      ),
    );

    return Opacity(
      opacity: enabled ? 1 : VColors.disabledOpacity,
      child: VTappable(
        onTap: enabled ? onPressed : null,
        child: SizedBox(width: double.infinity, child: button),
      ),
    );
  }
}

/// A small pill: chips, badges and inline actions ("Grant", "Copy", "Start").
class VPill extends StatelessWidget {
  const VPill(
    this.label, {
    super.key,
    this.fill = VFill.outline,
    this.onTap,
    this.style,
    this.padding = const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    this.leading,
  });

  /// Inverted status badge, e.g. `75/60`, `Taken`, `7h 30m`.
  const VPill.badge(this.label, {super.key, this.onTap, this.leading})
    : fill = VFill.filled,
      style = null,
      padding = const EdgeInsets.symmetric(horizontal: 8, vertical: 2);

  final String label;
  final VFill fill;
  final VoidCallback? onTap;
  final TextStyle? style;
  final EdgeInsetsGeometry padding;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final ink = VInk.of(context);
    final filled = fill == VFill.filled;
    final textStyle = (style ?? VText.inter(12, weight: filled ? 600 : 500))
        .copyWith(color: filled ? VColors.onColor(ink) : ink);

    Widget pill = VOutlined(
      radius: VRadius.pill,
      outline: switch (fill) {
        VFill.outline => VOutline.solid,
        VFill.dashed => VOutline.dashed,
        _ => VOutline.none,
      },
      fill: filled ? ink : VColors.transparent,
      child: Padding(
        padding: padding,
        child: VInkScope(
          ink: filled ? VColors.onColor(ink) : ink,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (leading != null) ...[leading!, const SizedBox(width: 6)],
              Text(label, style: textStyle),
            ],
          ),
        ),
      ),
    );
    if (onTap != null) pill = VTappable(onTap: onTap, child: pill);
    return pill;
  }
}

/// A round icon button: the gear on Today, the `+` on Tasks.
class VCircleButton extends StatelessWidget {
  const VCircleButton({
    super.key,
    required this.icon,
    this.onTap,
    this.filled = false,
    this.size = 40,
    this.dashed = false,
  });

  final VIcon icon;
  final VoidCallback? onTap;
  final bool filled;
  final bool dashed;
  final double size;

  @override
  Widget build(BuildContext context) {
    final ink = VInk.of(context);
    return VTappable(
      onTap: onTap,
      child: SizedBox.square(
        dimension: size,
        child: VOutlined(
          radius: size / 2,
          outline: filled
              ? VOutline.none
              : (dashed ? VOutline.dashed : VOutline.solid),
          fill: filled ? ink : VColors.transparent,
          child: Center(
            child: VIconView(
              icon,
              size: size / 2,
              strokeWidth: filled ? 2 : 1.6,
              color: filled ? VColors.onColor(ink) : ink,
            ),
          ),
        ),
      ),
    );
  }
}

/// Underlined text link, e.g. "Skip for now" or "Weekly summary".
class VLink extends StatelessWidget {
  const VLink(this.label, {super.key, this.onTap, this.style});

  final String label;
  final VoidCallback? onTap;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return VTappable(
      onTap: onTap,
      child: Text(
        label,
        style: (style ?? VText.inter(14)).copyWith(
          decoration: TextDecoration.underline,
          decorationColor: VInk.of(context),
        ),
      ),
    );
  }
}

/// Plain text action in a header, e.g. "Save".
class VTextAction extends StatelessWidget {
  const VTextAction(this.label, {super.key, this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return VTappable(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Text(label, style: VText.inter(14, weight: 600)),
      ),
    );
  }
}
