import 'package:flutter/cupertino.dart';

import '../../core/theme/v_colors.dart';
import '../../core/theme/v_tokens.dart';

/// Opens [builder] over everything as a see-through page that fades in,
/// for overlays drawn on the chat: message actions, the poke picker,
/// recorders and bursts.
Future<T?> showOverlayPage<T>(BuildContext context, WidgetBuilder builder) {
  return Navigator.of(context, rootNavigator: true).push<T>(
    PageRouteBuilder<T>(
      opaque: false,
      barrierColor: VColors.transparent,
      transitionDuration: VMotion.standard,
      reverseTransitionDuration: VMotion.standard,
      pageBuilder: (context, _, _) => builder(context),
      transitionsBuilder: (context, animation, _, child) => FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: VMotion.curve),
        child: child,
      ),
    ),
  );
}

/// Opens a full page (gallery, viewer, music search) that fades in.
Future<T?> pushPage<T>(BuildContext context, WidgetBuilder builder) {
  return Navigator.of(context, rootNavigator: true).push<T>(
    PageRouteBuilder<T>(
      transitionDuration: VMotion.standard,
      reverseTransitionDuration: VMotion.standard,
      opaque: false,
      pageBuilder: (context, _, _) => builder(context),
      transitionsBuilder: (context, animation, _, child) => FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: VMotion.curve),
        child: child,
      ),
    ),
  );
}
