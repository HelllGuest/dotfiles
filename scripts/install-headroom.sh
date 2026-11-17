#!/usr/bin/env bash
# install-headroom.sh — Headroom context optimizer (pipx, user-local)
# https://github.com/headroomlabs-ai/headroom

set -euo pipefail

if ! command -v pipx >/dev/null 2>&1; then
    echo "Installing python-pipx (pacman)..."
    sudo pacman -S --needed --noconfirm python-pipx
fi

export PATH="${HOME}/.local/bin:${PATH}"

# Pinned: headroom proxies every Anthropic/OpenAI request (ANTHROPIC_BASE_URL),
# so it sees API keys. Never auto-upgrade to whatever PyPI serves; bump the pin
# after reviewing a release.
HEADROOM_VERSION="${HEADROOM_VERSION:-0.44.0}"
[[ $HEADROOM_VERSION =~ ^[0-9]+(\.[0-9]+){1,3}$ ]] || { echo "invalid HEADROOM_VERSION" >&2; exit 1; }
HEADROOM_SPEC="headroom-ai[all]==${HEADROOM_VERSION}"
installed="$(pipx list --short 2>/dev/null | awk '$1 == "headroom-ai" {print $2}')"
if [[ "$installed" == "$HEADROOM_VERSION" ]]; then
    echo "headroom-ai ${HEADROOM_VERSION} already installed (pinned)"
else
    echo "Installing ${HEADROOM_SPEC} via pipx (pinned; was: ${installed:-none})..."
    pipx install --force "$HEADROOM_SPEC"
fi

echo "✓ headroom installed: $(headroom --version)"
