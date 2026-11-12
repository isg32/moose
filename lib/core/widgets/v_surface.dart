import 'package:flutter/widgets.dart';
import 'package:path_drawing/path_drawing.dart';

import '../theme/v_colors.dart';
import '../theme/v_tokens.dart';
import 'v_ink.dart';

/// How a surface is outlined.
enum VOutline { solid, dashed, none }

/// A card: 1 px outline on black, or a white inverted fill.
///
/// Hierarchy comes only from [outline], [borderWidth] and [inverted], never
/// from a grey.
class VCard extends StatelessWidget {
  const VCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(VSpace.cardPadding),
    this.radius = VRadius.card,
    this.outline = VOutline.solid,
    this.borderWidth = VSpace.hairline,
    this.inverted = false,
    this.onTap,
    this.onLongPress,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final VOutline outline;
  final double borderWidth;
  final bool inverted;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final ink = VInk.of(context);
    final fill = inverted ? ink : VColors.transparent;
    final contentInk = inverted ? VColors.onColor(ink) : ink;

    Widget body = Padding(
      padding: padding,
      child: VInkScope(ink: contentInk, child: child),
    );

    body = VOutlined(
      radius: radius,
      outline: inverted ? VOutline.none : outline,
      width: borderWidth,
      color: ink,
      fill: fill,
      child: body,
    );

    if (onTap != null || onLongPress != null) {
      body = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        onLongPress: onLongPress,
        child: body,
      );
    }
    return body;
  }
}

/// Paints a rounded outline (solid or dashed) and an optional fill behind
/// [child].
class VOutlined extends StatelessWidget {
  const VOutlined({
    super.key,
    required this.child,
    required this.radius,
    this.outline = VOutline.solid,
    this.width = VSpace.hairline,
    this.color,
    this.fill = VColors.transparent,
    this.dashPattern = const [4, 3],
  });

  final Widget child;
  final double radius;
  final VOutline outline;
  final double width;
  final Color? color;
  final Color fill;
  final List<double> dashPattern;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _OutlinePainter(
        radius: radius,
        outline: outline,
        width: width,
        color: color ?? VInk.of(context),
        fill: fill,
        dashPattern: dashPattern,
      ),
      child: child,
    );
  }
}

class _OutlinePainter extends CustomPainter {
  _OutlinePainter({
    required this.radius,
    required this.outline,
    required this.width,
    required this.color,
    required this.fill,
    required this.dashPattern,
  });

  final double radius;
  final VOutline outline;
  final double width;
  final Color color;
  final Color fill;
  final List<double> dashPattern;

  @override
  void paint(Canvas canvas, Size size) {
    final r = Radius.circular(radius.clamp(0, size.shortestSide / 2));
    if (fill.a > 0) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(Offset.zero & size, r),
        Paint()..color = fill,
      );
    }
    if (outline == VOutline.none || width <= 0) return;

    final inset = width / 2;
    final rect = Rect.fromLTWH(
      inset,
      inset,
      size.width - width,
      size.height - width,
    );
    final rrect = RRect.fromRectAndRadius(
      rect,
      Radius.circular((radius - inset).clamp(0, rect.shortestSide / 2)),
    );
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = width;

    if (outline == VOutline.solid) {
      canvas.drawRRect(rrect, paint);
    } else {
      final path = Path()..addRRect(rrect);
      canvas.drawPath(
        dashPath(path, dashArray: CircularIntervalList<double>(dashPattern)),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_OutlinePainter old) =>
      old.radius != radius ||
      old.outline != outline ||
      old.width != width ||
      old.color != color ||
      old.fill != fill;
}

/// A 1 px hairline divider in the current ink.
class VDivider extends StatelessWidget {
  const VDivider({super.key, this.vertical = false});

  final bool vertical;

  @override
  Widget build(BuildContext context) {
    final line = ColoredBox(color: VInk.of(context));
    return vertical
        ? SizedBox(width: VSpace.hairline, child: line)
        : SizedBox(
            height: VSpace.hairline,
            width: double.infinity,
            child: line,
          );
  }
}
