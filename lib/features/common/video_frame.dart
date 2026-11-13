import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:video_player/video_player.dart';

/// A real video's first frame, filling its box (the bubble's poster). The
/// stand-in art shows until the file is on the phone.
class VideoFrame extends StatefulWidget {
  const VideoFrame(this.path, {super.key});

  final String path;

  @override
  State<VideoFrame> createState() => _VideoFrameState();
}

class _VideoFrameState extends State<VideoFrame> {
  late final VideoPlayerController _c = VideoPlayerController.file(
    File(widget.path),
  );

  @override
  void initState() {
    super.initState();
    _c.initialize().then((_) {
      if (mounted) setState(() {});
    }, onError: (Object _) {});
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_c.value.isInitialized) return const SizedBox.expand();
    return SizedBox.expand(
      child: FittedBox(
        fit: BoxFit.cover,
        clipBehavior: Clip.hardEdge,
        child: SizedBox(
          width: _c.value.size.width,
          height: _c.value.size.height,
          child: VideoPlayer(_c),
        ),
      ),
    );
  }
}
