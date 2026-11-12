import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../icons/v_icons.dart';
import '../theme/v_colors.dart';
import '../theme/v_text.dart';
import '../theme/v_tokens.dart';
import 'v_buttons.dart';
import 'v_ink.dart';
import 'v_surface.dart';

/// On: ink-filled track with a surface-coloured knob.
/// Off: outlined track with an outlined knob.
class VSwitch extends StatelessWidget {
  const VSwitch({super.key, required this.value, this.onChanged});

  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final ink = VInk.of(context);
    final surface = VColors.onColor(ink);
    return Semantics(
      toggled: value,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onChanged == null
            ? null
            : () {
                HapticFeedback.lightImpact();
                onChanged!(!value);
              },
        child: SizedBox(
          width: 46,
          height: 28,
          child: VOutlined(
            radius: 14,
            outline: value ? VOutline.none : VOutline.solid,
            fill: value ? ink : VColors.transparent,
            color: ink,
            child: AnimatedAlign(
              duration: VMotion.standard,
              curve: VMotion.curve,
              alignment: value ? Alignment.centerRight : Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.all(3),
                child: SizedBox.square(
                  dimension: value ? 22 : 20,
                  child: VOutlined(
                    radius: 11,
                    outline: value ? VOutline.none : VOutline.solid,
                    fill: value ? surface : VColors.transparent,
                    color: ink,
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// An outlined pill whose selected segment is an inverted pill.
///
/// `compact` is the small inline variant used in list rows (`50 | 80 | 90%`).
class VSegmented<T> extends StatelessWidget {
  const VSegmented({
    super.key,
    required this.segments,
    required this.value,
    this.onChanged,
    this.compact = false,
  });

  final Map<T, String> segments;
  final T value;
  final ValueChanged<T>? onChanged;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final ink = VInk.of(context);
    final entries = segments.entries.toList();

    Widget segment(MapEntry<T, String> e) {
      final selected = e.key == value;
      final label = Text(
        e.value,
        textAlign: TextAlign.center,
        style: VText.inter(
          compact ? 12 : 13,
          weight: selected ? 600 : (compact ? 500 : 400),
        ).copyWith(color: selected ? VColors.onColor(ink) : ink),
      );
      final pill = AnimatedContainer(
        duration: VMotion.standard,
        curve: VMotion.curve,
        padding: compact
            ? const EdgeInsets.symmetric(horizontal: 10, vertical: 5)
            : const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: selected ? ink : VColors.transparent,
          borderRadius: BorderRadius.circular(VRadius.pill),
        ),
        child: label,
      );
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onChanged == null || selected
            ? null
            : () {
                HapticFeedback.selectionClick();
                onChanged!(e.key);
              },
        child: pill,
      );
    }

    return VOutlined(
      radius: VRadius.pill,
      child: Padding(
        padding: EdgeInsets.all(compact ? 2 : 3),
        child: compact
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [for (final e in entries) segment(e)],
              )
            : Row(
                children: [
                  for (final e in entries) Expanded(child: segment(e)),
                ],
              ),
      ),
    );
  }
}

/// Seven round day toggles, Monday first. Days are 1 (Mon) … 7 (Sun).
class VDayPicker extends StatelessWidget {
  const VDayPicker({super.key, required this.days, this.onChanged});

  final Set<int> days;
  final ValueChanged<Set<int>>? onChanged;

  static const _letters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  @override
  Widget build(BuildContext context) {
    final ink = VInk.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        for (var d = 1; d <= 7; d++)
          GestureDetector(
            onTap: onChanged == null
                ? null
                : () {
                    HapticFeedback.selectionClick();
                    final next = {...days};
                    next.contains(d) ? next.remove(d) : next.add(d);
                    onChanged!(next);
                  },
            child: SizedBox.square(
              dimension: 34,
              child: VOutlined(
                radius: 17,
                outline: days.contains(d) ? VOutline.none : VOutline.solid,
                fill: days.contains(d) ? ink : VColors.transparent,
                child: Center(
                  child: Text(
                    _letters[d - 1],
                    style: VText.inter(13, weight: days.contains(d) ? 600 : 400)
                        .copyWith(
                          color: days.contains(d) ? VColors.onColor(ink) : ink,
                        ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// − value + with round outline buttons. `large` is the onboarding stepper.
class VStepper extends StatelessWidget {
  const VStepper({
    super.key,
    required this.value,
    required this.onChanged,
    this.min = 0,
    this.max = 999,
    this.large = false,
  });

  final int value;
  final ValueChanged<int> onChanged;
  final int min;
  final int max;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final button = large ? 52.0 : 30.0;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        VCircleButton(
          icon: VIcon.minus,
          size: button,
          onTap: value > min ? () => onChanged(value - 1) : null,
        ),
        SizedBox(width: large ? 28 : 14),
        Text(
          '$value',
          style: large
              ? VText.doto(96, weight: 900, height: 1)
              : VText.doto(22),
        ),
        SizedBox(width: large ? 28 : 14),
        VCircleButton(
          icon: VIcon.plus,
          size: button,
          onTap: value < max ? () => onChanged(value + 1) : null,
        ),
      ],
    );
  }
}

/// A selectable row of pills where the chosen one is filled (chips list).
class VChoiceChips<T> extends StatelessWidget {
  const VChoiceChips({
    super.key,
    required this.options,
    required this.selected,
    this.onToggle,
    this.addLabel,
    this.onAdd,
  });

  final Map<T, String> options;
  final Set<T> selected;
  final ValueChanged<T>? onToggle;
  final String? addLabel;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final e in options.entries)
          VPill(
            e.value,
            fill: selected.contains(e.key) ? VFill.filled : VFill.outline,
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
            onTap: onToggle == null ? null : () => onToggle!(e.key),
          ),
        if (addLabel != null)
          VPill(
            addLabel!,
            fill: VFill.dashed,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            onTap: onAdd,
          ),
      ],
    );
  }
}
