import 'package:flutter/widgets.dart';

import '../../core/widgets/v_list.dart';
import '../../core/widgets/v_page.dart';

/// Doodles tab: a placeholder on the shell until Phase 3.
class DoodlesPage extends StatelessWidget {
  const DoodlesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const VTabPage(
      title: 'Doodles',
      veil: false,
      children: [VFootnote('The doodle gallery (C29) lands in Phase 3.')],
    );
  }
}
