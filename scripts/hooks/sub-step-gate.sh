#!/usr/bin/env bash
# sub-step gate — the "B" git-hook backstop (P0-D6 / ARCHITECTURE Decision #80).
#
# Fires as a Claude Code PreToolUse hook on Bash tool calls. If the command is
# a `git commit` or `git tag`, runs the sub-step gate before allowing it:
#
#   Phase 0:  mix format --check-formatted  +  mix test
#   Phase 1:  + mix ezagent.check_invariants  (this commit)
#
# Gate red  → exit 2 (blocks the tool call; stderr is shown to Claude).
# Not git   → exit 0 immediately (no-op for the vast majority of Bash calls).
#
# This is a *backstop*, not the primary mechanism — the primary mechanism is
# agent discipline (/goal prompt + CLAUDE.md 贯穿条款). Each subsequent phase's
# brainstorm extends this script: Phase 1 adds the invariants check;
# Phase 2+ adds e2e flow checks once those exist.
set -uo pipefail

input=$(cat)

# Only gate `git commit` / `git tag`. Wide match by design — P0-D5 实施期原则:
# 宁可宽也不要漏. A false-positive merely runs the (harmless) gate.
if ! printf '%s' "$input" | grep -qE 'git[[:space:]]+(commit|tag)'; then
  exit 0
fi

cd "${CLAUDE_PROJECT_DIR:-$(dirname "$0")/../..}" || {
  echo "[sub-step-gate] cannot cd to repo root" >&2
  exit 2
}

echo "[sub-step-gate] git commit/tag detected — running Phase 1 gate" >&2

echo "[sub-step-gate] → mix format --check-formatted" >&2
if ! mix format --check-formatted >&2; then
  echo "[sub-step-gate] BLOCKED: code not formatted (run: mix format)" >&2
  exit 2
fi

echo "[sub-step-gate] → mix test" >&2
if ! mix test >&2; then
  echo "[sub-step-gate] BLOCKED: mix test failed" >&2
  exit 2
fi

echo "[sub-step-gate] → mix ezagent.check_invariants" >&2
if ! mix ezagent.check_invariants >&2; then
  echo "[sub-step-gate] BLOCKED: invariant violation (see grep output above)" >&2
  exit 2
fi

echo "[sub-step-gate] gate green — commit/tag allowed" >&2
exit 0
