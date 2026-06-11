#!/bin/bash
# Laptop specific settings
echo "Applying Laptop profile..."

# Delegate to X1 profile only on X1 models (not every ThinkPad)
dmi_label=""
for f in product_family product_version product_name; do
    if [ -r "/sys/class/dmi/id/$f" ]; then
        dmi_label+=" $(cat "/sys/class/dmi/id/$f")"
    fi
done
if [ -z "$dmi_label" ] && command -v dmidecode >/dev/null 2>&1; then
    dmi_label="$(dmidecode -s system-product-name 2>/dev/null || true)"
fi
if echo "$dmi_label" | grep -qiE 'ThinkPad[[:space:]]*X1|X1[[:space:]]+Yoga|X1[[:space:]]+Carbon'; then
    if [ -f "profiles/thinkpad-x1.sh" ]; then
        # shellcheck source=/dev/null
        source "profiles/thinkpad-x1.sh"
        exit 0
    fi
fi

# General laptop tools (non-ThinkPad)
sudo pacman -S --needed --noconfirm power-profiles-daemon brightnessctl
sudo systemctl enable --now power-profiles-daemon
