import 'package:flutter/widgets.dart';

import '../../core/theme/v_text.dart';
import '../../core/widgets/v_buttons.dart';
import '../../core/widgets/v_glass.dart';
import '../../core/widgets/v_ink.dart';

/// The frame onboarding, pairing and lock steps share (C2–C12): on the
/// wallpaper under the top blur, a back link, an eyebrow, a Doto title and
/// a line, the step's content, then step dots and its buttons at the
/// bottom.
class StepPage extends StatelessWidget {
  const StepPage({
    super.key,
    required this.title,
    required this.content,
    this.eyebrow,
    this.body,
    this.back,
    this.onBack,
    this.step,
    this.steps = 3,
    this.bottom = const [],
    this.top = 56,
    this.center = false,
    this.leading,
    this.titleStyle,
  });

  /// Above the heading (the avatars on Paired).
  final Widget? leading;
  final TextStyle? titleStyle;

  final String title;
  final String? eyebrow;
  final String? body;

  /// "‹ Back" label, or null for none.
  final String? back;
  final VoidCallback? onBack;

  /// Which dot is long (0-based), or null for no dots.
  final int? step;
  final int steps;

  /// What sits under the heading.
  final List<Widget> content;
  final List<Widget> bottom;
  final double top;

  /// Centre the heading (Paired, re-pair).
  final bool center;

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.paddingOf(context);
    return Stack(
      fit: StackFit.expand,
      children: [
        SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(20, pad.top + top, 20, 200 + pad.bottom),
          child: Column(
            crossAxisAlignment: center
                ? CrossAxisAlignment.center
                : CrossAxisAlignment.stretch,
            children: [
              if (back != null) ...[
                Align(
                  alignment: Alignment.centerLeft,
                  child: VLink(
                    '‹ $back',
                    style: VText.inter(14),
                    onTap: onBack ?? () => Navigator.of(context).maybePop(),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              if (leading != null) ...[leading!, const SizedBox(height: 18)],
              if (eyebrow != null) ...[
                Text(
                  eyebrow!.toUpperCase(),
                  style: VText.eyebrow,
                  textAlign: center ? TextAlign.center : TextAlign.start,
                ),
                const SizedBox(height: 8),
              ],
              Text(
                title,
                style: VText.title,
                textAlign: center ? TextAlign.center : TextAlign.start,
              ),
              if (body != null) ...[
                const SizedBox(height: 8),
                Text(
                  body!,
                  style: VText.inter(14, weight: 300, height: 1.4),
                  textAlign: center ? TextAlign.center : TextAlign.start,
                ),
              ],
              ...content,
            ],
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          child: VEdgeBlur(edge: VEdge.top, solid: pad.top, fade: 40),
        ),
        Positioned(
          left: 24,
          right: 24,
          bottom: pad.bottom + 40,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (step != null) ...[
                StepDots(index: step!, count: steps),
                const SizedBox(height: 18),
              ],
              for (final (i, b) in bottom.indexed) ...[
                if (i > 0) const SizedBox(height: 12),
                b,
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Step dots: the current one long and filled, the rest small (Veronica).
class StepDots extends StatelessWidget {
  const StepDots({super.key, required this.index, required this.count});

  final int index;
  final int count;

  @override
  Widget build(BuildContext context) {
    final ink = VInk.of(context);
    return Semantics(
      label: 'Step ${index + 1} of $count',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < count; i++) ...[
            if (i > 0) const SizedBox(width: 6),
            Container(
              width: i == index ? 18 : 6,
              height: 6,
              decoration: BoxDecoration(
                color: i <= index ? ink : null,
                border: i <= index ? null : Border.all(color: ink),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The wordmark: MO / OSE in Doto 900.
class Wordmark extends StatelessWidget {
  const Wordmark({super.key, this.size = 62, this.center = false});

  final double size;
  final bool center;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Moose',
    excludeSemantics: true,
    child: Text(
      'MO\nOSE',
      textAlign: center ? TextAlign.center : TextAlign.start,
      style: VText.doto(
        size,
        weight: 900,
        height: 0.9,
        letterSpacing: -size * 0.02,
      ),
    ),
  );
}
