import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Every test draws with the real Doto and Inter, so layouts are checked
/// as they render on a phone (not with the wide stand-in test font).
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final (family, path) in [
    ('Doto', 'assets/fonts/Doto.ttf'),
    ('Inter', 'assets/fonts/Inter.ttf'),
  ]) {
    final loader = FontLoader(family)
      ..addFont(
        Future.value(ByteData.sublistView(File(path).readAsBytesSync())),
      );
    await loader.load();
  }
  await testMain();
}
