#!/usr/bin/env python3
"""Aatika, a second Moose user emulated in Python, for end-to-end runs with
one phone. She speaks the app's protocol from scratch (it shares no code
with lib/net/): a hidden Neon Managed Auth account, an X25519 identity,
HKDF-SHA256, XChaCha20-Poly1305 sealed envelopes, the API Function, the
Realtime-fed live socket and sealed blobs in Neon object storage. So if
the app and this script agree, the protocol is what both sides think it is.

She makes an invite code (written to --code-file), waits for the phone to
join, then plays a script against whatever the phone sends:

  after pairing     changes the shared theme to "dune"
  a text            typing…, ❤️ on it, then "on it 🥰" quoting it
  a moment          the same moment back
  a sticker         "cute 🥺"
  a photo           downloads and opens it, then sends a photo back
  a voice note      downloads and opens it, then sends one back (a tone)
                    and a 3 s video (a test pattern)
  a video           downloads and opens it
  a theme           notes it
  doodles           makes her own board "Aatika's board"; when the phone
                    makes one and draws, she draws a heart on it too
  "brb"             presses Home on the phone (adb), sends "you there?",
                    checks Firebase put a notification up, then reopens
                    Moose
  a call            answers after 2 s with a tone (and a test card on video),
                    checks the call connected and the phone's audio (and
                    video) came through, then waits for the phone to end it
  "call me"         rings the phone (a voice call), checks it connected and
                    heard the phone, and hangs up after 5 s
  "lost your phone?" she gets a new phone: a new account and key make a
                    code, the old phone sends it, the phone approves it
                    (Settings › Partner › Their new phone), and the new
                    phone says hello under the new key
  "bye"             "bye 👋", and she's done

Every check lands in --report (JSON); the exit code is 0 only if all pass.

  tool/partner/.venv/bin/python tool/partner/partner.py --code-file /tmp/c
"""

from __future__ import annotations

import argparse
import base64
import hashlib
import io
import json
import os
import queue
import re
import subprocess
import sys
import threading
import time
import uuid
from datetime import datetime, timezone
from pathlib import Path

import requests
import websocket
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.kdf.hkdf import HKDF
from nacl import bindings as sodium
from nacl.public import PrivateKey
from PIL import Image, ImageDraw

sys.path.insert(0, str(Path(__file__).parent))
from calls import CallSide  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
ORIGIN = "http://localhost"  # Managed Auth trusts localhost by default.
APP_ID = "com.isg32.moose"


def log(msg: str) -> None:
    print(f"[aatika {datetime.now():%H:%M:%S}] {msg}", flush=True)


# ── Crypto: must match lib/net/crypto.dart byte for byte ────────────────

def b64(b: bytes) -> str:
    return base64.b64encode(b).decode()


def unb64(s: str) -> bytes:
    return base64.b64decode(s)


def aead_seal(key: bytes, plain: bytes) -> bytes:
    nonce = os.urandom(24)
    return nonce + sodium.crypto_aead_xchacha20poly1305_ietf_encrypt(plain, None, nonce, key)


def aead_open(key: bytes, box: bytes) -> bytes:
    return sodium.crypto_aead_xchacha20poly1305_ietf_decrypt(box[24:], None, box[:24], key)


class Identity:
    def __init__(self) -> None:
        self.private = PrivateKey.generate()
        self.public = b64(bytes(self.private.public_key))

    def channel_key(self, partner: str) -> bytes:
        shared = sodium.crypto_scalarmult(bytes(self.private), unb64(partner))
        salt = "|".join(sorted([self.public, partner])).encode()
        return HKDF(hashes.SHA256(), 32, salt=salt, info=b"moose/v1/mail").derive(shared)


def security_code(a: str, b: str) -> list[str]:
    h = hashlib.sha512(("moose/v1/code|" + "|".join(sorted([a, b]))).encode()).digest()
    return [str(int.from_bytes(h[i * 5:i * 5 + 5], "big") % 100000).zfill(5) for i in range(12)]


# ── Neon: Managed Auth and the API ──────────────────────────────────────

class Neon:
    def __init__(self, api: str, auth: str) -> None:
        self.api, self.auth = api.rstrip("/"), auth.rstrip("/")
        self.http = requests.Session()
        self.jwt = ""
        self.expires = 0.0
        self.user = ""

    def sign_up(self) -> None:
        email = f"e2e-{uuid.uuid4().hex[:24]}@moose.app"  # npm run cleanup finds these
        r = self.http.post(f"{self.auth}/sign-up/email", headers={"origin": ORIGIN},
                           json={"email": email, "password": os.urandom(24).hex(), "name": "moose"})
        r.raise_for_status()
        self.user = r.json()["user"]["id"]

    def token(self) -> str:
        if time.time() < self.expires - 60:
            return self.jwt
        r = self.http.get(f"{self.auth}/token")
        r.raise_for_status()
        self.jwt = r.json()["token"]
        claims = json.loads(base64.urlsafe_b64decode(self.jwt.split(".")[1] + "=="))
        self.expires = claims["exp"]
        return self.jwt

    def call(self, method: str, path: str, body: dict | None = None):
        # A network blip (DNS, a dropped connection) gets three more tries.
        for attempt in range(4):
            try:
                r = requests.request(method, self.api + path, json=body, timeout=30,
                                     headers={"authorization": f"Bearer {self.token()}"})
                break
            except requests.exceptions.ConnectionError:
                if attempt == 3:
                    raise
                time.sleep(2 * (attempt + 1))
        if r.status_code >= 300:
            raise RuntimeError(f"{method} {path}: {r.status_code} {r.text}")
        return r.json()

    def upload(self, sealed: bytes) -> str:
        j = self.call("POST", "/v1/blobs")
        requests.put(j["url"], data=sealed, timeout=60).raise_for_status()
        return j["key"]

    def download(self, key: str) -> bytes:
        j = self.call("GET", f"/v1/blobs?key={requests.utils.quote(key, safe='')}")
        r = requests.get(j["url"], timeout=60)
        r.raise_for_status()
        return r.content


# ── Aatika ──────────────────────────────────────────────────────────────

class Aatika:
    def __init__(self, neon: Neon, report: Path) -> None:
        self.neon = neon
        self.me = Identity()
        self.key = b""
        self.partner = {}
        self.inbox: queue.Queue = queue.Queue()
        self.seen_mail: set[str] = set()
        self.checks: dict[str, object] = {}
        self.report = report
        self.n = 0
        self.done = False
        self.calls = CallSide()
        self.call_id: str | None = None

    def check(self, name: str, ok: bool, detail: object = None) -> None:
        self.checks[name] = {"ok": bool(ok), "detail": detail}
        log(f"{'✓' if ok else '✗'} {name}" + (f" · {detail}" if detail is not None else ""))
        self.report.write_text(json.dumps(self.checks, indent=2, ensure_ascii=False))

    # Envelopes (lib/net/wire.dart).
    def post(self, kind: str, env: dict) -> dict:
        sealed = b64(aead_seal(self.key, json.dumps(env, ensure_ascii=False).encode()))
        return self.neon.call("POST", "/v1/mail", {"id": str(uuid.uuid4()), "kind": kind, "body": sealed})

    def message(self, body: dict, reply: dict | None = None, kind: str = "msg") -> dict:
        self.n += 1
        env = {"type": "msg", "id": f"aatika-{self.n}",
               "at": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"), "body": body}
        if reply:
            env["reply"] = reply
        return self.post(kind, env)

    def text(self, text: str, reply: dict | None = None) -> dict:
        return self.message({"t": "text", "text": text}, reply)

    # Mail in: the live socket (Realtime), with a poll behind it.
    def listen(self) -> None:
        gen = self.generation = getattr(self, "generation", 0) + 1
        neon = self.neon

        def run() -> None:
            while not self.done and gen == self.generation:
                url = neon.api.replace("https", "wss") + "/v1/live?token=" + neon.token()
                try:
                    ws = websocket.create_connection(url, timeout=30)
                    log("live socket up")
                    while not self.done and gen == self.generation:
                        frame = json.loads(ws.recv())
                        if frame.get("type") == "mail":
                            self.inbox.put(frame)
                except Exception as e:  # noqa: BLE001 - reconnect on anything
                    if not self.done:
                        log(f"socket dropped ({e.__class__.__name__}), reconnecting")
                        time.sleep(2)

        def poll() -> None:
            while not self.done and gen == self.generation:
                time.sleep(15)
                try:
                    for m in neon.call("GET", "/v1/mail"):
                        self.inbox.put(m)
                except Exception:  # noqa: BLE001
                    pass

        threading.Thread(target=run, daemon=True).start()
        threading.Thread(target=poll, daemon=True).start()

    def take(self) -> list[dict]:
        """Opens what arrived; acks it."""
        out, ack = [], []
        try:
            while True:
                m = self.inbox.get(timeout=0.5)
                ack.append(m["id"])
                if m["id"] in self.seen_mail:
                    continue
                self.seen_mail.add(m["id"])
                try:
                    out.append(json.loads(aead_open(self.key, unb64(m["body"]))))
                except Exception:  # noqa: BLE001
                    # Sealed for the old phone in the moment of a re-pair:
                    # the new phone can't open it, and rightly drops it.
                    if time.time() - getattr(self, "repaired_at", 0) < 15:
                        log(f"dropped a {m['kind']} sealed for the old phone")
                    else:
                        self.check("every envelope opens", False, m["kind"])
        except queue.Empty:
            pass
        if ack:
            self.neon.call("POST", "/v1/mail/ack", {"ids": ack})
        return out

    # The script.
    def photo(self) -> bytes:
        img = Image.new("RGB", (800, 600), (255, 143, 163))
        d = ImageDraw.Draw(img)
        for r in range(260, 0, -40):
            d.ellipse((400 - r, 300 - r, 400 + r, 300 + r), outline=(255, 255, 255), width=6)
        buf = io.BytesIO()
        img.save(buf, "JPEG", quality=85)
        return buf.getvalue()

    def send_photo(self) -> dict:
        data = self.photo()
        file_key = os.urandom(32)
        blob = self.neon.upload(aead_seal(file_key, data))
        media = {"id": f"aatika-photo-{self.n}", "art": 1, "aspect": 800 / 600, "bytes": len(data),
                 "blob": blob, "k": b64(file_key)}
        return self.message({"t": "photo", "photos": [media], "caption": "for you 📸"})

    @staticmethod
    def heart(cx: float, cy: float) -> dict:
        """A heart in board space (390 × 700), as Wire._stroke writes it."""
        import math
        pts = []
        for i in range(60):
            a = i / 59 * 2 * math.pi
            x = 16 * math.sin(a) ** 3
            y = -(13 * math.cos(a) - 5 * math.cos(2 * a) - 2 * math.cos(3 * a) - math.cos(4 * a))
            pts += [round((cx + x * 3) * 10000), round((cy + y * 3) * 10000)]
        return {"by": "me", "tool": "neon", "argb": 0xFFFF5C7A, "size": 4.0, "opacity": 1.0, "p": pts}

    def send_voice(self) -> dict:
        tmp = Path(self.report.parent) / "aatika-voice.m4a"
        subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-f", "lavfi", "-i",
                        "sine=frequency=523:duration=2", "-c:a", "aac", "-b:a", "64k", str(tmp)],
                       check=True, timeout=60)
        data = tmp.read_bytes()
        file_key = os.urandom(32)
        blob = self.neon.upload(aead_seal(file_key, data))
        wave = [int(30 + 60 * abs(((i * 7) % 20) - 10) / 10) for i in range(40)]
        return self.message({"t": "voice", "ms": 2000, "wave": wave, "blob": blob, "k": b64(file_key)})

    def send_video(self) -> dict:
        tmp = Path(self.report.parent) / "aatika-video.mp4"
        subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-f", "lavfi", "-i",
                        "testsrc=size=480x270:rate=24:duration=3", "-c:v", "libx264",
                        "-pix_fmt", "yuv420p", "-movflags", "+faststart", str(tmp)],
                       check=True, timeout=120)
        data = tmp.read_bytes()
        file_key = os.urandom(32)
        blob = self.neon.upload(aead_seal(file_key, data))
        media = {"id": f"aatika-video-{self.n}", "art": 4, "aspect": 480 / 270, "bytes": len(data),
                 "ms": 3000, "blob": blob, "k": b64(file_key)}
        return self.message({"t": "video", "video": media})

    def on_call(self, env: dict) -> None:
        op = env["op"]
        if op == "offer":
            log(f"the phone is calling ({'video' if env.get('video') else 'voice'})")
            time.sleep(2)  # ringing
            sdp, kind = self.calls.answer(env["sdp"], env.get("sdpType") or "offer", bool(env.get("video")))
            self.call_id = env["id"]
            self.post("call", {"type": "call", "op": "answer", "id": env["id"],
                               "video": bool(env.get("video")), "sdp": sdp, "sdpType": kind})
            ok = self.calls.wait_connected(25)
            self.check("phone's call connected", ok, self.calls.state)
            if ok:
                time.sleep(3)
                g = self.calls.got
                self.check("phone's audio came through", g["audio"] > 20, f"{g['audio']} frames")
                if env.get("video"):
                    self.check("phone's video came through", g["video"] > 5, f"{g['video']} frames")
        elif op == "answer" and env["id"] == self.call_id:
            self.calls.answered(env["sdp"], env.get("sdpType") or "answer")
        elif op in ("end", "decline") and env["id"] == self.call_id:
            log(f"the phone {'ended' if op == 'end' else 'declined'} the call")
            self.calls.close()
            self.call_id = None

    def ring_phone(self) -> None:
        call_id = str(uuid.uuid4())
        sdp, kind = self.calls.offer(video=False)
        self.call_id = call_id
        self.post("call", {"type": "call", "op": "offer", "id": call_id, "video": False,
                           "sdp": sdp, "sdpType": kind})
        log("ringing the phone")
        ok = self.calls.wait_connected(45)
        self.check("phone picked up her call", ok, self.calls.state)
        if not ok:
            return
        time.sleep(5)
        g = self.calls.got
        self.check("phone's audio came through on her call", g["audio"] > 20, f"{g['audio']} frames")
        self.post("call", {"type": "call", "op": "end", "id": call_id})
        self.calls.close()
        self.call_id = None
        log("hung up")

    def adb(self, *args: str) -> str:
        return subprocess.run(["adb", *args], capture_output=True, text=True, timeout=30).stdout

    def background_check(self, push_on: bool) -> None:
        log("pressing Home on the phone")
        self.adb("shell", "input", "keyevent", "KEYCODE_HOME")
        time.sleep(3)
        sent = self.text("you there?")
        if not push_on:
            self.check("push: wake-up sent", sent.get("pushed") == "disabled",
                       "push is off (no backend/firebase-sa.json): skipped")
        else:
            self.check("push: wake-up sent", sent.get("pushed") == "sent", sent.get("pushed"))
            shown = None
            for _ in range(30):
                dump = self.adb("shell", "dumpsys", "notification", "--noredact")
                block = [b for b in dump.split("NotificationRecord(") if f"pkg={APP_ID}" in b]
                hit = [b for b in block if "Aatika" in b and "New message" in b]
                if hit:
                    shown = hit[0]
                    break
                time.sleep(1)
            self.check("push: notification shown while backgrounded", shown is not None,
                       "Aatika · New message" if shown else "none in 30 s")
        log("bringing Moose back")
        self.adb("shell", "monkey", "-p", APP_ID, "-c", "android.intent.category.LAUNCHER", "1")

    def new_phone(self) -> None:
        """Her phone is gone: a new account and key, paired again through
        the phone's approval."""
        old_key = self.key
        neon = Neon(self.neon.api, self.neon.auth)
        me = Identity()
        neon.sign_up()
        neon.call("PUT", "/v1/me", {"name": "Aatika", "pubkey": me.public})
        code = neon.call("POST", "/v1/invites")["code"]
        log(f"new phone, code {code}")
        self.text(f"new phone code {code}")  # from the old phone, sealed with the old key
        deadline = time.time() + 180
        while time.time() < deadline:
            mine = neon.call("GET", "/v1/me")
            if mine.get("partner"):
                break
            time.sleep(2)
        else:
            self.check("phone approved the new phone", False, "not in 3 min")
            return
        self.neon, self.me = neon, me
        self.key = me.channel_key(mine["partner"]["pubkey"])
        self.repaired_at = time.time()
        self.check("phone approved the new phone", self.key != old_key,
                   " ".join(security_code(me.public, mine["partner"]["pubkey"])[:3]) + " …")
        self.listen()  # the old phone's socket is done with
        time.sleep(2)
        self.text("it's me, on my new phone 📱")

    def run(self, code_file: Path) -> int:
        n = self.neon
        n.sign_up()
        n.call("PUT", "/v1/me", {"name": "Aatika", "pubkey": self.me.public})
        code = n.call("POST", "/v1/invites")["code"]
        code_file.write_text(code)
        log(f"code {code}, waiting for the phone")
        push_on = bool(requests.get(n.api, timeout=30).json().get("push"))
        log(f"push is {'on' if push_on else 'off'}")

        deadline = time.time() + 600
        while time.time() < deadline:
            me = n.call("GET", "/v1/me")
            if me.get("partner"):
                break
            time.sleep(2)
        else:
            self.check("the phone joined", False)
            return 1
        self.partner = me["partner"]
        self.key = self.me.channel_key(self.partner["pubkey"])
        code12 = security_code(self.me.public, self.partner["pubkey"])
        self.check("the phone joined", True, f"{self.partner['name']} · {' '.join(code12[:3])} …")
        (self.report.parent / "security_code.txt").write_text(" ".join(code12))
        self.listen()
        time.sleep(3)
        self.post("theme", {"type": "theme", "theme": {"wallpaper": {"builtin": "dune", "photo": None},
                                                       "dim": 0.1, "blur": 0.0, "glass": 0.6, "ink": "auto"}})
        log("changed the theme to dune")
        self.post("doodle", {"type": "doodle", "op": "create", "id": "aatika-board",
                             "name": "Aatika's board", "paper": "dotted"})
        self.post("doodle", {"type": "doodle", "op": "add", "id": "aatika-board",
                             "strokes": [self.heart(80, 120)]})
        log("made a board and drew on it")

        got: set[str] = set()
        until = time.time() + 900
        while not self.done and time.time() < until:
            for env in self.take():
                t = env.get("type")
                if t == "receipt":
                    if env["state"] == "seen":
                        got.add("seen")
                    continue
                if t == "typing":
                    got.add("typing")
                    continue
                if t == "react":
                    self.check("phone's ❤️ arrived", env.get("emoji") == "❤️", env.get("emoji"))
                    continue
                if t == "doodle":
                    op = env["op"]
                    if op == "create":
                        self.check("phone's doodle board arrived", bool(env.get("name")), env.get("name"))
                    elif op in ("add", "set") and env.get("strokes"):
                        mine = [x for x in env["strokes"] if x.get("by") == "me"]
                        if not self.checks.get("phone's strokes arrived"):
                            self.check("phone's strokes arrived", len(mine) > 0,
                                       f"{len(mine)} stroke(s), {len(mine[0]['p']) // 2 if mine else 0} points")
                            self.post("doodle", {"type": "doodle", "op": "add", "id": env["id"],
                                                 "strokes": [self.heart(220, 380)]})
                            log("drew a heart on the phone's board")
                    elif op == "here":
                        got.add("here" if env.get("here") else "left")
                    continue
                if t == "call":
                    self.on_call(env)
                    continue
                if t == "theme":
                    w = env["theme"]["wallpaper"]
                    self.check("phone's theme arrived", w.get("builtin") == "moss", w)
                    continue
                if t != "msg":
                    continue
                body, mid = env["body"], env["id"]
                quote = {"fromMe": False, "text": body.get("text", "")}
                self.post("receipt", {"type": "receipt", "ids": [mid], "state": "seen"})
                kind = body["t"]
                log(f"got {kind}: {body.get('text', '')}")
                if kind == "text":
                    text = body["text"].strip().lower()
                    if text == "bye":
                        self.text("bye 👋")
                        self.done = True
                    elif text == "brb":
                        self.background_check(push_on)
                    elif text == "dinner at 8?":
                        self.post("typing", {"type": "typing", "on": True})
                        time.sleep(1.5)
                        self.post("receipt", {"type": "react", "id": mid, "emoji": "❤️"})
                        self.post("typing", {"type": "typing", "on": False})
                        self.text("on it 🥰", reply=quote)
                    elif text == "lost your phone?":
                        self.new_phone()
                    elif text == "call me":
                        threading.Thread(target=self.ring_phone, daemon=True).start()
                    elif text == "back!":
                        self.check("phone took mail while away", True)
                elif kind == "moment":
                    self.check("phone's moment arrived", True, body["moment"])
                    time.sleep(1)
                    self.message({"t": "moment", "moment": body["moment"]}, kind="moment")
                elif kind == "sticker":
                    self.check("phone's sticker arrived", True)
                    self.text("cute 🥺")
                elif kind == "voice":
                    data = aead_open(unb64(body["k"]), n.download(body["blob"]))
                    self.check("phone's voice note opened", data[4:8] == b"ftyp",
                               f"{len(data)} bytes, {body['ms'] / 1000:.1f} s")
                    n.call("DELETE", f"/v1/blobs?key={requests.utils.quote(body['blob'], safe='')}")
                    self.send_voice()
                    self.send_video()
                elif kind == "video":
                    v = body["video"]
                    data = aead_open(unb64(v["k"]), n.download(v["blob"]))
                    self.check("phone's video opened", data[4:8] == b"ftyp",
                               f"{len(data)} bytes, {v.get('ms', 0) / 1000:.1f} s")
                    n.call("DELETE", f"/v1/blobs?key={requests.utils.quote(v['blob'], safe='')}")
                elif kind == "photo":
                    p = body["photos"][0]
                    data = aead_open(unb64(p["k"]), n.download(p["blob"]))
                    ok = data[:3] == b"\xff\xd8\xff" or data[:8] == b"\x89PNG\r\n\x1a\n"
                    self.check("phone's photo opened", ok, f"{len(data)} bytes, aspect {p['aspect']:.2f}")
                    n.call("DELETE", f"/v1/blobs?key={requests.utils.quote(p['blob'], safe='')}")
                    self.send_photo()
                    self.text("cute pic")
        self.check("seen receipts from the phone", "seen" in got)
        self.check("phone said it was on the board", "here" in got and "left" in got)
        self.done = True
        failed = [k for k, v in self.checks.items() if not v["ok"]]
        log("all checks passed" if not failed else f"FAILED: {failed}")
        return 0 if not failed else 1


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--code-file", type=Path, required=True)
    ap.add_argument("--report", type=Path, default=ROOT / "build" / "e2e_partner.json")
    args = ap.parse_args()
    env = json.loads((ROOT / "env.json").read_text())
    args.report.parent.mkdir(parents=True, exist_ok=True)
    return Aatika(Neon(env["MOOSE_API_URL"], env["MOOSE_AUTH_URL"]), args.report).run(args.code_file)


if __name__ == "__main__":
    sys.exit(main())
