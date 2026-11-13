"""Aatika's side of a call: aiortc (WebRTC in Python) on its own asyncio
loop. She sends a 440 Hz tone and, on a video call, a moving test card,
and counts what arrives from the phone."""

from __future__ import annotations

import asyncio
import fractions
import math
import threading
import time

import numpy as np
from aiortc import (
    MediaStreamTrack,
    RTCConfiguration,
    RTCIceServer,
    RTCPeerConnection,
    RTCSessionDescription,
)
from av import AudioFrame, VideoFrame

STUN = RTCConfiguration([RTCIceServer(urls=["stun:stun.l.google.com:19302"])])


class Tone(MediaStreamTrack):
    kind = "audio"

    def __init__(self) -> None:
        super().__init__()
        self.t = 0
        self.start = time.time()

    async def recv(self) -> AudioFrame:
        rate, n = 48000, 960  # 20 ms
        due = self.start + self.t / rate
        await asyncio.sleep(max(0, due - time.time()))
        k = np.arange(self.t, self.t + n)
        pcm = (np.sin(2 * math.pi * 440 * k / rate) * 6000).astype(np.int16)
        frame = AudioFrame.from_ndarray(pcm.reshape(1, -1), format="s16", layout="mono")
        frame.sample_rate = rate
        frame.pts = self.t
        frame.time_base = fractions.Fraction(1, rate)
        self.t += n
        return frame


class Card(MediaStreamTrack):
    kind = "video"

    def __init__(self) -> None:
        super().__init__()
        self.i = 0
        self.start = time.time()

    async def recv(self) -> VideoFrame:
        due = self.start + self.i / 15
        await asyncio.sleep(max(0, due - time.time()))
        img = np.zeros((360, 640, 3), np.uint8)
        img[:, :, 0] = 255
        img[:, :, 1] = 143
        img[:, :, 2] = 163  # moment pink
        x = (self.i * 8) % 640
        img[:, max(0, x - 20):x + 20, :] = 255  # a sweeping white bar
        frame = VideoFrame.from_ndarray(img, format="rgb24")
        frame.pts = self.i * 6000
        frame.time_base = fractions.Fraction(1, 90000)
        self.i += 1
        return frame


class CallSide:
    """One call at a time. Thread-safe entry points; WebRTC runs on a loop
    thread of its own."""

    def __init__(self) -> None:
        self.loop = asyncio.new_event_loop()
        threading.Thread(target=self.loop.run_forever, daemon=True).start()
        self.pc: RTCPeerConnection | None = None
        self.state = "new"
        self.got = {"audio": 0, "video": 0}
        self.connected_at: float | None = None

    def _run(self, coro, timeout: float = 30):
        return asyncio.run_coroutine_threadsafe(coro, self.loop).result(timeout)

    async def _new(self, video: bool) -> RTCPeerConnection:
        pc = RTCPeerConnection(STUN)
        self.pc, self.state, self.got = pc, "new", {"audio": 0, "video": 0}
        self.connected_at = None

        @pc.on("connectionstatechange")
        async def _changed() -> None:
            self.state = pc.connectionState
            if self.state == "connected" and self.connected_at is None:
                self.connected_at = time.time()

        @pc.on("track")
        def _track(track) -> None:
            async def drain() -> None:
                while True:
                    try:
                        await track.recv()
                    except Exception:  # noqa: BLE001 - the track ended
                        return
                    self.got[track.kind] += 1
            asyncio.ensure_future(drain())

        pc.addTrack(Tone())
        if video:
            pc.addTrack(Card())
        return pc

    def answer(self, sdp: str, kind: str, video: bool) -> tuple[str, str]:
        async def go():
            pc = await self._new(video)
            await pc.setRemoteDescription(RTCSessionDescription(sdp, kind))
            await pc.setLocalDescription(await pc.createAnswer())
            return pc.localDescription.sdp, pc.localDescription.type
        return self._run(go())

    def offer(self, video: bool) -> tuple[str, str]:
        async def go():
            pc = await self._new(video)
            await pc.setLocalDescription(await pc.createOffer())
            return pc.localDescription.sdp, pc.localDescription.type
        return self._run(go())

    def answered(self, sdp: str, kind: str) -> None:
        async def go():
            await self.pc.setRemoteDescription(RTCSessionDescription(sdp, kind))
        self._run(go())

    def wait_connected(self, seconds: float) -> bool:
        end = time.time() + seconds
        while time.time() < end:
            if self.state == "connected":
                return True
            if self.state in ("failed", "closed"):
                return False
            time.sleep(0.2)
        return False

    def close(self) -> None:
        if self.pc is not None:
            pc, self.pc = self.pc, None
            self._run(pc.close())
