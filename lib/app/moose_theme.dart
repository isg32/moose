import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../core/theme/v_colors.dart';
import '../core/theme/v_palette.dart';
import '../core/theme/v_text.dart';
import '../core/widgets/v_page.dart';
import '../data/chat_theme.dart';
import '../features/common/wallpaper.dart';

/// The couple's shared theme over everything: the wallpaper behind every
/// screen, and its ink and glass for everything drawn on it (as Cariño's
/// LayoutTheme).
class MooseTheme extends StatefulWidget {
  const MooseTheme({super.key, required this.theme, required this.child});

  final ChatTheme theme;
  final Widget child;

  @override
  State<MooseTheme> createState() => _MooseThemeState();
}

class _MooseThemeState extends State<MooseTheme> {
  @override
  void initState() {
    super.initState();
    _bake();
  }

  @override
  void didUpdateWidget(MooseTheme old) {
    super.didUpdateWidget(old);
    if (old.theme.wallpaper != widget.theme.wallpaper ||
        old.theme.blur != widget.theme.blur) {
      _bake();
    }
  }

  /// A blurred photo wallpaper is blurred once into a file, then shown as a
  /// plain image: blurring it live costs every frame, and blips.
  Future<void> _bake() async {
    final photo = widget.theme.wallpaper.photo;
    final blur = widget.theme.blur;
    if (photo == null || photo.startsWith('mock:') || blur <= 0.01) return;
    if (blurReady(photo, blur)) return;
    try {
      await bakeBlur(photo, blur);
    } on Object {
      return; // Stays blurred live.
    }
    // WallpaperView swaps to the baked copy once it is decoded.
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
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
              VVeilBackdrop(
                backdrop: WallpaperView(
                  wallpaper: theme.wallpaper,
                  dim: theme.dim,
                  soft: true,
                ),
                child: widget.child,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
