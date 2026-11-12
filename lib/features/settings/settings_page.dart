import 'package:flutter/widgets.dart';

import '../../core/widgets/v_list.dart';
import '../../core/widgets/v_page.dart';

/// Settings tab: a placeholder on the shell until Phase 3.
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const VTabPage(
      title: 'Settings',
      veil: true,
      children: [VFootnote('Settings (C36) lands in Phase 3.')],
    );
  }
}
