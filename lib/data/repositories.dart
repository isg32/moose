import '../core/theme/v_colors.dart';
import 'models.dart';

/// Every source of data the screens read. Phase 3 backs each with a mock
/// (`lib/mock/`); Phase 4 swaps in the real one without touching a widget.

abstract interface class PairRepository {
  Pairing load();

  /// Your name (and, for real, your public key) on the server.
  Future<void> setName(String name);

  /// A fresh invite code for your person to type or scan (C5).
  Future<String> invite();

  /// Gives the pairing once someone joins your code; cancel to stop
  /// waiting. [mockAfter] is how long the pretend partner takes; the real
  /// server ignores it.
  Stream<Pairing> waitForPartner({required Duration mockAfter});

  /// Joins their code (C6): the pairing, or null when it has expired.
  Future<Pairing?> join(String code);

  /// Ends the pairing for both phones (C41).
  Future<void> unpair();
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

/// The partner is calling (K2).
class CallArrived extends ChatEvent {
  const CallArrived({required this.video});
  final bool video;
}

/// The partner reacted to message [id]; null took it back.
class ReactionChanged extends ChatEvent {
  const ReactionChanged(this.id, this.emoji);
  final String id;
  final String? emoji;
}

/// The server came or went (C44's banner).
class OnlineChanged extends ChatEvent {
  const OnlineChanged(this.online);
  final bool online;
}

/// The partner unpaired from their phone.
class Unpaired extends ChatEvent {
  const Unpaired();
}

/// The partner has a new phone and asks to be approved (C9).
class RepairRequested extends ChatEvent {
  const RepairRequested();
}

abstract interface class ChatRepository {
  List<Message> history();

  /// What the other phone does, as it happens.
  Stream<ChatEvent> get events;

  /// Hands a message to the outbox.
  void send(Message message);

  /// Your reaction on [id] is now [emoji] (null took it back).
  void react(String id, String? emoji);

  /// You started or stopped typing.
  void typing(bool on);

  /// The conversation changed; keep it on this phone.
  void store(List<Message> messages);

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
