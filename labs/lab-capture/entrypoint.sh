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
echo "→ INetSim bound to 192.168.200.1 (virbr-malware)"
exec inetsim --config=/etc/inetsim/inetsim.conf
