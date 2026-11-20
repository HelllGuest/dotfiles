#!/usr/bin/env bash
# lab-mcp.sh — run browser/Flutter/adb MCP servers inside lab images (stdio).
#
# Usage (Cursor / Claude / OpenCode MCP "command"):
#   bash /path/to/dotfiles/scripts/lab-mcp.sh playwright
#   bash /path/to/dotfiles/scripts/lab-mcp.sh devtools
#   bash /path/to/dotfiles/scripts/lab-mcp.sh flutter
#   bash /path/to/dotfiles/scripts/lab-mcp.sh adb
set -euo pipefail

die() { echo "ERR $*" >&2; exit 1; }

# Shared with the lab-* shell wrappers: never mount home, its ancestors,
# hidden config dirs, the dotfiles repo or the samples dir as /work.
# shellcheck source=lib/lab-workdir.sh
source "$(cd "$(dirname "$0")" && pwd)/lib/lab-workdir.sh"
work_dir() { LAB_OUT="${LAB_OUT:-/srv/lab/out}" LAB_SAMPLES="${LAB_SAMPLES:-/srv/lab/samples}" _lab_work_dir; }

run_web() {
  local cmd=$1
  podman image exists localhost/lab-web:latest 2>/dev/null \
    || die "build lab-web first: bash scripts/labs-setup.sh"
  local work
  work=$(work_dir)
  exec podman run --rm -i --network pasta \
    --security-opt no-new-privileges --cap-drop ALL \
    --userns keep-id --user "$(id -u):$(id -g)" \
    -v "${work}:/work:Z" -w /work \
    localhost/lab-web:latest "$cmd"
}

run_android() {
  local cmd=$1
  podman image exists localhost/lab-android:latest 2>/dev/null \
    || die "build lab-android first: bash scripts/labs-setup.sh"
  local work extra=()
  work=$(work_dir)
  [[ -e /dev/kvm ]] && extra+=(--device /dev/kvm)
  # Host adb USB: optional bind of host adb server socket is intentionally omitted
  # (keeps host secrets out). Use emulator inside lab or TCP adb.
  exec podman run --rm -i --network pasta \
    --security-opt no-new-privileges --cap-drop ALL \
    --userns keep-id --user "$(id -u):$(id -g)" \
    "${extra[@]}" \
    -v "lab-android-flutter:/opt/flutter:U" \
    -v "lab-android-sdk:/opt/android-sdk:U" \
    -v "${work}:/work:Z" -w /work \
    -v "${LAB_SAMPLES:-/srv/lab/samples}:/srv/lab/samples:ro,Z" \
    -v "${LAB_OUT:-/srv/lab/out}:/srv/lab/out:Z" \
    localhost/lab-android:latest "$cmd"
}

main() {
  local which="${1:-}"
  case "$which" in
    playwright) run_web mcp-playwright ;;
    devtools) run_web mcp-devtools ;;
    flutter) run_android mcp-flutter ;;
    adb) run_android mcp-adb ;;
    *)
      echo "usage: lab-mcp.sh {playwright|devtools|flutter|adb}" >&2
      exit 2
      ;;
  esac
}

main "$@"
