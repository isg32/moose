import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../app/shell.dart';
import '../../core/theme/v_colors.dart';
import '../../core/theme/v_palette.dart';
import '../../core/theme/v_text.dart';

/// A short message over everything, near the bottom (A7): ink, or a
/// moment's colour.
void showToast(BuildContext context, String text, {Color? tint}) {
  final overlay = Overlay.of(context, rootOverlay: true);
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (context) =>
        _Toast(text: text, tint: tint, onDone: () => entry.remove()),
  );
  overlay.insert(entry);
}

class _Toast extends StatefulWidget {
  const _Toast({required this.text, required this.onDone, this.tint});

  final String text;
  final Color? tint;
  final VoidCallback onDone;

  @override
  State<_Toast> createState() => _ToastState();
}

class _ToastState extends State<_Toast> with SingleTickerProviderStateMixin {
  late final _t = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 250),
  )..forward();
  Timer? _hide;

  @override
  void initState() {
    super.initState();
    _hide = Timer(const Duration(milliseconds: 1800), () async {
      if (!mounted) return;
      await _t.reverse();
      widget.onDone();
    });
  }

  @override
  void dispose() {
    _hide?.cancel();
    _t.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = VPalette.of(context);
    final tint = widget.tint;
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Positioned(
      left: 0,
      right: 0,
      bottom: bottom + AppShell.pillBottom + AppShell.pillHeight + 74,
      child: IgnorePointer(
        child: FadeTransition(
          opacity: _t,
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: tint ?? palette.ink,
                borderRadius: BorderRadius.circular(999),
                boxShadow: tint == null
                    ? null
                    : [
                        BoxShadow(
                          color: tint.withValues(alpha: 0.45),
                          blurRadius: 30,
                          offset: const Offset(0, 10),
                        ),
                      ],
              ),
              child: Text(
                widget.text,
                style: VText.inter(
                  13,
                  weight: tint == null ? 500 : 600,
                ).copyWith(color: tint == null ? palette.paper : VColors.black),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
