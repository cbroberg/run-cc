#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
BIN_SRC="$REPO_DIR/bin/ccrun"
BIN_DST="${HOME}/.local/bin/ccrun"
CONFIG_DIR="$HOME/.config/ccrun"
CONFIG_FILE="$CONFIG_DIR/sessions.json"

command -v jq >/dev/null || {
  echo "ccrun: jq is required. Install with: brew install jq" >&2
  exit 1
}

# Check iTerm2 is installed
if [[ ! -d "/Applications/iTerm.app" ]]; then
  echo "ccrun: iTerm2 not found at /Applications/iTerm.app" >&2
  echo "Install iTerm2 first: https://iterm2.com" >&2
  exit 1
fi

# Install binary
mkdir -p "$(dirname "$BIN_DST")"
install -m 0755 "$BIN_SRC" "$BIN_DST"
echo "installed: $BIN_DST"

# Ensure ~/.local/bin is in PATH
if ! echo "$PATH" | tr ':' '\n' | grep -qx "$HOME/.local/bin"; then
  rc="$HOME/.bashrc"
  [[ "$(basename "$SHELL")" == "zsh" ]] && rc="$HOME/.zshrc"
  echo ""
  echo "⚠  ~/.local/bin is not in your PATH. Add it:"
  echo "   echo 'export PATH=\"\$HOME/.local/bin:\$PATH\"' >> $rc"
fi

# Create config dir + seed config if missing
mkdir -p "$CONFIG_DIR"
OLD_CONFIG="$HOME/.config/run-cc/sessions.json"
if [[ ! -f "$CONFIG_FILE" && -f "$OLD_CONFIG" ]]; then
  mv "$OLD_CONFIG" "$CONFIG_FILE"
  rmdir "$HOME/.config/run-cc" 2>/dev/null || true
  echo "migrated: $OLD_CONFIG → $CONFIG_FILE"
elif [[ ! -f "$CONFIG_FILE" ]]; then
  cp "$REPO_DIR/examples/sessions.json" "$CONFIG_FILE"
  echo "created:  $CONFIG_FILE (example config — edit with 'ccrun edit')"
else
  echo "kept:     $CONFIG_FILE (already exists)"
fi

echo ""
echo "done. try: ccrun list"
