import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../core/icons/v_icons.dart';
import '../../core/theme/v_colors.dart';
import '../../core/theme/v_palette.dart';
import '../../core/theme/v_text.dart';
import '../../core/widgets/v_buttons.dart';
import '../../core/widgets/v_surface.dart';

/// What each moment says and does (DESIGN.md › Moment colours).
extension MomentCopy on VMoment {
  String get word => switch (this) {
    VMoment.missYou => 'MISS YOU',
    _ => label.toUpperCase(),
  };

  String get back => switch (this) {
    VMoment.poke => 'Poke back',
    VMoment.hug => 'Hug back',
    VMoment.kiss => 'Kiss back',
    VMoment.missYou => 'Miss you too',
  };

  VIcon get icon => switch (this) {
    VMoment.poke => VIcon.poke,
    VMoment.hug => VIcon.hug,
    VMoment.kiss => VIcon.kiss,
    VMoment.missYou => VIcon.missYou,
  };

  String get haptic => switch (this) {
    VMoment.poke => 'Two quick taps, like a finger on your shoulder',
    VMoment.hug => 'One long, soft vibration that swells and fades',
    VMoment.kiss => 'Short, short, then a little flutter',
    VMoment.missYou => 'A slow heartbeat: lub-dub, lub-dub',
  };

  /// The hearts that drift across the screen with it.
  List<String> get hearts => switch (this) {
    VMoment.poke => const ['💛', '✨', '❤️', '🧡'],
    VMoment.hug => const ['❤️', '💗', '💕', '🩷'],
    VMoment.kiss => const ['❤️', '💋', '💞', '💗'],
    VMoment.missYou => const ['💙', '🤍', '💜', '❤️'],
  };

  /// "Aatika poked you", "You sent a hug" (B10).
  String row({required bool fromMe, required String partner}) {
    if (fromMe) {
      return switch (this) {
        VMoment.poke => 'You poked $partner',
        VMoment.hug => 'You sent a hug',
        VMoment.kiss => 'You sent a kiss',
        VMoment.missYou => 'You miss $partner',
      };
    }
    return switch (this) {
      VMoment.poke => '$partner poked you',
      VMoment.hug => '$partner sent a hug',
      VMoment.kiss => '$partner sent a kiss',
      VMoment.missYou => '$partner misses you',
    };
  }

  /// Plays the moment's vibration.
  Future<void> buzz() async {
    Future<void> wait(int ms) => Future.delayed(Duration(milliseconds: ms));
    switch (this) {
      case VMoment.poke:
        await HapticFeedback.mediumImpact();
        await wait(110);
        await HapticFeedback.mediumImpact();
      case VMoment.hug:
        for (final i in [0, 1, 2, 1, 0]) {
          await (i == 2
              ? HapticFeedback.heavyImpact()
              : i == 1
              ? HapticFeedback.mediumImpact()
              : HapticFeedback.lightImpact());
          await wait(120);
        }
      case VMoment.kiss:
        await HapticFeedback.mediumImpact();
        await wait(140);
        await HapticFeedback.mediumImpact();
        await wait(140);
        for (var i = 0; i < 3; i++) {
          await HapticFeedback.selectionClick();
          await wait(45);
        }
      case VMoment.missYou:
        for (var i = 0; i < 2; i++) {
          await HapticFeedback.heavyImpact();
          await wait(160);
          await HapticFeedback.mediumImpact();
          await wait(520);
        }
    }
  }
}

/// A moment arriving while the app is open (C25): the wash, the rings,
/// the beating centre, and hearts drifting up across the screen with the
/// gesture's own emoji floating through the middle.
class MomentBurst extends StatefulWidget {
  const MomentBurst({
    super.key,
    required this.moment,
    required this.from,
    required this.onBack,
    required this.onClose,
    this.buzz = true,
  });

  final VMoment moment;
  final String from;
  final VoidCallback onBack;
  final VoidCallback onClose;

  /// Off in tests.
  final bool buzz;

  @override
  State<MomentBurst> createState() => _MomentBurstState();
}

class _MomentBurstState extends State<MomentBurst>
    with TickerProviderStateMixin {
  /// One clock for the drifting emoji (each has its own period and delay).
  late final _drift = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 60),
  )..repeat();

  /// The rings' ripple, 2.4 s.
  late final _ripple = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  )..repeat();

  /// The heartbeat, 1.4 s.
  late final _beat = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  late final _flyers = _scatter(widget.moment);

  @override
  void initState() {
    super.initState();
    if (widget.buzz) unawaited(widget.moment.buzz());
  }

  @override
  void dispose() {
    _drift.dispose();
    _ripple.dispose();
    _beat.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.moment;
    final palette = VPalette.of(context);
    return Semantics(
      liveRegion: true,
      label: '${m.word} from ${widget.from}',
      child: Stack(
        fit: StackFit.expand,
        children: [
          ClipRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
              child: ColoredBox(
                color: palette.popupScrim,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      radius: 0.75,
                      colors: [m.wash, m.wash.withValues(alpha: 0)],
                    ),
                  ),
                ),
              ),
            ),
          ),
          IgnorePointer(
            child: AnimatedBuilder(
              animation: _drift,
              builder: (context, _) => CustomMultiChildLayout(
                delegate: _FlyerLayout(_flyers, _drift.value * 60),
                children: [
                  for (var i = 0; i < _flyers.length; i++)
                    LayoutId(
                      id: i,
                      child: _FlyerView(_flyers[i], _drift.value * 60),
                    ),
                ],
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                const Spacer(),
                _rings(m),
                const SizedBox(height: 16),
                Text(
                  m.word,
                  textAlign: TextAlign.center,
                  style: VText.doto(58, weight: 900, height: 0.92),
                ),
                const SizedBox(height: 16),
                Text('from ${widget.from} · just now', style: VText.inter(15)),
                const SizedBox(height: 26),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    VPill(
                      m.back,
                      fill: VFill.filled,
                      onTap: widget.onBack,
                      style: VText.inter(14, weight: 600),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 11,
                      ),
                    ),
                    const SizedBox(width: 10),
                    VPill(
                      'Close',
                      onTap: widget.onClose,
                      style: VText.inter(14, weight: 500),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 10,
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                Padding(
                  padding: const EdgeInsets.only(bottom: 34),
                  child: Text(m.haptic, style: VText.secondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _rings(VMoment m) {
    Widget ring(double inset, {bool dashed = false, double opacity = 1}) =>
        Positioned.fill(
          left: inset,
          top: inset,
          right: inset,
          bottom: inset,
          child: Opacity(
            opacity: opacity,
            child: VOutlined(
              radius: 200,
              color: m.color,
              outline: dashed ? VOutline.dashed : VOutline.solid,
              child: const SizedBox.expand(),
            ),
          ),
        );

    return SizedBox.square(
      dimension: 280,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // The outer ring ripples outward, twice over, a beat apart.
          for (final offset in [0.0, 0.5])
            AnimatedBuilder(
              animation: _ripple,
              builder: (context, child) {
                final t = (_ripple.value + offset) % 1;
                return Opacity(
                  opacity: (0.9 * (1 - t)).clamp(0.0, 1.0),
                  child: Transform.scale(scale: 0.7 + 0.65 * t, child: child),
                );
              },
              child: Stack(children: [ring(0, dashed: true)]),
            ),
          ring(36, opacity: 0.45),
          ring(72),
          AnimatedBuilder(
            animation: _beat,
            builder: (context, child) =>
                Transform.scale(scale: _beatScale(_beat.value), child: child),
            child: Container(
              width: 112,
              height: 112,
              decoration: BoxDecoration(
                color: m.color,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: m.wash,
                    blurRadius: 50,
                    offset: const Offset(0, 14),
                  ),
                ],
              ),
              child: Center(
                child: VIconView(
                  m.icon,
                  size: 56,
                  strokeWidth: 1.2,
                  color: VColors.black,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A heartbeat: 1 → 1.14 → 1 → 1.09 → 1, then rest (DESIGN.md).
double _beatScale(double t) {
  double ease(double a, double b, double x) =>
      a + (b - a) * Curves.easeInOut.transform(x.clamp(0.0, 1.0));
  if (t < 0.14) return ease(1, 1.14, t / 0.14);
  if (t < 0.28) return ease(1.14, 1, (t - 0.14) / 0.14);
  if (t < 0.42) return ease(1, 1.09, (t - 0.28) / 0.14);
  if (t < 0.70) return ease(1.09, 1, (t - 0.42) / 0.28);
  return 1;
}

/// One drifting emoji: where it starts (0–1 across, px below the bottom),
/// how far it sways and turns, and its period and delay in seconds.
class _Flyer {
  const _Flyer(
    this.emoji,
    this.x,
    this.y,
    this.size,
    this.dx,
    this.turn,
    this.period,
    this.delay,
  );

  final String emoji;
  final double x;
  final double y;
  final double size;
  final double dx;
  final double turn;
  final double period;
  final double delay;

  /// 0–1 through its rise at [clock] seconds.
  double at(double clock) => ((clock + delay) % period) / period;
}

/// About fourteen hearts across the whole screen, and five of the moment's
/// own emoji rising slower and larger through the middle (the canvas's
/// scatter, so every phone sees the same picture).
List<_Flyer> _scatter(VMoment m) => [
  for (var n = 0; n < 14; n++)
    _Flyer(
      m.hearts[n % m.hearts.length],
      ((n * 53 + 17) % 360) / 390,
      40.0 + (n % 3) * 20,
      18.0 + (n * 7) % 18,
      ((n * 37) % 120) - 60.0,
      ((n * 29) % 50) - 25.0,
      4.5 + (n % 4) * 0.8,
      (n * 0.63) % 5.5,
    ),
  for (var n = 0; n < 5; n++)
    _Flyer(
      m.emoji,
      (60.0 + n * 62) / 390,
      60,
      34.0 + (n % 2) * 10,
      ((n * 23) % 40) - 20.0,
      ((n * 13) % 16) - 8.0,
      7.0 + (n % 3),
      (n * 1.7) % 7,
    ),
];

class _FlyerLayout extends MultiChildLayoutDelegate {
  _FlyerLayout(this.flyers, this.clock);

  final List<_Flyer> flyers;
  final double clock;

  @override
  void performLayout(Size size) {
    for (var i = 0; i < flyers.length; i++) {
      final f = flyers[i];
      final t = Curves.easeOut.transform(f.at(clock));
      final s = layoutChild(i, BoxConstraints.loose(size));
      final rise = (size.height + 100) * t;
      positionChild(
        i,
        Offset(
          f.x * size.width + f.dx * t,
          size.height + f.y - rise - s.height,
        ),
      );
    }
  }

  @override
  bool shouldRelayout(_FlyerLayout old) => old.clock != clock;
}

class _FlyerView extends StatelessWidget {
  const _FlyerView(this.f, this.clock);

  final _Flyer f;
  final double clock;

  @override
  Widget build(BuildContext context) {
    final t = f.at(clock);
    final eased = Curves.easeOut.transform(t);
    final fade = t < 0.12
        ? t / 0.12
        : t > 0.8
        ? (1 - t) / 0.2
        : 1.0;
    return Opacity(
      opacity: fade.clamp(0.0, 1.0),
      child: Transform.rotate(
        angle: f.turn * eased * math.pi / 180,
        child: Transform.scale(
          scale: 0.5 + 0.65 * eased,
          child: Text(f.emoji, style: TextStyle(fontSize: f.size, height: 1)),
        ),
      ),
    );
  }
}
