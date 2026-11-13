import 'dart:async';

import 'package:just_audio/just_audio.dart';

import '../data/models.dart';
import '../data/providers.dart';
import '../data/repositories.dart';
import '../platform/youtube.dart';

/// Songs from YouTube (C27, C28): search, and 15 s clips played with
/// just_audio from the stream each phone finds for itself.
class YouTubeSongs implements MusicRepository, SongPlayer {
  final _player = AudioPlayer();
  final _streams = <String, Uri>{};
  StreamSubscription<PlayerState>? _state;
  StreamSubscription<Duration>? _position;
  void Function()? _onDone;

  @override
  Future<List<Song>> search(String query) async {
    if (query.trim().isEmpty) return const [];
    final found = await searchSongs(query.trim());
    return [
      for (final s in found.take(20))
        Song(
          videoId: s.id,
          title: s.title,
          artist: s.channel,
          length: s.length,
          art: s.id.codeUnits.fold(0, (a, b) => a + b) % 10,
          thumb: thumbnailUrl(s.id),
        ),
    ];
  }

  @override
  Future<void> play(
    Song song,
    Duration start, {
    void Function(Duration elapsed)? onTick,
    void Function()? onDone,
  }) async {
    await stop();
    _onDone = onDone;
    try {
      final url = _streams[song.videoId] ??= (await resolveAudio(song.videoId))
          .url;
      await _state?.cancel();
      await _position?.cancel();
      _state = _player.playerStateStream.listen((s) {
        if (s.processingState == ProcessingState.completed) _done();
      });
      // Load the whole stream and seek, rather than a clipping source:
      // some YouTube streams ignore the clip's start and play from 0:00.
      await _player.setAudioSource(
        AudioSource.uri(url),
        initialPosition: start,
      );
      if ((_player.position - start).abs() > const Duration(seconds: 1)) {
        await _player.seek(start);
      }
      final end = start + const Duration(seconds: 15);
      _position = _player.positionStream.listen((p) {
        if (p >= end) {
          unawaited(stop());
        } else if (_player.playing &&
            _player.processingState == ProcessingState.ready) {
          // Sound is coming: past loading.
          onTick?.call(p - start < Duration.zero ? Duration.zero : p - start);
        }
      });
      unawaited(_player.play());
    } on Object {
      _streams.remove(song.videoId); // maybe expired: find it afresh next time
      _done();
    }
  }

  void _done() {
    final f = _onDone;
    _onDone = null;
    f?.call();
  }

  /// A clip is playing (tests).
  bool get playing => _player.playing;

  @override
  Future<void> stop() async {
    await _position?.cancel();
    _position = null;
    await _player.stop();
    _done();
  }
}
