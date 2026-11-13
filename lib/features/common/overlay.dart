import 'package:flutter/cupertino.dart';

import '../../core/theme/v_colors.dart';

/// Puts the keyboard away for good: the field loses focus too, so closing
/// whatever opens next doesn't hand focus back to it and pop the keyboard
/// up again.
void dropKeyboard() => FocusManager.instance.primaryFocus?.unfocus(
  disposition: UnfocusDisposition.scope,
);

/// Opens [builder] over everything as a see-through page for overlays
/// drawn on the chat (message actions, the poke picker, sheets): it fades
/// in and rises a little on iOS's ease-out, and settles back on the way
/// out.
Future<T?> showOverlayPage<T>(BuildContext context, WidgetBuilder builder) {
  dropKeyboard();
  return Navigator.of(context, rootNavigator: true).push<T>(
    PageRouteBuilder<T>(
      opaque: false,
      barrierColor: VColors.transparent,
      transitionDuration: const Duration(milliseconds: 380),
      reverseTransitionDuration: const Duration(milliseconds: 260),
      pageBuilder: (context, _, _) => builder(context),
      transitionsBuilder: (context, animation, _, child) {
        final a = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutQuart,
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(
          opacity: a,
          child: SlideTransition(
            position: Tween(
              begin: const Offset(0, 0.06),
              end: Offset.zero,
            ).animate(a),
            child: ScaleTransition(
              scale: Tween(begin: 0.985, end: 1.0).animate(a),
              child: child,
            ),
          ),
        );
      },
    ),
  );
}

/// Opens a full page (gallery, viewer, music search, settings pages) the
/// iOS way: it slides in from the right over a page that slides back and
/// dims, and a swipe from the left edge takes it back.
Future<T?> pushPage<T>(BuildContext context, WidgetBuilder builder) {
  dropKeyboard();
  return Navigator.of(
    context,
    rootNavigator: true,
  ).push<T>(MoosePageRoute<T>(builder: builder));
}

/// iOS's page route (slide, parallax, shadow, edge swipe back), kept
/// see-through so the shared wallpaper shows under every page.
class MoosePageRoute<T> extends PageRoute<T>
    with CupertinoRouteTransitionMixin<T> {
  MoosePageRoute({required this.builder, super.settings});

  final WidgetBuilder builder;

  @override
  Widget buildContent(BuildContext context) => builder(context);

  @override
  String? get title => null;

  @override
  bool get maintainState => true;

  @override
  bool get opaque => false;
}
