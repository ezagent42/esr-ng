#!/usr/bin/env python3
"""
esr_mcp_bridge_v1_prototype — Phase 1 bidirectional CC channel bridge.

# What this is

A Claude Code **channel** server per
https://code.claude.com/docs/en/channels-reference. The protocol is
plain MCP over stdio with these channel-specific additions:

1. `capabilities.experimental['claude/channel'] = {}` in the
   `initialize` response — declares we're a channel
2. `notifications/claude/channel` sent server→claude — pushes
   messages into claude's context as `<channel>` tags
3. Standard MCP `reply` tool — claude calls this to send messages back

Outside MCP itself, we maintain two HTTP side-channels with esrd:

- POST `/api/cc-bridge/announce` at init: register the bridge
- GET  `/api/cc-bridge/events?bridge_id=X` SSE: subscribe for
  esr→claude pushes
- POST `/api/cc-bridge/reply`: forward claude's `reply` tool calls
- DELETE `/api/cc-bridge/announce/{bridge_id}` at shutdown: unregister

# Why HTTP instead of WebSocket

Phoenix can serve SSE through Bandit cleanly. WebSocket would add a
client-side dep (websockets package). For v1_prototype scope, SSE is
simpler and demonstrates the architecture.

# Phase 5 replacement

`esr_plugin_cc_channel` will replace this with a full MCP surface +
capability gating + permission relay + persistent session binding.
"""

import json
import logging
import os
import sys
import threading
import urllib.error
import urllib.request
import uuid

LOG = logging.getLogger("esr_mcp_bridge_v1")

ESRD_URL = os.environ.get("ESRD_URL", "http://127.0.0.1:4000")
BRIDGE_ID = os.environ.get("ESR_BRIDGE_ID", f"bridge-{uuid.uuid4().hex[:8]}")
# Phase 2c: if set, the announce includes agent_uri so esrd spawns an
# Esr.Entity.Agent Kind at this URI and binds it to BRIDGE_ID — reply
# traffic then routes via the chat router (not the legacy record_reply).
# Convention: agent://<short-name> (e.g. agent://cc-builder). Unset =
# legacy Phase 1 mode (bare bridge, no Agent Kind, reply 422s).
AGENT_URI = os.environ.get("ESR_AGENT_URI", "")

_stdout_lock = threading.Lock()


def setup_logging():
    logging.basicConfig(
        stream=sys.stderr,
        level=logging.INFO,
        format=f"[esr_mcp_bridge {BRIDGE_ID}] %(asctime)s %(levelname)s %(message)s",
    )


def write_frame(obj: dict) -> None:
    """Write one JSON line to stdout. Locked because the SSE thread also writes."""
    with _stdout_lock:
        sys.stdout.write(json.dumps(obj) + "\n")
        sys.stdout.flush()


def post_announce(claude_info: dict) -> bool:
    payload = {
        "bridge_id": BRIDGE_ID,
        "claude_info": claude_info,
        "tools": ["reply"],
    }
    if AGENT_URI:
        payload["agent_uri"] = AGENT_URI
    body = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(
        f"{ESRD_URL}/api/cc-bridge/announce",
        data=body,
        method="POST",
        headers={"Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(req, timeout=3) as resp:
            LOG.info("announce HTTP %s", resp.status)
            return 200 <= resp.status < 300
    except urllib.error.URLError as e:
        LOG.warning("announce failed: %s", e)
        return False


def post_disconnect() -> bool:
    req = urllib.request.Request(
        f"{ESRD_URL}/api/cc-bridge/announce/{BRIDGE_ID}",
        method="DELETE",
    )
    try:
        with urllib.request.urlopen(req, timeout=1) as resp:
            return 200 <= resp.status < 300
    except urllib.error.URLError:
        return False


def post_reply(text: str) -> bool:
    """Forward claude's reply tool call to esrd."""
    body = json.dumps({"bridge_id": BRIDGE_ID, "text": text}).encode("utf-8")
    req = urllib.request.Request(
        f"{ESRD_URL}/api/cc-bridge/reply",
        data=body,
        method="POST",
        headers={"Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(req, timeout=3) as resp:
            return 200 <= resp.status < 300
    except urllib.error.URLError as e:
        LOG.warning("reply post failed: %s", e)
        return False


def sse_subscribe_loop():
    """
    Subscribe to esrd's SSE stream. Each event becomes a
    `notifications/claude/channel` JSON-RPC notification on stdout, so
    claude sees it as a `<channel>` tag user message.

    Runs in a daemon thread; lifetime = bridge process lifetime.
    """
    url = f"{ESRD_URL}/api/cc-bridge/events?bridge_id={BRIDGE_ID}"
    LOG.info("SSE subscribing to %s", url)

    req = urllib.request.Request(url, headers={"Accept": "text/event-stream"})

    while True:
        try:
            with urllib.request.urlopen(req, timeout=None) as resp:
                LOG.info("SSE connected HTTP %s", resp.status)
                pending = ""
                for line in resp:
                    line = line.decode("utf-8")
                    if line == "\n":
                        if pending:
                            handle_sse_event(pending)
                            pending = ""
                    elif line.startswith("data:"):
                        pending += line[5:].lstrip()
        except (urllib.error.URLError, ConnectionResetError, OSError) as e:
            LOG.warning("SSE disconnected: %s — retry in 2s", e)
            import time

            time.sleep(2)


def handle_sse_event(raw: str):
    """One SSE 'data: ...' payload. Expected: JSON {content, meta}."""
    raw = raw.rstrip("\n")
    if not raw:
        return
    try:
        evt = json.loads(raw)
    except json.JSONDecodeError:
        LOG.warning("SSE event not JSON: %r", raw)
        return

    write_frame(
        {
            "jsonrpc": "2.0",
            "method": "notifications/claude/channel",
            "params": {
                "content": evt.get("content", ""),
                "meta": evt.get("meta", {}),
            },
        }
    )


def respond(req_id, result):
    write_frame({"jsonrpc": "2.0", "id": req_id, "result": result})


def handle(msg: dict):
    method = msg.get("method", "")
    req_id = msg.get("id")
    params = msg.get("params", {})

    if method == "initialize":
        client_info = params.get("clientInfo", {})
        threading.Thread(target=post_announce, args=(client_info,), daemon=True).start()
        threading.Thread(target=sse_subscribe_loop, daemon=True).start()
        respond(
            req_id,
            {
                "protocolVersion": params.get("protocolVersion", "2024-11-05"),
                "capabilities": {
                    "tools": {},
                    "experimental": {
                        # This makes us a channel per
                        # https://code.claude.com/docs/en/channels-reference
                        "claude/channel": {},
                    },
                },
                "serverInfo": {"name": "esr-bridge", "version": "0.1.0"},
                "instructions": (
                    'Messages from this channel arrive as <channel source="esr-bridge" ...>. '
                    "Treat them as user input. Reply by calling the `reply` tool with "
                    "the message text."
                ),
            },
        )
    elif method == "notifications/initialized":
        pass
    elif method == "tools/list":
        respond(
            req_id,
            {
                "tools": [
                    {
                        "name": "reply",
                        "description": (
                            "Send a reply back through the esr-bridge channel. "
                            "Use this whenever you want to respond to a "
                            "<channel source=\"esr-bridge\"> message."
                        ),
                        "inputSchema": {
                            "type": "object",
                            "properties": {
                                "text": {
                                    "type": "string",
                                    "description": "The message text to send back.",
                                }
                            },
                            "required": ["text"],
                        },
                    }
                ]
            },
        )
    elif method == "tools/call" and params.get("name") == "reply":
        text = params.get("arguments", {}).get("text", "")
        ok = post_reply(text)
        respond(
            req_id,
            {
                "content": [
                    {
                        "type": "text",
                        "text": f"reply forwarded to esrd ({'ok' if ok else 'FAILED'})",
                    }
                ]
            },
        )
    elif req_id is not None:
        respond(
            req_id,
            {"error": {"code": -32601, "message": f"Method not found: {method}"}},
        )


def main():
    setup_logging()
    LOG.info("bridge starting esrd=%s", ESRD_URL)

    try:
        for raw in sys.stdin:
            line = raw.strip()
            if not line:
                continue
            try:
                handle(json.loads(line))
            except json.JSONDecodeError as e:
                LOG.error("bad JSON: %s", e)
    finally:
        LOG.info("bridge shutting down, posting disconnect")
        post_disconnect()


if __name__ == "__main__":
    main()
