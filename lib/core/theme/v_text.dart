import 'package:flutter/widgets.dart';

/// Type scale from `design/DESIGN.md`.
///
/// Doto is for titles, numbers and times; Inter for everything else. Both are
/// bundled as variable fonts, so the weight is set on the `wght` axis as well
/// as through [FontWeight]. Styles carry no colour: the surrounding
/// [DefaultTextStyle] decides black or white, which is how inversion works.
abstract final class VText {
  static const String dotoFamily = 'Doto';
  static const String interFamily = 'Inter';

  static TextStyle doto(
    double size, {
    int weight = 700,
    double? height,
    double? letterSpacing,
  }) => _style(dotoFamily, size, weight, height, letterSpacing);

  static TextStyle inter(
    double size, {
    int weight = 400,
    double? height,
    double? letterSpacing,
  }) => _style(interFamily, size, weight, height, letterSpacing);

  static TextStyle _style(
    String family,
    double size,
    int weight,
    double? height,
    double? letterSpacing,
  ) {
    return TextStyle(
      fontFamily: family,
      fontSize: size,
      fontWeight: FontWeight.values[(weight ~/ 100).clamp(1, 9) - 1],
      fontVariations: [FontVariation('wght', weight.toDouble())],
      height: height,
      letterSpacing: letterSpacing,
    );
  }

  /// Page title, e.g. "Focus".
  static final TextStyle title = doto(34, height: 1);

  /// Eyebrow label above a card, e.g. "SCREEN TIME". Always uppercase.
  static final TextStyle eyebrow = inter(11, weight: 500, letterSpacing: 1.1);

  /// Default body text.
  static final TextStyle body = inter(14);

  /// Title of a list row.
  static final TextStyle rowTitle = inter(15, weight: 500);

  /// Subtitles, footnotes and secondary values.
  static final TextStyle secondary = inter(12, weight: 300, height: 1.35);

  /// Footnote under a section.
  static final TextStyle footnote = inter(12, weight: 300, height: 1.5);

  /// Label of a primary button.
  static final TextStyle button = inter(16, weight: 600);

  /// Label of a secondary or ghost button.
  static final TextStyle buttonSecondary = inter(15, weight: 500);

  /// Small pill labels (chips, badges, compact segmented controls).
  static final TextStyle chip = inter(11, weight: 500);

  /// Monospace for ADB commands.
  static const TextStyle mono = TextStyle(
    fontFamily: 'monospace',
    fontSize: 11.5,
    height: 1.5,
  );
}
