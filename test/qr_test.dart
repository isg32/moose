import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moose/features/onboarding/onboarding_pages.dart';

void main() {
  test('codes come out of scans, typed or as moose: links', () {
    expect(codeFromQr('moose:K7Q2MX'), 'K7Q2MX');
    expect(codeFromQr('k7q2mx'), 'K7Q2MX');
    expect(codeFromQr(' moose:ABCD23 '), 'ABCD23');
    expect(codeFromQr('https://example.com'), isNull);
    expect(codeFromQr('moose:K7Q2M'), isNull);
  });

  // The QR on the pairing screen is a real one: drawn here, then read back
  // by OpenCV (in the Python partner's venv), which shares no code with it.
  testWidgets('the pairing QR scans', (t) async {
    const py = 'tool/partner/.venv/bin/python';
    if (!File(py).existsSync()) {
      markTestSkipped('needs tool/partner/.venv with opencv');
      return;
    }
    final key = GlobalKey();
    await t.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: RepaintBoundary(
            key: key,
            child: QrCard(data: pairQr('K7Q2MX'), size: 240),
          ),
        ),
      ),
    );
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final png = await t.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 2);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      return data!.buffer.asUint8List();
    });
    final file = File('build/qr_test.png')
      ..createSync(recursive: true)
      ..writeAsBytesSync(png!);
    final read = await t.runAsync(
      () => Process.run(py, [
        '-c',
        'import cv2,sys; i=cv2.imread(sys.argv[1]); '
            'v,_,_=cv2.QRCodeDetector().detectAndDecode(i); print(v)',
        file.path,
      ]),
    );
    expect(
      (read!.stdout as String).trim(),
      'moose:K7Q2MX',
      reason: '${read.stderr}',
    );
  });
}
