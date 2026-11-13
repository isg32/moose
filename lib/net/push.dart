import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:path_provider/path_provider.dart';

import '../core/theme/v_colors.dart';
import '../data/models.dart';
import '../features/moments/moment_burst.dart' show MomentCopy;
import 'crypto.dart';
import 'local_store.dart';
import 'vault.dart';
import 'wire.dart';

/// Firebase Cloud Messaging: the API sends a data-only wake-up when mail
/// lands, and this turns it into a notification. The sealed envelope rides
/// along, so the notification can say what kind of thing arrived; the mail
/// stays on the server until Moose opens and takes it.
abstract final class Push {
  static final _local = FlutterLocalNotificationsPlugin();

  static const messages = AndroidNotificationChannel(
    'messages',
    'Messages',
    description: 'New messages from your person',
    importance: Importance.high,
  );

  static const moments = AndroidNotificationChannel(
    'moments',
    'Pokes and hugs',
    description: 'Pokes, hugs, kisses and miss-yous, as they come',
    importance: Importance.max,
  );

  /// Sets up Firebase and the notification channels. [onWake] runs when a
  /// push arrives while Moose is open.
  static Future<void> init({required VoidCallback onWake}) async {
    await Firebase.initializeApp();
    FirebaseMessaging.onBackgroundMessage(_background);
    FirebaseMessaging.onMessage.listen((_) => onWake());
    await ready();
  }

  /// Takes down Moose's notifications.
  static Future<void> clear() => _local.cancelAll();

  /// Asks for the notification permission (Android 13+).
  static Future<bool> ask() async {
    final s = await FirebaseMessaging.instance.requestPermission();
    return s.authorizationStatus == AuthorizationStatus.authorized;
  }

  static Future<String?> token() async {
    try {
      // The registration token still works with HTTP v1 `message.token`;
      // FID direct-send (register/onRegistered) is the newer path.
      // ignore: deprecated_member_use
      return await FirebaseMessaging.instance.getToken();
    } on Object {
      return null; // No Play services, or offline: the poll still works.
    }
  }

  static Stream<String> get tokenChanges =>
      // ignore: deprecated_member_use
      FirebaseMessaging.instance.onTokenRefresh;

  /// Sets up local notifications and their channels (any isolate).
  static Future<void> ready() async {
    await _local.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );
    final android = _local
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await android?.createNotificationChannel(messages);
    await android?.createNotificationChannel(moments);
  }

  /// What the notification says for a push; null shows nothing.
  static Future<({String title, String body, bool moment})?> describe(
    Map<String, dynamic> data, {
    required Vault vault,
    required LocalStore store,
  }) async {
    final partner = store.partner;
    if (partner == null) return null;
    final name = partner.name.isEmpty ? 'Your person' : partner.name;
    final kind = data['kind'] as String?;
    final sealed = data['body'] as String?;
    Envelope? env;
    if (sealed != null) {
      try {
        final ch = await (await Identity.load(vault)).channelTo(partner.pubkey);
        env = Envelope.fromJson(await ch.openJson(sealed));
      } on Object {
        env = null; // Not from the partner: say nothing about it.
        return null;
      }
    }
    if (env case MessageEnvelope(:final message)) {
      return switch (message.body) {
        MomentBody(:final moment) => (
          title: name,
          body: '${moment.emoji} ${moment.row(fromMe: false, partner: name)}',
          moment: true,
        ),
        CallBody(:final video) => (
          title: name,
          body: video ? 'Video call' : 'Voice call',
          moment: true,
        ),
        // The text only with "Show message text" on (Settings ›
        // Notifications); otherwise just that something came.
        TextBody(:final text) when store.settings.showPreview => (
          title: name,
          body: text,
          moment: false,
        ),
        _ => (title: name, body: 'New message', moment: false),
      };
    }
    return switch (kind) {
      'moment' => (title: name, body: 'Sent you something 💗', moment: true),
      'call' => (title: name, body: 'Calling you', moment: true),
      _ => (title: name, body: 'New message', moment: false),
    };
  }

  /// [tag] groups notifications (one per tag and id); the background
  /// check uses its own.
  static Future<void> show(
    ({String title, String body, bool moment}) n, {
    required int id,
    String? tag,
  }) => _local.show(
    id: id,
    title: n.title,
    body: n.body,
    notificationDetails: NotificationDetails(
      android: AndroidNotificationDetails(
        n.moment ? moments.id : messages.id,
        n.moment ? moments.name : messages.name,
        channelDescription: n.moment
            ? moments.description
            : messages.description,
        importance: n.moment ? Importance.max : Importance.high,
        priority: Priority.high,
        category: n.moment
            ? AndroidNotificationCategory.social
            : AndroidNotificationCategory.message,
        color: n.moment ? VMoment.hug.color : null,
        // One notification per kind: a stream of messages stacks into one.
        tag: tag ?? (n.moment ? 'moment' : 'messages'),
      ),
    ),
  );
}

/// A push while Moose is in the background or closed: its own isolate.
@pragma('vm:entry-point')
Future<void> _background(RemoteMessage message) async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  await Push.ready();
  final store = await LocalStore.open(await getApplicationSupportDirectory());
  final n = await Push.describe(
    message.data,
    vault: const SecureVault(),
    store: store,
  );
  if (n != null) await Push.show(n, id: n.moment ? 2 : 1);
}
