#!/usr/bin/env python3
"""STDIO MCP for the current native ARCHi expression owner; no provider SDK or keys.

ARCHI_REACTOR_PROFILE selects review (default) or preview. The native app must be
running. Live hosted sessions can only be started through its reviewed native UI.
"""

import json
import os
from pathlib import Path
import socket
import stat
import sys

MAX_BYTES = 256 * 1024
PROTOCOL_VERSIONS = {"2024-11-05", "2025-03-26", "2025-06-18"}
ACTIONS = {
    "reactor_status": ("status", "Read the current native ARCHi expression status. Local only; no provider session is created."),
    "reactor_prepare": ("prepare", "Check the local transport and public Reactor pricing for the currently chosen ARCHi body. No provider session or credential input."),
    "reactor_preview": ("preview", "Show a local expression preview in the native ARCHi app. Does not start paid Reactor generation."),
    "reactor_stop": ("stop", "Stop the current app-owned expression and return to local artwork. Does not create a provider session."),
}
FORBIDDEN_KEYS = {"apikey", "token", "accesstoken", "refreshtoken", "secret", "credential", "credentials", "authorization", "password", "cookie"}


class BridgeError(Exception):
    pass


def _pairs(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError("Duplicate JSON key")
        result[key] = value
    return result


def decode(data):
    return json.loads(data, object_pairs_hook=_pairs,
                      parse_constant=lambda _: (_ for _ in ()).throw(ValueError("Non-finite JSON")))


def contains_no_credentials(value):
    if isinstance(value, dict):
        return all("".join(c for c in key.lower() if c.isalnum()) not in FORBIDDEN_KEYS
                   and contains_no_credentials(item) for key, item in value.items())
    if isinstance(value, list):
        return all(contains_no_credentials(item) for item in value)
    return True


def control_path(profile):
    if profile not in {"review", "preview"}:
        raise BridgeError("ARCHI_REACTOR_PROFILE must be review or preview.")
    return Path(f"/private/tmp/archi-reactor-{os.getuid()}-{profile}/control.sock")


def _check_private(path, kind, mode):
    info = path.lstat()
    if info.st_uid != os.getuid() or stat.S_IFMT(info.st_mode) != kind or stat.S_IMODE(info.st_mode) != mode:
        raise BridgeError("ARCHi's local expression endpoint is not private and owned by this user.")


def call_native(action, profile):
    if action not in {item[0] for item in ACTIONS.values()}:
        raise BridgeError("Only local status, prepare, preview, and stop are supported.")
    path = control_path(profile)
    try:
        _check_private(path.parent, stat.S_IFDIR, 0o700)
        _check_private(path, stat.S_IFSOCK, 0o600)
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as client:
            client.settimeout(4)
            client.connect(str(path))
            client.sendall(json.dumps({"action": action}, separators=(",", ":")).encode() + b"\n")
            response = bytearray()
            while len(response) <= MAX_BYTES:
                chunk = client.recv(min(4096, MAX_BYTES + 1 - len(response)))
                if not chunk:
                    raise BridgeError("ARCHi ended the expression response before completion.")
                response.extend(chunk)
                if b"\n" in chunk:
                    break
            if len(response) > MAX_BYTES or b"\n" not in response:
                raise BridgeError("ARCHi's expression response exceeded the local message limit.")
            line, trailing = bytes(response).split(b"\n", 1)
            if trailing.strip():
                raise BridgeError("ARCHi returned more than one expression response.")
            result = decode(line)
            if not isinstance(result, dict) or not contains_no_credentials(result):
                raise BridgeError("ARCHi returned an invalid or private expression response.")
            return result
    except FileNotFoundError:
        raise BridgeError(f"Open ARCHi {'Development Review' if profile == 'review' else 'Preview'} first. No expression session was created.") from None
    except (ConnectionError, TimeoutError, OSError):
        raise BridgeError("The native ARCHi expression owner is unavailable. Reopen the selected app profile; no new session was created.") from None
    except (ValueError, RecursionError):
        raise BridgeError("ARCHi returned malformed expression JSON.") from None


def error(request_id, code, message):
    return {"jsonrpc": "2.0", "id": request_id, "error": {"code": code, "message": message}}


def process(request, profile, native_call=call_native):
    if not isinstance(request, dict) or request.get("jsonrpc") != "2.0" or not isinstance(request.get("method"), str):
        return error(None, -32600, "Expected one JSON-RPC 2.0 request.")
    request_id = request.get("id")
    if "id" not in request:
        return None
    if isinstance(request_id, bool) or not isinstance(request_id, (str, int, type(None))):
        return error(None, -32600, "Invalid request identifier.")
    method = request["method"]
    params = request.get("params", {})
    if not isinstance(params, dict):
        return error(request_id, -32602, "Parameters must be an object.")
    if method == "initialize":
        proposed_version = params.get("protocolVersion")
        result = {
            "protocolVersion": proposed_version if proposed_version in PROTOCOL_VERSIONS else "2024-11-05",
            "capabilities": {"tools": {"listChanged": False}},
            "serverInfo": {"name": "archi-reactor-local-control", "version": "1.0.0"},
            "instructions": "Controls one running native ARCHi app. No credentials, independent provider sessions, or live-start calls are accepted. Start hosted generation through the app's reviewed native action.",
        }
    elif method == "ping":
        result = {}
    elif method == "tools/list":
        if params:
            return error(request_id, -32602, "This local tool list is not paginated.")
        result = {"tools": [
            {"name": name, "description": description,
             "inputSchema": {"type": "object", "properties": {}, "additionalProperties": False},
             "annotations": {"title": name.replace("reactor_", "ARCHi expression: "),
                             "readOnlyHint": action == "status", "destructiveHint": False,
                             "idempotentHint": action in {"status", "stop"}, "openWorldHint": action == "prepare"}}
            for name, (action, description) in ACTIONS.items()]}
    elif method == "tools/call":
        name = params.get("name")
        if not isinstance(name, str) or name not in ACTIONS:
            return error(request_id, -32602, "Unknown local expression tool. Live start is available only in the native app.")
        if set(params) - {"name", "arguments", "_meta"} or params.get("arguments", {}) != {}:
            return error(request_id, -32602, "These local tools take no arguments. Credentials and provider configuration are not accepted.")
        try:
            native_result = native_call(ACTIONS[name][0], profile)
            if not isinstance(native_result, dict) or not contains_no_credentials(native_result):
                raise BridgeError("The native expression response was invalid or private.")
            payload = json.dumps(native_result, ensure_ascii=False, allow_nan=False, separators=(",", ":"))
            if len(payload.encode()) >= MAX_BYTES - 1024:
                raise BridgeError("The native expression response exceeded the local message limit.")
            result = {"content": [{"type": "text", "text": payload}], "isError": native_result.get("ok") is False}
        except (BridgeError, ValueError, TypeError, RecursionError) as exc:
            message = str(exc) if isinstance(exc, BridgeError) else "The native expression response was invalid."
            result = {"content": [{"type": "text", "text": message}], "isError": True}
    else:
        return error(request_id, -32601, "Method not found.")
    return {"jsonrpc": "2.0", "id": request_id, "result": result}


def run(input_stream, output_stream, profile):
    try:
        control_path(profile)
    except BridgeError as exc:
        print(str(exc), file=sys.stderr)
        return 2
    while True:
        line = input_stream.readline(MAX_BYTES + 1)
        if not line:
            return 0
        if len(line) > MAX_BYTES:
            while line and not line.endswith(b"\n"):
                line = input_stream.readline(MAX_BYTES + 1)
            response = error(None, -32700, "Message exceeds the local 256 KiB limit.")
        else:
            try:
                response = process(decode(line), profile)
            except (ValueError, RecursionError, UnicodeError):
                response = error(None, -32700, "Malformed JSON.")
        if response is not None:
            output_stream.write(json.dumps(response, ensure_ascii=False, allow_nan=False, separators=(",", ":")) + "\n")
            output_stream.flush()


if __name__ == "__main__":
    raise SystemExit(run(sys.stdin.buffer, sys.stdout, os.environ.get("ARCHI_REACTOR_PROFILE", "review")))
