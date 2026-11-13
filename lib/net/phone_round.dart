import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/widgets.dart';

import '../data/providers.dart';
import 'neon_backend.dart';

/// Round video notes (C16, B6) from the front camera.
class PhoneRound implements RoundCamera {
  PhoneRound(this.dir);

  final Directory dir;
  CameraController? _c;

  /// Opening takes a moment (a couple of seconds on some phones); a hold
  /// that ends sooner waits for it, so the recording isn't lost.
  Future<Widget?>? _opening;

  @override
  Future<Widget?> open() => _opening = _open();

  Future<Widget?> _open() async {
    final cameras = await availableCameras();
    if (cameras.isEmpty) return null;
    final front = cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.front,
      orElse: () => cameras.first,
    );
    final c = _c = CameraController(front, ResolutionPreset.medium);
    await c.initialize();
    await c.startVideoRecording();
    return _Square(c);
  }

  @override
  Future<String?> stop() async {
    try {
      await _opening;
    } on Object {
      return null;
    }
    final c = _c;
    if (c == null || !c.value.isRecordingVideo) return null;
    final file = await c.stopVideoRecording();
    await close();
    await dir.create(recursive: true);
    final kept = await File(file.path)
        .copy('${dir.path}/round-${NeonChatRepository.uuid()}.mp4');
    return kept.path;
  }

  @override
  Future<void> close() async {
    try {
      await _opening;
    } on Object {
      // It never opened.
    }
    final c = _c;
    _c = null;
    if (c == null) return;
    if (c.value.isRecordingVideo) await c.stopVideoRecording();
    await c.dispose();
  }
}

/// The preview cropped square, to sit in the circle.
class _Square extends StatelessWidget {
  const _Square(this.c);
  final CameraController c;

  @override
  Widget build(BuildContext context) => FittedBox(
    fit: BoxFit.cover,
    child: SizedBox(
      width: c.value.previewSize?.height ?? 480,
      height: c.value.previewSize?.width ?? 640,
      child: CameraPreview(c),
    ),
  );
}
