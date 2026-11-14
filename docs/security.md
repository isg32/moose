# Security and privacy

Moose is built so that **the server can route your messages but can't read them**, and so that what you've said lives on your two phones and nowhere else.

## What the server knows

| The server sees | The server never sees |
| --- | --- |
| That two hidden accounts are paired | Who you are (no email, phone number or contacts) |
| Each member's display name and X25519 public key | Any message, reaction, receipt or typing signal in plaintext |
| The coarse kind of each envelope (`msg`, `receipt`, `typing`, `moment`, `theme`, `doodle`, `rtc`, `call`) and when it was sent | Photos, videos, voice notes, stickers or wallpapers (only encrypted noise) |
| Each phone's FCM token | Your history: mail is deleted once it's delivered |
| Your IP address while connected | Your call audio and video (peer to peer) |

The display name is the one thing you type that the server stores in the clear, because the partner's phone needs it before any keys are exchanged.

## Identity

- On first launch, each phone makes an **X25519 key pair** (`Identity` in `lib/net/crypto.dart`). The private seed goes into the vault: the Android Keystore through flutter_secure_storage, or a private `vault.json` on Linux.
- The phone also signs up for a **hidden Neon Managed Auth account** with a generated email and password that are never shown (`lib/net/auth.dart`). It only exists so the API can tell members apart; the app sends its 15-minute JWT on each call.
- **There's no recovery, by design.** A new phone is a new identity. Re-pairing moves your place in the couple to the new phone, after your partner approves it. Your old history stays on the old phone.

## Sealing messages

```text
shared   = X25519(my private key, partner's public key)
key      = HKDF-SHA256(shared, salt = sorted(pubA, pubB) joined by "|", info = "moose/v1/mail") → 32 bytes
box      = XChaCha20-Poly1305(key, random 24-byte nonce, JSON envelope)
on wire  = base64(nonce ‖ ciphertext ‖ 16-byte tag)
```

- Both phones derive the same key without sending it anywhere. Sorting the public keys makes the salt the same on both sides.
- XChaCha20's 24-byte random nonces are safe to pick at random for every message.
- `Channel.open` throws if a box wasn't sealed with the pair's key or was changed on the way, so a tampered or foreign envelope is dropped, not shown.
- An envelope from a newer Moose that this one can't parse decodes to `null` and is skipped (`lib/net/wire.dart`).

**Limit:** the channel key is static for the life of the pairing. There's no ratchet, so someone who later gets a phone's private key could read mail they had recorded from the server while it was waiting. Mail is deleted on delivery, which narrows that window, but this isn't the forward secrecy a Signal-style protocol gives.

## Sealing media

Photos, videos, voice notes, round videos, photo stickers, profile pictures and photo wallpapers all take the same path:

1. The phone encrypts the file with a **fresh random XChaCha20-Poly1305 key** (`Channel.sealBlob`).
2. It asks the API for a presigned PUT URL under `c/<couple>/<uuid>` in the private `assets` bucket, and uploads the ciphertext in 64 KB chunks, reporting progress to the chat.
3. The blob's storage key and its **encryption key** travel inside a normal sealed message.
4. The receiver downloads it with a presigned GET, decrypts it, saves it locally, then **deletes the blob**.

The bucket only ever holds noise, and only for as long as it takes the other phone to fetch it. The API only signs URLs under the caller's own couple.

## Checking for a man in the middle

Both phones show a **security code** of twelve five-digit groups (screens C8 and C37):

```text
SHA-512("moose/v1/code|" + sorted(pubA, pubB) joined by "|") → first 60 bytes → 12 × (40-bit number mod 100000)
```

If the server swapped in its own key, the two phones would show different codes. Compare them once, in person or on a call. The code is in Settings › Partner.

**Re-pairing** (a lost or new phone): the new phone shows a code, and your partner types it in Settings › Partner › Their new phone. Before approving, their phone peeks at the invite (`GET /v1/invites/:code`) and shows the **new** security code, so they can check that it's really you.

## On the phone

| Protection | How |
| --- | --- |
| **Private storage** | History in `moose.json` and media files in app-private storage; secrets in the Keystore |
| **App lock** | A 4–6 digit PIN, kept in the vault. With a PIN set, Moose opens locked and locks again after the chosen time in the background. Five wrong tries mean a 30-second wait |
| **Decoy PIN** | A second PIN that opens an empty chat with a made-up name (default "Neha"). Every action there is inert, and it must differ from the real PIN |
| **Hide in recent apps** | Sets `FLAG_SECURE`: no thumbnail in Recents, and screenshots and screen recording are blocked |
| **Notification previews** | Off by default: a message notification just says "New message" |
| **Unpair** | A type-to-confirm sheet. It tells the server, then wipes the partner, the conversation and the account on this phone |

## Push and the background check

Firebase pushes are **data-only** and carry the sealed envelope (when it's under 3 KB), not plaintext. Google's FCM therefore sees the kind (`msg`, `moment` or `call`), the sender's display name and the time, but not the content. The phone opens it locally to decide what to show, such as "New message" or the moment's name, and the mail stays on the server until Moose opens and acks it. The background check also only **peeks**: it never takes or acks mail. See [Delivery](delivery.md).

## Calls

Calls are WebRTC, **peer to peer**, with DTLS-SRTP (WebRTC's built-in encryption). The offer, answer, decline and end messages that set a call up travel as sealed mail, so the server never sees the SDP. Moose uses Google's public STUN servers and **no TURN relay**, so media never passes through a server. The downside is that some strict networks (symmetric NAT, some mobile carriers) can't connect.

## Updates

The self-updater installs an APK only if its **size and SHA-256** match `update.json`, its **signer** matches the installed app, and its **versionCode** is higher. See [Releases](releases.md#over-the-air-updates).

## Secrets in this repo

The repo is public, so nothing secret is committed:

- `env.json`, `.env`, `backend/.env.local` and `backend/firebase-sa.json` are git-ignored.
- The release keystore lives outside the repo and reaches CI as a GitHub secret.
- `android/app/google-services.json` holds Firebase's client API key, which is public by design. It should be restricted in Google Cloud Console to package `com.isg32.moose` and the release signing SHA-256.

## Threat model in short

| Against | Moose holds up because |
| --- | --- |
| A curious or breached server | It only has ciphertext, public keys, names and timing |
| A network attacker | TLS to Neon, sealed bodies inside it, DTLS-SRTP for calls, and a security code to catch key swaps |
| Someone picking up your unlocked phone | App lock, a decoy PIN and Hide in recent apps |
| Someone with your unlocked phone **and** your PIN | Nothing; they can read everything on it, as with any messenger |
| Metadata analysis | Partly exposed: the server knows when each of you sends something, and what coarse kind it is |
