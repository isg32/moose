import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models.dart';

/// Where the chat hands off to the other features: attachments, stickers,
/// the media viewer and calls. Each is filled in as its feature lands.
class ChatHooks {
  const ChatHooks();

  static ChatHooks of(BuildContext context) => const ChatHooks();

  /// The attach sheet (C17); returns photos picked to send, if any.
  Future<List<Media>?> attach(BuildContext context, WidgetRef ref) async =>
      null;

  /// The gallery grid (C18), to add more photos to the strip.
  Future<List<Media>?> gallery(BuildContext context) async => null;

  /// The sticker, GIF and meme tray (S1, C26); returns what to send.
  Future<Body?> stickers(BuildContext context) async => null;

  /// The media viewer (C21) on [m]'s [index]th item.
  void openMedia(Message m, int index) {}

  /// Starts a call (K1).
  void call(BuildContext context, {required bool video}) {}
}
