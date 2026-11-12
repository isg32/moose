import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../core/theme/v_colors.dart';
import '../core/theme/v_palette.dart';
import '../core/theme/v_text.dart';
import '../data/chat_theme.dart';
import '../features/common/wallpaper.dart';

/// The couple's shared theme over everything: the wallpaper behind every
/// screen, and its ink and glass for everything drawn on it (as Cariño's
/// LayoutTheme).
class MooseTheme extends StatelessWidget {
  const MooseTheme({super.key, required this.theme, required this.child});

  final ChatTheme theme;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = theme.palette;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value:
          (palette.isDark
                  ? SystemUiOverlayStyle.light
                  : SystemUiOverlayStyle.dark)
              .copyWith(
                statusBarColor: VColors.transparent,
                systemNavigationBarColor: VColors.transparent,
                systemNavigationBarContrastEnforced: false,
              ),
      child: VPaletteScope(
        palette: palette,
        child: DefaultTextStyle.merge(
          style: VText.body.copyWith(color: palette.ink),
          child: Stack(
            fit: StackFit.expand,
            children: [
              WallpaperView(
                wallpaper: theme.wallpaper,
                dim: theme.dim,
                blur: theme.blur,
              ),
              child,
            ],
          ),
        ),
      ),
    );
  }
}
