import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'chat_theme.dart';

/// The couple's shared theme. Held in memory for now; Phase 3 reads it from
/// a mock repository and Phase 4 syncs it between both phones.
final chatThemeProvider = NotifierProvider<ChatThemeNotifier, ChatTheme>(
  ChatThemeNotifier.new,
);

class ChatThemeNotifier extends Notifier<ChatTheme> {
  @override
  ChatTheme build() => const ChatTheme();

  void set(ChatTheme theme) => state = theme;
}
