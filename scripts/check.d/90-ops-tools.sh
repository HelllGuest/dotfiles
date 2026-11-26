# 90-ops-tools.sh — sourced by scripts/check.sh at top level, in name order:
# shares check_fail/CHECK_FAILED, MODE and REPO_ROOT with the other checks.
# shellcheck shell=bash
# Ops/privacy tools, paccache, usbguard, dnscrypt-proxy.

echo "--- Ops / privacy tools ---"
for _bin in paccache mat2 exiftool bleachbit usbguard dnscrypt-proxy; do
    if command -v "$_bin" >/dev/null 2>&1; then
        echo "✓ $_bin present"
    else
        echo "○ $_bin missing — pacman -S from packages/pacman.txt / ./install.sh"
    fi
done
unset _bin
if systemctl is-enabled --quiet paccache.timer 2>/dev/null; then
    echo "✓ paccache.timer enabled"
else
    echo "○ paccache.timer off — bash security/scripts/ops-hygiene.sh"
fi
if systemctl --user is-enabled --quiet tmp-semgrep-cleanup.timer 2>/dev/null; then
    echo "✓ tmp-semgrep-cleanup.timer enabled"
else
    check_fail "tmp-semgrep-cleanup.timer not enabled (stow links it; ./install.sh enables it) — systemctl --user enable --now tmp-semgrep-cleanup.timer"
fi
if systemctl is-active --quiet usbguard 2>/dev/null; then
    echo "✓ usbguard active"
else
    echo "○ usbguard inactive — bash security/scripts/usbguard-setup.sh (allowlists plugged devices first)"
fi
if systemctl is-active --quiet dnscrypt-proxy 2>/dev/null; then
    echo "✓ dnscrypt-proxy active"
else
    echo "○ dnscrypt-proxy inactive — bash security/scripts/dnscrypt-setup.sh (Tailscale MagicDNS may override)"
fi
