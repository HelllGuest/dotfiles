#!/usr/bin/env bash
# labs-setup.sh — host dirs + Podman images for lab-triage/re/android/web.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LAB_ROOT="${LAB_ROOT:-/srv/lab}"

need() { command -v "$1" >/dev/null 2>&1 || { echo "missing $1" >&2; exit 1; }; }

echo "→ Ensuring podman + bubblewrap..."
sudo pacman -S --needed --noconfirm podman podman-compose bubblewrap buildah

echo "→ Creating $LAB_ROOT/{samples,out}..."
sudo install -d -m 0755 -o root -g root "$LAB_ROOT"
sudo install -d -m 0755 -o "$USER" -g "$USER" "$LAB_ROOT/samples" "$LAB_ROOT/out"

echo "→ Building lab images (may take a while)..."
podman build -t localhost/lab-triage:latest "$REPO_ROOT/labs/lab-triage"
podman build -t localhost/lab-re:latest "$REPO_ROOT/labs/lab-re"
podman build -t localhost/lab-android:latest "$REPO_ROOT/labs/lab-android"
podman build -t localhost/lab-web:latest "$REPO_ROOT/labs/lab-web"
podman build -t localhost/lab-capture:latest "$REPO_ROOT/labs/lab-capture"

echo "→ Detonation helpers (virbr-malware + INetSim/PolarProxy)..."
bash "$REPO_ROOT/scripts/lab-detonate.sh" setup || echo "WARN: lab-detonate setup skipped"


# adb udev (host) — Android devices for lab-android
if [[ -f /usr/lib/udev/rules.d/51-android.rules ]] || [[ -f /etc/udev/rules.d/51-android.rules ]]; then
  echo "○ Android udev rules already present"
else
  echo "→ Installing permissive Android USB udev rules (plugdev)..."
  sudo tee /etc/udev/rules.d/51-android.rules >/dev/null <<'EOF'
# Android USB (lab-android / adb) — reload: udevadm control --reload-rules
SUBSYSTEM=="usb", ATTR{idVendor}=="18d1", MODE="0666", GROUP="plugdev"
SUBSYSTEM=="usb", ATTR{idVendor}=="04e8", MODE="0666", GROUP="plugdev"
SUBSYSTEM=="usb", ATTR{idVendor}=="22b8", MODE="0666", GROUP="plugdev"
SUBSYSTEM=="usb", ATTR{idVendor}=="0bb4", MODE="0666", GROUP="plugdev"
SUBSYSTEM=="usb", ATTR{idVendor}=="12d1", MODE="0666", GROUP="plugdev"
SUBSYSTEM=="usb", ATTR{idVendor}=="24e3", MODE="0666", GROUP="plugdev"
SUBSYSTEM=="usb", ATTR{idVendor}=="05c6", MODE="0666", GROUP="plugdev"
EOF
  sudo udevadm control --reload-rules 2>/dev/null || true
fi

echo "✓ labs ready"
echo "  samples: $LAB_ROOT/samples  out: $LAB_ROOT/out"
echo "  wrappers: lab-triage | lab-re | lab-android | lab-web | lab-detonate | lab-mcp"
echo "  malware VM net: virbr-malware (lab-malware / block zone)"
echo "  MCP example: labs/mcp-host.example.json → scripts/lab-mcp.sh"
