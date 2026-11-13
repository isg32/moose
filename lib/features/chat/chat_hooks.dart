import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models.dart';
import '../../data/providers.dart';
import '../../core/icons/v_icons.dart';
import '../calls/call_page.dart';
import '../common/choice_sheet.dart';
import '../common/overlay.dart';
import '../common/toast.dart';
import '../media/attach_sheet.dart';
import '../media/media_pages.dart';
import '../media/media_viewer.dart';
import '../moments/poke_picker.dart';
import '../music/music_pages.dart';
import '../stickers/sticker_maker.dart';
import '../stickers/tray.dart';

/// Where the chat hands off to the other features: attachments, stickers,
/// music, the media viewer and calls.
class ChatHooks {
  const ChatHooks();

  static ChatHooks of(BuildContext context) => const ChatHooks();

  /// The attach sheet (C17). Recent photos come back for the composer's
  /// strip; everything else is sent from here.
  Future<List<Media>?> attach(BuildContext context, WidgetRef ref) async {
    final choice = await showAttachSheet(context);
    if (choice == null || !context.mounted) return null;
    final partner = ref.read(pairingProvider).partner.name;
    final messages = ref.read(messagesProvider.notifier);
    switch (choice) {
      case AttachRecent(:final media):
        return media;
      case AttachTile(:final kind):
        switch (kind) {
          case AttachKind.gallery:
            final picked = await pickFromGallery(
              context,
              partner: partner,
              source: ref.read(mediaSourceProvider),
            );
            if (picked != null) _sendPicked(messages, picked);
          case AttachKind.camera:
            final shot = await takePhoto(
              context,
              partner: partner,
              source: ref.read(mediaSourceProvider),
            );
            if (shot != null) _sendPicked(messages, shot);
          case AttachKind.roundVideo:
            if (context.mounted) {
              showToast(
                context,
                'Tap the mic to switch to round video, then hold',
              );
            }
          case AttachKind.poke:
            final m = await showPokePicker(context, partner: partner);
            if (m != null) ref.read(momentCooldownProvider.notifier).send(m);
          case AttachKind.music:
            final body = await music(context);
            if (body != null) messages.send(body);
          case AttachKind.meme:
            final body = await stickers(context, startOnMemes: true);
            if (body != null) messages.send(body);
          case AttachKind.doodle:
            final body = await doodle(context, ref);
            if (body != null) messages.send(body);
        }
    }
    return null;
  }

  void _sendPicked(MessagesNotifier messages, PickedMedia p) {
    final caption = p.caption.isEmpty ? null : p.caption;
    final videos = p.media.where((m) => m.duration != null).toList();
    final photos = p.media.where((m) => m.duration == null).toList();
    if (photos.isNotEmpty) messages.send(PhotoBody(photos, caption: caption));
    for (final v in videos) {
      messages.send(VideoBody(v));
    }
  }

  /// The gallery grid (C18), to add more photos to the strip.
  Future<List<Media>?> gallery(BuildContext context) =>
      pushPage<List<Media>>(context, (_) => const GalleryPage());

  /// The sticker, GIF and meme tray (S1, C26); returns what to send.
  Future<Body?> stickers(BuildContext context, {bool startOnMemes = false}) =>
      showTray(context, start: startOnMemes ? TrayTab.gifs : TrayTab.stickers);

  /// Music search and the 15 s picker (C27, C28).
  Future<Body?> music(BuildContext context) => pickSong(context);

  /// A doodle sent as a sticker: pick the board, send its snapshot.
  Future<Body?> doodle(BuildContext context, WidgetRef ref) async {
    final doodles = ref.read(doodlesProvider);
    final d = await showChoiceSheet<Doodle>(
      context,
      title: 'Send a doodle',
      choices: [for (final d in doodles) Choice(d, d.name, icon: VIcon.doodle)],
    );
    if (d == null) return null;
    return StickerBody(
      Sticker.doodle(
        id: 'snap${DateTime.now().microsecondsSinceEpoch}',
        strokes: normalise(d.strokes),
      ),
    );
  }

  /// The media viewer (C21) on [m]'s [index]th item.
  void openMedia(BuildContext context, WidgetRef ref, Message m, int index) {
    final partner = ref.read(pairingProvider).partner.name;
    final all = ref.read(messagesProvider);
    final items = viewerItems(all, partner: partner);
    final before = viewerItems(
      all.takeWhile((x) => x.id != m.id).toList(),
      partner: partner,
    ).length;
    pushPage<void>(
      context,
      (_) => MediaViewer(
        items: items,
        start: (before + index).clamp(0, items.length - 1),
      ),
    );
  }

  /// Starts a call (K1).
  void call(BuildContext context, WidgetRef ref, {required bool video}) =>
      startCall(context, ref, video: video);
}
