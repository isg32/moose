import 'dart:io';

import 'package:flutter/painting.dart';

import '../data/models.dart';
import '../data/repositories.dart';
import 'local_store.dart';

/// What Moose keeps on this phone (C38), from the files the conversation
/// points at; Clear deletes them (the bubbles fall back to stand-in art).
class PhoneStorage implements StorageRepository {
  PhoneStorage(this.store, this.mediaDir, this.cacheDir);

  final LocalStore store;
  final Directory mediaDir;
  final Directory cacheDir;

  Map<String, List<File>> _files() {
    final out = <String, List<File>>{
      'Photos': [],
      'Videos': [],
      'Round videos': [],
      'Voice notes': [],
      'Wallpapers': [],
    };
    void add(String kind, String? path) {
      if (path == null) return;
      final f = File(path);
      if (f.existsSync()) out[kind]!.add(f);
    }

    for (final m in store.messages) {
      switch (m.body) {
        case PhotoBody(:final photos):
          for (final p in photos) {
            add('Photos', p.path);
          }
        case VideoBody(:final video):
          add('Videos', video.path);
        case RoundVideoBody(:final video):
          add('Round videos', video.path);
        case VoiceBody(:final path):
          add('Voice notes', path);
        default:
          break;
      }
    }
    if (mediaDir.existsSync()) {
      for (final f in mediaDir.listSync().whereType<File>()) {
        if (f.uri.pathSegments.last.startsWith('wall-')) {
          out['Wallpapers']!.add(f);
        }
      }
    }
    add('Wallpapers', store.theme.wallpaper.photo);
    return out;
  }

  @override
  List<StorageUse> load() => [
    for (final MapEntry(:key, :value) in _files().entries)
      StorageUse(key, value.fold(0, (n, f) => n + f.lengthSync())),
    StorageUse('Doodles', _doodleBytes()),
  ];

  int _doodleBytes() {
    // Doodles live in moose.json: about 12 bytes a point.
    var points = 0;
    for (final d in store.doodles) {
      for (final s in d.strokes) {
        points += s.points.length;
      }
    }
    return points * 12;
  }

  @override
  int get cacheBytes {
    var n = PaintingBinding.instance.imageCache.currentSizeBytes;
    try {
      if (!cacheDir.existsSync()) return n;
      for (final f
          in cacheDir
              .listSync(recursive: true, followLinks: false)
              .whereType<File>()) {
        try {
          n += f.lengthSync();
        } on FileSystemException {
          // Gone or unreadable: not counted.
        }
      }
    } on FileSystemException {
      // A folder that can't be read: count what could be.
    }
    return n;
  }

  @override
  Future<void> clear(String label) async {
    for (final f in _files()[label] ?? const <File>[]) {
      try {
        await f.delete();
      } on FileSystemException {
        // Already gone.
      }
    }
  }

  @override
  Future<void> clearCache() async {
    PaintingBinding.instance.imageCache.clear();
    if (!cacheDir.existsSync()) return;
    for (final e in cacheDir.listSync()) {
      try {
        await e.delete(recursive: true);
      } on FileSystemException {
        // In use.
      }
    }
  }
}
