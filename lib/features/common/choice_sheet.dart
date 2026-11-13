import 'package:flutter/widgets.dart';

import '../../core/icons/v_icons.dart';
import '../../core/theme/v_text.dart';
import '../../core/widgets/v_buttons.dart';
import '../../core/widgets/v_glass.dart';
import '../../core/widgets/v_surface.dart';

/// One row of a [showChoiceSheet].
class Choice<T> {
  const Choice(this.value, this.label, {this.icon, this.sub});

  final T value;
  final String label;
  final VIcon? icon;
  final String? sub;
}

/// A glass sheet of rows to pick from (Moose's own, in the current ink).
Future<T?> showChoiceSheet<T>(
  BuildContext context, {
  required String title,
  required List<Choice<T>> choices,
}) {
  return showVSheet<T>(
    context,
    title: title,
    builder: (context) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (i, c) in choices.indexed) ...[
          if (i > 0) const VDivider(),
          Semantics(
            button: true,
            label: c.label,
            child: VTappable(
              onTap: () => Navigator.of(context).pop(c.value),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Row(
                  children: [
                    if (c.icon != null) ...[
                      VIconView(c.icon!, size: 22),
                      const SizedBox(width: 14),
                    ],
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(c.label, style: VText.rowTitle),
                          if (c.sub != null)
                            Text(c.sub!, style: VText.secondary),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ],
    ),
  );
}
