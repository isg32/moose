import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../core/theme/v_colors.dart';
import '../../data/models.dart';
import 'art.dart';
import 'strokes.dart';

/// The cut-out outlines photo stickers come in (the canvas's blob radii,
/// as fractions of width and height for each corner).
const _shapes = [
  [(.46, .52), (.54, .44), (.42, .56), (.58, .48)],
  [(.50, .50), (.40, .40), (.55, .55), (.45, .45)],
  [(.40, .55), (.60, .45), (.50, .55), (.50, .45)],
  [(.55, .55), (.45, .45), (.40, .40), (.60, .60)],
];

BorderRadius stickerRadius(int shape, double w, double h) {
  final s = _shapes[shape % _shapes.length];
  Radius r((double, double) c) => Radius.elliptical(c.$1 * w, c.$2 * h);
  return BorderRadius.only(
    topLeft: r(s[0]),
    topRight: r(s[1]),
    bottomRight: r(s[2]),
    bottomLeft: r(s[3]),
  );
}

/// A sticker as it shows in the chat and the tray: no bubble, a white
/// outline and a small tilt (S6).
class StickerView extends StatelessWidget {
  const StickerView(
    this.sticker, {
    super.key,
    this.size = 120,
    this.tilt = 0,
    this.border = 4,
    this.shadow = true,
  });

  final Sticker sticker;
  final double size;

  /// Degrees.
  final double tilt;
  final double border;
  final bool shadow;

  @override
  Widget build(BuildContext context) {
    final Widget art = sticker.isDoodle
        ? SizedBox.square(
            dimension: size,
            child: StrokesView(
              sticker.strokes,
              space: const Size(1, 1),
              outline: border * 1.6,
            ),
          )
        : Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              borderRadius: stickerRadius(sticker.shape, size, size),
              border: Border.all(color: VColors.white, width: border),
              boxShadow: shadow
                  ? [
                      BoxShadow(
                        color: VColors.black.withValues(alpha: 0.35),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ]
                  : null,
            ),
            child: ArtBox(
              art: sticker.art,
              path: sticker.path,
              radius: stickerRadius(sticker.shape, size, size),
            ),
          );
    return Transform.rotate(angle: tilt * math.pi / 180, child: art);
  }
}
