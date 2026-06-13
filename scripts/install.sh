#!/usr/bin/env bash
set -euo pipefail

LABEL="com.oltv00.mac-spaces-switcher"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN_DIR="$HOME/.local/bin"
BIN_PATH="$BIN_DIR/mac-spaces-switcher"
PLIST_DST="$HOME/Library/LaunchAgents/$LABEL.plist"
CONFIG_DIR="$HOME/.config/mac-spaces-switcher"

echo "Building release binary..."
swift build -c release --package-path "$ROOT"

mkdir -p "$BIN_DIR"
cp "$ROOT/.build/release/MacSpacesSwitcher" "$BIN_PATH"
echo "Installed binary -> $BIN_PATH"

# Ad-hoc sign with a stable identifier so macOS gives the binary a consistent
# code identity for the Accessibility (event-posting) permission grant.
codesign --force --sign - --identifier "$LABEL" "$BIN_PATH"
echo "Ad-hoc signed $BIN_PATH"

mkdir -p "$CONFIG_DIR"
if [ ! -f "$CONFIG_DIR/config.json" ]; then
  cp "$ROOT/config.example.json" "$CONFIG_DIR/config.json"
  echo "Installed default config -> $CONFIG_DIR/config.json"
fi

mkdir -p "$HOME/Library/LaunchAgents"
sed "s|__BIN_PATH__|$BIN_PATH|g" "$ROOT/LaunchAgent.plist" > "$PLIST_DST"
echo "Installed LaunchAgent -> $PLIST_DST"

launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST_DST"
launchctl kickstart -k "gui/$(id -u)/$LABEL"
echo "Loaded and started $LABEL"

echo
echo "Almost done — two one-time setup steps (details in README.md):"
echo
echo "  1. Grant Accessibility permission (needed to post the switch gesture):"
echo "       System Settings > Privacy & Security > Accessibility"
echo "       Enable 'mac-spaces-switcher' (if missing: +, then ⌘⇧G -> $BIN_DIR)."
echo "     Then reload the agent so it picks up the grant:"
echo "       launchctl kickstart -k \"gui/\$(id -u)/$LABEL\""
echo
echo "  2. Disable the native Mission Control shortcuts so they don't double-fire:"
echo "       System Settings > Keyboard > Keyboard Shortcuts > Mission Control"
echo "       Untick 'Move left/right a space' and 'Switch to Desktop 1-9'."
