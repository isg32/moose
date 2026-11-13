import 'dart:ui' show Offset;

import '../core/theme/v_colors.dart';
import '../data/chat_theme.dart';
import '../data/models.dart';

/// What travels inside a sealed envelope. The server sees only the coarse
/// [MailKind](api.dart); this is the plaintext both phones agree on.
sealed class Envelope {
  const Envelope();

  Map<String, Object?> toJson();

  /// Null for an envelope from a newer Moose this one can't read.
  static Envelope? fromJson(Map<String, Object?> j) => switch (j['type']) {
    'msg' => MessageEnvelope(Wire.message(j)),
    'receipt' => ReceiptEnvelope([
      for (final id in j['ids'] as List) id as String,
    ], Delivery.values.byName(j['state'] as String)),
    'typing' => TypingEnvelope(j['on'] as bool),
    'react' => ReactEnvelope(j['id'] as String, j['emoji'] as String?),
    'doodle' => DoodleEnvelope(Wire.doodleOp(j)),
    'theme' => ThemeEnvelope(
      ChatTheme.fromJson((j['theme'] as Map).cast<String, Object?>()),
      blob: j['blob'] as String?,
      blobKey: j['k'] as String?,
    ),
    _ => null,
  };
}

class MessageEnvelope extends Envelope {
  const MessageEnvelope(this.message);
  final Message message;

  @override
  Map<String, Object?> toJson() => {
    'type': 'msg',
    ...Wire.fromMessage(message),
  };
}

/// Your messages reached the other phone, or were seen there.
class ReceiptEnvelope extends Envelope {
  const ReceiptEnvelope(this.ids, this.state);
  final List<String> ids;
  final Delivery state;

  @override
  Map<String, Object?> toJson() => {
    'type': 'receipt',
    'ids': ids,
    'state': state.name,
  };
}

class TypingEnvelope extends Envelope {
  const TypingEnvelope(this.on);
  final bool on;

  @override
  Map<String, Object?> toJson() => {'type': 'typing', 'on': on};
}

/// The sender's reaction on message [id] now; null took it back.
class ReactEnvelope extends Envelope {
  const ReactEnvelope(this.id, this.emoji);
  final String id;
  final String? emoji;

  @override
  Map<String, Object?> toJson() => {'type': 'react', 'id': id, 'emoji': emoji};
}

/// A change to a shared doodle board (C29–C35).
class DoodleEnvelope extends Envelope {
  const DoodleEnvelope(this.op);
  final DoodleOp op;

  @override
  Map<String, Object?> toJson() => {'type': 'doodle', ...Wire.fromDoodleOp(op)};
}

/// The shared theme, last write wins. A photo wallpaper travels sealed in
/// storage, as [blob] with its own [blobKey].
class ThemeEnvelope extends Envelope {
  const ThemeEnvelope(this.theme, {this.blob, this.blobKey});
  final ChatTheme theme;
  final String? blob;
  final String? blobKey;

  @override
  Map<String, Object?> toJson() => {
    'type': 'theme',
    // A photo's path means nothing on the other phone.
    'theme': theme.toJson()
      ..['wallpaper'] = theme.wallpaper.photo == null
          ? theme.wallpaper.toJson()
          : const {'builtin': null, 'photo': 'blob'},
    'blob': ?blob,
    'k': ?blobKey,
  };
}

/// Message ↔ JSON. `fromMe` is not sent: it is always the sender's, and
/// the receiver flips it.
abstract final class Wire {
  /// [local] keeps what only matters on this phone (file paths), for the
  /// store; the wire never carries them.
  static Map<String, Object?> fromMessage(Message m, {bool local = false}) => {
    'id': m.id,
    'at': m.at.toUtc().toIso8601String(),
    'body': body(m.body, local: local),
    if (m.reply case final r?)
      'reply': {
        'fromMe': r.fromMe,
        'text': r.text,
        'art': ?r.art,
        'music': ?r.music,
      },
  };

  /// A message as it arrives on the other phone.
  static Message message(Map<String, Object?> j) {
    final reply = _map(j['reply']);
    return Message(
      id: j['id'] as String,
      fromMe: false,
      at: DateTime.parse(j['at'] as String).toLocal(),
      body: toBody(_map(j['body'])!),
      delivery: Delivery.delivered,
      reply: reply == null
          ? null
          : Quote(
              // Their "me" is my partner.
              fromMe: !(reply['fromMe'] as bool),
              text: reply['text'] as String,
              art: (reply['art'] as num?)?.toInt(),
              music: reply['music'] as bool?,
            ),
    );
  }

  static Map<String, Object?> body(Body b, {bool local = false}) => switch (b) {
    TextBody(:final text) => {'t': 'text', 'text': text},
    MomentBody(:final moment) => {'t': 'moment', 'moment': moment.name},
    MusicBody(:final song, :final start) => {
      't': 'music',
      'song': _song(song),
      'start': start.inMilliseconds,
    },
    MemeBody(:final meme) => {
      't': 'meme',
      'id': meme.id,
      'source': meme.source.name,
      'kind': meme.kind.name,
      'art': meme.art,
      'aspect': meme.aspect,
      'title': meme.title,
      'sub': ?meme.subreddit,
    },
    StickerBody(:final sticker) => {
      't': 'sticker',
      'id': sticker.id,
      if (sticker.isDoodle)
        'strokes': [for (final s in sticker.strokes) _stroke(s)]
      else ...{
        'art': sticker.art,
        'shape': sticker.shape,
      },
    },
    CallBody(:final video, :final outcome, :final length) => {
      't': 'call',
      'video': video,
      'outcome': outcome.name,
      'ms': length.inMilliseconds,
    },
    PhotoBody(:final photos, :final caption) => {
      't': 'photo',
      'photos': [for (final p in photos) _media(p, local: local)],
      'caption': ?caption,
    },
    VideoBody(:final video) => {
      't': 'video',
      'video': _media(video, local: local),
    },
    RoundVideoBody(:final video) => {'t': 'round', 'video': _media(video)},
    VoiceBody(:final length, :final wave, :final blob, :final blobKey) => {
      't': 'voice',
      'ms': length.inMilliseconds,
      'wave': [for (final w in wave) (w * 100).round()],
      'blob': ?blob,
      'k': ?blobKey,
      if (local) 'path': ?b.path,
      if (local && b.played) 'played': true,
    },
    SystemBody(:final kind, :final text) => {
      't': 'system',
      'kind': kind.name,
      'text': text,
    },
  };

  static Body toBody(Map<String, Object?> j) => switch (j['t']) {
    'text' => TextBody(j['text'] as String),
    'moment' => MomentBody(VMoment.values.byName(j['moment'] as String)),
    'music' => MusicBody(
      _toSong(_map(j['song'])!),
      start: Duration(milliseconds: (j['start'] as num).toInt()),
    ),
    'meme' => MemeBody(
      Meme(
        id: j['id'] as String,
        source: MemeSource.values.byName(j['source'] as String),
        kind: MemeKind.values.byName(j['kind'] as String),
        art: (j['art'] as num).toInt(),
        aspect: (j['aspect'] as num).toDouble(),
        title: j['title'] as String,
        subreddit: j['sub'] as String?,
      ),
    ),
    'sticker' when j['strokes'] != null => StickerBody(
      Sticker.doodle(
        id: j['id'] as String,
        from: 'partner',
        strokes: [for (final s in j['strokes'] as List) _toStroke(_map(s)!)],
      ),
    ),
    'sticker' => StickerBody(
      Sticker.photo(
        id: j['id'] as String,
        from: 'partner',
        art: (j['art'] as num).toInt(),
        shape: (j['shape'] as num).toInt(),
      ),
    ),
    'call' => CallBody(
      video: j['video'] as bool,
      outcome: CallOutcome.values.byName(j['outcome'] as String),
      length: Duration(milliseconds: (j['ms'] as num).toInt()),
    ),
    'photo' => PhotoBody([
      for (final p in j['photos'] as List) _toMedia(_map(p)!),
    ], caption: j['caption'] as String?),
    'video' => VideoBody(_toMedia(_map(j['video'])!)),
    'round' => RoundVideoBody(_toMedia(_map(j['video'])!)),
    'voice' => VoiceBody(
      length: Duration(milliseconds: (j['ms'] as num).toInt()),
      wave: [for (final w in j['wave'] as List) (w as num) / 100],
      blob: j['blob'] as String?,
      blobKey: j['k'] as String?,
      path: j['path'] as String?,
      played: j['played'] as bool? ?? false,
    ),
    'system' => SystemBody(
      SystemKind.values.byName(j['kind'] as String),
      j['text'] as String,
    ),
    final t => TextBody('This needs a newer Moose ($t)'),
  };

  static Map<String, Object?> _song(Song s) => {
    'v': s.videoId,
    'title': s.title,
    'artist': s.artist,
    'ms': s.length.inMilliseconds,
    'art': s.art,
  };

  static Song _toSong(Map<String, Object?> j) => Song(
    videoId: j['v'] as String,
    title: j['title'] as String,
    artist: j['artist'] as String,
    length: Duration(milliseconds: (j['ms'] as num).toInt()),
    art: (j['art'] as num).toInt(),
  );

  static Map<String, Object?> _media(Media m, {bool local = false}) => {
    'id': m.id,
    'art': m.art,
    'aspect': m.aspect,
    'bytes': m.bytes,
    if (m.duration case final d?) 'ms': d.inMilliseconds,
    'blob': ?m.blob,
    'k': ?m.blobKey,
    if (local) 'path': ?m.path,
  };

  static Media _toMedia(Map<String, Object?> j) => Media(
    id: j['id'] as String,
    art: (j['art'] as num).toInt(),
    aspect: (j['aspect'] as num).toDouble(),
    bytes: (j['bytes'] as num).toInt(),
    duration: j['ms'] == null
        ? null
        : Duration(milliseconds: (j['ms'] as num).toInt()),
    blob: j['blob'] as String?,
    blobKey: j['k'] as String?,
    path: j['path'] as String?,
  );

  static Map<String, Object?> fromDoodleOp(DoodleOp op) => switch (op) {
    DoodleCreated(:final doodle) => {
      'op': 'create',
      'id': doodle.id,
      'name': doodle.name,
      'paper': doodle.paper.name,
    },
    StrokesAdded(:final id, :final strokes) => {
      'op': 'add',
      'id': id,
      'strokes': [for (final s in strokes) stroke(s)],
    },
    StrokesSet(:final id, :final strokes) => {
      'op': 'set',
      'id': id,
      'strokes': [for (final s in strokes) stroke(s)],
    },
    DoodleRenamed(:final id, :final name) => {
      'op': 'rename',
      'id': id,
      'name': name,
    },
    DoodleDeleted(:final id) => {'op': 'delete', 'id': id},
    DoodlePresence(:final id, :final here) => {
      'op': 'here',
      'id': id,
      'here': here,
    },
  };

  /// An op as it arrives: strokes swap 'me' and 'partner'.
  static DoodleOp doodleOp(Map<String, Object?> j) {
    final id = j['id'] as String;
    List<Stroke> strokes() => [
      for (final s in j['strokes'] as List) toStroke(_map(s)!, flip: true),
    ];
    return switch (j['op']) {
      'create' => DoodleCreated(
        Doodle(
          id: id,
          name: j['name'] as String,
          strokes: const [],
          editedBy: 'partner',
          editedAt: DateTime.now(),
          paper: Paper.values.asNameMap()[j['paper']] ?? Paper.dotted,
        ),
      ),
      'add' => StrokesAdded(id, strokes()),
      'set' => StrokesSet(id, strokes()),
      'rename' => DoodleRenamed(id, j['name'] as String),
      'delete' => DoodleDeleted(id),
      _ => DoodlePresence(id, j['here'] as bool? ?? false),
    };
  }

  static Map<String, Object?> stroke(Stroke s) => _stroke(s);

  static Stroke toStroke(Map<String, Object?> j, {bool flip = false}) {
    final s = _toStroke(j);
    final by = (j['by'] as String?) ?? 'partner';
    return Stroke(
      tool: s.tool,
      argb: s.argb,
      size: s.size,
      opacity: s.opacity,
      points: s.points,
      by: flip ? (by == 'me' ? 'partner' : 'me') : by,
    );
  }

  // Points keep 4 decimals: plenty for a phone screen.
  static Map<String, Object?> _stroke(Stroke s) => {
    'by': s.by,
    'tool': s.tool.name,
    'argb': s.argb,
    'size': s.size,
    'opacity': s.opacity,
    'p': [
      for (final p in s.points) ...[
        (p.dx * 10000).round(),
        (p.dy * 10000).round(),
      ],
    ],
  };

  static Stroke _toStroke(Map<String, Object?> j) {
    final p = [for (final v in j['p'] as List) (v as num) / 10000];
    return Stroke(
      tool: PenTool.values.byName(j['tool'] as String),
      argb: (j['argb'] as num).toInt(),
      size: (j['size'] as num).toDouble(),
      opacity: (j['opacity'] as num).toDouble(),
      points: [
        for (var i = 0; i + 1 < p.length; i += 2) Offset(p[i], p[i + 1]),
      ],
      by: 'partner',
    );
  }

  static Map<String, Object?>? _map(Object? o) =>
      (o as Map?)?.cast<String, Object?>();
}
