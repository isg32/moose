import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/version.dart';
import '../../core/icons/v_icons.dart';
import '../../core/theme/v_text.dart';
import '../../core/widgets/v_buttons.dart';
import '../../core/widgets/v_controls.dart';
import '../../core/widgets/v_glass.dart';
import '../../core/widgets/v_list.dart';
import '../../core/widgets/v_page.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../common/avatar.dart';
import '../common/choice_sheet.dart';
import '../common/overlay.dart';
import '../common/parts.dart';
import '../common/toast.dart';
import '../lock/lock_pages.dart';
import '../stickers/sticker_maker.dart';
import 'settings_pages.dart';

/// Settings (C36): you, your partner, chat, notifications, privacy,
/// stickers, storage and About.
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  static String checkLine({required bool neon, DateTime? last}) {
    if (!neon) return 'Every 6 min · last 2 min ago';
    if (last == null) return 'Every 6 min · not yet';
    final m = DateTime.now().difference(last).inMinutes;
    return 'Every 6 min · last ${m < 1 ? 'just now' : '$m min ago'}';
  }

  Future<void> _rename(BuildContext context, WidgetRef ref) async {
    final c = TextEditingController(text: ref.read(pairingProvider).me.name);
    final name = await showVSheet<String>(
      context,
      title: 'Your name',
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
    );
    c.dispose();
    if (name != null && name.trim().isNotEmpty) {
      ref.read(pairingProvider.notifier).rename(name.trim());
      unawaited(
        ref
            .read(pairRepositoryProvider)
            .setName(name.trim())
            .catchError((_) {}),
      );
    }
  }

  Future<void> _setPin(BuildContext context, WidgetRef ref) async {
    final pin = await pushPage<String>(
      context,
      (_) => const PinEntryPage(eyebrow: 'App lock', back: 'Privacy'),
    );
    if (pin != null) ref.read(sessionProvider.notifier).setPin(pin);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pairing = ref.watch(pairingProvider);
    final session = ref.watch(sessionProvider);
    final settings = ref.watch(settingsProvider);
    final storage = ref.watch(storageProvider);
    final cache = ref.watch(storageRepositoryProvider).cacheBytes;
    final s = ref.read(settingsProvider.notifier);
    final used = storage.fold<int>(0, (n, u) => n + u.bytes);
    final lock = session.pin.isNotEmpty;
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final since = pairing.since;

    return VTabPage(
      title: 'Settings',
      veil: true,
      children: [
        VListSection(
          children: [
            VListRow(
              leading: Avatar(pairing.me, size: 44, filled: true),
              title: pairing.me.name,
              subtitle: 'Your name and picture',
              onTap: () => _rename(context, ref),
            ),
          ],
        ),
        const VEyebrow('Partner'),
        VListSection(
          children: [
            VListRow(
              leading: Avatar(pairing.partner, size: 32),
              title: pairing.partner.name,
              subtitle:
                  'Paired since ${since.day} ${months[since.month - 1]} ${since.year}',
              onTap: () => pushPage<void>(context, (_) => const PartnerPage()),
            ),
          ],
        ),
        const VEyebrow('Chat'),
        VListSection(
          children: [
            VListRow(
              title: 'Enter sends',
              trailing: VSwitch(
                value: settings.enterSends,
                onChanged: (v) => s.update((x) => x.copyWith(enterSends: v)),
              ),
            ),
            VListRow(
              title: 'Autoplay GIFs',
              trailing: VSwitch(
                value: settings.autoplayGifs,
                onChanged: (v) => s.update((x) => x.copyWith(autoplayGifs: v)),
              ),
            ),
            VListRow(
              title: 'Download media',
              value: settings.autoDownload.label,
              onTap: () async {
                final v = await showChoiceSheet<AutoDownload>(
                  context,
                  title: 'Download media',
                  choices: [
                    for (final a in AutoDownload.values) Choice(a, a.label),
                  ],
                );
                if (v != null) s.update((x) => x.copyWith(autoDownload: v));
              },
            ),
          ],
        ),
        const VEyebrow('Notifications'),
        VListSection(
          children: [
            VListRow(
              title: 'Pokes and messages',
              onTap: () =>
                  pushPage<void>(context, (_) => const NotificationsPage()),
            ),
            VListRow(
              title: 'Background check',
              subtitle: checkLine(
                neon: ref.watch(onNeonProvider),
                last: ref.watch(backgroundCheckProvider).value,
              ),
              value: 'Running',
              chevron: false,
            ),
          ],
        ),
        const VEyebrow('Privacy'),
        VListSection(
          children: [
            VListRow(
              title: 'App lock',
              trailing: VSwitch(
                value: lock,
                onChanged: (on) => on
                    ? _setPin(context, ref)
                    : ref.read(sessionProvider.notifier).removeLock(),
              ),
            ),
            if (lock) ...[
              VListRow(title: 'Change PIN', onTap: () => _setPin(context, ref)),
              VListRow(
                title: 'Decoy PIN',
                subtitle: session.decoyPin == null
                    ? 'Off'
                    : 'Opens an empty chat with ${session.decoyName}',
                value: session.decoyPin == null ? null : 'Set',
                onTap: () =>
                    pushPage<void>(context, (_) => const DecoyPinPage()),
              ),
              VListRow(
                title: 'Lock after',
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(settings.lockAfter.label, style: VText.doto(15)),
                    const SizedBox(width: 4),
                    const VIconView(VIcon.chevron, size: 18),
                  ],
                ),
                onTap: () async {
                  final v = await showChoiceSheet<LockAfter>(
                    context,
                    title: 'Lock after',
                    choices: [
                      for (final l in LockAfter.values) Choice(l, l.label),
                    ],
                  );
                  if (v != null) s.update((x) => x.copyWith(lockAfter: v));
                },
              ),
            ],
            VListRow(
              title: 'Hide in recent apps',
              trailing: VSwitch(
                value: settings.hideInRecents,
                onChanged: (v) => s.update((x) => x.copyWith(hideInRecents: v)),
              ),
            ),
          ],
        ),
        const VEyebrow('Stickers'),
        VListSection(
          children: [
            VListRow(
              title: 'Your stickers',
              value:
                  '${ref.watch(stickersProvider).fold<int>(0, (n, p) => n + p.stickers.length)}',
              onTap: () =>
                  pushPage<void>(context, (_) => const StickerLibraryPage()),
            ),
          ],
        ),
        const VEyebrow('Storage'),
        VListSection(
          children: [
            VListRow(
              title: 'Media on this phone',
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(bytes(used), style: VText.doto(15)),
                  const SizedBox(width: 4),
                  const VIconView(VIcon.chevron, size: 18),
                ],
              ),
              onTap: () => pushPage<void>(context, (_) => const StoragePage()),
            ),
            VListRow(
              title: 'Clear cache',
              subtitle: 'Meme and song previews',
              trailing: Text(bytes(cache), style: VText.doto(15)),
              onTap: () async {
                unawaited(HapticFeedback.selectionClick());
                await ref.read(storageRepositoryProvider).clearCache();
                if (context.mounted) showToast(context, 'Cache cleared');
              },
            ),
          ],
        ),
        VListSection(
          children: [
            VListRow(
              leading: const MooseMark(size: 44),
              title: 'Moose',
              subtitle: 'Version $mooseVersion · licences, developer',
              onTap: () => pushPage<void>(context, (_) => const AboutPage()),
            ),
          ],
        ),
        const VFootnote(
          "Your chats live on your phones. The server only holds sealed messages until they're delivered.",
          center: true,
        ),
      ],
    );
  }
}
