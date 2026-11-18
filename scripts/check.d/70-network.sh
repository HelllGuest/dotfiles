# 70-network.sh — sourced by scripts/check.sh at top level, in name order:
# shares check_fail/CHECK_FAILED, MODE and REPO_ROOT with the other checks.
# shellcheck shell=bash
# Tailscale, firewalld, ufw.

echo "--- Tailscale / firewalld ---"
if command -v tailscale >/dev/null 2>&1; then
    echo "✓ tailscale installed"
    # Nothing in the repo enables it (network service, opt-in). Without the
    # daemon there is no tailscale0, so firewalld-tailscale.sh cannot bind it.
    if systemctl is-enabled --quiet tailscaled 2>/dev/null; then
        echo "✓ tailscaled enabled"
    else
        echo "○ tailscaled not enabled — sudo systemctl enable --now tailscaled && sudo tailscale up, then bash scripts/firewalld-tailscale.sh"
    fi
    if systemctl is-active --quiet firewalld 2>/dev/null; then
        if firewall-cmd --zone=trusted --list-interfaces 2>/dev/null | grep -qw tailscale0 \
          || firewall-cmd --get-active-zones 2>/dev/null | grep -A1 '^trusted' | grep -qw tailscale0; then
            echo "✓ firewalld trusted zone includes tailscale0"
        else
            echo "○ firewalld active but tailscale0 not in trusted — bash scripts/firewalld-tailscale.sh"
        fi
    else
        echo "○ firewalld inactive (run scripts/firewalld-lab-zones.sh)"
    fi
else
    echo "○ tailscale not installed"
fi
if systemctl is-active --quiet firewalld 2>/dev/null; then
    echo "✓ firewalld active (default=$(firewall-cmd --get-default-zone 2>/dev/null || echo ?))"
elif systemctl is-enabled --quiet firewalld 2>/dev/null; then
    check_fail "firewalld enabled but not active"
else
    check_fail "firewalld not enabled — pacman -S firewalld && bash scripts/firewalld-lab-zones.sh"
fi
if pacman -Q ufw >/dev/null 2>&1; then
    check_fail "ufw package still installed — remove with: bash scripts/firewalld-lab-zones.sh"
else
    echo "✓ ufw not installed"
fi
if systemctl is-active --quiet ufw 2>/dev/null; then
    check_fail "ufw.service is active — run bash scripts/firewalld-lab-zones.sh"
elif systemctl is-enabled ufw 2>&1 | grep -qi masked; then
    echo "✓ ufw masked"
elif systemctl is-enabled --quiet ufw 2>/dev/null; then
    check_fail "ufw.service is enabled — run bash scripts/firewalld-lab-zones.sh"
fi
