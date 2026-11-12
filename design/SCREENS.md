# Moose: screens and components

This is the full inventory of every page, and every component on each page, for the Moose design canvas. It is the brief for Claude Design and the checklist for building the UI: nothing gets drawn or built that isn't listed here, and nothing listed here is left out.

Design rules are the same as Veronica, Idris and Cariño: two inks only (`#000` / `#FFF`), Doto and Inter, glass surfaces, Cariño's progressive top and bottom blur, and the chat wallpaper as the only colour. Draw every page in **both inks**: each screen board has a dark-ink row and a light-ink row.

Example people: **Sapan** (you, he) and **Aatika** (your partner, she). The decoy chat's made-up name is **Neha**. The example song is **"Sienna" by The Marías**.

## A. Shared components (component sheet)
1. **Ink and type:** wordmark `MO/OSE` (Doto 900), page title, eyebrow, body, secondary, hero number, mono code.
2. **Glass surfaces:** top progressive blur (status bar), bottom progressive blur (behind composer and pill), tab pill, glass card, bottom sheet (top border only), overlay card, and full-screen scrim.
3. **Buttons:** primary (filled, plus a disabled state @0.35), secondary (outline), ghost/text, dashed (for 'add'), icon button (outline circle), FAB-style hold button (record), and destructive (inverted).
4. **Controls:** toggle, slider (dim, blur, glass, brush size), segmented control, stepper, checkbox row, radio row, wheel picker (Idris `v_wheel`), and progress bar and ring (Idris `v_progress`).
5. **Lists:** list row (title, subtitle, trailing chevron, toggle or value), section header, divider, and empty state (Doto line + secondary text + action).
6. **Inputs:** text field, search field (with clear), PIN dots (4–6), number keypad (0–9, delete, biometric slot left empty), and invite code boxes (6 chars).
7. **Feedback:** toast/snack, inline error, loading (dotted Doto spinner), skeleton row, confirm dialog (title, body, two buttons), and permission explainer card.
8. **Avatars and presence:** partner avatar (initial in a circle, or a photo), online dot, last-seen text, and typing indicator (three dots).
9. **Icons (`v_icons`):** send, mic, camera, round camera, image, attach/plus, meme, music, poke, doodle, theme, lock, settings, back, close, more, reply, react, copy, delete, download, play, pause, check, double-check, clock (pending), warning, eraser, lasso, undo, redo, pen tool icons ×9, QR, share, and swap camera.
10. **Tab pill:** two tabs (Chat, Doodles) + a settings dot, with active and inactive states and an unread badge on Chat.

## B. Message bubbles

Each bubble comes in outgoing and incoming. States: pending (clock), sent ✓, delivered ✓✓, seen ✓✓ filled, and failed with retry. Any bubble can carry a reply quote and reaction chips.

1. Text: short, long and multi-line, emoji-only (large), and a link.
2. Reply quote header, showing the quoted text, media thumb or music title.
3. Reaction chips row, and the reaction picker popover (6 emoji + 'more').
4. Photo: single, and a 2–4 grid. States: downloading (P2P 'from {partner}'s phone' vs cloud), progress, and failed.
5. Video: thumbnail + duration + play, with the same download states.
6. Round video note: a circle with a progress ring, playing and paused, and muted autoplay.
7. Voice note: play/pause, waveform, duration, and a played/unplayed dot.
8. Music clip: thumbnail, title, artist, 15 s range bar, and play. States: resolving, playing, and unavailable.
9. Meme/GIF/sticker: GIF autoplay, sticker without a bubble, and a 'via KLIPY / r/sub' caption.
10. Poke event (centred system row in its moment colour: '👉 Aatika poked you · 21:14'), plus hug, kiss and miss-you variants.
11. System rows: date divider, 'Theme changed by X', 'Wallpaper changed', 'Paired', 'New doodle: name', and 'Unread' divider.
12. Swipe-to-reply affordance (the reply icon reveals as you drag).
13. Message action sheet (long-press): reactions row, Reply, Copy, Save media, Delete for me, and Info (sent, delivered, seen times).

## C. Pages

*Onboarding and pairing*
1. **Splash:** the wordmark over the progressive blur.
2. **Welcome:** wordmark, one-line pitch, primary 'Start', and secondary 'I have a code'.
3. **Your name:** title, text field, avatar picker (initial or photo), and Continue.
4. **Background permission explainer:** why the 6-min check needs a foreground service, the notification preview, and Allow notifications / battery optimisation buttons, each showing a ✓ once done.
5. **Create pair:** the 6-char invite code (large Doto), QR, Share and Copy buttons, a 'Waiting for your person…' spinner, and the expiry countdown.
6. **Enter code:** code boxes, a 'Scan QR' button, error state, and Join.
7. **QR scanner:** camera view, frame, and close.
8. **Paired!:** both names joined by a heart line, a security-code fingerprint (emoji/number grid to compare), and 'Start chatting'.
9. **Re-pair request** (on the partner's phone): 'X has a new phone', fingerprint, Approve / Not them.
10. **Re-pair waiting** (on the new phone): spinner, 'Ask X to approve', and cancel.

*App lock*
11. **Set PIN:** enter, confirm, mismatch error.
12. **Set decoy PIN** (optional): an explainer, enter + confirm, must differ from the real PIN.
13. **Lock screen:** wordmark small, PIN dots, keypad, wrong-PIN shake, and a cooldown after 5 tries.
14. **Decoy chat:** looks like the chat page, but empty and with a fake partner name. Every action is inert.

*Chat (home tab)*
15. **Chat page:** the custom wallpaper (palette or photo, dim, blur) with the top blur. Header: partner avatar, name, presence/typing, and a poke button. Message list with all bubble types, date dividers and an unread divider. A jump-to-bottom button with an unread count. Bottom blur, then composer, then the tab pill.
16. **Composer:** states for idle (attach +, text field, meme, then mic or send), typing (send), replying (quote bar with ×), recording a voice note (hold: timer, waveform, slide to cancel, lock to hands-free), round video recording (circle preview, timer, swap camera, cancel), and sending media (thumbnail strip).
17. **Attach sheet:** Photo/Video (gallery), Camera, Round video, Music, Meme, Doodle (send a snapshot), and Poke.
18. **Media picker / gallery grid:** multi-select counters and a Send (n) button.
19. **Media preview before send:** image or video, caption field, remove, and Send.
20. **Camera capture:** shutter, hold for video, flip, flash, and close.
21. **Media viewer:** full screen, zoom, swipe between items, sender and time, Save and Share, and video controls.
22. **Theme sheet** (long-press the background): palette swatches grid (Cariño palettes), custom photo slot(s) (add, long-press to delete), dim slider, blur slider, glass strength slider, a live preview, 'Applies for both of you', and Apply.
23. **Wallpaper photo crop:** a crop frame with the chat preview overlay, plus Use.
24. **Poke picker** (long-press the poke button): four colour tiles (Poke, Hug, Kiss, Miss you) with emoji and label; a variant on cooldown is faded with its seconds left.
25. **Poke burst** (one per variant, received while open): the colour wash over a scrim, three rings in the moment colour (outer one ripples), a filled centre circle with the line icon that **pulses like a heartbeat**, the word in Doto (HUG), 'from Aatika · just now', ink 'Hug back' + outline 'Close', and the haptic note. Hearts drift up across the whole screen, and the gesture's emoji (🫂 👉 💋 🥺) floats gently up through the middle.
26. **Meme picker sheet:** search field, source toggle (KLIPY / Reddit), category chips (Trending, GIFs, Stickers, Memes, and subreddits), masonry grid, loading/empty/error states, and a preview before send.
27. **Music search sheet:** search field, results list (thumb, title, channel, duration), and loading/empty/error.
28. **Music range picker:** big thumb and title, scrolling waveform with a 15 s window, start/end time labels, play preview, and Send.

*Doodles tab*
29. **Doodle gallery:** title 'Doodles', grid of board cards (thumbnail, name, last edited by and when, 'live' dot when the partner is on it), a 'New doodle' dashed card, an empty state, and long-press to Rename / Delete / Send to chat.
30. **New doodle dialog:** name field and background choice (plain, dotted, lined, or a chat wallpaper).
31. **Doodle board:** canvas with pan and zoom, the partner's live cursor and avatar. Top bar: back, name, undo, redo, and more (export, send to chat, clear). The bottom tool dock is glass.
32. **Tool dock:** 9 tools (fine liner, marker, brush, pencil, calligraphy, neon, highlighter, eraser, lasso), with the selected state lifted.
33. **Tool options sheet:** size slider with a live stroke preview, opacity, smoothing (0–100), pressure toggle, and the stroke-end shape for calligraphy.
34. **Color sheet:** color wheel + brightness, a recent swatches row, a preset swatch grid, and a hex field.
35. **Lasso actions popover:** move, recolor, duplicate, and delete.

*Settings (via pill)*
36. **Settings:** profile row (name, avatar), Partner (name, paired since, fingerprint), Chat (enter to send, autoplay GIFs, media auto-download, and keep media), Notifications (poke sound per variant, message preview on or off, background check status), Privacy (app lock, change PIN, decoy PIN, lock after, hide in recents), Storage (media used, clear cache), and About.
37. **Partner detail:** avatar, name, paired date, security code, and Unpair (destructive with confirm).
38. **Storage page:** a breakdown by type (photos, videos, voice, round, doodles, wallpapers) with sizes, and clear-per-type.
39. **Notification settings:** channels list, poke sounds preview, and background service status (running / stopped + Fix).
40. **About** (copied from Idris): big app mark, 'Moose' in Doto 40, version, one line; LICENCES list (Doto, Inter, NewPipe Extractor, youtube_explode_dart, OkHttp, flutter_webrtc, cryptography, drift, just_audio, camera); DEVELOPER (photo, Sapan Gajjar, "You've probably guessed who made this app", GitHub isg32, LinkedIn sapangajjar101105); HELP (See a test crash report); footnote. The Settings row shows the mark, 'Moose' and 'Version 0.1.0 · licences, developer'.
41. **Unpair confirm:** what gets deleted, a type-to-confirm field, and Unpair.

*System surfaces*
42. **Notifications:** the ongoing service notification (quiet), a message notification (preview on or off), a poke heads-up per variant, and a re-pair request.
43. **Crash overlay** (copied from Cariño/Idris).
44. **Offline/error banner** at the top of the chat, and the 'partner's phone is offline, using cloud' hint on media.


## D. Moment colours (the one exception to two inks)

Used only in poke bursts, the poke picker, poke rows in the chat, poke notifications and the 'Send a hug' call button.

| Moment | Emoji | Colour | Haptic |
| --- | --- | --- | --- |
| Poke | 👉 | `#FFC15E` | Two quick taps |
| Hug | 🫂 | `#FF8FA3` | One long swell that fades |
| Kiss | 💋 | `#FF5C7A` | Short, short, flutter |
| Miss you | 🥺 | `#9DB2FF` | Slow heartbeat |

## E. Stickers

Stickers can be made from **doodles** and from **photos**, and are kept in a WhatsApp-style library.

- **S1 · Sticker tray** (the composer's sticker button): Stickers / GIFs / Memes switch, search, pack tabs (Recent, Favourites, each pack, + make), a 4-column grid, long-press to favourite or remove.
- **S2 · Sticker from a photo:** checkerboard canvas, auto cut-out with a white outline, tools (Auto cut, Erase, Restore, Text, Outline), Save and Send.
- **S3 · Sticker from a doodle:** lasso › Sticker (also on the lasso popover), preview with a white outline toggle, choose a pack, Save / Save and send.
- **S4 · Save a received sticker:** big preview, 'From Aatika · in her pack', Add to favourites, Save to my stickers, Save the whole pack.
- **S5 · Sticker library** (Settings › Stickers): count and size, make from a photo or a doodle, packs with thumbnails (Ours, Moose doodles, Cat chaos, Favourites).
- **S6 · Stickers in the chat:** no bubble, tilted a few degrees, white outline, time chip under it, reactions on stickers, and replying to a sticker.

## F. Calls (P2P, WebRTC)

- **K1 · Calling:** pulsing rings round the avatar, name, 'Ringing…', Mute / End / Speaker.
- **K2 · Incoming:** 'Video call · direct and encrypted', name, 'is calling you', 'Reply with a message', Decline / Accept.
- **K3 · Voice call:** timer in Doto, 'Direct, phone to phone · encrypted', signal bars, Mute / Speaker / Video / Send a hug / End / Chat.
- **K4 · Video call:** partner full screen, your own picture top right, glass control bar (Flip, Mute, Camera off, End). Always dark.
- **K5 · Calls in the chat:** voice and video call buttons in the header; call rows (done, missed with Call back, 'no answer: her Moose was closed').
