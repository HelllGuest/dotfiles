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

# Refuse host escapes, home/hidden config dirs, dotfiles repo, and read-only samples.
home=$(readlink -f -- "${HOME:-/}" 2>/dev/null || echo "${HOME:-/}")
dotfiles=$(readlink -f -- "${DOTFILES_DIR:-$home/dotfiles}" 2>/dev/null || echo "$home/dotfiles")
samples=$(readlink -f -- "${LAB_SAMPLES:-/srv/lab/samples}" 2>/dev/null || echo "${LAB_SAMPLES:-/srv/lab/samples}")
case $PROJ in
  /|/etc|/etc/*|/usr|/usr/*|/var|/boot|/boot/*|/root|/root/*|/proc|/proc/*|/sys|/sys/*|/dev|/dev/*)
    die "refusing to mount system path: $PROJ" ;;
esac
if [[ "$PROJ" == "$home" || "$home/" == "$PROJ"/* ]]; then
  die "refusing to mount home/ancestor path: $PROJ"
elif [[ "$PROJ/" == "$home"/.* ]]; then
  die "refusing to mount hidden config dir under home: $PROJ"
elif [[ "$PROJ" == "$dotfiles" || "$PROJ" == "$dotfiles"/* ]]; then
  die "refusing to mount dotfiles repo: $PROJ"
elif [[ -n $samples && ( "$PROJ" == "$samples" || "$PROJ" == "$samples"/* || "$samples" == "$PROJ"/* ) ]]; then
  die "refusing to mount read-only samples path: $PROJ"
fi

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
