import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/theme/v_colors.dart';
import '../../core/theme/v_text.dart';
import '../../core/widgets/v_ink.dart';
import '../../data/chat_theme.dart';
import '../../data/models.dart';
import '../common/avatar.dart';
import '../common/wallpaper.dart';
import 'onboarding_pages.dart';

/// The card Share sends (C5): who's asking, the code, its QR and how to
/// use it, on the night wallpaper. 360 × 480, drawn at 3×.
class PairCard extends StatelessWidget {
  const PairCard({super.key, required this.me, required this.code});

  final Person me;
  final String code;

  static const size = Size(360, 480);

  @override
  Widget build(BuildContext context) => SizedBox.fromSize(
    size: size,
    child: VInkScope(
      ink: VColors.white,
      child: DefaultTextStyle(
        style: VText.inter(14).copyWith(color: VColors.white),
        child: Stack(
          fit: StackFit.expand,
          children: [
            const WallpaperView(wallpaper: WallpaperRef.builtin('night')),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        'MO\nOSE',
                        style: VText.doto(20, weight: 900, height: 0.9),
                      ),
                      const Spacer(),
                      Avatar(me, size: 44, filled: true),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Text(
                    '${me.name} wants to pair with you',
                    style: VText.inter(17, weight: 600),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'A quiet, private chat for two.',
                    style: VText.inter(13, weight: 300),
                  ),
                  const Spacer(),
                  Center(
                    child: Text(
                      code,
                      style: VText.doto(
                        44,
                        weight: 900,
                        height: 1,
                        letterSpacing: 3,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Center(child: QrCard(data: pairQr(code), size: 132)),
                  const Spacer(),
                  Text(
                    'In Moose: I have a code, then type or scan it. '
                    'Works once, for 10 minutes.',
                    style: VText.inter(12, weight: 300),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Draws [PairCard] off screen and opens the share sheet with it.
Future<void> sharePairCard(
  BuildContext context, {
  required Person me,
  required String code,
}) async {
  final key = GlobalKey();
  final overlay = Overlay.of(context, rootOverlay: true);
  final entry = OverlayEntry(
    builder: (_) => Positioned(
      // Painted, but out of sight.
      left: -PairCard.size.width * 2,
      top: 0,
      child: RepaintBoundary(
        key: key,
        child: PairCard(me: me, code: code),
      ),
    ),
  );
  overlay.insert(entry);
  try {
    // Let the wallpaper and avatar paint.
    await WidgetsBinding.instance.endOfFrame;
    await Future<void>.delayed(const Duration(milliseconds: 300));
    await WidgetsBinding.instance.endOfFrame;
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 3);
    final png = (await image.toByteData(format: ui.ImageByteFormat.png))!;
    final file = File('${(await getTemporaryDirectory()).path}/moose-$code.png')
      ..writeAsBytesSync(png.buffer.asUint8List());
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'image/png')],
        text: 'Pair with me on Moose: $code',
        subject: 'Moose',
      ),
    );
  } finally {
    entry.remove();
  }
}
