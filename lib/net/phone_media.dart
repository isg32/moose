import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';

import '../data/models.dart';
import '../data/providers.dart';
import 'neon_backend.dart';

/// The phone's own gallery and camera (C18, C20 on Neon). Each pick is
/// copied into Moose's private storage, so the chat keeps it even if it's
/// deleted from the gallery.
class PhoneMedia implements MediaSource {
  PhoneMedia(this.dir);

  final Directory dir;
  final _picker = ImagePicker();

  @override
  Future<List<Media>> gallery() async {
    // As they are: the preview's HD switch decides whether they're resized
    // (see standard).
    final picked = await _picker.pickMultipleMedia(limit: 10);
    return [for (final x in picked) await _keep(x)];
  }

  @override
  Future<Media?> camera() async {
    final x = await _picker.pickImage(source: ImageSource.camera);
    return x == null ? null : _keep(x);
  }

  static bool _isVideo(XFile x) {
    final mime = x.mimeType ?? '';
    if (mime.startsWith('video/')) return true;
    final name = x.path.toLowerCase();
    return name.endsWith('.mp4') ||
        name.endsWith('.mov') ||
        name.endsWith('.webm') ||
        name.endsWith('.3gp') ||
        name.endsWith('.mkv');
  }

  @override
  Future<Media> standard(Media m) async {
    final path = m.path;
    if (path == null || m.duration != null) return m;
    try {
      final out = '${dir.path}/${NeonChatRepository.uuid()}.jpg';
      final small = await FlutterImageCompress.compressAndGetFile(
        path,
        out,
        minWidth: 2048,
        minHeight: 2048,
        quality: 82,
      );
      if (small == null) return m;
      final bytes = await small.readAsBytes();
      // Only if it actually came out smaller.
      if (bytes.length >= m.bytes) return m;
      return Media(
        id: m.id,
        art: m.art,
        aspect: await aspectOf(bytes),
        bytes: bytes.length,
        path: small.path,
      );
    } on Object {
      return m; // No compressor here (the desktop build): send it as it is.
    }
  }

  Future<Media> _keep(XFile x) async {
    await dir.create(recursive: true);
    final id = NeonChatRepository.uuid();
    final bytes = await x.readAsBytes();
    final file = await File('${dir.path}/$id').writeAsBytes(bytes, flush: true);
    if (_isVideo(x)) return videoOf(file, id: id);
    return Media(
      id: id,
      art: bytes.length % 10,
      aspect: await aspectOf(bytes),
      bytes: bytes.length,
      path: file.path,
    );
  }
}

/// Width / height of an encoded image, without decoding its pixels.
Future<double> aspectOf(List<int> bytes) async {
  try {
    final buffer = await ui.ImmutableBuffer.fromUint8List(
      bytes is Uint8List ? bytes : Uint8List.fromList(bytes),
    );
    final d = await ui.ImageDescriptor.encoded(buffer);
    final a = d.width / d.height;
    d.dispose();
    buffer.dispose();
    return a.isFinite && a > 0 ? a : 1.4;
  } on Object {
    return 1.4;
  }
}

/// A video file as the chat shows it: its length and shape, read by the
/// player.
Future<Media> videoOf(File file, {required String id}) async {
  final c = VideoPlayerController.file(file);
  try {
    await c.initialize();
    final a = c.value.aspectRatio;
    return Media(
      id: id,
      art: file.lengthSync() % 10,
      aspect: a.isFinite && a > 0 ? a : 16 / 9,
      bytes: file.lengthSync(),
      duration: c.value.duration,
      path: file.path,
    );
  } finally {
    await c.dispose();
  }
}
