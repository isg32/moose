import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../data/chat_theme.dart';
import '../data/models.dart';
import 'api.dart';
import 'wire.dart';

/// The conversation and the pairing, kept on this phone (the server
/// forgets mail once it's delivered). One JSON file in app-private storage,
/// written shortly after each change.
class LocalStore {
  LocalStore._(this._file);

  final File _file;

  Member? partner;
  String myName = '';

  /// Your picture and your person's, as files on this phone.
  String? myPhoto;
  String? partnerPhoto;
  DateTime? since;
  List<String> securityCode = const [];
  List<Message> messages = const [];
  ChatTheme theme = const ChatTheme();
  AppSettings settings = const AppSettings();
  List<Doodle> doodles = const [];

  /// The sticker library (null until first saved: Moose starts it empty).
  List<StickerPack>? stickers;

  Timer? _save;
  Future<void> _writing = Future.value();

  static Future<LocalStore> open(Directory dir) async {
    final s = LocalStore._(File('${dir.path}/moose.json'));
    if (await s._file.exists()) {
      try {
        s._read(
          (jsonDecode(await s._file.readAsString()) as Map)
              .cast<String, Object?>(),
        );
      } on Object {
        // A torn write: start from nothing rather than not at all.
      }
    }
    return s;
  }

  bool get paired => partner != null;

  void _read(Map<String, Object?> j) {
    final p = (j['partner'] as Map?)?.cast<String, Object?>();
    partner = p == null ? null : Member.fromJson(p);
    myName = (j['me'] as String?) ?? '';
    myPhoto = j['myPhoto'] as String?;
    partnerPhoto = j['partnerPhoto'] as String?;
    since = j['since'] == null ? null : DateTime.parse(j['since'] as String);
    securityCode = [for (final g in (j['code'] as List?) ?? const []) '$g'];
    final t = (j['theme'] as Map?)?.cast<String, Object?>();
    if (t != null) theme = ChatTheme.fromJson(t);
    doodles = [
      for (final d in (j['doodles'] as List?) ?? const [])
        _doodle((d as Map).cast<String, Object?>()),
    ];
    final packs = j['stickers'] as List?;
    stickers = packs == null
        ? null
        : [for (final p in packs) _pack((p as Map).cast<String, Object?>())];
    final st = (j['settings'] as Map?)?.cast<String, Object?>();
    if (st != null) settings = AppSettings.fromJson(st);
    // Before v2, hiding in recents (which blocks screenshots) was on by
    // default; it's off unless chosen now.
    if (((j['v'] as num?) ?? 1) < 2) {
      settings = settings.copyWith(hideInRecents: false);
    }
    messages = [
      for (final m in (j['messages'] as List?) ?? const [])
        _message((m as Map).cast<String, Object?>()),
    ];
  }

  Map<String, Object?> _json() => {
    'v': 2,
    'me': myName,
    'myPhoto': myPhoto,
    'partnerPhoto': partnerPhoto,
    if (partner case final p?)
      'partner': {'id': p.id, 'name': p.name, 'pubkey': p.pubkey},
    'since': since?.toIso8601String(),
    'code': securityCode,
    'theme': theme.toJson(),
    'settings': settings.toJson(),
    if (stickers case final packs?)
      'stickers': [
        for (final p in packs)
          {
            'id': p.id,
            'name': p.name,
            'note': p.note,
            'stickers': [
              for (final s in p.stickers)
                {
                  'from': s.from,
                  'fav': s.favourite,
                  ...Wire.body(StickerBody(s), local: true),
                },
            ],
          },
      ],
    'doodles': [
      for (final d in doodles)
        {
          'id': d.id,
          'name': d.name,
          'paper': d.paper.name,
          'by': d.editedBy,
          'at': d.editedAt.toIso8601String(),
          'strokes': [for (final s in d.strokes) Wire.stroke(s)],
        },
    ],
    'messages': [for (final m in messages) _stored(m)],
  };

  /// Saves soon; many changes in a row write once.
  void changed() {
    _save?.cancel();
    _save = Timer(const Duration(milliseconds: 300), flush);
  }

  /// Writes now. Writes queue up, so two never race on the temp file.
  Future<void> flush() {
    _save?.cancel();
    final json = jsonEncode(_json());
    return _writing = _writing.catchError((Object _) {}).then((_) async {
      final tmp = File('${_file.path}.tmp');
      await tmp.writeAsString(json, flush: true);
      await tmp.rename(_file.path);
    });
  }

  /// Forgets the partner and the conversation (unpair).
  Future<void> clear() async {
    partner = null;
    since = null;
    securityCode = const [];
    messages = const [];
    await flush();
  }

  static StickerPack _pack(Map<String, Object?> j) => StickerPack(
    id: j['id'] as String,
    name: j['name'] as String,
    note: (j['note'] as String?) ?? '',
    stickers: [
      for (final raw in j['stickers'] as List)
        if (Wire.toBody((raw as Map).cast<String, Object?>()) case StickerBody(
          :final sticker,
        ))
          _owned(sticker, raw['from'] as String?, raw['fav'] as bool?),
    ],
  );

  static Sticker _owned(Sticker s, String? from, bool? fav) => s.isDoodle
      ? Sticker.doodle(
          id: s.id,
          strokes: s.strokes,
          favourite: fav ?? false,
          from: from ?? 'me',
        )
      : Sticker.photo(
          id: s.id,
          art: s.art,
          shape: s.shape,
          favourite: fav ?? false,
          from: from ?? 'me',
          path: s.path,
        );

  static Doodle _doodle(Map<String, Object?> j) => Doodle(
    id: j['id'] as String,
    name: j['name'] as String,
    paper: Paper.values.asNameMap()[j['paper']] ?? Paper.dotted,
    editedBy: j['by'] as String,
    editedAt: DateTime.parse(j['at'] as String),
    strokes: [
      for (final s in j['strokes'] as List)
        Wire.toStroke((s as Map).cast<String, Object?>()),
    ],
  );

  static Map<String, Object?> _stored(Message m) => {
    ...Wire.fromMessage(m, local: true),
    'me': m.fromMe,
    'd': m.delivery.name,
    if (m.reactions.isNotEmpty)
      'r': [
        for (final r in m.reactions)
          {'e': r.emoji, 'mine': r.mine, 'n': r.count},
      ],
  };

  static Message _message(Map<String, Object?> j) {
    final m = Wire.message(j);
    final fromMe = j['me'] as bool;
    final reply = m.reply;
    return Message(
      id: m.id,
      fromMe: fromMe,
      at: m.at,
      body: m.body,
      // Stored quotes are already from this phone's side.
      reply: reply == null
          ? null
          : Quote(
              fromMe: !reply.fromMe,
              text: reply.text,
              art: reply.art,
              music: reply.music,
            ),
      delivery: switch (Delivery.values.byName(j['d'] as String)) {
        // Still pending when the app closed: it will be retried.
        Delivery.pending => Delivery.failed,
        final d => d,
      },
      reactions: [
        for (final r in (j['r'] as List?) ?? const [])
          Reaction(
            (r as Map)['e'] as String,
            mine: r['mine'] as bool,
            count: (r['n'] as num).toInt(),
          ),
      ],
    );
  }
}
