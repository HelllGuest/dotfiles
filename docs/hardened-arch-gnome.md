# Definitive Hardened Arch Linux + GNOME Wayland Guide

## For the Lenovo ThinkPad X1 Yoga Gen 5

### Modern Security, Power Management, Btrfs Snapshots, UKIs, and Secure Boot

This guide builds a modern Arch Linux workstation with:

* UEFI boot
* LUKS2 full-disk encryption
* Btrfs subvolumes
* GNOME on Wayland
* linux-lts primary kernel
* linux-hardened fallback kernel
* AppArmor
* zram compressed swap
* UFW firewall
* Snapper snapshots
* rootless Podman
* Flatpak sandboxing
* Unified Kernel Images (UKIs)
* custom Secure Boot keys using [sbctl](https://github.com/Foxboron/sbctl?utm_source=chatgpt.com)

This guide prioritizes:

* stability
* maintainability
* strong defaults
* practical hardening
* laptop battery longevity
* developer workflows

> **Automated:** This guide is implemented end-to-end by [`scripts/arch-install.sh`](../scripts/arch-install.sh) — run it from the Arch ISO instead of the manual phases:
> ```bash
> bash <(curl -fsSL https://raw.githubusercontent.com/HelllGuest/dotfiles/main/scripts/arch-install.sh)
> ```
> Dry-run first in a UEFI VM with [`scripts/arch-install-vmtest.sh`](../scripts/arch-install-vmtest.sh). The manual phases below remain the reference for what it does and for customizing.

> **Dotfiles:** After completing this guide, continue with [PHASE 27 — Dotfiles Setup](#phase-27--dotfiles-setup) or jump to the [dotfiles README](../README.md) for shell and maintenance.

---

# PHASE 1 — BIOS / UEFI CONFIGURATION

Enter BIOS:

* Reboot
* Press `F1`

---

## Security → Secure Boot

Set:

```text
Disabled
```

(You will re-enable Secure Boot later using your own keys.)

---

## Config → Power → Sleep State

Set:

```text
Linux
```

Your system supports proper deep sleep:

```text
s2idle [deep]
```

Deep sleep (S3) is selected two ways in this repo: the `mem_sleep_default=deep`
kernel cmdline param (PHASE 9/21), and `stow/system/etc/systemd/sleep.conf.d/`
(`SuspendState=mem` + `MemorySleepMode=deep`). Either forces S3 over s2idle for
lower standby drain. Confirm after resume with `journalctl -b | grep "suspend entry"`
→ expect `PM: suspend entry (deep)`.

---

## Security → Virtualization

Enable:

* Intel Virtualization Technology
* Intel VT-d

---

## Security → Intel SGX

Disable unless specifically required.

---

## Security → Thunderbolt BIOS Assist Mode

Enable.

---

## Save and Exit

Press:

```text
F10
```

---

# PHASE 2 — BOOT ARCH INSTALLER

Boot the official Arch ISO in UEFI mode.

Verify UEFI:

```bash
cat /sys/firmware/efi/fw_platform_size
```

Expected:

```text
64
```

---

# Connect to Wi-Fi

Launch:

```bash
iwctl
```

Inside iwctl:

```bash
device list
station wlan0 scan
station wlan0 get-networks
station wlan0 connect YOUR_WIFI
exit
```

---

# Enable Network Time

```bash
timedatectl set-ntp true
```

---

# PHASE 3 — DISK PARTITIONING

Verify disks:

```bash
lsblk
```

Assume target drive:

```text
/dev/nvme0n1
```

---

# Create GPT Layout

Launch:

```bash
gdisk /dev/nvme0n1
```

Inside gdisk:

```text
o
y

n
1
<enter>
+1G
ef00

n
2
<enter>
<enter>
8309

w
y
```

---

# Final Layout

| Partition | Purpose               |
| --------- | --------------------- |
| nvme0n1p1 | EFI System Partition  |
| nvme0n1p2 | LUKS2 encrypted Linux |

---

# PHASE 4 — LUKS2 ENCRYPTION

Create encrypted container:

```bash
cryptsetup luksFormat \
--type luks2 \
--pbkdf argon2id \
/dev/nvme0n1p2
```

Open encrypted container:

```bash
cryptsetup open /dev/nvme0n1p2 cryptroot
```

---

# PHASE 5 — BTRFS FILESYSTEM

Format filesystems:

```bash
mkfs.fat -F32 -n EFI /dev/nvme0n1p1
mkfs.btrfs -L archroot /dev/mapper/cryptroot
```

---

# Create Btrfs Subvolumes

Temporary mount:

```bash
mount /dev/mapper/cryptroot /mnt
```

Create subvolumes:

```bash
btrfs subvolume create /mnt/@
btrfs subvolume create /mnt/@home
btrfs subvolume create /mnt/@snapshots
btrfs subvolume create /mnt/@var_log
btrfs subvolume create /mnt/@var_cache
btrfs subvolume create /mnt/@tmp
```

`@tmp` keeps `/tmp` on disk (not tmpfs) so heavy builds can't fill a RAM-capped
`/tmp` or trigger OOM, and `nodatacow` avoids CoW churn on temp files. As a
separate subvolume it is excluded from `@` snapshots automatically.

Unmount:

```bash
umount /mnt
```

---

# Mount Final Layout

## Root

```bash
mount -o noatime,compress=zstd:3,subvol=@ \
/dev/mapper/cryptroot /mnt
```

---

## Home

```bash
mkdir -p /mnt/home

mount -o noatime,compress=zstd:3,subvol=@home \
/dev/mapper/cryptroot /mnt/home
```

---

## Snapshots

```bash
mkdir -p /mnt/.snapshots

mount -o noatime,compress=zstd:3,subvol=@snapshots \
/dev/mapper/cryptroot /mnt/.snapshots
```

---

## Logs

```bash
mkdir -p /mnt/var/log

mount -o noatime,compress=zstd:3,subvol=@var_log \
/dev/mapper/cryptroot /mnt/var/log
```

---

## Cache

```bash
mkdir -p /mnt/var/cache

mount -o noatime,compress=zstd:3,subvol=@var_cache \
/dev/mapper/cryptroot /mnt/var/cache
```

---

## Tmp (disk-backed, nodatacow)

```bash
mkdir -p /mnt/tmp

mount -o noatime,nodatacow,nosuid,nodev,subvol=@tmp \
/dev/mapper/cryptroot /mnt/tmp

chmod 1777 /mnt/tmp
```

`nodatacow` excludes compression by design (don't add `compress` here). After
`genfstab`, edit the `/tmp` line so it carries `nodatacow,nosuid,nodev,nofail`
(add `nofail` — a `/tmp` mount failure then falls back to the dir on `@` instead
of dropping boot to emergency). Because an fstab `/tmp` entry exists, systemd uses
it instead of the default tmpfs `tmp.mount` — no masking required.

---

## EFI Partition

```bash
mkdir /mnt/boot

mount /dev/nvme0n1p1 /mnt/boot
```

---

# Important SSD Note

Use:

* `fstrim.timer`

Do NOT use:

```text
discard
```

as a Btrfs mount option.

Modern SSDs perform better with periodic TRIM.

---

# PHASE 6 — INSTALL BASE SYSTEM

Install base packages:

```bash
pacstrap -K /mnt \
base \
base-devel \
linux-lts \
linux-lts-headers \
linux-hardened \
linux-hardened-headers \
linux-firmware \
intel-ucode \
btrfs-progs \
networkmanager \
sudo \
nano \
vim \
git \
reflector \
pacman-contrib
```

Generate fstab:

```bash
genfstab -U /mnt >> /mnt/etc/fstab
```

Enter chroot:

```bash
arch-chroot /mnt
```

---

# PHASE 7 — SYSTEM CONFIGURATION

# Timezone

```bash
ln -sf /usr/share/zoneinfo/Europe/Dublin /etc/localtime
```

Sync hardware clock:

```bash
hwclock --systohc
```

---

# Locale

Edit:

```bash
nano /etc/locale.gen
```

Uncomment:

```text
en_IE.UTF-8 UTF-8
en_GB.UTF-8 UTF-8
```

Generate locales:

```bash
locale-gen
```

Set locale:

```bash
echo "LANG=en_IE.UTF-8" > /etc/locale.conf
```

Keyboard layout:

```bash
echo "KEYMAP=uk" > /etc/vconsole.conf
```

---

# Hostname

```bash
echo "thinkpad-x1" > /etc/hostname
```

---

# Hosts File

```bash
nano /etc/hosts
```

Contents:

```text
127.0.0.1 localhost
::1       localhost
127.0.1.1 thinkpad-x1.localdomain thinkpad-x1
```

---

# Root Password

```bash
passwd
```

---

# Create User

```bash
useradd -m -G wheel -s /bin/zsh yourusername
passwd yourusername
chsh -s /bin/zsh yourusername
```

Enable sudo:

```bash
EDITOR=nano visudo
```

Uncomment:

```text
%wheel ALL=(ALL:ALL) ALL
```

---

# PHASE 8 — MKINITCPIO

Edit:

```bash
nano /etc/mkinitcpio.conf
```

Use:

```text
HOOKS=(base systemd autodetect microcode modconf kms keyboard sd-vconsole block sd-encrypt filesystems fsck)
```

Generate initramfs:

```bash
mkinitcpio -P
```

---

# PHASE 9 — SYSTEMD-BOOT

Install bootloader:

```bash
bootctl install
```

---

# Configure Loader

```bash
nano /boot/loader/loader.conf
```

Contents:

```text
default arch-lts.conf
timeout 3
editor no
console-mode max
```

---

# Get LUKS UUID

```bash
blkid -s UUID -o value /dev/nvme0n1p2
```

Copy UUID.

---

# Create Hardened Boot Entry (fallback)

```bash
nano /boot/loader/entries/arch-hardened.conf
```

Contents:

```text
title   Arch Linux (Hardened)
linux   /vmlinuz-linux-hardened
initrd  /intel-ucode.img
initrd  /initramfs-linux-hardened.img
options rd.luks.name=YOUR_UUID=cryptroot root=/dev/mapper/cryptroot rootflags=subvol=@ rw quiet loglevel=3 mem_sleep_default=deep apparmor=1 security=apparmor intel_iommu=on
```

---

# Create LTS Entry

```bash
nano /boot/loader/entries/arch-lts.conf
```

Contents:

```text
title   Arch Linux (LTS)
linux   /vmlinuz-linux-lts
initrd  /intel-ucode.img
initrd  /initramfs-linux-lts.img
options rd.luks.name=YOUR_UUID=cryptroot root=/dev/mapper/cryptroot rootflags=subvol=@ rw quiet loglevel=3 mem_sleep_default=deep apparmor=1 security=apparmor intel_iommu=on
```

---

# PHASE 10 — GNOME + SECURITY STACK

Install packages:

Minimal GNOME — **not** the full `gnome` meta-package (which pulls ~60 pkgs: games, maps, weather, music, contacts, tour). Curated essentials + a few utils; install the rest via Flatpak (Phase 16).
```bash
pacman -S \
gnome-shell \
gnome-session \
gdm \
gnome-control-center \
gnome-keyring \
gnome-backgrounds \
nautilus \
gnome-console \
gnome-text-editor \
gnome-system-monitor \
gnome-calculator \
loupe \
evince \
gnome-disk-utility \
xdg-user-dirs-gtk \
xdg-desktop-portal \
xdg-desktop-portal-gnome \
polkit \
flatpak \
fwupd \
bolt \
pipewire \
pipewire-pulse \
wireplumber \
earlyoom \
power-profiles-daemon \
sof-firmware \
alsa-ucm-conf \
iio-sensor-proxy \
fprintd \
gnome-software
```

Enable services:

```bash
systemctl enable NetworkManager
systemctl enable gdm
systemctl enable apparmor
systemctl enable fstrim.timer
systemctl enable bolt.service
systemctl enable earlyoom.service
```

---

# Verify GDM Wayland Session

GDM may default to X11. Force Wayland:

```bash
nano /etc/gdm/custom.conf
```

Ensure uncommented:

```text
WaylandEnable=true
```

---

# PHASE 11 — ZRAM

**Option A — Dotfiles (recommended after cloning this repo):**

```bash
cd ~/dotfiles
sudo stow -d stow -t / zram
```

If stow reports a conflict, remove the existing plain file first (only when content matches `stow/zram/etc/systemd/zram-generator.conf`):

```bash
sudo rm /etc/systemd/zram-generator.conf
sudo stow -d ~/dotfiles/stow -t / zram
```

**Option B — Manual:**

Create:

```bash
nano /etc/systemd/zram-generator.conf
```

Contents:

```ini
[zram0]
zram-size = min(ram / 2, 8192)
compression-algorithm = zstd
swap-priority = 100
fs-type = swap
```

**Note on vm.swappiness:** With zram enabled and `vm.swappiness = 100`, the system aggressively uses compressed memory. This is intentional for battery efficiency but may cause performance lag under extreme memory pressure. Monitor with `zramctl` and adjust if needed.

---

# PHASE 12 — SYSCTL HARDENING

Create:

```bash
nano /etc/sysctl.d/99-security.conf
```

Contents:

```ini
kernel.kptr_restrict = 2
kernel.dmesg_restrict = 1
kernel.unprivileged_bpf_disabled = 1
kernel.yama.ptrace_scope = 1
net.core.bpf_jit_harden = 2
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0
vm.swappiness = 100
```

Apply:

```bash
sysctl --system
```

---

## User namespaces (required for Flatpak / Podman under linux-hardened)

`linux-hardened` ships `kernel.unprivileged_userns_clone = 0`, which breaks the
Flatpak sandbox, rootless Podman, Chromium/Firefox sandboxes, and GNOME
thumbnailers. `linux-lts` has no such key. Create one drop-in that works on both:

```bash
nano /etc/sysctl.d/99-userns.conf
```

```ini
# Leading '-' = ignore-if-absent. This knob is a downstream patch carried by
# linux-hardened (default 0) but NOT by mainline linux-lts, so the '-' makes the
# line set it under hardened and silently no-op under LTS (no `sysctl --system` error).
-kernel.unprivileged_userns_clone = 1
```

> Tradeoff: re-enabling userns relaxes part of what `linux-hardened` buys. Since
> `linux-lts` is the daily driver, this only applies when you deliberately boot
> the Hardened entry. For maximum lockdown, remove this file and run
> Flatpak/Podman only under LTS.

---

# PHASE 13 — FIREWALL

Configure UFW:

```bash
ufw default deny incoming
ufw default allow outgoing
ufw enable
```

Default behavior:

* **deny incoming** — All inbound connections rejected unless explicitly allowed
* **allow outgoing** — All outbound connections permitted

Add SSH rule (if needed):

```bash
ufw allow ssh
```

Enable:

```bash
systemctl enable ufw.service
```

## Waydroid internet (NAT masquerade)

Waydroid bridges the container on `waydroid0` (`192.168.240.1/24`) but provides
no outbound NAT, so containers have no return path and no internet. Masquerade
the container subnet and allow its DHCP/DNS to the host:

```bash
# host-side DHCP (67) + DNS (53) for the container's dnsmasq
ufw allow 53/udp
ufw allow 67/udp
```

Deploy the idempotent `waydroid-nat.service` unit (tracked at `stow/system/etc/systemd/system/waydroid-nat.service`):

```bash
sudo install -m 644 stow/system/etc/systemd/system/waydroid-nat.service /etc/systemd/system/waydroid-nat.service
sudo systemctl daemon-reload
sudo systemctl enable --now waydroid-nat.service
```

This service ensures the masquerade rule is added exactly once and survives `ufw reload` cycles.

`DEFAULT_FORWARD_POLICY="ACCEPT"` in `/etc/default/ufw` is required for
forwarding (default on this system).

---

# PHASE 14 — THINKPAD OPTIMIZATION

Install:

```bash
pacman -S \
power-profiles-daemon \
powertop \
sof-firmware \
alsa-ucm-conf \
fprintd \
iio-sensor-proxy
```

Enable:

```bash
systemctl enable --now power-profiles-daemon
systemctl enable --now iio-sensor-proxy
```

**Power stack note:** this system uses **power-profiles-daemon (PPD)** only.

* **TLP is *not* used** — it conflicts with PPD (`PLATFORM_PROFILE.../CPU_ENERGY_PERF_POLICY... not set because power-profiles-daemon is running`). Do not install `tlp`/`tlp-rdw`.
* **thermald is *not* used** — on the X1 it self-exits every boot (`[dytc_lapmode] present: Thermald can't run on this platform`); thermal is firmware-managed (Intel DPTF). Leave it uninstalled/disabled.

---

# Configure Battery Thresholds

Without TLP, set ThinkPad charge thresholds via the `thinkpad_acpi` sysfs
interface:

```bash
echo 70 | tee /sys/class/power_supply/BAT0/charge_control_start_threshold
echo 80 | tee /sys/class/power_supply/BAT0/charge_control_end_threshold
```

Persist across reboots with a small systemd unit or udev rule (sysfs values
reset on boot), e.g. a `oneshot` service that writes both files.

---

# Fingerprint Enrollment

```bash
fprintd-enroll
```

**If you do not use the fingerprint reader:** the Synaptics Prometheus sensor
(`06cb:00bd`) bounces on every resume (`xHC error in resume`, repeated
`usb 1-9: reset`) and wastes idle power. The dotfiles ship
`stow/system/etc/udev/rules.d/72-fingerprint-disable.rules`, which powers off
its root-hub port on enumeration. Re-enable by deleting that rule,
`sudo udevadm control --reload`, clearing the port `disable` flag, then reboot.

---

# PHASE 15 — SNAPSHOTS

Install:

```bash
pacman -S snapper snap-pac
```

Initialize Snapper:

```bash
snapper -c root create-config /
```

Enable timers:

```bash
systemctl enable --now snapper-timeline.timer
systemctl enable --now snapper-cleanup.timer
```

---

# PHASE 16 — FLATPAK SANDBOXING

Enable Flathub:

```bash
flatpak remote-add --if-not-exists flathub \
https://flathub.org/repo/flathub.flatpakrepo
```

Install apps:

```bash
# Browsers
flatpak install flathub com.brave.Browser
flatpak install flathub io.github.zen_browser.zen
flatpak install flathub com.google.Chrome
flatpak install flathub io.gitlab.librewolf-community

# VPN
flatpak install flathub com.protonvpn.www

# IDE (Android Studio is in packages/flatpak.txt; VS Code is AUR visual-studio-code-bin)
flatpak install flathub com.google.AndroidStudio
```

> After dotfiles install, `./install.sh` installs all apps in `packages/flatpak.txt` and `packages/aur.txt` automatically.

---

# PHASE 17 — ROOTLESS PODMAN

Install:

```bash
pacman -S podman
```

IMPORTANT:

Apply No-COW BEFORE creating containers.

```bash
mkdir -p ~/.local/share/containers/storage
chattr +C ~/.local/share/containers/storage
```

Enable socket:

```bash
systemctl --user enable --now podman.socket
```

Configure Docker compatibility:

Dotfiles set `DOCKER_HOST` in `~/.shell-exports` **only when** the Podman socket is running. If you use **Docker** instead (recommended when `docker.service` is enabled and Podman is not), leave Podman stopped — `DOCKER_HOST` stays unset and the Docker CLI talks to `/var/run/docker.sock`.

Podman-only (optional):

```bash
systemctl --user enable --now podman.socket
# ~/.shell-exports detects the socket automatically after exec zsh
```

Legacy manual override (not needed with current dotfiles):

```bash
mkdir -p ~/.config/secrets
echo 'export DOCKER_HOST="unix://$XDG_RUNTIME_DIR/podman/podman.sock"' >> ~/.config/secrets/env
```

Docker daemon (typical on this setup):

```bash
pacman -S docker docker-compose
sudo systemctl enable --now docker
sudo usermod -aG docker "$USER"
newgrp docker   # or log out/in
docker ps
```

---

# PHASE 17b — NODE.JS (FNM)

Install via dotfiles (`packages/pacman.txt`) or:

```bash
pacman -S fnm
```

Shell hooks (after `./install.sh` / `stow-only.sh` + `exec zsh`):

* Zsh: `fnm env --use-on-cd` in `.zsh-plugins`
* Bash: `fnm env --use-on-cd` in `.bashrc`

When a project declares Node in `.nvmrc`, `.node-version`, or `package.json` `engines.node`, fnm may prompt on shell start:

```text
Can't find an installed Node version matching >=22.12.0.
Do you want to install it? answer [y/N]:
```

Install the requested version once:

```bash
fnm install 22
fnm default 22
```

Or from inside the project: `fnm install`. To stop auto-switching (no prompt), remove `--use-on-cd` from the hook lines above.

List installed versions: `fnm list`. Current: `fnm current`.

---

# PHASE 17c — HEADROOM (CLAUDE / CURSOR)

Optional context compression proxy ([Headroom](https://github.com/headroomlabs-ai/headroom)). Installed user-local via **pipx** (`python-pipx` in `packages/pacman.txt`).

```bash
bash scripts/headroom-setup.sh   # install + Claude MCP registration
```

| Shell command | Purpose |
|---------------|---------|
| `hr-claude` | `headroom wrap claude` — proxy + launch Claude Code |
| `hr-cursor` | Start proxy; paste printed Base URL into Cursor → Settings → Models |
| `hr-proxy` | Proxy only (`HEADROOM_PORT`, default `8787`) |

**Claude Code:** one terminal — run `hr-claude` from the project directory.

**Cursor:** keep the `hr-cursor` terminal open; configure Override OpenAI Base URL in the IDE (Cursor does not read shell env for API routing). Headroom 0.27 registers MCP for Claude only — not Cursor yet.

**Other agents:** Antigravity CLI (`agy`) and Kiro are not in the stable Headroom wrap matrix; `hr-proxy` works only if the tool supports a custom OpenAI/Anthropic base URL.

---

# PHASE 18 — FIRMWARE UPDATES

Refresh metadata:

```bash
fwupdmgr refresh
```

Check updates:

```bash
fwupdmgr get-updates
```

Install updates:

```bash
fwupdmgr update
```

---

# PHASE 19 — PACMAN TUNING

Edit:

```bash
nano /etc/pacman.conf
```

Enable:

```ini
Color
ParallelDownloads = 10
VerbosePkgLists
ILoveCandy
```

---

# Reflector Configuration

Create:

```bash
nano /etc/xdg/reflector/reflector.conf
```

Contents:

```ini
--country Ireland,Germany,Netherlands
--latest 10
--protocol https
--sort rate
--save /etc/pacman.d/mirrorlist
```

Enable timer:

```bash
systemctl enable --now reflector.timer
```

---

# PHASE 20 — GNOME PRIVACY

Run as normal user:

```bash
gsettings set org.gnome.desktop.privacy report-technical-problems false
gsettings set org.gnome.desktop.privacy remember-recent-files false
```

---

# PHASE 21 — UNIFIED KERNEL IMAGES (UKIs)

Create cmdline:

```bash
mkdir -p /etc/kernel
nano /etc/kernel/cmdline
```

Contents (single line):

```text
rd.luks.name=YOUR_UUID=cryptroot root=/dev/mapper/cryptroot rootflags=subvol=@ rw quiet loglevel=3 mem_sleep_default=deep apparmor=1 security=apparmor intel_iommu=on
```

---

# Configure linux-hardened UKI Preset (fallback)

Edit:

```bash
nano /etc/mkinitcpio.d/linux-hardened.preset
```

Contents:

```ini
ALL_config="/etc/mkinitcpio.conf"
ALL_kver="/boot/vmlinuz-linux-hardened"

PRESETS=('default' 'fallback')

default_uki="/boot/EFI/Linux/arch-linux-hardened.efi"
default_options=""

fallback_uki="/boot/EFI/Linux/arch-linux-hardened-fallback.efi"
fallback_options="-S autodetect"
```

**Note:** The splash image option is removed. If `/usr/share/systemd/bootctl/splash-arch.bmp` exists on your system, you may add:

```ini
default_options="--splash /usr/share/systemd/bootctl/splash-arch.bmp"
```

---

# Configure linux-lts UKI Preset

Edit:

```bash
nano /etc/mkinitcpio.d/linux-lts.preset
```

Contents:

```ini
# ALL_kver is REQUIRED — mkinitcpio reads the kernel version from this vmlinuz.
ALL_config="/etc/mkinitcpio.conf"
ALL_kver="/boot/vmlinuz-linux-lts"

PRESETS=('default' 'fallback')

default_uki="/boot/EFI/Linux/arch-linux-lts.efi"
default_options=""

fallback_uki="/boot/EFI/Linux/arch-linux-lts-fallback.efi"
fallback_options="-S autodetect"
```

**Note:** The splash image option is removed. If `/usr/share/systemd/bootctl/splash-arch.bmp` exists on your system, you may add:

```ini
default_options="--splash /usr/share/systemd/bootctl/splash-arch.bmp"
```

---

# Build UKIs

```bash
mkdir -p /boot/EFI/Linux
mkinitcpio -P
```

systemd-boot auto-discovers UKIs in `/boot/EFI/Linux/`. Set LTS as the default boot target:

```bash
nano /boot/loader/loader.conf
```

```text
default arch-linux-lts.efi
```

---

## ESP reuse / multiboot

When using [`scripts/arch-install.sh`](../scripts/arch-install.sh) in **MANUAL** mode with **reuse existing ESP**, the installer removes **Arch-only** boot artifacts before rebuilding (Windows and other `/EFI/*` loaders stay intact):

* `/EFI/Linux/arch-linux*.efi`
* legacy `vmlinuz-linux*` / `initramfs-linux*` on the ESP root
* stale systemd-boot entries (`arch*.conf`, `linux-*.conf`)

`bootctl install` replaces the systemd-boot binary; existing `/EFI/Microsoft/` entries remain for dual-boot.

---

# PHASE 22 — APPARMOR VERIFICATION & ENFORCEMENT

Verify AppArmor profiles are loaded:

```bash
aa-status
```

Expected output shows profiles in **enforce** or **complain** mode.

If profiles are in **complain** mode, move them to **enforce**:

```bash
aa-enforce /etc/apparmor.d/*
```

Apply AppArmor:

```bash
systemctl restart apparmor
```

---

# PHASE 23 — SECURE BOOT WITH SBCTL

> **Automated:** [`scripts/arch-install.sh`](../scripts/arch-install.sh) installs `sbctl` during `pacstrap`, runs `create-keys`, signs the full boot chain (UKIs + systemd-boot), and can run `enroll-keys -m` during install when firmware is in Setup Mode and you answer yes to the prompt. **Enrollment after first boot** (below) is the usual path.

Install (manual path):

```bash
pacman -S sbctl
```

Check status:

```bash
sbctl status
```

Before enrolling custom keys, firmware should be in **Setup Mode**. If not:

* enter BIOS
* clear Secure Boot keys
* return to Setup Mode

---

# Create Keys

```bash
sbctl create-keys
```

---

# Sign boot chain

Sign UKIs **and** systemd-boot (`-s` saves each path to the sbctl db):

```bash
sbctl sign -s /boot/EFI/Linux/arch-linux-lts.efi
sbctl sign -s /boot/EFI/Linux/arch-linux-lts-fallback.efi
sbctl sign -s /boot/EFI/Linux/arch-linux-hardened.efi
sbctl sign -s /boot/EFI/Linux/arch-linux-hardened-fallback.efi
sbctl sign -s /boot/EFI/systemd/systemd-bootx64.efi
sbctl sign -s /boot/EFI/BOOT/BOOTX64.EFI
```

The `zz-sbctl` pacman hook auto-resigns saved paths on kernel package updates:

```bash
ls /usr/share/libalpm/hooks/ | grep -i sbctl   # expect zz-sbctl.hook
```

Verify signatures:

```bash
sbctl verify
```

---

# Enroll keys and enable Secure Boot

Boot successfully with Secure Boot **disabled** in BIOS first. Then:

```bash
sbctl enroll-keys -m
```

`-m` imports Microsoft keys so Windows still boots on a shared ESP.

Return to BIOS:

```text
Security → Secure Boot → Enabled
```

Confirm:

```bash
sbctl status    # Secure Boot: enabled
sbctl verify
bootctl status  # Measured UKI: yes (when SB active)
```

---

# Re-sign after manual UKI rebuilds

`mkinitcpio -P` (for example after editing `/etc/kernel/cmdline`) does **not** run the pacman hook. Re-sign UKIs:

```bash
sudo mkinitcpio -P
for f in /boot/EFI/Linux/arch-linux-lts.efi /boot/EFI/Linux/arch-linux-lts-fallback.efi \
         /boot/EFI/Linux/arch-linux-hardened.efi /boot/EFI/Linux/arch-linux-hardened-fallback.efi; do
  [[ -f $f ]] && sudo sbctl sign -s "$f"
done
sudo sbctl verify
```

`profiles/thinkpad-x1.sh` (via `./install.sh`) performs this automatically when `/etc/sbctl/keys` exists.

---

# IMPORTANT

Only remove old loader entries AFTER confirming UKIs boot correctly.

If UKIs work properly:

```bash
rm /boot/loader/entries/arch-lts.conf
rm /boot/loader/entries/arch-hardened.conf
```

---

# PHASE 24 — EXIT INSTALLER

Exit chroot:

```bash
exit
```

Unmount:

```bash
umount -R /mnt
```

Close encrypted container:

```bash
cryptsetup close cryptroot
```

Reboot:

```bash
reboot
```

Remove installation USB.

---

# PHASE 25 — OPTIONAL AUR HELPER

Install prerequisites:

```bash
sudo pacman -S --needed base-devel git
```

Install yay:

```bash
git clone https://aur.archlinux.org/yay.git
cd yay
makepkg -si
```

---

# PHASE 26 — MAINTENANCE

Check updates:

```bash
checkupdates
```

Remove orphan packages:

```bash
pacman -Qtdq
sudo pacman -Rns $(pacman -Qtdq)
```

---

---

# PHASE 27 — DOTFILES SETUP

Log into GNOME, open a terminal, then clone and install:

```bash
git clone https://github.com/HelllGuest/dotfiles.git ~/dotfiles
cd ~/dotfiles
./install.sh
```

`./install.sh` (run from a GNOME session) will:

* Apply a machine profile: `profiles/$(hostname).sh` if present, otherwise `scripts/detect-profile.sh` (ThinkPad X1 → `thinkpad-x1.sh`; hybrid GPU → also `nvidia.sh`)
* On ThinkPad X1, re-sign UKIs after `mkinitcpio -P` when Secure Boot keys exist (`/etc/sbctl/keys`)
* Install packages from `packages/pacman.txt` (kernels, shells, terminals, CLI tools)
* Install Flatpaks from `packages/flatpak.txt` (Brave, Zen, Chrome, LibreWolf, Proton VPN, Android Studio)
* Deploy browser telemetry policies via `scripts/browser-hardening.sh` (Chrome/Brave `/etc` policies; Zen `user.js` into each `~/.var/app/io.github.zen_browser.zen/.zen/<profile>/` after first launch; LibreWolf upstream defaults)
* Install AUR packages from `packages/aur.txt` (bootstraps `paru` if no helper exists)
* Stow configs to `$HOME` and `/etc` (`system/`; skips `zram` symlink and `gdm`)
* Materialize `zram-generator.conf` via `scripts/zram-setup.sh`
* Apply GNOME session dconf from `gnome/dconf/user.conf`, enable extensions, location spoofing
* Reset mouse/touchpad/keyboard to stock GNOME defaults (`scripts/reset-input-defaults.sh`); clean legacy touchpad udev/inhibit if present (`scripts/cleanup-input-overrides.sh`)
* Configure GDM, Git, Neovim, and run health checks + privacy hardening
* **fnm** auto Node version on `cd` / shell start when project pins a version (see Phase 17b)
* **Headroom** optional AI context proxy for Claude Code / Cursor (see Phase 17c)

Config-only (no package install; skips `zram`, `system`, and `gdm`):

```bash
./stow-only.sh
exec zsh
```

To install or refresh Flatpaks/AUR packages without a full reinstall:

```bash
bash scripts/install-flatpaks.sh
bash scripts/install-aur.sh
```



See [README.md](../README.md) for shell setup and maintenance commands.

---

# PHASE 28 — VERIFICATION

Verify Wayland:

```bash
echo $XDG_SESSION_TYPE
```

Expected:

```text
wayland
```

---

# Verify Deep Sleep

```bash
cat /sys/power/mem_sleep
```

Expected:

```text
s2idle [deep]
```

---

# Verify AppArmor

```bash
aa-status
```

Ensure profiles are in **enforce** mode.

---

# Verify IOMMU

```bash
dmesg | grep -i iommu
```

Expected output shows IOMMU entries confirming Intel VT-d is active.

---

# Verify Firewall

```bash
ufw status verbose
```

---

# Verify zram

```bash
zramctl
```

---

# Verify earlyoom

```bash
systemctl status earlyoom
```

---

# Verify Battery Thresholds

```bash
cat /sys/class/power_supply/BAT0/charge_control_start_threshold
cat /sys/class/power_supply/BAT0/charge_control_end_threshold
```

---

# Verify Secure Boot

```bash
sbctl status
sbctl verify
bootctl status | grep -E 'Secure Boot|Measured UKI'
```

Expected:

```text
Secure Boot: enabled
```

All signed binaries should pass `sbctl verify`. With SB enabled, `bootctl status` should show `Measured UKI: yes`.

If you rebuilt UKIs manually, re-sign before enabling SB or after `mkinitcpio -P` (see [Phase 23](#phase-23--secure-boot-with-sbctl)).

---

# Verify GDM Wayland

```bash
sudo systemctl status gdm
journalctl -u gdm -n 20
```

Look for "Wayland" in output to confirm session type.
