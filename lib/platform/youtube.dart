import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import 'net.dart';
import 'quality.dart';

/// YouTube for song clips (C27, C28): search, and a playable audio stream
/// for a video, the way Idris finds one (NewPipe first, then the Dart
/// extractor's clients). Only the video id and the 15 s window travel in a
/// message; each phone finds the stream itself.
const _newPipe = MethodChannel('moose/youtube');

YoutubeExplode _yt() =>
    YoutubeExplode(httpClient: YoutubeHttpClient(youtubeClient()));

/// A search result.
class YtSong {
  const YtSong({
    required this.id,
    required this.title,
    required this.channel,
    required this.length,
  });

  final String id;
  final String title;
  final String channel;
  final Duration length;
}

/// Music videos for [query], shortest-first noise (shorts, live) left out.
Future<List<YtSong>> searchSongs(String query) async {
  final yt = _yt();
  try {
    final results = await yt.search.search(query);
    return [
      for (final v in results)
        if (!v.isLive &&
            (v.duration ?? Duration.zero) > const Duration(seconds: 45))
          YtSong(
            id: v.id.value,
            title: v.title,
            channel: v.author.replaceAll(RegExp(r' - Topic$'), ''),
            length: v.duration ?? Duration.zero,
          ),
    ];
  } finally {
    yt.close();
  }
}

/// A playable audio stream for one video.
class ResolvedAudio {
  const ResolvedAudio({required this.url, required this.mime});
  final Uri url;
  final String mime;
}

typedef AudioResolver = Future<ResolvedAudio> Function(
  String videoId,
  AudioQuality quality,
);

AudioResolver _explode(YoutubeApiClient client) => (id, quality) async {
  final yt = _yt();
  try {
    final manifest = await yt.videos.streamsClient.getManifest(
      VideoId(id),
      ytClients: [client],
    );
    final picked = pickAudio([
      for (final s in manifest.audioOnly)
        if (s.fragments.isEmpty)
          AudioCandidate(
            kbps: s.bitrate.kiloBitsPerSecond,
            m4a: s.container == StreamContainer.mp4,
            value: s,
          ),
    ], quality);
    if (picked == null) throw StateError('No audio-only stream');
    return ResolvedAudio(
      url: picked.url,
      mime: picked.container == StreamContainer.mp4
          ? 'audio/mp4'
          : 'audio/webm',
    );
  } finally {
    yt.close();
  }
};

Future<ResolvedAudio> _newPipeAudio(String id, AudioQuality quality) async {
  final m = await _newPipe.invokeMapMethod<String, Object?>('audio', {
    'link': 'https://www.youtube.com/watch?v=$id',
    'quality': quality.name,
  });
  final url = m?['url'] as String?;
  if (url == null) throw StateError('NewPipe found no audio');
  return ResolvedAudio(
    url: Uri.parse(url),
    mime: (m?['mime'] as String?) ?? 'audio/mp4',
  );
}

/// The ways a stream is found, tried in order (see Idris's youtube.dart:
/// NewPipe's links stay whole; the Dart clients' links can stop at 1 MB).
final List<AudioResolver> audioResolvers = [
  _newPipeAudio,
  _explode(YoutubeApiClient.androidVr),
  _explode(YoutubeApiClient.tv),
  _explode(YoutubeApiClient.safari),
];

/// A stream for [videoId], trying each way in turn.
Future<ResolvedAudio> resolveAudio(
  String videoId, {
  AudioQuality quality = AudioQuality.medium,
}) async {
  Object? last;
  for (final way in audioResolvers) {
    try {
      return await way(videoId, quality);
    } on Object catch (e) {
      debugPrint('YouTube: a way failed for $videoId: $e');
      last = e;
    }
  }
  throw StateError('No way to stream $videoId: $last');
}

/// The video's thumbnail (320×180, no letterbox bars).
String thumbnailUrl(String videoId) =>
    'https://i.ytimg.com/vi/$videoId/mqdefault.jpg';
