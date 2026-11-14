# Moose: design spec

This is the spec the Flutter code follows. It is distilled from the **Moose Screens** canvas (a Claude Design artifact; its source is in [`canvas/`](canvas/)). When this file and the canvas disagree, the canvas wins on visuals and this file wins on behaviour. [`SCREENS.md`](SCREENS.md) lists every page and component.

| Path | What it is |
| --- | --- |
| `canvas/canvas.json` | The canvas index: board positions and titles. |
| `canvas/*.dc.html` | One board per file. Each screen board draws a dark-ink row and a light-ink row, and has wallpaper tweaks. |
| `SCREENS.md` | The inventory: every page, state and component. |
| `screens/*.png` | Each board rendered to PNG, for the README. Regenerate with `tool/design_render/render.sh`. |

## Boards

| Board | Covers |
| --- | --- |
| `Main` | Rules, type, the shared wallpapers, glass table, moment colours |
| `Icons` | The 48-icon line set |
| `Components` | A1–A10, both inks |
| `Bubbles` | B1–B12, both inks |
| `Onboarding`, `Pairing`, `Lock` | C1–C14 |
| `Chat`, `Composer`, `Attach`, `ChatSheets`, `MemeMusic` | C15–C28, B13, C44 |
| `Moments` | C25: Hug, Poke, Kiss, Miss you |
| `Calls` | K1–K5 |
| `Doodles` | C29–C35 |
| `Settings` | C36–C41 (About is copied from Idris) |
| `System` | C42–C43, empty and error states |
| `Stickers` | S1–S6 |

## Rules

1. **Two inks:** `#000000` and `#FFFFFF`, with no greys. Hierarchy comes from size, weight, outline vs fill, dashed vs solid, and inversion. Secondary text is Inter 300, not grey.
2. **The wallpaper decides the ink.** The couple's shared wallpaper sits behind every screen. Dark palettes get white ink and light ones get black ink, and the two are exact inverses. A photo wallpaper gets the ink that suits its brightness, and either partner can flip it.
3. **Every screen exists in both inks.** Build and test each one in both.
4. **Moment colours** are the only exception (see the table below).
5. **Media and camera surfaces stay dark** in both inks: the QR scanner, camera, round-video recorder and video call. The media viewer uses the paper colour.
6. **Translucency** is allowed only on these surfaces. They are the only alpha values in `VColors`.

| Surface | Dark ink | Light ink | Blur | Border |
| --- | --- | --- | --- | --- |
| Tab pill | white @ 0.10 | black @ 0.06 | 18 | 1 px ink |
| Glass card / incoming bubble | white @ 0.08 | black @ 0.05 | 16 | 1 px ink |
| Bottom sheet, popover, dialog | black @ 0.55 | white @ 0.60 | 14 | 1 px ink (sheets: top only) |
| Page veil (settings, full pages) | black @ 0.60 | white @ 0.60 | 30 | none |
| Scrim behind sheets and dialogs | black @ 0.40 | white @ 0.40 | 6 | none |
| Top / bottom progressive blur | paper @ 0.6 → 0 | same | ≤ 11 | none |
| Disabled action | whole element @ 0.35 | same | – | – |

**What the app does now (this replaces the Blur column):** live blur appears in exactly three places: the progressive edge blur at the top and bottom (`shaders/progressive_blur.frag`, drawn once by the shell), the frosted tab pill, and behind a moment burst (C25), where the chat blurs in through its sigma (0 → 18 over 420 ms). Everything else in the table has **no blur**:

- **Cards and the composer** are see-through paper at 55 %, or solid with Settings › Look › Solid panels.
- **Sheets** are always solid, so text never ghosts through them.
- **Page veils** are a copy of the wallpaper under the tint, opaque from the first frame.
- **Popups** dim what's behind them at 70 %.

A blur is never put inside an opacity or a fade, because it pops. Renders of the built screens are in [`docs/gallery.md`](../docs/gallery.md).

## Shared wallpapers (Cariño's palettes)

`night` (the default), `dune`, `moss`, `fog`, `ember` and `black` take white ink; `paper` and `white` take black ink. The base colours and blobs are Cariño's `VWallpapers`, copied as they are. Photo wallpapers add dim (0–100 %) and blur.

## Moment colours

| Moment | Emoji | Colour | Wash (centre of the screen) | Haptic |
| --- | --- | --- | --- | --- |
| Poke | 👉 | `#FFC15E` | `#FFC15E` @ 0.50 | Two quick taps |
| Hug | 🫂 | `#FF8FA3` | `#FF8FA3` @ 0.55 | One long swell that fades |
| Kiss | 💋 | `#FF5C7A` | `#FF5C7A` @ 0.55 | Short, short, flutter |
| Miss you | 🥺 | `#9DB2FF` | `#9DB2FF` @ 0.50 | Slow heartbeat |

**Burst (C25):**
- Layout: a radial wash in the moment colour over the scrim, then three rings in the colour. The outer ring is dashed and ripples outward (2.4 s); the middle ring is at 0.45; the inner ring is solid.
- Centre: a 112 px filled circle in the moment colour, with the line icon in black.
- Text: the word in Doto 900 / 58, then 'from Aatika · just now'.
- Buttons: an ink 'Hug back' and an outline 'Close'.
- Motion: the centre circle **beats like a heart** (scale 1 → 1.14 → 1 → 1.09 → 1 over 1.4 s, looping); it does not bob up and down. About 14 hearts drift up across the whole screen with sway and rotation (4.5–7 s each). Five of the gesture's own emoji float up more slowly and larger (7–9 s).

## Type

| Role | Font | Weight / size |
| --- | --- | --- |
| Wordmark | Doto | 900 / 62, line 0.9, `MO` / `OSE` |
| Page title | Doto | 700 / 34, line 1 |
| Hero number | Doto | 900 / 44–64 (codes, timers, storage) |
| Small number | Doto | 700 / 13–16 (times, durations, sizes) |
| Eyebrow | Inter | 500 / 11, +0.1 em, UPPERCASE |
| Body / bubble | Inter | 400 / 15, line 1.4 |
| Row title | Inter | 500 / 15 |
| Secondary | Inter | 300 / 12 |
| Button | Inter | 600 / 16 (primary), 500 / 15 (secondary) |
| Mono | ui-monospace | 400 / 11.5–12 |

## Layout and shape

- Gutters: 16 for cards and lists, 20 for titles, 14 for the message list.
- Radii: card 20, sheet 28 (top only), overlay card 28, bubble 20 with a 6 px tail corner, sticker tray tiles 12, pill and button 999.
- Tab pill: 12 from the sides, 22 from the bottom, 62 tall. The active tab is an ink pill with icon and label; inactive tabs are the icon only. There are three tabs: Chat, Doodles, Settings.
- Chat: the header (avatar, name, presence, voice call, video call, poke) sits on the top blur. The composer floats 96 px from the bottom, above the pill, on the bottom blur.
- Bubbles: outgoing are ink-filled with paper text; incoming are a glass card with a 1 px ink border. Stickers have no bubble: they get a white 4 px outline, a few degrees of tilt and a time chip underneath.

## Behaviour notes the canvas implies

- Long-press the chat wallpaper to open the shared theme sheet. Either partner can change it for both, and the last change wins. A system row records each change.
- Pokes have a 10 s cooldown per variant. In the picker, a variant on cooldown shows faded with its seconds left.
- Delivery ticks: a clock while sending, ✓ sent, ✓✓ delivered, a bold ✓✓ when seen, and a dashed bubble with Retry when it failed.
- Media say where they come from: 'from Aatika's phone' when direct (P2P), and the size with 'cloud' on the fallback.
- **Calls ring only while the partner's Moose is open.** Otherwise the call shows as 'no answer', and she gets a missed call at her next background check (up to 6 min).
