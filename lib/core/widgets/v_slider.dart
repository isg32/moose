import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../theme/v_text.dart';
import 'v_ink.dart';

/// A labelled slider (A4): a hairline track, the filled part 6 tall, and a
/// round ink knob ringed in paper. The value shows on the right in Doto.
class VSlider extends StatelessWidget {
  const VSlider({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.display,
  });

  final String label;

  /// 0–1.
  final double value;
  final ValueChanged<double>? onChanged;

  /// The value as shown, e.g. "30%"; defaults to a percentage.
  final String? display;

  @override
  Widget build(BuildContext context) {
    final ink = VInk.of(context);
    final paper = VInk.surfaceOf(context);
    final v = value.clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text(label, style: VText.inter(13, weight: 500))),
            Text(
              display ?? '${(v * 100).round()}%',
              style: VText.doto(14, weight: 700),
            ),
          ],
        ),
        const SizedBox(height: 4),
        LayoutBuilder(
          builder: (context, box) {
            final w = box.maxWidth;
            void set(double x) {
              final next = (x / w).clamp(0.0, 1.0);
              if ((next * 20).round() != (v * 20).round()) {
                HapticFeedback.selectionClick();
              }
              onChanged?.call(next);
            }

            return Semantics(
              slider: true,
              label: label,
              value: display ?? '${(v * 100).round()}%',
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (d) => set(d.localPosition.dx),
                onHorizontalDragUpdate: (d) => set(d.localPosition.dx),
                child: SizedBox(
                  height: 28,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned(
                        left: 0,
                        right: 0,
                        top: 13,
                        child: Container(height: 2, color: ink),
                      ),
                      Positioned(
                        left: 0,
                        top: 11,
                        child: Container(
                          width: w * v,
                          height: 6,
                          decoration: BoxDecoration(
                            color: ink,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ),
                      Positioned(
                        left: (w * v - 11).clamp(0.0, w - 22),
                        top: 3,
                        child: Container(
                          width: 22,
                          height: 22,
                          decoration: BoxDecoration(
                            color: ink,
                            shape: BoxShape.circle,
                            border: Border.all(color: paper, width: 3),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}
