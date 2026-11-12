import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:moose/platform/crash_log.dart';

void main() {
  test('network failures are logged, not reported', () {
    expect(isNetworkNoise(const SocketException('down')), isTrue);
    expect(isNetworkNoise(const HttpException('HTTP 403')), isTrue);
    expect(isNetworkNoise(TimeoutException('slow')), isTrue);
    expect(isNetworkNoise(StateError('bug')), isFalse);
    expect(isNetworkNoise(const FormatException('bad')), isFalse);
  });

  test('the log has the device, error, place, stack and recent lines', () {
    final log = buildLog(
      error: StateError('boom'),
      stack: StackTrace.fromString('#0 main (file.dart:1)'),
      context: 'While drawing',
      lines: ['12:00:00.0  opened', '12:00:01.0  played'],
      version: '1.0.0',
      device: 'android 17',
      at: DateTime(2026, 11, 8, 12),
    );
    expect(log, startsWith('Moose 1.0.0 · android 17 · 2026-11-08T12:00:00'));
    expect(log, contains('What: Bad state: boom'));
    expect(log, contains('Where: While drawing'));
    expect(log, contains('#0 main (file.dart:1)'));
    expect(log, contains('Recent log (2 lines):\n12:00:00.0  opened'));
  });

  test('a report waits to be shown; later ones fold into the first', () {
    final c = CrashLog.instance;
    c.dismiss();
    c.add('before');
    c.report(StateError('first'), null);
    c.report(StateError('second'), null);
    expect(c.pending.value!.log, contains('first'));
    expect(c.pending.value!.log, isNot(contains('What: Bad state: second')));
    c.dismiss();
    expect(c.pending.value, isNull);
    c.report(const HttpException('HTTP 403'), null);
    expect(c.pending.value, isNull);
  });
}
