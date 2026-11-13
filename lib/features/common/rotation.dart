import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Lets the phone turn to landscape while [child] is open, and puts Moose
/// back to portrait when it closes. Only the pages where landscape helps
/// use it: the media viewer, video calls and the doodle board.
class AllowRotation extends StatefulWidget {
  const AllowRotation({super.key, required this.child});

  final Widget child;

  @override
  State<AllowRotation> createState() => _AllowRotationState();
}

class _AllowRotationState extends State<AllowRotation> {
  static const _all = [
    DeviceOrientation.portraitUp,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ];

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations(_all);
  }

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Wider than tall.
bool isLandscape(BuildContext context) {
  final s = MediaQuery.sizeOf(context);
  return s.width > s.height;
}
