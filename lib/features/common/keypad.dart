import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../core/theme/v_colors.dart';
import '../../core/theme/v_text.dart';
import '../../core/widgets/v_buttons.dart';
import '../../core/widgets/v_ink.dart';
import '../../core/widgets/v_glass.dart';
import '../../core/widgets/v_surface.dart';

/// PIN dots (A6): filled for each digit typed, outlined for the rest;
/// dashed when the last try was wrong.
class PinDots extends StatelessWidget {
  const PinDots({
    super.key,
    required this.filled,
    this.length = 4,
    this.error = false,
  });

  final int filled;
  final int length;
  final bool error;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < length; i++) ...[
          if (i > 0) const SizedBox(width: 18),
          SizedBox.square(
            dimension: 14,
            child: VOutlined(
              radius: 7,
              outline: error
                  ? VOutline.dashed
                  : (i < filled ? VOutline.none : VOutline.solid),
              dashPattern: const [2, 2],
              fill: !error && i < filled
                  ? VInk.of(context)
                  : VColors.transparent,
              child: const SizedBox.shrink(),
            ),
          ),
        ],
      ],
    );
  }
}

/// The number keypad (A6): 1–9, a blank, 0 and delete, Doto digits in
/// outlined 64 px pills.
class Keypad extends StatelessWidget {
  const Keypad({super.key, required this.onDigit, required this.onDelete});

  final ValueChanged<String> onDigit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    const keys = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '', '0', '⌫'];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 34),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var r = 0; r < 4; r++) ...[
            if (r > 0) const SizedBox(height: 14),
            Row(
              children: [
                for (var c = 0; c < 3; c++) ...[
                  if (c > 0) const SizedBox(width: 22),
                  Expanded(child: _key(context, keys[r * 3 + c])),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _key(BuildContext context, String k) {
    if (k.isEmpty) return const SizedBox(height: 64);
    final delete = k == '⌫';
    return Semantics(
      button: true,
      label: delete ? 'Delete' : k,
      excludeSemantics: true,
      child: VTappable(
        onTap: () {
          HapticFeedback.lightImpact();
          delete ? onDelete() : onDigit(k);
        },
        child: SizedBox(
          height: 64,
          child: delete
              ? Center(child: Text(k, style: VText.inter(22, weight: 400)))
              // Digits sit on glass: the wallpaper blurred behind each key.
              : VGlass(
                  radius: 32,
                  border: false, // the outline below draws it
                  child: VOutlined(
                    radius: 32,
                    child: Center(
                      child: Text(k, style: VText.doto(28, weight: 700)),
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}

/// Six boxes for an invite code (A6, C6): typed boxes solid, the next one
/// bold, the rest dashed.
class CodeBoxes extends StatelessWidget {
  const CodeBoxes({super.key, required this.code, this.length = 6});

  final String code;
  final int length;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(
            child: SizedBox(
              height: 56,
              child: VOutlined(
                radius: 14,
                width: i == code.length ? 2 : 1,
                outline: i > code.length ? VOutline.dashed : VOutline.solid,
                child: Center(
                  child: Text(
                    i < code.length ? code[i] : '',
                    style: VText.doto(28, weight: 900),
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
