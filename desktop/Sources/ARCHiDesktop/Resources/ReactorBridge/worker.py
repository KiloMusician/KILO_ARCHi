"""ARCHi's owned, bounded Helios transport. NDJSON in/out; no browser or audio.

Preflight is public/read-only. Start mints one model-scoped token, permits one
session and caps its server lifetime at 15 seconds. There is no reconnect or
session adoption. SDK disconnect is followed by independent server read-back,
because SDK 1.4.0 suppresses coordinator termination errors internally.
"""
from __future__ import annotations

import asyncio
import base64
from collections import deque
import importlib.metadata
import io
import json
import logging
import math
import os
import platform
import re
import signal
import ssl
import sys
import threading
import time
import urllib.error
import urllib.request
import uuid

MODEL = "reactor/helios"
SDK_VERSION = "1.4.0"
API = "https://api.reactor.inc"
MAX_LINE = 2_000_000
MAX_PNG = 1_400_000
DURATION = 15
SIZE = (640, 384)
CUES = {
    "idle": "Almost still, a slow gentle breathing motion and occasional blink.",
    "working": "A subtle thoughtful tilt and quiet slow pulse of the existing chest light.",
    "responding": "A restrained attentive expression, tiny head movement, no speech or lip sync.",
    "ready": "One gentle acknowledging nod, then settle back into a calm idle pose.",
}
BOUNDARY = (
    "Keep the exact character, silhouette, face, colors and existing satellites from the reference. "
    "Locked camera, fixed scale and centered location. Solid uniform pure green RGB 0 255 0 background. "
    "No scenery, text, new objects, extra characters, scene transitions or camera motion. "
)


def valid_id(value):
    if not isinstance(value, str):
        return False
    try:
        return str(uuid.UUID(value)).lower() == value.lower()
    except (ValueError, AttributeError):
        return False


def strict_object(line):
    def unique(pairs):
        obj = {}
        for key, value in pairs:
            if key in obj:
                raise ValueError("duplicate field")
            obj[key] = value
        return obj
    value = json.loads(line, object_pairs_hook=unique,
                       parse_constant=lambda _: (_ for _ in ()).throw(ValueError("non-finite")))
    if not isinstance(value, dict):
        raise ValueError("object required")
    return value


class PublicAPI:
    """Fixed-origin TLS verified reads and one owned-session cleanup mutation."""
    def __init__(self):
        import certifi
        self.context = ssl.create_default_context(cafile=certifi.where())
        # The official token helper uses urllib's default verified context.
        os.environ["SSL_CERT_FILE"] = certifi.where()

    def request(self, path, method="GET", jwt=None):
        headers = {"Accept": "application/json"}
        if jwt is not None:
            headers["Authorization"] = "Bearer " + jwt
        request = urllib.request.Request(API + path, method=method, headers=headers)
        # Never follow credential-bearing redirects to another origin.
        class NoRedirect(urllib.request.HTTPRedirectHandler):
            def redirect_request(self, *args, **kwargs):
                return None
        opener = urllib.request.build_opener(NoRedirect(), urllib.request.HTTPSHandler(context=self.context))
        try:
            with opener.open(request, timeout=5) as response:
                raw = response.read(262145)
                if len(raw) > 262144:
                    raise ValueError("oversized response")
                return response.status, strict_object(raw) if raw else {}
        except urllib.error.HTTPError as exc:
            if exc.code == 404:
                return 404, {}
            raise RuntimeError("provider request failed") from None

    def pricing(self):
        status, data = self.request("/pricing")
        if status != 200:
            raise ValueError("pricing unavailable")
        dollars = data["settings"]["credits_per_dollar"]
        matches = [m for m in data["models"] if m.get("name") == "helios"]
        if len(matches) != 1:
            raise ValueError("model pricing ambiguous")
        rate = matches[0]["rate"]
        amount = rate["amount_per_sec"]
        if rate.get("unit") != "credits" or rate.get("denomination") != "second":
            raise ValueError("pricing unit changed")
        for value in (dollars, amount):
            if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value) or value <= 0:
                raise ValueError("invalid pricing")
        return amount, dollars

    def termination(self, session_id, jwt):
        if not valid_id(session_id) or not jwt:
            return False
        path = "/sessions/" + session_id
        def terminal(status, body):
            return status == 404 or (status == 200 and body.get("session_id") == session_id
                                     and body.get("state") in ("CLOSED", "INACTIVE"))
        status, body = self.request(path, jwt=jwt)
        if terminal(status, body):
            return True
        # Never touch a returned record whose identity disagrees with our owner.
        if status != 200 or body.get("session_id") != session_id:
            return False
        self.request(path, method="DELETE", jwt=jwt)
        status, body = self.request(path, jwt=jwt)
        return terminal(status, body)


class Output:
    """Bounded output independent of the event loop; newest pending frame only."""
    def __init__(self, stream):
        self.stream = stream
        self.condition = threading.Condition()
        self.controls = deque()
        self.frame = None
        self.running = True
        self.thread = threading.Thread(target=self._write, daemon=True)
        self.thread.start()

    def __call__(self, value):
        with self.condition:
            if value["event"] == "frame":
                self.frame = value
            else:
                if len(self.controls) >= 64:
                    # Fail closed instead of allowing unbounded IPC backlog.
                    self.running = False
                    return
                self.controls.append(value)
                if value["event"] in ("closed", "error") or value.get("state") == "closing":
                    self.frame = None
            self.condition.notify()

    def _write(self):
        while True:
            with self.condition:
                self.condition.wait_for(lambda: self.controls or self.frame or not self.running)
                if self.controls:
                    value = self.controls.popleft()
                elif self.frame:
                    value, self.frame = self.frame, None
                else:
                    return
            try:
                self.stream.write(json.dumps(value, separators=(",", ":"), allow_nan=False) + "\n")
                self.stream.flush()
            except (BrokenPipeError, OSError):
                return


class Worker:
    def __init__(self, emit, sdk=None, api=None, clock=time.monotonic):
        self.emit = emit
        self.sdk = sdk
        self.api = api
        self.clock = clock
        self.preflight_at = None
        self.owner = None
        self.used = False
        self.task = None
        self.stop_event = asyncio.Event()
        self.reason = "duration"
        self.client = None
        self.session_id = None
        self.jwt = None
        self.base_prompt = None
        self.cue = "idle"
        self.cue_event = asyncio.Event()
        self.generating = False
        self.frames = 0
        self.last_frame_at = -math.inf
        self.rate = None
        self.credits_per_dollar = None

    def event(self, event, **fields):
        self.emit({"event": event, "requestId": self.owner, **fields})

    async def preflight(self, request_id):
        ready = False
        rate = dollars = None
        error = None
        try:
            if self.sdk is None:
                if platform.machine() != "arm64" or importlib.metadata.version("reactor-sdk") != SDK_VERSION:
                    raise RuntimeError("runtime mismatch")
                import reactor_sdk
                from reactor_sdk._ffi import get_lib
                from PIL import Image
                get_lib()
                self.sdk = reactor_sdk
            ready = True
            if self.api is None:
                self.api = PublicAPI()
            rate, dollars = await asyncio.to_thread(self.api.pricing)
            self.rate = rate
            self.credits_per_dollar = dollars
            self.preflight_at = self.clock()
        except Exception:
            self.preflight_at = None
            error = "Reactor runtime or current public pricing could not be verified. Run the local runtime setup, then check again."
        self.emit({"event": "preflight", "requestId": request_id, "runtimeReady": ready,
                   "model": MODEL, "sdkVersion": SDK_VERSION, "rateCreditsPerSecond": rate,
                   "creditsPerUSD": dollars, "error": error})

    async def command(self, data):
        request_id = data.get("requestId")
        if not valid_id(request_id):
            return
        command = data.get("command")
        if command == "preflight":
            if self.task and not self.task.done():
                return
            await self.preflight(request_id)
        elif command == "start":
            if self.used or (self.task and not self.task.done()):
                self.emit({"event": "error", "requestId": request_id, "message": "This worker has already owned a trial. Start a fresh worker."})
                return
            try:
                if type(data.get("durationSeconds")) is not int or data["durationSeconds"] != DURATION:
                    raise ValueError("invalid duration")
                maximum = data.get("maximumCredits")
                if data.get("model") != MODEL or isinstance(maximum, bool) or not isinstance(maximum, (int, float)) or not math.isfinite(maximum) or maximum <= 0:
                    raise ValueError("invalid reviewed budget")
                maximum_usd = data.get("maximumUSD")
                if isinstance(maximum_usd, bool) or not isinstance(maximum_usd, (int, float)) or not math.isfinite(maximum_usd) or maximum_usd <= 0:
                    raise ValueError("invalid reviewed dollar budget")
                if data.get("cue") not in CUES:
                    raise ValueError("invalid activity cue")
                key = data.get("apiKey")
                prompt = data.get("prompt")
                if not isinstance(key, str) or not re.fullmatch(r"rk_[A-Za-z0-9_\-]{8,512}", key):
                    raise ValueError("invalid key")
                if not isinstance(prompt, str) or not 1 <= len(prompt.encode()) <= 2400 or any(ord(c) < 32 for c in prompt):
                    raise ValueError("invalid prompt")
                encoded = data.get("referencePNG")
                if not isinstance(encoded, str) or len(encoded) > MAX_PNG * 4 // 3 + 4:
                    raise ValueError("invalid reference")
                png = base64.b64decode(encoded, validate=True)
                if len(png) > MAX_PNG:
                    raise ValueError("oversized reference")
                from PIL import Image
                with Image.open(io.BytesIO(png)) as image:
                    if image.format != "PNG" or image.size != SIZE or image.mode != "RGB":
                        raise ValueError("invalid reference format")
                    image.verify()
            except Exception:
                self.emit({"event": "error", "requestId": request_id, "message": "Trial input or preflight is invalid. No session was started."})
                return
            self.owner, self.used = request_id, True
            self.cue = data["cue"]
            self.base_prompt = BOUNDARY + prompt + " "
            self.task = asyncio.create_task(self.run(key, png, maximum, maximum_usd))
            # Avoid keeping a second credential/reference copy in the command.
            data.pop("apiKey", None)
            data.pop("referencePNG", None)
        elif command == "stop" and request_id == self.owner:
            self.reason = "stopped"
            self.generating = False
            self.stop_event.set()
        elif command == "cue" and request_id == self.owner and not self.stop_event.is_set():
            cue = data.get("cue")
            if cue in CUES and cue != self.cue:
                self.cue = cue
                self.cue_event.set()

    async def interruptible(self, awaitable, timeout):
        operation = asyncio.ensure_future(awaitable)
        stopped = asyncio.create_task(self.stop_event.wait())
        done, _ = await asyncio.wait({operation, stopped}, timeout=timeout,
                                     return_when=asyncio.FIRST_COMPLETED)
        if stopped in done or operation not in done:
            operation.cancel()
            await asyncio.gather(operation, return_exceptions=True)
            stopped.cancel()
            if not self.stop_event.is_set():
                raise TimeoutError()
            raise asyncio.CancelledError()
        stopped.cancel()
        return await operation

    def raw_frame(self, raw, width, height, *_):
        now = self.clock()
        if not self.generating or self.stop_event.is_set() or now - self.last_frame_at < 1 / 6:
            return
        # Native Helios is 5:3. No stretching/cropping silently repairs a bad frame.
        if type(width) is not int or type(height) is not int or width < 1 or height < 1 or width > 2560 or height > 1536 or width * 3 != height * 5:
            return
        try:
            from PIL import Image
            if len(raw) != width * height * 4:
                return
            image = Image.frombytes("RGBA", (width, height), bytes(raw), "raw", "BGRA").convert("RGB")
            if image.size != SIZE:
                image = image.resize(SIZE, Image.Resampling.LANCZOS)
            output = io.BytesIO()
            image.save(output, format="PNG", compress_level=2)
            png = output.getvalue()
            if len(png) > MAX_PNG or not self.generating or self.stop_event.is_set():
                return
            self.last_frame_at = now
            self.frames += 1
            self.event("frame", sequence=self.frames, png=base64.b64encode(png).decode(), width=SIZE[0], height=SIZE[1])
        except Exception:
            return

    async def run(self, key, png, maximum, maximum_usd):
        began = self.clock()
        deadline = None
        try:
            self.event("state", state="connecting")
            # Native launches a fresh child for each trial. Refresh the public
            # rate in this child before any token/session operation.
            await self.preflight(self.owner)
            if (self.preflight_at is None or self.rate * DURATION > maximum
                    or self.rate * DURATION / self.credits_per_dollar > maximum_usd):
                raise ValueError("runtime, pricing or reviewed ceiling changed")
            if self.stop_event.is_set():
                raise asyncio.CancelledError()
            self.jwt = await self.interruptible(asyncio.to_thread(
                self.sdk.fetch_jwt, key, API, models=[MODEL], max_sessions=1,
                max_session_duration_seconds=DURATION, expires_after=120), 10)
            key = None
            if self.stop_event.is_set():
                raise asyncio.CancelledError()
            self.client = self.sdk.Reactor(model_name=MODEL, jwt=self.jwt)
            def owned_session(value):
                if valid_id(value) and self.session_id is None:
                    self.session_id = value
            self.client.on("session_id_changed", owned_session)
            self.client.track("main_video").on_raw_frame(self.raw_frame)
            # The local clock starts before allocation, never after READY. The
            # server's independent token cap still applies if this process dies.
            deadline = self.clock() + DURATION
            await self.interruptible(self.client.connect(), DURATION)
            owned_session(self.client.session_id)
            self.event("state", state="ready")
            async def remaining(operation):
                return await self.interruptible(operation, max(0, deadline - self.clock()))
            await remaining(self.client.send_command("set_sr_scale", {"sr_scale": "off"}))
            await remaining(self.client.send_command("set_image_strength", {"image_strength": 1.0}))
            reference = await remaining(self.client.upload_file(png, name="archi-reference.png", mime_type="image/png"))
            png = None
            await remaining(self.client.send_command("set_conditioning", {"prompt": self.base_prompt + CUES[self.cue], "image": reference}))
            await remaining(self.client.send_command("start", {}))
            self.generating = True
            self.event("state", state="generating")
            while self.clock() < deadline and not self.stop_event.is_set():
                try:
                    await self.interruptible(self.cue_event.wait(), min(0.25, max(0, deadline - self.clock())))
                    self.cue_event.clear()
                    await remaining(self.client.send_command("set_prompt", {"prompt": self.base_prompt + CUES[self.cue]}))
                except TimeoutError:
                    continue
        except asyncio.CancelledError:
            self.reason = "stopped"
        except TimeoutError:
            if deadline is None or self.clock() < deadline:
                self.reason = "failed"
                self.event("error", message="Reactor did not become ready within the trial limit.")
        except Exception:
            self.reason = "failed"
            self.event("error", message="The Reactor trial could not complete. Local artwork remains available.")
        finally:
            key = png = None
            self.generating = False
            self.stop_event.set()
            self.event("state", state="closing")
            confirmed = self.client is None  # No connect/allocation was invoked.
            if self.client is not None:
                if self.session_id is None:
                    candidate = self.client.session_id
                    if valid_id(candidate):
                        self.session_id = candidate
                try:
                    await asyncio.wait_for(self.client.disconnect(), timeout=5)
                except Exception:
                    pass
                if self.session_id is not None:
                    try:
                        confirmed = await asyncio.wait_for(asyncio.to_thread(self.api.termination, self.session_id, self.jwt), timeout=16)
                    except Exception:
                        confirmed = False
                self.client.close()
            self.jwt = self.base_prompt = None
            self.event("closed", terminationConfirmed=bool(confirmed), reason=self.reason,
                       framesDelivered=self.frames, durationSeconds=round(self.clock() - began, 3))

    async def shutdown(self):
        if self.task and not self.task.done():
            self.reason = "stopped"
            self.generating = False
            self.stop_event.set()
            await self.task


async def serve(output):
    worker = Worker(output)
    loop = asyncio.get_running_loop()
    stop = asyncio.Event()
    for sig in (signal.SIGTERM, signal.SIGINT):
        loop.add_signal_handler(sig, stop.set)
    reader = asyncio.StreamReader(limit=MAX_LINE)
    protocol = asyncio.StreamReaderProtocol(reader)
    await loop.connect_read_pipe(lambda: protocol, sys.stdin.buffer)
    try:
        while not stop.is_set():
            read = asyncio.create_task(reader.readline())
            stopped = asyncio.create_task(stop.wait())
            done, _ = await asyncio.wait({read, stopped}, return_when=asyncio.FIRST_COMPLETED)
            if stopped in done:
                read.cancel()
                break
            stopped.cancel()
            line = await read
            if not line or len(line) > MAX_LINE:
                break
            try:
                data = strict_object(line)
                await worker.command(data)
            except (ValueError, TypeError, UnicodeError):
                # Invalid input is never echoed, as it may contain credentials.
                continue
    finally:
        await worker.shutdown()


def main():
    # Own a dedicated protocol fd. Third-party/native logs cannot contaminate it
    # or leak credentials through stderr. The worker emits only generic errors.
    protocol = os.fdopen(os.dup(sys.stdout.fileno()), "w", buffering=1)
    null = os.open(os.devnull, os.O_WRONLY)
    os.dup2(null, sys.stdout.fileno())
    os.dup2(null, sys.stderr.fileno())
    os.close(null)
    logging.disable(logging.CRITICAL)
    output = Output(protocol)
    try:
        asyncio.run(serve(output))
    except Exception:
        pass
    finally:
        with output.condition:
            output.running = False
            output.condition.notify()
        output.thread.join(timeout=1)


if __name__ == "__main__":
    main()
