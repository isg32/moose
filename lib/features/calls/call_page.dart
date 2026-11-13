import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/icons/v_icons.dart';
import '../../core/theme/v_colors.dart';
import '../../core/theme/v_text.dart';
import '../../core/widgets/v_buttons.dart';
import '../../core/widgets/v_glass.dart';
import '../../core/widgets/v_ink.dart';
import '../../core/widgets/v_page.dart';
import '../../core/widgets/v_surface.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../common/art.dart';
import '../common/avatar.dart';
import '../common/overlay.dart';
import '../common/parts.dart';
import '../common/rotation.dart';
import '../moments/moment_flight.dart';

enum CallStage { calling, incoming, connected }

/// Starts a call to the partner (K1). When it ends, its row goes in the
/// chat (K5).
Future<void> startCall(
  BuildContext context,
  WidgetRef ref, {
  required bool video,
}) => _run(context, ref, video: video, incoming: false);

/// The partner is calling (K2).
Future<void> answerCall(
  BuildContext context,
  WidgetRef ref, {
  required bool video,
}) => _run(context, ref, video: video, incoming: true);

Future<void> _run(
  BuildContext context,
  WidgetRef ref, {
  required bool video,
  required bool incoming,
}) async {
  final row = await pushPage<CallBody>(
    context,
    (_) => CallPage(video: video, incoming: incoming),
  );
  // On Neon the caller's phone writes the call's row for both of you.
  if (row != null && !(incoming && ref.read(onNeonProvider))) {
    ref.read(messagesProvider.notifier).send(row);
  }
}

class CallPage extends ConsumerStatefulWidget {
  const CallPage({
    super.key,
    required this.video,
    this.incoming = false,
    this.answersAfter = const Duration(seconds: 3),
  });

  final bool video;
  final bool incoming;

  /// How long the mock partner takes to pick up.
  final Duration answersAfter;

  @override
  ConsumerState<CallPage> createState() => _CallPageState();
}

class _CallPageState extends ConsumerState<CallPage>
    with SingleTickerProviderStateMixin {
  late CallStage _stage = widget.incoming
      ? CallStage.incoming
      : CallStage.calling;
  late bool _video = widget.video;
  bool _muted = false;
  bool _speaker = false;
  bool _cameraOff = false;
  bool _front = true;
  Duration _length = Duration.zero;
  Timer? _clock;
  Timer? _answer;

  late final _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  )..repeat();

  /// The real call, on Neon; null runs the mock's timer.
  late final CallLink? _link = ref.read(callLinkProvider);
  StreamSubscription<CallUpdate>? _updates;
  bool _done = false;

  void _onUpdate(CallUpdate u) {
    if (!mounted) return;
    switch (u.phase) {
      case CallPhase.connected:
        if (_stage != CallStage.connected) _connect();
      case CallPhase.ended:
        _finish(u.why);
      case CallPhase.ringing || CallPhase.connecting:
        setState(() {});
    }
  }

  /// Closes the page with the call's row (K5).
  void _finish(CallEnd? why) {
    if (_done) return;
    _done = true;
    final outcome = _stage == CallStage.connected
        ? CallOutcome.answered
        : widget.incoming
        ? CallOutcome.missed
        : CallOutcome.noAnswer;
    Navigator.of(context)
        .pop(CallBody(video: _video, outcome: outcome, length: _length));
  }

  /// A moment flying over the call now.
  VMoment? _flight;
  late final InCall _inCall = ref.read(inCallProvider.notifier);

  void _fly(VMoment m) => setState(() => _flight = m);

  @override
  void initState() {
    super.initState();
    Future.microtask(() => _inCall.set(true));
    final link = _link;
    if (link != null) {
      _updates = link.updates.listen(_onUpdate);
      if (!widget.incoming) unawaited(link.dial(video: widget.video));
      return;
    }
    if (!widget.incoming) {
      final away = ref.read(pairingProvider).presence == Presence.away;
      _answer = Timer(widget.answersAfter, () {
        if (!mounted) return;
        if (away) {
          // Her Moose is closed: nobody picks up (K5).
          Navigator.of(context)
              .pop(CallBody(video: _video, outcome: CallOutcome.noAnswer));
        } else {
          _connect();
        }
      });
    }
  }

  @override
  void dispose() {
    final inCall = _inCall;
    Future.microtask(() => inCall.set(false));
    unawaited(_updates?.cancel());
    // Leaving the page any other way still ends the call.
    if (!_done) unawaited(_link?.hangUp());
    _clock?.cancel();
    _answer?.cancel();
    _pulse.dispose();
    super.dispose();
  }

  void _connect() {
    HapticFeedback.mediumImpact();
    setState(() => _stage = CallStage.connected);
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _length += const Duration(seconds: 1));
    });
  }

  void _end() {
    HapticFeedback.mediumImpact();
    final link = _link;
    if (link != null) {
      // The link reports "ended", which closes the page with its row.
      unawaited(link.hangUp());
      return;
    }
    Navigator.of(context).pop(
      CallBody(
        video: _video,
        outcome: _stage == CallStage.connected
            ? CallOutcome.answered
            : CallOutcome.missed,
        length: _length,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // A hug (or any moment) from them during the call flies over it.
    ref.listen(incomingMomentProvider, (_, m) {
      if (m == null) return;
      ref.read(incomingMomentProvider.notifier).dismiss();
      _fly(m);
    });
    final flight = _flight;
    return Stack(
      fit: StackFit.expand,
      children: [
        _body(context),
        if (flight != null)
          Positioned.fill(
            child: MomentFlight(
              key: ValueKey(flight),
              moment: flight,
              onDone: () {
                if (mounted) setState(() => _flight = null);
              },
            ),
          ),
      ],
    );
  }

  Widget _body(BuildContext context) {
    final partner = ref.watch(pairingProvider).partner;
    if (_stage == CallStage.connected && _video) {
      // Video turns with the phone (landscape where it helps).
      return AllowRotation(
        child: _VideoCall(
          partner: partner,
          length: _length,
          muted: _muted,
          cameraOff: _cameraOff,
          front: _front,
          remote: _link?.remoteView(),
          local: _cameraOff ? null : _link?.localView(),
          onFlip: () {
            setState(() => _front = !_front);
            unawaited(_link?.flip());
          },
          onMute: () {
            setState(() => _muted = !_muted);
            _link?.mute(_muted);
          },
          onCamera: () {
            setState(() => _cameraOff = !_cameraOff);
            _link?.cameraOff(_cameraOff);
          },
          onEnd: _end,
        ),
      );
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        const VVeil(),
        SafeArea(
          child: Column(
            children: [
              const SizedBox(height: 64),
              switch (_stage) {
                CallStage.calling => _calling(partner),
                CallStage.incoming => _incoming(partner),
                CallStage.connected => _voice(partner),
              },
              const Spacer(),
              Padding(
                padding: const EdgeInsets.fromLTRB(30, 0, 30, 44),
                child: switch (_stage) {
                  CallStage.calling => Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _Control(
                        VIcon.micOff,
                        _muted ? 'Muted' : 'Mute',
                        on: _muted,
                        onTap: () {
                          setState(() => _muted = !_muted);
                          _link?.mute(_muted);
                        },
                      ),
                      const SizedBox(width: 34),
                      _Control(
                        VIcon.phone,
                        'End',
                        on: true,
                        end: true,
                        onTap: _end,
                      ),
                      const SizedBox(width: 34),
                      _Control(
                        VIcon.speaker,
                        'Speaker',
                        on: _speaker,
                        onTap: () {
                          setState(() => _speaker = !_speaker);
                          _link?.speaker(_speaker);
                        },
                      ),
                    ],
                  ),
                  CallStage.incoming => Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _Control(
                        VIcon.phone,
                        'Decline',
                        size: 72,
                        end: true,
                        onTap: _end,
                      ),
                      _Control(
                        _video ? VIcon.video : VIcon.phone,
                        'Accept',
                        size: 72,
                        on: true,
                        onTap: _link == null
                            ? _connect
                            : () => unawaited(_link.answer()),
                      ),
                    ],
                  ),
                  CallStage.connected => _grid(),
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _rings(Widget child, {bool dashed = false}) => SizedBox.square(
    dimension: 220,
    child: Stack(
      alignment: Alignment.center,
      children: [
        for (final offset in [0.0, 0.5])
          AnimatedBuilder(
            animation: _pulse,
            builder: (context, c) {
              final t = (_pulse.value + offset) % 1;
              return Opacity(
                opacity: (0.9 * (1 - t)).clamp(0.0, 1.0),
                child: Transform.scale(scale: 0.7 + 0.6 * t, child: c),
              );
            },
            child: VOutlined(
              radius: 110,
              outline: dashed ? VOutline.dashed : VOutline.solid,
              child: const SizedBox.expand(),
            ),
          ),
        child,
      ],
    ),
  );

  Widget _calling(Person p) => Column(
    children: [
      Text(_video ? 'VIDEO CALL' : 'VOICE CALL', style: VText.eyebrow),
      const SizedBox(height: 10),
      _rings(Avatar(p, size: 130), dashed: true),
      const SizedBox(height: 10),
      Text(p.name, style: VText.doto(44, weight: 900, height: 1)),
      const SizedBox(height: 10),
      Text('Ringing…', style: VText.inter(15)),
    ],
  );

  Widget _incoming(Person p) => Column(
    children: [
      Text(
        '${_video ? 'VIDEO' : 'VOICE'} CALL · DIRECT AND ENCRYPTED',
        style: VText.eyebrow,
      ),
      const SizedBox(height: 10),
      _rings(Avatar(p, size: 130, filled: true)),
      const SizedBox(height: 10),
      Text(p.name, style: VText.doto(44, weight: 900, height: 1)),
      const SizedBox(height: 10),
      Text('is calling you', style: VText.inter(15)),
      const SizedBox(height: 16),
      VPill(
        'Reply with a message',
        style: VText.inter(13, weight: 500),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        onTap: () =>
            Navigator.of(context)
                .pop(CallBody(video: _video, outcome: CallOutcome.missed)),
      ),
    ],
  );

  Widget _voice(Person p) => Column(
    children: [
      const SizedBox(height: 10),
      Avatar(p, size: 110),
      const SizedBox(height: 16),
      Text(p.name, style: VText.doto(36, weight: 900, height: 1)),
      const SizedBox(height: 18),
      Text(mss(_length), style: VText.doto(52, weight: 900, height: 1)),
      const SizedBox(height: 10),
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const VIconView(VIcon.lock, size: 15),
          const SizedBox(width: 6),
          Text('Direct, phone to phone · encrypted', style: VText.inter(13)),
        ],
      ),
      const SizedBox(height: 12),
      const _Signal(level: 3),
    ],
  );

  Widget _grid() {
    const hug = VMoment.hug;
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _Control(
              VIcon.micOff,
              _muted ? 'Muted' : 'Mute',
              on: _muted,
              onTap: () {
                setState(() => _muted = !_muted);
                _link?.mute(_muted);
              },
            ),
            _Control(
              VIcon.speaker,
              'Speaker',
              on: _speaker,
              onTap: () {
                setState(() => _speaker = !_speaker);
                _link?.speaker(_speaker);
              },
            ),
            _Control(
              VIcon.video,
              'Video',
              onTap: () => setState(() => _video = true),
            ),
          ],
        ),
        const SizedBox(height: 22),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _Control(
              VIcon.hug,
              'Send a hug',
              tint: hug.color,
              emoji: hug.emoji,
              onTap: () {
                if (ref.read(momentCooldownProvider.notifier).send(hug)) {
                  _fly(hug);
                }
              },
            ),
            _Control(VIcon.phone, 'End', on: true, end: true, onTap: _end),
            _Control(VIcon.chat, 'Chat', onTap: _end),
          ],
        ),
      ],
    );
  }
}

/// A round call control with its label under it.
class _Control extends StatelessWidget {
  const _Control(
    this.icon,
    this.label, {
    required this.onTap,
    this.on = false,
    this.end = false,
    this.size = 64,
    this.tint,
    this.emoji,
  });

  final VIcon icon;
  final String label;
  final VoidCallback onTap;

  /// Filled with ink.
  final bool on;

  /// The hang-up handset, turned down.
  final bool end;
  final double size;
  final Color? tint;
  final String? emoji;

  @override
  Widget build(BuildContext context) {
    final ink = VInk.of(context);
    final paper = VInk.surfaceOf(context);
    Widget glyph = emoji != null
        ? Text(emoji!, style: const TextStyle(fontSize: 26, height: 1))
        : VIconView(icon, size: 24, color: on ? paper : ink);
    if (end) glyph = Transform.rotate(angle: 2.36, child: glyph);
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: VTappable(
        onTap: onTap,
        child: Column(
          children: [
            SizedBox.square(
              dimension: size,
              child: VOutlined(
                radius: size / 2,
                outline: on || tint != null ? VOutline.none : VOutline.solid,
                fill: tint ?? (on ? ink : VColors.transparent),
                child: Center(child: glyph),
              ),
            ),
            const SizedBox(height: 8),
            Text(label, style: VText.inter(12, weight: 500)),
          ],
        ),
      ),
    );
  }
}

/// Connection strength: four bars, the last outlined when weaker.
class _Signal extends StatelessWidget {
  const _Signal({required this.level});

  final int level;

  @override
  Widget build(BuildContext context) {
    final ink = VInk.of(context);
    return Semantics(
      label: 'Connection $level of 4',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < 4; i++) ...[
            if (i > 0) const SizedBox(width: 3),
            Container(
              width: 4,
              height: 6.0 + i * 5.5,
              decoration: BoxDecoration(
                color: i < level ? ink : null,
                border: i < level ? null : Border.all(color: ink),
                borderRadius: BorderRadius.circular(1),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// K4: always dark, it's video. Her picture fills the screen (stand-in art
/// until WebRTC arrives in Phase 4), yours sits top right.
class _VideoCall extends StatelessWidget {
  const _VideoCall({
    required this.partner,
    required this.length,
    required this.muted,
    required this.cameraOff,
    required this.front,
    required this.onFlip,
    required this.onMute,
    required this.onCamera,
    required this.onEnd,
    this.remote,
    this.local,
  });

  /// The live pictures on a real call; stand-in art otherwise.
  final Widget? remote;
  final Widget? local;
  final Person partner;
  final Duration length;
  final bool muted;
  final bool cameraOff;
  final bool front;
  final VoidCallback onFlip;
  final VoidCallback onMute;
  final VoidCallback onCamera;
  final VoidCallback onEnd;

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.paddingOf(context);
    final top = pad.top;
    final bottom = pad.bottom;
    // In landscape the controls stand in a column down the right side.
    final wide = isLandscape(context);
    final buttons = <Widget>[
      Semantics(
        button: true,
        label: 'Flip camera',
        child: VCircleButton(icon: VIcon.swapCamera, size: 54, onTap: onFlip),
      ),
      Semantics(
        button: true,
        label: muted ? 'Unmute' : 'Mute',
        child: VCircleButton(
          icon: VIcon.micOff,
          size: 54,
          filled: muted,
          onTap: onMute,
        ),
      ),
      Semantics(
        button: true,
        label: cameraOff ? 'Camera on' : 'Camera off',
        child: VCircleButton(
          icon: VIcon.video,
          size: 54,
          filled: cameraOff,
          onTap: onCamera,
        ),
      ),
      Semantics(
        button: true,
        label: 'End call',
        child: VTappable(
          onTap: onEnd,
          child: Container(
            width: 54,
            height: 54,
            decoration: const BoxDecoration(
              color: VColors.white,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Transform.rotate(
                angle: 2.36,
                child: const VIconView(
                  VIcon.phone,
                  size: 24,
                  color: VColors.black,
                ),
              ),
            ),
          ),
        ),
      ),
    ];
    return VInkScope(
      ink: VColors.white,
      child: ColoredBox(
        color: VColors.black,
        child: Stack(
          fit: StackFit.expand,
          children: [
            remote ??
                const ArtBox(
                  art: 0,
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              height: top + 110,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      VColors.black.withValues(alpha: 0.55),
                      VColors.transparent,
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              left: 20,
              top: top + 16,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(partner.name, style: VText.inter(17, weight: 600)),
                  Text(mss(length), style: VText.doto(14)),
                ],
              ),
            ),
            Positioned(
              right: wide ? 112 + pad.right : 16,
              top: top + 12,
              width: wide ? 150 : 104,
              height: wide ? 104 : 150,
              child: VOutlined(
                radius: 20,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(19),
                  child: cameraOff
                      ? const ColoredBox(
                          color: VColors.black,
                          child: Center(
                            child: VIconView(VIcon.video, size: 22),
                          ),
                        )
                      : local ?? ArtBox(art: front ? 4 : 5),
                ),
              ),
            ),
            Positioned(
              left: wide ? null : 14,
              right: wide ? 14 + pad.right : 14,
              top: wide ? 16 : null,
              bottom: wide ? 16 : bottom + 30,
              width: wide ? 84 : null,
              child: VGlass(
                radius: 42,
                tint: VColors.black.withValues(alpha: 0.45),
                blur: 18,
                child: SizedBox(
                  height: wide ? null : 84,
                  child: Flex(
                    direction: wide ? Axis.vertical : Axis.horizontal,
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: buttons,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
