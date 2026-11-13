import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../theme/v_colors.dart';
import '../theme/v_text.dart';
import '../theme/v_tokens.dart';
import 'v_ink.dart';
import 'v_surface.dart';

/// Progress ring: a dotted 1 px track with a round-capped arc from 12 o'clock.
class VRing extends StatelessWidget {
  const VRing({
    super.key,
    required this.value,
    required this.size,
    this.strokeWidth = 7,
    this.child,
    this.color,
  });

  /// 0 … 1. Values above 1 draw a full ring.
  final double value;
  final double size;
  final double strokeWidth;
  final Widget? child;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: _RingPainter(
          value: value.clamp(0, 1).toDouble(),
          color: color ?? VInk.of(context),
          strokeWidth: strokeWidth,
        ),
        child: child == null ? null : Center(child: child),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.value,
    required this.color,
    required this.strokeWidth,
  });

  final double value;
  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    // The design draws the ring at r = 44/100 of the box.
    final radius = size.width * 0.44;

    // Dotted track: a 1 px dot every 4 px of circumference.
    final dot = Paint()..color = color;
    final count = (2 * math.pi * radius / 4).floor();
    for (var i = 0; i < count; i++) {
      final a = 2 * math.pi * i / count;
      canvas.drawCircle(
        center + Offset(math.cos(a) * radius, math.sin(a) * radius),
        0.6,
        dot,
      );
    }

    if (value <= 0) return;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      2 * math.pi * value,
      false,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.value != value ||
      old.color != color ||
      old.strokeWidth != strokeWidth;
}

/// A 6 px progress bar: outlined track, solid fill. Full means solid.
class VBar extends StatelessWidget {
  const VBar({super.key, required this.value, this.height = 6});

  final double value;
  final double height;

  @override
  Widget build(BuildContext context) {
    final ink = VInk.of(context);
    final v = value.clamp(0, 1).toDouble();
    if (v >= 1) {
      return Container(
        height: height,
        decoration: BoxDecoration(
          color: ink,
          borderRadius: BorderRadius.circular(height / 2),
        ),
      );
    }
    return SizedBox(
      height: height,
      child: VOutlined(
        radius: height / 2,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(height / 2),
          child: FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: v,
            child: ColoredBox(color: ink),
          ),
        ),
      ),
    );
  }
}

/// Water glasses as dots: filled for drunk, outlined for remaining.
class VDots extends StatelessWidget {
  const VDots({
    super.key,
    required this.filled,
    required this.total,
    this.size = 16,
    this.gap = 8,
    this.columns,
    this.square = false,
  });

  final int filled;
  final int total;
  final double size;
  final double gap;

  /// Wrap into a grid with this many columns (the water widget uses 4).
  final int? columns;

  /// Squares instead of circles (nudges in the weekly summary).
  final bool square;

  @override
  Widget build(BuildContext context) {
    final ink = VInk.of(context);
    Widget dot(int i) => SizedBox.square(
      dimension: size,
      child: VOutlined(
        radius: square ? 0 : size / 2,
        outline: i < filled ? VOutline.none : VOutline.solid,
        fill: i < filled ? ink : VColors.transparent,
        child: const SizedBox.expand(),
      ),
    );

    final dots = [for (var i = 0; i < total; i++) dot(i)];
    if (columns == null) {
      return Wrap(spacing: gap, runSpacing: gap, children: dots);
    }
    return SizedBox(
      width: columns! * size + (columns! - 1) * gap,
      child: Wrap(spacing: gap, runSpacing: gap, children: dots),
    );
  }
}

/// Seven white bars with day initials and an optional dashed limit line.
class VBarChart extends StatelessWidget {
  const VBarChart({
    super.key,
    required this.values,
    required this.labels,
    this.limit,
    this.max,
    this.highlight,
    this.height = 128,
  });

  final List<double> values;
  final List<String> labels;

  /// Draws a dashed line at this value.
  final double? limit;
  final double? max;

  /// Index whose label is bold (today).
  final int? highlight;
  final double height;

  @override
  Widget build(BuildContext context) {
    final ink = VInk.of(context);
    const labelSpace = 18.0;
    final barArea = height - labelSpace;
    final top = max ?? [...values, ?limit].fold<double>(0, math.max) * 1.08;

    return SizedBox(
      height: height,
      child: Stack(
        children: [
          if (limit != null && top > 0)
            Positioned(
              left: 0,
              right: 0,
              bottom: labelSpace + barArea * (limit! / top),
              child: _DashedLine(color: ink),
            ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var i = 0; i < values.length; i++)
                SizedBox(
                  width: 28,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Container(
                        width: 18,
                        height: top == 0 ? 0 : barArea * (values[i] / top),
                        decoration: BoxDecoration(
                          color: ink,
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(3),
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        labels[i],
                        style: VText.inter(
                          10,
                          weight: i == highlight ? 600 : 400,
                          height: 1.2,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Planned (hatched outline) beside actual (solid) bars, per day.
class VPairChart extends StatelessWidget {
  const VPairChart({
    super.key,
    required this.planned,
    required this.actual,
    required this.labels,
    this.max,
    this.barHeight = 84,
  });

  final List<double> planned;
  final List<double> actual;
  final List<String> labels;
  final double? max;
  final double barHeight;

  @override
  Widget build(BuildContext context) {
    final ink = VInk.of(context);
    final top = max ?? [...planned, ...actual].fold<double>(0, math.max);
    double h(double v) => top == 0 ? 0 : barHeight * (v / top);

    return SizedBox(
      height: barHeight + 18,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < labels.length; i++)
            Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    VHatched(width: 9, height: h(planned[i])),
                    const SizedBox(width: 3),
                    Container(width: 9, height: h(actual[i]), color: ink),
                  ],
                ),
                const SizedBox(height: 6),
                Text(labels[i], style: VText.inter(10)),
              ],
            ),
        ],
      ),
    );
  }
}

/// Legend for [VPairChart]: "▨ Planned  ■ Actual".
class VPairLegend extends StatelessWidget {
  const VPairLegend({super.key});

  @override
  Widget build(BuildContext context) {
    final ink = VInk.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const VHatched(width: 8, height: 8),
        const SizedBox(width: 4),
        Text('Planned', style: VText.inter(11)),
        const SizedBox(width: 10),
        Container(width: 10, height: 10, color: ink),
        const SizedBox(width: 4),
        Text('Actual', style: VText.inter(11)),
      ],
    );
  }
}

/// A rectangle with a 1 px outline and 45° hatching — the second data series.
class VHatched extends StatelessWidget {
  const VHatched({super.key, required this.width, required this.height});

  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: CustomPaint(painter: _HatchPainter(VInk.of(context))),
    );
  }
}

class _HatchPainter extends CustomPainter {
  _HatchPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rect = Offset.zero & size;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    canvas.save();
    canvas.clipRect(rect);
    for (var x = -size.height; x < size.width; x += 4) {
      canvas.drawLine(
        Offset(x, size.height),
        Offset(x + size.height, 0),
        paint,
      );
    }
    canvas.restore();
    canvas.drawRect(rect.deflate(0.5), paint..style = PaintingStyle.stroke);
  }

  @override
  bool shouldRepaint(_HatchPainter old) => old.color != color;
}

class _DashedLine extends StatelessWidget {
  const _DashedLine({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: VSpace.hairline,
      child: CustomPaint(painter: _DashPainter(color)),
    );
  }
}

class _DashPainter extends CustomPainter {
  _DashPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    for (double x = 0; x < size.width; x += 7) {
      canvas.drawLine(
        Offset(x, 0),
        Offset(math.min(x + 4, size.width), 0),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_DashPainter old) => old.color != color;
}

/// A horizontal dashed rule, e.g. between bedtime and wake.
class VDashedRule extends StatelessWidget {
  const VDashedRule({super.key});

  @override
  Widget build(BuildContext context) => _DashedLine(color: VInk.of(context));
}

/// Loading: a quarter arc going round on a dotted track, in the ink.
class VSpinner extends StatefulWidget {
  const VSpinner({super.key, this.size = 20, this.strokeWidth = 2});

  final double size;
  final double strokeWidth;

  @override
  State<VSpinner> createState() => _VSpinnerState();
}

class _VSpinnerState extends State<VSpinner>
    with SingleTickerProviderStateMixin {
  late final _turn = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat();

  @override
  void dispose() {
    _turn.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Loading',
    child: RotationTransition(
      turns: _turn,
      child: CustomPaint(
        size: Size.square(widget.size),
        painter: _ArcPainter(VInk.of(context), widget.strokeWidth),
      ),
    ),
  );
}

class _ArcPainter extends CustomPainter {
  _ArcPainter(this.ink, this.stroke);
  final Color ink;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(stroke / 2);
    canvas.drawArc(
      rect,
      0,
      2 * math.pi,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = ink.withValues(alpha: 0.25),
    );
    canvas.drawArc(
      rect,
      -math.pi / 2,
      math.pi * 0.6,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..color = ink,
    );
  }

  @override
  bool shouldRepaint(_ArcPainter old) => old.ink != ink || old.stroke != stroke;
}
