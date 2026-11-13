import 'dart:async';
import 'dart:io';

import 'package:just_audio/just_audio.dart';
import 'package:record/record.dart';

import '../data/providers.dart';
import 'neon_backend.dart';

/// Voice notes on the phone: AAC recordings in Moose's private storage,
/// played back with just_audio.
class PhoneVoice implements Voice {
  PhoneVoice(this.dir);

  final Directory dir;
  final _recorder = AudioRecorder();
  AudioPlayer? _player;
  StreamSubscription<PlayerState>? _state;
  void Function()? _onDone;

  @override
  Future<bool> start() async {
    if (!await _recorder.hasPermission()) return false;
    await dir.create(recursive: true);
    await _recorder.start(
      const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 64000),
      path: '${dir.path}/${NeonChatRepository.uuid()}.m4a',
    );
    return true;
  }

  // dBFS: about -60 is silence and 0 the loudest; mapped onto 0–1.
  @override
  Stream<double> get levels => _recorder
      .onAmplitudeChanged(const Duration(milliseconds: 100))
      .map((a) => ((a.current + 60) / 60).clamp(0.0, 1.0));

  @override
  Future<String?> stop() => _recorder.stop();

  @override
  Future<void> cancel() => _recorder.cancel();

  @override
  Future<void> play(String path, {void Function()? onDone}) async {
    await stopPlaying();
    final player = _player ??= AudioPlayer();
    _onDone = onDone;
    await _state?.cancel();
    _state = player.playerStateStream.listen((s) {
      if (s.processingState == ProcessingState.completed) _done();
    });
    await player.setFilePath(path);
    unawaited(player.play());
  }

  void _done() {
    final f = _onDone;
    _onDone = null;
    f?.call();
  }

  @override
  Future<void> stopPlaying() async {
    await _player?.stop();
    _done();
  }
}
