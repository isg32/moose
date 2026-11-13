import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/icons/v_icons.dart';
import '../../core/theme/v_colors.dart';
import '../../core/theme/v_text.dart';
import '../../core/widgets/v_buttons.dart';
import '../../core/widgets/v_ink.dart';
import '../../core/widgets/v_marquee.dart';
import '../../core/widgets/v_progress.dart';
import '../../core/widgets/v_surface.dart';
import '../../data/models.dart';
import '../../data/providers.dart' show Playback, playbackProvider;
import '../common/art.dart';
import '../common/video_frame.dart';
import '../common/parts.dart';
import '../common/sticker_view.dart';
import '../moments/moment_burst.dart';

/// What a bubble can ask the chat to do.
class BubbleActions {
  const BubbleActions({
    this.onLongPress,
    this.onReply,
    this.onRetry,
    this.onOpenMedia,
    this.onPlayVoice,
    this.onPlaySong,
    this.onCallBack,
    this.onReact,
  });

  final void Function(Message m)? onLongPress;
  final void Function(Message m)? onReply;
  final void Function(Message m)? onRetry;
  final void Function(Message m, int index)? onOpenMedia;
  final void Function(Message m)? onPlayVoice;
  final void Function(Message m)? onPlaySong;
  final void Function(Message m)? onCallBack;
  final void Function(Message m, String emoji)? onReact;
}

/// One message as the chat draws it (B1–B12).
class MessageView extends StatelessWidget {
  const MessageView({
    super.key,
    required this.message,
    required this.partner,
    this.actions = const BubbleActions(),
    this.playingId,
  });

  final Message message;
  final String partner;
  final BubbleActions actions;

  /// The voice note or song playing now, if any.
  final String? playingId;

  @override
  Widget build(BuildContext context) {
    final m = message;
    if (m.centred) return Center(child: _Centred(m, partner, actions));
    final width = MediaQuery.sizeOf(context).width;
    final content = switch (m.body) {
      StickerBody(:final sticker) => _StickerMessage(m, sticker),
      RoundVideoBody(:final video, :final playing) => _RoundVideo(
        m,
        video,
        playing: playing,
        onTap: () => actions.onOpenMedia?.call(m, 0),
      ),
      TextBody(:final text) when (m.body as TextBody).emojiOnly => _EmojiOnly(
        m,
        text,
      ),
      _ => _Bubble(m, partner, actions, playing: playingId == m.id),
    };
    final failed = m.fromMe && m.delivery == Delivery.failed;
    return _SwipeToReply(
      onReply: actions.onReply == null ? null : () => actions.onReply!(m),
      child: GestureDetector(
        onLongPress: actions.onLongPress == null
            ? null
            : () {
                HapticFeedback.mediumImpact();
                actions.onLongPress!(m);
              },
        child: Align(
          alignment: m.fromMe ? Alignment.centerRight : Alignment.centerLeft,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: width * 0.78),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (failed) ...[
                  VPill(
                    'Retry',
                    leading: const VIconView(VIcon.warning, size: 14),
                    onTap: () => actions.onRetry?.call(m),
                  ),
                  const SizedBox(width: 8),
                ],
                Flexible(
                  child: _WithReactions(
                    message: m,
                    onReact: actions.onReact,
                    child: content,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The time and, on your messages, the delivery mark.
class _Meta extends StatelessWidget {
  const _Meta(this.m, {this.onMedia = false});

  final Message m;
  final bool onMedia;

  @override
  Widget build(BuildContext context) {
    final failed = m.fromMe && m.delivery == Delivery.failed;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          failed ? 'Not sent' : hhmm(m.at),
          style: VText.inter(11, weight: 300),
        ),
        if (m.fromMe && !failed) ...[
          const SizedBox(width: 4),
          DeliveryTicks(m.delivery),
        ],
      ],
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble(this.m, this.partner, this.actions, {required this.playing});

  final Message m;
  final String partner;
  final BubbleActions actions;
  final bool playing;

  bool get _media =>
      m.body is PhotoBody || m.body is VideoBody || m.body is MemeBody;

  @override
  Widget build(BuildContext context) {
    final ink = VInk.of(context);
    final paper = VInk.surfaceOf(context);
    final out = m.fromMe;
    final failed = out && m.delivery == Delivery.failed;
    final radius = BorderRadius.only(
      topLeft: const Radius.circular(20),
      topRight: const Radius.circular(20),
      bottomLeft: Radius.circular(out ? 20 : 6),
      bottomRight: Radius.circular(out ? 6 : 20),
    );
    // Theirs look like yours (solid ink, no blur): only the side and the
    // tail corner tell them apart.
    final fg = !failed ? paper : ink;
    final body = VInkScope(
      ink: fg,
      child: Padding(
        padding: _media
            ? const EdgeInsets.all(4)
            : const EdgeInsets.fromLTRB(13, 9, 13, 8),
        child: IntrinsicWidth(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (m.reply != null)
                Padding(
                  padding: _media
                      ? const EdgeInsets.fromLTRB(4, 4, 4, 6)
                      : const EdgeInsets.only(bottom: 6),
                  child: _QuoteView(m.reply!, partner: partner, onInk: !failed),
                ),
              _content(context),
            ],
          ),
        ),
      ),
    );

    if (failed) {
      return VOutlined(radius: 20, outline: VOutline.dashed, child: body);
    }
    return DecoratedBox(
      decoration: BoxDecoration(color: ink, borderRadius: radius),
      child: body,
    );
  }

  Widget _content(BuildContext context) {
    return switch (m.body) {
      TextBody(:final text) => _TextContent(m, text),
      PhotoBody(:final photos, :final caption) => _Photos(
        m,
        photos,
        caption: caption,
        partner: partner,
        onOpen: (i) => actions.onOpenMedia?.call(m, i),
      ),
      VideoBody(:final video) => _Video(
        m,
        video,
        onOpen: () => actions.onOpenMedia?.call(m, 0),
      ),
      VoiceBody() => _Voice(
        m,
        m.body as VoiceBody,
        playing: playing,
        onPlay: () => actions.onPlayVoice?.call(m),
      ),
      MusicBody() => _Music(
        m,
        m.body as MusicBody,
        playing: playing,
        onPlay: () => actions.onPlaySong?.call(m),
      ),
      MemeBody(:final meme) => _MemeContent(m, meme),
      _ => const SizedBox.shrink(),
    };
  }
}

class _TextContent extends StatelessWidget {
  const _TextContent(this.m, this.text);

  final Message m;
  final String text;

  @override
  Widget build(BuildContext context) {
    final style = VText.inter(15, height: 1.4);
    // Words that look like links are underlined (B1).
    final spans = <InlineSpan>[];
    final words = text.split(' ');
    for (var i = 0; i < words.length; i++) {
      final w = words[i];
      final link = w.contains('.') && w.contains('/');
      spans.add(
        TextSpan(
          text: w,
          style: link
              ? const TextStyle(
                  decoration: TextDecoration.underline,
                  decorationThickness: 1,
                )
              : null,
        ),
      );
      if (i < words.length - 1) spans.add(const TextSpan(text: ' '));
    }
    // As wide as the text or the reply quote above it, whichever is wider;
    // the text starts at the left, the time sits at the right.
    return IntrinsicWidth(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text.rich(TextSpan(children: spans), style: style),
          const SizedBox(height: 3),
          Align(alignment: Alignment.centerRight, child: _Meta(m)),
        ],
      ),
    );
  }
}

class _EmojiOnly extends StatelessWidget {
  const _EmojiOnly(this.m, this.text);

  final Message m;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 4),
    child: Column(
      crossAxisAlignment: m.fromMe
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(text, style: const TextStyle(fontSize: 44, height: 1.15)),
        _Meta(m),
      ],
    ),
  );
}

/// The reply quote at the top of a bubble (B2).
class _QuoteView extends StatelessWidget {
  const _QuoteView(this.q, {required this.partner, required this.onInk});

  final Quote q;
  final String partner;

  /// Inside your ink-filled bubble: drawn on a paper card.
  final bool onInk;

  @override
  Widget build(BuildContext context) {
    final ink = VInk.of(context);
    final Widget thumb = q.art != null
        ? ArtBox(
            art: q.art!,
            width: 32,
            height: 32,
            radius: BorderRadius.circular(8),
          )
        : q.music == true
        ? const VIconView(VIcon.music, size: 18)
        : const SizedBox.shrink();
    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 2,
          height: 34,
          decoration: BoxDecoration(
            color: onInk ? VInk.surfaceOf(context) : ink,
            borderRadius: BorderRadius.circular(1),
          ),
        ),
        const SizedBox(width: 8),
        if (q.art != null || q.music == true) ...[
          thumb,
          const SizedBox(width: 8),
        ],
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                q.fromMe ? 'You' : partner,
                style: VText.inter(13, weight: 600, height: 1.3),
              ),
              Text(
                q.text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: VText.inter(13, height: 1.3),
              ),
            ],
          ),
        ),
      ],
    );
    if (onInk) {
      // A paper card inside the ink bubble, in the bubble's own ink.
      return Container(
        padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
        decoration: BoxDecoration(
          color: ink,
          borderRadius: BorderRadius.circular(12),
        ),
        child: VInkScope(ink: VInk.surfaceOf(context), child: content),
      );
    }
    return VOutlined(
      radius: 12,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
        child: content,
      ),
    );
  }
}

/// Reaction chips under a bubble (B3): yours filled.
class _WithReactions extends StatelessWidget {
  const _WithReactions({
    required this.message,
    required this.child,
    this.onReact,
  });

  final Message message;
  final Widget child;
  final void Function(Message m, String emoji)? onReact;

  @override
  Widget build(BuildContext context) {
    final rs = message.reactions;
    if (rs.isEmpty) return child;
    return Column(
      crossAxisAlignment: message.fromMe
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        child,
        Transform.translate(
          offset: const Offset(0, -7),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Wrap(
              spacing: 4,
              children: [
                for (final r in rs)
                  VPill(
                    r.count > 1 ? '${r.emoji} ${r.count}' : r.emoji,
                    fill: r.mine ? VFill.filled : VFill.outline,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    onTap: onReact == null
                        ? null
                        : () => onReact!(message, r.emoji),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// A photo or a grid of up to four (B4), with how it's arriving.
class _Photos extends StatelessWidget {
  const _Photos(
    this.m,
    this.photos, {
    required this.partner,
    required this.onOpen,
    this.caption,
  });

  final Message m;
  final List<Media> photos;
  final String partner;
  final String? caption;
  final void Function(int i) onOpen;

  @override
  Widget build(BuildContext context) {
    const w = 252.0;
    final first = photos.first;
    final Widget grid;
    if (photos.length == 1) {
      grid = GestureDetector(
        onTap: () => onOpen(0),
        child: SizedBox(
          width: w,
          height: w / first.aspect,
          child: _MediaTile(
            first,
            partner: partner,
            radius: BorderRadius.circular(16),
            child: first.transfer == Transfer.done
                ? Align(
                    alignment: Alignment.bottomRight,
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: OnMedia(child: _Meta(m, onMedia: true)),
                    ),
                  )
                : null,
          ),
        ),
      );
    } else {
      final shown = photos.take(4).toList();
      grid = SizedBox(
        width: w,
        child: Wrap(
          spacing: 3,
          runSpacing: 3,
          children: [
            for (var i = 0; i < shown.length; i++)
              GestureDetector(
                onTap: () => onOpen(i),
                child: SizedBox(
                  width: (w - 3) / 2,
                  height: 110,
                  child: _MediaTile(
                    shown[i],
                    partner: partner,
                    radius: BorderRadius.circular(i == 0 || i == 1 ? 14 : 4),
                    child: i == 3 && photos.length > 4
                        ? Center(
                            child: OnMedia(
                              child: Text(
                                '+${photos.length - 4}',
                                style: VText.doto(28, weight: 900),
                              ),
                            ),
                          )
                        : null,
                  ),
                ),
              ),
          ],
        ),
      );
    }
    final cloud = first.transfer == Transfer.cloudDownloading;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        grid,
        if (caption != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(9, 6, 9, 2),
            child: Text(caption!, style: VText.inter(15, height: 1.4)),
          ),
        if (cloud)
          SizedBox(
            width: w,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 2),
              child: Text(
                "$partner's phone is offline, so this came the long way.",
                style: VText.inter(11, weight: 300),
              ),
            ),
          ),
        if (photos.length > 1 || caption != null || cloud)
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 2),
            child: Align(alignment: Alignment.centerRight, child: _Meta(m)),
          ),
      ],
    );
  }
}

/// Media art with its transfer state on top (B4): coming direct, waiting
/// in the cloud, downloading, or waiting for the partner's phone.
class _MediaTile extends StatelessWidget {
  const _MediaTile(
    this.media, {
    required this.partner,
    required this.radius,
    this.child,
  });

  final Media media;
  final String partner;
  final BorderRadius radius;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    if (media.transfer == Transfer.waiting) {
      return VOutlined(
        radius: 16,
        outline: VOutline.dashed,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              const VIconView(VIcon.warning, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  "$partner's phone is offline.\nIt'll arrive when it's back.",
                  style: VText.inter(13, height: 1.3),
                ),
              ),
            ],
          ),
        ),
      );
    }
    final mb = (media.bytes / 1e6).toStringAsFixed(1);
    final got = (media.bytes * media.progress / 1e6).toStringAsFixed(1);
    final Widget? state = switch (media.transfer) {
      Transfer.direct => _progress(media.progress, "from $partner's phone"),
      Transfer.cloudDownloading => _progress(
        media.progress,
        'From the cloud · $got of $mb MB',
      ),
      Transfer.cloud => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const VIconView(VIcon.download, size: 24),
          const SizedBox(height: 6),
          Text('$mb MB · cloud', style: VText.inter(11, weight: 500)),
        ],
      ),
      _ => null,
    };
    return ArtBox(
      art: media.art,
      path: media.path,
      radius: radius,
      child: OnMedia(
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (state != null) Center(child: state),
            ?child,
          ],
        ),
      ),
    );
  }

  Widget _progress(double p, String label) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      VRing(value: p, size: 44, strokeWidth: 4, color: VColors.white),
      const SizedBox(height: 6),
      Text(label, style: VText.inter(11, weight: 500)),
    ],
  );
}

class _Video extends StatelessWidget {
  const _Video(this.m, this.video, {required this.onOpen});

  final Message m;
  final Media video;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onOpen,
    child: SizedBox(
      width: 252,
      height: 252 / video.aspect,
      child: ArtBox(
        art: video.art,
        radius: BorderRadius.circular(16),
        child: OnMedia(
          child: Stack(
            children: [
              if (video.path case final path?)
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: VideoFrame(path),
                ),
              Center(
                child: Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: VColors.black.withValues(alpha: 0.4),
                    border: Border.all(color: VColors.white),
                  ),
                  child: const Center(
                    child: VIconView(
                      VIcon.play,
                      size: 24,
                      color: VColors.white,
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 10,
                bottom: 8,
                child: Text(
                  mss(video.duration ?? Duration.zero),
                  style: VText.doto(13),
                ),
              ),
              Positioned(right: 8, bottom: 8, child: _Meta(m, onMedia: true)),
            ],
          ),
        ),
      ),
    ),
  );
}

/// A round video note (B6): a circle, no bubble, with its progress ring
/// while playing, or muted autoplay.
class _RoundVideo extends StatefulWidget {
  const _RoundVideo(
    this.m,
    this.video, {
    required this.playing,
    required this.onTap,
  });

  final Message m;
  final Media video;
  final bool playing;
  final VoidCallback onTap;

  @override
  State<_RoundVideo> createState() => _RoundVideoState();
}

class _RoundVideoState extends State<_RoundVideo> {
  /// How far through the video is, for the ring.
  final _progress = ValueNotifier<double>(0);

  @override
  void dispose() {
    _progress.dispose();
    super.dispose();
  }

  Message get m => widget.m;
  Media get video => widget.video;
  bool get playing => widget.playing;
  VoidCallback get onTap => widget.onTap;

  @override
  Widget build(BuildContext context) {
    final size = playing ? 180.0 : 150.0;
    return GestureDetector(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: m.fromMe
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox.square(
            dimension: size + 8,
            child: Stack(
              alignment: Alignment.center,
              children: [
                ClipOval(
                  child: video.path == null
                      ? ArtBox(art: video.art, width: size, height: size)
                      : SizedBox.square(
                          dimension: size,
                          child: RoundPlayer(
                            video.path!,
                            playing: playing,
                            progress: _progress,
                          ),
                        ),
                ),
                if (!playing)
                  VRing(value: 0, size: size + 8, strokeWidth: 4)
                else if (video.path != null)
                  ValueListenableBuilder(
                    valueListenable: _progress,
                    builder: (context, p, _) =>
                        VRing(value: p, size: size + 8, strokeWidth: 4),
                  )
                else
                  // The mock has no player: the ring runs on a clock.
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: 1),
                    duration: video.duration ?? const Duration(seconds: 10),
                    builder: (context, p, _) =>
                        VRing(value: p, size: size + 8, strokeWidth: 4),
                  ),
                if (!playing)
                  const OnMedia(
                    child: VIconView(
                      VIcon.mute,
                      size: 22,
                      color: VColors.white,
                    ),
                  ),
                Positioned(
                  bottom: 14,
                  child: OnMedia(
                    child: Text(
                      mss(video.duration ?? Duration.zero),
                      style: VText.doto(13),
                    ),
                  ),
                ),
              ],
            ),
          ),
          _Meta(m),
        ],
      ),
    );
  }
}

class _Voice extends StatelessWidget {
  const _Voice(this.m, this.v, {required this.playing, required this.onPlay});

  final Message m;
  final VoiceBody v;
  final bool playing;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 252,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              VCircleButton(
                icon: playing ? VIcon.pause : VIcon.play,
                size: 36,
                onTap: onPlay,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _Progress(
                  m.id,
                  playing: playing,
                  builder: (p) => FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: WaveBars(v.wave, played: _share(p, v.length)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  // Counts up while it plays.
                  _Progress(
                    m.id,
                    playing: playing,
                    builder: (p) => Text(
                      mss(p == null ? v.length : p.elapsed),
                      style: VText.doto(13),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Opacity(
                    opacity: v.played || m.fromMe ? 0 : 1,
                    child: Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: VInk.of(context),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 2),
          _Meta(m),
        ],
      ),
    );
  }
}

/// A 15 s song clip (B8): loading, playing (the bar and time follow the
/// clip, a long title scrolls), or not playable now.
class _Music extends StatelessWidget {
  const _Music(this.m, this.b, {required this.playing, required this.onPlay});

  final Message m;
  final MusicBody b;
  final bool playing;
  final VoidCallback onPlay;

  static const _clip = Duration(seconds: 15);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 262,
      child: _Progress(
        m.id,
        playing: playing,
        builder: (p) {
          final loading = p?.loading ?? false;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  ArtBox(
                    art: b.song.art,
                    url: b.song.thumb,
                    width: 48,
                    height: 48,
                    radius: BorderRadius.circular(12),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        VMarquee(
                          b.song.title,
                          style: VText.inter(14, weight: 600),
                          running: playing,
                        ),
                        VMarquee(
                          b.song.artist,
                          style: VText.inter(12, weight: 300),
                          running: playing,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Opacity(
                    opacity: b.unavailable ? 0.35 : 1,
                    child: SizedBox.square(
                      dimension: 36,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          VCircleButton(
                            icon: b.unavailable
                                ? VIcon.warning
                                : playing
                                ? VIcon.pause
                                : VIcon.play,
                            size: 36,
                            onTap: b.unavailable ? null : onPlay,
                          ),
                          // Finding and loading the song: round the button.
                          if (loading)
                            const IgnorePointer(
                              child: VSpinner(size: 36, strokeWidth: 2),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              VBar(value: _share(p, _clip), height: 4),
              const SizedBox(height: 6),
              Row(
                children: [
                  Text(
                    '${mss(b.start)} – ${mss(b.end)}',
                    style: VText.inter(11, weight: 300),
                  ),
                  const Spacer(),
                  Text(
                    b.unavailable
                        ? "Can't play right now"
                        : loading
                        ? 'Loading…'
                        : p != null
                        ? 'Playing · ${mss(p.elapsed)}'
                        : '15 s',
                    style: VText.inter(11, weight: 300),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Align(alignment: Alignment.centerRight, child: _Meta(m)),
            ],
          );
        },
      ),
    );
  }
}

/// How far through [length] playback is (0 when it isn't playing).
double _share(Playback? p, Duration length) =>
    p == null || length == Duration.zero
    ? 0
    : (p.elapsed.inMilliseconds / length.inMilliseconds).clamp(0.0, 1.0);

/// Rebuilds [builder] with the chat's playback while [id] is the one
/// playing (null otherwise), so only the playing bubble redraws as it goes.
class _Progress extends StatelessWidget {
  const _Progress(this.id, {required this.playing, required this.builder});

  final String id;
  final bool playing;
  final Widget Function(Playback? p) builder;

  @override
  Widget build(BuildContext context) {
    if (!playing) return builder(null);
    return Consumer(
      builder: (context, ref, _) {
        final p = ref.watch(playbackProvider);
        return builder(p?.id == id ? p : null);
      },
    );
  }
}

class _MemeContent extends StatelessWidget {
  const _MemeContent(this.m, this.meme);

  final Message m;
  final Meme meme;

  @override
  Widget build(BuildContext context) {
    const w = 190.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: w,
          height: w / meme.aspect,
          child: ArtBox(
            art: meme.art,
            url: meme.url,
            radius: BorderRadius.circular(16),
            child: OnMedia(
              child: Stack(
                children: [
                  Positioned(
                    left: 8,
                    top: 8,
                    child: VOutlined(
                      radius: 6,
                      color: VColors.white,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 1,
                        ),
                        child: Text(
                          meme.tag,
                          style: VText.inter(10, weight: 600),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 2),
          child: SizedBox(
            width: w - 16,
            child: Row(
              children: [
                Text(meme.credit, style: VText.inter(11, weight: 300)),
                const Spacer(),
                _Meta(m),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// A sticker: no bubble, tilted, with its time in a small glass chip (S6).
class _StickerMessage extends StatelessWidget {
  const _StickerMessage(this.m, this.sticker);

  final Message m;
  final Sticker sticker;

  @override
  Widget build(BuildContext context) {
    final tilt = (m.id.hashCode % 9) - 4.0;
    return Column(
      crossAxisAlignment: m.fromMe
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.all(6),
          child: StickerView(sticker, size: 130, tilt: tilt),
        ),
        // A plain chip, no blur.
        DecoratedBox(
          decoration: BoxDecoration(
            color: VInk.surfaceOf(context).withValues(alpha: 0.78),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            child: _Meta(m),
          ),
        ),
      ],
    );
  }
}

/// Moments, calls and system notes: centred pills (B10, B11, K5).
class _Centred extends StatelessWidget {
  const _Centred(this.m, this.partner, this.actions);

  final Message m;
  final String partner;
  final BubbleActions actions;

  @override
  Widget build(BuildContext context) {
    final time = hhmm(m.at);
    switch (m.body) {
      case MomentBody(:final moment):
        return SystemPill(
          tint: moment.tint,
          borderColor: moment.color,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(moment.emoji, style: const TextStyle(fontSize: 15)),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  '${moment.row(fromMe: m.fromMe, partner: partner)} · $time',
                  style: VText.inter(13, weight: 500),
                ),
              ),
            ],
          ),
        );
      case CallBody(:final video, :final outcome, :final length):
        final icon = video ? VIcon.video : VIcon.phone;
        final kind = video ? 'video call' : 'voice call';
        return switch (outcome) {
          CallOutcome.answered => SystemPill(
            radius: 16,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                VIconView(icon, size: 16),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    '${video ? 'Video' : 'Voice'} call · ${length.inMinutes} min · $time',
                  ),
                ),
              ],
            ),
          ),
          CallOutcome.missed => SystemPill(
            dashed: true,
            radius: 16,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                VIconView(icon, size: 16),
                const SizedBox(width: 8),
                Flexible(child: Text('Missed $kind · $time')),
                const SizedBox(width: 8),
                VPill(
                  'Call back',
                  fill: VFill.filled,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  style: VText.inter(11, weight: 600),
                  onTap: () => actions.onCallBack?.call(m),
                ),
              ],
            ),
          ),
          CallOutcome.noAnswer => SystemPill(
            radius: 16,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 290),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      VIconView(icon, size: 16),
                      const SizedBox(width: 8),
                      Flexible(child: Text('You called · no answer · $time')),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "$partner's Moose was closed. She'll see a missed call at "
                    'its next check.',
                    style: VText.secondary,
                  ),
                ],
              ),
            ),
          ),
        };
      case SystemBody(:final kind, :final text):
        return SystemPill(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (kind == SystemKind.doodle) ...[
                const VIconView(VIcon.doodle, size: 16),
                const SizedBox(width: 6),
              ],
              Flexible(child: Text(text, textAlign: TextAlign.center)),
            ],
          ),
        );
      default:
        return const SizedBox.shrink();
    }
  }
}

/// Drag a bubble right to reply (B12): the reply mark fills in, and a light
/// tick of haptics marks the point where letting go replies.
class _SwipeToReply extends StatefulWidget {
  const _SwipeToReply({required this.child, this.onReply});

  final Widget child;
  final VoidCallback? onReply;

  @override
  State<_SwipeToReply> createState() => _SwipeToReplyState();
}

class _SwipeToReplyState extends State<_SwipeToReply> {
  static const _reach = 60.0;
  double _dx = 0;
  bool _armed = false;

  @override
  Widget build(BuildContext context) {
    if (widget.onReply == null) return widget.child;
    final p = (_dx / _reach).clamp(0.0, 1.0);
    return GestureDetector(
      onHorizontalDragUpdate: (d) {
        setState(() => _dx = (_dx + d.delta.dx).clamp(0.0, _reach * 1.3));
        final armed = _dx >= _reach;
        if (armed && !_armed) HapticFeedback.lightImpact();
        _armed = armed;
      },
      onHorizontalDragEnd: (_) {
        if (_armed) widget.onReply!();
        setState(() {
          _dx = 0;
          _armed = false;
        });
      },
      child: Stack(
        alignment: Alignment.centerLeft,
        children: [
          Opacity(
            opacity: p,
            child: Padding(
              padding: const EdgeInsets.only(left: 2),
              child: VCircleButton(icon: VIcon.reply, size: 34, filled: p >= 1),
            ),
          ),
          Transform.translate(offset: Offset(_dx, 0), child: widget.child),
        ],
      ),
    );
  }
}
