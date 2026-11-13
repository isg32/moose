import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

import '../../core/icons/v_icons.dart';
import '../../core/theme/v_colors.dart';
import '../../core/theme/v_palette.dart';
import '../../core/theme/v_text.dart';
import '../../core/widgets/v_buttons.dart';
import '../../core/widgets/v_controls.dart';
import '../../core/widgets/v_glass.dart';
import '../../core/widgets/v_ink.dart';
import '../../core/widgets/v_slider.dart';
import '../../core/widgets/v_surface.dart';
import '../../data/models.dart';
import '../common/overlay.dart';
import '../common/strokes.dart';
import 'board_page.dart';
import 'paper.dart';

/// A bottom sheet over the board: glass, top border, handle.
class _BoardSheet extends StatelessWidget {
  const _BoardSheet({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      Positioned.fill(
        child: GestureDetector(
          onTap: () => Navigator.of(context).pop(),
          child: ColoredBox(color: VPalette.of(context).popupScrim),
        ),
      ),
      Positioned(
        left: 0,
        right: 0,
        bottom: 0,
        child: VGlass(
          radius: 28,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          tint: VPalette.of(context).glassSheet,
          blur: 14,
          border: false,
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: VInk.of(context))),
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 36,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: VInk.of(context),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    child,
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ],
  );
}

/// C33: size (with a live stroke), opacity, smoothing, pressure, and the
/// nib angle for calligraphy. Returns the new settings.
Future<PenSettings?> showToolOptions(
  BuildContext context, {
  required PenTool tool,
  required PenSettings pen,
  required int argb,
}) => showOverlayPage<PenSettings>(
  context,
  (_) => _ToolOptions(tool: tool, pen: pen, argb: argb),
);

class _ToolOptions extends StatefulWidget {
  const _ToolOptions({
    required this.tool,
    required this.pen,
    required this.argb,
  });

  final PenTool tool;
  final PenSettings pen;
  final int argb;

  @override
  State<_ToolOptions> createState() => _ToolOptionsState();
}

class _ToolOptionsState extends State<_ToolOptions> {
  late var _pen = widget.pen;

  @override
  Widget build(BuildContext context) {
    final preview = Stroke(
      tool: widget.tool == PenTool.eraser ? PenTool.fineLiner : widget.tool,
      argb: widget.tool == PenTool.eraser
          ? VInk.of(context).toARGB32()
          : widget.argb,
      size: _pen.size,
      opacity: _pen.opacity,
      points: [
        for (var x = 10.0; x <= 290; x += 6)
          Offset(x, 30 + math.sin(x / 290 * 2 * math.pi) * 16),
      ],
    );
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(_pen);
      },
      child: _BoardSheet(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(child: Text(widget.tool.label, style: VText.doto(26))),
                VCircleButton(
                  icon: VIcon.check,
                  size: 40,
                  filled: true,
                  onTap: () => Navigator.of(context).pop(_pen),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Container(
              height: 86,
              decoration: BoxDecoration(
                color: VInk.surfaceOf(context),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: VInk.of(context)),
              ),
              child: Center(
                child: SizedBox(
                  width: 300,
                  height: 60,
                  child: CustomPaint(
                    painter: StrokesPainter([
                      preview,
                    ], space: const Size(300, 60)),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            VSlider(
              label: 'Size',
              value: (_pen.size - 1) / 39,
              display: '${_pen.size.round()}',
              onChanged: (v) =>
                  setState(() => _pen = _pen.copyWith(size: 1 + v * 39)),
            ),
            const SizedBox(height: 10),
            VSlider(
              label: 'Opacity',
              value: _pen.opacity,
              onChanged: (v) => setState(
                () => _pen = _pen.copyWith(opacity: math.max(0.1, v)),
              ),
            ),
            const SizedBox(height: 10),
            VSlider(
              label: 'Smoothing',
              value: _pen.smoothing,
              display: '${(_pen.smoothing * 100).round()}',
              onChanged: (v) =>
                  setState(() => _pen = _pen.copyWith(smoothing: v)),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(child: Text('Pressure', style: VText.rowTitle)),
                VSwitch(
                  value: _pen.pressure,
                  onChanged: (v) =>
                      setState(() => _pen = _pen.copyWith(pressure: v)),
                ),
              ],
            ),
            if (widget.tool == PenTool.calligraphy) ...[
              const SizedBox(height: 14),
              Text('Nib angle', style: VText.rowTitle),
              const SizedBox(height: 8),
              VSegmented<int>(
                segments: const {0: '0°', 30: '30°', 45: '45°', 60: '60°'},
                value: _pen.nibAngle,
                onChanged: (v) =>
                    setState(() => _pen = _pen.copyWith(nibAngle: v)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// C34: the colour wheel, brightness, recent colours, presets and hex.
Future<int?> showColourSheet(
  BuildContext context, {
  required int argb,
  required List<int> recent,
}) => showOverlayPage<int>(
  context,
  (_) => _ColourSheet(argb: argb, recent: recent),
);

class _ColourSheet extends StatefulWidget {
  const _ColourSheet({required this.argb, required this.recent});

  final int argb;
  final List<int> recent;

  @override
  State<_ColourSheet> createState() => _ColourSheetState();
}

class _ColourSheetState extends State<_ColourSheet> {
  late HSVColor _hsv = HSVColor.fromColor(VPenColors.of(widget.argb));

  int get _argb => _hsv.toColor().toARGB32();

  String get _hex =>
      '#${(_argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

  void _pickOnWheel(Offset p, double size) {
    final c = Offset(size / 2, size / 2);
    final d = p - c;
    final r = (d.distance / (size / 2)).clamp(0.0, 1.0);
    final hue = (math.atan2(d.dy, d.dx) * 180 / math.pi + 360 + 90) % 360;
    setState(() => _hsv = _hsv.withHue(hue).withSaturation(r));
  }

  @override
  Widget build(BuildContext context) {
    final ink = VInk.of(context);
    final paper = VInk.surfaceOf(context);
    final colour = _hsv.toColor();
    Widget swatch(int c, {double size = 32, double radius = 16}) => Semantics(
      button: true,
      label: '#${(c & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}',
      child: VTappable(
        onTap: () =>
            setState(() => _hsv = HSVColor.fromColor(VPenColors.of(c))),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: VPenColors.of(c),
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: ink),
          ),
        ),
      ),
    );
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(_argb);
      },
      child: _BoardSheet(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(child: Text('Colour', style: VText.doto(26))),
                Semantics(
                  button: true,
                  label: 'Use this colour',
                  child: VTappable(
                    onTap: () => Navigator.of(context).pop(_argb),
                    child: Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: colour,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(color: paper, spreadRadius: 2),
                          BoxShadow(color: ink, spreadRadius: 3),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Center(
              child: GestureDetector(
                onPanDown: (d) => _pickOnWheel(d.localPosition, 210),
                onPanUpdate: (d) => _pickOnWheel(d.localPosition, 210),
                child: SizedBox.square(
                  dimension: 210,
                  child: CustomPaint(
                    painter: _Wheel(ink),
                    child: Builder(
                      builder: (context) {
                        final a = (_hsv.hue - 90) * math.pi / 180;
                        final r = _hsv.saturation * 105;
                        return Stack(
                          children: [
                            Positioned(
                              left: 105 + math.cos(a) * r - 11,
                              top: 105 + math.sin(a) * r - 11,
                              child: Container(
                                width: 22,
                                height: 22,
                                decoration: BoxDecoration(
                                  color: colour,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: VColors.white,
                                    width: 3,
                                  ),
                                  boxShadow: const [
                                    BoxShadow(
                                      color: VColors.black,
                                      spreadRadius: 1,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            _Brightness(
              hsv: _hsv,
              onChanged: (v) => setState(() => _hsv = _hsv.withValue(v)),
            ),
            const SizedBox(height: 14),
            Text('RECENT', style: VText.eyebrow),
            const SizedBox(height: 8),
            Row(
              children: [
                for (final c in widget.recent) ...[
                  swatch(c),
                  const SizedBox(width: 10),
                ],
              ],
            ),
            const SizedBox(height: 14),
            Text('PRESETS', style: VText.eyebrow),
            const SizedBox(height: 8),
            LayoutBuilder(
              builder: (context, box) {
                final s = (box.maxWidth - 7 * 8) / 8;
                return Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final c in VPenColors.presets)
                      swatch(c, size: s, radius: 10),
                  ],
                );
              },
            ),
            const SizedBox(height: 14),
            VOutlined(
              radius: 999,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    Text('HEX', style: VText.eyebrow),
                    const SizedBox(width: 12),
                    Text(_hex, style: VText.mono.copyWith(fontSize: 15)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The hue wheel: hues round the edge, white at the centre.
class _Wheel extends CustomPainter {
  _Wheel(this.ink);

  final Color ink;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final c = rect.center;
    final r = size.width / 2;
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = const SweepGradient(
          colors: VPenColors.wheel,
          transform: GradientRotation(-math.pi / 2),
        ).createShader(rect),
    );
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = RadialGradient(
          colors: [VColors.white, VColors.white.withValues(alpha: 0)],
        ).createShader(rect),
    );
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..color = ink
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(_Wheel old) => old.ink != ink;
}

/// Black to the colour to white… as a single brightness track.
class _Brightness extends StatelessWidget {
  const _Brightness({required this.hsv, required this.onChanged});

  final HSVColor hsv;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final ink = VInk.of(context);
    return LayoutBuilder(
      builder: (context, box) {
        final w = box.maxWidth;
        void set(double x) => onChanged((x / w).clamp(0.0, 1.0));
        return Semantics(
          slider: true,
          label: 'Brightness',
          value: '${(hsv.value * 100).round()}%',
          child: GestureDetector(
            onTapDown: (d) => set(d.localPosition.dx),
            onHorizontalDragUpdate: (d) => set(d.localPosition.dx),
            child: SizedBox(
              height: 26,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    top: 2,
                    bottom: 2,
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(11),
                        border: Border.all(color: ink),
                        gradient: LinearGradient(
                          colors: [VColors.black, hsv.withValue(1).toColor()],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: (w * hsv.value - 13).clamp(0.0, w - 26),
                    top: 0,
                    child: Container(
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        color: hsv.toColor(),
                        shape: BoxShape.circle,
                        border: Border.all(color: VColors.white, width: 3),
                        boxShadow: const [
                          BoxShadow(color: VColors.black, spreadRadius: 1),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// C35: what to do with the lasso's strokes.
class LassoBar extends StatelessWidget {
  const LassoBar({super.key, required this.onAction});

  final void Function(String action) onAction;

  @override
  Widget build(BuildContext context) {
    return VGlass(
      radius: 999,
      tint: VPalette.of(context).glassSheet,
      blur: 14,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (i, (a, icon, label)) in [
            ('move', VIcon.move, 'Move'),
            ('recolour', VIcon.recolour, 'Recolour'),
            ('duplicate', VIcon.copy, 'Duplicate'),
            ('sticker', VIcon.sticker, 'Sticker'),
            ('delete', VIcon.trash, 'Delete'),
          ].indexed) ...[
            if (i > 0) Container(width: 1, height: 52, color: VInk.of(context)),
            Semantics(
              button: true,
              label: label,
              excludeSemantics: true,
              child: VTappable(
                onTap: () {
                  HapticFeedback.selectionClick();
                  onAction(a);
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 11,
                    vertical: 10,
                  ),
                  child: Column(
                    children: [
                      VIconView(icon, size: 20),
                      const SizedBox(height: 4),
                      Text(label, style: VText.inter(11, weight: 500)),
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
}

/// C30: a name and the paper. Returns them, or null.
Future<(String, Paper)?> showNewDoodle(
  BuildContext context, {
  required String partner,
}) => showOverlayPage<(String, Paper)>(
  context,
  (_) => _NewDoodle(partner: partner),
);

class _NewDoodle extends StatefulWidget {
  const _NewDoodle({required this.partner});

  final String partner;

  @override
  State<_NewDoodle> createState() => _NewDoodleState();
}

class _NewDoodleState extends State<_NewDoodle> {
  final _name = TextEditingController(text: 'Sunday plans');
  var _paper = Paper.dotted;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ink = VInk.of(context);
    final paper = VInk.surfaceOf(context);
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: ColoredBox(color: VPalette.of(context).popupScrim),
          ),
        ),
        Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: VGlass(
              radius: 28,
              tint: VPalette.of(context).glassSheet,
              blur: 14,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 22, 18, 18),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('New doodle', style: VText.doto(26)),
                    const SizedBox(height: 14),
                    Text('NAME', style: VText.eyebrow),
                    const SizedBox(height: 8),
                    VTextField(controller: _name, autofocus: true),
                    const SizedBox(height: 14),
                    Text('PAPER', style: VText.eyebrow),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        for (final p in Paper.values) ...[
                          if (p != Paper.plain) const SizedBox(width: 8),
                          Expanded(
                            child: Semantics(
                              button: true,
                              selected: p == _paper,
                              label: p.name,
                              child: VTappable(
                                onTap: () => setState(() => _paper = p),
                                child: Column(
                                  children: [
                                    Container(
                                      height: 78,
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(color: ink),
                                        boxShadow: p == _paper
                                            ? [
                                                BoxShadow(
                                                  color: paper,
                                                  spreadRadius: 3,
                                                ),
                                                BoxShadow(
                                                  color: ink,
                                                  spreadRadius: 5,
                                                ),
                                              ]
                                            : null,
                                      ),
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(11),
                                        child: PaperView(p),
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      p.name[0].toUpperCase() +
                                          p.name.substring(1),
                                      style: VText.inter(11, weight: 500),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(
                          child: VButton.secondary(
                            'Cancel',
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: VButton.primary(
                            'Create',
                            onPressed: () =>
                                Navigator.of(context).pop((_name.text, _paper)),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      '${widget.partner} gets it straight away and can draw too.',
                      style: VText.secondary,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
