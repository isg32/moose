import '../core/theme/v_colors.dart';
import 'models.dart';

/// Every source of data the screens read. Phase 3 backs each with a mock
/// (`lib/mock/`); Phase 4 swaps in the real one without touching a widget.

abstract interface class PairRepository {
  Pairing load();
}

/// Something that happened on the other phone.
sealed class ChatEvent {
  const ChatEvent();
}

/// A new message from the partner.
class Incoming extends ChatEvent {
  const Incoming(this.message);
  final Message message;
}

/// A sent message moved along (✓ → ✓✓ → seen).
class DeliveryUpdate extends ChatEvent {
  const DeliveryUpdate(this.id, this.delivery);
  final String id;
  final Delivery delivery;
}

/// The partner started or stopped typing.
class TypingChanged extends ChatEvent {
  const TypingChanged(this.typing);
  final bool typing;
}

/// A hug, poke, kiss or miss-you arrived while the app is open (C25).
class MomentArrived extends ChatEvent {
  const MomentArrived(this.moment);
  final VMoment moment;
}

abstract interface class ChatRepository {
  List<Message> history();

  /// What the other phone does, as it happens.
  Stream<ChatEvent> get events;

  /// Hands a message to the outbox.
  void send(Message message);

  void dispose();
}

abstract interface class DoodleRepository {
  List<Doodle> load();
}

abstract interface class StickerRepository {
  List<StickerPack> load();
}

abstract interface class MemeRepository {
  /// Trending when [query] is empty. [kind] null means everything.
  Future<List<Meme>> search(String query, MemeSource source, MemeKind? kind);
}

abstract interface class MusicRepository {
  Future<List<Song>> search(String query);
}

abstract interface class StorageRepository {
  List<StorageUse> load();

  /// Meme and song previews.
  int get cacheBytes;
}
