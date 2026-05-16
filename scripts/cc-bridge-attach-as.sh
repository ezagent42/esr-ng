#!/usr/bin/env bash
# cc-bridge-attach-as.sh — launch claude with a specific agent URI.
#
# Wrapper around cc-bridge-attach.sh for spawning multiple parallel
# claude instances each with a distinct agent URI. Bypasses
# cc-bridge-attach.local.sh's hardcoded `export ESR_AGENT_URI` (if
# present) by temporarily stubbing it for the duration of the attach.
#
# Usage:
#   bash scripts/cc-bridge-attach-as.sh agent://cc-architect
#   bash scripts/cc-bridge-attach-as.sh agent://cc-oncall
#
# Run in a separate terminal per agent. The default cc-builder instance
# is still `bash scripts/cc-bridge-attach.sh` (which uses .local.sh).
set -euo pipefail

if [ -z "${1:-}" ]; then
  echo "usage: bash scripts/cc-bridge-attach-as.sh <agent_uri>" >&2
  echo "example: bash scripts/cc-bridge-attach-as.sh agent://cc-architect" >&2
  exit 1
fi

AGENT_URI="$1"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LOCAL_SH="$SCRIPT_DIR/cc-bridge-attach.local.sh"

# If .local.sh exists, source it for proxy/etc — but we'll override
# its ESR_AGENT_URI export below + then stub the file before the main
# script re-sources it.
if [ -f "$LOCAL_SH" ]; then
  # shellcheck disable=SC1091
  source "$LOCAL_SH"
fi

# Override with the CLI arg (after .local.sh's potential hardcoded export).
export ESR_AGENT_URI="$AGENT_URI"

# Stub .local.sh during attach so the main script's `source $LOCAL_SH`
# doesn't re-overwrite our ESR_AGENT_URI. Restore on exit.
if [ -f "$LOCAL_SH" ]; then
  BACKUP="${LOCAL_SH}.bak-as-$$"
  mv "$LOCAL_SH" "$BACKUP"
  cat > "$LOCAL_SH" <<EOF
#!/usr/bin/env bash
# Stub written by cc-bridge-attach-as.sh; original at $BACKUP.
# Proxy + ESR_AGENT_URI already exported in parent shell.
EOF
  trap 'mv "$BACKUP" "$LOCAL_SH"' EXIT INT TERM
fi

bash "$SCRIPT_DIR/cc-bridge-attach.sh"
