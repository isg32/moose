import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'app/version.dart';
import 'core/theme/v_colors.dart';
import 'features/crash_overlay.dart';
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

  runApp(const ProviderScope(child: MooseApp()));
  // A crash on the Android side last time is shown once, now.
  unawaited(CrashLog.instance.checkLastRun());
}
