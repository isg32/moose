import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

/// One network route for everything that talks to YouTube.
///
/// YouTube signs each stream link for the address that asked for it and
/// refuses it (403) from any other. On mobile data, a phone often has IPv6
/// *and* IPv4 behind a carrier NAT whose public address can change from one
/// connection to the next (seen on Airtel: the first 1 MB downloads, the
/// next request is refused). So the request for a link and every download
/// of it leave by the same stable route: IPv6 when the phone has a public
/// IPv6 address (no NAT), else IPv4.
Future<InternetAddressType> preferredFamily() async {
  try {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv6,
    );
    for (final i in interfaces) {
      for (final a in i.addresses) {
        if (_isPublicV6(a)) return InternetAddressType.IPv6;
      }
    }
  } on Object {
    // Can't list interfaces: IPv4.
  }
  return InternetAddressType.IPv4;
}

bool _isPublicV6(InternetAddress a) {
  if (a.type != InternetAddressType.IPv6) return false;
  if (a.isLoopback || a.isLinkLocal || a.isMulticast) return false;
  // 2000::/3 is the global unicast range (this also rules out fc00::/7).
  return a.rawAddress.first & 0xe0 == 0x20;
}

/// An [HttpClient] that connects over [preferredFamily] when the host has
/// an address of that family, and normally otherwise.
HttpClient youtubeHttpClient() => HttpClient()
  ..connectionFactory = (uri, proxyHost, proxyPort) async {
    final family = await preferredFamily();
    List<InternetAddress> addresses = const [];
    try {
      addresses = await InternetAddress.lookup(uri.host, type: family);
    } on SocketException {
      // None of that family: connect normally below.
    }
    final port = uri.hasPort ? uri.port : (uri.scheme == 'https' ? 443 : 80);
    final Object target = addresses.isNotEmpty ? addresses.first : uri.host;
    final raw = await Socket.startConnect(target, port);
    if (uri.scheme != 'https') return raw;
    final secure = raw.socket.then(
      (s) => SecureSocket.secure(s, host: uri.host),
    );
    return ConnectionTask.fromSocket(secure, raw.cancel);
  };

/// The same route as a `package:http` client, for youtube_explode.
http.Client youtubeClient() => IOClient(youtubeHttpClient());
