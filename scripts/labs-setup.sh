#!/usr/bin/env bash
# labs-setup.sh — host dirs + Podman images for lab-triage/re/android/web.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LAB_ROOT="${LAB_ROOT:-/srv/lab}"

echo "→ Ensuring podman + bubblewrap..."
sudo pacman -S --needed --noconfirm podman podman-compose bubblewrap buildah

echo "→ Creating $LAB_ROOT/{samples,out}..."
sudo install -d -m 0755 -o root -g root "$LAB_ROOT"
sudo install -d -m 0755 -o "$USER" -g "$USER" "$LAB_ROOT/samples" "$LAB_ROOT/out"

# Host network: isolated build nets (pasta/slirp) throttle multi-GB pacman pulls
# (lab-re) to tens of KB/s behind dnscrypt. Runtime wrappers stay pasta/none.
echo "→ Building lab images (may take a while; --network=host for pacman)..."
_podman_build() { podman build --network=host "$@"; }
_podman_build -t localhost/lab-triage:latest "$REPO_ROOT/labs/lab-triage"
_podman_build -t localhost/lab-re:latest "$REPO_ROOT/labs/lab-re"
_podman_build -t localhost/lab-android:latest "$REPO_ROOT/labs/lab-android"
_podman_build -t localhost/lab-web:latest "$REPO_ROOT/labs/lab-web"
unset -f _podman_build

echo "→ Detonation helpers (virbr-malware + rootful lab-capture + INetSim/PolarProxy)..."
bash "$REPO_ROOT/scripts/lab-detonate.sh" setup || echo "WARN: lab-detonate setup skipped"
# setup builds lab-capture; capture-up cannot run without it, so stop here
# instead of letting a failed build pass as the warning above.
sudo podman image exists localhost/lab-capture:latest \
  || { echo "✗ lab-capture image missing (rootful podman): fix the build, then bash scripts/lab-detonate.sh setup" >&2; exit 1; }


# adb udev (host) — Android devices for lab-android
ANDROID_UDEV_USR="${ANDROID_UDEV_USR:-/usr/lib/udev/rules.d/51-android.rules}"
ANDROID_UDEV_ETC="${ANDROID_UDEV_ETC:-/etc/udev/rules.d/51-android.rules}"
_legacy_udev=0
if [[ -f "$ANDROID_UDEV_ETC" ]] && grep -qE '0666|plugdev' "$ANDROID_UDEV_ETC" 2>/dev/null; then
  _legacy_udev=1
fi
if [[ $_legacy_udev -eq 0 ]] && { [[ -f "$ANDROID_UDEV_USR" ]] || [[ -f "$ANDROID_UDEV_ETC" ]]; }; then
  echo "○ Android udev rules already present"
else
  if [[ $_legacy_udev -eq 1 ]]; then
    echo "→ Replacing legacy Android USB udev rules (0666/plugdev → uaccess)..."
  else
    echo "→ Installing Android USB udev rules (uaccess)..."
  fi
  sudo install -d -m 0755 "$(dirname "$ANDROID_UDEV_ETC")"
  sudo tee "$ANDROID_UDEV_ETC" >/dev/null <<'EOF'
# Android USB (lab-android / adb) — reload: udevadm control --reload-rules
SUBSYSTEM=="usb", ATTR{idVendor}=="18d1", MODE="0660", TAG+="uaccess"
SUBSYSTEM=="usb", ATTR{idVendor}=="04e8", MODE="0660", TAG+="uaccess"
SUBSYSTEM=="usb", ATTR{idVendor}=="22b8", MODE="0660", TAG+="uaccess"
SUBSYSTEM=="usb", ATTR{idVendor}=="0bb4", MODE="0660", TAG+="uaccess"
SUBSYSTEM=="usb", ATTR{idVendor}=="12d1", MODE="0660", TAG+="uaccess"
SUBSYSTEM=="usb", ATTR{idVendor}=="24e3", MODE="0660", TAG+="uaccess"
SUBSYSTEM=="usb", ATTR{idVendor}=="05c6", MODE="0660", TAG+="uaccess"
EOF
  sudo udevadm control --reload-rules 2>/dev/null || true
fi
unset _legacy_udev

echo "✓ labs ready"
echo "  samples: $LAB_ROOT/samples  out: $LAB_ROOT/out"
echo "  wrappers: lab-triage | lab-re | lab-android | lab-web | lab-detonate | lab-mcp"
echo "  malware VM net: virbr-malware (lab-malware zone, DROP)"
echo "  MCP example: labs/mcp-host.example.json → scripts/lab-mcp.sh"
