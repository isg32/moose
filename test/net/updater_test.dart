import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:moose/net/updater.dart';
import 'package:moose/platform/updater_channel.dart';

/// The phone, pretended: what is installed and what installing does.
class FakePlatform implements UpdatePlatform {
  int versionCode = 2037;
  bool canInstall = true;
  bool sameSigner = true;
  int apkVersionCode = 2038;
  final installs = <String>[];
  final _results = StreamController<InstallResult>.broadcast();

  void result(int code) => _results.add(InstallResult(code));

  @override
  Stream<InstallResult> get results => _results.stream;

  @override
  Future<Installed> info() async => Installed(
    versionCode: versionCode,
    versionName: '0.31.0',
    abi: 'arm64-v8a',
    canInstall: canInstall,
  );

  @override
  Future<ApkCheck> check(String path) async => ApkCheck(
    valid: true,
    package: 'com.isg32.moose',
    versionCode: apkVersionCode,
    sameSigner: sameSigner,
  );

  @override
  Future<void> openInstallSettings() async {}

  @override
  Future<void> install(String path) async => installs.add(path);
}

/// GitHub, pretended: the manifest, and the APK behind one redirect
/// (with Range support, and a connection that can drop part way).
class FakeGitHub extends http.BaseClient {
  FakeGitHub(this.apk, {this.version = '0.32.0', this.code = 2038});

  final List<int> apk;
  final String version;
  final int code;
  int? dropAfter;
  int manifestHits = 0;
  final ranges = <String?>[];
  String? shaOverride;

  Future<String> sha() async =>
      shaOverride ??
      (await Sha256().hash(apk)).bytes
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final url = request.url.toString();
    if (url == updateManifestUrl) {
      manifestHits++;
      final body = jsonEncode({
        'version': version,
        'notes': ['Moose updates itself', 'Smoother tabs'],
        'apks': {
          'arm64-v8a': {
            'url': 'https://github.com/x/releases/download/t/app.apk',
            'sha256': await sha(),
            'size': apk.length,
            'versionCode': code,
          },
        },
      });
      return http.StreamedResponse(Stream.value(utf8.encode(body)), 200);
    }
    if (url.contains('/releases/download/')) {
      return http.StreamedResponse(
        const Stream.empty(),
        302,
        headers: {'location': 'https://objects.example/app.apk'},
        isRedirect: true,
      );
    }
    // The CDN.
    final range = request.headers['range'];
    ranges.add(range);
    final from = range == null
        ? 0
        : int.parse(range.split('=')[1].split('-')[0]);
    final rest = apk.sublist(from);
    final drop = dropAfter;
    dropAfter = null;
    Stream<List<int>> body() async* {
      for (var i = 0; i < rest.length; i += 1000) {
        if (drop != null && i >= drop) {
          throw const SocketException('connection dropped');
        }
        yield rest.sublist(i, (i + 1000).clamp(0, rest.length));
      }
    }

    return http.StreamedResponse(body(), range == null ? 200 : 206);
  }
}

void main() {
  late Directory dir;
  late FakePlatform phone;
  late FakeGitHub github;
  late ProviderContainer c;
  var now = DateTime(2026, 11, 13, 12);
  final apk = List<int>.generate(25000, (i) => i % 251);

  ProviderContainer make() {
    final container = ProviderContainer(
      overrides: [
        updateDepsProvider.overrideWithValue(
          UpdateDeps(
            platform: phone,
            client: github,
            dir: () async => dir,
            now: () => now,
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  Updater up() => c.read(updaterProvider.notifier);
  UpdateState state() => c.read(updaterProvider);

  setUp(() {
    dir = Directory.systemTemp.createTempSync('moose-update-');
    phone = FakePlatform();
    github = FakeGitHub(apk);
    now = DateTime(2026, 11, 13, 12);
    c = make();
  });

  tearDown(() => dir.deleteSync(recursive: true));

  test('reads a manifest for the phone\'s ABI', () {
    final r = UpdateRelease.fromManifest({
      'version': '0.32.0',
      'notes': ['A', ' ', 'B'],
      'apks': {
        'arm64-v8a': {
          'url': 'u',
          'sha256': 'ABC',
          'size': 3,
          'versionCode': 2038,
        },
      },
    }, 'arm64-v8a')!;
    expect(r.version, '0.32.0');
    expect(r.notes, ['A', 'B']);
    expect(r.sha256, 'abc');
    expect(r.versionCode, 2038);
    expect(UpdateRelease.fromManifest({'apks': {}}, 'x86_64'), isNull);
  });

  test('nothing newer: up to date', () async {
    phone.versionCode = 2038;
    await up().check(manual: true);
    expect(state(), isA<UpdateUpToDate>());
  });

  test('finds, downloads, checks and installs an update', () async {
    await up().check(manual: true);
    expect(state(), isA<UpdateAvailable>());
    expect(state().release!.notes, contains('Smoother tabs'));

    await up().download();
    final ready = state() as UpdateReady;
    expect(File(ready.path).readAsBytesSync(), apk);

    await up().install();
    expect(phone.installs, [ready.path]);
    expect(state(), isA<UpdateInstalling>());
    phone.result(InstallResult.pendingUser);
    await pumpEventQueue();
    expect((state() as UpdateInstalling).confirming, isTrue);

    // Cancel on Android's screen: back to "Install".
    phone.result(InstallResult.aborted);
    await pumpEventQueue();
    expect(state(), isA<UpdateReady>());
  });

  test('a dropped download carries on where it stopped', () async {
    await up().check(manual: true);
    github.dropAfter = 12000;
    await up().download();
    expect(state(), isA<UpdateFailed>());
    expect((state() as UpdateFailed).message, contains('carry on'));

    await up().download();
    expect(state(), isA<UpdateReady>());
    expect(github.ranges.last, 'bytes=12000-');
    expect(File((state() as UpdateReady).path).readAsBytesSync(), apk);
  });

  test('a damaged download is thrown away', () async {
    github.shaOverride = 'deadbeef';
    await up().check(manual: true);
    await up().download();
    expect((state() as UpdateFailed).message, contains('damaged'));
    expect(
      dir.listSync(recursive: true).where((f) => f.path.endsWith('.apk')),
      isEmpty,
    );
  });

  test('signed differently: asks for one reinstall from GitHub', () async {
    phone.sameSigner = false;
    await up().check(manual: true);
    await up().download();
    final f = state() as UpdateFailed;
    expect(f.reinstall, isTrue);
  });

  test('asks for "Install unknown apps", then carries on by itself', () async {
    phone.canInstall = false;
    await up().check(manual: true);
    await up().download();
    await up().install();
    expect(state(), isA<UpdateNeedsPermission>());
    expect(phone.installs, isEmpty);

    // Back from Settings with it allowed.
    phone.canInstall = true;
    await up().resumed();
    expect(phone.installs, hasLength(1));
  });

  test('checks by itself at most every 6 hours', () async {
    await up().start();
    await pumpEventQueue();
    expect(github.manifestHits, 1);

    now = now.add(const Duration(hours: 1));
    await up().resumed();
    expect(github.manifestHits, 1);

    now = now.add(const Duration(hours: 6));
    await up().resumed();
    expect(github.manifestHits, 2);
  });

  test('after the update is in: what\'s new once, old APKs gone', () async {
    await up().check(manual: true);
    await up().download();
    await up().install();
    final path = (state() as UpdateInstalling).path;
    expect(File(path).existsSync(), isTrue);

    // Moose restarts as the new version.
    phone.versionCode = 2038;
    c = make();
    final whatsNew = await up().start();
    expect(whatsNew?.version, '0.32.0');
    expect(File(path).existsSync(), isFalse);

    c = make();
    expect(await up().start(), isNull);
  });

  test('a closed card stays closed for that version', () async {
    await up().check(manual: true);
    await up().dismiss();
    expect(c.read(dismissedUpdateProvider), '0.32.0');
    c = make();
    await up().start();
    expect(c.read(dismissedUpdateProvider), '0.32.0');
  });
}
