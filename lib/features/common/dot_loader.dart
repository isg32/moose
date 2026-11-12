import 'package:flutter/widgets.dart';

import '../../core/widgets/v_ink.dart';

/// Three square Doto dots filling in turn: Moose's "working on it".
class DotLoader extends StatefulWidget {
  const DotLoader({super.key, this.size = 10});

  final double size;

  @override
  State<DotLoader> createState() => _DotLoaderState();
}

class _DotLoaderState extends State<DotLoader>
    with SingleTickerProviderStateMixin {
  late final _t = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();

  @override
  void dispose() {
    _t.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ink = VInk.of(context);
    return AnimatedBuilder(
      animation: _t,
      builder: (context, _) {
        final step = (_t.value * 3).floor();
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < 3; i++)
              Container(
                width: widget.size,
                height: widget.size,
                margin: EdgeInsets.symmetric(horizontal: widget.size / 2),
                decoration: BoxDecoration(
                  color: i <= step ? ink : null,
                  border: Border.all(color: ink),
                ),
              ),
          ],
        );
      },
    );
  }
}
