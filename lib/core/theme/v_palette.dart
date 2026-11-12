import 'package:flutter/widgets.dart';

import 'v_colors.dart';

/// Black and white, resolved for the current layout.
///
/// Dark is white ink over the wallpaper; light swaps them. Each home layout
/// picks its ink (white, black or follow the system) and how strong the
/// glass is, and publishes the result with [VPaletteScope].
class VPalette {
  const VPalette._(this.brightness, [this.glass = 0.5]);

  static const VPalette dark = VPalette._(Brightness.dark);
  static const VPalette light = VPalette._(Brightness.light);

  factory VPalette.of(BuildContext context) {
    final scoped = context
        .dependOnInheritedWidgetOfExactType<VPaletteScope>()
        ?.palette;
    if (scoped != null) return scoped;
    return MediaQuery.platformBrightnessOf(context) == Brightness.light
        ? light
        : dark;
  }

  final Brightness brightness;

  /// Glass strength, 0 (barely there) to 1 (frosted). 0.5 is Veronica's.
  final double glass;

  VPalette withGlass(double value) =>
      VPalette._(brightness, value.clamp(0.0, 1.0));

  bool get isDark => brightness == Brightness.dark;

  /// Text, lines and icons.
  Color get ink => isDark ? VColors.white : VColors.black;

  /// The page background.
  Color get paper => isDark ? VColors.black : VColors.white;

  double get _glassScale => 0.3 + glass * 1.4;

  Color _scaled(Color c) =>
      c.withValues(alpha: (c.a * _glassScale).clamp(0.0, 1.0));

  /// Blur radius of glass surfaces.
  double get blur => 8 + glass * 20;

  Color get glassBar =>
      _scaled(isDark ? VColors.glassBar : VColors.glassBarLight);
  Color get glassCard =>
      _scaled(isDark ? VColors.glassCard : VColors.glassCardLight);
  Color get glassSheet => isDark ? VColors.glassSheet : VColors.glassSheetLight;
  Color get veil => isDark ? VColors.veil : VColors.veilLight;
  Color get popupScrim => isDark ? VColors.popupScrim : VColors.popupScrimLight;
}

/// Publishes the active layout's [VPalette] to everything below it.
class VPaletteScope extends InheritedWidget {
  const VPaletteScope({super.key, required this.palette, required super.child});

  final VPalette palette;

  @override
  bool updateShouldNotify(VPaletteScope old) =>
      old.palette.brightness != palette.brightness ||
      old.palette.glass != palette.glass;
}
