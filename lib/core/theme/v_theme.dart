import 'package:flutter/cupertino.dart';

import 'v_palette.dart';
import 'v_text.dart';

/// Cupertino theme with every default colour replaced by the palette's ink
/// and paper.
abstract final class VTheme {
  static CupertinoThemeData of(VPalette p) {
    final ink = p.ink;
    return CupertinoThemeData(
      brightness: p.brightness,
      primaryColor: ink,
      primaryContrastingColor: p.paper,
      scaffoldBackgroundColor: p.paper,
      barBackgroundColor: p.paper,
      applyThemeToAll: true,
      textTheme: CupertinoTextThemeData(
        primaryColor: ink,
        textStyle: VText.body.copyWith(color: ink),
        actionTextStyle: VText.body.copyWith(color: ink),
        navTitleTextStyle: VText.rowTitle.copyWith(color: ink),
        navLargeTitleTextStyle: VText.title.copyWith(color: ink),
        pickerTextStyle: VText.doto(22).copyWith(color: ink),
        dateTimePickerTextStyle: VText.doto(22).copyWith(color: ink),
        tabLabelTextStyle: VText.inter(12, weight: 600).copyWith(color: ink),
      ),
    );
  }
}
