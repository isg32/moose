import 'package:flutter/widgets.dart';

import '../../core/icons/v_icons.dart';
import '../../core/theme/v_colors.dart';
import '../../core/theme/v_text.dart';
import '../../core/theme/v_tokens.dart';
import '../../core/widgets/v_buttons.dart';
import '../../core/widgets/v_glass.dart';
import '../../core/widgets/v_ink.dart';
import '../../core/widgets/v_surface.dart';
import '../../data/models.dart';

/// The delivery mark after a sent message's time (B): a clock while
/// sending, ✓ sent, ✓✓ delivered, a bold ✓✓ when seen.
class DeliveryTicks extends StatelessWidget {
  const DeliveryTicks(this.delivery, {super.key, this.size = 15});

  final Delivery delivery;
  final double size;

  @override
  Widget build(BuildContext context) {
    final (icon, stroke, label) = switch (delivery) {
      Delivery.pending => (VIcon.pending, 1.5, 'Sending'),
      Delivery.sent => (VIcon.check, 1.5, 'Sent'),
      Delivery.delivered => (VIcon.doubleCheck, 1.5, 'Delivered'),
      Delivery.seen => (VIcon.doubleCheck, 2.6, 'Seen'),
      Delivery.failed => (VIcon.warning, 1.5, 'Not sent'),
    };
    return Semantics(
      label: label,
      child: VIconView(icon, size: size, strokeWidth: stroke),
    );
  }
}

/// Three dots, the first solid: "typing…" (A8).
class TypingDots extends StatefulWidget {
  const TypingDots({super.key, this.size = 7});

  final double size;

  @override
  State<TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<TypingDots>
    with SingleTickerProviderStateMixin {
  late final _t = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();

  @override
  void dispose() {
    _t.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ink = VInk.of(context);
    return AnimatedBuilder(
      animation: _t,
      builder: (context, _) {
        final lit = (_t.value * 3).floor() % 3;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < 3; i++) ...[
              if (i > 0) SizedBox(width: widget.size * 0.6),
              Container(
                width: widget.size,
                height: widget.size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: ink.withValues(alpha: i == lit ? 1 : 0.35),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

/// A voice note's bars; those before [played] (0–1) are full ink.
class WaveBars extends StatelessWidget {
  const WaveBars(
    this.wave, {
    super.key,
    this.played = 0,
    this.height = 28,
    this.barWidth = 3,
    this.gap = 2,
  });

  final List<double> wave;
  final double played;
  final double height;
  final double barWidth;
  final double gap;

  @override
  Widget build(BuildContext context) {
    final ink = VInk.of(context);
    final cut = (wave.length * played).floor();
    return SizedBox(
      height: height,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < wave.length; i++) ...[
            if (i > 0) SizedBox(width: gap),
            Container(
              width: barWidth,
              height: (wave[i] * height).clamp(3.0, height),
              decoration: BoxDecoration(
                color: ink.withValues(alpha: i < cut || played == 0 ? 1 : 0.35),
                borderRadius: BorderRadius.circular(barWidth),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// A centred glass pill in the chat (B11): dates, theme changes, calls.
class SystemPill extends StatelessWidget {
  const SystemPill({
    super.key,
    required this.child,
    this.dashed = false,
    this.tint,
    this.borderColor,
    this.padding = const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    this.radius = VRadius.pill,
  });

  final Widget child;
  final bool dashed;

  /// A moment's tint instead of glass.
  final Color? tint;
  final Color? borderColor;
  final EdgeInsetsGeometry padding;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final inner = VOutlined(
      radius: radius,
      outline: dashed ? VOutline.dashed : VOutline.solid,
      color: borderColor,
      fill: tint ?? VColors.transparent,
      child: Padding(
        padding: padding,
        child: DefaultTextStyle.merge(
          style: VText.inter(12, weight: 500),
          child: child,
        ),
      ),
    );
    if (tint != null) return inner;
    return VGlass(radius: radius, border: false, blur: 16, child: inner);
  }
}

/// "TODAY", "3 UNREAD": a label between dashed rules.
class RuleLabel extends StatelessWidget {
  const RuleLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(child: _Dash()),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Text(text.toUpperCase(), style: VText.eyebrow),
        ),
        const Expanded(child: _Dash()),
      ],
    );
  }
}

class _Dash extends StatelessWidget {
  const _Dash();

  @override
  Widget build(BuildContext context) {
    final ink = VInk.of(context);
    return LayoutBuilder(
      builder: (context, box) {
        final n = (box.maxWidth / 7).floor();
        return Row(
          children: [
            for (var i = 0; i < n; i++)
              Container(
                width: 4,
                height: 1,
                margin: const EdgeInsets.only(right: 3),
                color: ink,
              ),
          ],
        );
      },
    );
  }
}

/// A dashed card for "nothing here yet" (A5): a Doto line, a secondary
/// line, and an optional action.
class EmptyCard extends StatelessWidget {
  const EmptyCard({
    super.key,
    required this.title,
    required this.body,
    this.action,
    this.onAction,
  });

  final String title;
  final String body;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return VCard(
      outline: VOutline.dashed,
      padding: const EdgeInsets.all(22),
      child: Column(
        children: [
          Text(title, style: VText.doto(22), textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text(body, style: VText.secondary, textAlign: TextAlign.center),
          if (action != null) ...[
            const SizedBox(height: 12),
            VPill(action!, onTap: onAction),
          ],
        ],
      ),
    );
  }
}

/// An inline problem: a warning mark and one line (A7).
class InlineError extends StatelessWidget {
  const InlineError(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      const VIconView(VIcon.warning, size: 18),
      const SizedBox(width: 8),
      Expanded(child: Text(text, style: VText.inter(13, weight: 500))),
    ],
  );
}

/// A small ink badge with a count, e.g. unread on the jump button.
class CountBadge extends StatelessWidget {
  const CountBadge(this.count, {super.key});

  final int count;

  @override
  Widget build(BuildContext context) {
    final ink = VInk.of(context);
    return Container(
      constraints: const BoxConstraints(minWidth: 20),
      height: 20,
      padding: const EdgeInsets.symmetric(horizontal: 5),
      decoration: BoxDecoration(
        color: ink,
        borderRadius: BorderRadius.circular(10),
      ),
      alignment: Alignment.center,
      child: Text(
        '$count',
        style: VText.inter(
          11,
          weight: 600,
        ).copyWith(color: VInk.surfaceOf(context)),
      ),
    );
  }
}

/// Formats a clip or call length as m:ss.
String mss(Duration d) =>
    '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

/// hh:mm.
String hhmm(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

/// 2.4 MB, 820 MB, 1.4 GB.
String bytes(int b) {
  if (b >= 1000 * 1000 * 1000) {
    return '${(b / 1e9).toStringAsFixed(1)} GB';
  }
  if (b >= 10 * 1000 * 1000) return '${(b / 1e6).round()} MB';
  return '${(b / 1e6).toStringAsFixed(1)} MB';
}
