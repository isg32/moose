# mockdata.md

This file lists every fake dataset in Moose. In Phase 3, every screen reads from a repository in `lib/data/repositories.dart` backed by a `Mock…Repository` in `lib/mock/`, and no widget hard-codes values. When Phase 4 wires a feature to real data, its **Status** flips from `Mock` to `Real`, and the mock is kept only for tests.

The values match the design canvas ([`design/DESIGN.md`](design/DESIGN.md)), so screens can be compared side by side. The sample data lives in `lib/mock/mock_data.dart`, and times are anchored to the moment it loads (`MockData.mockNow`).

**Example people:** Sapan (you, he) and Aatika (your partner, she). They have been paired since 14 Feb 2025.

**Mock PINs:** `1402` opens Moose and `2580` opens the decoy chat with Neha.

| Dataset | File | Used on | Contents | Status |
| --- | --- | --- | --- | --- |
| Pairing | `lib/mock/mock_repositories.dart` (`MockPairRepository`) | Chat header, Partner, Paired, Settings | Sapan and Aatika, paired since 14 Feb 2025, the 12-group security code, presence and last seen | Mock |
| Session | `lib/data/providers.dart` (`SessionNotifier`) | Lock, decoy chat, onboarding, unpair | Paired; locked with PIN `1402`; decoy PIN `2580` opens "Neha"; 5 wrong tries mean a 30 s wait | Mock |
| Conversation | `MockChatRepository`, `MockData.messages()` | Chat, bubbles, replies, reactions, media, calls | Last night and today: text, emoji-only, link, a reply, reactions, voice note, round video, a photo, a 7-photo grid, a video, "Sienna", a GIF, a sticker, a poke, a hug, a theme change, a cloud download in progress, ✓ / ✓✓ / pending ticks, a voice call | Mock |
| Fake partner | `MockChatRepository` | Chat | Your messages go ✓ → ✓✓ → seen. Every other text gets a typing indicator and a reply. A moment you send comes back as a burst | Mock |
| Shared theme | `lib/data/providers.dart` (`ChatThemeNotifier`) | Every screen, Theme sheet | Night wallpaper, no dim or blur, glass 50 % | Mock |
| Moments | `momentCooldownProvider`, `incomingMomentProvider` | Poke picker, bursts | One of each moment every 10 s | Mock |
| Doodles | `MockDoodleRepository` | Doodles, Board | Sunday plans (Aatika is on it), Our flat, Tic tac toe, Moose! | Mock |
| Stickers | `MockStickerRepository` | Sticker tray, library, chat | Packs Ours, Moose doodles and Cat chaos (from Aatika); favourites | Mock |
| Memes | `MockMemeRepository` | Meme picker | 16 GIFs, stickers, memes and clips from KLIPY and r/wholesomememes; searchable by title | Mock |
| Songs | `MockMusicRepository` | Music search, range picker, music bubbles | "Sienna" by The Marías and its versions, plus "Yellow" | Mock |
| Storage | `MockStorageRepository` | Settings, Storage | 1.4 GB across photos, videos, round videos, voice, doodles and wallpapers; 86 MB of cache | Mock |
| Settings | `lib/data/providers.dart` (`SettingsNotifier`) | Settings, Notifications | App lock on after 30 s, previews off, autoplay GIFs, download on Wi-Fi | Mock |
| Media art | `VMockArt` in `lib/core/theme/v_colors.dart` | Every photo, video, GIF, sticker and cover | Two-stop gradients from the canvas, standing in for real media | Mock |
