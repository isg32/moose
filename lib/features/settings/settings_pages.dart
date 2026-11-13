import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/version.dart';
import '../../core/icons/v_icons.dart';
import '../../core/theme/v_colors.dart';
import '../../core/theme/v_palette.dart';
import '../../core/theme/v_text.dart';
import '../../core/widgets/v_buttons.dart';
import '../../core/widgets/v_controls.dart';
import '../../core/widgets/v_glass.dart';
import '../../core/widgets/v_list.dart';
import '../../core/widgets/v_page.dart';
import '../../core/widgets/v_progress.dart';
import '../../core/widgets/v_surface.dart';
import '../../data/chat_theme.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../platform/crash_log.dart';
import '../common/avatar.dart';
import '../common/overlay.dart';
import '../common/parts.dart';
import '../common/toast.dart';
import '../common/wallpaper.dart';
import '../moments/moment_burst.dart';
import '../onboarding/onboarding_pages.dart';

/// Moose's mark until the launcher icon lands: the wordmark on the night
/// wallpaper, in a rounded tile.
class MooseMark extends StatelessWidget {
  const MooseMark({super.key, this.size = 132});

  final double size;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Moose',
    excludeSemantics: true,
    child: Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.26),
        border: size > 60 ? Border.all(color: VPalette.of(context).ink) : null,
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          const WallpaperView(wallpaper: WallpaperRef.builtin('night')),
          Center(
            child: Text(
              'MO\nOSE',
              textAlign: TextAlign.center,
              style: VText.doto(
                size * 0.26,
                weight: 900,
                height: 0.9,
              ).copyWith(color: VColors.white),
            ),
          ),
        ],
      ),
    ),
  );
}

/// C37: your partner, how long you've been paired, the security code, and
/// Unpair.
class PartnerPage extends ConsumerWidget {
  const PartnerPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = ref.watch(pairingProvider);
    final days = DateTime.now().difference(p.since).inDays;
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
    return VDetailPage(
      backLabel: 'Settings',
      title: '',
      children: [
        Center(
          child: Column(
            children: [
              Avatar(p.partner, size: 96),
              const SizedBox(height: 12),
              Text(
                p.partner.name,
                style: VText.doto(44, weight: 900, height: 1),
              ),
              const SizedBox(height: 8),
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text:
                          'Paired since ${p.since.day} ${months[p.since.month - 1]} ${p.since.year} · ',
                    ),
                    TextSpan(text: '$days', style: VText.doto(13)),
                    const TextSpan(text: ' days'),
                  ],
                ),
                style: VText.inter(13, weight: 300),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        VListSection(
          children: [
            VListRow(
              title: 'Last seen',
              value: p.presence == Presence.away
                  ? hhmm(p.lastSeen ?? DateTime.now())
                  : 'online',
              chevron: false,
            ),
            VListRow(
              title: 'Their new phone',
              subtitle: 'Lost theirs? Type the code their new Moose shows',
              onTap: () =>
                  pushPage<void>(context, (_) => const JoinPage(repair: true)),
            ),
            VListRow(
              title: 'Messages waiting',
              subtitle: 'Sealed on the server for ${p.partner.name}',
              trailing: Text('${p.waitingOnServer}', style: VText.doto(15)),
            ),
          ],
        ),
        VCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('SECURITY CODE', style: VText.eyebrow),
              const SizedBox(height: 12),
              SecurityCode(p.securityCode),
              const SizedBox(height: 12),
              Text(
                "Matches ${p.partner.name}'s screen? Then only you two can read your chat.",
                style: VText.secondary,
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        _DashedAction(VIcon.unlink, 'Unpair', () => showUnpair(context, ref)),
      ],
    );
  }
}

class _DashedAction extends StatelessWidget {
  const _DashedAction(this.icon, this.label, this.onTap);

  final VIcon icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: label,
    excludeSemantics: true,
    child: VTappable(
      onTap: onTap,
      child: VOutlined(
        radius: 999,
        outline: VOutline.dashed,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 15),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              VIconView(icon, size: 18),
              const SizedBox(width: 8),
              Text(label, style: VText.buttonSecondary),
            ],
          ),
        ),
      ),
    ),
  );
}

/// C41: what unpairing does, typed confirmation, and Unpair.
Future<void> showUnpair(BuildContext context, WidgetRef ref) async {
  final ok = await showOverlayPage<bool>(context, (_) => const _Unpair());
  if (ok != true || !context.mounted) return;
  try {
    await ref.read(pairRepositoryProvider).unpair();
  } on Object {
    if (context.mounted) {
      showToast(context, "Couldn't reach the server. Try again.");
    }
    return;
  }
  if (!context.mounted) return;
  ref.read(sessionProvider.notifier).unpair();
  context.go(OnboardingRoutes.welcome);
}

class _Unpair extends ConsumerStatefulWidget {
  const _Unpair();

  @override
  ConsumerState<_Unpair> createState() => _UnpairState();
}

class _UnpairState extends ConsumerState<_Unpair> {
  final _typed = TextEditingController();
  var _wipe = false;

  @override
  void dispose() {
    _typed.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final partner = ref.watch(pairingProvider).partner.name;
    final ready = _typed.text.trim().toUpperCase() == 'UNPAIR';
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            onTap: () => Navigator.of(context).pop(false),
            child: ColoredBox(color: VPalette.of(context).popupScrim),
          ),
        ),
        Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: VGlass(
              radius: 28,
              tint: VPalette.of(context).glassSheet,
              blur: 14,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 20, 18, 18),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Unpair from $partner?',
                      style: VText.doto(26, height: 1.05),
                    ),
                    const SizedBox(height: 12),
                    for (final line in [
                      "You'll stop getting her messages, pokes and doodles.",
                      'Anything still sealed on the server is deleted.',
                      'Your history stays on this phone unless you tick below.',
                    ])
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text(
                          '· $line',
                          style: VText.inter(13, height: 1.4),
                        ),
                      ),
                    const SizedBox(height: 6),
                    Semantics(
                      checked: _wipe,
                      label: 'Also delete history here',
                      excludeSemantics: true,
                      child: VTappable(
                        onTap: () => setState(() => _wipe = !_wipe),
                        child: Row(
                          children: [
                            SizedBox.square(
                              dimension: 22,
                              child: VOutlined(
                                radius: 6,
                                outline: _wipe ? VOutline.none : VOutline.solid,
                                fill: _wipe
                                    ? VPalette.of(context).ink
                                    : VColors.transparent,
                                child: _wipe
                                    ? Center(
                                        child: VIconView(
                                          VIcon.check,
                                          size: 16,
                                          strokeWidth: 2.5,
                                          color: VPalette.of(context).paper,
                                        ),
                                      )
                                    : const SizedBox.shrink(),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              'Also delete history here',
                              style: VText.inter(14, weight: 500),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text('TYPE UNPAIR TO CONFIRM', style: VText.eyebrow),
                    const SizedBox(height: 6),
                    VTextField(
                      controller: _typed,
                      style: VText.doto(16),
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: VButton.secondary(
                            'Keep',
                            onPressed: () => Navigator.of(context).pop(false),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: VButton.primary(
                            'Unpair',
                            enabled: ready,
                            onPressed: () {
                              HapticFeedback.heavyImpact();
                              Navigator.of(context).pop(true);
                            },
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
    );
  }
}

/// C38: what Moose keeps on this phone, by kind, each clearable.
class StoragePage extends ConsumerWidget {
  const StoragePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final use = ref.watch(storageProvider);
    final partner = ref.watch(pairingProvider).partner.name;
    final total = use.fold<int>(0, (n, u) => n + u.bytes);
    final parts = bytes(total).split(' ');
    return VDetailPage(
      backLabel: 'Settings',
      title: 'Storage',
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(parts.first, style: VText.doto(64, weight: 900, height: 1)),
              const SizedBox(width: 8),
              Text(parts.last, style: VText.doto(22)),
              const SizedBox(width: 10),
              Text('on this phone', style: VText.secondary),
            ],
          ),
        ),
        VListSection(
          children: [
            for (final u in use)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 13,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(child: Text(u.label, style: VText.rowTitle)),
                        Text(bytes(u.bytes), style: VText.doto(14)),
                        const SizedBox(width: 10),
                        VPill(
                          'Clear',
                          onTap: u.bytes == 0
                              ? null
                              : () {
                                  HapticFeedback.selectionClick();
                                  ref
                                      .read(storageProvider.notifier)
                                      .clear(u.label);
                                },
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    VBar(value: total == 0 ? 0 : u.bytes / total),
                  ],
                ),
              ),
          ],
        ),
        VFootnote(
          'Clearing only removes it from this phone. $partner keeps her copy, and can send it again if her phone is on.',
        ),
      ],
    );
  }
}

/// C39: message previews, each moment's sound, and the background check.
class NotificationsPage extends ConsumerWidget {
  const NotificationsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final partner = ref.watch(pairingProvider).partner.name;
    const sounds = {
      VMoment.poke: 'Knock',
      VMoment.hug: 'Warm hum',
      VMoment.kiss: 'Smooch',
      VMoment.missYou: 'Soft chime',
    };
    return VDetailPage(
      backLabel: 'Settings',
      title: 'Notifications',
      children: [
        const VEyebrow('Messages'),
        VListSection(
          children: [
            VListRow(
              title: 'Show message text',
              subtitle: 'Off shows "New message from $partner"',
              trailing: VSwitch(
                value: settings.showPreview,
                onChanged: (v) => ref
                    .read(settingsProvider.notifier)
                    .update((s) => s.copyWith(showPreview: v)),
              ),
            ),
          ],
        ),
        const VEyebrow('Pokes'),
        VListSection(
          children: [
            for (final m in VMoment.values)
              VListRow(
                leading: Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: m.color,
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Text(m.emoji, style: const TextStyle(fontSize: 17)),
                ),
                title: m.label,
                subtitle: '${m.haptic.split(',').first} · ${sounds[m]}',
                trailing: VPill(
                  'Hear',
                  leading: const VIconView(VIcon.play, size: 14),
                  onTap: () => m.buzz(),
                ),
              ),
          ],
        ),
        const VEyebrow('Background check'),
        VListSection(
          children: [
            VListRow(
              leading: Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: VPalette.of(context).ink,
                  shape: BoxShape.circle,
                ),
              ),
              title: 'Running',
              subtitle: 'Every 6 min · last check 2 min ago',
            ),
          ],
        ),
        VCard(
          outline: VOutline.dashed,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              const VIconView(VIcon.warning, size: 18),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('If Android stops it', style: VText.rowTitle),
                    Text(
                      'Pokes would wait until you open Moose',
                      style: VText.secondary,
                    ),
                  ],
                ),
              ),
              VPill(
                'Fix',
                fill: VFill.filled,
                onTap: () => HapticFeedback.selectionClick(),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// C40: as Idris's About: the mark, the version, a line, the licences, who
/// made it, and a test crash report.
class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  static const _licences = [
    ('Doto', 'OFL'),
    ('Inter', 'OFL'),
    ('NewPipe Extractor', 'GPL-3.0'),
    ('youtube_explode_dart', 'BSD-3'),
    ('OkHttp', 'Apache 2.0'),
    ('flutter_webrtc', 'MIT'),
    ('cryptography', 'Apache 2.0'),
    ('drift', 'MIT'),
    ('just_audio', 'MIT'),
    ('camera', 'BSD-3'),
  ];

  @override
  Widget build(BuildContext context) {
    return VDetailPage(
      backLabel: 'Settings',
      title: 'About',
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            children: [
              const MooseMark(),
              const SizedBox(height: 18),
              Text('Moose', style: VText.doto(40, height: 1)),
              const SizedBox(height: 8),
              Text(
                'Version $mooseVersion',
                style: VText.inter(13, weight: 300),
              ),
              const SizedBox(height: 4),
              Text(
                'A quiet, private chat for two.',
                textAlign: TextAlign.center,
                style: VText.secondary,
              ),
            ],
          ),
        ),
        VListSection(
          header: const VEyebrow('Licences'),
          children: [
            for (final (name, licence) in _licences)
              VListRow(title: name, value: licence, chevron: false),
          ],
        ),
        VListSection(
          header: const VEyebrow('Developer'),
          children: [
            VListRow(
              leading: ClipOval(
                child: Image.asset(
                  'assets/images/developer.jpg',
                  width: 44,
                  height: 44,
                  fit: BoxFit.cover,
                ),
              ),
              title: 'Sapan Gajjar',
              subtitle: "You've probably guessed who made this app",
              chevron: false,
            ),
            for (final (title, handle) in const [
              ('GitHub', 'isg32'),
              ('LinkedIn', 'sapangajjar101105'),
            ])
              VListRow(
                title: title,
                value: handle,
                onTap: () => Clipboard.setData(ClipboardData(text: handle)),
              ),
          ],
        ),
        VListSection(
          header: const VEyebrow('Help'),
          children: [
            VListRow(
              title: 'See a test crash report',
              subtitle: 'What Moose shows if something goes wrong',
              onTap: CrashLog.instance.test,
            ),
          ],
        ),
        const VFootnote(
          'Your chats live on your two phones. The server only holds sealed messages '
          "until they're delivered, then wipes them. Nothing is collected.",
        ),
      ],
    );
  }
}
