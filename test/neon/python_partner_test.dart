import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:moose/core/theme/v_colors.dart';
import 'package:moose/data/chat_theme.dart';
import 'package:moose/data/models.dart';
import 'package:moose/data/repositories.dart';
import 'package:moose/net/config.dart';
import 'package:moose/net/neon_backend.dart';
import 'package:moose/net/vault.dart';

/// The app's network stack (lib/net, no screens) as the phone, against
/// Aatika emulated in Python (tool/partner/partner.py), through the
/// deployed backend. The two share no code, so this pins the protocol.
///
///   MOOSE_API_URL=… MOOSE_AUTH_URL=… flutter test test/neon/python_partner_test.dart
void main() {
  final env = Platform.environment;
  final api = env['MOOSE_API_URL'] ?? '';
  final auth = env['MOOSE_AUTH_URL'] ?? '';
  const py = 'tool/partner/.venv/bin/python';
  final skip = api.isEmpty || auth.isEmpty || !File(py).existsSync()
      ? 'needs MOOSE_API_URL, MOOSE_AUTH_URL and tool/partner/.venv'
      : null;

  setUpAll(() => HttpOverrides.global = null);

  test('pair and talk with the Python partner', skip: skip, () async {
    final tmp = await Directory.systemTemp.createTemp('moose-py');
    addTearDown(() => tmp.delete(recursive: true));
    final codeFile = File('${tmp.path}/code');
    final report = File('${tmp.path}/report.json');
    final partner = await Process.start(py, [
      'tool/partner/partner.py',
      '--code-file',
      codeFile.path,
      '--report',
      report.path,
    ]);
    final log = StringBuffer();
    partner.stdout.transform(utf8.decoder).listen(log.write);
    partner.stderr.transform(utf8.decoder).listen(log.write);
    addTearDown(partner.kill);

    for (var i = 0; i < 60 && !codeFile.existsSync(); i++) {
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    expect(codeFile.existsSync(), isTrue, reason: '$log');
    final code = codeFile.readAsStringSync();

    final b = await NeonBackend.open(
      NeonConfig(api: api, auth: auth),
      vault: MemoryVault(),
      dir: tmp,
      label: 'e2e',
    );
    addTearDown(b.store.flush); // before the folder goes
    b.isOpen = () => true;
    final pair = NeonPairRepository(b);
    await pair.setName('Sapan');
    final pairing = (await pair.join(code))!;
    expect(pairing.partner.name, 'Aatika');
    // Python's security code is the app's, digit for digit.
    for (
      var i = 0;
      i < 20 && !File('${tmp.path}/security_code.txt').existsSync();
      i++
    ) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    expect(
      File('${tmp.path}/security_code.txt').readAsStringSync(),
      pairing.securityCode.join(' '),
    );

    final chat = NeonChatRepository(b);
    addTearDown(chat.dispose);
    final events = chat.events.asBroadcastStream();
    final messages = <Message>[];
    final theme = <ChatTheme>[];
    final reactions = <String?>[];
    var typed = false;
    final ready = <String, String>{};
    events.listen((e) {
      switch (e) {
        case Incoming(:final message):
          messages.add(message);
        case ThemeChanged(theme: final t):
          theme.add(t);
        case ReactionChanged(:final emoji):
          reactions.add(emoji);
        case TypingChanged(typing: true):
          typed = true;
        case MediaReady(:final mediaId, :final path):
          ready[mediaId] = path;
        default:
          break;
      }
    });

    Future<void> until(String what, bool Function() done, [int s = 30]) async {
      final end = DateTime.now().add(Duration(seconds: s));
      while (!done()) {
        if (DateTime.now().isAfter(end)) fail('no $what\n$log');
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
    }

    var n = 0;
    Message out(Body body) => Message(
      id: 'py-${n++}',
      fromMe: true,
      at: DateTime.now(),
      body: body,
      delivery: Delivery.pending,
    );
    bool got(String text) => messages.any((m) => m.quote().text == text);

    await until('her theme', () => theme.isNotEmpty);
    expect(theme.last.wallpaper.builtin, 'dune');
    expect(theme.last.glass, 0.6);

    final hello = out(const TextBody('dinner at 8?'));
    chat.send(hello);
    await until('her reply', () => got('on it 🥰'));
    final reply = messages.firstWhere((m) => m.quote().text == 'on it 🥰');
    expect(reply.reply?.fromMe, isTrue);
    expect(reply.reply?.text, 'dinner at 8?');
    expect(reactions, contains('❤️'));
    expect(typed, isTrue);
    chat.react(reply.id, '❤️');

    chat.send(out(const MomentBody(VMoment.kiss)));
    await until(
      'her kiss',
      () => messages.any(
        (m) =>
            m.body is MomentBody &&
            (m.body as MomentBody).moment == VMoment.kiss,
      ),
    );

    chat.send(out(const StickerBody(Sticker.photo(id: 's1', art: 3))));
    await until('"cute 🥺"', () => got('cute 🥺'));

    // A real PNG, sealed into storage.
    final png = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAIAAAADCAIAAAA2iEnWAAAAFklEQVR4nGP8z8DAwMDAxMDAwMDAAAANHQEDK+mmyAAAAABJRU5ErkJggg==',
    );
    final file = File('${tmp.path}/mine.png')..writeAsBytesSync(png);
    chat.send(
      out(
        PhotoBody([
          Media(
            id: 'p1',
            art: 2,
            aspect: 2 / 3,
            bytes: png.length,
            path: file.path,
          ),
        ]),
      ),
    );
    await until('her photo', () => ready.isNotEmpty, 60);
    final hers = File(ready.values.single).readAsBytesSync();
    expect(hers.sublist(0, 3), [0xFF, 0xD8, 0xFF]);
    final photoMsg = messages.firstWhere((m) => m.body is PhotoBody);
    expect((photoMsg.body as PhotoBody).caption, 'for you 📸');
    expect(
      (photoMsg.body as PhotoBody).photos.single.aspect,
      closeTo(4 / 3, 0.01),
    );
    await until('"cute pic"', () => got('cute pic'));

    chat.shareTheme(const ChatTheme(wallpaper: WallpaperRef.builtin('moss')));
    chat.send(out(const TextBody('brb')));
    await until('"you there?"', () => got('you there?'), 60);
    chat.send(out(const TextBody('back!')));
    chat.send(out(const TextBody('bye')));
    await until('"bye 👋"', () => got('bye 👋'));

    expect(
      await partner.exitCode.timeout(const Duration(seconds: 60)),
      0,
      reason: '$log',
    );
    final checks = (jsonDecode(report.readAsStringSync()) as Map)
        .cast<String, Object?>();
    for (final MapEntry(:key, :value) in checks.entries) {
      expect((value! as Map)['ok'], isTrue, reason: key);
    }
    expect(
      checks.keys,
      containsAll([
        'phone\'s photo opened',
        'phone\'s theme arrived',
        'phone\'s ❤️ arrived',
      ]),
    );
    await b.store.flush();
  }, timeout: const Timeout(Duration(minutes: 6)));
}
