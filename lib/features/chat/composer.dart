import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/services.dart';

import '../../core/icons/v_icons.dart';
import '../../core/theme/v_colors.dart';
import '../../core/theme/v_palette.dart';
import '../../core/theme/v_text.dart';
import '../../core/widgets/v_buttons.dart';
import '../../core/widgets/v_glass.dart';
import '../../core/widgets/v_ink.dart';
import '../../core/widgets/v_progress.dart';
import '../../core/widgets/v_surface.dart';
import '../../data/models.dart';
import '../../data/providers.dart' show RoundCamera, Voice;
import '../common/art.dart';
import '../common/overlay.dart';
import '../common/parts.dart';

/// The composer's callbacks.
class ComposerActions {
  const ComposerActions({
    required this.onSendText,
    required this.onSendVoice,
    required this.onSendRound,
    required this.onAttach,
    required this.onStickers,
    this.onSendMedia,
    this.onCancelReply,
    this.onRemoveMedia,
    this.onAddMedia,
    this.onTyping,
  });

  final void Function(String text) onSendText;

  /// A voice note: its [path] and [wave] when it was really recorded.
  final void Function(Duration length, {String? path, List<double>? wave})
  onSendVoice;

  /// A round video: its [path] when it was really recorded.
  final void Function(Duration length, {String? path}) onSendRound;
  final VoidCallback onAttach;
  final VoidCallback onStickers;
  final void Function(String caption)? onSendMedia;
  final VoidCallback? onCancelReply;
  final void Function(int index)? onRemoveMedia;
  final VoidCallback? onAddMedia;

  /// Text started or stopped being there (the partner's typing dots).
  final void Function(bool typing)? onTyping;
}

/// The chat's composer (C16).
class Composer extends StatefulWidget {
  const Composer({
    super.key,
    required this.actions,
    this.replyTo,
    this.partner = '',
    this.media = const [],
    this.enterSends = false,
    this.enabled = true,
    this.voice,
    this.roundCamera,
  });

  final ComposerActions actions;
  final Message? replyTo;
  final String partner;

  /// Photos picked and waiting to be sent: shows the strip.
  final List<Media> media;
  final bool enterSends;

  /// Off in the decoy chat: everything shows, nothing sends.
  final bool enabled;

  /// The real microphone (Neon builds); null records pretend.
  final Voice? voice;

  /// The front camera for round videos (Neon builds); null is pretend.
  final RoundCamera? roundCamera;

  @override
  State<Composer> createState() => ComposerState();
}

enum _Rec { none, holding, locked }

class ComposerState extends State<Composer> with WidgetsBindingObserver {
  /// The keyboard's height last time the window changed.
  double _keyboard = 0;

  /// The keyboard has risen since the field took focus. Until it has, a
  /// keyboard still sliding away from before isn't "put away".
  bool _risen = false;

  /// Android hides and re-shows the keyboard for a frame or two when the
  /// text connection resets; only a keyboard that stays down this long was
  /// really put away.
  Timer? _away;
  static const _awayAfter = Duration(milliseconds: 400);
  final _text = TextEditingController();
  final _focus = FocusNode();

  /// The mic button records a round video instead (tap to switch).
  bool _round = false;

  _Rec _rec = _Rec.none;
  Duration _length = Duration.zero;
  Timer? _clock;
  final _rand = math.Random(7);
  final List<double> _live = [];

  /// How far the finger has slid while holding (left to cancel, up to
  /// lock).
  Offset _slide = Offset.zero;

  /// While recording a round video: its length, for the recorder overlay.
  final _roundLength = ValueNotifier(Duration.zero);

  /// The recorder over everything while recording a round video. An
  /// overlay entry, not a route: pushing a route mid-hold makes the
  /// Navigator cancel the finger, and "release to send" never comes.
  OverlayEntry? _roundEntry;

  /// The keyboard was put away (Back, or its own hide key): let go of the
  /// focus too, or the next route that closes hands it back and the
  /// keyboard pops up on its own.
  @override
  void didChangeMetrics() {
    final views = WidgetsBinding.instance.platformDispatcher.views;
    if (views.isEmpty) return;
    final now = views.first.viewInsets.bottom;
    if (_focus.hasFocus && now > _keyboard) _risen = true;
    if (now > 0) {
      _away?.cancel();
    } else if (_risen && _keyboard > 0 && _focus.hasFocus) {
      _away?.cancel();
      _away = Timer(_awayAfter, () {
        final views = WidgetsBinding.instance.platformDispatcher.views;
        final still = views.isEmpty || views.first.viewInsets.bottom == 0;
        if (mounted && still && _focus.hasFocus) {
          _risen = false;
          _focus.unfocus();
        }
      });
    }
    _keyboard = now;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _focus.addListener(() {
      if (_focus.hasFocus) _risen = false;
    });
    var was = false;
    _text.addListener(() {
      setState(() {});
      if (_typing || was) widget.actions.onTyping?.call(_typing);
      was = _typing;
    });
  }

  @override
  void dispose() {
    _roundEntry?.remove();
    WidgetsBinding.instance.removeObserver(this);
    _away?.cancel();
    _clock?.cancel();
    _text.dispose();
    _focus.dispose();
    _roundLength.dispose();
    super.dispose();
  }

  bool get _typing => _text.text.trim().isNotEmpty;

  void _send() {
    if (!widget.enabled || !_typing) return;
    HapticFeedback.selectionClick();
    widget.actions.onSendText(_text.text.trim());
    _text.clear();
  }

  // Voice and round video recording.

  StreamSubscription<double>? _levels;
  final List<double> _wave = [];

  /// Where the finger went down to record. The hold is followed from here
  /// by a Listener around the whole composer, because the layout switches
  /// to the recording row underneath it and the mic button's own long
  /// press would be lost with it.
  Offset? _holdFrom;

  void _start(LongPressStartDetails d) {
    if (!widget.enabled) return;
    _holdFrom = d.globalPosition;
    HapticFeedback.mediumImpact();
    _length = Duration.zero;
    _slide = Offset.zero;
    _live.clear();
    _wave.clear();
    _clock?.cancel();
    final voice = widget.voice;
    if (voice != null && !_round) {
      // The real microphone: its loudness draws the live wave.
      unawaited(
        voice.start().then((ok) {
          if (!ok && mounted) _cancel();
        }),
      );
      unawaited(_levels?.cancel());
      _levels = voice.levels.listen((v) {
        _wave.add(v);
        if (!mounted) return;
        setState(() {
          _live.add(0.08 + v * 0.92);
          if (_live.length > 40) _live.removeAt(0);
        });
      });
    }
    _clock = Timer.periodic(const Duration(milliseconds: 100), (_) {
      _length += const Duration(milliseconds: 100);
      if (_round) {
        _roundLength.value = _length;
        if (_length >= const Duration(minutes: 1)) _finish();
        return;
      }
      if (widget.voice != null) {
        setState(() {}); // the timer; the wave comes from the microphone
        return;
      }
      setState(() {
        _live.add(0.2 + _rand.nextDouble() * 0.8);
        if (_live.length > 40) _live.removeAt(0);
      });
    });
    if (_round) {
      final camera = widget.roundCamera;
      final preview = ValueNotifier<Widget?>(null);
      if (camera != null) {
        unawaited(
          camera.open().then((w) => preview.value = w, onError: (Object _) {}),
        );
      }
      dropKeyboard();
      final entry = _roundEntry = OverlayEntry(
        builder: (_) => RoundRecorder(
          length: _roundLength,
          preview: preview,
          onCancel: _cancel,
          onStop: _finish,
        ),
      );
      Overlay.of(context, rootOverlay: true).insert(entry);
    }
    setState(() => _rec = _Rec.holding);
  }

  void _move(LongPressMoveUpdateDetails d) => _slideTo(d.offsetFromOrigin);

  void _pointerMove(PointerMoveEvent e) {
    final from = _holdFrom;
    if (from != null) _slideTo(e.position - from);
  }

  void _pointerUp(PointerEvent _) {
    if (_holdFrom == null) return;
    _holdFrom = null;
    if (_rec == _Rec.holding) unawaited(_finish());
  }

  void _slideTo(Offset slide) {
    if (_rec != _Rec.holding) return;
    _slide = slide;
    if (_slide.dx < -120) {
      _cancel();
    } else if (!_round && _slide.dy < -80) {
      HapticFeedback.lightImpact();
      setState(() => _rec = _Rec.locked);
    } else {
      setState(() {});
    }
  }

  void _end(LongPressEndDetails _) => _pointerUp(const PointerUpEvent());

  void _closeRound() {
    _roundEntry?.remove();
    _roundEntry = null;
  }

  void _cancel() {
    _holdFrom = null;
    _clock?.cancel();
    unawaited(_levels?.cancel());
    if (!_round) unawaited(widget.voice?.cancel());
    if (_round) unawaited(widget.roundCamera?.close());
    HapticFeedback.lightImpact();
    _closeRound();
    setState(() => _rec = _Rec.none);
  }

  Future<void> _finish() async {
    _clock?.cancel();
    unawaited(_levels?.cancel());
    final len = _length;
    final round = _round;
    _closeRound();
    setState(() => _rec = _Rec.none);
    final voice = round ? null : widget.voice;
    if (len < const Duration(milliseconds: 600)) {
      await voice?.cancel();
      return;
    }
    if (round) {
      final camera = widget.roundCamera;
      if (camera == null) {
        widget.actions.onSendRound(len);
        return;
      }
      final path = await camera.stop();
      if (path != null) widget.actions.onSendRound(len, path: path);
      return;
    }
    if (voice == null) {
      widget.actions.onSendVoice(len);
      return;
    }
    final path = await voice.stop();
    if (path == null) return;
    widget.actions.onSendVoice(len, path: path, wave: _bars(_wave, 40));
  }

  /// [levels] squeezed (or stretched) into [n] bars.
  static List<double> _bars(List<double> levels, int n) {
    if (levels.isEmpty) return List.filled(n, 0.1);
    return [
      for (var i = 0; i < n; i++)
        (levels[(i * levels.length / n).floor()] * 0.92 + 0.08).clamp(
          0.08,
          1.0,
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerMove: _pointerMove,
      onPointerUp: _pointerUp,
      onPointerCancel: _pointerUp,
      child: _body(context),
    );
  }

  Widget _body(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.replyTo != null && widget.media.isEmpty) ...[
          _ReplyBar(
            message: widget.replyTo!,
            partner: widget.partner,
            onCancel: widget.actions.onCancelReply,
          ),
          const SizedBox(height: 8),
        ],
        if (widget.media.isNotEmpty)
          _MediaStrip(
            media: widget.media,
            onRemove: widget.actions.onRemoveMedia,
            onAdd: widget.actions.onAddMedia,
            onSend: (c) => widget.actions.onSendMedia?.call(c),
          )
        else if (_rec != _Rec.none && !_round)
          _recording(context)
        else
          _idle(context),
      ],
    );
  }

  Widget _idle(BuildContext context) {
    return Row(
      children: [
        VCircleButton(
          icon: VIcon.plus,
          size: 44,
          onTap: widget.enabled ? widget.actions.onAttach : null,
        ),
        const SizedBox(width: 8),
        Expanded(child: _field(context)),
        const SizedBox(width: 8),
        if (_typing)
          Semantics(
            button: true,
            label: 'Send',
            child: VCircleButton(
              icon: VIcon.send,
              size: 44,
              filled: true,
              onTap: _send,
            ),
          )
        else
          Semantics(
            button: true,
            label: _round
                ? 'Hold to record a round video, tap for voice'
                : 'Hold to record, tap for round video',
            child: GestureDetector(
              onLongPressStart: _start,
              onLongPressMoveUpdate: _move,
              onLongPressEnd: _end,
              child: VCircleButton(
                icon: _round ? VIcon.roundVideo : VIcon.mic,
                size: 44,
                filled: true,
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() => _round = !_round);
                },
              ),
            ),
          ),
      ],
    );
  }

  Widget _field(BuildContext context) {
    final ink = VInk.of(context);
    return VGlass(
      radius: 22,
      tint: VPalette.of(context).glassCard,
      blur: 16,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: CupertinoTextField(
                controller: _text,
                focusNode: _focus,
                enabled: widget.enabled,
                minLines: 1,
                maxLines: 5,
                textInputAction: widget.enterSends
                    ? TextInputAction.send
                    : TextInputAction.newline,
                onSubmitted: (_) => _send(),
                cursorColor: ink,
                placeholder: 'Message',
                placeholderStyle: VText.inter(15).copyWith(color: ink),
                style: VText.inter(15, height: 1.4).copyWith(color: ink),
                padding: const EdgeInsets.fromLTRB(16, 11, 4, 11),
                decoration: const BoxDecoration(color: VColors.transparent),
              ),
            ),
            Semantics(
              button: true,
              label: 'Stickers, GIFs and memes',
              child: VTappable(
                onTap: widget.enabled ? widget.actions.onStickers : null,
                child: const Padding(
                  padding: EdgeInsets.fromLTRB(6, 10, 12, 10),
                  child: VIconView(VIcon.sticker, size: 24),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Holding the mic (C16): the timer, the live waveform, "slide to
  /// cancel", and the lock above the button; or locked, hands-free.
  Widget _recording(BuildContext context) {
    final locked = _rec == _Rec.locked;
    final ink = VInk.of(context);
    final field = VGlass(
      radius: 22,
      tint: VPalette.of(context).glassCard,
      blur: 16,
      child: SizedBox(
        height: 44,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            children: [
              Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(color: ink, shape: BoxShape.circle),
              ),
              const SizedBox(width: 10),
              Text(mss(_length), style: VText.doto(16)),
              const SizedBox(width: 10),
              Expanded(
                child: ClipRect(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: WaveBars(_live, height: 22, fit: true),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              if (locked)
                VTappable(
                  onTap: _finish,
                  child: const SizedBox.square(
                    dimension: 24,
                    child: VOutlined(
                      radius: 12,
                      child: Center(child: _StopSquare()),
                    ),
                  ),
                )
              else
                Text(
                  '‹ slide to cancel',
                  style: VText.inter(12).copyWith(
                    color: ink.withValues(
                      alpha: (1 + _slide.dx / 120).clamp(0.3, 1.0),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    if (locked) {
      return Row(
        children: [
          VCircleButton(icon: VIcon.trash, size: 44, onTap: _cancel),
          const SizedBox(width: 8),
          Expanded(child: field),
          const SizedBox(width: 8),
          VCircleButton(
            icon: VIcon.send,
            size: 44,
            filled: true,
            onTap: _finish,
          ),
        ],
      );
    }
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Row(
          children: [
            Expanded(child: field),
            const SizedBox(width: 12),
            GestureDetector(
              onLongPressMoveUpdate: _move,
              onLongPressEnd: _end,
              child: Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: ink,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: VPalette.of(context).glassCard,
                      spreadRadius: 10,
                    ),
                  ],
                ),
                child: Center(
                  child: VIconView(
                    VIcon.mic,
                    size: 24,
                    color: VInk.surfaceOf(context),
                  ),
                ),
              ),
            ),
          ],
        ),
        Positioned(
          right: 10,
          bottom: 84,
          child: VGlass(
            radius: 22,
            tint: VPalette.of(context).glassSheet,
            blur: 14,
            child: const SizedBox(
              width: 44,
              height: 96,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  VIconView(VIcon.lock, size: 18),
                  VIconView(VIcon.up, size: 18),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _StopSquare extends StatelessWidget {
  const _StopSquare();

  @override
  Widget build(BuildContext context) => Container(
    width: 8,
    height: 8,
    decoration: BoxDecoration(
      color: VInk.of(context),
      borderRadius: BorderRadius.circular(2),
    ),
  );
}

/// The quote above the field while replying (C16).
class _ReplyBar extends StatelessWidget {
  const _ReplyBar({
    required this.message,
    required this.partner,
    this.onCancel,
  });

  final Message message;
  final String partner;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final q = message.quote();
    return VGlass(
      radius: 16,
      tint: VPalette.of(context).glassSheet,
      blur: 14,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
        child: Row(
          children: [
            const VIconView(VIcon.reply, size: 18),
            const SizedBox(width: 10),
            Container(width: 2, height: 32, color: VInk.of(context)),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    q.fromMe ? 'You' : partner,
                    style: VText.inter(13, weight: 600),
                  ),
                  Text(
                    q.text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: VText.inter(13),
                  ),
                ],
              ),
            ),
            Semantics(
              button: true,
              label: 'Cancel reply',
              child: VTappable(
                onTap: onCancel,
                child: const Padding(
                  padding: EdgeInsets.all(6),
                  child: VIconView(VIcon.close, size: 18),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Photos picked to send (C16): thumbnails with ×, an add tile, a caption
/// and "Send n".
class _MediaStrip extends StatefulWidget {
  const _MediaStrip({
    required this.media,
    required this.onSend,
    this.onRemove,
    this.onAdd,
  });

  final List<Media> media;
  final void Function(String caption) onSend;
  final void Function(int index)? onRemove;
  final VoidCallback? onAdd;

  @override
  State<_MediaStrip> createState() => _MediaStripState();
}

class _MediaStripState extends State<_MediaStrip> {
  final _caption = TextEditingController();

  @override
  void dispose() {
    _caption.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ink = VInk.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 72,
          child: ListView(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            children: [
              for (var i = 0; i < widget.media.length; i++)
                Padding(
                  padding: const EdgeInsets.only(right: 8, top: 6),
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      ArtBox(
                        art: widget.media[i].art,
                        path: widget.media[i].path,
                        width: 64,
                        height: 64,
                        radius: BorderRadius.circular(14),
                      ),
                      Positioned(
                        top: -6,
                        right: -6,
                        child: VCircleButton(
                          icon: VIcon.close,
                          size: 22,
                          filled: true,
                          onTap: () => widget.onRemove?.call(i),
                        ),
                      ),
                    ],
                  ),
                ),
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: VTappable(
                  onTap: widget.onAdd,
                  child: const SizedBox.square(
                    dimension: 64,
                    child: VOutlined(
                      radius: 14,
                      outline: VOutline.dashed,
                      child: Center(child: VIconView(VIcon.plus, size: 24)),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: VGlass(
                radius: 22,
                tint: VPalette.of(context).glassCard,
                blur: 16,
                child: CupertinoTextField(
                  controller: _caption,
                  placeholder: 'Add a caption',
                  placeholderStyle: VText.inter(15).copyWith(color: ink),
                  style: VText.inter(15).copyWith(color: ink),
                  cursorColor: ink,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  decoration: const BoxDecoration(color: VColors.transparent),
                ),
              ),
            ),
            const SizedBox(width: 8),
            VTappable(
              onTap: () => widget.onSend(_caption.text.trim()),
              child: Container(
                height: 44,
                padding: const EdgeInsets.symmetric(horizontal: 18),
                decoration: BoxDecoration(
                  color: ink,
                  borderRadius: BorderRadius.circular(22),
                ),
                child: VInkScope(
                  ink: VInk.surfaceOf(context),
                  child: Row(
                    children: [
                      Text(
                        'Send ${widget.media.length}',
                        style: VText.inter(14, weight: 600),
                      ),
                      const SizedBox(width: 6),
                      const VIconView(VIcon.send, size: 18),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Recording a round video (C16): the circle preview with its progress
/// ring, the timer out of a minute, and cancel / stop / swap camera. The
/// camera preview is stand-in art until the camera arrives in Phase 4.
class RoundRecorder extends StatelessWidget {
  const RoundRecorder({
    super.key,
    required this.length,
    required this.onCancel,
    required this.onStop,
    this.preview,
  });

  /// The front camera's picture, once it's open (Neon builds).
  final ValueListenable<Widget?>? preview;
  final ValueListenable<Duration> length;
  final VoidCallback onCancel;
  final VoidCallback onStop;

  static const max = Duration(minutes: 1);

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(color: VPalette.of(context).popupScrim),
        SafeArea(
          child: ValueListenableBuilder<Duration>(
            valueListenable: length,
            builder: (context, len, _) => Column(
              children: [
                const SizedBox(height: 110),
                SizedBox.square(
                  dimension: 300,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      ClipOval(
                        child: SizedBox.square(
                          dimension: 280,
                          child: ValueListenableBuilder<Widget?>(
                            valueListenable:
                                preview ?? ValueNotifier<Widget?>(null),
                            builder: (context, camera, _) =>
                                camera ??
                                const ArtBox(
                                  art: 0,
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                          ),
                        ),
                      ),
                      VRing(
                        value: len.inMilliseconds / max.inMilliseconds,
                        size: 300,
                        strokeWidth: 5,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(mss(len), style: VText.doto(32, weight: 900)),
                    const SizedBox(width: 6),
                    Text('/ 1:00', style: VText.doto(14, weight: 500)),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  'Release to send · slide left to cancel',
                  style: VText.secondary,
                ),
                const Spacer(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    VCircleButton(icon: VIcon.close, size: 44, onTap: onCancel),
                    const SizedBox(width: 34),
                    Semantics(
                      button: true,
                      label: 'Stop and send',
                      child: VTappable(
                        onTap: onStop,
                        child: SizedBox.square(
                          dimension: 72,
                          child: VOutlined(
                            radius: 36,
                            child: Center(
                              child: Container(
                                width: 28,
                                height: 28,
                                decoration: BoxDecoration(
                                  color: VInk.of(context),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 34),
                    VCircleButton(
                      icon: VIcon.swapCamera,
                      size: 44,
                      onTap: () => HapticFeedback.selectionClick(),
                    ),
                  ],
                ),
                const SizedBox(height: 60),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
