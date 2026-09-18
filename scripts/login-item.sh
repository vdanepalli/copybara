#!/bin/bash
# Install/uninstall the Copybara Mac agent as a login item (LaunchAgent),
# so it auto-starts after a reboot/login.
#
#   ./scripts/login-item.sh install
#   ./scripts/login-item.sh uninstall
#
# Requires /Applications/Copybara.app to exist (see README setup step 3).

set -euo pipefail

LABEL="com.copybara.mac"
SRC="$(cd "$(dirname "$0")" && pwd)/${LABEL}.plist"
DEST="$HOME/Library/LaunchAgents/${LABEL}.plist"
UID_NUM="$(id -u)"

case "${1:-}" in
  install)
    mkdir -p "$HOME/Library/LaunchAgents"
    cp "$SRC" "$DEST"
    # Reload cleanly if already present.
    launchctl bootout "gui/${UID_NUM}/${LABEL}" 2>/dev/null || true
    launchctl bootstrap "gui/${UID_NUM}" "$DEST"
    echo "Installed login item: ${LABEL}"
    ;;
  uninstall)
    launchctl bootout "gui/${UID_NUM}/${LABEL}" 2>/dev/null || true
    rm -f "$DEST"
    echo "Removed login item: ${LABEL}"
    ;;
  *)
    echo "usage: $0 {install|uninstall}" >&2
    exit 1
    ;;
esac
