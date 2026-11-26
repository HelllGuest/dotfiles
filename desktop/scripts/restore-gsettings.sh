#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
IN="$REPO_ROOT/desktop/gnome/dconf/user.conf"

if [[ ! -f "$IN" ]]; then
    echo "Missing: $IN" >&2
    exit 1
fi

if [[ -z ${DBUS_SESSION_BUS_ADDRESS:-} && ! -S ${XDG_RUNTIME_DIR:-/nonexistent}/bus ]]; then
    echo "✗ no session D-Bus: cannot write GNOME dconf — re-run from your GNOME login" >&2
    exit 1
fi

echo "Restoring GNOME settings from $IN..."
dconf load / < "$IN"
echo "Done."
