import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'package:flutter/widgets.dart';

import '../../core/icons/v_icons.dart';
import '../../core/theme/v_colors.dart';
import '../../core/theme/v_text.dart';
import '../../core/widgets/v_buttons.dart';
import '../../core/widgets/v_ink.dart';
import '../../core/widgets/v_progress.dart';
import '../../data/models.dart';
import '../common/art.dart';
import '../common/video_frame.dart';
import '../common/parts.dart';
import '../common/rotation.dart';

/// One item the viewer can show, with who sent it and when.
class ViewerItem {
  const ViewerItem({required this.media, required this.from, required this.at});

  final Media media;
  final String from;
  final DateTime at;

  bool get video => media.duration != null;
}

/// Every photo and video in [messages], oldest first.
List<ViewerItem> viewerItems(
  List<Message> messages, {
  required String partner,
}) => [
  for (final m in messages)
    ...switch (m.body) {
      PhotoBody(:final photos) => photos,
      VideoBody(:final video) => [video],
      RoundVideoBody(:final video) => [video],
      _ => const <Media>[],
    }.map(
      (media) =>
          ViewerItem(media: media, from: m.fromMe ? 'You' : partner, at: m.at),
    ),
];

/// The media viewer (C21): full screen on the page colour, swipe between
/// every photo and video in the chat, pinch to zoom, video controls, and
/// Reply / Save / Share.
class MediaViewer extends StatefulWidget {
  const MediaViewer({
    super.key,
    required this.items,
    required this.start,
    this.onReply,
  });

  final List<ViewerItem> items;
  final int start;
  final void Function(ViewerItem item)? onReply;

  @override
  State<MediaViewer> createState() => _MediaViewerState();
}

class _MediaViewerState extends State<MediaViewer> {
  late final _page = PageController(initialPage: widget.start);
  late int _at = widget.start;
  bool _playing = false;
  double _position = 0;
  Timer? _clock;

  /// The real video on screen, when its file is on the phone.
  VideoPlayerController? _video;

  @override
  void dispose() {
    _clock?.cancel();
    _video?.dispose();
    _page.dispose();
    super.dispose();
  }

  void _dropVideo() {
    final v = _video;
    _video = null;
    unawaited(v?.dispose());
  }

  Future<void> _toggle() async {
    final item = widget.items[_at];
    _clock?.cancel();
    final path = item.media.path;
    if (path != null) {
      var v = _video;
      if (v == null) {
        v = _video = VideoPlayerController.file(File(path));
        await v.initialize();
        v.addListener(() {
          if (!mounted || _video != v) return;
          final d = v!.value.duration.inMilliseconds;
          final ended = d > 0 && v.value.position.inMilliseconds >= d - 50;
          setState(() {
            _playing = v!.value.isPlaying && !ended;
            _position = d == 0 ? 0 : v.value.position.inMilliseconds / d;
            if (ended) _position = 1;
          });
        });
      }
      if (v.value.isPlaying) {
        await v.pause();
      } else {
        if (v.value.position >= v.value.duration) await v.seekTo(Duration.zero);
        await v.play();
      }
      return;
    }
    if (_playing) {
      setState(() => _playing = false);
      return;
    }
    final total = item.media.duration!.inMilliseconds;
    setState(() => _playing = true);
    _clock = Timer.periodic(const Duration(milliseconds: 100), (_) {
      setState(() {
        _position += 100 / total;
        if (_position >= 1) {
          _position = 0;
          _playing = false;
          _clock?.cancel();
        }
      });
    });
  }

  String _when(DateTime t) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final d = DateTime(t.year, t.month, t.day);
    final day = d == today
        ? 'Today'
        : today.difference(d).inDays == 1
        ? 'Yesterday'
        : '${t.day}/${t.month}';
    return '$day, ${hhmm(t)}';
  }

  Widget _header(ViewerItem item) => Row(
    children: [
      VCircleButton(
        icon: VIcon.back,
        size: 44,
        onTap: () => Navigator.of(context).pop(),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(item.from, style: VText.inter(15, weight: 600)),
            Text(
              '${_when(item.at)} · ${_at + 1} of ${widget.items.length}',
              style: VText.secondary,
            ),
          ],
        ),
      ),
      VCircleButton(icon: VIcon.more, size: 44, onTap: () {}),
    ],
  );

  Widget _pages() => PageView.builder(
    controller: _page,
    itemCount: widget.items.length,
    onPageChanged: (i) {
      _clock?.cancel();
      _dropVideo();
      setState(() {
        _at = i;
        _playing = false;
        _position = 0;
      });
    },
    itemBuilder: (context, i) {
      final it = widget.items[i];
      return InteractiveViewer(
        maxScale: 4,
        child: Center(
          child: AspectRatio(
            aspectRatio: it.media.aspect,
            child: ArtBox(
              art: it.media.art,
              path: it.video ? null : it.media.path,
              child: it.video
                  ? Stack(
                      fit: StackFit.expand,
                      children: [
                        if (i == _at && _video?.value.isInitialized == true)
                          VideoPlayer(_video!)
                        else if (it.media.path case final path?)
                          VideoFrame(path),
                        Center(
                          child: Semantics(
                            button: true,
                            label: _playing ? 'Pause' : 'Play',
                            child: VTappable(
                              onTap: _toggle,
                              child: Opacity(
                                opacity: _playing && i == _at ? 0 : 1,
                                child: Container(
                                  width: 68,
                                  height: 68,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: VColors.black.withValues(alpha: 0.4),
                                    border: Border.all(color: VColors.white),
                                  ),
                                  child: const Center(
                                    child: VIconView(
                                      VIcon.play,
                                      size: 28,
                                      color: VColors.white,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    )
                  : null,
            ),
          ),
        ),
      );
    },
  );

  Widget _scrubber(ViewerItem item) {
    final total = item.media.duration ?? Duration.zero;
    return Row(
      children: [
        Text(mss(total * _position), style: VText.doto(13)),
        const SizedBox(width: 10),
        Expanded(child: VBar(value: _position, height: 4)),
        const SizedBox(width: 10),
        Text(mss(total), style: VText.doto(13)),
      ],
    );
  }

  Widget _actions(ViewerItem item) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceAround,
    children: [
      _Action(VIcon.reply, 'Reply', () {
        Navigator.of(context).pop();
        widget.onReply?.call(item);
      }),
      _Action(VIcon.download, 'Save', () => HapticFeedback.selectionClick()),
      _Action(VIcon.share, 'Share', () => HapticFeedback.selectionClick()),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final paper = VInk.surfaceOf(context);
    final item = widget.items[_at];
    // In landscape the picture takes the screen and the rest sits beside
    // it.
    final wide = isLandscape(context);
    return AllowRotation(
      child: ColoredBox(
        color: paper,
        child: SafeArea(
          child: wide
              ? Row(
                  children: [
                    Expanded(child: _pages()),
                    SizedBox(
                      width: 280,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 12, 16, 12),
                        child: Column(
                          children: [
                            _header(item),
                            const Spacer(),
                            if (item.video) ...[
                              _scrubber(item),
                              const SizedBox(height: 18),
                            ],
                            _actions(item),
                          ],
                        ),
                      ),
                    ),
                  ],
                )
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                      child: _header(item),
                    ),
                    const SizedBox(height: 20),
                    Expanded(child: _pages()),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
                      child: Column(
                        children: [
                          if (item.video) ...[
                            _scrubber(item),
                            const SizedBox(height: 18),
                          ],
                          _actions(item),
                        ],
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _Action extends StatelessWidget {
  const _Action(this.icon, this.label, this.onTap);

  final VIcon icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: label,
    child: VTappable(
      onTap: onTap,
      child: Column(
        children: [
          VCircleButton(icon: icon, size: 44),
          const SizedBox(height: 6),
          Text(label, style: VText.inter(12, weight: 500)),
        ],
      ),
    ),
  );
}
