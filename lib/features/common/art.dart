import 'package:flutter/widgets.dart';

import '../../core/theme/v_colors.dart';

/// Stand-in art for a photo, video, GIF or cover: one of [VMockArt]'s
/// gradients until real media arrives.
class ArtBox extends StatelessWidget {
  const ArtBox({
    super.key,
    required this.art,
    this.radius = BorderRadius.zero,
    this.child,
    this.width,
    this.height,
    this.begin = Alignment.topLeft,
    this.end = Alignment.bottomRight,
  });

  final int art;
  final BorderRadius radius;
  final Widget? child;
  final double? width;
  final double? height;
  final Alignment begin;
  final Alignment end;

  @override
  Widget build(BuildContext context) {
    final (a, b) = VMockArt.of(art);
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: radius,
        gradient: LinearGradient(colors: [a, b], begin: begin, end: end),
      ),
      child: child,
    );
  }
}

/// White text and icons on media, which is dark whatever the ink.
class OnMedia extends StatelessWidget {
  const OnMedia({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => DefaultTextStyle.merge(
    style: const TextStyle(color: VColors.white),
    child: child,
  );
}
