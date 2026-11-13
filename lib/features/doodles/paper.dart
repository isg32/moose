import 'package:flutter/widgets.dart';

import '../../core/widgets/v_ink.dart';
import '../../data/models.dart';

/// What a board is drawn on (C30): plain, dotted, lined, or the shared
/// wallpaper showing through.
class PaperView extends StatelessWidget {
  const PaperView(this.paper, {super.key});

  final Paper paper;

  @override
  Widget build(BuildContext context) {
    if (paper == Paper.wallpaper) return const SizedBox.expand();
    return ColoredBox(
      color: VInk.surfaceOf(context),
      child: CustomPaint(
        painter: _PaperPainter(paper, VInk.of(context)),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _PaperPainter extends CustomPainter {
  _PaperPainter(this.paper, this.ink);

  final Paper paper;
  final Color ink;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = ink.withValues(alpha: 0.22);
    switch (paper) {
      case Paper.dotted:
        for (var y = 11.0; y < size.height; y += 22) {
          for (var x = 11.0; x < size.width; x += 22) {
            canvas.drawCircle(Offset(x, y), 1.1, p);
          }
        }
      case Paper.lined:
        p.strokeWidth = 1;
        for (var y = 28.0; y < size.height; y += 28) {
          canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
        }
      case Paper.plain:
      case Paper.wallpaper:
        break;
    }
  }

  @override
  bool shouldRepaint(_PaperPainter old) => old.paper != paper || old.ink != ink;
}
