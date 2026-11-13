import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/icons/v_icons.dart';
import '../../core/theme/v_text.dart';
import '../../core/widgets/v_buttons.dart';
import '../../core/widgets/v_ink.dart';
import '../../core/widgets/v_marquee.dart';
import '../../core/widgets/v_page.dart';
import '../../core/widgets/v_progress.dart';
import '../../core/widgets/v_surface.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../common/art.dart';
import '../common/overlay.dart';
import '../common/parts.dart';
import '../stickers/tray.dart';

/// Music: search YouTube (C27), then pick 15 seconds (C28). Returns the
/// clip to send.
Future<Body?> pickSong(BuildContext context) =>
    pushPage<Body>(context, (_) => const MusicSearchPage());

class MusicSearchPage extends ConsumerStatefulWidget {
  const MusicSearchPage({super.key});

  @override
  ConsumerState<MusicSearchPage> createState() => _MusicSearchPageState();
}

class _MusicSearchPageState extends ConsumerState<MusicSearchPage> {
  final _search = TextEditingController();
  var _query = '';
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _changed(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (mounted) setState(() => _query = q);
    });
  }

  Future<void> _open(Song s) async {
    final clip = await pushPage<Body>(context, (_) => RangePickerPage(song: s));
    if (clip != null && mounted) Navigator.of(context).pop(clip);
  }

  @override
  Widget build(BuildContext context) {
    final results = _query.trim().isEmpty
        ? null
        : ref.watch(songSearchProvider(_query));
    return Stack(
      fit: StackFit.expand,
      children: [
        const VVeil(),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: VLink(
                    '‹ Chat',
                    style: VText.inter(14),
                    onTap: () => Navigator.of(context).pop(),
                  ),
                ),
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: Text('Music', style: VText.title),
                ),
                const SizedBox(height: 14),
                SearchPill(
                  controller: _search,
                  placeholder: 'Search songs',
                  autofocus: true,
                  onChanged: _changed,
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: results == null
                      ? Align(
                          alignment: Alignment.topLeft,
                          child: Padding(
                            padding: const EdgeInsets.only(left: 4),
                            child: Text(
                              'Find a song, then pick 15 seconds of it.',
                              style: VText.secondary,
                            ),
                          ),
                        )
                      : results.when(
                          loading: () => ListView(
                            padding:
                                EdgeInsets.zero, // not the status bar's inset
                            children: const [
                              _SkeletonRow(),
                              _SkeletonRow(),
                              _SkeletonRow(),
                            ],
                          ),
                          error: (_, _) => const Align(
                            alignment: Alignment.topCenter,
                            child: VCard(
                              child: InlineError(
                                "YouTube isn't answering. Try again.",
                              ),
                            ),
                          ),
                          data: (songs) => songs.isEmpty
                              ? Align(
                                  alignment: Alignment.topCenter,
                                  child: EmptyCard(
                                    title: 'Nothing for "$_query"',
                                    body: 'Check the spelling, or try fewer words.',
                                  ),
                                )
                              : ListView(
                                  padding: EdgeInsets.zero,
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                        4,
                                        0,
                                        0,
                                        6,
                                      ),
                                      child: Text(
                                        'RESULTS',
                                        style: VText.eyebrow,
                                      ),
                                    ),
                                    for (final (i, s) in songs.indexed) ...[
                                      if (i > 0) const VDivider(),
                                      _SongRow(s, onTap: () => _open(s)),
                                    ],
                                    const SizedBox(height: 10),
                                    Padding(
                                      padding: const EdgeInsets.only(left: 4),
                                      child: Text(
                                        "From YouTube. You'll pick 15 seconds next.",
                                        style: VText.secondary,
                                      ),
                                    ),
                                  ],
                                ),
                        ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _SongRow extends StatelessWidget {
  const _SongRow(this.s, {required this.onTap});

  final Song s;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: '${s.title} by ${s.artist}',
    child: VTappable(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            ArtBox(
              art: s.art,
              url: s.thumb,
              width: 52,
              height: 52,
              radius: BorderRadius.circular(12),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: VText.inter(15, weight: 500),
                  ),
                  Text(s.artist, style: VText.secondary),
                ],
              ),
            ),
            Text(mss(s.length), style: VText.doto(14)),
          ],
        ),
      ),
    ),
  );
}

class _SkeletonRow extends StatelessWidget {
  const _SkeletonRow();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(vertical: 10),
    child: Row(
      children: [
        SizedBox.square(
          dimension: 52,
          child: VOutlined(
            radius: 12,
            outline: VOutline.dashed,
            child: SizedBox.expand(),
          ),
        ),
        SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FractionallySizedBox(
                widthFactor: 0.7,
                child: SizedBox(
                  height: 10,
                  child: VOutlined(
                    radius: 5,
                    outline: VOutline.dashed,
                    child: SizedBox.expand(),
                  ),
                ),
              ),
              SizedBox(height: 6),
              FractionallySizedBox(
                widthFactor: 0.4,
                child: SizedBox(
                  height: 10,
                  child: VOutlined(
                    radius: 5,
                    outline: VOutline.dashed,
                    child: SizedBox.expand(),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

/// C28: drag the waveform under a 15 s window, preview, send.
class RangePickerPage extends ConsumerStatefulWidget {
  const RangePickerPage({super.key, required this.song});

  final Song song;

  @override
  ConsumerState<RangePickerPage> createState() => _RangePickerPageState();
}

class _RangePickerPageState extends ConsumerState<RangePickerPage> {
  static const _clip = Duration(seconds: 15);

  /// Pixels per second of song.
  static const _pps = 13.0;

  late final _scroll = ScrollController(initialScrollOffset: 41 * _pps);
  Duration _start = const Duration(seconds: 41);
  bool _playing = false;

  /// Finding and loading the song before any sound.
  bool _loading = false;

  /// How far into the clip the preview is.
  Duration _elapsed = Duration.zero;
  Timer? _stop;

  late final List<double> _wave = () {
    final r = math.Random(widget.song.videoId.hashCode);
    final secs = widget.song.length.inSeconds;
    return [
      for (var i = 0; i < secs; i++)
        0.15 +
            0.85 * (0.5 + 0.5 * math.sin(i / 7)) * (0.4 + 0.6 * r.nextDouble()),
    ];
  }();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      final last = math.max(0, widget.song.length.inSeconds - _clip.inSeconds);
      final s = (_scroll.offset / _pps).round().clamp(0, last).toInt();
      if (s != _start.inSeconds) {
        HapticFeedback.selectionClick();
        // A new start: the preview playing the old one stops.
        if (_playing) _preview();
        setState(() => _start = Duration(seconds: s));
      }
    });
  }

  @override
  void dispose() {
    _stop?.cancel();
    if (_playing) unawaited(_player?.stop());
    _scroll.dispose();
    super.dispose();
  }

  late final SongPlayer? _player = ref.read(songPlayerProvider);

  void _preview() {
    _stop?.cancel();
    final player = _player;
    final on = !_playing;
    setState(() {
      _playing = on;
      _loading = on;
      _elapsed = Duration.zero;
    });
    void done() {
      _stop?.cancel();
      if (mounted) {
        setState(() {
          _playing = false;
          _loading = false;
          _elapsed = Duration.zero;
        });
      }
    }

    void tick(Duration e) {
      if (mounted && _playing) {
        setState(() {
          _loading = false;
          _elapsed = e;
        });
      }
    }

    if (player != null) {
      // The real clip, from YouTube.
      if (!on) {
        unawaited(player.stop());
        return;
      }
      unawaited(player.play(widget.song, _start, onTick: tick, onDone: done));
      return;
    }
    if (!on) return;
    // The mock: a short load, then a clock.
    _stop = Timer.periodic(const Duration(milliseconds: 100), (t) {
      final e = Duration(milliseconds: (t.tick - 8) * 100);
      if (e >= _clip) {
        done();
      } else if (!e.isNegative) {
        tick(e);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final partner = ref.watch(pairingProvider).partner.name;
    final ink = VInk.of(context);
    final width = MediaQuery.sizeOf(context).width;
    const window = 15 * _pps;
    final side = (width - window) / 2;
    return Stack(
      fit: StackFit.expand,
      children: [
        const VVeil(),
        SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: VLink(
                    '‹ Results',
                    style: VText.inter(14),
                    onTap: () => Navigator.of(context).pop(),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              ArtBox(
                art: widget.song.art,
                url: widget.song.thumb,
                width: 230,
                height: 230,
                radius: BorderRadius.circular(28),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Center(
                  child: VMarquee(
                    widget.song.title,
                    style: VText.doto(24),
                    running: true,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Center(
                  child: VMarquee(
                    widget.song.artist,
                    style: VText.inter(13, weight: 300),
                    running: true,
                  ),
                ),
              ),
              const Spacer(),
              SizedBox(
                height: 72,
                child: Stack(
                  children: [
                    ListView.builder(
                      controller: _scroll,
                      scrollDirection: Axis.horizontal,
                      padding: EdgeInsets.symmetric(horizontal: side),
                      itemCount: _wave.length,
                      itemExtent: _pps / 2,
                      itemBuilder: (context, i) {
                        final inside =
                            i >= _start.inSeconds &&
                            i < (_start + _clip).inSeconds;
                        return Center(
                          child: Container(
                            width: 3,
                            height: 8 + _wave[i] * 56,
                            decoration: BoxDecoration(
                              color: ink.withValues(alpha: inside ? 1 : 0.35),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        );
                      },
                    ),
                    Positioned(
                      left: side - 2,
                      width: window + 4,
                      top: 0,
                      bottom: 0,
                      child: const IgnorePointer(
                        child: VOutlined(
                          radius: 14,
                          width: 2,
                          child: SizedBox.expand(),
                        ),
                      ),
                    ),
                    // The playhead, crossing the window as the preview plays.
                    if (_playing && !_loading)
                      Positioned(
                        left:
                            side +
                            window *
                                (_elapsed.inMilliseconds / _clip.inMilliseconds)
                                    .clamp(0.0, 1.0) -
                            1,
                        width: 2,
                        top: 6,
                        bottom: 6,
                        child: IgnorePointer(child: ColoredBox(color: ink)),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: window + 120,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(mss(_start), style: VText.doto(15)),
                    Text(mss(_start + _clip), style: VText.doto(15)),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: _loading
                          ? 'Loading the song… · '
                          : _playing
                          ? 'Previewing · '
                          : 'Drag the wave to choose · ',
                    ),
                    TextSpan(
                      text: _playing && !_loading
                          ? '${mss(_elapsed)} / 0:15'
                          : '15 s',
                      style: VText.inter(12, weight: 600),
                    ),
                  ],
                ),
                style: VText.secondary,
              ),
              const SizedBox(height: 26),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                child: Row(
                  children: [
                    Semantics(
                      button: true,
                      label: _playing ? 'Stop preview' : 'Play preview',
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          VCircleButton(
                            icon: _playing ? VIcon.pause : VIcon.play,
                            size: 54,
                            onTap: _preview,
                          ),
                          if (_loading)
                            const IgnorePointer(
                              child: VSpinner(size: 54, strokeWidth: 2.5),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: VButton.primary(
                        'Send to $partner',
                        onPressed: () =>
                            Navigator.of(context)
                                .pop(MusicBody(widget.song, start: _start)),
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
