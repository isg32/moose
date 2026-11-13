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

  /// Where Reddit memes come from when nothing is typed.
  static const subreddits = ['wholesomememes', 'memes', 'aww', 'catmemes'];

  @override
  Future<List<Meme>> search(
    String query,
    MemeSource source,
    MemeKind? kind,
  ) async => switch (source) {
    MemeSource.reddit => _reddit(query),
    MemeSource.klipy => hasKlipy ? _klipy(query, kind) : const [],
  };

  Future<List<Meme>> _reddit(String query) async {
    final q = query.trim().toLowerCase();
    // A word that names a subreddit opens it; anything else filters the
    // usual ones by title.
    final subs = q.isNotEmpty && !q.contains(' ')
        ? [q, ...subreddits]
        : subreddits;
    final out = <Meme>[];
    for (final sub in subs.take(q.isEmpty ? 2 : 3)) {
      try {
        final res = await _http
            .get(Uri.parse('https://meme-api.com/gimme/$sub/25'))
            .timeout(const Duration(seconds: 12));
        if (res.statusCode != 200) continue;
        final memes = ((jsonDecode(res.body) as Map)['memes'] as List?) ?? [];
        for (final raw in memes) {
          final m = (raw as Map).cast<String, Object?>();
          if (m['nsfw'] == true || m['spoiler'] == true) continue;
          final url = m['url'] as String?;
          if (url == null ||
              !RegExp(r'\.(png|jpe?g|gif|webp)$').hasMatch(url)) {
            continue;
          }
          final title = (m['title'] as String?) ?? '';
          if (q.isNotEmpty && sub != q && !title.toLowerCase().contains(q)) {
            continue;
          }
          final previews = (m['preview'] as List?)?.cast<String>() ?? const [];
          out.add(
            Meme(
              id: (m['postLink'] as String?) ?? url,
              source: MemeSource.reddit,
              kind: url.endsWith('.gif') ? MemeKind.gif : MemeKind.meme,
              art: url.length % 10,
              aspect: 1,
              title: title,
              subreddit: m['subreddit'] as String?,
              url: url,
              thumb: previews.length > 2 ? previews[2] : previews.lastOrNull,
            ),
          );
        }
      } on Object {
        // One subreddit down doesn't empty the picker.
      }
    }
    return out;
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
