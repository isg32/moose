import 'dart:io';

import 'package:flutter/widgets.dart';

import '../../core/theme/v_colors.dart';
import '../../core/theme/v_text.dart';
import '../../core/widgets/v_ink.dart';
import '../../core/widgets/v_surface.dart';
import '../../data/models.dart';

/// A person's picture, or their initial, in a circle (A8): yours filled
/// with ink, your partner's outlined, with an optional online dot.
class Avatar extends StatelessWidget {
  const Avatar(
    this.person, {
    super.key,
    this.size = 40,
    this.filled = false,
    this.online = false,
  });

  final Person person;
  final double size;
  final bool filled;
  final bool online;

  @override
  Widget build(BuildContext context) {
    final ink = VInk.of(context);
    final paper = VInk.surfaceOf(context);
    final photo = person.photo;
    final hasPhoto =
        photo != null && !photo.startsWith('mock:') && File(photo).existsSync();
    return SizedBox.square(
      dimension: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          if (hasPhoto)
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: ink),
                  image: DecorationImage(
                    image: ResizeImage(
                      FileImage(File(photo)),
                      width: (size * 3).round(),
                    ),
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            )
          else
            Positioned.fill(
              child: VOutlined(
                radius: size / 2,
                outline: filled ? VOutline.none : VOutline.solid,
                fill: filled ? ink : VColors.transparent,
                child: Center(
                  child: Text(
                    person.initial,
                    style: VText.doto(
                      size * 0.46,
                      weight: 900,
                      height: 1,
                    ).copyWith(color: filled ? paper : ink),
                  ),
                ),
              ),
            ),
          if (online)
            Positioned(
              right: -1,
              bottom: -1,
              child: Container(
                width: size * 0.28,
                height: size * 0.28,
                decoration: BoxDecoration(
                  color: ink,
                  shape: BoxShape.circle,
                  border: Border.all(color: paper, width: 2),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
