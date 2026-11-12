import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../core/theme/v_colors.dart';
import '../../data/models.dart';

/// A smooth path through [points]: quadratic curves through the midpoints
/// (the board's smoothing; Phase 4 adds the 1€ filter on live input).
Path smoothPath(List<Offset> points) {
  final path = Path();
  if (points.isEmpty) return path;
  path.moveTo(points.first.dx, points.first.dy);
  if (points.length < 3) {
    for (final p in points.skip(1)) {
      path.lineTo(p.dx, p.dy);
    }
    return path;
  }
  for (var i = 1; i < points.length - 1; i++) {
    final mid = (points[i] + points[i + 1]) / 2;
    path.quadraticBezierTo(points[i].dx, points[i].dy, mid.dx, mid.dy);
  }
  path.lineTo(points.last.dx, points.last.dy);
  return path;
}

/// Paints [strokes] the way each tool looks (C31), scaled from [space] to
/// the canvas. [outline] draws a white rim under every stroke, as on
/// doodle stickers.
class StrokesPainter extends CustomPainter {
  StrokesPainter(
    this.strokes, {
    required this.space,
    this.outline = 0,
    this.repaintKey = 0,
  });

  final List<Stroke> strokes;

  /// The size the strokes were drawn in (390 × 700 for boards, 1 × 1 for
  /// stickers).
  final Size space;

  /// White rim width, in canvas pixels; 0 for none.
  final double outline;

  /// Bumped by the board as a stroke grows.
  final int repaintKey;

  @override
  void paint(Canvas canvas, Size size) {
    final s = math.min(size.width / space.width, size.height / space.height);
    canvas.save();
    canvas.translate(
      (size.width - space.width * s) / 2,
      (size.height - space.height * s) / 2,
    );
    canvas.scale(s);
    if (outline > 0) {
      for (final st in strokes) {
        if (st.tool == PenTool.eraser) continue;
        canvas.drawPath(
          smoothPath(st.points),
          Paint()
            ..color = VColors.white
            ..style = PaintingStyle.stroke
            ..strokeWidth = st.size + outline * 2 / s
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round,
        );
      }
    }
    // Erasing clears what is under it, so the strokes share one layer.
    canvas.saveLayer(Offset.zero & space, Paint());
    for (final st in strokes) {
      paintStroke(canvas, st);
    }
    canvas.restore();
    canvas.restore();
  }

  @override
  bool shouldRepaint(StrokesPainter old) =>
      old.strokes != strokes ||
      old.repaintKey != repaintKey ||
      old.space != space ||
      old.outline != outline;
}

/// Draws one stroke in its tool's style.
void paintStroke(Canvas canvas, Stroke st) {
  if (st.points.isEmpty) return;
  final color = VPenColors.of(st.argb).withValues(alpha: st.opacity);
  final path = smoothPath(st.points);
  Paint base({double? width, StrokeCap cap = StrokeCap.round}) => Paint()
    ..color = color
    ..style = PaintingStyle.stroke
    ..strokeWidth = width ?? st.size
    ..strokeCap = cap
    ..strokeJoin = StrokeJoin.round
    ..isAntiAlias = true;

  if (st.points.length == 1) {
    canvas.drawCircle(
      st.points.first,
      st.size / 2,
      Paint()..color = st.tool == PenTool.eraser ? VColors.black : color,
    );
    return;
  }

  switch (st.tool) {
    case PenTool.eraser:
      canvas.drawPath(
        path,
        base(width: st.size * 3)..blendMode = BlendMode.clear,
      );
    case PenTool.highlighter:
      canvas.drawPath(
        path,
        base(cap: StrokeCap.butt)
          ..color = color.withValues(alpha: math.min(st.opacity, 0.45)),
      );
    case PenTool.marker:
      canvas.drawPath(path, base(cap: StrokeCap.square));
    case PenTool.pencil:
      canvas.drawPath(
        path,
        base(width: st.size * 0.8)
          ..color = color.withValues(alpha: st.opacity * 0.85),
      );
    case PenTool.neon:
      canvas.drawPath(
        path,
        base(width: st.size * 2.4)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6)
          ..color = color.withValues(alpha: 0.7),
      );
      canvas.drawPath(path, base(width: st.size * 0.6)..color = VColors.white);
    case PenTool.calligraphy:
      // A flat nib at 45°: the stroke is swept along the nib's edge.
      const angle = -math.pi / 4;
      final nib = Offset(math.cos(angle), math.sin(angle)) * (st.size / 2);
      final p = Paint()
        ..color = color
        ..style = PaintingStyle.fill;
      for (var i = 0; i < st.points.length - 1; i++) {
        final a = st.points[i], b = st.points[i + 1];
        canvas.drawPath(
          Path()
            ..moveTo((a - nib).dx, (a - nib).dy)
            ..lineTo((a + nib).dx, (a + nib).dy)
            ..lineTo((b + nib).dx, (b + nib).dy)
            ..lineTo((b - nib).dx, (b - nib).dy)
            ..close(),
          p,
        );
      }
    case PenTool.brush:
      canvas.drawPath(path, base());
      canvas.drawPath(
        path,
        base(width: st.size * 1.25)..color = color.withValues(alpha: 0.18),
      );
    case PenTool.fineLiner:
    case PenTool.lasso:
      canvas.drawPath(path, base());
  }
}

/// Doodle strokes, fitted to the box (board thumbnails, stickers).
class StrokesView extends StatelessWidget {
  const StrokesView(
    this.strokes, {
    super.key,
    this.space = const Size(390, 700),
    this.outline = 0,
  });

  final List<Stroke> strokes;
  final Size space;
  final double outline;

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: StrokesPainter(strokes, space: space, outline: outline),
    child: const SizedBox.expand(),
  );
}
