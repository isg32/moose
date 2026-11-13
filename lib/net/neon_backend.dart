import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/misc.dart' show Override;

import '../data/chat_theme.dart';
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
  NeonBackend._(
    this.auth,
    this.api,
    this.identity,
    this.store,
    this.dir,
    this.vault,
    this._lock,
  );

  final Vault vault;

  /// The app lock as last saved: PIN, decoy PIN and the decoy's name.
  final ({String pin, String? decoy, String decoyName}) _lock;
  static const _kPin = 'lock.pin';
  static const _kDecoy = 'lock.decoy';
  static const _kDecoyName = 'lock.decoyName';

  final NeonAuth auth;
  final MooseApi api;
  final Identity identity;
  final LocalStore store;
  final Directory dir;
  Channel? _channel;

  /// Photos and wallpapers that came from the partner, decrypted.
  Directory get mediaDir => Directory('${dir.path}/media');

  /// This phone's push token (Firebase), when push is set up.
  Future<String?> Function()? pushToken;

  /// Set by the open chat: a push arrived, so look for mail now.
  void Function()? wake;

  /// The phone's gallery and camera; null keeps the mock pages.
  MediaSource? media;

  /// The microphone and speaker for voice notes; null keeps them pretend.
  Voice? voice;

  /// Asks for the notification permission.
  Future<bool> Function() askNotifications = () async => true;

  /// Shows a notification for a message taken while Moose isn't on
  /// screen (its live socket still runs in the background).
  Future<void> Function(Map<String, dynamic> push)? notifyAway;

  /// Starts and stops the background check (once paired, and on unpair).
  Future<void> Function()? startChecking;
  Future<void> Function()? stopChecking;

  /// Real calls (WebRTC); null keeps them pretend.
  CallLink? calls;

  /// Call set-up from the partner, for the [calls] link.
  final callSignals = StreamController<CallEnvelope>.broadcast();

  /// Seals [env] for the partner and leaves it on the server.
  Future<bool> post(MailKind kind, Envelope env) async {
    final ch = await channel();
    if (ch == null) return false;
    try {
      await api.send(
        NeonChatRepository.uuid(),
        kind,
        await ch.sealJson(env.toJson()),
      );
      return true;
    } on NetError {
      return false;
    }
  }

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
      dir,
      vault,
      (
        pin: await vault.read(_kPin) ?? '',
        decoy: await vault.read(_kDecoy),
        decoyName: await vault.read(_kDecoyName) ?? 'Neha',
      ),
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
      chatThemeProvider.overrideWith(() => _StoredTheme(store)),
      doodleRepositoryProvider.overrideWithValue(_StoredDoodles(store)),
      stickerRepositoryProvider.overrideWithValue(_StoredStickers(store)),
      mediaSourceProvider.overrideWithValue(media),
      voiceProvider.overrideWithValue(voice),
      callLinkProvider.overrideWithValue(calls),
      askNotificationsProvider.overrideWithValue(() => askNotifications()),
      settingsProvider.overrideWith(() => _StoredSettings(store)),
      sessionProvider.overrideWith(
        () => _StoredSession(
          vault,
          Session(
            paired: store.paired,
            // With a PIN saved, Moose opens locked (C13).
            locked: _lock.pin.isNotEmpty,
            pin: _lock.pin,
            decoyPin: _lock.decoy,
            decoyName: _lock.decoyName,
            name: store.myName,
          ),
        ),
      ),
    ];
  }
}

/// The shared theme, kept with the conversation.
class _StoredTheme extends ChatThemeNotifier {
  _StoredTheme(this._store);
  final LocalStore _store;

  @override
  ChatTheme build() => _store.theme;

  @override
  void set(ChatTheme theme) {
    super.set(theme);
    _store
      ..theme = theme
      ..changed();
  }
}

/// The doodle boards, kept with the conversation (they start empty).
class _StoredDoodles implements DoodleRepository {
  _StoredDoodles(this._store);
  final LocalStore _store;

  @override
  List<Doodle> load() => _store.doodles;

  @override
  void save(List<Doodle> doodles) {
    _store
      ..doodles = doodles
      ..changed();
  }
}

/// The sticker library: yours, and the ones you saved from your person.
class _StoredStickers implements StickerRepository {
  _StoredStickers(this._store);
  final LocalStore _store;

  @override
  List<StickerPack> load() =>
      _store.stickers ??
      const [
        StickerPack(
          id: 'ours',
          name: 'Ours',
          note: 'Made by you two',
          stickers: [],
        ),
        StickerPack(
          id: 'saved',
          name: 'Saved',
          note: 'From your person',
          stickers: [],
        ),
      ];

  @override
  void save(List<StickerPack> packs) {
    _store
      ..stickers = packs
      ..changed();
  }
}

/// Local settings, kept with the conversation.
class _StoredSettings extends SettingsNotifier {
  _StoredSettings(this._store);
  final LocalStore _store;

  @override
  AppSettings build() => _store.settings;

  @override
  void update(AppSettings Function(AppSettings) f) {
    super.update(f);
    _store
      ..settings = state
      ..changed();
  }
}

/// The session, with the app lock kept in the Keystore.
class _StoredSession extends SessionNotifier {
  _StoredSession(this._vault, this._start);
  final Vault _vault;
  final Session _start;

  @override
  Session build() => _start;

  void _save() {
    unawaited(_vault.write(NeonBackend._kPin, state.pin));
    unawaited(_vault.write(NeonBackend._kDecoy, state.decoyPin));
    unawaited(_vault.write(NeonBackend._kDecoyName, state.decoyName));
  }

  @override
  void setPin(String pin) {
    super.setPin(pin);
    _save();
  }

  @override
  void setDecoy(String pin, String name) {
    super.setDecoy(pin, name);
    _save();
  }

  @override
  void removeLock() {
    super.removeLock();
    _save();
  }
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
  Future<List<String>?> peek(String code) async {
    try {
      final them = await b.api.peek(code.toUpperCase());
      return await securityCode(b.identity.publicKey, them.pubkey);
    } on NetError catch (e) {
      if (e.status == 404 || e.status == 400) return null;
      rethrow;
    }
  }

  @override
  Future<void> unpair() async {
    await b.stopChecking?.call();
    await b.api.unpair();
    await b.store.clear();
  }
}

/// The conversation over Neon: sealed mail out through the API, in live
/// over Realtime, with a slow poll as a safety net (Realtime doesn't
/// promise every change).
class NeonChatRepository implements ChatRepository {
  NeonChatRepository(this.b) {
    b.wake = () => unawaited(_catchUp());
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
  String? _pushToken;

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
        if (b.store.paired) unawaited(b.startChecking?.call());
        await _registerPush();
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

  /// Tells the server where to send wake-ups, when the token is new.
  Future<void> _registerPush() async {
    final token = await b.pushToken?.call();
    if (token == null || token == _pushToken) return;
    await b.api.setMe(fcm: token);
    _pushToken = token;
  }

  Future<void> _checkPairing() async {
    final me = await b.api.me();
    if (!me.paired && b.store.paired) {
      await b.stopChecking?.call();
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
        case MessageEnvelope(message: final sent):
          if (b.store.messages.any((x) => x.id == sent.id)) break;
          final message = _arrived(sent);
          delivered.add(message.id);
          if (!b.isOpen()) {
            unawaited(b.notifyAway?.call({'kind': m.kind, 'body': m.body}));
          }
          _emit(Incoming(message));
          _fetchMedia(message);
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
        case DoodleEnvelope(:final op):
          _emit(DoodleChanged(op));
        case CallEnvelope():
          // An offer older than a minute rang out long ago.
          if (env.op == 'offer' &&
              DateTime.now().difference(m.at).inSeconds < 60) {
            b.callSignals.add(env);
            _emit(CallArrived(video: env.video));
          } else if (env.op != 'offer') {
            b.callSignals.add(env);
          }
        case ThemeEnvelope(:final theme, :final blob, :final blobKey):
          unawaited(_themeArrived(theme, blob, blobKey));
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

  Future<bool> _post(MailKind kind, Envelope env) => b.post(kind, env);

  /// A message as this phone keeps it: system notes in the partner's
  /// words, and photos waiting to come down from storage.
  Message _arrived(Message m) {
    final name = b.store.partner?.name ?? 'Your person';
    Media waiting(Media x) => x.blob == null
        ? x
        : x.copyWith(transfer: Transfer.cloudDownloading, progress: 0);
    return m.copyWith(
      body: switch (m.body) {
        SystemBody(:final kind, :final text) when text.startsWith('You ') =>
          SystemBody(kind, '$name ${text.substring(4)}'),
        PhotoBody(:final photos, :final caption) => PhotoBody([
          for (final p in photos) waiting(p),
        ], caption: caption),
        VideoBody(:final video) => VideoBody(waiting(video)),
        RoundVideoBody(:final video) => RoundVideoBody(waiting(video)),
        final b => b,
      },
    );
  }

  /// Brings each sealed photo down, opens it, keeps it, then deletes the
  /// server's copy.
  void _fetchMedia(Message m) {
    final media = switch (m.body) {
      PhotoBody(:final photos) => photos,
      VideoBody(:final video) => [video],
      RoundVideoBody(:final video) => [video],
      _ => const <Media>[],
    };
    if (m.body case StickerBody(
      sticker: Sticker(:final blob?, :final blobKey?, :final id),
    )) {
      unawaited(() async {
        try {
          final path = await _download(blob, blobKey, 'sticker-$id');
          _emit(MediaReady(m.id, 'sticker', path));
        } on Object {
          // Left in storage: the next start tries again.
        }
      }());
    }
    if (m.body case VoiceBody(:final blob?, :final blobKey?)) {
      unawaited(() async {
        try {
          final path = await _download(blob, blobKey, '${m.id}.m4a');
          _emit(MediaReady(m.id, 'voice', path));
        } on Object {
          // Left in storage: the next start tries again.
        }
      }());
    }
    for (final x in media) {
      if (x.blob == null || x.blobKey == null) continue;
      unawaited(() async {
        try {
          final path = await _download(x.blob!, x.blobKey!, x.id);
          _emit(MediaReady(m.id, x.id, path));
        } on Object {
          // Left in storage: the next start tries again.
        }
      }());
    }
  }

  Future<String> _download(String blob, String key, String name) async {
    final plain = await Channel.openBlob(await b.api.download(blob), key);
    await b.mediaDir.create(recursive: true);
    final file = File('${b.mediaDir.path}/$name');
    await file.writeAsBytes(plain, flush: true);
    try {
      await b.api.deleteBlob(blob);
    } on NetError {
      // The month-old sweep gets it.
    }
    return file.path;
  }

  /// Seals and uploads [m]'s files that aren't in storage yet.
  Future<Media> _upload(Media m) async {
    final path = m.path;
    if (m.blob != null || path == null) return m;
    final sealed = await Channel.sealBlob(await File(path).readAsBytes());
    final key = await b.api.upload(sealed.bytes);
    return m.copyWith(blob: key, blobKey: sealed.key);
  }

  Future<Message> _withUploads(Message m) async => switch (m.body) {
    PhotoBody(:final photos, :final caption) => m.copyWith(
      body: PhotoBody([
        for (final p in photos) await _upload(p),
      ], caption: caption),
    ),
    VideoBody(:final video) => m.copyWith(
      body: VideoBody(await _upload(video)),
    ),
    RoundVideoBody(:final video) => m.copyWith(
      body: RoundVideoBody(await _upload(video)),
    ),
    StickerBody(:final sticker)
        when sticker.path != null && sticker.blob == null =>
      await () async {
        final sealed = await Channel.sealBlob(
          await File(sticker.path!).readAsBytes(),
        );
        final key = await b.api.upload(sealed.bytes);
        return m.copyWith(
          body: StickerBody(sticker.withFile(blob: key, blobKey: sealed.key)),
        );
      }(),
    VoiceBody(:final path, :final blob) when path != null && blob == null =>
      await () async {
        final sealed = await Channel.sealBlob(await File(path).readAsBytes());
        final key = await b.api.upload(sealed.bytes);
        return m.copyWith(
          body: (m.body as VoiceBody).copyWith(blob: key, blobKey: sealed.key),
        );
      }(),
    _ => m,
  };

  Future<void> _themeArrived(ChatTheme t, String? blob, String? key) async {
    var theme = t;
    if (blob != null && key != null) {
      try {
        final path = await _download(blob, key, 'wall-${uuid()}');
        theme = t.copyWith(wallpaper: WallpaperRef.photo(path));
      } on Object {
        return; // Couldn't get the photo: keep the current theme.
      }
    } else if (t.wallpaper.photo != null) {
      return;
    }
    _emit(ThemeChanged(theme));
  }

  @override
  void send(Message message) {
    final kind = switch (message.body) {
      MomentBody() => MailKind.moment,
      CallBody() => MailKind.call,
      _ => MailKind.msg,
    };
    unawaited(() async {
      var ok = false;
      try {
        ok = await _post(kind, MessageEnvelope(await _withUploads(message)));
      } on Object {
        ok = false;
      }
      _emit(DeliveryUpdate(message.id, ok ? Delivery.sent : Delivery.failed));
    }());
  }

  @override
  void shareDoodle(DoodleOp op) =>
      unawaited(_post(MailKind.doodle, DoodleEnvelope(op)));

  @override
  void shareTheme(ChatTheme theme) => unawaited(() async {
    final photo = theme.wallpaper.photo;
    if (photo == null) {
      await _post(MailKind.theme, ThemeEnvelope(theme));
      return;
    }
    if (photo.startsWith('mock:')) return; // Stand-in art isn't shareable.
    try {
      final sealed = await Channel.sealBlob(await File(photo).readAsBytes());
      final key = await b.api.upload(sealed.bytes);
      await _post(
        MailKind.theme,
        ThemeEnvelope(theme, blob: key, blobKey: sealed.key),
      );
    } on Object {
      // Offline: the theme stays here until it's applied again.
    }
  }());

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
    b.wake = null;
    _poll?.cancel();
    unawaited(_live?.cancel());
    unawaited(_events.close());
    unawaited(b.store.flush());
  }
}
