import 'dart:math' as math;
import 'dart:ui' show Offset;

import '../core/theme/v_colors.dart';
import '../data/models.dart';

/// Every fake dataset in Moose, as listed in `mockdata.md`. The values match
/// the design canvas, so screens can be compared side by side. Times are
/// anchored to [mockNow], the moment the data is built.
abstract final class MockData {
  static DateTime mockNow = DateTime.now();

  /// Today at [h]:[m].
  static DateTime today(int h, int m) =>
      DateTime(mockNow.year, mockNow.month, mockNow.day, h, m);

  /// When you last read the chat: what came after is unread (C15).
  static DateTime get lastRead => today(17, 0);

  /// Photos saved as wallpapers in the theme sheet (C22).
  static const themePhotos = ['mock:0', 'mock:2'];

  /// The phone's gallery (C18): photos, with a few videos.
  static List<Media> gallery() => [
    for (var i = 0; i < 18; i++)
      Media(
        id: 'g$i',
        art: i,
        aspect: const [1.0, 1.5, 0.75][i % 3],
        duration: i == 2
            ? const Duration(seconds: 24)
            : i == 9
            ? const Duration(minutes: 1, seconds: 2)
            : null,
      ),
  ];

  static const sapan = Person(id: 'me', name: 'Sapan');
  static const aatika = Person(id: 'partner', name: 'Aatika');

  /// The decoy chat's made-up person (C14).
  static const decoyName = 'Neha';

  /// The PINs that open Moose and the decoy chat, until real ones are set.
  static const pin = '1402';
  static const decoyPin = '2580';

  static const securityCode = [
    '41073', '93225', '68120', '57734', //
    '20918', '33461', '87102', '46659',
    '12890', '75341', '09826', '61470',
  ];

  /// What Aatika's new phone shows during a re-pair (C9, C10).
  static const newSecurityCode = [
    '88214', '30957', '14402', '69183', //
    '27560', '51348', '93017', '40625',
    '78891', '05233', '64719', '22806',
  ];

  /// The invite code on Create pair (C5).
  static const inviteCode = 'K7Q2MX';

  static Pairing pairing() => Pairing(
    me: sapan,
    partner: aatika,
    since: DateTime(2025, 2, 14),
    securityCode: securityCode,
    lastSeen: today(21, 4),
  );

  // Songs (C27, C28).
  static const sienna = Song(
    videoId: 'sienna-the-marias',
    title: 'Sienna',
    artist: 'The Marías',
    length: Duration(minutes: 2, seconds: 57),
    art: 5,
  );

  static const songs = [
    sienna,
    Song(
      videoId: 'sienna-sped-up',
      title: 'Sienna (sped up)',
      artist: 'The Marías',
      length: Duration(minutes: 2, seconds: 41),
      art: 2,
    ),
    Song(
      videoId: 'sienna-live',
      title: 'Sienna · live session',
      artist: 'The Marías',
      length: Duration(minutes: 3, seconds: 37),
      art: 1,
    ),
    Song(
      videoId: 'sienna-slowed',
      title: 'Sienna (slowed + reverb)',
      artist: 'Lofi Covers',
      length: Duration(minutes: 3, seconds: 41),
      art: 3,
    ),
    Song(
      videoId: 'sienna-piano',
      title: 'Sienna · piano cover',
      artist: 'Piano Dreamers',
      length: Duration(minutes: 2, seconds: 48),
      art: 4,
    ),
    Song(
      videoId: 'yellow',
      title: 'Yellow',
      artist: 'Coldplay',
      length: Duration(minutes: 4, seconds: 26),
      art: 0,
    ),
  ];

  // Memes (C26).
  static List<Meme> memes() => [
    for (var i = 0; i < 16; i++)
      Meme(
        id: 'meme-$i',
        source: i % 5 == 4 ? MemeSource.reddit : MemeSource.klipy,
        kind: switch (i % 6) {
          2 => MemeKind.sticker,
          4 => MemeKind.meme,
          5 => MemeKind.clip,
          _ => MemeKind.gif,
        },
        art: i,
        aspect: const [1.1, 1.5, 0.9, 1.3, 0.8, 1.2][i % 6],
        title: const [
          'sleepy cat',
          'cat stretching',
          'cat in a box',
          'good morning',
          'wholesome',
          'dance',
        ][i % 6],
        subreddit: i % 5 == 4 ? 'wholesomememes' : null,
      ),
  ];

  // Doodle strokes. Boards are drawn in a 390 × 700 space; stickers in 0–1.

  /// A heart outline around [c], [r] wide.
  static List<Offset> heart(Offset c, double r) => [
    for (var t = 0.0; t <= 2 * math.pi + 0.01; t += 0.08)
      c +
          Offset(
            r * math.pow(math.sin(t), 3) / 1.0,
            -r *
                (13 * math.cos(t) -
                    5 * math.cos(2 * t) -
                    2 * math.cos(3 * t) -
                    math.cos(4 * t)) /
                16,
          ),
  ];

  /// A wave from [from], [length] long.
  static List<Offset> wave(Offset from, double length, {double height = 10}) =>
      [
        for (var x = 0.0; x <= length; x += 4)
          from + Offset(x, math.sin(x / length * 3 * math.pi) * height),
      ];

  static List<Offset> line(List<Offset> points) => points;

  static List<Stroke> sundayPlans() => [
    Stroke(
      tool: PenTool.highlighter,
      argb: 0xFFFFE066,
      size: 22,
      opacity: 0.45,
      points: wave(const Offset(70, 160), 260, height: 12),
    ),
    Stroke(
      tool: PenTool.fineLiner,
      argb: VPenColors.presets[1],
      size: 3,
      points: wave(const Offset(64, 150), 250, height: 14),
    ),
    Stroke(
      tool: PenTool.brush,
      argb: 0xFFFF5C7A,
      size: 7,
      points: heart(const Offset(195, 300), 96),
    ),
    Stroke(
      tool: PenTool.marker,
      argb: 0xFF5BC0EB,
      size: 4,
      points: wave(const Offset(80, 470), 240),
    ),
    Stroke(
      tool: PenTool.neon,
      argb: 0xFF9DB2FF,
      size: 4,
      points: line(const [
        Offset(120, 540),
        Offset(138, 504),
        Offset(156, 540),
        Offset(165, 520),
        Offset(175, 504),
        Offset(175, 540),
        Offset(197, 540),
      ]),
    ),
    const Stroke(
      tool: PenTool.pencil,
      argb: 0xFF3FA34D,
      size: 4,
      by: 'partner',
      points: [Offset(300, 560), Offset(312, 552), Offset(326, 534)],
    ),
  ];

  static List<Doodle> doodles() => [
    Doodle(
      id: 'sunday',
      name: 'Sunday plans',
      strokes: sundayPlans(),
      editedBy: 'Aatika',
      editedAt: mockNow,
      partnerHere: true,
    ),
    Doodle(
      id: 'flat',
      name: 'Our flat',
      strokes: const [
        Stroke(
          tool: PenTool.marker,
          argb: 0xFFFFC15E,
          size: 6,
          points: [
            Offset(80, 520),
            Offset(80, 320),
            Offset(195, 220),
            Offset(310, 320),
            Offset(310, 520),
            Offset(80, 520),
          ],
        ),
        Stroke(
          tool: PenTool.fineLiner,
          argb: 0xFF3FA34D,
          size: 4,
          points: [Offset(40, 560), Offset(350, 560)],
        ),
      ],
      editedBy: 'You',
      editedAt: mockNow.subtract(const Duration(hours: 2)),
      paper: Paper.plain,
    ),
    Doodle(
      id: 'ttt',
      name: 'Tic tac toe',
      strokes: const [
        Stroke(
          tool: PenTool.fineLiner,
          argb: 0xFF9DB2FF,
          size: 5,
          points: [Offset(150, 180), Offset(150, 520)],
        ),
        Stroke(
          tool: PenTool.fineLiner,
          argb: 0xFF9DB2FF,
          size: 5,
          points: [Offset(240, 180), Offset(240, 520)],
        ),
        Stroke(
          tool: PenTool.fineLiner,
          argb: 0xFF9DB2FF,
          size: 5,
          points: [Offset(60, 290), Offset(330, 290)],
        ),
        Stroke(
          tool: PenTool.fineLiner,
          argb: 0xFF9DB2FF,
          size: 5,
          points: [Offset(60, 410), Offset(330, 410)],
        ),
        Stroke(
          tool: PenTool.marker,
          argb: 0xFFFF5C7A,
          size: 6,
          points: [Offset(80, 200), Offset(130, 270)],
        ),
        Stroke(
          tool: PenTool.marker,
          argb: 0xFFFF5C7A,
          size: 6,
          points: [Offset(130, 200), Offset(80, 270)],
        ),
      ],
      editedBy: 'Aatika',
      editedAt: mockNow.subtract(const Duration(days: 1)),
    ),
    Doodle(
      id: 'moose',
      name: 'Moose!',
      strokes: [
        Stroke(
          tool: PenTool.brush,
          argb: 0xFFB57EDC,
          size: 6,
          points: wave(const Offset(90, 420), 210, height: 40),
        ),
        const Stroke(
          tool: PenTool.brush,
          argb: 0xFFB57EDC,
          size: 6,
          points: [Offset(140, 330), Offset(100, 230), Offset(140, 260)],
        ),
        const Stroke(
          tool: PenTool.brush,
          argb: 0xFFB57EDC,
          size: 6,
          points: [Offset(250, 330), Offset(290, 230), Offset(250, 260)],
        ),
      ],
      editedBy: 'You',
      editedAt: mockNow.subtract(const Duration(days: 4)),
      paper: Paper.lined,
    ),
  ];

  // Stickers (S1–S6). Doodle stickers live in a 0–1 box.
  static final _heartSticker = [
    Stroke(
      tool: PenTool.brush,
      argb: 0xFFFF5C7A,
      size: 0.05,
      points: heart(const Offset(0.5, 0.5), 0.36),
    ),
  ];

  static final _waveSticker = [
    Stroke(
      tool: PenTool.marker,
      argb: 0xFF5BC0EB,
      size: 0.05,
      points: [
        for (var x = 0.1; x <= 0.9; x += 0.02)
          Offset(x, 0.5 + math.sin(x * 3 * math.pi) * 0.14),
      ],
    ),
  ];

  static List<StickerPack> stickerPacks() {
    Sticker photo(String id, int art, int shape, {bool fav = false}) =>
        Sticker.photo(id: id, art: art, shape: shape, favourite: fav);
    return [
      StickerPack(
        id: 'ours',
        name: 'Ours',
        note: '24 · made by you two',
        stickers: [
          photo('s-us', 7, 0, fav: true),
          photo('s-lake', 0, 1, fav: true),
          photo('s-chai', 3, 2),
          photo('s-night', 9, 3, fav: true),
          photo('s-6am', 5, 1),
        ],
      ),
      StickerPack(
        id: 'doodles',
        name: 'Moose doodles',
        note: '12 · from doodles',
        stickers: [
          Sticker.doodle(
            id: 's-heart',
            strokes: _heartSticker,
            favourite: true,
          ),
          Sticker.doodle(id: 's-wave', strokes: _waveSticker),
        ],
      ),
      const StickerPack(
        id: 'cats',
        name: 'Cat chaos',
        note: '8 · from Aatika',
        stickers: [
          Sticker.photo(
            id: 's-cat',
            art: 6,
            shape: 1,
            favourite: true,
            from: 'partner',
          ),
          Sticker.photo(id: 's-cat2', art: 8, shape: 2, from: 'partner'),
          Sticker.photo(id: 's-cat3', art: 4, shape: 3, from: 'partner'),
        ],
      ),
    ];
  }

  static const storage = [
    StorageUse('Photos', 820 * 1000 * 1000),
    StorageUse('Videos', 410 * 1000 * 1000),
    StorageUse('Round videos', 96 * 1000 * 1000),
    StorageUse('Voice notes', 48 * 1000 * 1000),
    StorageUse('Doodles', 12 * 1000 * 1000),
    StorageUse('Wallpapers', 9 * 1000 * 1000),
  ];

  /// Meme and song previews (C36 › Clear cache).
  static const cacheBytes = 86 * 1000 * 1000;

  /// A voice note's waveform.
  static const voiceWave = [
    .2, .4, .65, .35, .8, .5, .3, .75, 1.0, .6, .4, .2, .5, .8, //
    .65, .45, .3, .6, .9, .75, .45, .2, .35, .65, .5, .3, .45, .2,
  ];

  /// The conversation (C15 and the canvas's other chat boards).
  static List<Message> messages() {
    var n = 0;
    String id() => 'm${n++}';
    Message mine(
      int h,
      int m,
      Body body, {
      Delivery d = Delivery.seen,
      Quote? reply,
      List<Reaction> r = const [],
    }) => Message(
      id: id(),
      fromMe: true,
      at: today(h, m),
      body: body,
      delivery: d,
      reply: reply,
      reactions: r,
      deliveredAt: today(h, m),
      seenAt: d == Delivery.seen ? today(h, m + 1) : null,
    );
    Message theirs(
      int h,
      int m,
      Body body, {
      Quote? reply,
      List<Reaction> r = const [],
    }) => Message(
      id: id(),
      fromMe: false,
      at: today(h, m),
      body: body,
      reply: reply,
      reactions: r,
    );
    final yesterday = mockNow.subtract(const Duration(days: 1));
    DateTime y(int h, int m) =>
        DateTime(yesterday.year, yesterday.month, yesterday.day, h, m);
    return [
      Message(
        id: id(),
        fromMe: false,
        at: y(23, 41),
        body: const TextBody('are you up?'),
      ),
      Message(
        id: id(),
        fromMe: true,
        at: y(23, 42),
        body: const TextBody(
          "yes!! couldn't sleep, kept thinking about the trip. did you book "
          'the train or should i',
        ),
      ),
      Message(
        id: id(),
        fromMe: true,
        at: y(23, 42),
        body: const TextBody('🥺🫶'),
      ),
      Message(
        id: id(),
        fromMe: false,
        at: y(23, 44),
        body: const TextBody(
          'look maps.app.goo.gl/k8Qd the café with the swing',
        ),
      ),
      Message(
        id: id(),
        fromMe: true,
        at: y(23, 46),
        body: const TextBody("let's go saturday"),
        reply: const Quote(fromMe: false, text: 'the café with the swing'),
      ),
      Message(
        id: id(),
        fromMe: false,
        at: y(23, 50),
        body: const TextBody('i miss you already'),
        reactions: const [Reaction('❤️', mine: true), Reaction('🥺', count: 2)],
      ),
      Message(
        id: id(),
        fromMe: false,
        at: y(23, 52),
        body: const VoiceBody(length: Duration(seconds: 18), wave: voiceWave),
      ),
      Message(
        id: id(),
        fromMe: true,
        at: y(23, 58),
        body: const RoundVideoBody(
          Media(id: 'rv1', art: 2, duration: Duration(seconds: 12)),
        ),
      ),
      theirs(8, 12, const TextBody('good morning sapan ☀️')),
      mine(8, 14, const TextBody('morning!! did you sleep at all')),
      theirs(9, 30, const PhotoBody([Media(id: 'p1', art: 0, aspect: 1.5)])),
      mine(
        9,
        34,
        const PhotoBody([
          Media(id: 'p2', art: 1),
          Media(id: 'p3', art: 0),
          Media(id: 'p4', art: 2),
          Media(id: 'p5', art: 3),
          Media(id: 'p6', art: 1),
          Media(id: 'p7', art: 4),
          Media(id: 'p8', art: 5),
        ]),
        reply: const Quote(fromMe: false, text: 'Photo', art: 0),
      ),
      mine(
        10,
        2,
        const VideoBody(
          Media(id: 'v1', art: 1, aspect: 1.6, duration: Duration(seconds: 24)),
        ),
      ),
      mine(11, 2, const MusicBody(sienna, start: Duration(seconds: 41))),
      theirs(
        11,
        5,
        const TextBody('stuck in my head now'),
        reply: const Quote(
          fromMe: true,
          text: 'Sienna · The Marías',
          music: true,
        ),
      ),
      theirs(13, 2, const MomentBody(VMoment.poke)),
      Message(
        id: id(),
        fromMe: false,
        at: today(13, 30),
        body: const SystemBody(
          SystemKind.theme,
          'Aatika changed the theme to Night',
        ),
      ),
      theirs(
        17,
        40,
        const TextBody("come home early today? i'm making rajma"),
        r: const [Reaction('❤️', mine: true)],
      ),
      theirs(
        17,
        41,
        const MemeBody(
          Meme(
            id: 'gif1',
            source: MemeSource.klipy,
            kind: MemeKind.gif,
            art: 1,
            aspect: 1.36,
          ),
        ),
      ),
      mine(17, 42, const MomentBody(VMoment.hug)),
      theirs(
        17,
        44,
        const StickerBody(
          Sticker.photo(id: 's-cat', art: 6, shape: 1, from: 'partner'),
        ),
      ),
      mine(18, 31, const TextBody('leaving office now'), d: Delivery.delivered),
      Message(
        id: id(),
        fromMe: false,
        at: today(18, 35),
        body: const PhotoBody([
          Media(
            id: 'p9',
            art: 2,
            aspect: 1.45,
            transfer: Transfer.cloudDownloading,
            progress: 0.46,
          ),
        ]),
      ),
      mine(
        18,
        40,
        const TextBody('grabbing the mangoes on the way'),
        d: Delivery.sent,
      ),
      mine(18, 40, const TextBody('🥭🥭'), d: Delivery.pending),
      mine(
        20,
        31,
        const CallBody(
          video: false,
          outcome: CallOutcome.answered,
          length: Duration(minutes: 12),
        ),
      ),
      theirs(20, 44, const TextBody('that was the best call omg')),
      theirs(22, 45, const CallBody(video: true, outcome: CallOutcome.missed)),
      mine(23, 2, const CallBody(video: false, outcome: CallOutcome.noAnswer)),
      mine(23, 5, const TextBody("call me when you're up ☀️")),
    ];
  }
}
