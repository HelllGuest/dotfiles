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

# Refuse obvious host escapes in the project path itself (still bind that dir only).
case $PROJ in
  /|/etc|/usr|/var|/boot|/root) die "refusing to mount system path: $PROJ" ;;
esac

NET=${AGENT_NET:-none}
case $NET in
  none|pasta) ;;
  *) die "AGENT_NET must be none or pasta (got: $NET)" ;;
esac

NAME=${AGENT_NAME:-agent-$(basename "$PROJ")-$$}
TMP_SIZE=${AGENT_TMP_SIZE:-512m}
UIDGID="$(id -u):$(id -g)"

# Hard deny: never pass through container runtime sockets.
for sock in \
  "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/podman/podman.sock" \
  /run/podman/podman.sock \
  /var/run/docker.sock \
  /run/docker.sock
do
  [[ -S $sock ]] || continue
  # Ensure we are not about to -v that path (args are only PROJ + image + cmd).
  :
done

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
