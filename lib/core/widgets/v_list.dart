import 'package:flutter/widgets.dart';

import '../icons/v_icons.dart';
import '../theme/v_text.dart';
import '../theme/v_tokens.dart';
import 'v_buttons.dart';
import 'v_surface.dart';

/// Uppercase, tracked label above a card's content, with an optional trailing
/// widget on the right ("All 6 ›", "avg 2h 42m a day").
class VEyebrow extends StatelessWidget {
  const VEyebrow(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(child: Text(text.toUpperCase(), style: VText.eyebrow)),
        ?trailing,
      ],
    );
  }
}

/// Secondary text on the right of an eyebrow.
class VEyebrowNote extends StatelessWidget {
  const VEyebrowNote(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) =>
      Text(text, style: VText.inter(12, weight: 300));
}

/// An inset-grouped list: one outlined card with hairlines between rows.
class VListSection extends StatelessWidget {
  const VListSection({
    super.key,
    required this.children,
    this.header,
    this.radius = VRadius.card,
    this.padding = EdgeInsets.zero,
  });

  final List<Widget> children;

  /// Optional eyebrow shown inside the card, above the first row.
  final Widget? header;
  final double radius;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      rows.add(children[i]);
      if (i < children.length - 1) rows.add(const VDivider());
    }
    return VCard(
      padding: padding,
      radius: radius,
      // Clipped so an inverted row (the track playing) keeps the corners.
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius - 1),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (header != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
                child: header,
              ),
            ...rows,
          ],
        ),
      ),
    );
  }
}

/// A list row: title, optional subtitle, and a trailing slot.
///
/// Pass [value] for a "value ›" row that opens something, or [trailing] for
/// a switch, segmented control or stepper.
class VListRow extends StatelessWidget {
  const VListRow({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.value,
    this.trailing,
    this.onTap,
    this.chevron,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final String? value;
  final Widget? trailing;
  final VoidCallback? onTap;

  /// Defaults to true when [onTap] is set and there is no [trailing].
  final bool? chevron;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final showChevron = chevron ?? (onTap != null && trailing == null);
    final row = Padding(
      padding: padding,
      child: Row(
        children: [
          if (leading != null) ...[leading!, const SizedBox(width: 12)],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: VText.rowTitle),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(subtitle!, style: VText.secondary),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          if (value != null) Text(value!, style: VText.inter(13)),
          ?trailing,
          if (showChevron) ...[
            const SizedBox(width: 6),
            const VIconView(VIcon.chevron, size: 14, strokeWidth: 1.6),
          ],
        ],
      ),
    );
    return onTap == null ? row : VTappable(onTap: onTap, child: row);
  }
}

/// A short footnote under a section.
class VFootnote extends StatelessWidget {
  const VFootnote(this.text, {super.key, this.center = false});

  final String text;
  final bool center;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Text(
        text,
        style: VText.footnote,
        textAlign: center ? TextAlign.center : TextAlign.start,
      ),
    );
  }
}
