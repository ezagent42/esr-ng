#!/usr/bin/env python3
"""
esr_bridge_v1_prototype — Phase 1 stdio JSON-RPC echo bridge.

# What this is

A minimal stdio JSON-RPC server that demonstrates the bridge↔ESR wire
shape (Decision P1-D1). It is NOT yet integrated with a real Claude
Code instance — Phase 5 wholesale-replaces this module with the full
`esr_plugin_cc_channel` plugin per SPEC §1b boundary note.

# Protocol

Line-delimited JSON-RPC 2.0:

    → {"jsonrpc":"2.0","id":"1","method":"ping","params":{}}
    ← {"jsonrpc":"2.0","id":"1","result":"pong"}

    → {"jsonrpc":"2.0","id":"2","method":"echo","params":{"msg":"hi"}}
    ← {"jsonrpc":"2.0","id":"2","result":{"echo":"hi"}}

    → {"jsonrpc":"2.0","id":"3","method":"shutdown","params":{}}
    ← {"jsonrpc":"2.0","id":"3","result":"bye"}
      (process exits 0)

# Why stdio not WebSocket

bridge↔CC must be stdio per the channels protocol (hard invariant #8).
bridge↔ESR also uses stdio in Phase 1 to keep the prototype minimal —
adding a TCP/WS hop would obscure whether the wire works at all.
Phase 5 may revisit this for performance.

# Run

    uv run python3 apps/esr_plugin_cc_bridge_v1_prototype/python/esr_bridge_v1_prototype.py

    {"jsonrpc":"2.0","id":"1","method":"ping","params":{}}
    {"jsonrpc": "2.0", "id": "1", "result": "pong"}

Ctrl-D / EOF terminates cleanly.
"""

import json
import sys


def respond(req_id, result):
    sys.stdout.write(json.dumps({"jsonrpc": "2.0", "id": req_id, "result": result}) + "\n")
    sys.stdout.flush()


def error(req_id, code, message):
    sys.stdout.write(
        json.dumps(
            {"jsonrpc": "2.0", "id": req_id, "error": {"code": code, "message": message}}
        )
        + "\n"
    )
    sys.stdout.flush()


def handle(line):
    try:
        msg = json.loads(line)
    except json.JSONDecodeError as e:
        error(None, -32700, f"Parse error: {e}")
        return True

    req_id = msg.get("id")
    method = msg.get("method")
    params = msg.get("params", {})

    if method == "ping":
        respond(req_id, "pong")
    elif method == "echo":
        respond(req_id, {"echo": params.get("msg", "")})
    elif method == "shutdown":
        respond(req_id, "bye")
        return False
    else:
        error(req_id, -32601, f"Method not found: {method}")

    return True


def main():
    sys.stdout.write(
        json.dumps({"jsonrpc": "2.0", "method": "hello", "params": {"role": "bridge_v1_prototype"}})
        + "\n"
    )
    sys.stdout.flush()

    for raw in sys.stdin:
        line = raw.strip()
        if not line:
            continue
        if not handle(line):
            break


if __name__ == "__main__":
    main()
