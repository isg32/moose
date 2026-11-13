import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/v_palette.dart';
import '../../core/theme/v_text.dart';
import '../../core/widgets/v_buttons.dart';
import '../../core/widgets/v_glass.dart';
import '../../core/widgets/v_page.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../data/session.dart';
import '../common/avatar.dart';
import '../common/keypad.dart';
import '../common/parts.dart';
import '../onboarding/step_page.dart';

/// Shakes its child sideways when [shakes] changes (a wrong PIN).
class _Shake extends StatefulWidget {
  const _Shake({required this.shakes, required this.child});

  final int shakes;
  final Widget child;

  @override
  State<_Shake> createState() => _ShakeState();
}

class _ShakeState extends State<_Shake> with SingleTickerProviderStateMixin {
  late final _t = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );

  @override
  void didUpdateWidget(_Shake old) {
    super.didUpdateWidget(old);
    if (old.shakes != widget.shakes) _t.forward(from: 0);
  }

  @override
  void dispose() {
    _t.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _t,
    builder: (context, child) => Transform.translate(
      offset: Offset(math.sin(_t.value * math.pi * 6) * 10 * (1 - _t.value), 0),
      child: child,
    ),
    child: widget.child,
  );
}

/// C13: Moose is locked. The PIN opens it; the decoy PIN opens the empty
/// decoy chat; five wrong tries mean a 30 s wait.
class LockScreen extends ConsumerStatefulWidget {
  const LockScreen({super.key});

  @override
  ConsumerState<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends ConsumerState<LockScreen> {
  var _typed = '';
  var _shakes = 0;
  var _wrong = false;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && ref.read(sessionProvider).waitUntil != null) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  void _digit(String d, int length) {
    if (_typed.length >= length) return;
    setState(() {
      _typed += d;
      _wrong = false;
    });
    if (_typed.length < length) return;
    final r = ref.read(sessionProvider.notifier).unlock(_typed);
    if (r == Unlock.wrong || r == Unlock.waiting) {
      HapticFeedback.heavyImpact();
      setState(() {
        _shakes++;
        _wrong = true;
        _typed = '';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    final length = math.max(4, session.pin.length);
    final until = session.waitUntil;
    final wait = until == null
        ? Duration.zero
        : until.difference(DateTime.now());
    final String? note = wait > Duration.zero
        ? 'Too many tries · try again in ${wait.inSeconds + 1}s'
        : _wrong
        ? 'Wrong PIN · ${session.triesLeft} tr${session.triesLeft == 1 ? 'y' : 'ies'} left before a 30 s wait'
        : null;
    final pad = MediaQuery.paddingOf(context);
    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          child: VEdgeBlur(edge: VEdge.top, solid: pad.top, fade: 40),
        ),
        Column(
          children: [
            SizedBox(height: pad.top + 96),
            const Wordmark(size: 28, center: true),
            const SizedBox(height: 28),
            Text('Enter your PIN', style: VText.inter(15, weight: 500)),
            const SizedBox(height: 16),
            _Shake(
              shakes: _shakes,
              child: PinDots(
                filled: _typed.length,
                length: length,
                error: _wrong,
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 18,
              child: note == null ? null : Text(note, style: VText.secondary),
            ),
            const Spacer(),
            Opacity(
              opacity: wait > Duration.zero ? 0.35 : 1,
              child: IgnorePointer(
                ignoring: wait > Duration.zero,
                child: Keypad(
                  onDigit: (d) => _digit(d, length),
                  onDelete: () => setState(
                    () => _typed = _typed.isEmpty
                        ? ''
                        : _typed.substring(0, _typed.length - 1),
                  ),
                ),
              ),
            ),
            SizedBox(height: pad.bottom + 48),
          ],
        ),
      ],
    );
  }
}

/// Type a PIN twice (C11, and the decoy's in C12). Returns it.
class PinEntryPage extends StatefulWidget {
  const PinEntryPage({
    super.key,
    required this.eyebrow,
    required this.back,
    this.mustDiffer,
  });

  final String eyebrow;
  final String back;

  /// The real PIN, which the decoy may not be.
  final String? mustDiffer;

  @override
  State<PinEntryPage> createState() => _PinEntryPageState();
}

class _PinEntryPageState extends State<PinEntryPage> {
  static const _length = 4;
  var _first = '';
  var _typed = '';
  String? _error;
  var _shakes = 0;

  void _digit(String d) {
    if (_typed.length >= _length) return;
    setState(() {
      _typed += d;
      _error = null;
    });
    if (_typed.length < _length) return;
    if (_first.isEmpty) {
      if (_typed == widget.mustDiffer) {
        _fail('It has to be different from your real PIN.');
        return;
      }
      setState(() {
        _first = _typed;
        _typed = '';
      });
      return;
    }
    if (_typed == _first) {
      HapticFeedback.mediumImpact();
      Navigator.of(context).pop(_typed);
    } else {
      _fail("Those didn't match. Try again.");
      setState(() => _first = '');
    }
  }

  void _fail(String why) {
    HapticFeedback.heavyImpact();
    setState(() {
      _error = why;
      _typed = '';
      _shakes++;
    });
  }

  @override
  Widget build(BuildContext context) {
    final confirming = _first.isNotEmpty;
    final pad = MediaQuery.paddingOf(context);
    return Stack(
      fit: StackFit.expand,
      children: [
        const VVeil(),
        Padding(
          padding: EdgeInsets.fromLTRB(20, pad.top + 16, 20, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              VLink(
                '‹ ${widget.back}',
                style: VText.inter(14),
                onTap: () => Navigator.of(context).pop(),
              ),
              const SizedBox(height: 12),
              Text(
                '${widget.eyebrow} · ${confirming ? 2 : 1} of 2'.toUpperCase(),
                style: VText.eyebrow,
              ),
              const SizedBox(height: 8),
              Text(
                confirming ? 'Type it again' : 'Choose a PIN',
                style: VText.title,
              ),
              const SizedBox(height: 8),
              Text(
                "4 to 6 digits. You'll need it every time you open Moose.",
                style: VText.inter(14, weight: 300),
              ),
              const SizedBox(height: 40),
              Center(
                child: _Shake(
                  shakes: _shakes,
                  child: PinDots(
                    filled: _typed.length,
                    error: _error != null && _typed.isEmpty,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              if (_error != null) Center(child: InlineErrorCentered(_error!)),
            ],
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: pad.bottom + 48,
          child: Keypad(
            onDigit: _digit,
            onDelete: () => setState(
              () => _typed = _typed.isEmpty
                  ? ''
                  : _typed.substring(0, _typed.length - 1),
            ),
          ),
        ),
      ],
    );
  }
}

/// An inline error, centred under the PIN dots.
class InlineErrorCentered extends StatelessWidget {
  const InlineErrorCentered(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) =>
      IntrinsicWidth(child: InlineError(text));
}

/// C12: explain the decoy, name its made-up person, then choose its PIN.
class DecoyPinPage extends ConsumerStatefulWidget {
  const DecoyPinPage({super.key});

  @override
  ConsumerState<DecoyPinPage> createState() => _DecoyPinPageState();
}

class _DecoyPinPageState extends ConsumerState<DecoyPinPage> {
  late final _name = TextEditingController(
    text: ref.read(sessionProvider).decoyName,
  );

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _choose() async {
    final pin = await Navigator.of(context).push<String>(
      PageRouteBuilder(
        opaque: false,
        pageBuilder: (_, _, _) => PinEntryPage(
          eyebrow: 'Decoy PIN',
          back: 'Decoy',
          mustDiffer: ref.read(sessionProvider).pin,
        ),
      ),
    );
    if (pin == null || !mounted) return;
    ref
        .read(sessionProvider.notifier)
        .setDecoy(pin, _name.text.trim().isEmpty ? 'Neha' : _name.text.trim());
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final name = _name.text.trim().isEmpty ? 'Neha' : _name.text.trim();
    return Stack(
      fit: StackFit.expand,
      children: [
        const VVeil(),
        StepPage(
          back: 'Privacy',
          onBack: () => Navigator.of(context).pop(),
          eyebrow: 'Optional',
          title: 'A decoy PIN',
          body:
              'If anyone makes you open Moose, type this one instead. It opens an empty chat '
              'that looks real, and nothing in it can be sent.',
          content: [
            const SizedBox(height: 16),
            VGlass(
              radius: 20,
              tint: VPalette.of(context).glassCard,
              blur: 16,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("WHAT THEY'LL SEE", style: VText.eyebrow),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Avatar(Person(id: 'decoy', name: name)),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(name, style: VText.inter(15, weight: 600)),
                            Text('last seen yesterday', style: VText.secondary),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'An empty chat with a made-up name. You can rename it.',
                      style: VText.inter(13, weight: 300),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text('DECOY NAME', style: VText.eyebrow),
            const SizedBox(height: 8),
            VTextField(controller: _name, onChanged: (_) => setState(() {})),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Text(
                'It has to be different from your real PIN.',
                style: VText.secondary,
              ),
            ),
          ],
          bottom: [
            VButton.primary('Choose decoy PIN', onPressed: _choose),
            VButton.ghost(
              'Not now',
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ],
    );
  }
}
