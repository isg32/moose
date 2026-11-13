import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'app/app.dart';
import 'app/version.dart';
import 'core/theme/v_colors.dart';
import 'features/crash_overlay.dart';
import 'net/config.dart';
import 'net/neon_backend.dart';
import 'net/phone_media.dart';
import 'net/phone_voice.dart';
import 'net/push.dart';
import 'net/vault.dart';
import 'platform/crash_log.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // First, so errors from here on are logged and shown, not lost.
  CrashLog.instance
    ..appVersion = mooseVersion
    ..install();
  ErrorWidget.builder = quietErrorWidget;

  // Edge to edge: the wallpaper runs under the status and navigation bars.
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: VColors.transparent,
      systemNavigationBarColor: VColors.transparent,
      systemNavigationBarContrastEnforced: false,
    ),
  );
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  LicenseRegistry.addLicense(() async* {
    for (final font in ['Doto', 'Inter']) {
      final text = await rootBundle.loadString('assets/fonts/OFL-$font.txt');
      yield LicenseEntryWithLineBreaks([font], text);
    }
  });

  // On Neon when the build has a backend (env.json); the mock partner
  // otherwise.
  final config = NeonConfig.fromEnvironment;
  final backend = config == null
      ? null
      : await NeonBackend.open(
          config,
          vault: const SecureVault(),
          dir: await getApplicationSupportDirectory(),
        );
  if (backend != null) {
    backend
      ..media = PhoneMedia(backend.mediaDir)
      ..voice = PhoneVoice(backend.mediaDir)
      ..askNotifications = Push.ask
      ..pushToken = Push.token;
    try {
      await Push.init(onWake: () => backend.wake?.call());
    } on Object catch (e) {
      // Without Firebase, Moose still polls; it just can't be woken.
      CrashLog.instance.add('push off: $e');
    }
  }
  runApp(
    ProviderScope(
      overrides: backend?.overrides() ?? const [],
      child: const MooseApp(splash: true),
    ),
  );
  // A crash on the Android side last time is shown once, now.
  unawaited(CrashLog.instance.checkLastRun());
}
