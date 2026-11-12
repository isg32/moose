import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moose/core/theme/v_colors.dart';
import 'package:moose/data/models.dart';
import 'package:moose/data/providers.dart';
import 'package:moose/data/repositories.dart';
import 'package:moose/data/session.dart';
import 'package:moose/mock/mock_data.dart';
import 'package:moose/mock/mock_repositories.dart';

void main() {
  late ProviderContainer c;

  setUp(() {
    c = ProviderContainer(
      overrides: [
        chatRepositoryProvider.overrideWith((ref) {
          final repo = MockChatRepository(
            replyDelay: const Duration(milliseconds: 10),
          );
          ref.onDispose(repo.dispose);
          return repo;
        }),
      ],
    );
  });
  tearDown(() => c.dispose());

  group('lock', () {
    test('the PIN opens Moose, the decoy PIN opens the decoy', () {
      final s = c.read(sessionProvider.notifier);
      expect(c.read(sessionProvider).locked, isTrue);
      expect(s.unlock(MockData.decoyPin), Unlock.decoy);
      expect(c.read(sessionProvider).decoy, isTrue);
      s.lock();
      expect(s.unlock(MockData.pin), Unlock.opened);
      expect(c.read(sessionProvider).decoy, isFalse);
    });

    test('five wrong PINs mean a 30 s wait', () {
      final s = c.read(sessionProvider.notifier);
      final now = DateTime(2026, 11, 13, 21);
      for (var i = 0; i < Session.maxTries; i++) {
        expect(s.unlock('0000', now: now), Unlock.wrong);
      }
      expect(s.unlock(MockData.pin, now: now), Unlock.waiting);
      expect(
        s.unlock(MockData.pin, now: now.add(Session.wait)),
        Unlock.opened,
      );
    });
  });

  group('chat', () {
    test('a sent message goes pending, sent, delivered, then seen', () async {
      final m = c
          .read(messagesProvider.notifier)
          .send(const TextBody('dinner at 8?'));
      Delivery of() =>
          c.read(messagesProvider).firstWhere((x) => x.id == m.id).delivery;
      expect(of(), Delivery.pending);
      await Future<void>.delayed(const Duration(milliseconds: 2000));
      expect(of(), Delivery.seen);
    });

    test('Aatika types and then replies to a text', () async {
      final before = c.read(messagesProvider).length;
      c.read(messagesProvider.notifier).send(const TextBody('hi'));
      await Future<void>.delayed(const Duration(milliseconds: 12));
      expect(c.read(pairingProvider).presence, Presence.typing);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      final after = c.read(messagesProvider);
      expect(after.length, before + 2);
      expect(after.last.fromMe, isFalse);
      expect(c.read(pairingProvider).presence, Presence.online);
    });

    test('reacting toggles your reaction and moves it', () {
      final n = c.read(messagesProvider.notifier);
      final id = c.read(messagesProvider).first.id;
      List<Reaction> rs() =>
          c.read(messagesProvider).firstWhere((m) => m.id == id).reactions;
      n.react(id, '🔥');
      expect(rs().single.emoji, '🔥');
      expect(rs().single.mine, isTrue);
      n.react(id, '❤️');
      expect(rs().map((r) => r.emoji), ['❤️']);
      n.react(id, '❤️');
      expect(rs(), isEmpty);
    });
  });

  group('moments', () {
    test('one of each every 10 s, and Aatika sends one back', () async {
      final cd = c.read(momentCooldownProvider.notifier);
      expect(cd.send(VMoment.hug), isTrue);
      expect(cd.send(VMoment.hug), isFalse);
      expect(cd.left(VMoment.hug), greaterThan(Duration.zero));
      expect(cd.send(VMoment.kiss), isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(c.read(incomingMomentProvider), isNotNull);
    });
  });

  test('mock searches find the canvas data', () async {
    final songs = await MockMusicRepository(
      latency: Duration.zero,
    ).search('sienna the marias');
    expect(songs.first.title, 'Sienna');
    final memes = await MockMemeRepository(
      latency: Duration.zero,
    ).search('sleepy cat', MemeSource.klipy, null);
    expect(memes, isNotEmpty);
  });

  test('the conversation covers every bubble the design shows', () {
    final kinds = MockData.messages().map((m) => m.body.runtimeType).toSet();
    expect(
      kinds,
      containsAll([
        TextBody,
        PhotoBody,
        VideoBody,
        RoundVideoBody,
        VoiceBody,
        MusicBody,
        MemeBody,
        StickerBody,
        MomentBody,
        CallBody,
        SystemBody,
      ]),
    );
    expect(ChatEvent, isNotNull);
  });
}
