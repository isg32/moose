import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:moose/core/theme/v_colors.dart';
import 'package:moose/data/models.dart';
import 'package:moose/mock/mock_data.dart';
import 'package:moose/net/local_store.dart';
import 'package:moose/net/wire.dart';

void main() {
  test('every message in the sample day survives the wire', () {
    for (final m in MockData.messages()) {
      final json = jsonDecode(
        jsonEncode(MessageEnvelope(m).toJson()),
      ) as Map<String, Object?>;
      final back = (Envelope.fromJson(json)! as MessageEnvelope).message;
      expect(back.id, m.id);
      expect(back.fromMe, isFalse, reason: 'it arrives from the partner');
      expect(back.at.toUtc(), m.at.toUtc());
      expect(back.body.runtimeType, m.body.runtimeType, reason: m.id);
      expect(back.quote().text, m.quote().text, reason: m.id);
      if (m.reply case final r?) expect(back.reply!.fromMe, !r.fromMe);
    }
  });

  test('bodies keep what the bubbles show', () {
    Body trip(Body b) => Wire.toBody(
      jsonDecode(jsonEncode(Wire.body(b))) as Map<String, Object?>,
    );
    expect((trip(const TextBody('hi 🥰')) as TextBody).text, 'hi 🥰');
    expect(
      (trip(const MomentBody(VMoment.hug)) as MomentBody).moment,
      VMoment.hug,
    );
    final music = trip(
      const MusicBody(MockData.sienna, start: Duration(seconds: 42)),
    ) as MusicBody;
    expect(music.song.videoId, MockData.sienna.videoId);
    expect(music.start, const Duration(seconds: 42));
    final sticker = trip(
      const StickerBody(
        Sticker.doodle(
          id: 's1',
          strokes: [
            Stroke(
              tool: PenTool.neon,
              argb: 0xFFFF5C7A,
              points: [Offset(0.1, 0.2), Offset(0.33333, 0.9)],
            ),
          ],
        ),
      ),
    ) as StickerBody;
    final p = sticker.sticker.strokes.single.points;
    expect(p.first, const Offset(0.1, 0.2));
    expect(p.last.dx, closeTo(0.3333, 0.0001));
    expect(sticker.sticker.strokes.single.tool, PenTool.neon);
    expect(
      (Wire.toBody({'t': 'hologram'}) as TextBody).text,
      contains('newer Moose'),
    );
  });

  test('receipts, typing and reactions', () {
    Envelope trip(Envelope e) => Envelope.fromJson(
      jsonDecode(jsonEncode(e.toJson())) as Map<String, Object?>,
    )!;
    final r = trip(
      const ReceiptEnvelope(['a', 'b'], Delivery.seen),
    ) as ReceiptEnvelope;
    expect(r.ids, ['a', 'b']);
    expect(r.state, Delivery.seen);
    expect((trip(const TypingEnvelope(true)) as TypingEnvelope).on, isTrue);
    final x = trip(const ReactEnvelope('m1', null)) as ReactEnvelope;
    expect(x.id, 'm1');
    expect(x.emoji, isNull);
    expect(Envelope.fromJson({'type': 'future-thing'}), isNull);
  });

  test('the conversation is kept on the phone across restarts', () async {
    final dir = await Directory.systemTemp.createTemp('moose-store');
    addTearDown(() => dir.delete(recursive: true));
    final store = await LocalStore.open(dir);
    expect(store.paired, isFalse);
    final day = MockData.messages();
    store
      ..myName = 'Sapan'
      ..messages = [
        ...day,
        Message(
          id: 'p',
          fromMe: true,
          at: DateTime.now(),
          body: const TextBody('on its way'),
          delivery: Delivery.pending,
        ),
      ];
    await store.flush();
    final again = await LocalStore.open(dir);
    expect(again.myName, 'Sapan');
    expect(again.messages, hasLength(day.length + 1));
    for (var i = 0; i < day.length; i++) {
      expect(again.messages[i].fromMe, day[i].fromMe);
      expect(
        again.messages[i].delivery,
        day[i].delivery == Delivery.pending ? Delivery.failed : day[i].delivery,
      );
      expect(again.messages[i].reactions.length, day[i].reactions.length);
      expect(again.messages[i].reply?.fromMe, day[i].reply?.fromMe);
    }
    expect(again.messages.last.delivery, Delivery.failed, reason: 'retry it');
  });
}
