import 'package:flutter/widgets.dart';
import 'package:path_drawing/path_drawing.dart';

import '../widgets/v_ink.dart';

/// Moose's line icons (the canvas's Icons board), drawn on a 24 × 24 grid
/// with 1.5 round-capped strokes, as in Veronica, Idris and Cariño.
enum VIcon {
  send('M4 12L20 4l-6 16l-3-7zM11 13l9-9'),
  mic(
    'M12 3a3 3 0 0 1 3 3v6a3 3 0 0 1-6 0V6a3 3 0 0 1 3-3z'
    'M6 11a6 6 0 0 0 12 0M12 17v4'
  ),
  micOff(
    'M12 3a3 3 0 0 1 3 3v6a3 3 0 0 1-6 0V6a3 3 0 0 1 3-3z'
    'M6 11a6 6 0 0 0 12 0M12 17v4M4 4l16 16'
  ),
  camera('M4 8h3l2-3h6l2 3h3v11H4zM12 10a3.5 3.5 0 1 0 0 7a3.5 3.5 0 1 0 0-7'),
  roundVideo(
    'M12 3a9 9 0 1 0 0 18a9 9 0 1 0 0-18'
    'M12 9a3 3 0 1 0 0 6a3 3 0 1 0 0-6'
  ),
  image('M4 5h16v14H4zM4 16l5-5l4 4l3-3l4 4M15 8.5h.01'),
  plus('M12 5v14M5 12h14'),
  minus('M5 12h14'),
  meme(
    'M12 3a9 9 0 1 0 0 18a9 9 0 1 0 0-18'
    'M8.5 14c1 1.5 2.2 2 3.5 2s2.5-.5 3.5-2M9 9.5v.5M15 9.5v.5'
  ),
  sticker('M4 4h11l5 5v11H4zM15 4v5h5M8.5 14c1 1.5 2.2 2 3.5 2s2.5-.5 3.5-2'),
  music(
    'M9 18V6l10-2v12M9 18a2.5 2.5 0 1 1-5 0a2.5 2.5 0 1 1 5 0'
    'M19 16a2.5 2.5 0 1 1-5 0a2.5 2.5 0 1 1 5 0'
  ),
  poke(
    'M12 10.5a1.5 1.5 0 1 0 0 3a1.5 1.5 0 1 0 0-3'
    'M7.8 7.8a6 6 0 0 0 0 8.4M16.2 7.8a6 6 0 0 1 0 8.4'
    'M5 5a10 10 0 0 0 0 14M19 5a10 10 0 0 1 0 14'
  ),
  hug('M12 20s-7-4.5-7-10a4 4 0 0 1 7-2.5A4 4 0 0 1 19 10c0 5.5-7 10-7 10z'),
  kiss('M4 12c2-3 5-4 8-1c3-3 6-2 8 1c-2 3-5 4-8 4s-6-1-8-4zM4 12h16'),
  missYou(
    'M12 3a9 9 0 1 0 0 18a9 9 0 1 0 0-18'
    'M8.5 15.5c1-1 2.2-1.5 3.5-1.5s2.5.5 3.5 1.5M9 9.5v.5M15 9.5v.5'
    'M16 11v2'
  ),
  doodle('M14.5 4.5l5 5L9 20H4v-5zM12.5 6.5l5 5'),
  chat('M4 5h16v11H9l-5 4z'),
  theme(
    'M12 3a9 9 0 1 0 0 18a9 9 0 1 0 0-18M12 3v18M12 8l6.5-3M12 13l8.5-2'
    'M12 18l6.5 1'
  ),
  lock('M6 11h12v9H6zM8.5 11V8a3.5 3.5 0 0 1 7 0v3'),
  gear(
    'M12 9a3 3 0 1 0 0 6a3 3 0 1 0 0-6M12 2v3M12 19v3M2 12h3M19 12h3'
    'M4.9 4.9l2.1 2.1M17 17l2.1 2.1M4.9 19.1L7 17M17 7l2.1-2.1'
  ),
  back('M15 6l-6 6l6 6'),
  chevron('M9 6l6 6l-6 6'),
  up('M6 15l6-6l6 6'),
  down('M12 5v14M6 13l6 6l6-6'),
  close('M6 6l12 12M18 6L6 18'),
  more('M5 12h.01M12 12h.01M19 12h.01'),
  reply('M10 8L5 12l5 4M5 12h9a5 5 0 0 1 5 5v1'),
  react(
    'M11 3.1A9 9 0 1 0 20.9 13M8.5 14c1 1.5 2.2 2 3.5 2s2.5-.5 3.5-2'
    'M9 9.5v.5M15 9.5v.5M19 2v6M16 5h6'
  ),
  copy('M9 9h11v11H9zM5 15H4V4h11v1'),
  trash('M5 7h14M10 7V4h4v3M7 7l1 13h8l1-13'),
  download('M12 4v11M7 10l5 5l5-5M5 20h14'),
  share('M12 15V3M7 8l5-5l5 5M5 13v7h14v-7'),
  play('M8 5l11 7l-11 7z'),
  pause('M8 5v14M16 5v14'),
  check('M5 12l5 5l9-10'),
  doubleCheck('M2 12l5 5l9-10M12 16l1 1l9-10'),
  pending('M12 3a9 9 0 1 0 0 18a9 9 0 1 0 0-18M12 7v5l3 2'),
  warning('M12 3l10 18H2zM12 10v5M12 18h.01'),
  info('M12 3a9 9 0 1 0 0 18a9 9 0 1 0 0-18M12 11v5M12 8h.01'),
  search('M11 4a7 7 0 1 0 0 14a7 7 0 1 0 0-14M16 16l5 5'),
  qr(
    'M4 4h6v6H4zM14 4h6v6h-6zM4 14h6v6H4zM14 14h2v2h-2zM18 18h2v2h-2z'
    'M14 18h2M18 14h2'
  ),
  swapCamera(
    'M4 10a8 8 0 0 1 14-4l2 2M20 4v4h-4M20 14a8 8 0 0 1-14 4l-2-2'
    'M4 20v-4h4'
  ),
  flash('M13 3L5 14h6l-1 7l8-11h-6z'),
  undo('M9 7L5 11l4 4M5 11h9a5 5 0 0 1 0 10h-3'),
  redo('M15 7l4 4l-4 4M19 11h-9a5 5 0 0 0 0 10h3'),
  star(
    'M12 3l2.7 5.6l6.1.9l-4.4 4.3l1 6.1L12 17l-5.4 2.9l1-6.1L3.2 9.5l6.1-.9z'
  ),
  phone(
    'M5 4h4l2 5l-2.5 1.5a11 11 0 0 0 5 5L15 13l5 2v4a2 2 0 0 1-2 2A16 16 0 0 1 3 6a2 2 0 0 1 2-2z'
  ),
  video('M3 7h12v10H3zM15 10l6-3v10l-6-3'),
  speaker('M4 9h4l5-4v14l-5-4H4zM16 9a4 4 0 0 1 0 6M18.5 6.5a8 8 0 0 1 0 11'),
  mute('M4 9h4l5-4v14l-5-4H4zM17 9l4 6M21 9l-4 6'),
  offline(
    'M3 3l18 18M8.5 16.5a5 5 0 0 1 7 0M5 12.5a10 10 0 0 1 4-2.4'
    'M19 12.5a10 10 0 0 0-2.6-1.8M12 20h.01'
  ),
  unlink(
    'M9 15l-2 2a3 3 0 0 1-4-4l3-3a3 3 0 0 1 4 0'
    'M15 9l2-2a3 3 0 0 1 4 4l-3 3a3 3 0 0 1-4 0M4 4l16 16'
  ),
  phoneDevice('M7 3h10v18H7zM11 18h2'),
  fineLiner('M4 20l3-1L19 7l-2-2L5 17zM15 7l2 2'),
  marker('M5 19h4l10-10l-4-4L5 15zM13 7l4 4M4 21h7'),
  brush('M14 4l6 6l-6 6l-6-6zM8 10c-3 0-5 2-5 5c0 2-1 4-1 5c3 0 8-1 8-5'),
  pencil('M4 20l1-5L16 4l4 4L9 19zM14 6l4 4M5 15l4 4'),
  calligraphy('M12 3l5 7l-5 11l-5-11zM12 10v4'),
  neon('M12 3v3M5 6l2 2M19 6l-2 2M8 14a4 4 0 1 1 8 0v3H8zM9 20h6'),
  highlighter('M9 14l7-10l4 3l-7 10zM9 14l-2 3h4M4 21h10'),
  eraser('M8 20h12M4 15l9-9l6 6l-8 8H8z'),
  lasso(
    'M12 4c5 0 9 2.2 9 5s-4 5-9 5s-9-2.2-9-5s4-5 9-5z'
    'M6 13c-1 2 0 4 2 4s2 2 0 3'
  ),
  move('M12 3v18M3 12h18M9 6l3-3l3 3M9 18l3 3l3-3M6 9l-3 3l3 3M18 9l3 3l-3 3'),
  recolour(
    'M12 3a9 9 0 1 0 0 18c1.5 0 2-1 2-2s-1-2 0-3s4 0 5-2a9 9 0 0 0-7-11z'
    'M8 10h.01M12 7h.01M16 10h.01'
  ),
  cutOut('M6 6l12 12M6 18L18 6M4 12h3M17 12h3'),
  text('M5 6h14M12 6v13M9 19h6'),
  outline(
    'M12 3a9 9 0 1 0 0 18a9 9 0 1 0 0-18'
    'M12 7a5 5 0 1 0 0 10a5 5 0 1 0 0-10'
  );

  const VIcon(this.svgPath);

  final String svgPath;

  static final Map<VIcon, Path> _cache = {};

  Path get path => _cache.putIfAbsent(this, () => parseSvgPathData(svgPath));
}
/// Draws a [VIcon] in the current ink colour.
///
/// [strokeWidth] is in grid units, like the SVG `stroke-width` in the design
/// (1.5 idle, 2 inside a selected pill).
class VIconView extends StatelessWidget {
  const VIconView(
    this.icon, {
    super.key,
    this.size = 20,
    this.strokeWidth = 1.5,
    this.color,
  });

  final VIcon icon;
  final double size;
  final double strokeWidth;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: _IconPainter(
          path: icon.path,
          color: color ?? VInk.of(context),
          strokeWidth: strokeWidth,
        ),
      ),
    );
  }
}

class _IconPainter extends CustomPainter {
  _IconPainter({
    required this.path,
    required this.color,
    required this.strokeWidth,
  });

  final Path path;
  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 24, size.height / 24);
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_IconPainter old) =>
      old.path != path || old.color != color || old.strokeWidth != strokeWidth;
}
