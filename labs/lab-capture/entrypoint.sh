#!/usr/bin/env bash
set -euo pipefail
mkdir -p /var/log/inetsim
echo "→ INetSim bound to 192.168.200.1 (virbr-malware)"
exec inetsim --config=/etc/inetsim/inetsim.conf
