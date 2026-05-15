#!/usr/bin/env python3
"""
esr_mcp_bridge_v1_prototype — Phase 1 real-CC bridge.

# What this is

A minimal MCP stdio server that Claude Code spawns via mcp.json. On
`initialize` (which Claude always calls first), it posts a one-shot
"hello, here I am" announcement to esrd's `POST /api/cc-bridge/announce`
HTTP endpoint. esrd's controller updates Esr.Bridge.V1Prototype.Server
state + PubSub broadcasts; the LiveView /admin then shows the bridge
as connected.

It also exposes one MCP tool, `esr_announce`, which Claude can call
explicitly to re-announce or to ping. The tool body is symmetric with
init-time announce.

# Architecture pattern

cc-openclaw MCP-stdio (the channel pattern this very Feishu chat is
using). NOT old esr's `--dangerously-load-development-channels` /
Phoenix Channel WebSocket pattern, which Allen reports has issues.

# Phase 5 replacement

`esr_plugin_cc_channel` wholesale-replaces this script with a full
MCP surface + capability gating + bidirectional event routing.

# Wire (per MCP spec)

Each line on stdin is one JSON-RPC 2.0 message. Server responses go
to stdout. All logging goes to stderr (stdout is reserved for MCP).

    initialize -> respond capabilities, asynchronously post announce
    notifications/initialized -> ack
    tools/list -> respond [esr_announce]
    tools/call esr_announce -> POST + respond
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


def setup_logging():
    logging.basicConfig(
        stream=sys.stderr,
        level=logging.INFO,
        format=f"[esr_mcp_bridge {BRIDGE_ID}] %(asctime)s %(levelname)s %(message)s",
    )


def post_announce(claude_info: dict) -> bool:
    """POST a one-line announce to esrd. Returns True on 2xx."""
    body = json.dumps(
        {
            "bridge_id": BRIDGE_ID,
            "claude_info": claude_info,
            "tools": ["esr_announce"],
        }
    ).encode("utf-8")

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
    """Tell esrd we're going away. Best-effort; ignore errors on shutdown."""
    req = urllib.request.Request(
        f"{ESRD_URL}/api/cc-bridge/announce/{BRIDGE_ID}",
        method="DELETE",
    )
    try:
        with urllib.request.urlopen(req, timeout=1) as resp:
            return 200 <= resp.status < 300
    except urllib.error.URLError:
        return False


def respond(req_id, result):
    sys.stdout.write(json.dumps({"jsonrpc": "2.0", "id": req_id, "result": result}) + "\n")
    sys.stdout.flush()


def handle(msg: dict):
    method = msg.get("method", "")
    req_id = msg.get("id")
    params = msg.get("params", {})

    if method == "initialize":
        client_info = params.get("clientInfo", {})
        # Fire-and-forget announce so we don't block initialize.
        threading.Thread(target=post_announce, args=(client_info,), daemon=True).start()
        respond(
            req_id,
            {
                "protocolVersion": params.get("protocolVersion", "2024-11-05"),
                "capabilities": {"tools": {}},
                "serverInfo": {"name": "esr-bridge-v1-prototype", "version": "0.1.0"},
            },
        )
    elif method == "notifications/initialized":
        pass  # notification, no response required
    elif method == "tools/list":
        respond(
            req_id,
            {
                "tools": [
                    {
                        "name": "esr_announce",
                        "description": "Ping esrd to register or refresh this bridge connection.",
                        "inputSchema": {"type": "object", "properties": {}, "required": []},
                    }
                ]
            },
        )
    elif method == "tools/call" and params.get("name") == "esr_announce":
        ok = post_announce({"source": "tools/call"})
        respond(
            req_id,
            {
                "content": [
                    {
                        "type": "text",
                        "text": f"esr_announce posted to {ESRD_URL}: {'ok' if ok else 'failed'}",
                    }
                ]
            },
        )
    elif req_id is not None:
        respond(req_id, {"error": {"code": -32601, "message": f"Method not found: {method}"}})


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
        # claude closed stdin (= shut us down). Tell esrd we're going.
        # Best-effort — esrd may already be unreachable; that's fine.
        LOG.info("bridge shutting down, posting disconnect")
        post_disconnect()


if __name__ == "__main__":
    main()
