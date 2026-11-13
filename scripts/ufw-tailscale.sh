#!/usr/bin/env bash
# ufw-tailscale.sh — deprecated alias; forwards to firewalld-tailscale.sh.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
echo "ufw-tailscale.sh: deprecated — using firewalld-tailscale.sh" >&2
exec bash "$ROOT/firewalld-tailscale.sh" "$@"
