import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../core/icons/v_icons.dart';
import '../../core/theme/v_palette.dart';
import '../../core/theme/v_text.dart';
import '../../core/widgets/v_buttons.dart';
import '../../core/widgets/v_glass.dart';
import '../../core/widgets/v_ink.dart';
import '../../core/widgets/v_surface.dart';
import '../../data/models.dart';
import '../common/overlay.dart';
import '../common/parts.dart';
import 'bubbles.dart';

/// What was picked on the message actions overlay.
sealed class MessageAction {
  const MessageAction();
}

class ReactAction extends MessageAction {
  const ReactAction(this.emoji);
  final String emoji;
}

class ReplyAction extends MessageAction {
  const ReplyAction();
}

class CopyAction extends MessageAction {
  const CopyAction();
}

class SaveAction extends MessageAction {
  const SaveAction();
}

class DeleteAction extends MessageAction {
  const DeleteAction();
}

/// The six quick reactions (B3).
const quickReactions = ['❤️', '😂', '🥺', '😮', '🔥', '👍'];

/// Opens the long-press overlay for [m] (B13).
Future<MessageAction?> showMessageActions(
  BuildContext context, {
  required Message m,
  required String partner,
}) => showOverlayPage<MessageAction>(
  context,
  (_) => MessageActions(message: m, partner: partner),
);

class MessageActions extends StatelessWidget {
  const MessageActions({
    super.key,
    required this.message,
    required this.partner,
  });

  final Message message;
  final String partner;

  bool get _media => switch (message.body) {
    PhotoBody() || VideoBody() || RoundVideoBody() || MemeBody() => true,
    StickerBody() => true,
    _ => false,
  };

  @override
  Widget build(BuildContext context) {
    void pick(MessageAction a) {
      HapticFeedback.selectionClick();
      Navigator.of(context).pop(a);
    }

    final m = message;
    final info = [
      'Sent ${hhmm(m.at)}',
      if (m.fromMe && m.delivery.index >= Delivery.delivered.index)
        'Delivered ${hhmm(m.deliveredAt ?? m.at)}',
      if (m.fromMe && m.delivery == Delivery.seen)
        'Seen ${hhmm(m.seenAt ?? m.at)}',
    ].join(' · ');

    return Stack(
      fit: StackFit.expand,
      children: [
        GestureDetector(
          onTap: () => Navigator.of(context).pop(),
          child: ColoredBox(color: VPalette.of(context).popupScrim),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 120, 14, 0),
            child: Column(
              crossAxisAlignment: m.fromMe
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                VGlass(
                  radius: 999,
                  tint: VPalette.of(context).glassSheet,
                  blur: 14,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final e in quickReactions)
                          Semantics(
                            button: true,
                            label: 'React $e',
                            child: VTappable(
                              onTap: () => pick(ReactAction(e)),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                ),
                                child: Text(
                                  e,
                                  style: const TextStyle(fontSize: 26),
                                ),
                              ),
                            ),
                          ),
                        const SizedBox(width: 4),
                        VCircleButton(
                          icon: VIcon.plus,
                          size: 32,
                          onTap: () => pick(const ReactAction('🫶')),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                IgnorePointer(
                  child: MessageView(message: m, partner: partner),
                ),
              ],
            ),
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
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const _Handle(),
                      const SizedBox(height: 6),
                      _Row(
                        VIcon.reply,
                        'Reply',
                        () => pick(const ReplyAction()),
                      ),
                      if (m.body is TextBody)
                        _Row(
                          VIcon.copy,
                          'Copy',
                          () => pick(const CopyAction()),
                        ),
                      _Row(
                        VIcon.download,
                        'Save media',
                        _media ? () => pick(const SaveAction()) : null,
                      ),
                      _Row(VIcon.info, 'Info', null, sub: info, enabled: true),
                      _Row(
                        VIcon.trash,
                        'Delete for me',
                        () => pick(const DeleteAction()),
                        last: true,
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

class _Handle extends StatelessWidget {
  const _Handle();

  @override
  Widget build(BuildContext context) => Container(
    width: 36,
    height: 4,
    decoration: BoxDecoration(
      color: VInk.of(context),
      borderRadius: BorderRadius.circular(2),
    ),
  );
}

class _Row extends StatelessWidget {
  const _Row(
    this.icon,
    this.label,
    this.onTap, {
    this.sub,
    this.last = false,
    bool? enabled,
  }) : enabled = enabled ?? onTap != null;

  final VIcon icon;
  final String label;
  final VoidCallback? onTap;
  final String? sub;
  final bool last;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.35,
      child: VTappable(
        onTap: onTap,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
              child: Row(
                crossAxisAlignment: sub == null
                    ? CrossAxisAlignment.center
                    : CrossAxisAlignment.start,
                children: [
                  VIconView(icon, size: 22),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(label, style: VText.rowTitle),
                        if (sub != null) ...[
                          const SizedBox(height: 4),
                          Text(sub!, style: VText.secondary),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (!last) const VDivider(),
          ],
        ),
      ),
    );
  }
}
