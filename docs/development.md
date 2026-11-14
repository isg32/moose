# Development

## Requirements

| Tool | Version | For |
| --- | --- | --- |
| Flutter | 3.47.9 (stable), Dart ^3.13 | The app |
| Android SDK, Java 17 | | Android builds |
| `clang`, `cmake`, `ninja`, GTK 3, `libmpv` | | The Linux build (media_kit plays audio and video through libmpv) |
| Node.js 22+ and the `neon` CLI | | The backend in `backend/` |
| Python 3 | | The e2e partner (`tool/partner`), the icon and design renders |
| Playwright's headless Chromium | | `tool/design_render/render.sh` |
| ImageMagick | | `tool/docs_renders.sh` |

## Mock mode

```bash
flutter pub get
flutter run
```

Without `env.json`, every repository is a mock (`lib/mock/`). The pretend partner, Aatika:

- answers your texts with a typing indicator and a reply;
- sends your moments back as bursts;
- answers calls after 3 seconds, and calls back if you write "call me";
- sends a re-pair request if you write "new phone".

On the mock, PIN `1402` opens Moose and `2580` opens the decoy chat. Invite `K7Q2MX` joins, `R3PA1R` plays the new-phone wait, and any other code has expired. All of this is listed in [`mockdata.md`](../mockdata.md).

## Real mode (Neon)

1. Set up the backend (see [`backend/README.md`](../backend/README.md)) and deploy it.
2. Copy `env.example.json` to `env.json` (git-ignored) and fill it in:

   ```json
   {
     "MOOSE_API_URL": "https://<branch-id>-api.compute.<region>.aws.neon.tech",
     "MOOSE_AUTH_URL": "https://<endpoint>.neonauth.<region>.aws.neon.tech/neondb/auth",
     "MOOSE_KLIPY_KEY": "<optional>"
   }
   ```

3. Build with it: `flutter run --dart-define-from-file=env.json`.

Other build-time defines:

| Define | Default | Does |
| --- | --- | --- |
| `MOOSE_UPDATE_URL` | The latest GitHub release's `update.json` | Where the updater looks |
| `MOOSE_CHECK_EVERY` | 360 (seconds) | The background check's interval |

### Firebase

Push needs `android/app/google-services.json` (committed; the client key is public by design) and, on the server, a service-account key at `backend/firebase-sa.json` (git-ignored). `npm run deploy` passes it to the Function as `FIREBASE_SA_B64`. Without Firebase, Moose still works: it just can't be woken, and relies on the live socket and the background check.

## On the phone

Use a **release-signed** build, as CI makes, so it installs over a release without wiping data:

```bash
export MOOSE_KEYSTORE_FILE=/path/to/release-key.jks \
       MOOSE_KEYSTORE_PASSWORD=… MOOSE_KEY_PASSWORD=… MOOSE_KEY_ALIAS=upload
flutter build apk --release --split-per-abi --target-platform android-arm64 --dart-define-from-file=env.json
adb install -r build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
```

- `adb install -r` keeps the app's data, so pairing and history survive. **Uninstalling wipes the identity**, and the phone has to pair again.
- Without the `MOOSE_*` signing variables, Gradle signs with the debug key, which can't be installed over a release-key install.
- Screenshots: `adb exec-out screencap -p > shot.png`.

## On Linux

The Linux build is a full second device: the same pairing and chat, against the same backend.

```bash
flutter build linux --debug --dart-define-from-file=env.json
build/linux/x64/debug/bundle/moose
```

| | Linux |
| --- | --- |
| App data | `~/.local/share/com.isg32.moose/` (`moose.json`, `vault.json`) |
| Cache | `~/.cache/com.isg32.moose/` |
| Secrets | `FileVault`: a private `vault.json`, because the desktop keyring isn't always reachable |
| Audio and video | media_kit (libmpv) |
| Not available | Push (no FCM on Linux), the background check, round video recording, ML Kit cut-outs, the camera QR scanner (type the code instead), and self-update. Share on the pair screen copies the code instead |

## Conventions

- **Cupertino only:** `CupertinoApp` and go_router, with `uses-material-design: false`. Don't import `package:flutter/material.dart`.
- **Colours only through `VColors`:** `test/design/no_banned_colors_test.dart` fails on any `Color(…)` outside `lib/core/theme/v_colors.dart`.
- **Text through `VText`:** Doto for titles and numbers, Inter for everything else. Colour comes from the surrounding `DefaultTextStyle`, which is how inversion works.
- **Blur in three places only:** the shell's edge blur, the tab pill, and behind a moment burst. Never put a blur inside an `Opacity` or a fade; animate the sigma instead.
- **Lists:** `GridView` and `ListView` need `padding: EdgeInsets.zero`, or they take the status-bar inset as a gap.
- **Covered pages stay mounted:** during a transition the old page goes to opacity 0; it's never swapped for a placeholder.
- **No stand-ins:** a value drawn straight into a widget (a progress bar, a time) goes in [`mockdata.md`](../mockdata.md) until it follows real data.
- **Both inks:** check every screen on a dark and a light wallpaper.
- **Comments say why**, in plain sentences, and doc comments reference the screen codes from `design/SCREENS.md`.

## Tests

```bash
flutter analyze        # must be clean
flutter test           # about 300 tests
```

| Suite | Covers |
| --- | --- |
| `test/*_test.dart` | Widget tests for every area on the mocks: chat, composer and keyboard, media, voice, stickers and music, doodles, calls, onboarding and QR, settings, the shell, step transitions, the update UI and the crash overlay |
| `test/net/` | Crypto (sealing, the security code), the wire format, local persistence, auth, push descriptions and the updater (manifest, ABI, verification) |
| `test/design/` | The banned-colour check |
| `test/neon/` | Live tests against a deployed branch. **Skipped** unless the Neon env is set |
| `integration_test/` | On a device: the app, focus, look, Neon, QR scanning and round video |
| `backend/test/e2e.ts` | The API end to end (`npm test` in `backend/`) |

Notes:

- `test/flutter_test_config.dart` loads the real fonts, so text measures the same as on the phone.
- `test/data_test.dart` "Aatika types and then replies" is timing-sensitive and can fail under load; rerun it.

### End to end with a real phone

```bash
tool/e2e_neon.sh     # needs env.json, backend/.env.local and a phone on adb
```

Moose runs on the phone, and Aatika is emulated in Python on this computer (`tool/partner/partner.py`, with `calls.py` using aiortc for WebRTC, in the venv at `tool/partner/.venv`). They meet only through the deployed backend. The phone's screen has to stay on for the whole run. Afterwards, `npm run cleanup` in `backend/` deletes the `e2e-…` test accounts.

## Renders

Two kinds of picture are committed:

| What | Source | Regenerate |
| --- | --- | --- |
| **App renders** (`docs/renders/*.webp`) | The real widgets on the mock data, drawn by the local peek harness in `test_peek/` (git-ignored) at 390 × 844, on the night and paper wallpapers | `tool/docs_renders.sh` (`--keep` to only convert) |
| **Design boards** (`design/screens/*.png`) | The design canvas, `design/canvas/*.dc.html` | `tool/design_render/render.sh` |

The peek harness loads Doto and Inter from `assets/fonts`, Noto Color Emoji and Noto Sans Mono from the system (`VText.fallback`), and fakes the status and gesture bars as both `padding` and `viewPadding`, as a phone reports them.

## Tools

| Path | Does |
| --- | --- |
| `tool/e2e_neon.sh` | The end-to-end journey against Neon with the Python partner |
| `tool/partner/` | The emulated partner: `partner.py` (pairing, mail, crypto) and `calls.py` (aiortc) |
| `tool/docs_renders.sh` | Refreshes `docs/renders/` |
| `tool/design_render/` | Renders the design canvas with headless Chromium and `dc-mini.js` |
| `tool/icon/make_icon.py` | Draws the launcher icon |
| `backend/scripts/` | `migrate.ts`, `cleanup.ts`, and `push-check.ts` (who has a push token; send a test push) |
