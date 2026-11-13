import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/icons/v_icons.dart';
import '../../core/theme/v_colors.dart';
import '../../core/theme/v_palette.dart';
import '../../core/theme/v_text.dart';
import '../../core/widgets/v_buttons.dart';
import '../../core/widgets/v_controls.dart';
import '../../core/widgets/v_glass.dart';
import '../../core/widgets/v_ink.dart';
import '../../core/widgets/v_list.dart';
import '../../core/widgets/v_page.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../common/art.dart';
import '../common/choice_sheet.dart';
import '../common/overlay.dart';
import '../common/sticker_view.dart';
import '../common/strokes.dart';

/// Make a sticker from a photo or a doodle (S2, S3); it lands in your
/// stickers and is returned when it should be sent too.
Future<Sticker?> makeSticker(BuildContext context, WidgetRef ref) async {
  final from = await showChoiceSheet<String>(
    context,
    title: 'Make a sticker',
    choices: const [
      Choice('photo', 'From a photo', icon: VIcon.image),
      Choice('doodle', 'From a doodle', icon: VIcon.doodle),
    ],
  );
  if (from == null || !context.mounted) return null;
  if (from == 'photo') {
    return pushPage<Sticker>(context, (_) => const PhotoStickerPage(art: 7));
  }
  final doodles = ref.read(doodlesProvider);
  final pick = await showChoiceSheet<Doodle>(
    context,
    title: 'Which doodle?',
    choices: [
      for (final d in doodles)
        Choice(
          d,
          d.name,
          icon: VIcon.doodle,
          sub: '${d.strokes.length} strokes',
        ),
    ],
  );
  if (pick == null || !context.mounted) return null;
  return showDoodleStickerSheet(context, ref, pick.strokes);
}

/// Strokes from a board, fitted into the 0–1 box a sticker uses.
List<Stroke> normalise(List<Stroke> strokes) {
  final pts = [
    for (final s in strokes)
      if (s.tool != PenTool.eraser && s.tool != PenTool.lasso) ...s.points,
  ];
  if (pts.isEmpty) return const [];
  var minX = pts.first.dx, maxX = minX, minY = pts.first.dy, maxY = minY;
  for (final p in pts) {
    minX = math.min(minX, p.dx);
    maxX = math.max(maxX, p.dx);
    minY = math.min(minY, p.dy);
    maxY = math.max(maxY, p.dy);
  }
  final side = math.max(maxX - minX, maxY - minY) * 1.25 + 1;
  final cx = (minX + maxX) / 2, cy = (minY + maxY) / 2;
  Offset f(Offset p) =>
      Offset((p.dx - cx) / side + 0.5, (p.dy - cy) / side + 0.5);
  return [
    for (final s in strokes)
      if (s.tool != PenTool.eraser && s.tool != PenTool.lasso)
        Stroke(
          tool: s.tool,
          argb: s.argb,
          size: s.size / side,
          opacity: s.opacity,
          points: [for (final p in s.points) f(p)],
        ),
  ];
}

/// S3: a doodle (or a lasso selection) as a sticker.
Future<Sticker?> showDoodleStickerSheet(
  BuildContext context,
  WidgetRef ref,
  List<Stroke> strokes,
) => showOverlayPage<Sticker>(
  context,
  (_) => _DoodleStickerSheet(strokes: normalise(strokes)),
);

class _DoodleStickerSheet extends ConsumerStatefulWidget {
  const _DoodleStickerSheet({required this.strokes});

  final List<Stroke> strokes;

  @override
  ConsumerState<_DoodleStickerSheet> createState() =>
      _DoodleStickerSheetState();
}

class _DoodleStickerSheetState extends ConsumerState<_DoodleStickerSheet> {
  var _outline = true;
  var _pack = 'doodles';

  Sticker? _save({required bool send}) {
    final s = Sticker.doodle(
      id: 'st${DateTime.now().microsecondsSinceEpoch}',
      strokes: widget.strokes,
    );
    ref.read(stickersProvider.notifier).add(_pack, s);
    HapticFeedback.selectionClick();
    Navigator.of(context).pop(send ? s : null);
    return s;
  }

  @override
  Widget build(BuildContext context) {
    final packs = ref.watch(stickersProvider);
    return Stack(
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
          child: _SheetFrame(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('New sticker', style: VText.doto(26)),
                const SizedBox(height: 12),
                _Checker(
                  height: 220,
                  child: Transform.rotate(
                    angle: -5 * math.pi / 180,
                    child: SizedBox.square(
                      dimension: 190,
                      child: StrokesView(
                        widget.strokes,
                        space: const Size(1, 1),
                        outline: _outline ? 6 : 0,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: Text('White outline', style: VText.rowTitle),
                    ),
                    VSwitch(
                      value: _outline,
                      onChanged: (v) => setState(() => _outline = v),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                VListSection(
                  children: [
                    VListRow(
                      title: 'Add to pack',
                      value: packs.firstWhere((p) => p.id == _pack).name,
                      onTap: () async {
                        final p = await showChoiceSheet<String>(
                          context,
                          title: 'Add to pack',
                          choices: [
                            for (final p in packs) Choice(p.id, p.name),
                          ],
                        );
                        if (p != null) setState(() => _pack = p);
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: VButton.secondary(
                        'Save',
                        onPressed: () => _save(send: false),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: VButton.primary(
                        'Save and send',
                        onPressed: () => _save(send: true),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// S2: a sticker from a photo. The cut-out is drawn on stand-in art until
/// real photos arrive in Phase 4.
class PhotoStickerPage extends ConsumerStatefulWidget {
  const PhotoStickerPage({super.key, required this.art});

  final int art;

  @override
  ConsumerState<PhotoStickerPage> createState() => _PhotoStickerPageState();
}

enum _Cut { auto, erase, restore, text }

class _PhotoStickerPageState extends ConsumerState<PhotoStickerPage> {
  var _tool = _Cut.auto;
  var _outline = true;
  var _caption = 'us!!';

  Sticker _make() => Sticker.photo(
    id: 'st${DateTime.now().microsecondsSinceEpoch}',
    art: widget.art,
  );

  void _save({required bool send}) {
    final s = _make();
    ref.read(stickersProvider.notifier).add('ours', s);
    HapticFeedback.selectionClick();
    Navigator.of(context).pop(send ? s : null);
  }

  @override
  Widget build(BuildContext context) {
    final partner = ref.watch(pairingProvider).partner.name;
    return Stack(
      fit: StackFit.expand,
      children: [
        const VVeil(),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
            child: Column(
              children: [
                Row(
                  children: [
                    VCircleButton(
                      icon: VIcon.close,
                      size: 44,
                      onTap: () => Navigator.of(context).pop(),
                    ),
                    Expanded(
                      child: Text(
                        'New sticker',
                        textAlign: TextAlign.center,
                        style: VText.inter(15, weight: 600),
                      ),
                    ),
                    VCircleButton(icon: VIcon.undo, size: 44, onTap: () {}),
                  ],
                ),
                const SizedBox(height: 20),
                Expanded(
                  child: _Checker(
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Container(
                          width: 230,
                          height: 270,
                          decoration: BoxDecoration(
                            borderRadius: stickerRadius(0, 230, 270),
                            border: _outline
                                ? Border.all(color: VColors.white, width: 6)
                                : null,
                            boxShadow: [
                              BoxShadow(
                                color: VColors.black.withValues(alpha: 0.4),
                                blurRadius: 30,
                                offset: const Offset(0, 10),
                              ),
                            ],
                          ),
                          child: ArtBox(
                            art: widget.art,
                            radius: stickerRadius(0, 230, 270),
                          ),
                        ),
                        if (_tool == _Cut.auto)
                          IgnorePointer(
                            child: Container(
                              width: 250,
                              height: 290,
                              decoration: BoxDecoration(
                                borderRadius: stickerRadius(0, 250, 290),
                                border: Border.all(
                                  color: VColors.black,
                                  width: 1.5,
                                ),
                              ),
                            ),
                          ),
                        if (_caption.isNotEmpty)
                          Positioned(
                            bottom: 28,
                            child: Transform.rotate(
                              angle: -4 * math.pi / 180,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: VColors.white,
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  _caption,
                                  style: VText.doto(
                                    22,
                                    weight: 700,
                                  ).copyWith(color: VColors.black),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    for (final (t, icon, label) in [
                      (_Cut.auto, VIcon.cutOut, 'Auto cut'),
                      (_Cut.erase, VIcon.eraser, 'Erase'),
                      (_Cut.restore, VIcon.doodle, 'Restore'),
                      (_Cut.text, VIcon.text, 'Text'),
                    ])
                      _Tool(
                        icon: icon,
                        label: label,
                        on: _tool == t,
                        onTap: () => setState(() {
                          _tool = t;
                          if (t == _Cut.text) {
                            _caption = _caption.isEmpty ? 'us!!' : '';
                          }
                        }),
                      ),
                    _Tool(
                      icon: VIcon.outline,
                      label: 'Outline',
                      on: _outline,
                      onTap: () => setState(() => _outline = !_outline),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: VButton.secondary(
                        'Save',
                        onPressed: () => _save(send: false),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: VButton.primary(
                        'Send to $partner',
                        onPressed: () => _save(send: true),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Tool extends StatelessWidget {
  const _Tool({
    required this.icon,
    required this.label,
    required this.on,
    required this.onTap,
  });

  final VIcon icon;
  final String label;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: on,
    label: label,
    child: VTappable(
      onTap: onTap,
      child: Column(
        children: [
          VCircleButton(icon: icon, size: 48, filled: on),
          const SizedBox(height: 6),
          Text(label, style: VText.inter(11, weight: 500)),
        ],
      ),
    ),
  );
}

/// The see-through checkerboard stickers are made on.
class _Checker extends StatelessWidget {
  const _Checker({required this.child, this.height});

  final Widget child;
  final double? height;

  @override
  Widget build(BuildContext context) => Container(
    height: height,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: VInk.of(context)),
    ),
    clipBehavior: Clip.antiAlias,
    child: CustomPaint(
      painter: _CheckerPainter(),
      child: Center(child: child),
    ),
  );
}

class _CheckerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = VColors.white);
    final grey = Paint()..color = VColors.black.withValues(alpha: 0.1);
    const s = 8.0;
    for (var y = 0.0; y < size.height; y += s) {
      for (var x = ((y / s).floor() % 2) * s; x < size.width; x += s * 2) {
        canvas.drawRect(Rect.fromLTWH(x, y, s, s), grey);
      }
    }
  }

  @override
  bool shouldRepaint(_CheckerPainter old) => false;
}

/// The glass sheet frame these sticker sheets share.
class _SheetFrame extends StatelessWidget {
  const _SheetFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => VGlass(
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
  );
}

/// S4: a sticker Aatika sent: favourite it, save it, or save her pack.
Future<void> showReceivedSticker(
  BuildContext context,
  WidgetRef ref,
  Sticker sticker,
) => showOverlayPage<void>(context, (_) => _ReceivedSticker(sticker: sticker));

class _ReceivedSticker extends ConsumerWidget {
  const _ReceivedSticker({required this.sticker});

  final Sticker sticker;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final partner = ref.watch(pairingProvider).partner.name;
    final packs = ref.watch(stickersProvider);
    final pack = packs
        .where((p) => p.stickers.any((s) => s.id == sticker.id))
        .firstOrNull;
    final n = ref.read(stickersProvider.notifier);
    void done(String text) {
      HapticFeedback.selectionClick();
      Navigator.of(context).pop();
    }

    return Stack(
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
          child: _SheetFrame(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(child: StickerView(sticker, size: 170, tilt: -4)),
                const SizedBox(height: 16),
                Text(
                  'From $partner',
                  textAlign: TextAlign.center,
                  style: VText.inter(15, weight: 600),
                ),
                Text(
                  pack == null
                      ? 'Not in your stickers yet'
                      : 'In her pack "${pack.name}" · ${pack.stickers.length} stickers',
                  textAlign: TextAlign.center,
                  style: VText.secondary,
                ),
                const SizedBox(height: 14),
                VButton.secondary(
                  sticker.favourite
                      ? 'Remove from favourites'
                      : 'Add to favourites',
                  onPressed: () {
                    if (pack == null) n.add('ours', sticker);
                    n.toggleFavourite(sticker.id);
                    done('Favourite');
                  },
                ),
                const SizedBox(height: 10),
                VButton.secondary(
                  'Save to my stickers',
                  onPressed: () {
                    if (pack == null) n.add('ours', sticker);
                    done('Saved');
                  },
                ),
                const SizedBox(height: 10),
                VButton.primary(
                  'Save the whole pack',
                  onPressed: () => done('Saved the pack'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// S5: every sticker you keep, by pack (Settings › Stickers).
class StickerLibraryPage extends ConsumerWidget {
  const StickerLibraryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final packs = ref.watch(stickersProvider);
    final count = packs.fold<int>(0, (n, p) => n + p.stickers.length);
    final partner = ref.watch(pairingProvider).partner.name;
    return VDetailPage(
      backLabel: 'Settings',
      title: 'Stickers',
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4),
          child: Text(
            '$count stickers · ${(count * 0.13).toStringAsFixed(1)} MB on this phone',
            style: VText.secondary,
          ),
        ),
        VListSection(
          children: [
            VListRow(
              title: 'From a photo',
              leading: const VIconView(VIcon.image, size: 20),
              onTap: () => pushPage<Sticker>(
                context,
                (_) => const PhotoStickerPage(art: 7),
              ),
            ),
            VListRow(
              title: 'From a doodle',
              leading: const VIconView(VIcon.doodle, size: 20),
              onTap: () {
                final d = ref.read(doodlesProvider).first;
                showDoodleStickerSheet(context, ref, d.strokes);
              },
            ),
          ],
        ),
        VListSection(
          children: [
            for (final p in packs)
              VListRow(
                title: p.name,
                subtitle: p.note,
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final s in p.stickers.take(3))
                      Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: StickerView(
                          s,
                          size: 34,
                          border: 2,
                          shadow: false,
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
        VFootnote(
          'Stickers live on this phone. Sending one sends $partner a copy she can save.',
        ),
      ],
    );
  }
}
