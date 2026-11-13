import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/widgets.dart';

/// A blur that rides a motion (as Cariño's): none at either end, strongest
/// half way, so a moving page softens as it moves and lands sharp. It blurs
/// the page itself, not what's behind it, so nothing pops when it ends.
class VMotionBlur extends StatelessWidget {
  const VMotionBlur({
    super.key,
    required this.animation,
    required this.child,
    this.sigma = 5,
  });

  /// 0 → 1 over the motion.
  final Animation<double> animation;
  final Widget child;

  /// The blur half way.
  final double sigma;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: animation,
    child: child,
    builder: (context, child) {
      final s = math.sin(math.pi * animation.value.clamp(0.0, 1.0)) * sigma;
      return ImageFiltered(
        enabled: s > 0.05,
        imageFilter: ImageFilter.blur(sigmaX: s, sigmaY: s),
        child: child,
      );
    },
  );
}

/// Moving between whole screens that have no background of their own (the
/// setup steps, over the shared wallpaper): the old one slides a little
/// left, blurs and is gone by half way; the new one comes in from the right
/// the same way. They never show their text over each other.
Widget stepTransition(
  Animation<double> animation,
  Animation<double> secondary,
  Widget child,
) {
  final enter = CurvedAnimation(
    parent: animation,
    curve: const Interval(0.35, 1, curve: Curves.easeOutCubic),
    reverseCurve: const Interval(0.35, 1, curve: Curves.easeInCubic),
  );
  final leave = CurvedAnimation(
    parent: secondary,
    curve: const Interval(0, 0.5, curve: Curves.easeInCubic),
    reverseCurve: const Interval(0, 0.5, curve: Curves.easeOutCubic),
  );
  return AnimatedBuilder(
    animation: Listenable.merge([animation, secondary]),
    child: child,
    builder: (context, child) {
      final a = enter.value, b = leave.value;
      final opacity = (a * (1 - b)).clamp(0.0, 1.0);
      final dx = (1 - a) * 48 - b * 48;
      // The blur follows the whole motion, in and out.
      final s =
          (math.sin(math.pi * animation.value.clamp(0.0, 1.0)) +
              math.sin(math.pi * secondary.value.clamp(0.0, 1.0))) *
          6;
      if (opacity == 0) return const SizedBox.expand();
      return Opacity(
        opacity: opacity,
        child: Transform.translate(
          offset: Offset(dx, 0),
          child: ImageFiltered(
            enabled: s > 0.05,
            imageFilter: ImageFilter.blur(sigmaX: s, sigmaY: s),
            child: child,
          ),
        ),
      );
    },
  );
}
