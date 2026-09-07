"""No-network tests of the exact native worker, with fake provider operations."""
import asyncio
import base64
import importlib.util
import io
import json
from pathlib import Path
import unittest
import uuid
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("archi_worker", ROOT / "desktop/Sources/ARCHiDesktop/Resources/ReactorBridge/worker.py")
module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)


class API:
    def __init__(self, rate=17, dollars=10000, closed=True): self.rate, self.dollars, self.closed, self.checks = rate, dollars, closed, []
    def pricing(self): return self.rate, self.dollars
    def termination(self, sid, jwt): self.checks.append((sid, jwt)); return self.closed


class SDK:
    def __init__(self): self.tokens, self.clients = [], []; self.worker = None
    def fetch_jwt(self, key, api, **constraints): self.tokens.append(constraints); return "fake-scoped-token"
    def Reactor(self, **kwargs):
        client = Client(self, kwargs); self.clients.append(client); return client


class Client:
    def __init__(self, sdk, kwargs):
        self.sdk, self.kwargs, self.commands = sdk, kwargs, []
        self.session_id = str(uuid.uuid4()); self.disconnected = False; self.closed = False
    def on(self, event, handler): pass
    def track(self, name): return self
    def on_raw_frame(self, handler): self.frame = handler
    async def connect(self): pass
    async def upload_file(self, png, **kwargs): return {"id": "fixture-file"}
    async def send_command(self, name, args):
        self.commands.append((name, args))
        if name == "start": self.sdk.worker.stop_event.set()
    async def disconnect(self): self.disconnected = True
    def close(self): self.closed = True


class WorkerTests(unittest.IsolatedAsyncioTestCase):
    def make(self, **api_args):
        events, sdk, api = [], SDK(), API(**api_args)
        worker = module.Worker(events.append, sdk=sdk, api=api); sdk.worker = worker
        return worker, events, sdk, api
    def start_input(self, **changes):
        image = Image.new("RGB", module.SIZE, (0, 255, 0)); buffer = io.BytesIO(); image.save(buffer, format="PNG")
        data = {"command": "start", "requestId": str(uuid.uuid4()), "durationSeconds": 15,
                "model": module.MODEL, "maximumCredits": 255, "maximumUSD": 0.0255, "cue": "working", "apiKey": "rk_fixture_key_only123",
                "prompt": "Match this synthetic fixture.", "referencePNG": base64.b64encode(buffer.getvalue()).decode()}
        data.update(changes); return data

    async def test_preflight_never_mints_or_allocates(self):
        worker, events, sdk, _ = self.make(); await worker.command({"command": "preflight", "requestId": str(uuid.uuid4())})
        self.assertEqual(sdk.tokens, []); self.assertEqual(sdk.clients, [])
        self.assertEqual(events[-1]["rateCreditsPerSecond"], 17)

    async def test_fresh_worker_start_rechecks_price_and_caps_one_owned_session(self):
        worker, events, sdk, api = self.make(); await worker.command(self.start_input()); await worker.task
        self.assertEqual(len(sdk.tokens), 1)
        self.assertEqual(sdk.tokens[0], {"models": [module.MODEL], "max_sessions": 1, "max_session_duration_seconds": 15, "expires_after": 120})
        self.assertEqual(len(sdk.clients), 1); self.assertTrue(sdk.clients[0].disconnected)
        self.assertTrue(events[-1]["terminationConfirmed"]); self.assertEqual(len(api.checks), 1)
        conditioning = next(args for name, args in sdk.clients[0].commands if name == 'set_conditioning')
        self.assertIn(module.CUES['working'], conditioning['prompt'])

    async def test_price_increase_fails_before_token(self):
        worker, events, sdk, _ = self.make(rate=18); await worker.command(self.start_input()); await worker.task
        self.assertEqual(sdk.tokens, []); self.assertEqual(sdk.clients, [])
        self.assertTrue(any(event["event"] == "error" for event in events))

    async def test_disconnect_success_is_not_termination_proof(self):
        worker, events, sdk, _ = self.make(closed=False); await worker.command(self.start_input()); await worker.task
        self.assertTrue(sdk.clients[0].disconnected); self.assertFalse(events[-1]["terminationConfirmed"])

    async def test_dollar_conversion_increase_fails_before_token(self):
        worker, events, sdk, _ = self.make(dollars=9000); await worker.command(self.start_input()); await worker.task
        self.assertEqual(sdk.tokens, []); self.assertEqual(sdk.clients, [])
        self.assertTrue(any(event['event'] == 'error' for event in events))

    async def test_stop_before_allocation_prevents_mint(self):
        worker, _, sdk, _ = self.make(); data = self.start_input(); owner = data["requestId"]
        await worker.command(data); await worker.command({"command": "stop", "requestId": owner}); await worker.task
        self.assertEqual(sdk.tokens, [])

    async def test_second_start_and_foreign_stop_do_not_create_or_steer_a_trial(self):
        worker, _, sdk, _ = self.make(); data = self.start_input(); await worker.command(data)
        await worker.command({"command": "stop", "requestId": str(uuid.uuid4())})
        self.assertFalse(worker.stop_event.is_set())
        await worker.task; await worker.command(self.start_input())
        self.assertEqual(len(sdk.clients), 1)

    async def test_invalid_inputs_and_missing_budget_never_allocate(self):
        for changes in [{"durationSeconds": 16}, {"durationSeconds": True}, {"model": "other"},
                        {"maximumCredits": float("inf")}, {"maximumCredits": True}, {"maximumCredits": None},
                        {"maximumUSD": None}, {"maximumUSD": True}, {"cue": "invented"},
                        {"referencePNG": "invalid"}, {"apiKey": "not-a-key"}, {"prompt": "line\nsecond"}]:
            worker, _, sdk, _ = self.make(); await worker.command(self.start_input(**changes))
            self.assertIsNone(worker.task); self.assertEqual(sdk.tokens, [])

    async def test_output_never_contains_credential_and_frames_retire_on_stop(self):
        worker, events, _, _ = self.make(); await worker.command(self.start_input()); await worker.task
        self.assertNotIn("rk_fixture", json.dumps(events))
        worker.raw_frame(bytes(module.SIZE[0] * module.SIZE[1] * 4), *module.SIZE)
        self.assertFalse(any(event["event"] == "frame" for event in events))

    def test_strict_input_rejects_duplicate_and_nonfinite_fields(self):
        for value in ['{"command":"stop","command":"start"}', '{"value":NaN}', '[]']:
            with self.assertRaises(ValueError): module.strict_object(value)


if __name__ == "__main__": unittest.main()
