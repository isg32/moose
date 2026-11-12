import 'dart:io';

import 'package:moose/app/version.dart';
import 'package:flutter_test/flutter_test.dart';

/// The version shown in About and crash logs must be the one in pubspec.yaml.
void main() {
  test('About shows the pubspec version', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final match = RegExp(
      r'^version:\s*([0-9.]+)',
      multiLine: true,
    ).firstMatch(pubspec);
    expect(match, isNotNull);
    expect(mooseVersion, match!.group(1));
  });
}
