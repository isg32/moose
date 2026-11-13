import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../core/icons/v_icons.dart';
import '../../core/theme/v_colors.dart';
import '../../core/theme/v_palette.dart';
import '../../core/theme/v_text.dart';
import '../../core/widgets/v_buttons.dart';
import '../../core/widgets/v_glass.dart';
import '../../core/widgets/v_ink.dart';
import '../../core/widgets/v_surface.dart';
import '../../data/models.dart';
import '../../mock/mock_data.dart';
import '../common/art.dart';
import '../common/overlay.dart';

/// What the attach sheet was asked for.
sealed class AttachChoice {
  const AttachChoice();
}

/// Recent photos tapped: they go to the composer's strip.
class AttachRecent extends AttachChoice {
  const AttachRecent(this.media);
  final List<Media> media;
}

/// One of the seven tiles.
class AttachTile extends AttachChoice {
  const AttachTile(this.kind);
  final AttachKind kind;
}

enum AttachKind {
  gallery('Gallery', VIcon.image),
  camera('Camera', VIcon.camera),
  roundVideo('Round video', VIcon.roundVideo),
  music('Music', VIcon.music),
  meme('Meme', VIcon.meme),
  doodle('Doodle', VIcon.doodle),
  poke('Poke', VIcon.poke);

  const AttachKind(this.label, this.icon);
  final String label;
  final VIcon icon;
}

/// The attach sheet (C17): recent photos, then the seven tiles.
Future<AttachChoice?> showAttachSheet(
  BuildContext context, {
  bool recent = true,
}) =>
    showOverlayPage<AttachChoice>(context, (_) => AttachSheet(recent: recent));

class AttachSheet extends StatefulWidget {
  const AttachSheet({super.key, this.recent = true});

  /// The strip of recent photos (stand-ins on the mock). Real builds go
  /// straight to the phone's gallery from "All photos".
  final bool recent;

  @override
  State<AttachSheet> createState() => _AttachSheetState();
}

class _AttachSheetState extends State<AttachSheet> {
  final _recent = MockData.gallery().take(6).toList();
  final _picked = <Media>[];

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            onTap: () => Navigator.of(context)
                .pop(_picked.isEmpty ? null : AttachRecent(List.of(_picked))),
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
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 26),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: Container(
                          width: 36,
                          height: 4,
                          decoration: BoxDecoration(
                            color: VInk.of(context),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      // Recent photos (the mock's; a real gallery strip
                      // isn't wired yet, so on Neon the row is left out
                      // rather than shown empty: Gallery opens them all).
                      if (widget.recent) ...[
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Text('RECENT', style: VText.eyebrow),
                            const Spacer(),
                            VTappable(
                              onTap: () => Navigator.of(context)
                                  .pop(const AttachTile(AttachKind.gallery)),
                              child: Text(
                                _picked.isEmpty
                                    ? 'All photos ›'
                                    : 'Add ${_picked.length} ›',
                                style: VText.inter(13, weight: 500),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          height: 84,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: _recent.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(width: 8),
                            itemBuilder: (context, i) {
                              final m = _recent[i];
                              final n = _picked.indexOf(m);
                              return Semantics(
                                button: true,
                                selected: n >= 0,
                                label: 'Recent photo ${i + 1}',
                                child: VTappable(
                                  onTap: () => setState(
                                    () => n >= 0
                                        ? _picked.remove(m)
                                        : _picked.add(m),
                                  ),
                                  child: _Thumb(m, size: 84, number: n + 1),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                      const SizedBox(height: 22),
                      if (_picked.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 18),
                          child: VButton.primary(
                            'Add ${_picked.length} to the message',
                            onPressed: () =>
                                Navigator.of(context)
                                    .pop(AttachRecent(List.of(_picked))),
                          ),
                        ),
                      GridView.count(
                        padding: EdgeInsets.zero, // not the status bar's inset
                        crossAxisCount: 4,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        mainAxisSpacing: 20,
                        crossAxisSpacing: 6,
                        childAspectRatio: 0.92,
                        children: [
                          for (final k in AttachKind.values)
                            Semantics(
                              button: true,
                              label: k.label,
                              child: VTappable(
                                onTap: () {
                                  HapticFeedback.selectionClick();
                                  Navigator.of(context).pop(AttachTile(k));
                                },
                                child: Column(
                                  children: [
                                    SizedBox.square(
                                      dimension: 58,
                                      child: VOutlined(
                                        radius: 29,
                                        child: Center(
                                          child: VIconView(k.icon, size: 24),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      k.label,
                                      style: VText.inter(12, weight: 500),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
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
}

/// A gallery thumbnail, with its pick number and a video's length.
class _Thumb extends StatelessWidget {
  const _Thumb(this.m, {required this.size, this.number = 0});

  final Media m;
  final double size;
  final int number;

  @override
  Widget build(BuildContext context) => ArtBox(
    art: m.art,
    width: size,
    height: size,
    radius: BorderRadius.circular(14),
    child: number > 0
        ? Align(alignment: Alignment.topRight, child: PickMark(number))
        : null,
  );
}

/// The white numbered circle on a picked photo (C18): white whatever the
/// ink, since it sits on the photo.
class PickMark extends StatelessWidget {
  const PickMark(this.number, {super.key});

  /// 0 for not picked: an empty ring.
  final int number;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(6),
    child: Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: number > 0 ? VColors.white : null,
        border: Border.all(color: VColors.white, width: 1.5),
      ),
      alignment: Alignment.center,
      child: number > 0
          ? Text(
              '$number',
              style: VText.inter(
                12,
                weight: 600,
              ).copyWith(color: VColors.black),
            )
          : null,
    ),
  );
}
