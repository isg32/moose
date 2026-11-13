import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/icons/v_icons.dart';
import '../../core/theme/v_colors.dart';
import '../../core/theme/v_palette.dart';
import '../../core/theme/v_text.dart';
import '../../core/widgets/v_buttons.dart';
import '../../core/widgets/v_glass.dart';
import '../../core/widgets/v_ink.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../common/choice_sheet.dart';
import '../common/strokes.dart';
import '../common/toast.dart';
import '../stickers/sticker_maker.dart';
import 'doodle_sheets.dart';
import 'paper.dart';

/// The space every board is drawn in; it scales to fit the screen.
const boardSpace = Size(390, 700);

/// A pen's settings (C33).
class PenSettings {
  const PenSettings({
    this.size = 7,
    this.opacity = 1,
    this.smoothing = 0.6,
    this.pressure = true,
    this.nibAngle = 45,
  });

  final double size;
  final double opacity;

  /// 0–1: how much each new point is pulled towards the last.
  final double smoothing;
  final bool pressure;

  /// Calligraphy only, degrees.
  final int nibAngle;

  PenSettings copyWith({
    double? size,
    double? opacity,
    double? smoothing,
    bool? pressure,
    int? nibAngle,
  }) => PenSettings(
    size: size ?? this.size,
    opacity: opacity ?? this.opacity,
    smoothing: smoothing ?? this.smoothing,
    pressure: pressure ?? this.pressure,
    nibAngle: nibAngle ?? this.nibAngle,
  );
}

/// A shared board (C31): draw with the dock's nine tools (C32), undo and
/// redo, and see Aatika's cursor while she draws.
class BoardPage extends ConsumerStatefulWidget {
  const BoardPage({super.key, required this.id});

  final String id;

  @override
  ConsumerState<BoardPage> createState() => _BoardPageState();
}

class _BoardPageState extends ConsumerState<BoardPage> {
  var _tool = PenTool.brush;
  var _argb = 0xFFFF5C7A;
  final _recent = <int>[
    0xFFFF5C7A,
    0xFF5BC0EB,
    0xFFFFE066,
    0xFF3FA34D,
    0xFF9DB2FF,
  ];
  final _settings = <PenTool, PenSettings>{};

  late List<Stroke> _strokes = _doodle.strokes;
  final _undo = <List<Stroke>>[];
  final _redo = <List<Stroke>>[];

  /// The stroke being drawn, in board space.
  List<Offset>? _live;
  int _tick = 0;

  /// Lasso: the strokes picked, and how far they've been dragged.
  Set<int> _picked = {};
  Offset _drag = Offset.zero;

  Doodle get _doodle => ref
      .read(doodlesProvider)
      .firstWhere(
        (d) => d.id == widget.id,
        orElse: () => ref.read(doodlesProvider).first,
      );

  PenSettings _pen(PenTool t) =>
      _settings[t] ??
      switch (t) {
        PenTool.fineLiner => const PenSettings(size: 3),
        PenTool.marker => const PenSettings(size: 6),
        PenTool.pencil => const PenSettings(size: 3, opacity: 0.9),
        PenTool.calligraphy => const PenSettings(size: 9),
        PenTool.neon => const PenSettings(size: 4),
        PenTool.highlighter => const PenSettings(size: 20, opacity: 0.45),
        PenTool.eraser => const PenSettings(size: 18),
        _ => const PenSettings(),
      };

  void _commit(List<Stroke> next) {
    _undo.add(_strokes);
    _redo.clear();
    setState(() => _strokes = next);
    ref.read(doodlesProvider.notifier).setStrokes(widget.id, next);
  }

  void _undoOne() {
    if (_undo.isEmpty) return;
    HapticFeedback.selectionClick();
    _redo.add(_strokes);
    setState(() {
      _strokes = _undo.removeLast();
      _picked = {};
    });
    ref.read(doodlesProvider.notifier).setStrokes(widget.id, _strokes);
  }

  void _redoOne() {
    if (_redo.isEmpty) return;
    HapticFeedback.selectionClick();
    _undo.add(_strokes);
    setState(() => _strokes = _redo.removeLast());
    ref.read(doodlesProvider.notifier).setStrokes(widget.id, _strokes);
  }

  // Board space <-> screen.

  double _scale(Size s) =>
      math.min(s.width / boardSpace.width, s.height / boardSpace.height);

  Offset _origin(Size s) {
    final k = _scale(s);
    return Offset(
      (s.width - boardSpace.width * k) / 2,
      (s.height - boardSpace.height * k) / 2,
    );
  }

  Offset _toBoard(Offset p, Size s) => (p - _origin(s)) / _scale(s);

  // Drawing.

  void _down(Offset p, Size s) {
    final b = _toBoard(p, s);
    if (_tool == PenTool.lasso && _picked.isNotEmpty && _inPicked(b)) {
      _drag = Offset.zero;
      _live = null;
      return;
    }
    if (_picked.isNotEmpty) setState(() => _picked = {});
    setState(() => _live = [b]);
  }

  void _move(Offset p, Size s, Offset delta) {
    if (_tool == PenTool.lasso && _picked.isNotEmpty && _live == null) {
      setState(() => _drag += delta / _scale(s));
      return;
    }
    final live = _live;
    if (live == null) return;
    var b = _toBoard(p, s);
    // Smoothing: each point is pulled towards the last (an easy 1€-style
    // low-pass; Phase 4 tunes it on real devices).
    final k = _pen(_tool).smoothing * 0.7;
    if (live.isNotEmpty) b = Offset.lerp(b, live.last, k)!;
    if (live.isEmpty || (b - live.last).distance > 1.2) {
      live.add(b);
      setState(() => _tick++);
    }
  }

  void _up() {
    if (_tool == PenTool.lasso && _picked.isNotEmpty && _live == null) {
      if (_drag != Offset.zero) {
        _commit([
          for (final (i, st) in _strokes.indexed)
            _picked.contains(i) ? _shift(st, _drag) : st,
        ]);
      }
      setState(() => _drag = Offset.zero);
      return;
    }
    final live = _live;
    if (live == null) return;
    setState(() => _live = null);
    if (_tool == PenTool.lasso) {
      _select(live);
      return;
    }
    if (_tool == PenTool.eraser) {
      _erase(live);
      return;
    }
    final pen = _pen(_tool);
    _commit([
      ..._strokes,
      Stroke(
        tool: _tool,
        argb: _argb,
        size: pen.size,
        opacity: pen.opacity,
        points: List.of(live),
      ),
    ]);
  }

  Stroke _shift(Stroke s, Offset d) => Stroke(
    tool: s.tool,
    argb: s.argb,
    size: s.size,
    opacity: s.opacity,
    by: s.by,
    points: [for (final p in s.points) p + d],
  );

  /// The eraser takes away every stroke it touches.
  void _erase(List<Offset> path) {
    final r = _pen(PenTool.eraser).size;
    bool touches(Stroke s) =>
        s.points.any((p) => path.any((q) => (p - q).distance < r + s.size / 2));
    final next = [
      for (final s in _strokes)
        if (!touches(s)) s,
    ];
    if (next.length != _strokes.length) {
      HapticFeedback.selectionClick();
      _commit(next);
    }
  }

  /// The lasso picks strokes whose points mostly fall inside it.
  void _select(List<Offset> loop) {
    if (loop.length < 3) return;
    final path = Path()..addPolygon(loop, true);
    final picked = <int>{};
    for (final (i, s) in _strokes.indexed) {
      final inside = s.points.where(path.contains).length;
      if (s.points.isNotEmpty && inside >= s.points.length * 0.6) picked.add(i);
    }
    if (picked.isNotEmpty) HapticFeedback.mediumImpact();
    setState(() => _picked = picked);
  }

  bool _inPicked(Offset b) {
    final r = _pickedBounds();
    return r != null && r.inflate(16).contains(b);
  }

  Rect? _pickedBounds() {
    Rect? r;
    for (final i in _picked) {
      for (final p in _strokes[i].points) {
        final pr = Rect.fromCircle(
          center: p + _drag,
          radius: _strokes[i].size / 2,
        );
        r = r == null ? pr : r.expandToInclude(pr);
      }
    }
    return r;
  }

  Future<void> _lassoAction(String a) async {
    final picked = [for (final i in _picked) _strokes[i]];
    switch (a) {
      case 'recolour':
        _commit([
          for (final (i, s) in _strokes.indexed)
            _picked.contains(i)
                ? Stroke(
                    tool: s.tool,
                    argb: _argb,
                    size: s.size,
                    opacity: s.opacity,
                    points: s.points,
                  )
                : s,
        ]);
      case 'duplicate':
        _commit([
          ..._strokes,
          for (final s in picked) _shift(s, const Offset(24, 24)),
        ]);
      case 'sticker':
        await showDoodleStickerSheet(context, ref, picked);
      case 'delete':
        _commit([
          for (final (i, s) in _strokes.indexed)
            if (!_picked.contains(i)) s,
        ]);
        setState(() => _picked = {});
      case 'move':
        showToast(context, 'Drag the selection to move it');
    }
  }

  Future<void> _more() async {
    final a = await showChoiceSheet<String>(
      context,
      title: _doodle.name,
      choices: const [
        Choice('export', 'Save to gallery', icon: VIcon.download),
        Choice('send', 'Send to chat', icon: VIcon.send),
        Choice(
          'clear',
          'Clear the board',
          icon: VIcon.trash,
          sub: 'For both of you',
        ),
      ],
    );
    if (!mounted || a == null) return;
    switch (a) {
      case 'export':
        showToast(context, 'Saved to your gallery');
      case 'send':
        ref
            .read(messagesProvider.notifier)
            .send(
              StickerBody(
                Sticker.doodle(
                  id: 'snap${DateTime.now().microsecondsSinceEpoch}',
                  strokes: normalise(_strokes),
                ),
              ),
            );
        showToast(context, 'Sent to ${ref.read(pairingProvider).partner.name}');
      case 'clear':
        _commit(const []);
    }
  }

  Future<void> _options() async {
    final next = await showToolOptions(
      context,
      tool: _tool,
      pen: _pen(_tool),
      argb: _argb,
    );
    if (next != null) setState(() => _settings[_tool] = next);
  }

  Future<void> _colour() async {
    final next = await showColourSheet(context, argb: _argb, recent: _recent);
    if (next == null) return;
    setState(() {
      _argb = next;
      _recent
        ..remove(next)
        ..insert(0, next);
      if (_recent.length > 6) _recent.removeLast();
    });
  }

  @override
  Widget build(BuildContext context) {
    final doodle = ref
        .watch(doodlesProvider)
        .firstWhere((d) => d.id == widget.id, orElse: () => _doodle);
    final partner = ref.watch(pairingProvider).partner.name;
    final top = MediaQuery.paddingOf(context).top;
    final bottom = MediaQuery.paddingOf(context).bottom;
    final pen = _pen(_tool);
    final live = _live;
    final shown = [
      for (final (i, s) in _strokes.indexed)
        _picked.contains(i) && _drag != Offset.zero ? _shift(s, _drag) : s,
      if (live != null && _tool != PenTool.eraser && _tool != PenTool.lasso)
        Stroke(
          tool: _tool,
          argb: _argb,
          size: pen.size,
          opacity: pen.opacity,
          points: live,
        ),
    ];
    // Where Aatika's pen is: the end of her last stroke.
    final partnerAt = doodle.partnerHere
        ? _strokes.where((s) => s.by == 'partner').lastOrNull?.points.lastOrNull
        : null;

    return ColoredBox(
      color: VInk.surfaceOf(context),
      child: Stack(
        fit: StackFit.expand,
        children: [
          LayoutBuilder(
            builder: (context, box) {
              final size = box.biggest;
              final k = _scale(size);
              final o = _origin(size);
              final bounds = _pickedBounds();
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanStart: (d) => _down(d.localPosition, size),
                onPanUpdate: (d) => _move(d.localPosition, size, d.delta),
                onPanEnd: (_) => _up(),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    PaperView(doodle.paper),
                    CustomPaint(
                      painter: StrokesPainter(
                        shown,
                        space: boardSpace,
                        repaintKey: _tick,
                      ),
                    ),
                    if (live != null &&
                        (_tool == PenTool.lasso || _tool == PenTool.eraser))
                      CustomPaint(
                        painter: _Trace(
                          live,
                          k,
                          o,
                          VInk.of(context),
                          dashed: _tool == PenTool.lasso,
                        ),
                      ),
                    if (bounds != null) ...[
                      Positioned.fromRect(
                        rect: Rect.fromLTRB(
                          o.dx + bounds.left * k - 10,
                          o.dy + bounds.top * k - 10,
                          o.dx + bounds.right * k + 10,
                          o.dy + bounds.bottom * k + 10,
                        ),
                        child: IgnorePointer(
                          child: _SelectionBox(ink: VInk.of(context)),
                        ),
                      ),
                    ],
                    if (partnerAt != null)
                      Positioned(
                        left: o.dx + partnerAt.dx * k,
                        top: o.dy + partnerAt.dy * k,
                        child: IgnorePointer(
                          child: _PartnerCursor(name: partner),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
          // The top bar: back, name and who's here, undo, redo, more.
          Positioned(
            left: 14,
            right: 14,
            top: top + 8,
            child: Row(
              children: [
                _GlassButton(
                  VIcon.back,
                  'Back',
                  () => Navigator.of(context).pop(),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        doodle.name,
                        style: VText.inter(15, weight: 600),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        _picked.isNotEmpty
                            ? '${_picked.length} stroke${_picked.length == 1 ? '' : 's'} selected'
                            : doodle.partnerHere
                            ? '$partner is drawing'
                            : 'Shared with $partner',
                        style: VText.secondary,
                      ),
                    ],
                  ),
                ),
                Opacity(
                  opacity: _undo.isEmpty ? 0.35 : 1,
                  child: _GlassButton(VIcon.undo, 'Undo', _undoOne),
                ),
                const SizedBox(width: 8),
                Opacity(
                  opacity: _redo.isEmpty ? 0.35 : 1,
                  child: _GlassButton(VIcon.redo, 'Redo', _redoOne),
                ),
                const SizedBox(width: 8),
                _GlassButton(VIcon.more, 'More', _more),
              ],
            ),
          ),
          if (_picked.isNotEmpty && _tool == PenTool.lasso)
            Positioned(
              left: 0,
              right: 0,
              top: top + 150,
              child: Center(child: LassoBar(onAction: _lassoAction)),
            ),
          // The dock (C32).
          Positioned(
            left: 10,
            right: 10,
            bottom: bottom + 26,
            child: _Dock(
              tool: _tool,
              argb: _argb,
              onTool: (t) {
                HapticFeedback.selectionClick();
                if (t == _tool && t != PenTool.lasso) {
                  _options();
                } else {
                  setState(() {
                    _tool = t;
                    _picked = {};
                  });
                }
              },
              onHold: (t) {
                setState(() => _tool = t);
                _options();
              },
              onColour: _colour,
            ),
          ),
        ],
      ),
    );
  }
}

class _GlassButton extends StatelessWidget {
  const _GlassButton(this.icon, this.label, this.onTap);

  final VIcon icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: label,
    child: VTappable(
      onTap: onTap,
      child: VGlass(
        radius: 20,
        tint: VPalette.of(context).glassSheet,
        blur: 14,
        child: SizedBox.square(
          dimension: 40,
          child: Center(
            child: VIconView(
              icon,
              size: 20,
              strokeWidth: icon == VIcon.more ? 2.5 : 1.5,
            ),
          ),
        ),
      ),
    ),
  );
}

/// The nine tools, then the colour (C32). The tool in hand lifts out of
/// the dock, filled.
class _Dock extends StatelessWidget {
  const _Dock({
    required this.tool,
    required this.argb,
    required this.onTool,
    required this.onHold,
    required this.onColour,
  });

  final PenTool tool;
  final int argb;
  final void Function(PenTool t) onTool;
  final void Function(PenTool t) onHold;
  final VoidCallback onColour;

  static VIcon iconOf(PenTool t) => switch (t) {
    PenTool.fineLiner => VIcon.fineLiner,
    PenTool.marker => VIcon.marker,
    PenTool.brush => VIcon.brush,
    PenTool.pencil => VIcon.pencil,
    PenTool.calligraphy => VIcon.calligraphy,
    PenTool.neon => VIcon.neon,
    PenTool.highlighter => VIcon.highlighter,
    PenTool.eraser => VIcon.eraser,
    PenTool.lasso => VIcon.lasso,
  };

  @override
  Widget build(BuildContext context) {
    final ink = VInk.of(context);
    final paper = VInk.surfaceOf(context);
    return VGlass(
      radius: 32,
      tint: VPalette.of(context).glassSheet,
      blur: 18,
      child: SizedBox(
        height: 64,
        child: Row(
          children: [
            const SizedBox(width: 6),
            for (final t in PenTool.values)
              Expanded(
                child: Semantics(
                  button: true,
                  selected: t == tool,
                  label: t.label,
                  child: GestureDetector(
                    onTap: () => onTool(t),
                    onLongPress: () => onHold(t),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      curve: Curves.easeOut,
                      height: t == tool ? 46 : 40,
                      transform: Matrix4.translationValues(
                        0,
                        t == tool ? -8 : 0,
                        0,
                      ),
                      decoration: BoxDecoration(
                        color: t == tool ? ink : null,
                        borderRadius: BorderRadius.circular(17),
                        boxShadow: t == tool
                            ? [BoxShadow(color: paper, spreadRadius: 3)]
                            : null,
                      ),
                      child: Center(
                        child: VIconView(
                          iconOf(t),
                          size: 21,
                          color: t == tool ? paper : ink,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            Container(
              width: 1,
              height: 30,
              color: ink,
              margin: const EdgeInsets.symmetric(horizontal: 5),
            ),
            Semantics(
              button: true,
              label: 'Colour',
              child: GestureDetector(
                onTap: onColour,
                child: Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: VPenColors.of(argb),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(color: paper, spreadRadius: 2),
                      BoxShadow(color: ink, spreadRadius: 3),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
          ],
        ),
      ),
    );
  }
}

/// The lasso or eraser path as it's drawn.
class _Trace extends CustomPainter {
  _Trace(this.points, this.k, this.o, this.ink, {required this.dashed});

  final List<Offset> points;
  final double k;
  final Offset o;
  final Color ink;
  final bool dashed;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = ink
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    final pts = [for (final p in points) o + p * k];
    for (var i = 0; i < pts.length - 1; i++) {
      if (dashed && i % 4 >= 2) continue;
      canvas.drawLine(pts[i], pts[i + 1], paint);
    }
  }

  @override
  bool shouldRepaint(_Trace old) => true;
}

/// A dashed frame with corner handles around a lasso selection.
class _SelectionBox extends StatelessWidget {
  const _SelectionBox({required this.ink});

  final Color ink;

  @override
  Widget build(BuildContext context) {
    final paper = VInk.surfaceOf(context);
    Widget handle() => Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(
        color: paper,
        border: Border.all(color: ink, width: 1.5),
        borderRadius: BorderRadius.circular(3),
      ),
    );
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(child: CustomPaint(painter: _DashRect(ink))),
        Positioned(left: -6, top: -6, child: handle()),
        Positioned(right: -6, top: -6, child: handle()),
        Positioned(left: -6, bottom: -6, child: handle()),
        Positioned(right: -6, bottom: -6, child: handle()),
      ],
    );
  }
}

class _DashRect extends CustomPainter {
  _DashRect(this.ink);

  final Color ink;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = ink
      ..strokeWidth = 1.5;
    void dash(Offset a, Offset b) {
      final len = (b - a).distance;
      final dir = (b - a) / len;
      for (var d = 0.0; d < len; d += 12) {
        canvas.drawLine(a + dir * d, a + dir * math.min(d + 6, len), p);
      }
    }

    dash(Offset.zero, Offset(size.width, 0));
    dash(Offset(size.width, 0), Offset(size.width, size.height));
    dash(Offset(size.width, size.height), Offset(0, size.height));
    dash(Offset(0, size.height), Offset.zero);
  }

  @override
  bool shouldRepaint(_DashRect old) => old.ink != ink;
}

/// Aatika's pen while she draws: a dot in her colour and her name.
class _PartnerCursor extends StatelessWidget {
  const _PartnerCursor({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final ink = VInk.of(context);
    final paper = VInk.surfaceOf(context);
    return Transform.translate(
      offset: const Offset(-6, -6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: VPenColors.of(0xFF3FA34D),
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: paper, spreadRadius: 3)],
            ),
          ),
          const SizedBox(height: 2),
          Container(
            margin: const EdgeInsets.only(left: 8),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: ink,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              name,
              style: VText.inter(10, weight: 600).copyWith(color: paper),
            ),
          ),
        ],
      ),
    );
  }
}
