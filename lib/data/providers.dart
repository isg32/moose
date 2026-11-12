import 'dart:async';

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
    }
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
        m.copyWith(
          body: VoiceBody(
            length: (m.body as VoiceBody).length,
            wave: (m.body as VoiceBody).wave,
            played: true,
          ),
        )
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
  List<Doodle> build() => ref.read(doodleRepositoryProvider).load();

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
    return d;
  }

  void setStrokes(String id, List<Stroke> strokes) => state = [
    for (final d in state)
      d.id == id
          ? d.copyWith(
              strokes: strokes,
              editedBy: 'You',
              editedAt: DateTime.now(),
            )
          : d,
  ];

  void rename(String id, String name) =>
      state = [for (final d in state) d.id == id ? d.copyWith(name: name) : d];

  void delete(String id) => state = [
    for (final d in state)
      if (d.id != id) d,
  ];
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
