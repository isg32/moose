import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../core/theme/v_colors.dart';
import 'moment_burst.dart';

/// A moment during a call: no full-screen burst, just its emoji and hearts
/// rising over the call for about two seconds, then gone.
class MomentFlight extends StatefulWidget {
  const MomentFlight({super.key, required this.moment, required this.onDone});

  final VMoment moment;
  final VoidCallback onDone;

  static const length = Duration(milliseconds: 2200);

  @override
  State<MomentFlight> createState() => _MomentFlightState();
}

class _MomentFlightState extends State<MomentFlight>
    with SingleTickerProviderStateMixin {
  late final _t = AnimationController(
    vsync: this,
    duration: MomentFlight.length,
  )..forward().whenComplete(widget.onDone);

  // Each flyer: where it starts across, how far it drifts, its delay,
  // size, spin, and which glyph.
  late final List<(double, double, double, double, double, String)> _flyers =
      () {
        final r = math.Random();
        final glyphs = [widget.moment.emoji, ...widget.moment.hearts];
        return [
          for (var i = 0; i < 22; i++)
            (
              0.08 + r.nextDouble() * 0.84,
              (r.nextDouble() - 0.5) * 0.25,
              r.nextDouble() * 0.35,
              i < 6 ? 44 + r.nextDouble() * 18 : 22 + r.nextDouble() * 16,
              (r.nextDouble() - 0.5) * 0.8,
              i < 6 ? widget.moment.emoji : glyphs[r.nextInt(glyphs.length)],
            ),
        ];
      }();

  @override
  void dispose() {
    _t.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: LayoutBuilder(
      builder: (context, box) => AnimatedBuilder(
        animation: _t,
        builder: (context, _) {
          final t = _t.value;
          return Stack(
            children: [
              // A soft wash of the moment's colour, in and out.
              Positioned.fill(
                child: ColoredBox(
                  color: widget.moment.color.withValues(
                    alpha: 0.18 * math.sin(math.pi * t),
                  ),
                ),
              ),
              for (final (x, drift, delay, size, spin, glyph) in _flyers)
                if (t > delay)
                  () {
                    final p = ((t - delay) / (1 - delay)).clamp(0.0, 1.0);
                    final rise = Curves.easeOutCubic.transform(p);
                    return Positioned(
                      left: (x + drift * p) * box.maxWidth - size / 2,
                      top: box.maxHeight * (1.05 - 1.0 * rise) - size / 2,
                      child: Opacity(
                        opacity:
                            (p < 0.15
                                    ? p / 0.15
                                    : 1 - (p - 0.6).clamp(0, 0.4) / 0.4)
                                .clamp(0.0, 1.0),
                        child: Transform.rotate(
                          angle: spin * p,
                          child: Transform.scale(
                            scale:
                                0.6 +
                                0.5 *
                                    Curves.easeOutBack.transform(
                                      (p * 2).clamp(0.0, 1.0),
                                    ),
                            child: Text(
                              glyph,
                              style: TextStyle(
                                fontSize: size,
                                color: VColors.white,
                                decoration: TextDecoration.none,
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  }(),
            ],
          );
        },
      ),
    ),
  );
}
