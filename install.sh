#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
BIN_SRC="$REPO_DIR/bin/run-cc"
BIN_DST="/usr/local/bin/run-cc"
CONFIG_DIR="$HOME/.config/run-cc"
CONFIG_FILE="$CONFIG_DIR/sessions.json"

command -v jq >/dev/null || {
  echo "run-cc: jq is required. Install with: brew install jq" >&2
  exit 1
}

# Check iTerm2 is installed
if [[ ! -d "/Applications/iTerm.app" ]]; then
  echo "run-cc: iTerm2 not found at /Applications/iTerm.app" >&2
  echo "Install iTerm2 first: https://iterm2.com" >&2
  exit 1
fi

# Install binary
if [[ -w "/usr/local/bin" ]]; then
  install -m 0755 "$BIN_SRC" "$BIN_DST"
else
  sudo install -m 0755 "$BIN_SRC" "$BIN_DST"
fi
echo "installed: $BIN_DST"

# Create config dir + seed config if missing
mkdir -p "$CONFIG_DIR"
if [[ ! -f "$CONFIG_FILE" ]]; then
  cp "$REPO_DIR/examples/sessions.json" "$CONFIG_FILE"
  echo "created: $CONFIG_FILE (example config — edit with 'run-cc edit')"
else
  echo "kept:    $CONFIG_FILE (already exists)"
fi

echo ""
echo "done. try: run-cc list"
