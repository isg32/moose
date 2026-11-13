import 'dart:convert';

import 'package:http/http.dart' as http;

import '../data/models.dart';
import '../data/repositories.dart';

/// Memes from the web (C26): Reddit through meme-api.com (no key), and
/// GIFs, stickers, memes and clips from KLIPY when the build has a key
/// (`MOOSE_KLIPY_KEY` in env.json). A sent meme carries its link, and the
/// other phone loads it from there.
class WebMemes implements MemeRepository {
  WebMemes({http.Client? client}) : _http = client ?? http.Client();

  final http.Client _http;

  static const _klipyKey = String.fromEnvironment('MOOSE_KLIPY_KEY');
  static bool get hasKlipy => _klipyKey.isNotEmpty;

  @override
  Future<List<Meme>> search(
    String query,
    MemeSource source,
    MemeKind? kind,
  ) async => switch (source) {
    MemeSource.reddit => _reddit(query, kind),
    MemeSource.klipy => hasKlipy ? _klipy(query, kind) : const [],
  };

  /// Where Reddit memes and GIFs come from.
  static const _memeSubs = ['memes', 'wholesomememes', 'me_irl', 'dankmemes'];
  static const _gifSubs = ['reactiongifs', 'HighQualityGifs', 'gifs'];

  /// Reddit through meme-api.com, which fetches a subreddit's recent image
  /// posts but can't search. So a search tries the words as subreddits
  /// ("cat" → r/catmemes, r/cat) and filters the titles of the big ones'
  /// recent posts; the empty search is what's popular.
  Future<List<Meme>> _reddit(String query, MemeKind? kind) async {
    final gifs = kind == MemeKind.gif || kind == MemeKind.clip;
    final words = [
      for (final w in query.toLowerCase().split(RegExp(r'[^a-z0-9]+')))
        if (w.length > 1) w,
    ];
    final topical = <String>[
      for (final w in words.take(3)) ...[
        if (gifs) '${w}gifs' else '${w}memes',
        w,
      ],
    ];
    final general = gifs ? _gifSubs : _memeSubs;
    final batches = await Future.wait([
      for (final sub in topical) _gimme(sub, 25),
      for (final sub in general) _gimme(sub, words.isEmpty ? 15 : 50),
    ]);
    final seen = <String>{};
    final out = <Meme>[];
    void take(List<Meme> ms, {required bool filter}) {
      for (final m in ms) {
        if (gifs && m.kind != MemeKind.gif) continue;
        if (!gifs && kind == MemeKind.meme && m.kind == MemeKind.gif) continue;
        if (filter &&
            words.isNotEmpty &&
            !words.any((w) => m.title.toLowerCase().contains(w))) {
          continue;
        }
        if (seen.add(m.url ?? m.id)) out.add(m);
      }
    }

    for (var i = 0; i < batches.length; i++) {
      take(batches[i], filter: i >= topical.length);
    }
    return out;
  }

  Future<List<Meme>> _gimme(String sub, int count) async {
    try {
      final res = await _http
          .get(Uri.parse('https://meme-api.com/gimme/$sub/$count'))
          .timeout(const Duration(seconds: 12));
      if (res.statusCode != 200) return const [];
      final memes = ((jsonDecode(res.body) as Map)['memes'] as List?) ?? [];
      return [
        for (final raw in memes)
          ?_redditMeme((raw as Map).cast<String, Object?>()),
      ];
    } on Object {
      return const []; // one subreddit down doesn't empty the picker
    }
  }

  static Meme? _redditMeme(Map<String, Object?> m) {
    if (m['nsfw'] == true || m['spoiler'] == true) return null;
    final url = m['url'] as String?;
    if (url == null || !RegExp(r'\.(png|jpe?g|gif|webp)$').hasMatch(url)) {
      return null;
    }
    return Meme(
      id: (m['postLink'] as String?) ?? url,
      source: MemeSource.reddit,
      kind: url.endsWith('.gif') ? MemeKind.gif : MemeKind.meme,
      art: url.length % 10,
      aspect: 1,
      title: (m['title'] as String?) ?? '',
      subreddit: m['subreddit'] as String?,
      url: url,
      // Reddit's preview links expire (404); the full picture lasts.
      thumb: url,
    );
  }

  Future<List<Meme>> _klipy(String query, MemeKind? kind) async {
    final type = switch (kind) {
      MemeKind.sticker => 'stickers',
      MemeKind.clip => 'clips',
      MemeKind.meme => 'static-memes',
      _ => 'gifs',
    };
    final q = query.trim();
    final uri = Uri.parse(
      'https://api.klipy.com/api/v1/$_klipyKey/$type/'
      '${q.isEmpty ? 'trending' : 'search'}',
    ).replace(queryParameters: {'per_page': '24', if (q.isNotEmpty) 'q': q});
    try {
      final res = await _http.get(uri).timeout(const Duration(seconds: 12));
      if (res.statusCode != 200) return const [];
      final data = ((jsonDecode(res.body) as Map)['data'] as Map?)?['data'];
      return [
        for (final raw in (data as List?) ?? const [])
          ?_klipyMeme((raw as Map).cast<String, Object?>(), kind),
      ];
    } on Object {
      return const [];
    }
  }

  static Meme? _klipyMeme(Map<String, Object?> j, MemeKind? kind) {
    final file = (j['file'] as Map?)?.cast<String, Object?>();
    if (file == null) return null;
    Map<String, Object?>? size(String s) =>
        (file[s] as Map?)?.cast<String, Object?>();
    Map<String, Object?>? pick(Map<String, Object?>? s) =>
        ((s?['gif'] ?? s?['webp'] ?? s?['png'] ?? s?['jpg']) as Map?)
            ?.cast<String, Object?>();
    final full = pick(size('md') ?? size('hd'));
    final small = pick(size('sm') ?? size('xs'));
    final url = full?['url'] as String?;
    if (url == null) return null;
    final w = (full?['width'] as num?)?.toDouble() ?? 1;
    final h = (full?['height'] as num?)?.toDouble() ?? 1;
    return Meme(
      id: '${j['id'] ?? j['slug'] ?? url}',
      source: MemeSource.klipy,
      kind: kind ?? MemeKind.gif,
      art: url.length % 10,
      aspect: h == 0 ? 1 : w / h,
      title: (j['title'] as String?) ?? '',
      url: url,
      thumb: small?['url'] as String?,
    );
  }
}
