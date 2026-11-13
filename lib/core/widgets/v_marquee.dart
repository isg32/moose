import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../theme/v_colors.dart';

/// One line of text. When it doesn't fit it ends in "…", and while
/// [running] it scrolls slowly across instead, pausing at the start, so the
/// whole of it can be read (a song title while it plays).
class VMarquee extends StatefulWidget {
  const VMarquee(this.text, {super.key, this.style, this.running = false});

  final String text;
  final TextStyle? style;
  final bool running;

  /// Speed, in logical pixels a second.
  static const speed = 30.0;

  /// Space between the end of the text and its next pass.
  static const gap = 40.0;

  /// Seconds it rests at the start of each pass.
  static const rest = 1.2;

  @override
  State<VMarquee> createState() => _VMarqueeState();
}

class _VMarqueeState extends State<VMarquee>
    with SingleTickerProviderStateMixin {
  /// A clock: its value × 1000 is seconds since it started.
  late final _clock = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 1000),
  );

  @override
  void initState() {
    super.initState();
    if (widget.running) _clock.repeat();
  }

  @override
  void didUpdateWidget(VMarquee old) {
    super.didUpdateWidget(old);
    if (widget.running && !_clock.isAnimating) {
      _clock.repeat();
    } else if (!widget.running && _clock.isAnimating) {
      _clock
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.running) {
      return Text(
        widget.text,
        style: widget.style,
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.ellipsis,
      );
    }
    final line = Text(widget.text, style: widget.style, softWrap: false);
    return _Marquee(
      clock: _clock,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          line,
          const SizedBox(width: VMarquee.gap),
          line,
        ],
      ),
    );
  }
}

/// Lays out two copies of the line side by side ([child]), shows one
/// line's width of it, and slides it along with [clock] when it overflows.
class _Marquee extends SingleChildRenderObjectWidget {
  const _Marquee({required this.clock, required super.child});

  final Animation<double> clock;

  @override
  _RenderMarquee createRenderObject(BuildContext context) =>
      _RenderMarquee(clock);

  @override
  void updateRenderObject(BuildContext context, _RenderMarquee r) =>
      r.clock = clock;
}

class _RenderMarquee extends RenderProxyBox {
  _RenderMarquee(this._clock);

  Animation<double> _clock;
  set clock(Animation<double> c) {
    if (c == _clock) return;
    if (attached) _clock.removeListener(markNeedsPaint);
    _clock = c;
    if (attached) _clock.addListener(markNeedsPaint);
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _clock.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    _clock.removeListener(markNeedsPaint);
    super.detach();
  }

  /// One copy's width, from the pair's.
  double _line(double pair) => math.max(0, (pair - VMarquee.gap) / 2);

  @override
  double computeMinIntrinsicWidth(double height) => 0;

  @override
  double computeMaxIntrinsicWidth(double height) =>
      _line(child?.getMaxIntrinsicWidth(height) ?? 0);

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final c = child;
    if (c == null) return constraints.smallest;
    final s = c.getDryLayout(const BoxConstraints());
    return constraints.constrain(Size(_line(s.width), s.height));
  }

  @override
  void performLayout() {
    final c = child;
    if (c == null) {
      size = constraints.smallest;
      return;
    }
    c.layout(const BoxConstraints(), parentUsesSize: true);
    size = constraints.constrain(Size(_line(c.size.width), c.size.height));
  }

  @override
  bool get alwaysNeedsCompositing => false;

  @override
  void paint(PaintingContext context, Offset offset) {
    final c = child;
    if (c == null) return;
    final line = _line(c.size.width);
    var shift = 0.0;
    if (line > size.width + 0.5) {
      final run = line + VMarquee.gap;
      final cycle = VMarquee.rest + run / VMarquee.speed;
      final secs = _clock.value * 1000 % cycle;
      shift = math.max(0, secs - VMarquee.rest) * VMarquee.speed;
    }
    if (line <= size.width + 0.5) {
      context.paintChild(c, offset);
      return;
    }
    // Scrolling: the text fades out at both ends instead of being cut.
    context.pushClipRect(needsCompositing, offset, Offset.zero & size, (
      context,
      offset,
    ) {
      final bounds = offset & size;
      final canvas = context.canvas;
      canvas.saveLayer(bounds, Paint());
      context.paintChild(c, offset - Offset(shift, 0));
      final edge = math.min(18.0, size.width / 4) / size.width;
      context.canvas.drawRect(
        bounds,
        Paint()
          ..blendMode = BlendMode.dstIn
          ..shader = LinearGradient(
            colors: [
              // Resting at its start, the first letters stay whole.
              shift < 1 ? VColors.black : VColors.transparent,
              VColors.black,
              VColors.black,
              VColors.transparent,
            ],
            stops: [0, edge, 1 - edge, 1],
          ).createShader(bounds),
      );
      context.canvas.restore();
    });
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      false;
}
