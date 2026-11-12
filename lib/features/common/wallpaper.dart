import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../../core/theme/v_colors.dart';
import '../../data/chat_theme.dart';

/// The image a photo wallpaper is drawn from: the blurred copy when one is
/// asked for and made, else the photo, always at the same decode size, so
/// every view of the same wallpaper shares one decoded image.
ImageProvider wallpaperImage(
  String photo, {
  double blur = 0,
  bool soft = false,
}) {
  if (soft) return ResizeImage(FileImage(File(photo)), width: 40);
  if (blur > 0.01 && blurReady(photo, blur)) {
    return FileImage(File(bakedPath(photo, blur)));
  }
  return ResizeImage(FileImage(File(photo)), width: blur > 0.01 ? 720 : 1440);
}

/// Decodes [image] (if not already) and completes when it can be drawn.
Future<void> warmImage(ImageProvider image) {
  final done = Completer<void>();
  final stream = image.resolve(ImageConfiguration.empty);
  late final ImageStreamListener listener;
  void finish() {
    if (!done.isCompleted) done.complete();
    stream.removeListener(listener);
  }

  listener = ImageStreamListener(
    (_, _) => finish(),
    onError: (_, _) => finish(),
  );
  stream.addListener(listener);
  return done.future;
}

/// Draws a layout's wallpaper: a built-in palette or a photo, with its dim.
///
/// When the wallpaper changes, the new one is decoded first and then fades
/// in over the old one, so a layout switch never shows an empty or
/// half-loaded frame.
class WallpaperView extends StatefulWidget {
  const WallpaperView({
    super.key,
    required this.wallpaper,
    this.dim = 0,
    this.blur = 0,
    this.soft = false,
  });

  final WallpaperRef wallpaper;
  final double dim;

  /// Blur over a photo (0–1). Shown from the file [bakeBlur] wrote; until
  /// that exists, blurred live.
  final double blur;

  /// A blurred-looking copy: photos are decoded tiny and scaled up, which
  /// reads as a heavy blur at no per-frame cost. Built-in palettes are soft
  /// already.
  final bool soft;

  @override
  State<WallpaperView> createState() => _WallpaperViewState();
}

class _WallpaperViewState extends State<WallpaperView> {
  late _Shown _shown = _Shown.of(widget);
  int _generation = 0;

  @override
  void didUpdateWidget(WallpaperView old) {
    super.didUpdateWidget(old);
    final next = _Shown.of(widget);
    if (next.key == _shown.key) return;
    final generation = ++_generation;
    final image = next.image;
    if (image == null) {
      setState(() => _shown = next);
      return;
    }
    // Keep showing the old wallpaper until the new one is decoded.
    warmImage(image).then((_) {
      if (mounted && generation == _generation) setState(() => _shown = next);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 320),
      switchInCurve: Curves.easeOutCubic,
      layoutBuilder: (current, previous) =>
          Stack(fit: StackFit.expand, children: [...previous, ?current]),
      child: KeyedSubtree(key: ValueKey(_shown.key), child: _shown.build()),
    );
  }
}

/// One wallpaper as it is drawn, with a key that changes exactly when what
/// shows changes.
class _Shown {
  _Shown(this.key, this.image, this.build);

  factory _Shown.of(WallpaperView w) {
    final photo = w.wallpaper.photo;
    final dim = w.dim.clamp(0.0, 0.8);
    Widget withDim(Widget base) => Stack(
      fit: StackFit.expand,
      children: [
        base,
        if (dim > 0) ColoredBox(color: VColors.black.withValues(alpha: dim)),
      ],
    );

    if (photo == null) {
      final palette = VWallpapers.all[w.wallpaper.builtin] ?? VWallpapers.night;
      return _Shown(
        'b:${w.wallpaper.builtin}:$dim',
        null,
        () => withDim(_Palette(palette)),
      );
    }
    final blur = w.soft ? 0.0 : w.blur;
    final image = wallpaperImage(photo, blur: blur, soft: w.soft);
    final baked = blur > 0.01 && blurReady(photo, blur);
    final live = blur > 0.01 && !baked;
    Widget picture() => Image(
      image: image,
      fit: BoxFit.cover,
      gaplessPlayback: true,
      filterQuality: w.soft ? FilterQuality.high : FilterQuality.medium,
      errorBuilder: (_, _, _) => const _Palette(VWallpapers.night),
    );
    return _Shown(
      'p:$photo:${w.soft}:$blur:$baked:$dim',
      image,
      () => withDim(
        live
            ? ImageFiltered(
                imageFilter: ui.ImageFilter.blur(
                  sigmaX: blur * 30,
                  sigmaY: blur * 30,
                  tileMode: TileMode.clamp,
                ),
                child: picture(),
              )
            : picture(),
      ),
    );
  }

  final String key;
  final ImageProvider? image;
  final Widget Function() build;
}

/// Whether the blurred copy of [photo] at [blur] already exists.
bool blurReady(String photo, double blur) =>
    File(bakedPath(photo, blur)).existsSync();

/// Where the blurred copy of [photo] at [blur] is kept.
String bakedPath(String photo, double blur) =>
    '$photo.b${(blur * 100).round()}.png';

/// Renders [photo] blurred once and saves it beside the photo, so Home shows
/// a plain image instead of blurring a full-screen photo on every frame.
Future<void> bakeBlur(String photo, double blur) async {
  if (blur <= 0.01) return;
  final out = File(bakedPath(photo, blur));
  if (out.existsSync()) return;
  final codec = await ui.instantiateImageCodec(
    await File(photo).readAsBytes(),
    targetWidth: 720,
  );
  final image = (await codec.getNextFrame()).image;
  final w = image.width.toDouble();
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final sigma = blur * 30 * (w / 412);
  canvas.drawImage(
    image,
    Offset.zero,
    Paint()
      ..imageFilter = ui.ImageFilter.blur(
        sigmaX: sigma,
        sigmaY: sigma,
        tileMode: TileMode.clamp,
      ),
  );
  final blurred = await recorder.endRecording().toImage(
    image.width,
    image.height,
  );
  final png = await blurred.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  blurred.dispose();
  if (png != null) await out.writeAsBytes(png.buffer.asUint8List());
}

/// Deletes a saved photo and every blurred copy of it.
Future<void> deletePhoto(String photo) async {
  final file = File(photo);
  final dir = file.parent;
  if (!dir.existsSync()) return;
  final name = file.uri.pathSegments.last;
  await for (final f in dir.list()) {
    if (f is File && f.uri.pathSegments.last.startsWith(name)) {
      await f.delete();
    }
  }
}

/// Whether a wallpaper suggests black ink.
bool wallpaperIsLight(WallpaperRef w) =>
    w.photo == null && (VWallpapers.all[w.builtin]?.light ?? false);

class _Palette extends StatelessWidget {
  const _Palette(this.palette);

  final VWallpaperPalette palette;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _PalettePainter(palette),
      child: const SizedBox.expand(),
    );
  }
}

class _PalettePainter extends CustomPainter {
  _PalettePainter(this.palette);

  final VWallpaperPalette palette;

  @override
  void paint(Canvas canvas, Size size) =>
      paintWallpaperPalette(canvas, size, palette);

  @override
  bool shouldRepaint(_PalettePainter old) => old.palette != palette;
}

/// Paints a built-in wallpaper: its base, then each soft blob.
void paintWallpaperPalette(
  Canvas canvas,
  Size size,
  VWallpaperPalette palette,
) {
  canvas.drawRect(Offset.zero & size, Paint()..color = palette.base);
  final longer = math.max(size.width, size.height);
  for (final b in palette.blobs) {
    final c = Offset(
      size.width / 2 + b.x * size.width / 2,
      size.height / 2 + b.y * size.height / 2,
    );
    final r = b.radius * longer;
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = RadialGradient(
          colors: [b.color, b.color.withValues(alpha: 0)],
        ).createShader(Rect.fromCircle(center: c, radius: r)),
    );
  }
}
