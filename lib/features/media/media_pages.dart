import 'dart:async';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../../core/icons/v_icons.dart';
import '../../core/theme/v_colors.dart';
import '../../core/theme/v_palette.dart';
import '../../core/theme/v_text.dart';
import '../../core/widgets/v_buttons.dart';
import '../../core/widgets/v_controls.dart';
import '../../core/widgets/v_glass.dart';
import '../../core/widgets/v_ink.dart';
import '../../core/widgets/v_page.dart';
import '../../data/models.dart';
import '../../data/providers.dart' show MediaSource;
import '../../mock/mock_data.dart';
import '../common/art.dart';
import '../common/video_frame.dart';
import '../common/overlay.dart';
import '../common/parts.dart';
import 'attach_sheet.dart';

/// Photos picked and their caption, ready to send.
/// What the preview hands back: the media, its caption, and whether to
/// send the photos as they are (HD) rather than resized.
typedef PickedMedia = ({List<Media> media, String caption, bool hd});

/// The gallery (C18): pick several, numbered in order, then Send n opens
/// the preview (C19). Returns what to send.
Future<PickedMedia?> pickFromGallery(
  BuildContext context, {
  String partner = '',
  MediaSource? source,
}) async {
  final picked = source != null
      ? await source.gallery()
      : await pushPage<List<Media>>(context, (_) => const GalleryPage());
  if (picked == null || picked.isEmpty || !context.mounted) return null;
  return pushPage<PickedMedia>(
    context,
    (_) => MediaPreview(media: picked, partner: partner),
  );
}

/// The camera (C20), then the preview (C19).
Future<PickedMedia?> takePhoto(
  BuildContext context, {
  String partner = '',
  MediaSource? source,
}) async {
  final shot = source != null
      ? (await source.camera())
      : await pushPage<Media>(context, (_) => const CameraPage());
  if (shot == null || !context.mounted) return null;
  return pushPage<PickedMedia>(
    context,
    (_) => MediaPreview(media: [shot], partner: partner),
  );
}

enum _Filter { all, photos, videos }

class GalleryPage extends StatefulWidget {
  const GalleryPage({super.key, this.addTo = 0});

  /// How many are already in the composer's strip (to number after them).
  final int addTo;

  @override
  State<GalleryPage> createState() => _GalleryPageState();
}

class _GalleryPageState extends State<GalleryPage> {
  final _all = MockData.gallery();
  final _picked = <Media>[];
  var _filter = _Filter.all;

  @override
  Widget build(BuildContext context) {
    final shown = _all
        .where(
          (m) => switch (_filter) {
            _Filter.all => true,
            _Filter.photos => m.duration == null,
            _Filter.videos => m.duration != null,
          },
        )
        .toList();
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Stack(
      fit: StackFit.expand,
      children: [
        const VVeil(),
        CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          VLink(
                            '‹ Chat',
                            onTap: () => Navigator.of(context).pop(),
                            style: VText.inter(14),
                          ),
                          const Spacer(),
                          Text(
                            'Recents ⌄',
                            style: VText.inter(13, weight: 500),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Padding(
                        padding: const EdgeInsets.only(left: 4),
                        child: Text('Gallery', style: VText.title),
                      ),
                      const SizedBox(height: 14),
                      VSegmented<_Filter>(
                        segments: const {
                          _Filter.all: 'All',
                          _Filter.photos: 'Photos',
                          _Filter.videos: 'Videos',
                        },
                        value: _filter,
                        onChanged: (f) => setState(() => _filter = f),
                      ),
                      const SizedBox(height: 14),
                    ],
                  ),
                ),
              ),
            ),
            SliverPadding(
              padding: EdgeInsets.fromLTRB(4, 0, 4, bottom + 100),
              sliver: SliverGrid.count(
                crossAxisCount: 3,
                mainAxisSpacing: 4,
                crossAxisSpacing: 4,
                children: [
                  for (final m in shown)
                    Semantics(
                      button: true,
                      selected: _picked.contains(m),
                      label: m.duration == null ? 'Photo' : 'Video',
                      child: VTappable(
                        haptic: false,
                        onTap: () {
                          HapticFeedback.selectionClick();
                          setState(
                            () => _picked.contains(m)
                                ? _picked.remove(m)
                                : _picked.add(m),
                          );
                        },
                        child: ArtBox(
                          art: m.art,
                          radius: BorderRadius.circular(6),
                          child: OnMedia(
                            child: Stack(
                              children: [
                                if (_picked.contains(m))
                                  Positioned.fill(
                                    child: Container(
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(
                                          color: VColors.white,
                                          width: 2,
                                        ),
                                      ),
                                    ),
                                  ),
                                Align(
                                  alignment: Alignment.topRight,
                                  child: PickMark(
                                    _picked.contains(m)
                                        ? widget.addTo + _picked.indexOf(m) + 1
                                        : 0,
                                  ),
                                ),
                                if (m.duration != null)
                                  Positioned(
                                    left: 6,
                                    bottom: 5,
                                    child: Text(
                                      mss(m.duration!),
                                      style: VText.doto(12),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
        Positioned(
          left: 16,
          right: 16,
          bottom: bottom + 24,
          child: VButton.primary(
            _picked.isEmpty ? 'Pick photos' : 'Send ${_picked.length}',
            enabled: _picked.isNotEmpty,
            onPressed: () => Navigator.of(context).pop(List.of(_picked)),
          ),
        ),
      ],
    );
  }
}

/// Before sending (C19): the photos one at a time, remove, caption, Send.
class MediaPreview extends StatefulWidget {
  const MediaPreview({super.key, required this.media, this.partner = ''});

  final List<Media> media;
  final String partner;

  @override
  State<MediaPreview> createState() => _MediaPreviewState();
}

class _MediaPreviewState extends State<MediaPreview> {
  late final _media = List.of(widget.media);

  /// Send photos as they are, not resized.
  bool _hd = false;
  final _page = PageController();
  final _caption = TextEditingController();
  var _at = 0;

  @override
  void dispose() {
    _page.dispose();
    _caption.dispose();
    super.dispose();
  }

  void _remove() {
    HapticFeedback.lightImpact();
    if (_media.length == 1) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _media.removeAt(_at);
      _at = _at.clamp(0, _media.length - 1);
    });
  }

  @override
  Widget build(BuildContext context) {
    final ink = VInk.of(context);
    return Stack(
      fit: StackFit.expand,
      children: [
        const VVeil(),
        SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Row(
                  children: [
                    VCircleButton(
                      icon: VIcon.close,
                      size: 44,
                      onTap: () => Navigator.of(context).pop(),
                    ),
                    const Spacer(),
                    Text(
                      '${_at + 1} / ${_media.length}',
                      style: VText.doto(16),
                    ),
                    const Spacer(),
                    VCircleButton(icon: VIcon.trash, size: 44, onTap: _remove),
                  ],
                ),
              ),
              const SizedBox(height: 22),
              Expanded(
                child: PageView.builder(
                  controller: _page,
                  itemCount: _media.length,
                  onPageChanged: (i) => setState(() => _at = i),
                  itemBuilder: (context, i) => Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: _media[i].duration != null
                        ? _PreviewVideo(_media[i], active: i == _at)
                        : ArtBox(
                            art: _media[i].art,
                            path: _media[i].path,
                            radius: BorderRadius.circular(20),
                          ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                height: 52,
                child: Center(
                  child: ListView.separated(
                    shrinkWrap: true,
                    scrollDirection: Axis.horizontal,
                    itemCount: _media.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 8),
                    itemBuilder: (context, i) => VTappable(
                      onTap: () => _page.animateToPage(
                        i,
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeOut,
                      ),
                      child: Container(
                        margin: const EdgeInsets.all(2),
                        decoration: i == _at
                            ? BoxDecoration(
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: ink, width: 2),
                              )
                            : null,
                        padding: const EdgeInsets.all(2),
                        child: ArtBox(
                          art: _media[i].art,
                          // A video's file isn't an image: its first frame
                          // goes on top instead.
                          path: _media[i].duration == null
                              ? _media[i].path
                              : null,
                          width: 44,
                          height: 44,
                          radius: BorderRadius.circular(10),
                          child: _media[i].duration != null
                              ? ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: _media[i].path == null
                                      ? null
                                      : VideoFrame(_media[i].path!),
                                )
                              : null,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                child: Row(
                  children: [
                    Expanded(
                      child: VGlass(
                        radius: 22,
                        tint: VPalette.of(context).glassCard,
                        blur: 16,
                        child: _CaptionField(controller: _caption),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Semantics(
                      button: true,
                      toggled: _hd,
                      label: 'HD',
                      child: VPill(
                        'HD',
                        fill: _hd ? VFill.filled : VFill.outline,
                        onTap: () {
                          HapticFeedback.selectionClick();
                          setState(() => _hd = !_hd);
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Semantics(
                      button: true,
                      label: widget.partner.isEmpty
                          ? 'Send'
                          : 'Send to ${widget.partner}',
                      child: VCircleButton(
                        icon: VIcon.send,
                        size: 44,
                        filled: true,
                        onTap: () => Navigator.of(context).pop((
                          media: List.of(_media),
                          caption: _caption.text.trim(),
                          hd: _hd,
                        )),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CaptionField extends StatelessWidget {
  const _CaptionField({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    final ink = VInk.of(context);
    return CupertinoTextField(
      controller: controller,
      placeholder: 'Add a caption',
      placeholderStyle: VText.inter(15).copyWith(color: ink),
      style: VText.inter(15).copyWith(color: ink),
      cursorColor: ink,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(color: VColors.transparent),
    );
  }
}

/// The camera (C20): always dark, it's a viewfinder. Tap for a photo,
/// hold for video. The live view is stand-in art until the camera arrives
/// in Phase 4.
class CameraPage extends StatefulWidget {
  const CameraPage({super.key});

  @override
  State<CameraPage> createState() => _CameraPageState();
}

class _CameraPageState extends State<CameraPage> {
  var _flash = false;
  var _front = false;
  var _recording = false;

  @override
  Widget build(BuildContext context) {
    final last = MockData.gallery().first;
    return VInkScope(
      ink: VColors.white,
      child: ColoredBox(
        color: VColors.black,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ArtBox(
              art: _front ? 8 : 4,
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
            SafeArea(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: Row(
                      children: [
                        VCircleButton(
                          icon: VIcon.close,
                          size: 44,
                          onTap: () => Navigator.of(context).pop(),
                        ),
                        const Spacer(),
                        if (_recording)
                          const VPill.badge('REC')
                        else
                          const SizedBox.shrink(),
                        const Spacer(),
                        Semantics(
                          button: true,
                          label: _flash ? 'Flash on' : 'Flash off',
                          child: VCircleButton(
                            icon: VIcon.flash,
                            size: 44,
                            filled: _flash,
                            onTap: () => setState(() => _flash = !_flash),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  Text(
                    'Tap for a photo · hold for video',
                    style: VText.inter(13),
                  ),
                  const SizedBox(height: 22),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(44, 0, 44, 40),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        ArtBox(
                          art: last.art,
                          width: 48,
                          height: 48,
                          radius: BorderRadius.circular(12),
                        ),
                        Semantics(
                          button: true,
                          label: 'Shutter',
                          child: GestureDetector(
                            onTap: () {
                              HapticFeedback.mediumImpact();
                              Navigator.of(context).pop(
                                Media(
                                  id: 'cam${DateTime.now().millisecondsSinceEpoch}',
                                  art: _front ? 8 : 4,
                                  aspect: 0.75,
                                ),
                              );
                            },
                            onLongPressStart: (_) =>
                                setState(() => _recording = true),
                            onLongPressEnd: (_) {
                              setState(() => _recording = false);
                              Navigator.of(context).pop(
                                Media(
                                  id: 'vid${DateTime.now().millisecondsSinceEpoch}',
                                  art: _front ? 8 : 4,
                                  aspect: 0.75,
                                  duration: const Duration(seconds: 6),
                                ),
                              );
                            },
                            child: Container(
                              width: 80,
                              height: 80,
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: VColors.white,
                                  width: 2,
                                ),
                              ),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                decoration: BoxDecoration(
                                  color: VColors.white,
                                  borderRadius: BorderRadius.circular(
                                    _recording ? 8 : 40,
                                  ),
                                ),
                                margin: EdgeInsets.all(_recording ? 14 : 0),
                              ),
                            ),
                          ),
                        ),
                        VCircleButton(
                          icon: VIcon.swapCamera,
                          size: 44,
                          onTap: () => setState(() => _front = !_front),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}


/// A video in the preview (C19): its first frame, and tap to play it
/// through before sending. It stops when swiped away.
class _PreviewVideo extends StatefulWidget {
  const _PreviewVideo(this.media, {required this.active});

  final Media media;
  final bool active;

  @override
  State<_PreviewVideo> createState() => _PreviewVideoState();
}

class _PreviewVideoState extends State<_PreviewVideo> {
  VideoPlayerController? _c;

  @override
  void initState() {
    super.initState();
    final path = widget.media.path;
    if (path == null) return;
    final c = _c = VideoPlayerController.file(File(path));
    c.addListener(_changed);
    c.initialize().then((_) async {
      // Some decoders show nothing until asked for a frame.
      await c.seekTo(Duration.zero);
      if (mounted) setState(() {});
    }, onError: (Object _) {});
  }

  void _changed() {
    final c = _c!;
    if (!mounted) return;
    final v = c.value;
    if (v.isInitialized && !v.isPlaying && v.position >= v.duration) {
      unawaited(c.seekTo(Duration.zero));
    }
    setState(() {});
  }

  @override
  void didUpdateWidget(_PreviewVideo old) {
    super.didUpdateWidget(old);
    if (!widget.active && (_c?.value.isPlaying ?? false)) unawaited(_c!.pause());
  }

  @override
  void dispose() {
    _c?.removeListener(_changed);
    unawaited(_c?.dispose());
    super.dispose();
  }

  void _toggle() {
    final c = _c;
    if (c == null || !c.value.isInitialized) return;
    unawaited(c.value.isPlaying ? c.pause() : c.play());
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    final ready = c != null && c.value.isInitialized;
    final playing = ready && c.value.isPlaying;
    final shown = ready ? c.value.position : Duration.zero;
    final total = ready ? c.value.duration : widget.media.duration!;
    return VTappable(
      onTap: _toggle,
      haptic: false,
      child: ArtBox(
        art: widget.media.art,
        radius: BorderRadius.circular(20),
        child: OnMedia(
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (ready)
                ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: FittedBox(
                    fit: BoxFit.contain,
                    child: SizedBox(
                      width: c.value.size.width,
                      height: c.value.size.height,
                      child: VideoPlayer(c),
                    ),
                  ),
                ),
              Center(
                child: AnimatedOpacity(
                  opacity: playing ? 0 : 1,
                  duration: const Duration(milliseconds: 200),
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
              Positioned(
                left: 14,
                bottom: 12,
                child: Text(
                  playing ? '${mss(shown)} / ${mss(total)}' : mss(total),
                  style: VText.doto(13),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
