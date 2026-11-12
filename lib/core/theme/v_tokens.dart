import 'package:flutter/animation.dart';

/// Radii from `design/DESIGN.md`.
abstract final class VRadius {
  static const double card = 20;
  static const double cardLarge = 24;
  static const double taskRow = 18;
  static const double sheet = 28;
  static const double appTile = 10;
  static const double pill = 999;
}

/// Spacing from `design/DESIGN.md`.
abstract final class VSpace {
  /// Side gutter for cards.
  static const double gutter = 16;

  /// Side gutter for page titles.
  static const double titleGutter = 20;

  /// Gap between cards.
  static const double cardGap = 12;

  /// Inner padding of a card.
  static const double cardPadding = 16;

  /// Bottom padding on tab pages so content clears the floating tab bar.
  static const double tabBarClearance = 120;

  /// Hairline width.
  static const double hairline = 1;
}

/// Motion: 250 ms ease-out fades and slides, no bounce.
abstract final class VMotion {
  static const Duration standard = Duration(milliseconds: 250);
  static const Curve curve = Curves.easeOut;

  /// Breathing: in for 4 s, out for 6 s.
  static const Duration breatheIn = Duration(seconds: 4);
  static const Duration breatheOut = Duration(seconds: 6);
}
