import 'package:flutter/widgets.dart';

import '../theme/v_colors.dart';

/// The foreground colour ("ink") of the current surface.
///
/// Black surfaces have white ink and inverted (white) surfaces have black
/// ink. Ink travels through [DefaultTextStyle], so text, icons and custom
/// painters all follow it without being told.
abstract final class VInk {
  static Color of(BuildContext context) =>
      DefaultTextStyle.of(context).style.color ?? VColors.white;

  /// The fill of the current surface (the opposite of the ink).
  static Color surfaceOf(BuildContext context) => VColors.onColor(of(context));
}

/// Sets the ink colour for a subtree.
class VInkScope extends StatelessWidget {
  const VInkScope({super.key, required this.ink, required this.child});

  /// Flips the current ink, for content on an inverted surface.
  static Widget inverted(BuildContext context, {required Widget child}) =>
      VInkScope(ink: VInk.surfaceOf(context), child: child);

  final Color ink;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DefaultTextStyle.merge(
      style: TextStyle(color: ink),
      child: child,
    );
  }
}
