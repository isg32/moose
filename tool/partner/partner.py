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
  a theme           notes it
  "brb"             presses Home on the phone (adb), sends "you there?",
                    checks Firebase put a notification up, then reopens
                    Moose
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
        r = requests.request(method, self.api + path, json=body, timeout=30,
                             headers={"authorization": f"Bearer {self.token()}"})
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
        def run() -> None:
            while not self.done:
                url = self.neon.api.replace("https", "wss") + "/v1/live?token=" + self.neon.token()
                try:
                    ws = websocket.create_connection(url, timeout=30)
                    log("live socket up")
                    while not self.done:
                        frame = json.loads(ws.recv())
                        if frame.get("type") == "mail":
                            self.inbox.put(frame)
                except Exception as e:  # noqa: BLE001 - reconnect on anything
                    if not self.done:
                        log(f"socket dropped ({e.__class__.__name__}), reconnecting")
                        time.sleep(2)

        def poll() -> None:
            while not self.done:
                time.sleep(15)
                try:
                    for m in self.neon.call("GET", "/v1/mail"):
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
                    elif text == "back!":
                        self.check("phone took mail while away", True)
                elif kind == "moment":
                    self.check("phone's moment arrived", True, body["moment"])
                    time.sleep(1)
                    self.message({"t": "moment", "moment": body["moment"]}, kind="moment")
                elif kind == "sticker":
                    self.check("phone's sticker arrived", True)
                    self.text("cute 🥺")
                elif kind == "photo":
                    p = body["photos"][0]
                    data = aead_open(unb64(p["k"]), n.download(p["blob"]))
                    ok = data[:3] == b"\xff\xd8\xff" or data[:8] == b"\x89PNG\r\n\x1a\n"
                    self.check("phone's photo opened", ok, f"{len(data)} bytes, aspect {p['aspect']:.2f}")
                    n.call("DELETE", f"/v1/blobs?key={requests.utils.quote(p['blob'], safe='')}")
                    self.send_photo()
                    self.text("cute pic")
        self.check("seen receipts from the phone", "seen" in got)
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
