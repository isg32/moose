import 'dart:io';

import 'package:flutter/widgets.dart';

import '../../core/theme/v_colors.dart';

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
  });

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
                image: ResizeImage(FileImage(File(file)), width: 1080),
                fit: BoxFit.cover,
              )
            : web != null
            ? DecorationImage(
                image: NetworkImage(web),
                fit: BoxFit.cover,
                onError: (_, _) {},
              )
            : null,
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
