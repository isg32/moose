import 'dart:io';

import 'package:flutter/widgets.dart';

import '../../core/theme/v_colors.dart';
import '../../core/widgets/v_progress.dart';

/// A photo, video, GIF or cover: the real file at [path] once it's on the
/// phone, else one of [VMockArt]'s gradients standing in for it.
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
    this.path,
    this.url,
    this.full = false,
  });

  /// Decode [path] at full size (the zoomable viewer), not 1080 px wide.
  final bool full;

  final int art;
  final String? path;

  /// A picture on the web (song covers, memes), when there's no [path].
  final String? url;
  final BorderRadius radius;
  final Widget? child;
  final double? width;
  final double? height;
  final Alignment begin;
  final Alignment end;

  @override
  Widget build(BuildContext context) {
    final (a, b) = VMockArt.of(art);
    final file = path;
    final web = url;
    return Container(
      width: width,
      height: height,
      clipBehavior: file == null && web == null ? Clip.none : Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: radius,
        gradient: LinearGradient(colors: [a, b], begin: begin, end: end),
        image: file != null
            ? DecorationImage(
                image: full
                    ? FileImage(File(file))
                    : ResizeImage(FileImage(File(file)), width: 1080),
                fit: BoxFit.cover,
              )
            : null,
      ),
      child: web == null || file != null
          ? child
          : Stack(
              fit: StackFit.passthrough,
              children: [
                // Decoded no wider than 720 px (a Reddit GIF can be 10 MB),
                // with a spinner until it's ready, then fades in.
                Positioned.fill(
                  child: Image(
                    image: ResizeImage(NetworkImage(web), width: 720),
                    fit: BoxFit.cover,
                    gaplessPlayback: true,
                    frameBuilder: (context, img, frame, sync) {
                      if (sync) return img;
                      return Stack(
                        fit: StackFit.expand,
                        children: [
                          if (frame == null && (width == null || width! >= 64))
                            const Center(child: VSpinner(size: 22)),
                          AnimatedOpacity(
                            opacity: frame == null ? 0 : 1,
                            duration: const Duration(milliseconds: 260),
                            curve: Curves.easeOut,
                            child: img,
                          ),
                        ],
                      );
                    },
                    errorBuilder: (_, _, _) => const SizedBox.shrink(),
                  ),
                ),
                ?child,
              ],
            ),
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
