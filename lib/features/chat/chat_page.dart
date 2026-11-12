import 'package:flutter/widgets.dart';

import '../../core/widgets/v_list.dart';
import '../../core/widgets/v_page.dart';

/// Chat tab: a placeholder on the shell until Phase 3.
class ChatPage extends StatelessWidget {
  const ChatPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const VTabPage(
      title: 'Chat',
      veil: false,
      children: [VFootnote('The conversation (C15) lands in Phase 3.')],
    );
  }
}
