import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:moose/data/models.dart';
import 'package:moose/data/repositories.dart';
import 'package:moose/net/config.dart';
import 'package:moose/net/neon_backend.dart';
import 'package:moose/net/vault.dart';

/// Aatika as a bot, for end-to-end runs with one phone: she makes an
/// invite code, writes it to BOT_CODE_FILE, and once the phone joins she
/// answers like a person would, through the real Neon backend:
///
/// * a text: typing…, ❤️ on it, then a reply quoting it
/// * a moment: the same moment back
/// * a sticker or a song: "cute 🥺"
/// * "bye": "bye 👋", and she's done
///
/// Run by tool/e2e_neon.sh; skipped unless BOT_CODE_FILE is set.
void main() {
  final env = Platform.environment;
  final codeFile = env['BOT_CODE_FILE'] ?? '';

  setUpAll(() => HttpOverrides.global = null);

  test(
    'Aatika, the partner bot',
    skip: codeFile.isEmpty ? 'set BOT_CODE_FILE to run the partner bot' : null,
    () async {
      final dir = await Directory.systemTemp.createTemp('moose-bot');
      addTearDown(() => dir.delete(recursive: true));
      final me = await NeonBackend.open(
        NeonConfig(api: env['MOOSE_API_URL']!, auth: env['MOOSE_AUTH_URL']!),
        vault: MemoryVault(),
        dir: dir,
        label: 'e2e',
      );
      me.isOpen = () => true;
      addTearDown(me.store.flush);
      final pair = NeonPairRepository(me);
      await pair.setName('Aatika');
      final code = await pair.invite();
      await File(codeFile).writeAsString(code);
      log('code $code, waiting for the phone');

      final pairing = await pair
          .waitForPartner(mockAfter: Duration.zero)
          .first
          .timeout(const Duration(minutes: 10));
      log(
        'paired with ${pairing.partner.name} · '
        'code ${pairing.securityCode.take(3).join(' ')} …',
      );

      final chat = NeonChatRepository(me);
      addTearDown(chat.dispose);
      final got = <String>[];
      final done = Completer<void>();
      var n = 0;

      Message out(Body body, {Quote? reply}) => Message(
        id: 'bot-${n++}',
        fromMe: true,
        at: DateTime.now(),
        body: body,
        reply: reply,
      );

      final sub = chat.events.listen((e) async {
        switch (e) {
          case Incoming(:final message):
            final body = message.body;
            got.add(body.runtimeType.toString());
            log('got ${message.quote().text}');
            switch (body) {
              case TextBody(:final text) when text.toLowerCase() == 'bye':
                chat.send(out(const TextBody('bye 👋')));
                await Future<void>.delayed(const Duration(seconds: 2));
                if (!done.isCompleted) done.complete();
              case TextBody():
                chat.typing(true);
                await Future<void>.delayed(const Duration(milliseconds: 1500));
                chat.react(message.id, '❤️');
                chat.typing(false);
                chat.send(
                  out(const TextBody('on it 🥰'), reply: message.quote()),
                );
              case MomentBody(:final moment):
                await Future<void>.delayed(const Duration(seconds: 1));
                chat.send(out(MomentBody(moment)));
              case StickerBody() || MusicBody():
                chat.send(out(const TextBody('cute 🥺')));
              default:
                break;
            }
          case ReactionChanged(:final emoji):
            got.add('reaction $emoji');
            log('reaction $emoji');
          case DeliveryUpdate(:final id, :final delivery):
            if (delivery == Delivery.seen) got.add('seen $id');
          case Unpaired():
            log('unpaired');
            if (!done.isCompleted) done.complete();
          default:
            break;
        }
      });
      addTearDown(sub.cancel);

      await done.future.timeout(const Duration(minutes: 10));
      log('done: ${got.join(', ')}');
      expect(got, contains('TextBody'));
      expect(got, contains('MomentBody'));
      expect(got, contains('StickerBody'));
      expect(got, contains('reaction ❤️'));
      expect(got.where((g) => g.startsWith('seen ')), isNotEmpty);
    },
    timeout: const Timeout(Duration(minutes: 25)),
  );
}

void log(String s) {
  // ignore: avoid_print
  print('[bot ${DateTime.now().toIso8601String().substring(11, 19)}] $s');
}
