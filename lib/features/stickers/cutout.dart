import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:google_mlkit_subject_segmentation/google_mlkit_subject_segmentation.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/theme/v_colors.dart';
import '../../core/theme/v_text.dart';

/// A brush stroke on the cut: erase (take away) or restore (bring back),
/// in 0–1 photo space so it fits any size.
class CutStroke {
  CutStroke({required this.erase, required this.width});
  final bool erase;

  /// Brush width as a share of the photo's width.
  final double width;
  final List<Offset> points = [];
}

/// A photo becoming a sticker (S2): the subject cut out on the phone with
/// ML Kit, touched up with Erase and Restore, a white outline and a
/// caption, then drawn into a transparent PNG.
class Cutout extends ChangeNotifier {
  Cutout._(this.photo, this.workPath);

  /// The photo, at most 1024 px across (its EXIF turn applied).
  final ui.Image photo;
  final String workPath;

  /// How much of each pixel is the subject; null until cut (all of it).
  ui.Image? mask;
  final strokes = <CutStroke>[];
  bool outline = true;
  String caption = '';
  bool cutting = false;

  static Future<Cutout> open(String path) async {
    final bytes = await File(path).readAsBytes();
    final probe = await ui.ImageDescriptor.encoded(
      await ui.ImmutableBuffer.fromUint8List(bytes),
    );
    final big = math.max(probe.width, probe.height);
    final k = big > 1024 ? 1024 / big : 1.0;
    final codec = await probe.instantiateCodec(
      targetWidth: (probe.width * k).round(),
      targetHeight: (probe.height * k).round(),
    );
    final photo = (await codec.getNextFrame()).image;
    // ML Kit reads a file: give it this exact picture, so the mask lines
    // up pixel for pixel.
    final png = (await photo.toByteData(format: ui.ImageByteFormat.png))!;
    final work = File(
      '${(await getTemporaryDirectory()).path}/cut-${DateTime.now().microsecondsSinceEpoch}.png',
    )..writeAsBytesSync(png.buffer.asUint8List());
    return Cutout._(photo, work.path);
  }

  /// Finds the subject and cuts it out. False when it can't here (the
  /// desktop build), and the whole photo stays.
  Future<bool> autoCut() async {
    if (!Platform.isAndroid && !Platform.isIOS) return false;
    cutting = true;
    notifyListeners();
    final segmenter = SubjectSegmenter(
      options: SubjectSegmenterOptions(
        enableForegroundConfidenceMask: true,
        enableForegroundBitmap: false,
        enableMultipleSubjects: SubjectResultOptions(
          enableConfidenceMask: false,
          enableSubjectBitmap: false,
        ),
      ),
    );
    try {
      final result = await segmenter.processImage(
        InputImage.fromFilePath(workPath),
      );
      final conf = result.foregroundConfidenceMask;
      final w = photo.width, h = photo.height;
      if (conf == null || conf.length != w * h) return false;
      final rgba = Uint8List(w * h * 4);
      for (var i = 0; i < conf.length; i++) {
        // A soft edge: fully in above 0.7, out below 0.3.
        final a = ((conf[i] - 0.3) / 0.4).clamp(0.0, 1.0);
        final o = i * 4;
        rgba[o] = 255;
        rgba[o + 1] = 255;
        rgba[o + 2] = 255;
        rgba[o + 3] = (a * 255).round();
      }
      final done = Completer<ui.Image>();
      ui.decodeImageFromPixels(
        rgba,
        w,
        h,
        ui.PixelFormat.rgba8888,
        done.complete,
      );
      mask = await done.future;
      strokes.clear();
      return true;
    } on Object {
      return false;
    } finally {
      cutting = false;
      unawaited(segmenter.close());
      notifyListeners();
    }
  }

  void stroke(CutStroke s) {
    strokes.add(s);
    notifyListeners();
  }

  void moved() => notifyListeners();

  void undo() {
    if (strokes.isNotEmpty) strokes.removeLast();
    notifyListeners();
  }

  void setOutline(bool on) {
    outline = on;
    notifyListeners();
  }

  void setCaption(String text) {
    caption = text;
    notifyListeners();
  }

  Size get size => Size(photo.width.toDouble(), photo.height.toDouble());

  /// The mask (cut, then each stroke) drawn into [dst].
  void _paintMask(Canvas c, Rect dst) {
    final m = mask;
    if (m == null) {
      c.drawRect(dst, Paint()..color = VColors.white);
    } else {
      c.drawImageRect(
        m,
        Offset.zero & Size(m.width.toDouble(), m.height.toDouble()),
        dst,
        Paint()..filterQuality = FilterQuality.medium,
      );
    }
    for (final s in strokes) {
      if (s.points.isEmpty) continue;
      final p = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = s.width * dst.width
        ..color = VColors.white
        ..blendMode = s.erase ? BlendMode.clear : BlendMode.srcOver;
      final path = Path();
      final first = s.points.first;
      path.moveTo(
        dst.left + first.dx * dst.width,
        dst.top + first.dy * dst.height,
      );
      for (final q in s.points.skip(1)) {
        path.lineTo(dst.left + q.dx * dst.width, dst.top + q.dy * dst.height);
      }
      if (s.points.length == 1) {
        c.drawCircle(
          Offset(
            dst.left + first.dx * dst.width,
            dst.top + first.dy * dst.height,
          ),
          p.strokeWidth / 2,
          p..style = PaintingStyle.fill,
        );
      } else {
        c.drawPath(path, p);
      }
    }
  }

  /// The sticker into [dst]: outline, the cut-out photo, the caption.
  void paint(Canvas c, Rect dst, {required Rect bounds}) {
    final edge = dst.width * 0.022;
    if (outline) {
      // The mask grown by [edge] and filled white, under the photo.
      c.saveLayer(
        bounds,
        Paint()
          ..imageFilter = ui.ImageFilter.dilate(radiusX: edge, radiusY: edge),
      );
      _paintMask(c, dst);
      c.drawRect(
        bounds,
        Paint()
          ..color = VColors.white
          ..blendMode = BlendMode.srcIn,
      );
      c.restore();
    }
    c.saveLayer(bounds, Paint());
    c.drawImageRect(
      photo,
      Offset.zero & size,
      dst,
      Paint()..filterQuality = FilterQuality.high,
    );
    c.saveLayer(bounds, Paint()..blendMode = BlendMode.dstIn);
    _paintMask(c, dst);
    c.restore();
    c.restore();
    if (caption.isNotEmpty) {
      final tp = TextPainter(
        text: TextSpan(
          text: caption,
          style: VText.doto(
            dst.width * 0.09,
            weight: 800,
          ).copyWith(color: VColors.black),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 2,
        textAlign: TextAlign.center,
      )..layout(maxWidth: dst.width * 0.9);
      final padX = dst.width * 0.04, padY = dst.width * 0.015;
      final box = Rect.fromCenter(
        center: Offset(
          dst.center.dx,
          dst.bottom - tp.height / 2 - dst.height * 0.05,
        ),
        width: tp.width + padX * 2,
        height: tp.height + padY * 2,
      );
      c.save();
      c.translate(box.center.dx, box.center.dy);
      c.rotate(-4 * math.pi / 180);
      c.translate(-box.center.dx, -box.center.dy);
      c.drawRRect(
        RRect.fromRectAndRadius(box, Radius.circular(box.height / 2)),
        Paint()..color = VColors.white,
      );
      tp.paint(c, Offset(box.left + padX, box.top + padY));
      c.restore();
      tp.dispose();
    }
  }

  /// The finished sticker: a transparent PNG at the photo's size, with
  /// room for the outline.
  Future<String> export(Directory dir) async {
    final pad = size.width * 0.05;
    final out = Size(size.width + pad * 2, size.height + pad * 2);
    final rec = ui.PictureRecorder();
    final c = Canvas(rec);
    paint(c, Offset(pad, pad) & size, bounds: Offset.zero & out);
    final image = await rec.endRecording().toImage(
      out.width.round(),
      out.height.round(),
    );
    final png = (await image.toByteData(format: ui.ImageByteFormat.png))!;
    await dir.create(recursive: true);
    final file = File(
      '${dir.path}/cut-${DateTime.now().microsecondsSinceEpoch}.png',
    );
    await file.writeAsBytes(png.buffer.asUint8List(), flush: true);
    return file.path;
  }
}

/// The cut on screen: the sticker on a checkerboard, and the brush when
/// Erase or Restore is on.
class CutoutCanvas extends StatelessWidget {
  const CutoutCanvas({super.key, required this.cut, this.brush});

  final Cutout cut;

  /// Erase (true), Restore (false), or no brush (null).
  final bool? brush;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final k = math.min(
        box.maxWidth * 0.86 / cut.size.width,
        box.maxHeight * 0.86 / cut.size.height,
      );
      final dst = Rect.fromCenter(
        center: box.biggest.center(Offset.zero),
        width: cut.size.width * k,
        height: cut.size.height * k,
      );
      Offset rel(Offset p) => Offset(
        ((p.dx - dst.left) / dst.width).clamp(-0.1, 1.1),
        ((p.dy - dst.top) / dst.height).clamp(-0.1, 1.1),
      );
      final erase = brush;
      return GestureDetector(
        onPanStart: erase == null
            ? null
            : (d) => cut.stroke(
                CutStroke(erase: erase, width: 0.07)
                  ..points.add(rel(d.localPosition)),
              ),
        onPanUpdate: erase == null
            ? null
            : (d) {
                cut.strokes.last.points.add(rel(d.localPosition));
                cut.moved();
              },
        child: ListenableBuilder(
          listenable: cut,
          builder: (context, _) =>
              CustomPaint(size: box.biggest, painter: _CutPainter(cut, dst)),
        ),
      );
    },
  );
}

class _CutPainter extends CustomPainter {
  _CutPainter(this.cut, this.dst);
  final Cutout cut;
  final Rect dst;

  @override
  void paint(Canvas canvas, Size size) =>
      cut.paint(canvas, dst, bounds: Offset.zero & size);

  @override
  bool shouldRepaint(_CutPainter old) => true;
}
