import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

const _files = MethodChannel('moose/files');

/// A problem worth showing the person: what happened, and the full log.
@immutable
class CrashReport {
  const CrashReport({
    required this.title,
    required this.summary,
    required this.log,
    this.fromLastRun = false,
  });

  final String title;
  final String summary;

  /// Everything to copy or save: device, error, stack, recent log lines.
  final String log;

  /// Moose closed unexpectedly last time (a native crash, read at start).
  final bool fromLastRun;
}

/// Keeps a rolling log of what Moose printed, catches errors that would
/// otherwise be lost or crash the app, and raises a [CrashReport] the app
/// shows as a popup (copy, save to Downloads, close).
///
/// Network failures (the weather service unreachable, a dropped
/// connection) are logged but not reported: weather already falls back to
/// its last reading.
class CrashLog {
  CrashLog._();

  static final CrashLog instance = CrashLog._();

  static const int _keep = 400;
  final Queue<String> _lines = Queue();

  /// The report to show now, if any.
  final ValueNotifier<CrashReport?> pending = ValueNotifier(null);

  String appVersion = '';

  /// Hooks into Flutter's error handlers and debugPrint. Call first in
  /// main().
  void install() {
    final print = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) add(message);
      print(message, wrapWidth: wrapWidth);
    };
    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      report(
        details.exception,
        details.stack,
        context: details.context?.toDescription() ?? 'While drawing',
      );
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      report(error, stack, context: 'In the background');
      return true;
    };
  }

  /// Adds a line to the rolling log.
  void add(String line) {
    _lines.addLast('${_time(DateTime.now())}  $line');
    while (_lines.length > _keep) {
      _lines.removeFirst();
    }
  }

  /// The rolling log, oldest first.
  List<String> get lines => List.unmodifiable(_lines);

  /// Logs [error]; shows a report unless it's network noise.
  void report(Object error, StackTrace? stack, {String context = ''}) {
    add('ERROR ${context.isEmpty ? '' : '($context) '}$error');
    if (isNetworkNoise(error)) return;
    final log = buildLog(
      error: error,
      stack: stack,
      context: context,
      lines: lines,
      version: appVersion,
      device: _device(),
      at: DateTime.now(),
    );
    unawaited(_persist(log));
    // One popup at a time; later errors are in the log of the first.
    pending.value ??= CrashReport(
      title: 'Something went wrong',
      summary:
          'Moose ran into an unexpected problem. Your chats '
          'are safe. The log below helps find the cause.',
      log: log,
    );
  }

  /// A crash Moose couldn't catch last time (written by MainActivity),
  /// shown once at start.
  Future<void> checkLastRun() async {
    try {
      final dir = await _dir();
      final files =
          dir
              .listSync()
              .whereType<File>()
              .where((f) => _name(f.path).startsWith('native-'))
              .toList()
            ..sort((a, b) => a.path.compareTo(b.path));
      if (files.isEmpty) return;
      final newest = files.last;
      final text = await newest.readAsString();
      for (final f in files) {
        await f.rename('${dir.path}/seen-${_name(f.path)}');
      }
      pending.value ??= CrashReport(
        title: 'Moose closed unexpectedly',
        summary:
            'Last time, Moose stopped because of a problem on the Android '
            'side. Your chats are safe.',
        log: '${_header(appVersion, _device())}\n$text',
        fromLastRun: true,
      );
    } on Object catch (e) {
      add('Could not read last crash: $e');
    }
  }

  /// Shows a sample report, to see what one looks like.
  void test() {
    report(
      StateError('This is a test report. Nothing is wrong.'),
      StackTrace.current,
      context: 'Test from Settings',
    );
  }

  void dismiss() => pending.value = null;

  /// Saves [log] to the phone's Downloads folder; returns where.
  Future<String> saveToDownloads(String log) async {
    final name = 'moose-log-${_stamp(DateTime.now())}.txt';
    final where = await _files.invokeMethod<String>('saveToDownloads', {
      'name': name,
      'text': log,
    });
    return where ?? 'Downloads/$name';
  }

  Future<void> _persist(String log) async {
    try {
      final f = File(
        '${(await _dir()).path}/dart-${_stamp(DateTime.now())}.txt',
      );
      await f.writeAsString(log);
    } on Object {
      // The popup still shows the log.
    }
  }

  /// `<files>/crashes`, the folder MainActivity writes native crashes to.
  static Future<Directory> _dir() async {
    final path = await _files.invokeMethod<String>('crashDir');
    final d = Directory(path ?? '${Directory.systemTemp.path}/crashes');
    if (!d.existsSync()) await d.create(recursive: true);
    return d;
  }

  static String _name(String path) => path.split('/').last;

  static String _device() =>
      '${Platform.operatingSystem} ${Platform.operatingSystemVersion}';
}

/// True for network failures (recovered from, so not worth a popup).
bool isNetworkNoise(Object error) =>
    error is SocketException ||
    error is HttpException ||
    error is HandshakeException ||
    error is TimeoutException ||
    error is TlsException;

/// The text a report copies or saves.
String buildLog({
  required Object error,
  required StackTrace? stack,
  required String context,
  required List<String> lines,
  required String version,
  required String device,
  required DateTime at,
}) {
  final b = StringBuffer()
    ..writeln(_header(version, device, at: at))
    ..writeln('What: $error');
  if (context.isNotEmpty) b.writeln('Where: $context');
  b
    ..writeln()
    ..writeln('Stack:')
    ..writeln(stack?.toString().trim() ?? '(none)')
    ..writeln()
    ..writeln('Recent log (${lines.length} lines):');
  for (final l in lines) {
    b.writeln(l);
  }
  return b.toString();
}

String _header(String version, String device, {DateTime? at}) =>
    'Moose ${version.isEmpty ? '' : '$version '}· $device · '
    '${(at ?? DateTime.now()).toIso8601String()}';

String _time(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:'
    '${t.minute.toString().padLeft(2, '0')}:'
    '${t.second.toString().padLeft(2, '0')}.'
    '${(t.millisecond ~/ 100)}';

String _stamp(DateTime t) =>
    '${t.year}${t.month.toString().padLeft(2, '0')}'
    '${t.day.toString().padLeft(2, '0')}-'
    '${t.hour.toString().padLeft(2, '0')}'
    '${t.minute.toString().padLeft(2, '0')}'
    '${t.second.toString().padLeft(2, '0')}';
