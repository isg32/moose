import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/icons/v_icons.dart';
import '../../core/theme/v_palette.dart';
import '../../core/theme/v_text.dart';
import '../../core/widgets/v_buttons.dart';
import '../../core/widgets/v_glass.dart';
import '../../core/widgets/v_ink.dart';
import '../../core/widgets/v_page.dart';
import '../../core/widgets/v_surface.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../common/choice_sheet.dart';
import '../common/overlay.dart';
import '../common/parts.dart';
import '../common/strokes.dart';
import '../common/toast.dart';
import '../stickers/sticker_maker.dart';
import 'board_page.dart';
import 'doodle_sheets.dart';
import 'paper.dart';

/// The Doodles tab (C29): every shared board, newest first.
class DoodlesPage extends ConsumerWidget {
  const DoodlesPage({super.key});

  Future<void> _new(BuildContext context, WidgetRef ref) async {
    final partner = ref.read(pairingProvider).partner.name;
    final made = await showNewDoodle(context, partner: partner);
    if (made == null || !context.mounted) return;
    final d = ref.read(doodlesProvider.notifier).create(made.$1, made.$2);
    ref
        .read(messagesProvider.notifier)
        .send(SystemBody(SystemKind.doodle, 'New doodle: ${d.name}'));
    await openBoard(context, d.id);
  }

  Future<void> _hold(BuildContext context, WidgetRef ref, Doodle d) async {
    unawaited(HapticFeedback.mediumImpact());
    final a = await showChoiceSheet<String>(
      context,
      title: d.name,
      choices: const [
        Choice('rename', 'Rename', icon: VIcon.doodle),
        Choice('send', 'Send to chat', icon: VIcon.send),
        Choice('delete', 'Delete for both', icon: VIcon.trash),
      ],
    );
    if (!context.mounted || a == null) return;
    final n = ref.read(doodlesProvider.notifier);
    switch (a) {
      case 'rename':
        final name = await showRename(context, d.name);
        if (name != null && name.trim().isNotEmpty) n.rename(d.id, name.trim());
      case 'send':
        ref
            .read(messagesProvider.notifier)
            .send(
              StickerBody(
                Sticker.doodle(
                  id: 'snap${DateTime.now().microsecondsSinceEpoch}',
                  strokes: normalise(d.strokes),
                ),
              ),
            );
        showToast(context, 'Sent to ${ref.read(pairingProvider).partner.name}');
      case 'delete':
        final sure = await showConfirm(
          context,
          title: 'Delete this doodle?',
          body: "It goes for both of you. This can't be undone.",
          yes: 'Delete',
        );
        if (sure == true) n.delete(d.id);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final doodles = ref.watch(doodlesProvider);
    final partner = ref.watch(pairingProvider).partner.name;
    return VTabPage(
      title: 'Doodles',
      header: Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 14),
        child: Text(
          '${doodles.length} board${doodles.length == 1 ? '' : 's'}, shared with $partner',
          style: VText.secondary,
        ),
      ),
      children: [
        // With no boards yet, just this (it has the button).
        if (doodles.isEmpty)
          EmptyCard(
            title: 'Nothing here yet',
            body: 'Start a doodle and $partner can draw on it too.',
            action: 'New doodle',
            onAction: () => _new(context, ref),
          ),
        if (doodles.isNotEmpty)
          GridView.count(
            padding: EdgeInsets.zero, // not the status bar's inset
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 0.8,
            children: [
              // With no boards yet, the empty card above has the button.
              if (doodles.isNotEmpty)
                Semantics(
                  button: true,
                  label: 'New doodle',
                  excludeSemantics: true,
                  child: VTappable(
                    onTap: () => _new(context, ref),
                    child: VOutlined(
                      radius: 20,
                      outline: VOutline.dashed,
                      fill: VGlass.dim(context),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const VIconView(VIcon.plus, size: 24),
                            const SizedBox(height: 8),
                            Text(
                              'New doodle',
                              style: VText.inter(14, weight: 500),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              for (final d in doodles)
                _Card(
                  d,
                  partner: partner,
                  onTap: () => openBoard(context, d.id),
                  onHold: () => _hold(context, ref, d),
                ),
            ],
          ),
      ],
    );
  }
}

/// Opens a board full screen.
Future<void> openBoard(BuildContext context, String id) =>
    pushPage<void>(context, (_) => BoardPage(id: id));

class _Card extends StatelessWidget {
  const _Card(
    this.d, {
    required this.partner,
    required this.onTap,
    required this.onHold,
  });

  final Doodle d;
  final String partner;
  final VoidCallback onTap;
  final VoidCallback onHold;

  String get _when {
    final ago = DateTime.now().difference(d.editedAt);
    if (ago.inMinutes < 1) return 'now';
    if (ago.inHours < 1) return '${ago.inMinutes} min ago';
    if (ago.inDays < 1) return '${ago.inHours} h ago';
    if (ago.inDays == 1) return 'yesterday';
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return days[d.editedAt.weekday - 1];
  }

  @override
  Widget build(BuildContext context) {
    final ink = VInk.of(context);
    final paper = VInk.surfaceOf(context);
    return Semantics(
      button: true,
      label: d.name,
      excludeSemantics: true,
      child: GestureDetector(
        onLongPress: onHold,
        child: VTappable(
          onTap: onTap,
          child: VGlass(
            radius: 20,
            tint: VPalette.of(context).glassCard,
            blur: 16,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(19),
                    ),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        PaperView(
                          d.paper == Paper.wallpaper ? Paper.plain : d.paper,
                        ),
                        Padding(
                          padding: const EdgeInsets.all(8),
                          child: StrokesView(d.strokes, space: boardSpace),
                        ),
                        if (d.partnerHere)
                          Positioned(
                            left: 8,
                            top: 8,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: ink,
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 6,
                                    height: 6,
                                    decoration: BoxDecoration(
                                      color: paper,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    '$partner here',
                                    style: VText.inter(
                                      10,
                                      weight: 600,
                                    ).copyWith(color: paper),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                Container(height: 1, color: ink),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 9, 12, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        d.name,
                        style: VText.inter(14, weight: 500),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text('${d.editedBy} · $_when', style: VText.secondary),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A dialog in the middle of the screen (A7): title, body, two buttons.
Future<bool?> showConfirm(
  BuildContext context, {
  required String title,
  required String body,
  required String yes,
  String no = 'Keep',
}) => showOverlayPage<bool>(
  context,
  (context) => Stack(
    children: [
      Positioned.fill(
        child: GestureDetector(
          onTap: () => Navigator.of(context).pop(false),
          child: ColoredBox(color: VPalette.of(context).popupScrim),
        ),
      ),
      Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: VGlass(
            radius: 28,
            tint: VPalette.of(context).glassSheet,
            blur: 14,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(title, style: VText.doto(22)),
                  const SizedBox(height: 10),
                  Text(body, style: VText.inter(13, weight: 300)),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: VButton.secondary(
                          no,
                          onPressed: () => Navigator.of(context).pop(false),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: VButton.primary(
                          yes,
                          onPressed: () => Navigator.of(context).pop(true),
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
    ],
  ),
);

/// Rename a board.
Future<String?> showRename(BuildContext context, String name) {
  final c = TextEditingController(text: name);
  return showVSheet<String>(
    context,
    title: 'Rename',
    builder: (context) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        VTextField(
          controller: c,
          autofocus: true,
          onSubmitted: (v) => Navigator.of(context).pop(v),
        ),
        const SizedBox(height: 14),
        VButton.primary(
          'Save',
          onPressed: () => Navigator.of(context).pop(c.text),
        ),
      ],
    ),
  ).whenComplete(c.dispose);
}
