import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/misc.dart' show Override;

import '../data/models.dart';
import '../data/providers.dart';
import '../data/repositories.dart';
import '../data/session.dart';
import 'api.dart';
import 'auth.dart';
import 'config.dart';
import 'crypto.dart';
import 'local_store.dart';
import 'vault.dart';
import 'wire.dart';

/// Moose on Neon: the hidden account, this phone's keys, the API and the
/// conversation on disk. Opening needs no network, so Moose starts offline.
class NeonBackend {
  NeonBackend._(this.auth, this.api, this.identity, this.store);

  final NeonAuth auth;
  final MooseApi api;
  final Identity identity;
  final LocalStore store;
  Channel? _channel;

  /// Whether Moose is on screen, so a new message counts as seen.
  bool Function() isOpen = () =>
      WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;

  static Future<NeonBackend> open(
    NeonConfig config, {
    required Vault vault,
    required Directory dir,
    String label = 'p',
  }) async {
    final auth = NeonAuth(base: config.auth, vault: vault, label: label);
    return NeonBackend._(
      auth,
      MooseApi(base: config.api, auth: auth),
      await Identity.load(vault),
      await LocalStore.open(dir),
    );
  }

  /// The sealed channel to the partner, once paired.
  Future<Channel?> channel() async {
    final p = store.partner;
    if (p == null) return null;
    return _channel ??= await identity.channelTo(p.pubkey);
  }

  /// Takes the server's word for who the partner is.
  Future<Pairing> adopt(Me me) async {
    final p = me.partner!;
    store
      ..partner = p
      ..since = me.since ?? DateTime.now()
      ..securityCode = await securityCode(identity.publicKey, p.pubkey);
    if (me.member.name.isNotEmpty) store.myName = me.member.name;
    _channel = null;
    await store.flush();
    return pairing();
  }

  Pairing pairing() {
    final p = store.partner;
    return Pairing(
      me: Person(id: 'me', name: store.myName.isEmpty ? 'You' : store.myName),
      partner: Person(id: p?.id ?? 'partner', name: p?.name ?? ''),
      since: store.since ?? DateTime.now(),
      securityCode: store.securityCode,
      presence: Presence.away,
    );
  }

  /// The overrides that put this backend under every screen.
  List<Override> overrides() {
    final pair = NeonPairRepository(this);
    return [
      onNeonProvider.overrideWithValue(true),
      pairRepositoryProvider.overrideWithValue(pair),
      chatRepositoryProvider.overrideWith((ref) {
        final repo = NeonChatRepository(this);
        ref.onDispose(repo.dispose);
        return repo;
      }),
      sessionProvider.overrideWith(
        () => _StartSession(
          Session(paired: store.paired, locked: false, name: store.myName),
        ),
      ),
    ];
  }
}

class _StartSession extends SessionNotifier {
  _StartSession(this._start);
  final Session _start;

  @override
  Session build() => _start;
}

class NeonPairRepository implements PairRepository {
  NeonPairRepository(this.b);
  final NeonBackend b;

  @override
  Pairing load() => b.pairing();

  @override
  Future<void> setName(String name) async {
    b.store
      ..myName = name
      ..changed();
    await b.api.setMe(name: name, pubkey: b.identity.publicKey);
  }

  Future<void> _register() =>
      b.api.setMe(name: b.store.myName, pubkey: b.identity.publicKey);

  @override
  Future<String> invite() async {
    await _register();
    return (await b.api.invite()).code;
  }

  @override
  Stream<Pairing> waitForPartner({required Duration mockAfter}) async* {
    final until = DateTime.now().add(const Duration(minutes: 10));
    while (DateTime.now().isBefore(until)) {
      try {
        final me = await b.api.me();
        if (me.paired) {
          yield await b.adopt(me);
          return;
        }
      } on NetError catch (e) {
        if (!e.offline) rethrow;
      }
      await Future<void>.delayed(const Duration(seconds: 2));
    }
    throw const NetError(408, 'nobody joined');
  }

  @override
  Future<Pairing?> join(String code) async {
    await _register();
    try {
      return await b.adopt(await b.api.join(code));
    } on NetError catch (e) {
      if (e.status == 404 || e.status == 400) return null;
      rethrow;
    }
  }

  @override
  Future<void> unpair() async {
    await b.api.unpair();
    await b.store.clear();
  }
}

/// The conversation over Neon: sealed mail out through the API, in live
/// over Realtime, with a slow poll as a safety net (Realtime doesn't
/// promise every change).
class NeonChatRepository implements ChatRepository {
  NeonChatRepository(this.b) {
    unawaited(_run());
  }

  final NeonBackend b;
  final _events = StreamController<ChatEvent>.broadcast();
  final _seen = <String>{};
  var _closed = false;
  var _online = true;
  StreamSubscription<Mail>? _live;
  Timer? _poll;
  DateTime _typingSent = DateTime.fromMillisecondsSinceEpoch(0);

  static final _rnd = Random.secure();

  static String uuid() {
    final b = List<int>.generate(16, (_) => _rnd.nextInt(256));
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;
    final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-'
        '${h.substring(16, 20)}-${h.substring(20)}';
  }

  @override
  List<Message> history() => b.store.messages;

  @override
  Stream<ChatEvent> get events => _events.stream;

  void _emit(ChatEvent e) {
    if (!_events.isClosed) _events.add(e);
  }

  void _setOnline(bool v) {
    if (v == _online) return;
    _online = v;
    _emit(OnlineChanged(v));
  }

  /// Connects, catches up, then listens; backs off and retries on any drop.
  Future<void> _run() async {
    var wait = const Duration(seconds: 2);
    _poll = Timer.periodic(const Duration(seconds: 30), (_) => _catchUp());
    while (!_closed) {
      if (!b.store.paired) {
        await Future<void>.delayed(const Duration(seconds: 2));
        continue;
      }
      try {
        await _checkPairing();
        await _catchUp();
        final done = Completer<void>();
        final stream = await b.api.live();
        _setOnline(true);
        wait = const Duration(seconds: 2);
        _live = stream.listen(
          (m) => _handle([m]),
          onDone: done.complete,
          onError: (Object _) => done.complete(),
          cancelOnError: true,
        );
        await done.future;
      } on Object {
        _setOnline(false);
      }
      if (_closed) break;
      await Future<void>.delayed(wait);
      wait = Duration(seconds: min(wait.inSeconds * 2, 30));
    }
  }

  Future<void> _checkPairing() async {
    final me = await b.api.me();
    if (!me.paired && b.store.paired) {
      await b.store.clear();
      _emit(const Unpaired());
    }
  }

  Future<void> _catchUp() async {
    if (_closed || !b.store.paired) return;
    try {
      await _handle(await b.api.inbox());
      _setOnline(true);
    } on NetError catch (e) {
      if (e.offline) _setOnline(false);
    }
  }

  /// Opens, applies and acks a batch of mail.
  Future<void> _handle(List<Mail> mail) async {
    final ch = await b.channel();
    if (ch == null || mail.isEmpty) return;
    final ack = <String>[];
    final delivered = <String>[];
    for (final m in mail) {
      ack.add(m.id);
      if (!_seen.add(m.id)) continue;
      final Envelope? env;
      try {
        env = Envelope.fromJson(await ch.openJson(m.body));
      } on Object {
        continue; // Not sealed by the partner: drop it.
      }
      switch (env) {
        case MessageEnvelope(:final message):
          if (b.store.messages.any((x) => x.id == message.id)) break;
          delivered.add(message.id);
          _emit(Incoming(message));
          if (message.body case MomentBody(:final moment)
              when DateTime.now().difference(message.at).inMinutes < 2) {
            _emit(MomentArrived(moment));
          }
        case ReceiptEnvelope(:final ids, :final state):
          for (final id in ids) {
            _emit(DeliveryUpdate(id, state));
          }
        case TypingEnvelope(:final on):
          if (DateTime.now().difference(m.at).inSeconds < 10) {
            _emit(TypingChanged(on));
          }
        case ReactEnvelope(:final id, :final emoji):
          _emit(ReactionChanged(id, emoji));
        case null:
          break;
      }
    }
    if (delivered.isNotEmpty) {
      final open = b.isOpen();
      unawaited(
        _post(
          MailKind.receipt,
          ReceiptEnvelope(delivered, open ? Delivery.seen : Delivery.delivered),
        ),
      );
    }
    try {
      await b.api.ack(ack);
    } on NetError {
      // Acked next time; _seen keeps them from showing twice.
    }
  }

  Future<bool> _post(MailKind kind, Envelope env) async {
    final ch = await b.channel();
    if (ch == null) return false;
    try {
      await b.api.send(uuid(), kind, await ch.sealJson(env.toJson()));
      return true;
    } on NetError {
      return false;
    }
  }

  @override
  void send(Message message) {
    final kind = switch (message.body) {
      MomentBody() => MailKind.moment,
      CallBody() => MailKind.call,
      _ => MailKind.msg,
    };
    unawaited(
      _post(kind, MessageEnvelope(message)).then(
        (ok) => _emit(
          DeliveryUpdate(message.id, ok ? Delivery.sent : Delivery.failed),
        ),
      ),
    );
  }

  @override
  void react(String id, String? emoji) =>
      unawaited(_post(MailKind.receipt, ReactEnvelope(id, emoji)));

  @override
  void typing(bool on) {
    // At most one "typing" every 4 s; "stopped" always goes.
    final now = DateTime.now();
    if (on && now.difference(_typingSent).inSeconds < 4) return;
    _typingSent = on ? now : DateTime.fromMillisecondsSinceEpoch(0);
    unawaited(_post(MailKind.typing, TypingEnvelope(on)));
  }

  @override
  void store(List<Message> messages) {
    b.store
      ..messages = messages
      ..changed();
  }

  @override
  void dispose() {
    _closed = true;
    _poll?.cancel();
    unawaited(_live?.cancel());
    unawaited(_events.close());
    unawaited(b.store.flush());
  }
}
