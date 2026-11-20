#!/usr/bin/env bash
set -euo pipefail
# INetSim opens files as root (no DAC_OVERRIDE: caps are dropped) and writes
# them after switching to user inetsim, so every writable dir is root-owned,
# group inetsim, 0775. The root fs is read-only: captured mail, FTP uploads and
# HTTP POST bodies live on host volumes (see lab-detonate.sh capture-up).
for d in /var/log/inetsim /var/lib/inetsim/smtp /var/lib/inetsim/ftp/upload /var/lib/inetsim/http/postdata; do
  mkdir -p "$d"
  chown root:inetsim "$d"
  chmod 0775 "$d"
done
bind="${LAB_CAPTURE_BIND:-192.168.200.1}"
[[ "$bind" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || { echo "lab-capture: invalid LAB_CAPTURE_BIND: $bind" >&2; exit 1; }
sed "s/192\.168\.200\.1/${bind}/g" /etc/inetsim/inetsim.conf >/tmp/inetsim.conf
echo "→ INetSim bound to ${bind} (virbr-malware)"
exec inetsim --config=/tmp/inetsim.conf
