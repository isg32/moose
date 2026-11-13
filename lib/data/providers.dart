import 'dart:async';

import 'package:flutter/widgets.dart' show Widget;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/v_colors.dart';
import '../mock/mock_data.dart';
import '../mock/mock_repositories.dart';
import 'chat_theme.dart';
import 'models.dart';
import 'repositories.dart';
import 'session.dart';

// Repositories: mocks for now (see mockdata.md).

final pairRepositoryProvider = Provider<PairRepository>(
  (ref) => MockPairRepository(),
);

final chatRepositoryProvider = Provider<ChatRepository>((ref) {
  final repo = MockChatRepository();
  ref.onDispose(repo.dispose);
  return repo;
});

final doodleRepositoryProvider = Provider<DoodleRepository>(
  (ref) => MockDoodleRepository(),
);

final stickerRepositoryProvider = Provider<StickerRepository>(
  (ref) => MockStickerRepository(),
);

final memeRepositoryProvider = Provider<MemeRepository>(
  (ref) => MockMemeRepository(),
);

final musicRepositoryProvider = Provider<MusicRepository>(
  (ref) => MockMusicRepository(),
);

final storageRepositoryProvider = Provider<StorageRepository>(
  (ref) => MockStorageRepository(),
);

/// The phone's own photos and camera. Null on the mock, where the gallery
/// (C18) and camera (C20) pages show stand-in art.
abstract interface class MediaSource {
  /// Photos picked from the phone's gallery (empty when cancelled).
  Future<List<Media>> gallery();

  /// A photo from the camera, or null.
  Future<Media?> camera();
}

final mediaSourceProvider = Provider<MediaSource?>((ref) => null);

/// The microphone and speaker for voice notes. Null on the mock, where
/// recording is pretend and playback is a timer.
abstract interface class Voice {
  /// Starts recording; false when the microphone isn't allowed.
  Future<bool> start();

  /// 0–1 loudness while recording, about ten times a second.
  Stream<double> get levels;

  /// Stops and returns the recording's file.
  Future<String?> stop();

  /// Stops and throws the recording away.
  Future<void> cancel();

  /// Plays [path]; [onDone] runs when it ends or is stopped.
  Future<void> play(String path, {void Function()? onDone});

  Future<void> stopPlaying();
}

final voiceProvider = Provider<Voice?>((ref) => null);

/// How a call is going.
enum CallPhase { ringing, connecting, connected, ended }

/// Why a call ended.
enum CallEnd { hungUp, theyHungUp, declined, noAnswer, failed }

class CallUpdate {
  const CallUpdate(this.phase, [this.why]);
  final CallPhase phase;
  final CallEnd? why;
}

/// A real call, phone to phone (K1–K4). Null on the mock, where the
/// partner picks up on a timer.
abstract interface class CallLink {
  Stream<CallUpdate> get updates;

  /// Calls the partner.
  Future<void> dial({required bool video});

  /// Picks up the call that's ringing.
  Future<void> answer();

  /// Ends the call, declines it, or stops ringing.
  Future<void> hangUp();

  void mute(bool on);
  void cameraOff(bool off);
  Future<void> flip();
  void speaker(bool on);

  /// The partner's video and ours, once there are any.
  Widget? remoteView();
  Widget? localView();
}

final callLinkProvider = Provider<CallLink?>((ref) => null);

/// Asks for the notification permission; true when granted. Always yes
/// on the mock.
final askNotificationsProvider = Provider<Future<bool> Function()>(
  (ref) =>
      () async => true,
);

/// True when Moose runs on Neon, false on the mock partner.
final onNeonProvider = Provider<bool>((ref) => false);

// The shared theme.

final chatThemeProvider = NotifierProvider<ChatThemeNotifier, ChatTheme>(
  ChatThemeNotifier.new,
);

class ChatThemeNotifier extends Notifier<ChatTheme> {
  @override
  ChatTheme build() => const ChatTheme();

  void set(ChatTheme theme) => state = theme;
}

// Session: pairing, lock and decoy.

final sessionProvider = NotifierProvider<SessionNotifier, Session>(
  SessionNotifier.new,
);

class SessionNotifier extends Notifier<Session> {
  @override
  Session build() => const Session(
    pin: MockData.pin,
    decoyPin: MockData.decoyPin,
    decoyName: MockData.decoyName,
  );

  void set(Session s) => state = s;

  /// Tries a PIN on the lock screen.
  Unlock unlock(String pin, {DateTime? now}) {
    final t = now ?? DateTime.now();
    final until = state.waitUntil;
    if (until != null && t.isBefore(until)) return Unlock.waiting;
    if (pin == state.pin) {
      state = state.copyWith(
        locked: false,
        decoy: false,
        wrongTries: 0,
        clearWait: true,
      );
      return Unlock.opened;
    }
    if (state.decoyPin != null && pin == state.decoyPin) {
      state = state.copyWith(
        locked: false,
        decoy: true,
        wrongTries: 0,
        clearWait: true,
      );
      return Unlock.decoy;
    }
    final tries = state.wrongTries + 1;
    state = tries >= Session.maxTries
        ? state.copyWith(wrongTries: 0, waitUntil: t.add(Session.wait))
        : state.copyWith(wrongTries: tries, clearWait: true);
    return Unlock.wrong;
  }

  void lock() {
    if (state.pin.isEmpty) return;
    state = state.copyWith(locked: true, decoy: false);
  }

  void setPin(String pin) => state = state.copyWith(pin: pin, locked: false);

  void setDecoy(String pin, String name) =>
      state = state.copyWith(decoyPin: pin, decoyName: name);

  void removeLock() => state = state.copyWith(
    pin: '',
    clearDecoyPin: true,
    locked: false,
    decoy: false,
  );

  void setName(String name) => state = state.copyWith(name: name);

  void pair() => state = state.copyWith(paired: true, locked: false);

  void unpair() => state = state.copyWith(paired: false, locked: false);
}

// The pairing and the partner's presence.

final pairingProvider = NotifierProvider<PairingNotifier, Pairing>(
  PairingNotifier.new,
);

class PairingNotifier extends Notifier<Pairing> {
  @override
  Pairing build() => ref.read(pairRepositoryProvider).load();

  void set(Pairing p) => state = p;

  void setPresence(Presence p) =>
      state = state.copyWith(presence: p, lastSeen: DateTime.now());

  void rename(String name) =>
      state = state.copyWith(me: state.me.copyWith(name: name));
}

// The conversation.

final messagesProvider = NotifierProvider<MessagesNotifier, List<Message>>(
  MessagesNotifier.new,
);

class MessagesNotifier extends Notifier<List<Message>> {
  StreamSubscription<ChatEvent>? _sub;
  var _n = 0;

  @override
  List<Message> build() {
    final repo = ref.watch(chatRepositoryProvider);
    _sub = repo.events.listen(_on);
    ref.onDispose(() => _sub?.cancel());
    listenSelf((_, next) => repo.store(next));
    return repo.history();
  }

  void _on(ChatEvent e) {
    switch (e) {
      case Incoming(:final message):
        state = [...state, message];
      case DeliveryUpdate(:final id, :final delivery):
        state = [
          for (final m in state)
            m.id == id ? m.copyWith(delivery: delivery) : m,
        ];
      case TypingChanged(:final typing):
        ref
            .read(pairingProvider.notifier)
            .setPresence(typing ? Presence.typing : Presence.online);
      case MomentArrived(:final moment):
        ref.read(incomingMomentProvider.notifier).show(moment);
      case CallArrived(:final video):
        ref.read(incomingCallProvider.notifier).ring(video: video);
      case RepairRequested():
        ref.read(repairRequestProvider.notifier).set(true);
      case ReactionChanged(:final id, :final emoji):
        state = [
          for (final m in state)
            m.id == id ? m.copyWith(reactions: _theirs(m.reactions, emoji)) : m,
        ];
      case MediaReady(:final messageId, :final mediaId, :final path):
        state = [
          for (final m in state)
            if (m.id == messageId) _withFile(m, mediaId, path) else m,
        ];
      case DoodleChanged(:final op):
        ref.read(doodlesProvider.notifier).applyRemote(op);
      case ThemeChanged(:final theme):
        ref.read(chatThemeProvider.notifier).set(theme);
      case OnlineChanged(:final online):
        ref.read(onlineProvider.notifier).set(online);
      case Unpaired():
        ref.read(sessionProvider.notifier).unpair();
    }
  }

  static Message _withFile(Message m, String mediaId, String path) {
    Media done(Media x) => x.id == mediaId
        ? x.copyWith(path: path, transfer: Transfer.done, progress: 1)
        : x;
    return m.copyWith(
      body: switch (m.body) {
        PhotoBody(:final photos, :final caption) => PhotoBody([
          for (final p in photos) done(p),
        ], caption: caption),
        VideoBody(:final video) => VideoBody(done(video)),
        final VoiceBody v when mediaId == 'voice' => v.copyWith(path: path),
        final b => b,
      },
    );
  }

  /// The partner's reaction is now [emoji]: theirs is whatever isn't mine.
  static List<Reaction> _theirs(List<Reaction> rs, String? emoji) {
    final out = <Reaction>[];
    for (final r in rs) {
      if (r.mine && r.count > 1) {
        out.add(Reaction(r.emoji, mine: true));
      } else if (r.mine) {
        out.add(r);
      }
    }
    if (emoji == null) return out;
    final i = out.indexWhere((r) => r.emoji == emoji);
    if (i >= 0) {
      out[i] = Reaction(emoji, mine: true, count: 2);
    } else {
      out.add(Reaction(emoji));
    }
    return out;
  }

  /// Sends a message of [body], optionally replying to [reply].
  Message send(Body body, {Quote? reply}) {
    final m = Message(
      id: 'out${DateTime.now().microsecondsSinceEpoch}-${_n++}',
      fromMe: true,
      at: DateTime.now(),
      body: body,
      delivery: Delivery.pending,
      reply: reply,
    );
    state = [...state, m];
    ref.read(chatRepositoryProvider).send(m);
    return m;
  }

  /// Your reaction: tapping the same one again takes it back.
  void react(String id, String emoji) {
    state = [
      for (final m in state)
        if (m.id != id)
          m
        else
          m.copyWith(reactions: _toggle(m.reactions, emoji)),
    ];
    final mine = state
        .firstWhere((m) => m.id == id)
        .reactions
        .where((r) => r.mine)
        .firstOrNull;
    ref.read(chatRepositoryProvider).react(id, mine?.emoji);
  }

  static List<Reaction> _toggle(List<Reaction> rs, String emoji) {
    final mine = rs.where((r) => r.mine).firstOrNull;
    final out = <Reaction>[];
    for (final r in rs) {
      if (r.mine) {
        if (r.count > 1) out.add(Reaction(r.emoji, count: r.count - 1));
        continue;
      }
      out.add(r);
    }
    if (mine?.emoji == emoji) return out;
    final i = out.indexWhere((r) => r.emoji == emoji);
    if (i >= 0) {
      out[i] = Reaction(emoji, mine: true, count: out[i].count + 1);
    } else {
      out.add(Reaction(emoji, mine: true));
    }
    return out;
  }

  void delete(String id) => state = [
    for (final m in state)
      if (m.id != id) m,
  ];

  void retry(String id) {
    final m = state.firstWhere((m) => m.id == id);
    state = [
      for (final x in state)
        x.id == id ? x.copyWith(delivery: Delivery.pending) : x,
    ];
    ref.read(chatRepositoryProvider).send(m);
  }

  /// Marks a voice note as played.
  void played(String id) => state = [
    for (final m in state)
      if (m.id == id && m.body is VoiceBody)
        m.copyWith(body: (m.body as VoiceBody).copyWith(played: true))
      else
        m,
  ];
}

// Moments: the burst on screen, and each kind's cooldown.

final incomingMomentProvider = NotifierProvider<IncomingMoment, VMoment?>(
  IncomingMoment.new,
);

class IncomingMoment extends Notifier<VMoment?> {
  @override
  VMoment? build() => null;

  void show(VMoment m) => state = m;

  void dismiss() => state = null;
}

/// The partner's new phone is waiting for approval (C9).
final repairRequestProvider = NotifierProvider<RepairRequest, bool>(
  RepairRequest.new,
);

class RepairRequest extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool v) => state = v;
}

/// A call ringing now (K2): true for video, false for voice.
final incomingCallProvider = NotifierProvider<IncomingCall, bool?>(
  IncomingCall.new,
);

class IncomingCall extends Notifier<bool?> {
  @override
  bool? build() => null;

  void ring({required bool video}) => state = video;

  void clear() => state = null;
}

/// When each moment can next be sent: one of each every 10 s (C24).
final momentCooldownProvider =
    NotifierProvider<MomentCooldown, Map<VMoment, DateTime>>(
      MomentCooldown.new,
    );

class MomentCooldown extends Notifier<Map<VMoment, DateTime>> {
  static const cooldown = Duration(seconds: 10);

  @override
  Map<VMoment, DateTime> build() => const {};

  Duration left(VMoment m, {DateTime? now}) {
    final until = state[m];
    if (until == null) return Duration.zero;
    final d = until.difference(now ?? DateTime.now());
    return d.isNegative ? Duration.zero : d;
  }

  /// Sends [m] if it's off cooldown; true when it went.
  bool send(VMoment m) {
    if (left(m) > Duration.zero) return false;
    state = {...state, m: DateTime.now().add(cooldown)};
    ref.read(messagesProvider.notifier).send(MomentBody(m));
    return true;
  }
}

// Doodles.

final doodlesProvider = NotifierProvider<DoodlesNotifier, List<Doodle>>(
  DoodlesNotifier.new,
);

class DoodlesNotifier extends Notifier<List<Doodle>> {
  @override
  List<Doodle> build() {
    final repo = ref.read(doodleRepositoryProvider);
    listenSelf((_, next) => repo.save(next));
    return repo.load();
  }

  void _share(DoodleOp op) => ref.read(chatRepositoryProvider).shareDoodle(op);

  /// A change from the partner's phone.
  void applyRemote(DoodleOp op) {
    final partner = ref.read(pairingProvider).partner.name;
    Doodle edited(Doodle d, List<Stroke> strokes) => d.copyWith(
      strokes: strokes,
      editedBy: partner,
      editedAt: DateTime.now(),
    );
    switch (op) {
      case DoodleCreated(:final doodle):
        if (state.any((d) => d.id == doodle.id)) return;
        state = [
          Doodle(
            id: doodle.id,
            name: doodle.name,
            strokes: const [],
            editedBy: partner,
            editedAt: doodle.editedAt,
            paper: doodle.paper,
          ),
          ...state,
        ];
      case StrokesAdded(:final id, :final strokes):
        state = [
          for (final d in state)
            d.id == id ? edited(d, [...d.strokes, ...strokes]) : d,
        ];
      case StrokesSet(:final id, :final strokes):
        state = [for (final d in state) d.id == id ? edited(d, strokes) : d];
      case DoodleRenamed(:final id, :final name):
        state = [
          for (final d in state) d.id == id ? d.copyWith(name: name) : d,
        ];
      case DoodleDeleted(:final id):
        state = [
          for (final d in state)
            if (d.id != id) d,
        ];
      case DoodlePresence(:final id, :final here):
        state = [
          for (final d in state)
            d.id == id
                ? Doodle(
                    id: d.id,
                    name: d.name,
                    strokes: d.strokes,
                    editedBy: d.editedBy,
                    editedAt: d.editedAt,
                    paper: d.paper,
                    partnerHere: here,
                  )
                : d,
        ];
    }
  }

  /// You opened ([here]) or left board [id]: the partner sees the live dot.
  void present(String id, {required bool here}) =>
      _share(DoodlePresence(id, here));

  Doodle create(String name, Paper paper) {
    final d = Doodle(
      id: 'd${DateTime.now().microsecondsSinceEpoch}',
      name: name.trim().isEmpty ? 'Untitled' : name.trim(),
      strokes: const [],
      editedBy: 'You',
      editedAt: DateTime.now(),
      paper: paper,
    );
    state = [d, ...state];
    _share(DoodleCreated(d));
    return d;
  }

  void setStrokes(String id, List<Stroke> strokes) {
    final before = state.where((d) => d.id == id).firstOrNull?.strokes;
    state = [
      for (final d in state)
        d.id == id
            ? d.copyWith(
                strokes: strokes,
                editedBy: 'You',
                editedAt: DateTime.now(),
              )
            : d,
    ];
    // Strokes added on the end go as just those; anything else (undo,
    // erase, a lasso move) sends the whole board.
    final appended =
        before != null &&
        strokes.length > before.length &&
        Iterable<int>.generate(before.length)
            .every((i) => identical(strokes[i], before[i]));
    _share(
      appended
          ? StrokesAdded(id, strokes.sublist(before.length))
          : StrokesSet(id, strokes),
    );
  }

  void rename(String id, String name) {
    state = [for (final d in state) d.id == id ? d.copyWith(name: name) : d];
    _share(DoodleRenamed(id, name));
  }

  void delete(String id) {
    state = [
      for (final d in state)
        if (d.id != id) d,
    ];
    _share(DoodleDeleted(id));
  }
}

// Stickers.

final stickersProvider = NotifierProvider<StickersNotifier, List<StickerPack>>(
  StickersNotifier.new,
);

class StickersNotifier extends Notifier<List<StickerPack>> {
  @override
  List<StickerPack> build() => ref.read(stickerRepositoryProvider).load();

  List<Sticker> get favourites => [
    for (final p in state)
      for (final s in p.stickers)
        if (s.favourite) s,
  ];

  void toggleFavourite(String id) => state = [
    for (final p in state)
      StickerPack(
        id: p.id,
        name: p.name,
        note: p.note,
        stickers: [
          for (final s in p.stickers)
            s.id == id ? s.withFavourite(!s.favourite) : s,
        ],
      ),
  ];

  /// Adds [sticker] to the pack [packId] (made here, or saved from Aatika).
  void add(String packId, Sticker sticker) => state = [
    for (final p in state)
      p.id == packId
          ? StickerPack(
              id: p.id,
              name: p.name,
              note: p.note,
              stickers: [sticker, ...p.stickers],
            )
          : p,
  ];

  void remove(String id) => state = [
    for (final p in state)
      StickerPack(
        id: p.id,
        name: p.name,
        note: p.note,
        stickers: [
          for (final s in p.stickers)
            if (s.id != id) s,
        ],
      ),
  ];
}

// Searches.

typedef MemeQuery = ({String query, MemeSource source, MemeKind? kind});

final memeSearchProvider = FutureProvider.autoDispose
    .family<List<Meme>, MemeQuery>(
      (ref, q) =>
          ref.read(memeRepositoryProvider).search(q.query, q.source, q.kind),
    );

final songSearchProvider = FutureProvider.autoDispose
    .family<List<Song>, String>(
      (ref, q) => ref.read(musicRepositoryProvider).search(q),
    );

/// Whether this phone can reach the server (C44's banner). Always online
/// in the mock.
final onlineProvider = NotifierProvider<OnlineNotifier, bool>(
  OnlineNotifier.new,
);

class OnlineNotifier extends Notifier<bool> {
  @override
  bool build() => true;

  void set(bool v) => state = v;
}

// Settings and storage.

final settingsProvider = NotifierProvider<SettingsNotifier, AppSettings>(
  SettingsNotifier.new,
);

class SettingsNotifier extends Notifier<AppSettings> {
  @override
  AppSettings build() => const AppSettings();

  void update(AppSettings Function(AppSettings) f) => state = f(state);
}

final storageProvider = NotifierProvider<StorageNotifier, List<StorageUse>>(
  StorageNotifier.new,
);

class StorageNotifier extends Notifier<List<StorageUse>> {
  @override
  List<StorageUse> build() => ref.read(storageRepositoryProvider).load();

  void clear(String label) => state = [
    for (final s in state) s.label == label ? StorageUse(label, 0) : s,
  ];
}
