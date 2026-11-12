import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'app/version.dart';
import 'core/theme/v_colors.dart';
import 'core/theme/v_palette.dart';
import 'core/theme/v_text.dart';
import 'core/theme/v_theme.dart';
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

  runApp(const MooseApp());
  // A crash on the Android side last time is shown once, now.
  unawaited(CrashLog.instance.checkLastRun());
}

/// The app root. For now just the splash wordmark (C1) on the design
/// system; the shell arrives next.
class MooseApp extends StatelessWidget {
  const MooseApp({super.key});

  @override
  Widget build(BuildContext context) {
    const palette = VPalette.dark;
    return CupertinoApp(
      title: 'Moose',
      debugShowCheckedModeBanner: false,
      theme: VTheme.of(palette),
      builder: (context, child) => CrashOverlay(child: child!),
      home: ColoredBox(
        color: palette.paper,
        child: Center(
          child: Text(
            'MO\nOSE',
            textAlign: TextAlign.center,
            style: VText.doto(
              62,
              weight: 900,
              height: 0.9,
              letterSpacing: -1.2,
            ).copyWith(color: palette.ink),
          ),
        ),
      ),
    );
  }
}
