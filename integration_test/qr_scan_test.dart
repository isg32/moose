import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:moose/features/onboarding/onboarding_pages.dart';
import 'package:path_provider/path_provider.dart';

/// The pairing QR, drawn by Moose, read by the phone's own scanner (ML Kit,
/// the same reader the camera page uses).
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the phone reads the pairing QR', (t) async {
    final key = GlobalKey();
    await t.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: RepaintBoundary(
            key: key,
            child: QrCard(data: pairQr('H4PPY2'), size: 240),
          ),
        ),
      ),
    );
    await t.pump();
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 3);
    final png = (await image.toByteData(format: ui.ImageByteFormat.png))!;
    final file = File('${(await getTemporaryDirectory()).path}/qr.png')
      ..writeAsBytesSync(png.buffer.asUint8List());
    final scanner = MobileScannerController(autoStart: false);
    addTearDown(scanner.dispose);
    final capture = await scanner.analyzeImage(file.path);
    final read = capture?.barcodes.map((b) => b.rawValue).toList();
    expect(read, contains('moose:H4PPY2'));
    expect(codeFromQr(read!.first!), 'H4PPY2');
  });
}
