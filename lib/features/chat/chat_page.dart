import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/shell.dart';
import '../../core/icons/v_icons.dart';
import '../../core/theme/v_colors.dart';
import '../../core/theme/v_palette.dart';
import '../../core/theme/v_text.dart';
import '../../core/widgets/v_buttons.dart';
import '../../core/widgets/v_glass.dart';
import '../../core/widgets/v_surface.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../mock/mock_data.dart';
import '../common/avatar.dart';
import '../common/parts.dart';
import '../common/toast.dart';
import '../moments/poke_picker.dart';
import '../stickers/sticker_maker.dart';
import 'bubbles.dart';
import 'chat_hooks.dart';
import 'composer.dart';
import 'message_actions.dart';
import 'theme_sheet.dart';

/// The conversation (C15): everything else in Moose hangs off it.
class ChatPage extends ConsumerStatefulWidget {
  const ChatPage({super.key});

  @override
  ConsumerState<ChatPage> createState() => ChatPageState();
}

class ChatPageState extends ConsumerState<ChatPage> {
  final _scroll = ScrollController();

  /// Messages after this were unread when the chat opened.
  late final DateTime _lastRead = MockData.lastRead;
  bool _showJump = false;
  int _newWhileAway = 0;

  Message? _replyTo;
  List<Media> _picked = const [];
  String? _playing;
  Timer? _playTimer;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      final away = _scroll.offset > 300;
      if (away != _showJump) {
        setState(() {
          _showJump = away;
          if (!away) _newWhileAway = 0;
        });
      }
    });
  }

  @override
  void dispose() {
    _playTimer?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  void _toBottom() {
    HapticFeedback.selectionClick();
    _scroll.animateTo(
      0,
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
    );
  }

  MessagesNotifier get _messages => ref.read(messagesProvider.notifier);

  void _send(Body body) {
    _messages.send(body, reply: _replyTo?.quote());
    setState(() => _replyTo = null);
    if (_scroll.hasClients && _scroll.offset > 0) _toBottom();
  }

  Future<void> _onLongPress(Message m) async {
    final body = m.body;
    if (body is StickerBody && !m.fromMe) {
      await showReceivedSticker(context, ref, body.sticker);
      return;
    }
    final partner = ref.read(pairingProvider).partner.name;
    final action = await showMessageActions(context, m: m, partner: partner);
    if (!mounted || action == null) return;
    switch (action) {
      case ReactAction(:final emoji):
        _messages.react(m.id, emoji);
      case ReplyAction():
        setState(() => _replyTo = m);
      case CopyAction():
        final body = m.body;
        if (body is TextBody) {
          await Clipboard.setData(ClipboardData(text: body.text));
          if (mounted) showToast(context, 'Copied');
        }
      case SaveAction():
        showToast(context, 'Saved to your gallery');
      case DeleteAction():
        _messages.delete(m.id);
    }
  }

  void _play(Message m, Duration length) {
    _playTimer?.cancel();
    if (_playing == m.id) {
      setState(() => _playing = null);
      return;
    }
    if (m.body is VoiceBody) _messages.played(m.id);
    setState(() => _playing = m.id);
    _playTimer = Timer(length, () {
      if (mounted) setState(() => _playing = null);
    });
  }

  Future<void> _poke({bool pick = false}) async {
    final cd = ref.read(momentCooldownProvider.notifier);
    final partner = ref.read(pairingProvider).partner.name;
    final m = pick
        ? await showPokePicker(context, partner: partner)
        : VMoment.poke;
    if (m == null || !mounted) return;
    if (cd.send(m)) {
      unawaited(HapticFeedback.mediumImpact());
      showToast(
        context,
        '${m.emoji}  ${m.label} sent to $partner',
        tint: m.color,
      );
    } else {
      unawaited(HapticFeedback.heavyImpact());
      showToast(context, '${m.label} again in ${cd.left(m).inSeconds + 1}s');
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    final pairing = ref.watch(pairingProvider);
    final messages = session.decoy
        ? const <Message>[]
        : ref.watch(messagesProvider);
    final online = ref.watch(onlineProvider);
    final settings = ref.watch(settingsProvider);
    final hooks = ChatHooks.of(context);

    // New messages while scrolled up count on the jump button.
    ref.listen(messagesProvider, (before, after) {
      if (_showJump &&
          before != null &&
          after.length > before.length &&
          !after.last.fromMe) {
        setState(() => _newWhileAway++);
      }
    });

    final partner = session.decoy
        ? Person(id: 'decoy', name: session.decoyName)
        : pairing.partner;
    final media = MediaQuery.of(context);
    final top = media.padding.top;
    final bottom = media.padding.bottom;
    const pillTop = AppShell.pillBottom + AppShell.pillHeight;
    final composerBottom = bottom + pillTop + 12;
    final unread = messages
        .where((m) => !m.fromMe && m.at.isAfter(_lastRead))
        .length;

    final actions = BubbleActions(
      onLongPress: session.decoy ? null : _onLongPress,
      onReply: session.decoy ? null : (m) => setState(() => _replyTo = m),
      onRetry: (m) => _messages.retry(m.id),
      onReact: (m, e) => _messages.react(m.id, e),
      onPlayVoice: (m) => _play(m, (m.body as VoiceBody).length),
      onPlaySong: (m) => _play(m, const Duration(seconds: 15)),
      onOpenMedia: (m, i) => hooks.openMedia(context, ref, m, i),
      onCallBack: (m) => hooks.call(context, video: (m.body as CallBody).video),
    );

    return Stack(
      children: [
        // Long-press the wallpaper (anywhere that isn't a message) for the
        // shared theme.
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onLongPress: session.decoy
                ? null
                : () {
                    HapticFeedback.mediumImpact();
                    showThemeSheet(context, ref);
                  },
            child: messages.isEmpty
                ? _Empty(partner: partner.name)
                : _List(
                    controller: _scroll,
                    messages: messages,
                    lastRead: _lastRead,
                    unread: unread,
                    partner: partner.name,
                    actions: actions,
                    playing: _playing,
                    padding: EdgeInsets.fromLTRB(
                      14,
                      top + 64 + (online ? 0 : 56),
                      14,
                      composerBottom +
                          56 +
                          (_replyTo != null ? 52 : 0) +
                          (_picked.isNotEmpty ? 90 : 0),
                    ),
                  ),
          ),
        ),
        // The top blur under the status bar and header.
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          child: VEdgeBlur(edge: VEdge.top, solid: top + 64, fade: 44),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: VEdgeBlur(
            edge: VEdge.bottom,
            solid: composerBottom + 44,
            fade: 40,
          ),
        ),
        Positioned(
          left: 16,
          right: 16,
          top: top + 8,
          child: _Header(
            partner: partner,
            presence: session.decoy ? Presence.away : pairing.presence,
            lastSeen: session.decoy
                ? DateTime.now().subtract(const Duration(days: 1))
                : pairing.lastSeen,
            onPoke: session.decoy ? null : () => _poke(),
            onPokeHold: session.decoy ? null : () => _poke(pick: true),
            onCall: session.decoy
                ? null
                : (video) => hooks.call(context, video: video),
          ),
        ),
        if (!online)
          Positioned(
            left: 16,
            right: 16,
            top: top + 64,
            child: const _OfflineBanner(),
          ),
        if (_showJump)
          Positioned(
            right: 16,
            bottom: composerBottom + 60,
            child: _JumpButton(count: _newWhileAway, onTap: _toBottom),
          ),
        Positioned(
          left: 12,
          right: 12,
          bottom: composerBottom,
          child: Composer(
            enabled: !session.decoy,
            partner: partner.name,
            replyTo: _replyTo,
            media: _picked,
            enterSends: settings.enterSends,
            actions: ComposerActions(
              onSendText: (t) => _send(TextBody(t)),
              onSendVoice: (len) =>
                  _send(VoiceBody(length: len, wave: MockData.voiceWave)),
              onSendRound: (len) => _send(
                RoundVideoBody(
                  Media(
                    id: 'rv${DateTime.now().millisecondsSinceEpoch}',
                    art: 0,
                    duration: len,
                  ),
                ),
              ),
              onAttach: () async {
                final picked = await hooks.attach(context, ref);
                if (picked != null && mounted) {
                  setState(() => _picked = [..._picked, ...picked]);
                }
              },
              onStickers: () async {
                final body = await hooks.stickers(context);
                if (body != null) _send(body);
              },
              onCancelReply: () => setState(() => _replyTo = null),
              onRemoveMedia: (i) =>
                  setState(() => _picked = [..._picked]..removeAt(i)),
              onAddMedia: () async {
                final more = await hooks.gallery(context);
                if (more != null && mounted) {
                  setState(() => _picked = [..._picked, ...more]);
                }
              },
              onSendMedia: (caption) {
                _send(
                  PhotoBody(_picked, caption: caption.isEmpty ? null : caption),
                );
                setState(() => _picked = const []);
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.partner,
    required this.presence,
    required this.lastSeen,
    required this.onPoke,
    required this.onPokeHold,
    required this.onCall,
  });

  final Person partner;
  final Presence presence;
  final DateTime? lastSeen;
  final VoidCallback? onPoke;
  final VoidCallback? onPokeHold;
  final void Function(bool video)? onCall;

  @override
  Widget build(BuildContext context) {
    final status = switch (presence) {
      Presence.online => 'online',
      Presence.typing => 'typing…',
      Presence.away =>
        lastSeen == null ? 'away' : 'last seen ${_ago(lastSeen!)}',
    };
    return Row(
      children: [
        Avatar(partner, online: presence != Presence.away),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(partner.name, style: VText.inter(16, weight: 600)),
              Text(status, style: VText.secondary),
            ],
          ),
        ),
        VCircleButton(
          icon: VIcon.phone,
          size: 40,
          onTap: onCall == null ? null : () => onCall!(false),
        ),
        const SizedBox(width: 8),
        VCircleButton(
          icon: VIcon.video,
          size: 40,
          onTap: onCall == null ? null : () => onCall!(true),
        ),
        const SizedBox(width: 8),
        Semantics(
          button: true,
          label: 'Poke, hold for more',
          child: GestureDetector(
            onLongPress: onPokeHold == null
                ? null
                : () {
                    HapticFeedback.mediumImpact();
                    onPokeHold!();
                  },
            child: VCircleButton(icon: VIcon.poke, size: 40, onTap: onPoke),
          ),
        ),
      ],
    );
  }

  static String _ago(DateTime t) {
    final now = DateTime.now();
    if (now.difference(t).inDays >= 1) return 'yesterday';
    return hhmm(t);
  }
}

/// The messages, newest at the bottom, with a pill for each day and the
/// unread divider.
class _List extends StatelessWidget {
  const _List({
    required this.controller,
    required this.messages,
    required this.lastRead,
    required this.unread,
    required this.partner,
    required this.actions,
    required this.playing,
    required this.padding,
  });

  final ScrollController controller;
  final List<Message> messages;
  final DateTime lastRead;
  final int unread;
  final String partner;
  final BubbleActions actions;
  final String? playing;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final items = <Widget>[];
    DateTime? day;
    var dividerShown = false;
    for (final m in messages) {
      final d = DateTime(m.at.year, m.at.month, m.at.day);
      if (day != d) {
        day = d;
        items.add(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Center(
              child: SystemPill(
                child: Text(_dayLabel(d).toUpperCase(), style: VText.eyebrow),
              ),
            ),
          ),
        );
      }
      if (!dividerShown && unread > 0 && !m.fromMe && m.at.isAfter(lastRead)) {
        dividerShown = true;
        items.add(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: RuleLabel('$unread unread'),
          ),
        );
      }
      items.add(
        Padding(
          padding: EdgeInsets.only(
            top: m.reactions.isEmpty ? 4 : 4,
            bottom: m.reactions.isEmpty ? 4 : 0,
          ),
          child: MessageView(
            key: ValueKey(m.id),
            message: m,
            partner: partner,
            actions: actions,
            playingId: playing,
          ),
        ),
      );
    }
    final reversed = items.reversed.toList();
    return ListView.builder(
      controller: controller,
      reverse: true,
      padding: padding,
      itemCount: reversed.length,
      itemBuilder: (context, i) => reversed[i],
    );
  }

  static String _dayLabel(DateTime d) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final diff = today.difference(d).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
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
    return '${days[d.weekday - 1]} ${d.day} ${months[d.month - 1]}';
  }
}

/// A new chat, or the decoy chat (C14): nothing yet.
class _Empty extends StatelessWidget {
  const _Empty({required this.partner});

  final String partner;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Say hi to $partner',
            style: VText.doto(22),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text('No messages yet.', style: VText.secondary),
        ],
      ),
    ),
  );
}

/// C44: no connection.
class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner();

  @override
  Widget build(BuildContext context) => VGlass(
    radius: 16,
    tint: VPalette.of(context).glassSheet,
    blur: 14,
    border: false,
    child: VOutlined(
      radius: 16,
      outline: VOutline.dashed,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            const VIconView(VIcon.offline, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                "You're offline. Messages send when you're back.",
                style: VText.inter(13, weight: 500),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _JumpButton extends StatelessWidget {
  const _JumpButton({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: count > 0 ? 'Jump to latest, $count new' : 'Jump to latest',
    child: VTappable(
      onTap: onTap,
      child: SizedBox.square(
        dimension: 48,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: VGlass(
                radius: 22,
                tint: VPalette.of(context).glassSheet,
                blur: 14,
                child: const Center(child: VIconView(VIcon.down, size: 22)),
              ),
            ),
            if (count > 0)
              Positioned(top: -6, right: -4, child: CountBadge(count)),
          ],
        ),
      ),
    ),
  );
}
