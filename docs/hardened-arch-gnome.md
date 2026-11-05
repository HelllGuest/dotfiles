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
* custom Secure Boot keys using [sbctl](https://github.com/Foxboron/sbctl)

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
> **ThinkPad T14s Gen 3 AMD** (type **21CQ/21CR**): use [`scripts/arch-install-t14s.sh`](../scripts/arch-install-t14s.sh) instead — same stack with `amd_iommu` / `amd_pstate`, `amd-ucode` (not `intel_iommu`), plus `mesa` / `vulkan-radeon` / `fprintd` / `sof-firmware`. After first-boot `./install.sh`, `profiles/thinkpad-t14s.sh` repairs Intel cmdline leftovers and applies charge thresholds (see Phase 14).
> ```bash
> bash <(curl -fsSL https://raw.githubusercontent.com/HelllGuest/dotfiles/main/scripts/arch-install-t14s.sh)
> ```
> Rehearse first in a UEFI VM with [`scripts/arch-install-vmtest.sh`](../scripts/arch-install-vmtest.sh) (full install on a virtual disk; host disks untouched). For the T14s script: `INSTALLER=arch-install-t14s.sh scripts/arch-install-vmtest.sh` (confirm past the DMI warn in the VM). The manual phases below remain the reference for what it does and for customizing.

> **Dotfiles:** After completing this guide, continue with [PHASE 27 — Dotfiles Setup](#phase-27--dotfiles-setup) or jump to the [dotfiles README](../README.md) for shell and maintenance. For coding, reverse engineering, and malware-lab purpose stacks on this ThinkPad, see [fresh-install-coding-re.md](fresh-install-coding-re.md).

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

Pick the BIOS mode that matches the sleep policy you want in Linux. On ThinkPads
these labels are easy to misread:

| BIOS Sleep State | Firmware behavior | Matches this repo? |
|------------------|-------------------|--------------------|
| **Windows and Linux** | Prefers modern standby (**s2idle**) | Yes — default below |
| **Linux** | Enables classic S3 (**deep**) | No — fights the s2idle pin unless you also change cmdline + `sleep.conf.d` |

For a fresh install that follows this repo, set:

```text
Windows and Linux
```

`/sys/power/mem_sleep` lists available modes; the **bracketed** value is active.

This repo’s tracked files pin **s2idle** (not S3/`deep`):
`mem_sleep_default=s2idle` on the kernel cmdline (`arch-install.sh` and
`stow/system/etc/kernel/cmdline`) plus `stow/system/etc/systemd/sleep.conf.d/`
(`SuspendState=mem` + `MemorySleepMode=s2idle`). Check with
[Verify sleep](#verify-sleep-s2idle); after resume,
`journalctl -b | grep "suspend entry"` → `PM: suspend entry (s2idle)`.

### Kernel cmdline + `system/` files (installed, not stowed)

`stow/system/` is **not** stowed. `install.sh` runs `scripts/system-setup.sh`,
which installs each file as a root-owned regular file (same reason as zram and
GDM). Symlinks from `/etc` into `$HOME` break in two ways:

* `ufw.service` starts before `/home` is mounted. A stowed
  `/etc/ufw/before.rules` dangles, ufw loads its chains without the
  `ESTABLISHED,RELATED` accepts, and reply traffic (DNS included) is dropped.
  `ufw status` still says `active`.
* The repo owner could edit root config (kernel cmdline, udev, sleep, units)
  without sudo.

`arch-install.sh` writes `/etc/kernel/cmdline` with the LUKS UUID of the disk it
configured. The tracked `stow/system/etc/kernel/cmdline` carries this machine's
UUID and X1 options (i915, `thinkpad_acpi`). It and the other X1-only files (i915,
X1 sleep/logind, fingerprint port rule) install only on ThinkPad X1 hardware, by
DMI (`is_thinkpad_x1`), not hostname. Other profiles (e.g. P15 with
`nvidia_drm.modeset=1`) keep their own; old stow symlinks to X1-only files are
removed there, and a stowed cmdline becomes a real file. It rewrites `rd.luks.name=` to the UUID in `/proc/cmdline`
(the one that unlocked the running root) and skips the file if that UUID is not
a present block device. When cmdline or `modprobe.d` changes it runs
`mkinitcpio -P` (sbctl's hook re-signs the UKIs). Replaced files are backed up to
`/var/backups/dotfiles-system/<timestamp>/`. Leftover stow symlinks from older
setups are removed; `scripts/check.sh` flags any that remain.

The four location files (`/etc/geolocation`, GeoClue drop-in, NetworkManager
dispatcher, polkit rule) are installed by `scripts/location-setup.sh` instead.

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
+2G
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
cryptsetup \
bluez \
bluez-utils \
networkmanager \
sudo \
zsh \
nano \
vim \
git \
reflector \
pacman-contrib \
mkinitcpio \
snapper \
snap-pac \
zram-generator \
apparmor \
ufw \
sbctl \
efibootmgr
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
# installer prompt default is America/New_York; pick your Region/City
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
# installer prompt default is en_US.UTF-8
```

Keyboard layout:

```bash
echo "KEYMAP=uk" > /etc/vconsole.conf
# installer prompt default is us
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
options rd.luks.name=YOUR_UUID=cryptroot root=/dev/mapper/cryptroot rootflags=subvol=@ rw quiet loglevel=3 mem_sleep_default=s2idle apparmor=1 security=apparmor intel_iommu=on
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
options rd.luks.name=YOUR_UUID=cryptroot root=/dev/mapper/cryptroot rootflags=subvol=@ rw quiet loglevel=3 mem_sleep_default=s2idle apparmor=1 security=apparmor intel_iommu=on
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
systemctl enable bluetooth
systemctl enable fstrim.timer
systemctl enable bolt.service
systemctl enable earlyoom.service
systemctl enable power-profiles-daemon
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

Do **not** `stow -t / zram`: a symlink into `$HOME` breaks at early boot (home is not mounted when zram-generator runs).

**Option A — Dotfiles (recommended after cloning this repo):**

```bash
cd ~/dotfiles
bash scripts/zram-setup.sh
```

That copies a real file to `/etc/systemd/zram-generator.conf`.

**Option B — Manual:**

Create:

```bash
nano /etc/systemd/zram-generator.conf
```

Contents:

```ini
[zram0]
zram-size = min(ram / 2, 32768)
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

Add SSH rule (if needed). Arch’s UFW package usually has **no** `OpenSSH` app
profile (`ufw app list` will not list it; `ufw allow OpenSSH` fails with
“Could not find a profile matching 'OpenSSH'”). Allow the port instead:

```bash
sudo ufw allow 22/tcp comment 'ssh'
sudo ufw reload
sudo systemctl enable --now sshd
```

Confirm with `sudo ufw status` and `ss -tlnp | grep ':22'`. Prefer key auth over passwords.

Enable UFW at boot (if not already):

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

Enable the idempotent `waydroid-nat.service` unit (installed from `stow/system/` by `scripts/system-setup.sh`):

```bash
sudo systemctl enable --now waydroid-nat.service
```

This service ensures the masquerade rule is added exactly once and survives `ufw reload` cycles.

If container forwarding fails, check `/etc/default/ufw` and set
`DEFAULT_FORWARD_POLICY="ACCEPT"` if it is still `DROP`.

## Tailscale + UFW

Tailscale’s default `netfilter-mode=on` already accepts `tailscale0` in its own
chains ([docs](https://tailscale.com/docs/reference/netfilter-modes)). For a
locked-down host (`ufw default deny incoming`) still add UFW rules so policy is
visible and works if netfilter mode is `off`:

```bash
bash scripts/ufw-tailscale.sh
# equivalent:
#   sudo ufw allow in on tailscale0
#   sudo ufw allow 41641/udp comment 'tailscale-wg'
#   sudo ufw route allow in on tailscale0
#   sudo ufw route allow out on tailscale0
```

`./install.sh` runs this when `tailscale` is on PATH. Official lock-down guide:
[Secure Ubuntu with UFW](https://tailscale.com/docs/how-to/secure-ubuntu-server-with-ufw).

## Libvirt disposable Kali (virbr0 NAT)

UFW’s default **deny routed** blocks guest DHCP/NAT. Prefer narrow allows over
global `DEFAULT_FORWARD_POLICY=ACCEPT`. `scripts/kali-disposable.sh setup` /
`start --nat` add:

* `ufw allow in|out on virbr0`
* `ufw route allow` guest↔guest on `virbr0` and guest→host WAN ifaces
* `ufw route allow from 192.168.122.0/24`

Boot unit `virbr0-up.service` (from `stow/system/`, installed by
`system-setup.sh` / kali `setup`) runs `virsh net-start default` then
`ip link set virbr0 up` after `libvirtd` (avoids `Cannot find device virbr0`
when the oneshot races the bridge). Check: `systemctl status virbr0-up`.

Lab usage: [fresh-install RE — Disposable Kali](fresh-install-coding-re.md#disposable-kali).

---

# PHASE 14 — THINKPAD OPTIMIZATION

PPD, `sof-firmware`, `alsa-ucm-conf`, `fprintd`, and (X1 Yoga)
`iio-sensor-proxy` come from Phase 10 / the matching installer
(`iio-sensor-proxy` and `fprintd` are D-Bus activated — do not enable them).
Optional power diagnostics:

```bash
pacman -S powertop
```

**Power stack note:** this system uses **power-profiles-daemon (PPD)** only.

* **TLP is *not* used** — it conflicts with PPD (`PLATFORM_PROFILE.../CPU_ENERGY_PERF_POLICY... not set because power-profiles-daemon is running`). Do not install `tlp`/`tlp-rdw`.
* **thermald is *not* used** — on the X1 it self-exits every boot (`[dytc_lapmode] present: Thermald can't run on this platform`); thermal is firmware-managed (Intel DPTF / AMD DYTC on T14s). Leave it uninstalled/disabled.
* **Skip `ryzenadj`** on T14s Gen 3 AMD PRO — EC often locks SMU; not part of the profile.

**T14s Gen 3 AMD (21CQ/21CR)** extras (installer + `profiles/thinkpad-t14s.sh`):

* Cmdline: `amd_iommu=on` `amd_pstate=active` (strip any `intel_iommu` / `i915.*` leftovers; rebuild UKI)
* GPU / FP packages: `packages/thinkpad-t14s.txt` (`mesa` + `vulkan-radeon` + `fprintd`; VA-API via mesa `Provides`)
* Charge window 70–80: installer seeds `scripts/lib/thinkpad-charge-thresholds.conf`; live refresh via `scripts/thinkpad-charge-thresholds.sh` (also `install-re-extras.sh`)
* No Yoga tablet rotate stack; keep fingerprint enabled (do not install the X1 fingerprint-disable udev rule)

---

# Configure Battery Thresholds

Without TLP, set ThinkPad charge thresholds via the `thinkpad_acpi` sysfs
interface. Prefer the shared helper (writes live sysfs +
`/etc/tmpfiles.d/thinkpad-charge-thresholds.conf`). Auto-applied by
`profiles/thinkpad-t14s.sh` and `scripts/install-re-extras.sh`; safe to re-run
on X1/P15:

```bash
bash scripts/thinkpad-charge-thresholds.sh
# keep a custom window (example used on some hosts):
# CHARGE_START=75 CHARGE_END=80 bash scripts/thinkpad-charge-thresholds.sh
```

Manual equivalent:

```bash
echo 70 | tee /sys/class/power_supply/BAT0/charge_control_start_threshold
echo 80 | tee /sys/class/power_supply/BAT0/charge_control_end_threshold
```

Sysfs values reset on boot; the tmpfiles drop-in re-applies them. Only batteries
that expose `charge_control_*_threshold` are touched. If live thresholds exist
but `/etc/tmpfiles.d/thinkpad-charge-thresholds.conf` is missing, re-run the
helper (needs sudo). `scripts/check.sh` reports this gap.

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

`snapper` and `snap-pac` are installed in Phase 6. Initialize Snapper:

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

Apps: `packages/flatpak.txt` (browsers, Proton VPN, Android Studio). `arch-install.sh`
installs the browsers + Proton VPN; `./install.sh` (`scripts/install-flatpaks.sh`)
installs the full list, including any that failed in the installer chroot.

---

# PHASE 17 — ROOTLESS PODMAN

Primary container runtime for **AI agent sandboxes** on this workstation.
Packages are in `packages/pacman.txt` (`podman`, `podman-compose`, `buildah`,
`skopeo`, `crun`, `netavark`, `aardvark-dns`, `passt`, `catatonit`).

```bash
# Already covered by ./install.sh + pacman.txt; manual:
sudo pacman -S --needed podman podman-compose buildah skopeo crun \
  netavark aardvark-dns passt catatonit
```

IMPORTANT: apply No-COW **before** the first pull (and re-apply after first use
if children lost `C`):

```bash
mkdir -p ~/.local/share/containers/storage
chattr +C ~/.local/share/containers/storage
# after first pull/run, retrofit children if needed:
chattr -R +C ~/.local/share/containers/storage
```

Enable the user socket (`.shell-exports` then points `DOCKER_HOST` at Podman —
intentional; `docker` CLI → Podman):

```bash
systemctl --user enable --now podman.socket
# optional: keep socket after logout (larger post-logout surface)
# loginctl enable-linger "$USER"
```

Hardened agent runs (preferred over raw `podman run`):

```bash
bash scripts/agent-run.sh ~/src/my-job alpine:3.20 sh
# AGENT_NET=pasta bash scripts/agent-run.sh ~/src/my-job alpine:3.20  # allow egress
```

Never mount `$XDG_RUNTIME_DIR/podman/podman.sock` or `/var/run/docker.sock`
into an agent container.

User defaults: stow package `containers` →
`~/.config/containers/containers.conf` (`no_new_privileges`, stock seccomp).
Pull policy on Arch remains distro default (`insecureAcceptAnything`); pin image
**digests** for untrusted agent workloads.

AppArmor: Podman may report `apparmorEnabled: false` on this host while still
using seccomp. Treat AppArmor as unused for containers unless you add a real
profile.

Optional leftover **Docker** package: fine to keep for rare `FORCE_DOCKER=1`
use. If both are installed, **disable the system daemon** so Podman stays
default (otherwise `docker.service` owns `/var/run/docker.sock` and confuses
checks):

```bash
sudo systemctl disable --now docker.service docker.socket
systemctl --user enable --now podman.socket
# new shell, or: export DOCKER_HOST=unix://$XDG_RUNTIME_DIR/podman/podman.sock
```

Real dockerd for one shell: `FORCE_DOCKER=1`. Do not install `podman-docker`
alongside `docker` (pacman conflict).

---

# PHASE 17b–17e — DEVELOPER EXTRAS (DOTFILES)

Installed or wired by `./install.sh`; documented once in the README:

* fnm Node pins: [README — Node.js (fnm)](../README.md#nodejs-fnm)
* x86-64-v3 makepkg + `rebuild-v3.sh`: [README — x86-64-v3 local builds](../README.md#x86-64-v3-local-builds)
* Headroom proxy (Claude / Cursor): [README — Headroom](../README.md#headroom-claude--cursor-token-compression)
* PhotoGIMP: [README — PhotoGIMP](../README.md#photogimp-gimp-photoshop-layout)
* Dash2Dock Animated: [README — Dash2Dock Animated](../README.md#dash2dock-animated)

---

# PHASE 17f — PTYXIS / GHIDRA-CLI (OPTIONAL)

```bash
bash scripts/ptyxis-setup.sh
# if pacman -Q ghidra:
bash scripts/install-ghidra-cli.sh
```

* Ptyxis: gsettings/dconf rice aligned with kitty/ghostty habits; wired into `./install.sh` after `gnome-console-setup.sh`
* ghidra-cli: cargo CLI + host skill under `skills/ghidra-cli-host/`; GUI via `ghidra-gui` (cargo `ghidra` shadows `/usr/bin/ghidra`). Install failure is non-fatal in `./install.sh`

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
```

(`arch-install.sh` enables Color + ParallelDownloads = 10 only; VerbosePkgLists / ILoveCandy are optional extras, not set by the installer.)

---

# Reflector Configuration

Create:

```bash
nano /etc/xdg/reflector/reflector.conf
```

Contents:

```ini
--latest 10
--protocol https
--sort rate
--save /etc/pacman.d/mirrorlist
```

(`arch-install.sh` writes this file with no `--country` filter. Live ISO `reflector` uses `--latest 20`.)

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
rd.luks.name=YOUR_UUID=cryptroot root=/dev/mapper/cryptroot rootflags=subvol=@ rw quiet loglevel=3 mem_sleep_default=s2idle apparmor=1 security=apparmor intel_iommu=on
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

---

# Build UKIs

Optional splash for either preset, if `/usr/share/systemd/bootctl/splash-arch.bmp` exists: `default_options="--splash /usr/share/systemd/bootctl/splash-arch.bmp"`.

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

# UKI rebuilds after enrollment

`mkinitcpio -P` (for example after editing `/etc/kernel/cmdline`) re-signs the
UKIs itself: sbctl ships a mkinitcpio post hook (`/usr/lib/initcpio/post/sbctl`)
that signs each UKI it builds once sbctl keys exist. Confirm with `sudo sbctl verify`.

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

`./install.sh` / `install-aur.sh` bootstraps **paru** if no AUR helper is present. yay is optional:

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

# PHASE 27 — DOTFILES SETUP

Log into GNOME, open a terminal, then clone and install:

```bash
git clone https://github.com/HelllGuest/dotfiles.git ~/dotfiles
cd ~/dotfiles
./install.sh
```

`./install.sh` (run from a GNOME session) will:

* Apply exactly one machine profile: `profiles/$(hostname).sh` if present, otherwise `scripts/detect-profile.sh` (ThinkPad X1 → `thinkpad-x1`; ThinkPad P15 → `thinkpad-p15`; other ThinkPads/laptop chassis → `laptop`). Optimus/NVIDIA setup is inside `thinkpad-p15.sh` (no `nvidia.sh`).
* Install packages from `packages/pacman.txt` (kernels, shells, terminals, CLI tools)
* Install Flatpaks from `packages/flatpak.txt` (Brave, Zen, Chrome, LibreWolf, Proton VPN, Android Studio)
* Deploy browser telemetry via `scripts/browser-hardening.sh` (layout and per-browser notes: README Flatpaks section). Launch Zen once before re-running if profiles are new.
* Install AUR packages from `packages/aur.txt` (bootstraps `paru` if no helper exists)
* Stow configs to `$HOME` (skips `zram` and `gdm`); install `system/` into `/etc` as root-owned files via `scripts/system-setup.sh`
* Materialize `zram-generator.conf` via `scripts/zram-setup.sh`
* Apply GNOME session dconf from `gnome/dconf/user.conf`, enable extensions, location spoofing
* Reset mouse/touchpad/keyboard to stock GNOME defaults (`scripts/reset-input-defaults.sh`); clean legacy touchpad udev/inhibit if present (`scripts/cleanup-input-overrides.sh`)
* Configure GDM, Git, Neovim; run `bash scripts/privacy-hardener.sh` then `bash scripts/check.sh`
* fnm, Headroom, PhotoGIMP, Dash2Dock (Wayland needs logout): see Phase 17b–17e
* **Ptyxis** optional terminal rice via `scripts/ptyxis-setup.sh` (after Console setup)
* **ghidra-cli** optional when pacman `ghidra` is installed (`scripts/install-ghidra-cli.sh`; failure does not abort `./install.sh`)

Config-only (no package install; skips `zram`, `system`, and `gdm`; removes unmodified `/etc/skel` copies that block stow):

```bash
./stow-only.sh
exec zsh
```

To install or refresh Flatpaks/AUR packages without a full reinstall:

```bash
bash scripts/install-flatpaks.sh
bash scripts/install-aur.sh
```

See [README.md](../README.md) for shell setup and maintenance commands. For
coding / reverse engineering / malware-lab stacks on this machine, see
[fresh-install-coding-re.md](fresh-install-coding-re.md).

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

# Verify sleep (s2idle)

```bash
cat /sys/power/mem_sleep
grep -o 'mem_sleep_default=[^ ]*' /proc/cmdline
```

Expected after this repo’s cmdline + `sleep.conf.d` are actually applied (S3 still
listed if firmware exposes it):

```text
[s2idle] deep
mem_sleep_default=s2idle
```

If you see `s2idle [deep]` and/or `mem_sleep_default=deep`, the live cmdline or
BIOS Sleep State has drifted from the repo pin. Repair:

1. BIOS Sleep State = **Windows and Linux** (not **Linux** / S3).
2. `bash scripts/system-setup.sh` (rewrites `/etc/kernel/cmdline` from
   `stow/system/`, installs `s2idle.conf` + lid drop-in, rebuilds UKIs).
3. **Reboot**, then re-check `/proc/cmdline` and `/sys/power/mem_sleep`.
   Expect bracket on **s2idle**: `[s2idle] deep`.

Cmdline backups land under `/var/backups/dotfiles-system/<timestamp>/`.

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
systemctl is-active ufw
sudo ufw status verbose
sudo iptables -S ufw-before-input | grep -c ESTABLISHED
```

Expect `active`, `Status: active`, and a count of at least `1`. `ufw status`
alone is not enough: it reports `active` even when `ufw.service` failed at boot
and loaded no `before.rules` (then reply traffic, DNS included, is dropped).
Fix with `sudo ufw reload` and check `journalctl -b -u ufw`.

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
# expect 70 and 80 (or your CHARGE_START / CHARGE_END, e.g. 75/80)
test -f /etc/tmpfiles.d/thinkpad-charge-thresholds.conf && cat /etc/tmpfiles.d/thinkpad-charge-thresholds.conf
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

UKIs rebuilt with `mkinitcpio -P` are re-signed by sbctl's mkinitcpio hook (see [Phase 23](#phase-23--secure-boot-with-sbctl)).

---

# Verify GDM Wayland

```bash
sudo systemctl status gdm
journalctl -u gdm -n 20
```

Look for "Wayland" in output to confirm session type.
