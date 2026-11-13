import 'dart:async';

import '../data/chat_theme.dart';
import '../data/models.dart';
import '../data/repositories.dart';
import 'mock_data.dart';

class MockPairRepository implements PairRepository {
  @override
  Pairing load() => MockData.pairing();

  @override
  Future<void> setName(String name) async {}

  @override
  Future<void> setPhoto(String? path) async {}

  @override
  Future<String> invite() async => MockData.inviteCode;

  @override
  Stream<Pairing> waitForPartner({required Duration mockAfter}) =>
      Stream<void>.periodic(mockAfter).take(1).map((_) => MockData.pairing());

  @override
  Future<Pairing?> join(String code) async =>
      code == MockData.inviteCode ? MockData.pairing() : null;

  @override
  Future<List<String>?> peek(String code) async =>
      code == MockData.repairCode || code == MockData.inviteCode
      ? MockData.newSecurityCode
      : null;

  @override
  Future<void> unpair() async {}
}

/// A pretend Aatika: what you send goes ✓, ✓✓ then seen; now and then she
/// types back; a moment you send gets one back.
class MockChatRepository implements ChatRepository {
  MockChatRepository({this.replyDelay = const Duration(seconds: 2)});

  final Duration replyDelay;
  final _events = StreamController<ChatEvent>.broadcast();
  final _timers = <Timer>[];
  var _replies = 0;
  var _n = 0;

  static const _lines = [
    'hehe 🥰',
    'okay okay',
    'come here',
    "that's so us",
    'i love that',
    '🥺🫶',
  ];

  @override
  List<Message> history() => MockData.messages();

  @override
  Stream<ChatEvent> get events => _events.stream;

  /// Something from Aatika right now (tests).
  void push(ChatEvent e) => _events.add(e);

  void _after(Duration d, void Function() f) => _timers.add(
    Timer(d, () {
      if (!_events.isClosed) f();
    }),
  );

  @override
  void send(Message message) {
    final id = message.id;
    _after(const Duration(milliseconds: 500), () {
      _events.add(DeliveryUpdate(id, Delivery.sent));
    });
    _after(const Duration(milliseconds: 1100), () {
      _events.add(DeliveryUpdate(id, Delivery.delivered));
    });
    _after(const Duration(milliseconds: 1800), () {
      _events.add(DeliveryUpdate(id, Delivery.seen));
    });
    final body = message.body;
    if (body is MomentBody) {
      _after(replyDelay * 2, () {
        _events.add(MomentArrived(body.moment));
        _events.add(
          Incoming(
            Message(
              id: 'echo${_n++}',
              fromMe: false,
              at: DateTime.now(),
              body: MomentBody(body.moment),
            ),
          ),
        );
      });
      return;
    }
    // "new phone" plays Aatika's re-pair request (C9).
    if (body is TextBody && body.text.toLowerCase().contains('new phone')) {
      _after(replyDelay, () => _events.add(const RepairRequested()));
      return;
    }
    // "call me" gets a call back, to show an incoming call (K2).
    if (body is TextBody && body.text.toLowerCase().contains('call me')) {
      _after(replyDelay, () => _events.add(const CallArrived(video: true)));
      return;
    }
    if (body is! TextBody || _replies++ % 2 == 1) return;
    _after(replyDelay, () => _events.add(const TypingChanged(true)));
    _after(replyDelay * 2, () {
      _events.add(const TypingChanged(false));
      _events.add(
        Incoming(
          Message(
            id: 'reply${_n++}',
            fromMe: false,
            at: DateTime.now(),
            body: TextBody(_lines[_n % _lines.length]),
          ),
        ),
      );
    });
  }

  @override
  void react(String id, String? emoji) {}

  @override
  void typing(bool on) {}

  @override
  void shareTheme(ChatTheme theme) {}

  @override
  void shareDoodle(DoodleOp op) {}

  @override
  void store(List<Message> messages) {}

  @override
  void dispose() {
    for (final t in _timers) {
      t.cancel();
    }
    _events.close();
  }
}

class MockDoodleRepository implements DoodleRepository {
  @override
  List<Doodle> load() => MockData.doodles();

  @override
  void save(List<Doodle> doodles) {}
}

class MockStickerRepository implements StickerRepository {
  @override
  List<StickerPack> load() => MockData.stickerPacks();

  @override
  void save(List<StickerPack> packs) {}
}

class MockMemeRepository implements MemeRepository {
  MockMemeRepository({this.latency = const Duration(milliseconds: 350)});

  final Duration latency;

  @override
  Future<List<Meme>> search(
    String query,
    MemeSource source,
    MemeKind? kind,
  ) async {
    await Future<void>.delayed(latency);
    final q = query.trim().toLowerCase();
    final all = MockData.memes().where((m) => kind == null || m.kind == kind);
    if (q.isEmpty) return all.toList();
    final words = q.split(RegExp(r'\s+'));
    return all.where((m) => words.any((w) => m.title.contains(w))).toList();
  }
}

class MockMusicRepository implements MusicRepository {
  MockMusicRepository({this.latency = const Duration(milliseconds: 400)});

  final Duration latency;

  @override
  Future<List<Song>> search(String query) async {
    await Future<void>.delayed(latency);
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const [];
    final words = q.split(RegExp(r'\s+'));
    return MockData.songs
        .where(
          (s) => words.any(
            (w) =>
                s.title.toLowerCase().contains(w) ||
                s.artist.toLowerCase().contains(w),
          ),
        )
        .toList();
  }
}

class MockStorageRepository implements StorageRepository {
  @override
  List<StorageUse> load() => MockData.storage;

  @override
  int get cacheBytes => MockData.cacheBytes;

  @override
  Future<void> clear(String label) async {}

  @override
  Future<void> clearCache() async {}
}
