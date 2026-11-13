# Definitive Hardened Arch Linux + GNOME Wayland Guide

## For Lenovo ThinkPad P15 Gen 1 and T14s Gen 3 AMD

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
* firewalld (`nftables`, default zone `drop`)
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
`mem_sleep_default=s2idle` on the kernel cmdline (written by `arch-install.sh` /
`arch-install-t14s.sh` and machine profiles) plus
`stow/system/etc/systemd/sleep.conf.d/` (`SuspendState=mem` +
`MemorySleepMode=s2idle`). Check with [Verify sleep](#verify-sleep-s2idle);
after resume, `journalctl -b | grep "suspend entry"` →
`PM: suspend entry (s2idle)`.

### Kernel cmdline + `system/` files (installed, not stowed)

`stow/system/` is **not** stowed. `install.sh` runs `scripts/system-setup.sh`,
which installs each file as a root-owned regular file (same reason as zram and
GDM). Symlinks from `/etc` into `$HOME` break in two ways:

* Early boot units start before `/home` is mounted; stowed `/etc` links into
  `$HOME` dangle and break services (historically UFW `before.rules`).
* The repo owner could edit root config (udev, sleep, units) without sudo.

`arch-install.sh` / `arch-install-t14s.sh` write `/etc/kernel/cmdline` with the
LUKS UUID of the disk they configure. Machine profiles may append host-specific
flags (P15: `nvidia_drm.modeset=1` + `rd.driver.blacklist=nouveau`; T14s:
`amd_iommu=on` + `amd_pstate=active`). `system-setup.sh` does **not** own the
cmdline. When a managed `modprobe.d` file changes it runs `mkinitcpio -P`
(sbctl's hook re-signs the UKIs). Replaced files are backed up to
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
firewalld \
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
echo "p15" > /etc/hostname
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
127.0.1.1 p15.localdomain p15
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

Configure firewalld (nftables backend, deny inbound):

```bash
pacman -S firewalld
# or: bash scripts/firewalld-migrate.sh   # from an existing UFW host
firewall-cmd --set-default-zone=drop
systemctl enable --now firewalld
```

Libvirt: bind `virbr0` to zone `libvirt`. Air-gapped malware net: host-only
`virbr-malware` in zone `block` (see `scripts/firewalld-migrate.sh`).

Default behavior:

* **deny incoming** — All inbound connections rejected unless explicitly allowed
* **allow outgoing** — All outbound connections permitted

Add SSH rule (if needed). Prefer an explicit port over app profiles:

```bash
sudo firewall-cmd --permanent --add-service=ssh
# or: sudo firewall-cmd --permanent --add-port=22/tcp
sudo firewall-cmd --reload
sudo systemctl enable --now sshd
```

Confirm with `firewall-cmd --list-all` and `ss -tlnp | grep ':22'`. Prefer key
auth over passwords. Mask leftover UFW so it never fights firewalld on nftables:

```bash
systemctl disable --now ufw 2>/dev/null || true
systemctl mask ufw 2>/dev/null || true
```

## Waydroid internet (NAT masquerade)

Waydroid bridges the container on `waydroid0` (`192.168.240.1/24`) but provides
no outbound NAT, so containers have no return path and no internet. Bind the
bridge to a zone that allows DHCP/DNS to the host, then enable the idempotent
`waydroid-nat.service` unit (from `stow/system/`, installed by
`scripts/system-setup.sh`):

```bash
# host-side DHCP (67) + DNS (53) for the container's dnsmasq
sudo firewall-cmd --permanent --add-port=53/udp
sudo firewall-cmd --permanent --add-port=67/udp
sudo firewall-cmd --reload
sudo systemctl enable --now waydroid-nat.service
```

This service ensures the masquerade rule is added exactly once and survives
firewall reloads. If container forwarding fails, confirm `waydroid0` is in a
zone that permits forward (or use the stock `libvirt` pattern from migrate).

## Tailscale + firewalld

Tailscale’s default `netfilter-mode=on` already accepts `tailscale0` in its own
chains ([docs](https://tailscale.com/docs/reference/netfilter-modes)). On a
default-`drop` host still bind the mesh iface and allow WireGuard so policy is
visible if netfilter mode is `off`:

```bash
bash scripts/firewalld-tailscale.sh
# deprecated alias: bash scripts/ufw-tailscale.sh
# equivalent:
#   sudo firewall-cmd --permanent --zone=trusted --change-interface=tailscale0
#   sudo firewall-cmd --permanent --add-port=41641/udp
#   sudo firewall-cmd --reload
```

`./install.sh` runs this when `tailscale` is on PATH. Official lock-down guide
(Ubuntu/UFW wording; map to firewalld above):
[Secure Ubuntu with UFW](https://tailscale.com/docs/how-to/secure-ubuntu-server-with-ufw).

## Libvirt disposable Kali (virbr0 NAT)

firewalld default zone `drop` rejects unsolicited inbound; libvirt guest NAT
needs `virbr0` in the stock `libvirt` zone (forward + masquerade). Prefer that
over opening the host default zone. `scripts/firewalld-migrate.sh` and
`scripts/kali-disposable.sh setup` / `start --nat`:

* permanent `--zone=libvirt --add-interface=virbr0` (inherits when bridge appears)
* runtime `--change-interface=virbr0` when the iface exists
* host-only `virbr-malware` → zone `block` (no NAT/forward)

Boot unit `virbr0-up.service` (from `stow/system/`, installed by
`system-setup.sh` / kali `setup`) runs `virsh net-start default` then
`ip link set virbr0 up` after `libvirtd` (avoids `Cannot find device virbr0`
when the oneshot races the bridge). Check: `systemctl status virbr0-up`.

Lab usage: [fresh-install RE — Disposable Kali](fresh-install-coding-re.md#disposable-kali).

---

# PHASE 14 — THINKPAD OPTIMIZATION

PPD, `sof-firmware`, `alsa-ucm-conf`, and `fprintd` come from Phase 10 / the
matching installer (`fprintd` is D-Bus activated — do not systemctl-enable it).
Optional power diagnostics:

```bash
pacman -S powertop
```

**Power stack note:** this system uses **power-profiles-daemon (PPD)** only.

* **TLP is *not* used** — it conflicts with PPD (`PLATFORM_PROFILE.../CPU_ENERGY_PERF_POLICY... not set because power-profiles-daemon is running`). Do not install `tlp`/`tlp-rdw`.
* **thermald is *not* used** — it self-exits on these ThinkPads (`[dytc_lapmode] present: Thermald can't run on this platform`); thermal is firmware-managed (Intel DPTF on P15 / AMD DYTC on T14s). Leave it uninstalled/disabled.
* **Skip `ryzenadj`** on T14s Gen 3 AMD PRO — EC often locks SMU; not part of the profile.

**T14s Gen 3 AMD (21CQ/21CR)** extras (installer + `profiles/thinkpad-t14s.sh`):

* Cmdline: `amd_iommu=on` `amd_pstate=active` (strip any `intel_iommu` / `i915.*` leftovers; rebuild UKI)
* Power: PPD by default; if the host came from `t14s-arch-install` with
  tuned, `tuned` + `tuned-ppd` (same GNOME power menu API) replace PPD —
  `./install.sh` then skips `power-profiles-daemon` and the profile enables tuned
* GPU / Wi-Fi / FP packages: `packages/thinkpad-t14s.txt` (`mesa` + `vulkan-radeon` + `libva-utils` + `wireless-regdb` + `fprintd`; VA-API via `LIBVA_DRIVER_NAME=radeonsi` in `.shell-exports`, `/etc/environment.d/99-wayland.conf`, and GDM override)
* Touchpad `s2idle` wakeup: `/etc/udev/rules.d/71-thinkpad-t14s-touchpad-wakeup.rules` disables I2C touchpad wakeup (`i2c-ELAN0678:*` / `i2c-SYNA8018:*`) so lid flex in transit does not wake the laptop from `s2idle`
* Charge window 70–80: `arch-install-t14s.sh` seeds tmpfiles from
  `scripts/lib/thinkpad-charge-thresholds.conf`, installs
  `/etc/udev/rules.d/61-thinkpad-charge-limit.rules` (`ENV{CHARGE_LIMIT}="70,80"`
  so UPower 1.90+ / GNOME Preserve Battery Health does not reset
  `charge_control_start_threshold` to `0`), **and** enables
  `thinkpad-charge-thresholds.service` (waits for late BAT* sysfs; apply script
  under `/usr/local/lib/thinkpad/`). Live refresh via
  `scripts/thinkpad-charge-thresholds.sh` (also `install-re-extras.sh` /
  `profiles/thinkpad-t14s.sh`) installs both tmpfiles and the service.
* Keep fingerprint enabled (power-button Goodix on T14s; palm-rest Synaptics on P15)

---

# Configure Battery Thresholds

Without TLP, set ThinkPad charge thresholds via the `thinkpad_acpi` sysfs
interface. Prefer the shared helper (writes live sysfs +
`/etc/tmpfiles.d/thinkpad-charge-thresholds.conf` + late-boot
`thinkpad-charge-thresholds.service`). Auto-applied by
`profiles/thinkpad-t14s.sh` and `scripts/install-re-extras.sh`. Safe to re-run
on P15 (live BAT* → write + persist). On desktop/VM/non-ThinkPad with no
BAT*, the helper plain-skips (no unit). Only ThinkPad DMI may seed BAT0
tmpfiles + service when charge_control_* is not visible yet (late
`thinkpad_acpi`; enable uses `start --no-block` so the helper does not wait):

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

Sysfs values reset on boot. Two layers re-apply them on ThinkPad hosts:

1. **tmpfiles** (`/etc/tmpfiles.d/thinkpad-charge-thresholds.conf`) — early boot,
   best-effort (mode 644).
2. **`thinkpad-charge-thresholds.service`** — `After=multi-user.target`, waits up
   to ~60s for `BAT*/charge_control_*` (`thinkpad_acpi` can appear late). Apply
   script: `/usr/local/lib/thinkpad/apply-charge-thresholds.sh`. Exits 0 after
   ~60 s if BAT* never appears; runs after multi-user, so it does not delay
   login. Desktops, VMs, and non-ThinkPad laptops without charge sysfs do not
   get this unit — the helper skips unless ThinkPad DMI allows a no-BAT seed.

Only batteries that expose `charge_control_*_threshold` are touched. If live
thresholds exist but tmpfiles and/or the unit are missing, re-run the helper
(needs sudo). Upgrading from an older installer: the helper removes legacy
`/usr/local/lib/t14s/apply-charge-thresholds.sh` when it rewrites the unit.
`scripts/check.sh` reports gaps.

---

# Fingerprint Enrollment

```bash
bash scripts/fingerprint-setup.sh
# or: fprintd-enroll
```

P15 uses Synaptics `06cb:00bd` (palm rest). T14s Gen 3 AMD uses Goodix
`27c6:6594` (power button). Both work with `fprintd` / `libfprint` on Arch.

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

`./install.sh` (run from a GNOME session; full step-by-step order in [README — Script execution order](../README.md#script-execution-order-fresh-machine)) will:

* Install packages from `packages/pacman.txt` (kernels, shells, terminals, CLI tools; skips Intel/NVIDIA GPU packages on ThinkPad T14s Gen 3 AMD and skips `power-profiles-daemon` when `tuned-ppd` is present)
* Apply **after** `pacman.txt` exactly one machine profile via `scripts/apply-profile.sh`: `profiles/$(hostname).sh` if present, otherwise `scripts/detect-profile.sh` (`thinkpad-p15`, `thinkpad-t14s`, or `laptop`). Optimus/NVIDIA setup is inside `thinkpad-p15.sh` (no `nvidia.sh`).
* Install Flatpaks from `packages/flatpak.txt` (Brave, Zen, Chrome, LibreWolf, Proton VPN, Android Studio) and AUR packages from `packages/aur.txt` (bootstraps `paru` if no helper exists)
* Stow configs to `$HOME` (skips `zram` and `gdm`); install `system/` into `/etc` as root-owned files via `scripts/system-setup.sh`; materialize `zram-generator.conf` via `scripts/zram-setup.sh`
* Apply GNOME session dconf (`gnome/dconf/user.conf`), Console & Ptyxis terminal settings, Dash2Dock + extensions, location spoofing, and stock input defaults (`scripts/reset-input-defaults.sh` + `scripts/cleanup-input-overrides.sh`)
* Configure GDM, Git, Neovim, Headroom proxy + MCP (`scripts/headroom-setup.sh`), AI coding/RE agents + plugins + skills (`sync-agent-skills.sh`, `install-coding-agents.sh`, `install-caveman.sh`, `install-ponytail.sh`, `install-android-ui-skills.sh`, `install-ghidra-cli.sh`, `install-rea.sh`, `install-obscura.sh`, `install-re-skills.sh`, `install-ecosystem-skills.sh`), PhotoGIMP, and foxcage (`install-foxcage.sh`, Firefox in rootless Podman when `podman` exists)
* Run `scripts/privacy-hardener.sh` (incl. `browser-hardening.sh`), `scripts/check.sh`, and `scripts/validate-configs.sh`

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
2. Confirm `/etc/kernel/cmdline` still has `mem_sleep_default=s2idle` (installer
   / profile owns that file). Then `bash scripts/system-setup.sh` (installs
   `s2idle.conf` + lid drop-in; rebuilds UKIs only if a managed `modprobe.d`
   file changed).
3. **Reboot**, then re-check `/proc/cmdline` and `/sys/power/mem_sleep`.
   Expect bracket on **s2idle**: `[s2idle] deep`.

Replaced `system/` file backups land under
`/var/backups/dotfiles-system/<timestamp>/`.

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
# tmpfiles is mode 644 (readable without sudo)
test -f /etc/tmpfiles.d/thinkpad-charge-thresholds.conf \
  && cat /etc/tmpfiles.d/thinkpad-charge-thresholds.conf
systemctl is-enabled thinkpad-charge-thresholds.service
test -x /usr/local/lib/thinkpad/apply-charge-thresholds.sh
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
