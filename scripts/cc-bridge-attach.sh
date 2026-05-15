#!/usr/bin/env bash
# cc-bridge-attach — Phase 1 v1_prototype: spawn a real Claude Code
# session attached to esrd via MCP-stdio bridge.
#
# Usage:
#   bash scripts/cc-bridge-attach.sh            # foreground (interactive)
#   bash scripts/cc-bridge-attach.sh --headless # non-interactive; ideal for
#                                               # agent-browser verification
#
# Pattern: cc-openclaw style — `claude --mcp-config <path>` reads our
# generated mcp.json and spawns the Python MCP bridge as a subprocess.
# The bridge POSTs `/api/cc-bridge/announce` to esrd on init; the LV
# /admin shows the new bridge as connected.
#
# PTY: wrapped in `script` (macOS/Linux util) so claude gets a real TTY,
# which it currently requires. `script -q /dev/null` is the standard
# trick for that.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

if ! command -v claude >/dev/null 2>&1; then
  echo "❌ claude binary not on PATH. Install Claude Code first." >&2
  exit 1
fi

echo "[cc-bridge-attach] writing mcp.json..." >&2
MCP_PATH=$(mix run --no-start -e \
  'IO.puts(elem(Esr.Bridge.V1Prototype.McpConfigWriter.write!(), 1))' \
  2>/dev/null | tail -1)

if [ -z "$MCP_PATH" ] || [ ! -f "$MCP_PATH" ]; then
  echo "❌ mcp.json generation failed (got: '$MCP_PATH')" >&2
  exit 1
fi

echo "[cc-bridge-attach] mcp.json: $MCP_PATH" >&2
echo "[cc-bridge-attach] launching claude (PTY wrapper)..." >&2

if [ "${1:-}" = "--headless" ]; then
  # Non-interactive: pipe a closing stdin so claude exits cleanly after
  # MCP init. Used for agent-browser verification — bridge announces on
  # initialize, the announce HTTP POST hits esrd, then we tear down.
  exec script -q /dev/null claude \
    --permission-mode bypassPermissions \
    --mcp-config "$MCP_PATH" \
    --print "ping" \
    --output-format json
else
  # Interactive: opens a real claude session in this terminal.
  exec script -q /dev/null claude \
    --permission-mode bypassPermissions \
    --mcp-config "$MCP_PATH"
fi
