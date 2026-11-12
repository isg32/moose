import '../core/theme/v_palette.dart';
import '../features/common/wallpaper.dart';

/// A wallpaper: one of the built-in palettes (`VWallpapers`) or a photo.
/// (As in Cariño.)
class WallpaperRef {
  const WallpaperRef.builtin(String this.builtin) : photo = null;
  const WallpaperRef.photo(String this.photo) : builtin = null;

  factory WallpaperRef.fromJson(Map<String, Object?> j) => j['photo'] != null
      ? WallpaperRef.photo(j['photo']! as String)
      : WallpaperRef.builtin((j['builtin'] as String?) ?? 'night');

  final String? builtin;
  final String? photo;

  Map<String, Object?> toJson() => {'builtin': builtin, 'photo': photo};

  @override
  bool operator ==(Object other) =>
      other is WallpaperRef && other.builtin == builtin && other.photo == photo;

  @override
  int get hashCode => Object.hash(builtin, photo);
}

/// Which ink a photo wallpaper gets. Built-in palettes always use [auto].
enum InkChoice { auto, white, black }

/// The couple's shared look (C22): wallpaper, dim, blur and glass. Either
/// partner can change it for both; the last change wins.
class ChatTheme {
  const ChatTheme({
    this.wallpaper = const WallpaperRef.builtin('night'),
    this.dim = 0.0,
    this.blur = 0.0,
    this.glass = 0.5,
    this.ink = InkChoice.auto,
  });

  final WallpaperRef wallpaper;

  /// 0–1, black over the wallpaper.
  final double dim;

  /// 0–1, photos only.
  final double blur;

  /// 0 (barely there) to 1 (frosted).
  final double glass;

  /// "Use black ink" on a photo (C23).
  final InkChoice ink;

  /// Light wallpapers take black ink, dark ones white (DESIGN.md › Rules 2).
  bool get isLight => switch (ink) {
    InkChoice.white => false,
    InkChoice.black => true,
    InkChoice.auto => wallpaperIsLight(wallpaper) && dim < 0.3,
  };

  VPalette get palette =>
      (isLight ? VPalette.light : VPalette.dark).withGlass(glass);

  ChatTheme copyWith({
    WallpaperRef? wallpaper,
    double? dim,
    double? blur,
    double? glass,
    InkChoice? ink,
  }) => ChatTheme(
    wallpaper: wallpaper ?? this.wallpaper,
    dim: dim ?? this.dim,
    blur: blur ?? this.blur,
    glass: glass ?? this.glass,
    ink: ink ?? this.ink,
  );

  Map<String, Object?> toJson() => {
    'wallpaper': wallpaper.toJson(),
    'dim': dim,
    'blur': blur,
    'glass': glass,
    'ink': ink.name,
  };

  factory ChatTheme.fromJson(Map<String, Object?> j) => ChatTheme(
    wallpaper: WallpaperRef.fromJson(
      (j['wallpaper'] as Map<String, Object?>?) ?? const {},
    ),
    dim: (j['dim'] as num?)?.toDouble() ?? 0,
    blur: (j['blur'] as num?)?.toDouble() ?? 0,
    glass: (j['glass'] as num?)?.toDouble() ?? 0.5,
    ink: InkChoice.values.asNameMap()[j['ink']] ?? InkChoice.auto,
  );

  @override
  bool operator ==(Object other) =>
      other is ChatTheme &&
      other.wallpaper == wallpaper &&
      other.dim == dim &&
      other.blur == blur &&
      other.glass == glass &&
      other.ink == ink;

  @override
  int get hashCode => Object.hash(wallpaper, dim, blur, glass, ink);
}
