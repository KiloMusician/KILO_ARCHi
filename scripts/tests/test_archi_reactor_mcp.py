import importlib.util
import io
import json
import os
from pathlib import Path
import socket
import tempfile
import threading
import unittest
from unittest.mock import patch

SCRIPT = Path(__file__).resolve().parents[1] / "archi-reactor-mcp.py"
spec = importlib.util.spec_from_file_location("archi_reactor_mcp", SCRIPT)
mcp = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mcp)


class ReactorMCPTests(unittest.TestCase):
    def request(self, method, params=None):
        return {"jsonrpc": "2.0", "id": 7, "method": method, "params": params or {}}

    def test_initialize_and_discovery_are_provider_free(self):
        def forbidden(*_):
            self.fail("Discovery must not contact the native owner or a provider")
        initialized = mcp.process(self.request("initialize", {"protocolVersion": "2025-03-26"}), "review", forbidden)
        self.assertEqual(initialized["result"]["protocolVersion"], "2025-03-26")
        listed = mcp.process(self.request("tools/list"), "review", forbidden)["result"]["tools"]
        self.assertEqual([t["name"] for t in listed], list(mcp.ACTIONS))
        self.assertTrue(all(t["inputSchema"]["additionalProperties"] is False for t in listed))
        self.assertTrue(all("Local" in t["description"] or "local" in t["description"] or "app-owned" in t["description"] for t in listed))

    def test_each_tool_reaches_only_matching_native_action(self):
        calls = []
        for name, (action, _) in mcp.ACTIONS.items():
            result = mcp.process(self.request("tools/call", {"name": name, "arguments": {}}), "preview",
                                 lambda received, profile: calls.append((received, profile)) or {"ok": True, "state": "localPreview"})
            self.assertFalse(result["result"]["isError"])
            self.assertEqual(calls[-1], (action, "preview"))
        self.assertEqual(len(calls), 4)

    def test_live_and_credential_requests_never_reach_owner(self):
        def forbidden(*_):
            self.fail("Unsupported/credential requests must not reach the owner")
        for params in [{"name": "reactor_start"}, {"name": "reactor_preview", "arguments": {"apiKey": "PRIVATE"}},
                       {"name": "reactor_prepare", "apiKey": "PRIVATE"}, {"name": "reactor_status", "arguments": []}]:
            response = mcp.process(self.request("tools/call", params), "review", forbidden)
            self.assertEqual(response["error"]["code"], -32602)
            self.assertNotIn("PRIVATE", json.dumps(response))

    def test_private_or_oversize_native_response_is_not_exposed(self):
        for value in [{"nested": {"api_key": "PRIVATE"}}, {"cookie": "PRIVATE"}, {"text": "x" * mcp.MAX_BYTES}]:
            response = mcp.process(self.request("tools/call", {"name": "reactor_status"}), "review", lambda *_: value)
            self.assertTrue(response["result"]["isError"])
            self.assertNotIn("PRIVATE", json.dumps(response))
            self.assertLess(len(json.dumps(response)), 1000)

    def test_stdin_recovers_after_malformed_duplicate_and_oversize_messages(self):
        valid = json.dumps(self.request("ping")).encode() + b"\n"
        source = io.BytesIO(b"not-json\n" + b'{"id":1,"id":2}\n' + b"x" * (mcp.MAX_BYTES + 1) + b"\n" + valid)
        output = io.StringIO()
        self.assertEqual(mcp.run(source, output, "review"), 0)
        replies = [json.loads(line) for line in output.getvalue().splitlines()]
        self.assertEqual([r.get("error", {}).get("code") for r in replies[:3]], [-32700] * 3)
        self.assertEqual(replies[3]["result"], {})

    def test_notifications_and_invalid_ids(self):
        self.assertIsNone(mcp.process({"jsonrpc": "2.0", "method": "notifications/initialized"}, "review"))
        self.assertEqual(mcp.process([], "review")["error"]["code"], -32600)
        request = self.request("ping"); request["id"] = True
        self.assertEqual(mcp.process(request, "review")["error"]["code"], -32600)

    def test_profile_is_fixed_and_invalid_profile_rejected(self):
        self.assertEqual(str(mcp.control_path("review")), f"/private/tmp/archi-reactor-{os.getuid()}-review/control.sock")
        self.assertNotEqual(mcp.control_path("preview"), mcp.control_path("review"))
        for profile in ["../../secret", "ordinary", ""]:
            with self.assertRaises(mcp.BridgeError):
                mcp.control_path(profile)

    def test_real_private_unix_socket_round_trip(self):
        with tempfile.TemporaryDirectory(prefix="archi-rmcp-", dir="/private/tmp") as directory:
            path = Path(directory) / "control.sock"
            os.chmod(directory, 0o700)
            server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            server.bind(str(path)); os.chmod(path, 0o600); server.listen(1)
            received = []
            def serve():
                with server:
                    client, _ = server.accept()
                    with client:
                        received.append(json.loads(client.recv(4096)))
                        client.sendall(b'{"ok":true,"state":"preview","providerCalls":0}\n')
            thread = threading.Thread(target=serve); thread.start()
            with patch.object(mcp, "control_path", return_value=path):
                result = mcp.call_native("preview", "review")
            thread.join(2)
            self.assertFalse(thread.is_alive())
            self.assertEqual(received, [{"action": "preview"}])
            self.assertEqual(result, {"ok": True, "state": "preview", "providerCalls": 0})

    def test_unsafe_directory_and_symlink_endpoint_rejected(self):
        with tempfile.TemporaryDirectory(prefix="archi-rmcp-", dir="/private/tmp") as directory:
            path = Path(directory) / "control.sock"
            os.chmod(directory, 0o755)
            with patch.object(mcp, "control_path", return_value=path), self.assertRaises(mcp.BridgeError):
                mcp.call_native("status", "review")
            os.chmod(directory, 0o700)
            path.symlink_to("/private/tmp/never-connect")
            with patch.object(mcp, "control_path", return_value=path), self.assertRaises(mcp.BridgeError):
                mcp.call_native("status", "review")


if __name__ == "__main__":
    unittest.main()
