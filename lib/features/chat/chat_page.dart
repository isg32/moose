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

  /// When the chat opened: what arrives after it is read as it comes.
  final _openedAt = DateTime.now();

  /// Messages after this were unread when the chat opened. On Neon there
  /// is no read marker yet, so nothing is.
  late final DateTime _lastRead = ref.read(onNeonProvider)
      ? _openedAt
      : MockData.lastRead;
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

  /// Every message shown so far: what isn't in here is new, and pops in.
  Set<String>? _known;

  Set<String> _fresh(List<Message> messages) {
    final known = _known ??= {for (final m in messages) m.id};
    final fresh = {
      for (final m in messages)
        if (!known.contains(m.id)) m.id,
    };
    known.addAll(fresh);
    return fresh;
  }

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
    final playback = ref.read(playbackProvider.notifier);
    final songs = ref.read(songPlayerProvider);
    final voice = ref.read(voiceProvider);
    final file = switch (m.body) {
      VoiceBody(:final path) => path,
      _ => null,
    };
    final song = m.body is MusicBody;
    // Whatever else was playing stops first.
    if (songs != null) unawaited(songs.stop());
    if (voice != null) unawaited(voice.stopPlaying());
    final again = _playing == m.id;
    if (_playing != null) playback.stop(_playing!);
    if (again) {
      setState(() => _playing = null);
      return;
    }
    setState(() => _playing = m.id);
    if (m.body is VoiceBody && !m.fromMe) _messages.played(m.id);
    // A song finds and loads its stream before any sound: show that.
    playback.start(m.id, loading: song);
    void tick(Duration e) => playback.tick(m.id, e);
    void done() {
      playback.stop(m.id);
      if (mounted && _playing == m.id) setState(() => _playing = null);
    }

    if (song && songs != null) {
      final b = m.body as MusicBody;
      unawaited(songs.play(b.song, b.start, onTick: tick, onDone: done));
      return;
    }
    if (voice != null && file != null) {
      // A real recording: the bubble follows the player.
      unawaited(voice.play(file, onTick: tick, onDone: done));
      return;
    }
    // The mock: a clock stands in, after a short load for songs.
    final load = song ? 8 : 0; // ticks
    _playTimer = Timer.periodic(const Duration(milliseconds: 100), (t) {
      final e = Duration(milliseconds: (t.tick - load) * 100);
      if (e >= length) {
        t.cancel();
        done();
      } else if (!e.isNegative) {
        tick(e);
      }
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

    // A new message while scrolled up: a little way up, glide down to it;
    // further, count it on the jump arrow (as Instagram does).
    ref.listen(messagesProvider, (before, after) {
      if (before == null ||
          after.length <= before.length ||
          after.last.fromMe ||
          !_scroll.hasClients ||
          _scroll.offset <= 0) {
        return;
      }
      if (_showJump) {
        setState(() => _newWhileAway++);
      } else {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _scroll.hasClients) {
            _scroll.animateTo(
              0,
              duration: const Duration(milliseconds: 320),
              curve: Curves.easeOutCubic,
            );
          }
        });
      }
    });

    final partner = session.decoy
        ? Person(id: 'decoy', name: session.decoyName)
        : pairing.partner;
    // Only padding here: the keyboard is read by _Lift alone, so its
    // animation moves the composer without rebuilding the conversation.
    // viewPadding, not padding: padding.bottom drops to 0 while the
    // keyboard is up, which slid the whole conversation down.
    final pad = MediaQuery.viewPaddingOf(context);
    final top = pad.top;
    const pillTop = AppShell.pillBottom + AppShell.pillHeight;
    // Where the composer rests, above the pill; the keyboard lifts it, and
    // the list's bottom with it (see _Lift).
    final composerBottom = pad.bottom + pillTop + 12;
    final unread = messages
        .where(
          (m) =>
              !m.fromMe && m.at.isAfter(_lastRead) && !m.at.isAfter(_openedAt),
        )
        .length;

    final actions = BubbleActions(
      onLongPress: session.decoy ? null : _onLongPress,
      onReply: session.decoy ? null : (m) => setState(() => _replyTo = m),
      onRetry: (m) => _messages.retry(m.id),
      onReact: (m, e) => _messages.react(m.id, e),
      onPlayVoice: (m) => _play(m, (m.body as VoiceBody).length),
      onPlaySong: (m) => _play(m, const Duration(seconds: 15)),
      onOpenMedia: (m, i) => hooks.openMedia(
        context,
        ref,
        m,
        i,
        onReply: session.decoy ? null : (m) => setState(() => _replyTo = m),
      ),
      onCallBack: (m) =>
          hooks.call(context, ref, video: (m.body as CallBody).video),
    );

    return Stack(
      children: [
        // Long-press the wallpaper (anywhere that isn't a message) for the
        // shared theme.
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            // A tap on the conversation puts the keyboard away.
            onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
            onLongPress: session.decoy
                ? null
                : () {
                    HapticFeedback.mediumImpact();
                    showThemeSheet(context, ref);
                  },
            child: messages.isEmpty
                ? _Empty(partner: partner.name)
                // The newest message rides up with the composer, so it
                // stays in view above the keyboard (a reversed list keeps
                // its bottom where the padding puts it).
                : _Lift(
                    rest: composerBottom,
                    builder: (lift) => _List(
                      controller: _scroll,
                      messages: messages,
                      lastRead: _lastRead,
                      unread: unread,
                      partner: partner.name,
                      actions: actions,
                      playing: _playing,
                      fresh: _fresh(messages),
                      padding: EdgeInsets.fromLTRB(
                        14,
                        top + 64 + (online ? 0 : 56),
                        14,
                        lift +
                            56 +
                            (_replyTo != null ? 52 : 0) +
                            (_picked.isNotEmpty ? 90 : 0),
                      ),
                    ),
                  ),
          ),
        ),
        // Under the header and the composer, a solid soft band, not a
        // blur: the app's one top and bottom blur belong to the shell.
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          child: VEdgeBlur(edge: VEdge.top, solid: top + 64),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: _Lift(
            rest: composerBottom,
            builder: (lift) => VEdgeBlur(edge: VEdge.bottom, solid: lift + 44),
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
                : (video) => hooks.call(context, ref, video: video),
          ),
        ),
        if (!online)
          Positioned(
            left: 16,
            right: 16,
            top: top + 64,
            child: const _OfflineBanner(),
          ),
        Positioned(
          right: 16,
          bottom: 0,
          child: _Lift(
            rest: composerBottom,
            builder: (lift) => Padding(
              padding: EdgeInsets.only(bottom: lift + 60),
              child: IgnorePointer(
                ignoring: !_showJump,
                child: AnimatedScale(
                  scale: _showJump ? 1 : 0.4,
                  duration: const Duration(milliseconds: 300),
                  curve: _showJump ? Curves.easeOutBack : Curves.easeIn,
                  child: AnimatedOpacity(
                    opacity: _showJump ? 1 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: _JumpButton(count: _newWhileAway, onTap: _toBottom),
                  ),
                ),
              ),
            ),
          ),
        ),
        Positioned(
          left: 12,
          right: 12,
          bottom: 0,
          child: _Lift(
            rest: composerBottom,
            builder: (lift) => Padding(
              padding: EdgeInsets.only(bottom: lift),
              child: Composer(
                enabled: !session.decoy,
                voice: ref.watch(voiceProvider),
                roundCamera: ref.watch(roundCameraProvider),
                partner: partner.name,
                replyTo: _replyTo,
                media: _picked,
                enterSends: settings.enterSends,
                actions: ComposerActions(
                  onSendText: (t) => _send(TextBody(t)),
                  onTyping: (on) => ref.read(chatRepositoryProvider).typing(on),
                  onSendVoice: (len, {path, wave}) => _send(
                    VoiceBody(
                      length: len,
                      wave: wave ?? MockData.voiceWave,
                      path: path,
                    ),
                  ),
                  onSendRound: (len, {path}) => _send(
                    RoundVideoBody(
                      Media(
                        id: 'rv${DateTime.now().millisecondsSinceEpoch}',
                        art: 0,
                        aspect: 1,
                        duration: len,
                        path: path,
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
                      PhotoBody(
                        _picked,
                        caption: caption.isEmpty ? null : caption,
                      ),
                    );
                    setState(() => _picked = const []);
                  },
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Lifts what rides on the keyboard (composer, bottom blur, jump arrow):
/// [rest] above the bottom, or just over the keyboard once it's taller.
/// Never lower than [rest], so the composer doesn't dip as the keyboard
/// starts to rise. It alone listens to the keyboard's animation.
class _Lift extends StatelessWidget {
  const _Lift({required this.rest, required this.builder});

  final double rest;
  final Widget Function(double lift) builder;

  @override
  Widget build(BuildContext context) {
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    return builder(keyboard + 10 > rest ? keyboard + 10 : rest);
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
        Semantics(
          button: true,
          label: 'Voice call',
          child: VCircleButton(
            icon: VIcon.phone,
            size: 40,
            onTap: onCall == null ? null : () => onCall!(false),
          ),
        ),
        const SizedBox(width: 8),
        Semantics(
          button: true,
          label: 'Video call',
          child: VCircleButton(
            icon: VIcon.video,
            size: 40,
            onTap: onCall == null ? null : () => onCall!(true),
          ),
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
    this.fresh = const {},
  });

  /// Messages new since the chat opened: they pop in.
  final Set<String> fresh;
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
          child: _Appear(
            key: ValueKey('appear-${m.id}'),
            animate: fresh.contains(m.id),
            alignment: m.centred
                ? Alignment.bottomCenter
                : m.fromMe
                ? Alignment.bottomRight
                : Alignment.bottomLeft,
            child: MessageView(
              key: ValueKey(m.id),
              message: m,
              partner: partner,
              actions: actions,
              playingId: playing,
            ),
          ),
        ),
      );
    }
    final reversed = items.reversed.toList();
    return ListView.builder(
      controller: controller,
      reverse: true,
      // Scrolling the conversation puts the keyboard away.
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
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

/// A message arriving: from its own corner it grows, rises and fades in on
/// a soft spring. Messages already there when the chat opened just sit.
class _Appear extends StatefulWidget {
  const _Appear({
    super.key,
    required this.animate,
    required this.alignment,
    required this.child,
  });

  final bool animate;
  final Alignment alignment;
  final Widget child;

  @override
  State<_Appear> createState() => _AppearState();
}

class _AppearState extends State<_Appear> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 520),
    value: widget.animate ? 0 : 1,
  );

  @override
  void initState() {
    super.initState();
    if (widget.animate) _c.forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _c,
    child: widget.child,
    builder: (context, child) {
      if (_c.value == 1) return child!;
      final grow = Curves.easeOutBack.transform(_c.value);
      final fade = Curves.easeOut.transform((_c.value * 1.8).clamp(0, 1));
      return Opacity(
        opacity: fade,
        child: Transform.translate(
          offset: Offset(0, 18 * (1 - Curves.easeOutCubic.transform(_c.value))),
          child: Transform.scale(
            scale: 0.85 + 0.15 * grow,
            alignment: widget.alignment,
            child: child,
          ),
        ),
      );
    },
  );
}
