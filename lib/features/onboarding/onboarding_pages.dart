import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/icons/v_icons.dart';
import '../../core/theme/v_colors.dart';
import '../../core/theme/v_palette.dart';
import '../../core/theme/v_text.dart';
import '../../core/widgets/v_buttons.dart';
import '../../core/widgets/v_glass.dart';
import '../../core/widgets/v_ink.dart';
import '../../core/widgets/v_list.dart';
import '../../core/widgets/v_surface.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../mock/mock_data.dart';
import '../common/art.dart';
import '../common/avatar.dart';
import '../common/dot_loader.dart';
import '../common/keypad.dart';
import '../common/parts.dart';
import '../common/toast.dart';
import 'step_page.dart';

/// Onboarding paths (outside the tabs).
abstract final class OnboardingRoutes {
  static const welcome = '/welcome';
  static const name = '/welcome/name';
  static const background = '/welcome/background';
  static const pair = '/welcome/pair';
  static const join = '/welcome/join';
  static const scan = '/welcome/scan';
  static const waiting = '/welcome/waiting';
  static const paired = '/paired';
}

/// C1: the wordmark over the wallpaper while Moose starts.
class SplashView extends StatelessWidget {
  const SplashView({super.key});

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      const Center(child: Wordmark(center: true)),
      Positioned(
        left: 0,
        right: 0,
        bottom: MediaQuery.paddingOf(context).bottom + 64,
        child: const Center(child: DotLoader()),
      ),
    ],
  );
}

/// C2.
class WelcomePage extends StatelessWidget {
  const WelcomePage({super.key});

  @override
  Widget build(BuildContext context) {
    Widget promise(VIcon icon, String text) => Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          VIconView(icon, size: 22),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: VText.inter(14, height: 1.4))),
        ],
      ),
    );
    final pad = MediaQuery.paddingOf(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(28, pad.top, 28, pad.bottom + 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Spacer(),
          const Wordmark(),
          const SizedBox(height: 22),
          Text(
            'A quiet, private chat for just the two of you.',
            style: VText.inter(20, weight: 300, height: 1.35),
          ),
          const SizedBox(height: 28),
          promise(
            VIcon.phoneDevice,
            'Messages live on your phones, not on a server.',
          ),
          promise(
            VIcon.lock,
            'Locked end to end, and with a PIN only you know.',
          ),
          promise(VIcon.poke, 'Pokes, doodles and songs, just between you.'),
          const Spacer(),
          VButton.primary(
            'Start',
            onPressed: () => context.push(OnboardingRoutes.name),
          ),
          const SizedBox(height: 12),
          VButton.secondary(
            'I have a code',
            onPressed: () => context.push('${OnboardingRoutes.name}?join=1'),
          ),
        ],
      ),
    );
  }
}

/// C3: your name and picture.
class NamePage extends ConsumerStatefulWidget {
  const NamePage({super.key, this.join = false});

  /// Came from "I have a code": pairing joins rather than creates.
  final bool join;

  @override
  ConsumerState<NamePage> createState() => _NamePageState();
}

class _NamePageState extends ConsumerState<NamePage> {
  late final _name = TextEditingController(
    text: ref.read(sessionProvider).name.isEmpty
        ? MockData.sapan.name
        : ref.read(sessionProvider).name,
  );
  var _photo = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final initial = _name.text.isEmpty ? '?' : _name.text[0].toUpperCase();
    return StepPage(
      back: 'Back',
      eyebrow: 'Step 1 of 3',
      title: "What's your name?",
      body: 'Only your person sees it.',
      step: 0,
      content: [
        const SizedBox(height: 22),
        Text('NAME', style: VText.eyebrow),
        const SizedBox(height: 8),
        VTextField(
          controller: _name,
          autofocus: true,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 22),
        Text('PICTURE', style: VText.eyebrow),
        const SizedBox(height: 10),
        Row(
          children: [
            _photo
                ? const ClipOval(child: ArtBox(art: 7, width: 84, height: 84))
                : Avatar(
                    Person(id: 'me', name: initial),
                    size: 84,
                    filled: true,
                  ),
            const SizedBox(width: 14),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                VPill(
                  'Use my initial',
                  fill: _photo ? VFill.outline : VFill.filled,
                  onTap: () => setState(() => _photo = false),
                ),
                const SizedBox(height: 10),
                VPill(
                  'Choose a photo',
                  fill: _photo ? VFill.filled : VFill.dashed,
                  onTap: () => setState(() => _photo = true),
                ),
              ],
            ),
          ],
        ),
      ],
      bottom: [
        VButton.primary(
          'Continue',
          enabled: _name.text.trim().isNotEmpty,
          onPressed: () {
            ref.read(sessionProvider.notifier).setName(_name.text.trim());
            // Best effort: pairing registers the name again anyway.
            unawaited(
              ref
                  .read(pairRepositoryProvider)
                  .setName(_name.text.trim())
                  .catchError((_) {}),
            );
            context.push(
              '${OnboardingRoutes.background}${widget.join ? '?join=1' : ''}',
            );
          },
        ),
      ],
    );
  }
}

/// C4: why Moose runs in the background, and the two permissions.
class BackgroundPage extends ConsumerStatefulWidget {
  const BackgroundPage({super.key, this.join = false});

  final bool join;

  @override
  ConsumerState<BackgroundPage> createState() => _BackgroundPageState();
}

class _BackgroundPageState extends ConsumerState<BackgroundPage> {
  // The mock shows notifications already allowed, as the canvas does.
  late var _notifications = !ref.read(onNeonProvider);
  var _battery = false;

  @override
  Widget build(BuildContext context) {
    Widget granted(bool on, VoidCallback allow) => on
        ? Semantics(
            label: 'Granted',
            child: Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: VInk.of(context),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: VIconView(
                  VIcon.check,
                  size: 16,
                  strokeWidth: 3,
                  color: VInk.surfaceOf(context),
                ),
              ),
            ),
          )
        : VPill('Allow', onTap: allow);
    final all = _notifications && _battery;
    return StepPage(
      back: 'Back',
      eyebrow: 'Step 2 of 3',
      title: 'Staying in touch',
      body:
          "Moose checks for new messages and pokes every 6 minutes, even when it's "
          'closed. Android asks for a small, quiet notification while it does.',
      step: 1,
      content: [
        const SizedBox(height: 18),
        VGlass(
          radius: 20,
          tint: VPalette.of(context).glassCard,
          blur: 16,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                SizedBox.square(
                  dimension: 36,
                  child: VOutlined(
                    radius: 10,
                    child: Center(
                      child: Text('M', style: VText.doto(16, weight: 900)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Moose', style: VText.inter(14, weight: 500)),
                      Text('Keeping in touch · quiet', style: VText.secondary),
                    ],
                  ),
                ),
                Text('now', style: VText.secondary),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            'This is the notification. It makes no sound and you can hide it from '
            "Android's notification settings.",
            style: VText.secondary,
          ),
        ),
        const SizedBox(height: 14),
        VListSection(
          children: [
            VListRow(
              title: 'Notifications',
              subtitle: 'For pokes and messages',
              trailing: granted(_notifications, () async {
                final ok = await ref.read(askNotificationsProvider)();
                if (mounted) setState(() => _notifications = ok);
              }),
            ),
            VListRow(
              title: 'Run in the background',
              subtitle: "Battery: don't optimise Moose",
              trailing: granted(_battery, () {
                HapticFeedback.selectionClick();
                setState(() => _battery = true);
              }),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.only(left: 4),
          child: Text(
            '${(_notifications ? 1 : 0) + (_battery ? 1 : 0)} of 2 allowed',
            style: VText.secondary,
          ),
        ),
      ],
      bottom: [
        if (all)
          VButton.primary(
            'Continue',
            onPressed: () => context.push(
              widget.join ? OnboardingRoutes.join : OnboardingRoutes.pair,
            ),
          )
        else
          VButton.ghost(
            'Continue',
            onPressed: () => context.push(
              widget.join ? OnboardingRoutes.join : OnboardingRoutes.pair,
            ),
          ),
      ],
    );
  }
}

/// A QR code drawn in black on a white card (always: scanners need it).
class QrCard extends StatelessWidget {
  const QrCard({super.key, required this.data, this.size = 147});

  final String data;
  final double size;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'QR code for $data',
    child: Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: VColors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: VInk.of(context)),
      ),
      child: SizedBox.square(
        dimension: size,
        child: CustomPaint(painter: _QrPainter(data.hashCode)),
      ),
    ),
  );
}

class _QrPainter extends CustomPainter {
  _QrPainter(this.seed);

  final int seed;

  @override
  void paint(Canvas canvas, Size size) {
    const n = 21;
    final cell = size.width / n;
    final p = Paint()..color = VColors.black;
    bool? finder(int x, int y) {
      for (final (ox, oy) in [(0, 0), (14, 0), (0, 14)]) {
        final dx = x - ox, dy = y - oy;
        if (dx >= 0 && dx < 7 && dy >= 0 && dy < 7) {
          return dx == 0 ||
              dx == 6 ||
              dy == 0 ||
              dy == 6 ||
              (dx >= 2 && dx <= 4 && dy >= 2 && dy <= 4);
        }
      }
      return null;
    }

    for (var y = 0; y < n; y++) {
      for (var x = 0; x < n; x++) {
        final f = finder(x, y);
        final on = f ?? ((x * 7 + y * 13 + x * y * 3 + seed) % 5 < 2);
        if (on) {
          canvas.drawRect(Rect.fromLTWH(x * cell, y * cell, cell, cell), p);
        }
      }
    }
  }

  @override
  bool shouldRepaint(_QrPainter old) => old.seed != seed;
}

/// C5: show your code; your person types or scans it. The server makes the
/// code and says when they've joined; the mock Aatika joins after
/// [joinsAfter].
class CreatePairPage extends ConsumerStatefulWidget {
  const CreatePairPage({
    super.key,
    this.joinsAfter = const Duration(seconds: 4),
  });

  final Duration joinsAfter;

  @override
  ConsumerState<CreatePairPage> createState() => _CreatePairPageState();
}

class _CreatePairPageState extends ConsumerState<CreatePairPage> {
  var _left = const Duration(minutes: 10);
  Timer? _clock;
  StreamSubscription<Pairing>? _wait;
  String? _code;
  String? _error;

  @override
  void initState() {
    super.initState();
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _code == null) return;
      setState(() => _left -= const Duration(seconds: 1));
      if (_left <= Duration.zero) unawaited(_start());
    });
    unawaited(_start());
  }

  /// Gets a code, then waits for your person to join it.
  Future<void> _start() async {
    final repo = ref.read(pairRepositoryProvider);
    setState(() {
      _code = null;
      _error = null;
      _left = const Duration(minutes: 10);
    });
    try {
      final code = await repo.invite();
      if (!mounted) return;
      setState(() => _code = code);
      await _wait?.cancel();
      _wait = repo
          .waitForPartner(mockAfter: widget.joinsAfter)
          .listen(
            (pairing) {
              if (!mounted) return;
              unawaited(HapticFeedback.heavyImpact());
              ref.read(pairingProvider.notifier).set(pairing);
              ref.read(sessionProvider.notifier).pair();
              context.go(OnboardingRoutes.paired);
            },
            onError: (Object _) {
              if (mounted) {
                setState(
                  () => _error = "Couldn't reach Moose's server. Tap to retry.",
                );
              }
            },
          );
    } on Object {
      if (mounted) {
        setState(() => _error = "Couldn't reach Moose's server. Tap to retry.");
      }
    }
  }

  @override
  void dispose() {
    _clock?.cancel();
    unawaited(_wait?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final code = _code ?? '······';
    return StepPage(
      back: 'Back',
      eyebrow: 'Step 3 of 3',
      title: 'Pair with your person',
      body: 'Show them this code, or send it. It works once.',
      content: [
        const SizedBox(height: 18),
        Center(
          child: Text(
            code,
            style: VText.doto(52, weight: 900, height: 1, letterSpacing: 3),
          ),
        ),
        const SizedBox(height: 10),
        Center(child: QrCard(data: code)),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _SmallButton(
                VIcon.share,
                'Share',
                () => HapticFeedback.selectionClick(),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _SmallButton(VIcon.copy, 'Copy', () async {
                await Clipboard.setData(ClipboardData(text: code));
                if (context.mounted) showToast(context, 'Code copied');
              }),
            ),
          ],
        ),
      ],
      bottom: [
        if (_error != null)
          GestureDetector(onTap: _start, child: InlineError(_error!))
        else
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const DotLoader(),
              const SizedBox(width: 10),
              Text(
                'Waiting for your person',
                style: VText.inter(14, weight: 500),
              ),
            ],
          ),
        Text.rich(
          TextSpan(
            children: [
              const TextSpan(text: 'Expires in '),
              TextSpan(text: mss(_left), style: VText.doto(13)),
            ],
          ),
          style: VText.secondary,
        ),
      ],
    );
  }
}

class _SmallButton extends StatelessWidget {
  const _SmallButton(this.icon, this.label, this.onTap);

  final VIcon icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: label,
    excludeSemantics: true,
    child: VTappable(
      onTap: onTap,
      child: VOutlined(
        radius: 999,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 11),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              VIconView(icon, size: 18),
              const SizedBox(width: 8),
              Text(label, style: VText.inter(14, weight: 500)),
            ],
          ),
        ),
      ),
    ),
  );
}

/// C6: type their code (or scan it).
class JoinPage extends ConsumerStatefulWidget {
  const JoinPage({super.key});

  @override
  ConsumerState<JoinPage> createState() => _JoinPageState();
}

class _JoinPageState extends ConsumerState<JoinPage> {
  final _code = TextEditingController();
  final _focus = FocusNode();
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    _focus.dispose();
    super.dispose();
  }

  var _joining = false;

  Future<void> _join(String code) async {
    if (code == MockData.repairCode && !ref.read(onNeonProvider)) {
      context.go(OnboardingRoutes.waiting);
      return;
    }
    setState(() => _joining = true);
    String? error;
    try {
      final pairing = await ref.read(pairRepositoryProvider).join(code);
      if (!mounted) return;
      if (pairing != null) {
        ref.read(pairingProvider.notifier).set(pairing);
        ref.read(sessionProvider.notifier).pair();
        context.go(OnboardingRoutes.paired);
        return;
      }
      error = 'That code has expired. Ask for a new one.';
    } on Object {
      error = "Couldn't reach Moose's server. Try again.";
    }
    if (!mounted) return;
    unawaited(HapticFeedback.heavyImpact());
    setState(() {
      _joining = false;
      _error = error;
    });
  }

  @override
  Widget build(BuildContext context) {
    final code = _code.text.toUpperCase();
    return StepPage(
      back: 'Back',
      eyebrow: 'Step 3 of 3',
      title: 'Enter their code',
      body: 'Six letters and numbers, from their Moose.',
      content: [
        const SizedBox(height: 24),
        GestureDetector(
          onTap: () => _focus.requestFocus(),
          child: Stack(
            children: [
              CodeBoxes(code: code),
              // An invisible field takes the typing; the boxes show it.
              Positioned.fill(
                child: Opacity(
                  opacity: 0,
                  child: CupertinoTextField(
                    controller: _code,
                    focusNode: _focus,
                    autofocus: true,
                    maxLength: 6,
                    textCapitalization: TextCapitalization.characters,
                    onChanged: (_) => setState(() => _error = null),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 10),
          InlineError(_error!),
        ],
        const SizedBox(height: 24),
        _SmallButton(
          VIcon.qr,
          'Scan their QR instead',
          () => context.push(OnboardingRoutes.scan),
        ),
      ],
      bottom: [
        VButton.primary(
          'Join',
          enabled: code.length == 6 && !_joining,
          onPressed: () => _join(code),
        ),
      ],
    );
  }
}

/// C7: point at their QR. Always dark, it's a viewfinder; tap reads it in
/// the mock.
class ScanPage extends ConsumerWidget {
  const ScanPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pad = MediaQuery.paddingOf(context);
    return VInkScope(
      ink: VColors.white,
      child: GestureDetector(
        onTap: () {
          if (ref.read(onNeonProvider)) {
            // The camera reader isn't in yet: type the code.
            showToast(context, 'Type their code for now');
            context.pop();
            return;
          }
          HapticFeedback.heavyImpact();
          ref.read(sessionProvider.notifier).pair();
          context.go(OnboardingRoutes.paired);
        },
        child: ColoredBox(
          color: VColors.black,
          child: Stack(
            fit: StackFit.expand,
            children: [
              const ArtBox(
                art: 3,
                begin: Alignment.center,
                end: Alignment.bottomRight,
              ),
              ColoredBox(color: VColors.black.withValues(alpha: 0.4)),
              Center(
                child: SizedBox.square(
                  dimension: 240,
                  child: CustomPaint(painter: _Corners()),
                ),
              ),
              Positioned(
                left: 16,
                top: pad.top + 12,
                child: VCircleButton(
                  icon: VIcon.close,
                  size: 44,
                  onTap: () => context.pop(),
                ),
              ),
              Positioned(
                left: 24,
                right: 24,
                bottom: pad.bottom + 64,
                child: Column(
                  children: [
                    Text(
                      'Point at the code on their phone',
                      style: VText.inter(15, weight: 500),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'It joins as soon as it reads it.',
                      style: VText.secondary,
                    ),
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

class _Corners extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = VColors.white
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    const l = 44.0, r = 20.0;
    final w = size.width, h = size.height;
    for (final (x, y, sx, sy) in [
      (0.0, 0.0, 1, 1),
      (w, 0.0, -1, 1),
      (0.0, h, 1, -1),
      (w, h, -1, -1),
    ]) {
      canvas.drawPath(
        Path()
          ..moveTo(x, y + sy * l)
          ..lineTo(x, y + sy * r)
          ..quadraticBezierTo(x, y, x + sx * r, y)
          ..lineTo(x + sx * l, y),
        p,
      );
    }
  }

  @override
  bool shouldRepaint(_Corners old) => false;
}

/// The twelve groups of a security code, four to a row.
class SecurityCode extends StatelessWidget {
  const SecurityCode(this.groups, {super.key});

  final List<String> groups;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Security code ${groups.join(' ')}',
    excludeSemantics: true,
    child: Column(
      children: [
        for (var r = 0; r < 3; r++) ...[
          if (r > 0) const SizedBox(height: 10),
          Row(
            children: [
              for (final g in groups.skip(r * 4).take(4))
                Expanded(
                  child: Text(
                    g,
                    textAlign: TextAlign.center,
                    style: VText.doto(17),
                  ),
                ),
            ],
          ),
        ],
      ],
    ),
  );
}

/// C8: paired, and the code to compare.
class PairedPage extends ConsumerWidget {
  const PairedPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final pairing = ref.watch(pairingProvider);
    final me = session.name.isEmpty
        ? pairing.me
        : pairing.me.copyWith(name: session.name);
    final ink = VInk.of(context);
    return StepPage(
      top: 96,
      center: true,
      leading: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Avatar(me, size: 72, filled: true),
          Container(width: 34, height: 1, color: ink),
          const VIconView(VIcon.hug, size: 28),
          Container(width: 34, height: 1, color: ink),
          Avatar(pairing.partner, size: 72),
        ],
      ),
      title: '${me.name} & ${pairing.partner.name}',
      titleStyle: VText.doto(44, weight: 900, height: 1),
      body: 'Paired. Everything you send is locked for just the two of you.',
      content: [
        const SizedBox(height: 22),
        VGlass(
          radius: 20,
          tint: VPalette.of(context).glassCard,
          blur: 16,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('SECURITY CODE', style: VText.eyebrow),
                const SizedBox(height: 12),
                SecurityCode(pairing.securityCode),
                const SizedBox(height: 12),
                Text(
                  "Compare with ${pairing.partner.name}'s screen. If they match, nobody is in between.",
                  style: VText.secondary,
                ),
              ],
            ),
          ),
        ),
      ],
      bottom: [
        VButton.primary(
          'Start chatting',
          onPressed: () {
            if (session.name.isNotEmpty) {
              ref.read(pairingProvider.notifier).rename(session.name);
            }
            context.go('/chat');
          },
        ),
      ],
    );
  }
}

/// C9: your partner has a new phone; approve it only if it's her.
class RepairRequestPage extends ConsumerWidget {
  const RepairRequestPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final partner = ref.watch(pairingProvider).partner.name;
    return Stack(
      fit: StackFit.expand,
      children: [
        Builder(
          builder: (context) => ColoredBox(color: VPalette.of(context).veil),
        ),
        StepPage(
          top: 96,
          eyebrow: 'New phone',
          title: '$partner has a new phone',
          body:
              "Her old one is gone, so Moose made her a new key. Only approve if you're "
              'sure it\'s $partner. A quick call is the easiest way to check.',
          content: [
            const SizedBox(height: 18),
            VGlass(
              radius: 20,
              tint: VPalette.of(context).glassCard,
              blur: 16,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('NEW SECURITY CODE', style: VText.eyebrow),
                    const SizedBox(height: 12),
                    const SecurityCode(MockData.newSecurityCode),
                    const SizedBox(height: 12),
                    Text(
                      'Ask $partner to read hers out. Every group should match.',
                      style: VText.secondary,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Text(
                "Your history stays here. $partner's new phone starts empty.",
                style: VText.secondary,
              ),
            ),
          ],
          bottom: [
            VButton.primary(
              "It's $partner, approve",
              onPressed: () => Navigator.of(context).pop(true),
            ),
            VButton.ghost(
              'Not them',
              onPressed: () => Navigator.of(context).pop(false),
            ),
          ],
        ),
      ],
    );
  }
}

/// C10: on the new phone, waiting for the partner to approve. In the mock
/// she approves after a few seconds.
class RepairWaitingPage extends ConsumerStatefulWidget {
  const RepairWaitingPage({
    super.key,
    this.approvesAfter = const Duration(seconds: 5),
  });

  final Duration approvesAfter;

  @override
  ConsumerState<RepairWaitingPage> createState() => _RepairWaitingPageState();
}

class _RepairWaitingPageState extends ConsumerState<RepairWaitingPage> {
  Timer? _approved;

  @override
  void initState() {
    super.initState();
    _approved = Timer(widget.approvesAfter, () {
      if (!mounted) return;
      ref.read(sessionProvider.notifier).pair();
      context.go(OnboardingRoutes.paired);
    });
  }

  @override
  void dispose() {
    _approved?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(pairingProvider).me.name;
    return StepPage(
      top: 96,
      eyebrow: 'Welcome back',
      title: 'Ask $me to approve',
      body:
          "We've sent a request to $me's phone. It reaches him within about 6 minutes, "
          'or straight away if Moose is open.',
      content: [
        const SizedBox(height: 16),
        Row(
          children: [
            const DotLoader(),
            const SizedBox(width: 10),
            Text('Waiting for $me', style: VText.inter(14, weight: 500)),
          ],
        ),
        const SizedBox(height: 16),
        VGlass(
          radius: 20,
          tint: VPalette.of(context).glassCard,
          blur: 16,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('YOUR SECURITY CODE', style: VText.eyebrow),
                const SizedBox(height: 12),
                const SecurityCode(MockData.newSecurityCode),
              ],
            ),
          ),
        ),
      ],
      bottom: [
        VButton.ghost(
          'Cancel',
          onPressed: () => context.go(OnboardingRoutes.welcome),
        ),
      ],
    );
  }
}
