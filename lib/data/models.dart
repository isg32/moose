import 'dart:ui' show Offset;

import '../core/theme/v_colors.dart';

/// One of the two people in a pair.
class Person {
  const Person({required this.id, required this.name, this.photo});

  final String id;
  final String name;

  /// A local file path, or null for the initial in a circle.
  final String? photo;

  String get initial => name.isEmpty ? '?' : name[0].toUpperCase();

  Person copyWith({String? name, String? photo}) =>
      Person(id: id, name: name ?? this.name, photo: photo ?? this.photo);
}

/// Where the partner is right now (A8).
enum Presence { online, typing, away }

/// The pairing: you, your person, and how you're connected.
class Pairing {
  const Pairing({
    required this.me,
    required this.partner,
    required this.since,
    required this.securityCode,
    this.presence = Presence.online,
    this.lastSeen,
    this.waitingOnServer = 0,
  });

  final Person me;
  final Person partner;
  final DateTime since;

  /// Twelve five-digit groups both phones show (C8, C37).
  final List<String> securityCode;
  final Presence presence;
  final DateTime? lastSeen;

  /// Messages sealed on the server for the partner (C37).
  final int waitingOnServer;

  Pairing copyWith({
    Person? me,
    Person? partner,
    Presence? presence,
    DateTime? lastSeen,
  }) => Pairing(
    me: me ?? this.me,
    partner: partner ?? this.partner,
    since: since,
    securityCode: securityCode,
    presence: presence ?? this.presence,
    lastSeen: lastSeen ?? this.lastSeen,
    waitingOnServer: waitingOnServer,
  );
}

/// How far a sent message has got (B: pending, ✓, ✓✓, bold ✓✓, failed).
enum Delivery { pending, sent, delivered, seen, failed }

/// How a piece of media is reaching this phone (B4).
enum Transfer {
  /// On this phone.
  done,

  /// Coming straight from the partner's phone (P2P), with progress.
  direct,

  /// Waiting in the cloud: tap to download.
  cloud,

  /// Coming from the cloud, with progress.
  cloudDownloading,

  /// The partner's phone is offline and nothing is in the cloud yet.
  waiting,
}

/// A photo or video as the chat shows it. [art] picks the stand-in art until
/// real media arrives.
class Media {
  const Media({
    required this.id,
    required this.art,
    this.aspect = 1.4,
    this.bytes = 2400000,
    this.transfer = Transfer.done,
    this.progress = 0,
    this.duration,
  });

  final String id;
  final int art;

  /// Width / height.
  final double aspect;
  final int bytes;
  final Transfer transfer;
  final double progress;

  /// For videos.
  final Duration? duration;
}

/// A song clip: the YouTube video and the 15 s window (B8).
class Song {
  const Song({
    required this.videoId,
    required this.title,
    required this.artist,
    required this.length,
    required this.art,
  });

  final String videoId;
  final String title;
  final String artist;
  final Duration length;
  final int art;
}

/// Where a meme came from.
enum MemeSource { klipy, reddit }

enum MemeKind { gif, sticker, meme, clip }

/// One result in the meme picker (C26), or a sent meme (B9).
class Meme {
  const Meme({
    required this.id,
    required this.source,
    required this.kind,
    required this.art,
    this.aspect = 1.2,
    this.title = '',
    this.subreddit,
  });

  final String id;
  final MemeSource source;
  final MemeKind kind;
  final int art;
  final double aspect;
  final String title;
  final String? subreddit;

  String get credit => switch (source) {
    MemeSource.klipy => 'via KLIPY',
    MemeSource.reddit => 'r/${subreddit ?? 'memes'}',
  };

  String get tag => switch (kind) {
    MemeKind.gif => 'GIF',
    MemeKind.sticker => 'STICKER',
    MemeKind.meme => 'MEME',
    MemeKind.clip => 'CLIP',
  };
}

/// A stroke drawn on a doodle or a doodle sticker.
class Stroke {
  const Stroke({
    required this.tool,
    required this.argb,
    required this.points,
    this.size = 4,
    this.opacity = 1,
    this.by = 'me',
  });

  final PenTool tool;
  final int argb;
  final List<Offset> points;
  final double size;
  final double opacity;

  /// Who drew it: 'me' or 'partner'.
  final String by;
}

/// The nine doodle tools (C32), in the dock's order.
enum PenTool {
  fineLiner('Fine liner'),
  marker('Marker'),
  brush('Brush'),
  pencil('Pencil'),
  calligraphy('Calligraphy'),
  neon('Neon'),
  highlighter('Highlighter'),
  eraser('Eraser'),
  lasso('Lasso');

  const PenTool(this.label);
  final String label;
}

/// A sticker: a cut-out photo or a doodle with a white outline.
class Sticker {
  const Sticker.photo({
    required this.id,
    required this.art,
    this.shape = 0,
    this.favourite = false,
    this.from = 'me',
  }) : strokes = const [];

  const Sticker.doodle({
    required this.id,
    required this.strokes,
    this.favourite = false,
    this.from = 'me',
  }) : art = 0,
       shape = 0;

  final String id;

  /// Photo stickers: stand-in art and which blob shape it was cut to.
  final int art;
  final int shape;

  /// Doodle stickers: their strokes, in a 0–1 box.
  final List<Stroke> strokes;
  final bool favourite;
  final String from;

  bool get isDoodle => strokes.isNotEmpty;

  Sticker withFavourite(bool f) => isDoodle
      ? Sticker.doodle(id: id, strokes: strokes, favourite: f, from: from)
      : Sticker.photo(id: id, art: art, shape: shape, favourite: f, from: from);
}

/// A named set of stickers (S5).
class StickerPack {
  const StickerPack({
    required this.id,
    required this.name,
    required this.note,
    required this.stickers,
  });

  final String id;
  final String name;
  final String note;
  final List<Sticker> stickers;
}

/// What happened in a call row (K5).
enum CallOutcome { answered, missed, noAnswer }

/// A reaction on a message: the emoji and who reacted.
class Reaction {
  const Reaction(this.emoji, {this.mine = false, this.count = 1});

  final String emoji;
  final bool mine;
  final int count;
}

/// What a message is. One class per kind keeps each bubble's data typed.
sealed class Body {
  const Body();
}

class TextBody extends Body {
  const TextBody(this.text);
  final String text;

  /// Only emoji, so the bubble drops and the emoji grow (B1).
  bool get emojiOnly {
    final t = text.replaceAll(RegExp(r'\s'), '');
    if (t.isEmpty) return false;
    return t.runes.every((r) => r > 0x2000);
  }
}

class PhotoBody extends Body {
  const PhotoBody(this.photos, {this.caption});
  final List<Media> photos;
  final String? caption;
}

class VideoBody extends Body {
  const VideoBody(this.video);
  final Media video;
}

class RoundVideoBody extends Body {
  const RoundVideoBody(this.video, {this.playing = false});
  final Media video;
  final bool playing;
}

class VoiceBody extends Body {
  const VoiceBody({
    required this.length,
    required this.wave,
    this.played = false,
    this.position = Duration.zero,
  });

  final Duration length;

  /// Bar heights, 0–1.
  final List<double> wave;
  final bool played;
  final Duration position;
}

class MusicBody extends Body {
  const MusicBody(this.song, {required this.start, this.unavailable = false});

  final Song song;
  final Duration start;
  final bool unavailable;

  Duration get end => start + const Duration(seconds: 15);
}

class MemeBody extends Body {
  const MemeBody(this.meme);
  final Meme meme;
}

class StickerBody extends Body {
  const StickerBody(this.sticker);
  final Sticker sticker;
}

class MomentBody extends Body {
  const MomentBody(this.moment);
  final VMoment moment;
}

class CallBody extends Body {
  const CallBody({
    required this.video,
    required this.outcome,
    this.length = Duration.zero,
  });

  final bool video;
  final CallOutcome outcome;
  final Duration length;
}

/// The kinds of system row in the chat (B11).
enum SystemKind { theme, wallpaper, paired, doodle }

class SystemBody extends Body {
  const SystemBody(this.kind, this.text);
  final SystemKind kind;
  final String text;
}

/// A short summary of a message, for reply quotes (B2).
class Quote {
  const Quote({required this.fromMe, required this.text, this.art, this.music});

  final bool fromMe;
  final String text;

  /// Thumbnail art for a quoted photo or sticker.
  final int? art;

  /// The quoted message was a song.
  final bool? music;
}

/// One message in the conversation.
class Message {
  const Message({
    required this.id,
    required this.fromMe,
    required this.at,
    required this.body,
    this.delivery = Delivery.seen,
    this.reply,
    this.reactions = const [],
    this.deliveredAt,
    this.seenAt,
  });

  final String id;
  final bool fromMe;
  final DateTime at;
  final Body body;
  final Delivery delivery;
  final Quote? reply;
  final List<Reaction> reactions;
  final DateTime? deliveredAt;
  final DateTime? seenAt;

  /// Moments, calls and system notes sit in the middle, not in a bubble.
  bool get centred =>
      body is MomentBody || body is CallBody || body is SystemBody;

  Message copyWith({
    Delivery? delivery,
    List<Reaction>? reactions,
    Body? body,
  }) => Message(
    id: id,
    fromMe: fromMe,
    at: at,
    body: body ?? this.body,
    delivery: delivery ?? this.delivery,
    reply: reply,
    reactions: reactions ?? this.reactions,
    deliveredAt: deliveredAt,
    seenAt: seenAt,
  );

  /// A quote of this message for a reply.
  Quote quote() => Quote(
    fromMe: fromMe,
    text: switch (body) {
      TextBody(:final text) => text,
      PhotoBody(:final photos) => photos.length > 1 ? 'Photos' : 'Photo',
      VideoBody() => 'Video',
      RoundVideoBody() => 'Round video',
      VoiceBody() => 'Voice note',
      MusicBody(:final song) => '${song.title} · ${song.artist}',
      MemeBody(:final meme) => meme.tag == 'GIF' ? 'GIF' : 'Meme',
      StickerBody() => 'Sticker',
      MomentBody(:final moment) => moment.label,
      CallBody(:final video) => video ? 'Video call' : 'Voice call',
      SystemBody(:final text) => text,
    },
    art: switch (body) {
      PhotoBody(:final photos) => photos.first.art,
      StickerBody(:final sticker) => sticker.art,
      _ => null,
    },
    music: body is MusicBody ? true : null,
  );
}

/// The papers a doodle can be drawn on (C30).
enum Paper { plain, dotted, lined, wallpaper }

/// A shared doodle board (C29, C31).
class Doodle {
  const Doodle({
    required this.id,
    required this.name,
    required this.strokes,
    required this.editedBy,
    required this.editedAt,
    this.paper = Paper.dotted,
    this.partnerHere = false,
  });

  final String id;
  final String name;
  final List<Stroke> strokes;
  final String editedBy;
  final DateTime editedAt;
  final Paper paper;
  final bool partnerHere;

  Doodle copyWith({
    String? name,
    List<Stroke>? strokes,
    String? editedBy,
    DateTime? editedAt,
  }) => Doodle(
    id: id,
    name: name ?? this.name,
    strokes: strokes ?? this.strokes,
    editedBy: editedBy ?? this.editedBy,
    editedAt: editedAt ?? this.editedAt,
    paper: paper,
    partnerHere: partnerHere,
  );
}

/// What one kind of media uses on this phone (C38).
class StorageUse {
  const StorageUse(this.label, this.bytes);
  final String label;
  final int bytes;
}

/// How long the app waits in the background before locking (C36).
enum LockAfter {
  now('Immediately', Duration.zero),
  s30('30s', Duration(seconds: 30)),
  m1('1 min', Duration(minutes: 1)),
  m5('5 min', Duration(minutes: 5));

  const LockAfter(this.label, this.duration);
  final String label;
  final Duration duration;
}

/// When media download by themselves (C36).
enum AutoDownload {
  always('Always'),
  wifi('On Wi-Fi'),
  never('Never');

  const AutoDownload(this.label);
  final String label;
}

/// Local, per-phone settings (C36, C39).
class AppSettings {
  const AppSettings({
    this.enterSends = false,
    this.autoplayGifs = true,
    this.autoDownload = AutoDownload.wifi,
    this.showPreview = false,
    this.appLock = true,
    this.lockAfter = LockAfter.s30,
    this.hideInRecents = true,
  });

  final bool enterSends;
  final bool autoplayGifs;
  final AutoDownload autoDownload;
  final bool showPreview;
  final bool appLock;
  final LockAfter lockAfter;
  final bool hideInRecents;

  AppSettings copyWith({
    bool? enterSends,
    bool? autoplayGifs,
    AutoDownload? autoDownload,
    bool? showPreview,
    bool? appLock,
    LockAfter? lockAfter,
    bool? hideInRecents,
  }) => AppSettings(
    enterSends: enterSends ?? this.enterSends,
    autoplayGifs: autoplayGifs ?? this.autoplayGifs,
    autoDownload: autoDownload ?? this.autoDownload,
    showPreview: showPreview ?? this.showPreview,
    appLock: appLock ?? this.appLock,
    lockAfter: lockAfter ?? this.lockAfter,
    hideInRecents: hideInRecents ?? this.hideInRecents,
  );
}
