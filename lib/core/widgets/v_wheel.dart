import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../theme/v_text.dart';
import 'v_surface.dart';

/// A Doto picker wheel: the chosen value is large and framed by hairlines,
/// its neighbours small above and below.
class VWheel extends StatefulWidget {
  const VWheel({
    super.key,
    required this.values,
    required this.selected,
    required this.onChanged,
    this.format,
    this.looping = false,
    this.width = 64,
  });

  final List<int> values;
  final int selected;
  final ValueChanged<int> onChanged;
  final String Function(int value)? format;
  final bool looping;
  final double width;

  static const double itemExtent = 40;
  static const double height = itemExtent * 3;

  @override
  State<VWheel> createState() => _VWheelState();
}

class _VWheelState extends State<VWheel> {
  late FixedExtentScrollController _controller;
  late int _index;

  @override
  void initState() {
    super.initState();
    _index = _indexOf(widget.selected);
    _controller = FixedExtentScrollController(initialItem: _index);
  }

  int _indexOf(int value) {
    final i = widget.values.indexOf(value);
    return i < 0 ? 0 : i;
  }

  @override
  void didUpdateWidget(VWheel old) {
    super.didUpdateWidget(old);
    final next = _indexOf(widget.selected);
    if (next != _index % widget.values.length) {
      _index = next;
      _controller.jumpToItem(next);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _label(int v) =>
      widget.format?.call(v) ?? v.toString().padLeft(2, '0');

  @override
  Widget build(BuildContext context) {
    final n = widget.values.length;
    Widget item(int i) {
      final selected = i % n == _index % n;
      return Center(
        child: Text(
          _label(widget.values[i % n]),
          style: selected
              ? VText.doto(38, weight: 900, height: 1)
              : VText.doto(18, weight: 500, height: 1),
        ),
      );
    }

    return SizedBox(
      width: widget.width,
      height: VWheel.height,
      child: ListWheelScrollView.useDelegate(
        controller: _controller,
        itemExtent: VWheel.itemExtent,
        diameterRatio: 100,
        physics: const FixedExtentScrollPhysics(),
        onSelectedItemChanged: (i) {
          HapticFeedback.selectionClick();
          setState(() => _index = i);
          widget.onChanged(widget.values[i % n]);
        },
        childDelegate: widget.looping
            ? ListWheelChildLoopingListDelegate(
                children: [for (var i = 0; i < n; i++) item(i)],
              )
            : ListWheelChildBuilderDelegate(
                childCount: n,
                builder: (_, i) => item(i),
              ),
      ),
    );
  }
}

/// Hairlines across the full width behind one or more wheels.
class VWheelFrame extends StatelessWidget {
  const VWheelFrame({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: VWheel.height,
      child: Stack(
        alignment: Alignment.center,
        children: [
          const Positioned(
            left: 0,
            right: 0,
            top: VWheel.itemExtent - 4,
            child: VDivider(),
          ),
          const Positioned(
            left: 0,
            right: 0,
            top: VWheel.itemExtent * 2 + 4,
            child: VDivider(),
          ),
          child,
        ],
      ),
    );
  }
}

/// Hour and minute wheels with a Doto colon between them.
class VTimeWheel extends StatelessWidget {
  const VTimeWheel({
    super.key,
    required this.hour,
    required this.minute,
    required this.onChanged,
    this.minuteStep = 5,
  });

  final int hour;
  final int minute;
  final void Function(int hour, int minute) onChanged;
  final int minuteStep;

  @override
  Widget build(BuildContext context) {
    final minutes = [for (var m = 0; m < 60; m += minuteStep) m];
    final snapped = minutes.lastWhere((m) => m <= minute, orElse: () => 0);
    return VWheelFrame(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          VWheel(
            values: [for (var h = 0; h < 24; h++) h],
            selected: hour,
            looping: true,
            onChanged: (h) => onChanged(h, snapped),
          ),
          const SizedBox(width: 20),
          Text(':', style: VText.doto(32, weight: 900)),
          const SizedBox(width: 20),
          VWheel(
            values: minutes,
            selected: snapped,
            looping: true,
            onChanged: (m) => onChanged(hour, m),
          ),
        ],
      ),
    );
  }
}
