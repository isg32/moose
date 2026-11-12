import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Enforces the two-colour rule from `design/DESIGN.md`.
///
/// Colours may only be created in `lib/core/theme/v_colors.dart`. Everywhere
/// else must use `VColors`. Material is banned outright, because its widgets
/// bring their own palette.
void main() {
  const allowedFile = 'lib/core/theme/v_colors.dart';

  final banned = <String, RegExp>{
    'Color(...) constructor': RegExp(r'(?<![A-Za-z_])Color\s*\('),
    'Color.from* constructor': RegExp(r'(?<![A-Za-z_])Color\.from'),
    'CupertinoColors': RegExp(r'\bCupertinoColors\.'),
    'Material Colors': RegExp(r'(?<![A-Za-z_])Colors\.'),
    'Material import': RegExp(r'''package:flutter/material\.dart'''),
  };

  final files = Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .where((f) => !f.path.endsWith('.g.dart'))
      .where((f) => f.path.replaceAll(r'\', '/') != allowedFile)
      .toList();

  test('lib/ contains Dart files to check', () {
    expect(files, isNotEmpty);
  });

  test('no colour is created outside VColors', () {
    final violations = <String>[];
    for (final file in files) {
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        if (line.trimLeft().startsWith('//')) continue;
        banned.forEach((name, pattern) {
          if (pattern.hasMatch(line)) {
            violations.add('${file.path}:${i + 1}  $name  →  ${line.trim()}');
          }
        });
      }
    }
    expect(violations, isEmpty, reason: violations.join('\n'));
  });
}
