import 'package:flutter/widgets.dart';

/// The only colours Moose may use (Veronica's palette, as in Cariño).
///
/// The interface is pure black and white: white ink on dark wallpapers,
/// black ink on light ones. Translucency exists only for the glass surfaces
/// named here. Colour comes in from two places only: the shared wallpaper
/// (its palettes are at the end of this file) and the moment colours of
/// hugs, pokes, kisses and miss-yous ([VMoment]). Colored app icons are images, not
/// colours. `test/design/no_banned_colors_test.dart` fails the build if a
/// colour is created anywhere outside this file.
abstract final class VColors {
  static const Color black = Color(0xFF000000);
  static const Color white = Color(0xFFFFFFFF);
  static const Color transparent = Color(0x00000000);

  /// Floating tab bar: white at 10 %.
  static const Color glassBar = Color(0x1AFFFFFF);

  /// Glass card (icons, widgets): white at 8 %.
  static const Color glassCard = Color(0x14FFFFFF);

  /// Bottom sheet: black at 55 %.
  static const Color glassSheet = Color(0x8C000000);

  /// Light ink: tab bar is black at 6 %.
  static const Color glassBarLight = Color(0x0F000000);

  /// Light ink: glass card is black at 5 %.
  static const Color glassCardLight = Color(0x0D000000);

  /// Light ink: bottom sheet is white at 60 %.
  static const Color glassSheetLight = Color(0x99FFFFFF);

  /// Veil over the blurred wallpaper on Apps, Widgets and full pages:
  /// black at 60 %.
  static const Color veil = Color(0x99000000);

  /// Light ink: white at 60 %.
  static const Color veilLight = Color(0x99FFFFFF);

  /// Behind a popup (no blur under it): black at 70 %.
  static const Color popupScrim = Color(0xB3000000);

  /// Light ink: white at 70 %.
  static const Color popupScrimLight = Color(0xB3FFFFFF);

  /// Opacity of a disabled primary action.
  static const double disabledOpacity = 0.35;

  /// The colour that sits on top of [color] (black on white, white on black).
  static Color onColor(Color color) => color == white ? black : white;
}

/// One soft blob of a built-in wallpaper.
class VWallpaperBlob {
  const VWallpaperBlob(this.color, this.x, this.y, this.radius);

  final Color color;

  /// Centre, as an alignment (-1 to 1).
  final double x;
  final double y;

  /// Radius as a fraction of the longer side.
  final double radius;
}

/// A built-in wallpaper: a base colour with soft blobs over it.
class VWallpaperPalette {
  const VWallpaperPalette(this.base, this.blobs, {this.light = false});

  final Color base;
  final List<VWallpaperBlob> blobs;

  /// Light wallpapers suggest black ink.
  final bool light;
}

/// Cariño's built-in wallpapers, shared by both partners in Moose.
abstract final class VWallpapers {
  static const night = VWallpaperPalette(Color(0xFF06070A), [
    VWallpaperBlob(Color(0xFF24344F), -0.7, -0.8, 0.75),
    VWallpaperBlob(Color(0xFF3D2536), 0.9, 0.1, 0.6),
    VWallpaperBlob(Color(0xFF15322F), -0.4, 1.1, 0.7),
  ]);

  static const dune = VWallpaperPalette(Color(0xFF120B07), [
    VWallpaperBlob(Color(0xFF6B3B1F), 0.6, -0.6, 0.8),
    VWallpaperBlob(Color(0xFF3A2416), -0.8, 0.8, 0.65),
  ]);

  static const paper = VWallpaperPalette(Color(0xFFEFE9E0), [
    VWallpaperBlob(Color(0xFFF3E6D2), 0.7, -0.85, 0.7),
    VWallpaperBlob(Color(0xFFDCD0C0), -1.0, 0.2, 0.65),
    VWallpaperBlob(Color(0xFFCDBFA9), 0.4, 1.1, 0.6),
  ], light: true);

  static const moss = VWallpaperPalette(Color(0xFF060A07), [
    VWallpaperBlob(Color(0xFF1F3A26), -0.6, 0.8, 0.7),
    VWallpaperBlob(Color(0xFF2C3B2F), 0.8, -0.8, 0.6),
  ]);

  static const fog = VWallpaperPalette(Color(0xFF1A1D22), [
    VWallpaperBlob(Color(0xFF5B6470), 0.0, -0.4, 0.8),
  ]);

  static const ember = VWallpaperPalette(Color(0xFF0B0505), [
    VWallpaperBlob(Color(0xFF5A1A1A), -0.4, 0.6, 0.6),
  ]);

  static const black = VWallpaperPalette(VColors.black, []);

  static const white = VWallpaperPalette(VColors.white, [], light: true);

  static const all = <String, VWallpaperPalette>{
    'night': night,
    'dune': dune,
    'paper': paper,
    'moss': moss,
    'fog': fog,
    'ember': ember,
    'black': black,
    'white': white,
  };
}

/// The four moments a partner can send, each with its own colour: the one
/// exception to the two inks (see `design/DESIGN.md` › Moment colours).
/// Used only in poke bursts, the poke picker, poke rows in the chat and
/// poke notifications.
enum VMoment {
  poke('Poke', '👉', Color(0xFFFFC15E), 0.50),
  hug('Hug', '🫂', Color(0xFFFF8FA3), 0.55),
  kiss('Kiss', '💋', Color(0xFFFF5C7A), 0.55),
  missYou('Miss you', '🥺', Color(0xFF9DB2FF), 0.50);

  const VMoment(this.label, this.emoji, this.color, this.washAlpha);

  final String label;
  final String emoji;

  /// The moment's colour: tiles, the burst's rings and centre, its chip.
  final Color color;

  /// How strong the radial wash behind a burst is.
  final double washAlpha;

  /// The wash at the centre of a burst.
  Color get wash => color.withValues(alpha: washAlpha);

  /// A poke row's tinted background in the chat.
  Color get tint => color.withValues(alpha: 0.18);
}

/// Stand-in art for mock photos, videos, GIFs, stickers and song covers until
/// real media arrives (Phase 4): two-stop gradients from the design canvas.
/// Content, not interface.
abstract final class VMockArt {
  static const List<(Color, Color)> gradients = [
    (Color(0xFF6B3B1F), Color(0xFF24344F)),
    (Color(0xFF1F3A26), Color(0xFF5B6470)),
    (Color(0xFF3D2536), Color(0xFF5A1A1A)),
    (Color(0xFF3A2416), Color(0xFFCDBFA9)),
    (Color(0xFF15322F), Color(0xFF3D2536)),
    (Color(0xFF24344F), Color(0xFF15322F)),
    (Color(0xFF1F3A26), Color(0xFFFFC15E)),
    (Color(0xFF6B3B1F), Color(0xFFFF8FA3)),
    (Color(0xFF3D2536), Color(0xFF9DB2FF)),
    (Color(0xFF24344F), Color(0xFFF3E6D2)),
  ];

  static (Color, Color) of(int art) => gradients[art % gradients.length];
}

/// Pen colours for doodles and stickers: what people draw with, not the
/// interface. Strokes store their colour as ARGB; [of] turns it back.
abstract final class VPenColors {
  static const List<int> presets = [
    0xFF000000, 0xFFFFFFFF, 0xFFFF5C7A, 0xFFFF8FA3, //
    0xFFFFC15E, 0xFFFFE066, 0xFF3FA34D, 0xFF5BC0EB,
    0xFF9DB2FF, 0xFFB57EDC, 0xFF6B3B1F, 0xFF24344F,
    0xFFF3E6D2, 0xFF5B6470, 0xFF5A1A1A, 0xFF1F3A26,
  ];

  /// The hues on the colour wheel, in order round it.
  static const List<Color> wheel = [
    Color(0xFFFF5C7A),
    Color(0xFFFFC15E),
    Color(0xFFFFE066),
    Color(0xFF3FA34D),
    Color(0xFF5BC0EB),
    Color(0xFF9DB2FF),
    Color(0xFFB57EDC),
    Color(0xFFFF5C7A),
  ];

  static Color of(int argb) => Color(argb);
}
