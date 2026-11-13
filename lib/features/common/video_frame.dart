import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:video_player/video_player.dart';

/// A round video note's file in its circle: still on its first frame, and
/// playing (with sound) while [playing].
class RoundPlayer extends StatefulWidget {
  const RoundPlayer(this.path, {super.key, required this.playing});

  final String path;
  final bool playing;

  @override
  State<RoundPlayer> createState() => _RoundPlayerState();
}

class _RoundPlayerState extends State<RoundPlayer> {
  late final VideoPlayerController _c = VideoPlayerController.file(
    File(widget.path),
  );

  @override
  void initState() {
    super.initState();
    _c.initialize().then((_) {
      if (!mounted) return;
      setState(() {});
      if (widget.playing) _c.play();
    }, onError: (Object _) {});
  }

  @override
  void didUpdateWidget(RoundPlayer old) {
    super.didUpdateWidget(old);
    if (!_c.value.isInitialized || old.playing == widget.playing) return;
    if (widget.playing) {
      _c
        ..seekTo(Duration.zero)
        ..play();
    } else {
      _c.pause();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_c.value.isInitialized) return const SizedBox.expand();
    return FittedBox(
      fit: BoxFit.cover,
      clipBehavior: Clip.hardEdge,
      child: SizedBox(
        width: _c.value.size.width,
        height: _c.value.size.height,
        child: VideoPlayer(_c),
      ),
    );
  }
}

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
