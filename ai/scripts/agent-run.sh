#!/usr/bin/env bash
# agent-run.sh — hardened rootless Podman launcher for AI agents / tools.
#
# Usage:
#   agent-run <project-dir> <image> [command...]
#   agent-run ~/src/job alpine:3.20 sh
#   AGENT_NET=pasta agent-run ~/src/job alpine:3.20
#
# Defaults: read-only root, cap-drop ALL, no-new-privileges, network none,
# bind-mount only the project dir at /work. Never mounts Podman/Docker sockets.
#
# Env:
#   AGENT_NET=none|pasta   (default none)
#   AGENT_NAME=...         container name prefix
#   AGENT_TMP_SIZE=512m
set -euo pipefail

die() { printf 'ERR %s\n' "$*" >&2; exit 1; }

command -v podman >/dev/null || die "podman not installed (pacman -S podman)"

[[ $# -ge 2 ]] || die "usage: agent-run <project-dir> <image> [command...]"

PROJ=$(readlink -f -- "$1") || die "bad project dir: $1"
IMAGE=$2
shift 2
[[ -d $PROJ ]] || die "not a directory: $PROJ"

# Shared with lab-* wrappers and lab-mcp.sh: refuse system/socket paths (/run,
# /var, /tmp and its session socket dirs, /opt, any dir holding a socket),
# home/hidden config dirs, dotfiles repo, and samples.
# shellcheck source=../../labs/lib/lab-workdir.sh
source "$(cd "$(dirname "$0")/../.." && pwd)/labs/lib/lab-workdir.sh"
reason=$(_lab_path_refusal_reason "$PROJ")
[[ -z $reason ]] || die "refusing to mount $PROJ ($reason)"

NET=${AGENT_NET:-none}
case $NET in
  none|pasta) ;;
  *) die "AGENT_NET must be none or pasta (got: $NET)" ;;
esac

NAME=${AGENT_NAME:-agent-$(basename "$PROJ")-$$}
TMP_SIZE=${AGENT_TMP_SIZE:-512m}
UIDGID="$(id -u):$(id -g)"

# Never mounts Podman/Docker sockets: bind list is only PROJ → /work below.

args=(
  run --rm -it
  --name "$NAME"
  --read-only
  --tmpfs "/tmp:rw,size=${TMP_SIZE}"
  --security-opt no-new-privileges
  --cap-drop ALL
  --user "$UIDGID"
  --userns keep-id
  --network "$NET"
  -v "$PROJ:/work:Z"
  -w /work
  "$IMAGE"
)

if [[ $# -gt 0 ]]; then
  exec podman "${args[@]}" "$@"
else
  exec podman "${args[@]}"
fi
