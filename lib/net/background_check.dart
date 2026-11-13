import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:path_provider/path_provider.dart';

import 'api.dart';
import 'config.dart';
import 'local_store.dart';
import 'neon_backend.dart';
import 'push.dart';
import 'vault.dart';

/// The background check: a quiet foreground service that looks for sealed
/// mail every 6 minutes while Moose is closed, so a message still makes a
/// notification when Firebase can't wake the phone. It only peeks; Moose
/// takes the mail (and acks it) when it opens.
abstract final class BackgroundCheck {
  /// Every 6 minutes (the user's choice: it keeps Neon's compute within
  /// the free plan). `--dart-define=MOOSE_CHECK_EVERY=<seconds>` shortens
  /// it for tests.
  static const every = Duration(
    seconds: int.fromEnvironment('MOOSE_CHECK_EVERY', defaultValue: 360),
  );

  static const _file = 'background-check.json';

  static void init() => FlutterForegroundTask.init(
    androidNotificationOptions: AndroidNotificationOptions(
      channelId: 'background',
      channelName: 'Background check',
      channelDescription: 'Quietly looks for messages while Moose is closed',
      onlyAlertOnce: true,
    ),
    iosNotificationOptions: const IOSNotificationOptions(),
    foregroundTaskOptions: ForegroundTaskOptions(
      eventAction: ForegroundTaskEventAction.repeat(every.inMilliseconds),
      allowWakeLock: true,
      autoRunOnBoot: true,
    ),
  );

  static Future<bool> get running => FlutterForegroundTask.isRunningService;

  static Future<void> start() async {
    if (await running) return;
    await FlutterForegroundTask.startService(
      serviceId: 600,
      serviceTypes: [ForegroundServiceTypes.remoteMessaging],
      notificationTitle: 'Moose',
      notificationText:
          'Checking for messages every '
          '${every.inMinutes > 0 ? '${every.inMinutes} min' : '${every.inSeconds} s'}',
      callback: backgroundCheckMain,
    );
  }

  static Future<void> stop() => FlutterForegroundTask.stopService();

  /// When the last check ran, from any isolate.
  static Future<DateTime?> lastCheck() async {
    try {
      final f = File('${(await getApplicationSupportDirectory()).path}/$_file');
      if (!f.existsSync()) return null;
      final j = jsonDecode(await f.readAsString()) as Map;
      return DateTime.tryParse(j['at'] as String? ?? '');
    } on Object {
      return null;
    }
  }
}

@pragma('vm:entry-point')
void backgroundCheckMain() => FlutterForegroundTask.setTaskHandler(_Check());

class _Check extends TaskHandler {
  NeonBackend? _b;
  final _told = <String>{};
  var _busy = false;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    final config = NeonConfig.fromEnvironment;
    if (config == null) return;
    await Push.ready();
    _b = await NeonBackend.open(
      config,
      vault: const SecureVault(),
      dir: await getApplicationSupportDirectory(),
    );
    await _check();
  }

  @override
  void onRepeatEvent(DateTime timestamp) => unawaited(_check());

  Future<void> _check() async {
    final b = _b;
    if (b == null || _busy) return;
    _busy = true;
    try {
      // The app may have written since: read its store afresh.
      final store = await LocalStore.open(b.dir);
      if (!store.paired) return;
      final List<Mail> mail;
      try {
        mail = await b.api.inbox();
      } on Object {
        return; // offline: next time
      }
      for (final m in mail) {
        if (!_told.add(m.id)) continue;
        final n = await Push.describe(
          {'kind': m.kind, 'body': m.body},
          vault: b.vault,
          store: store,
        );
        if (n != null) await Push.show(n, id: n.moment ? 2 : 1, tag: 'bg');
      }
      final at = DateTime.now();
      await File('${b.dir.path}/${BackgroundCheck._file}')
          .writeAsString(jsonEncode({'at': at.toIso8601String()}));
      await FlutterForegroundTask.updateService(
        notificationText:
            'Last checked ${at.hour.toString().padLeft(2, '0')}:'
            '${at.minute.toString().padLeft(2, '0')}',
      );
    } finally {
      _busy = false;
    }
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}
}
