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

> **Automated Stage A:** canonical in-repo installer
> [stage-a/](../stage-a/README.md)
> (`HW_PROFILE=t14s` for 21CQ/21CR, `HW_PROFILE=p15` for 20SU Optimus, or generic x86_64). Dotfiles
> [`arch-install-t14s.sh`](../scripts/arch-install-t14s.sh) /
> [`arch-install-p15.sh`](../scripts/arch-install-p15.sh) /
> [`arch-install.sh`](../scripts/arch-install.sh) are thin handoffs only.
> ```bash
> bash <(curl -fsSL https://raw.githubusercontent.com/HelllGuest/dotfiles/main/stage-a/install.sh)
> # or: …/dotfiles/main/scripts/arch-install-t14s.sh  # HW_PROFILE=t14s
> # or: …/dotfiles/main/scripts/arch-install-p15.sh   # HW_PROFILE=p15
> ```
> After first boot: `./install.sh` → `profiles/thinkpad-t14s.sh` or
> `thinkpad-p15.sh`. Verify: `scripts/check.sh --stage-a` (Stage A, via the
> installer's `tests/host-check.sh`), `scripts/check.sh` (post-install), `--all`
> (both). Rehearse with
> [`arch-install-vmtest.sh`](../provision/scripts/arch-install-vmtest.sh). Manual phases
> below remain the reference for what Stage A does.

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
`arch-install-t14s.sh` / `arch-install-p15.sh` and machine profiles) plus
`system/etc/systemd/sleep.conf.d/` (`SuspendState=mem` +
`MemorySleepMode=s2idle`). Check with [Verify sleep](#verify-sleep-s2idle);
after resume, `journalctl -b | grep "suspend entry"` →
`PM: suspend entry (s2idle)`.

### Kernel cmdline + `system/` files (installed, not stowed)

`system/` is **not** stowed. `install.sh` runs `system/scripts/system-setup.sh`,
which installs each file as a root-owned regular file (same reason as zram and
GDM). Symlinks from `/etc` into `$HOME` break in two ways:

* Early boot units start before `/home` is mounted; stowed `/etc` links into
  `$HOME` dangle and break services (historically UFW `before.rules`).
* The repo owner could edit root config (udev, sleep, units) without sudo.

`arch-install.sh` / `arch-install-t14s.sh` / `arch-install-p15.sh` write
`/etc/kernel/cmdline` with the LUKS UUID of the disk they configure. Machine
profiles may append host-specific flags (P15: `nvidia_drm.modeset=1` +
`rd.driver.blacklist=nouveau`; T14s: `amd_iommu=on` + `amd_pstate=active`).
`system-setup.sh` does **not** own the cmdline. When a managed `modprobe.d` file changes it runs `mkinitcpio -P`
(sbctl's hook re-signs the UKIs). Replaced files are backed up to
`/var/backups/dotfiles-system/<timestamp>/`. Leftover stow symlinks from older
setups are removed; `scripts/check.sh` flags any that remain.

The four location files (`/etc/geolocation`, GeoClue drop-in, NetworkManager
dispatcher, `50-vpn-location-sync.rules`) are installed by
`security/scripts/location-setup.sh`, and `50-kali-lan-host-prep.rules` is installed by
`labs/scripts/kali-disposable.sh setup`; `system-setup.sh` skips all of them.

---

## Security → Virtualization

Enable:

* Intel Virtualization Technology + Intel VT-d (P15), or AMD SVM + IOMMU (T14s)

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

mount -o fmask=0077,dmask=0077 /dev/nvme0n1p1 /mnt/boot
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
efibootmgr \
wireless-regdb \
xdg-user-dirs
```

*(On T14s Gen 3 AMD, replace `intel-ucode` with `amd-ucode`.)*


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

Configure timezone, locale, hostname, and the initial admin user inside the chroot.

## Timezone

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

*(The Phase 8 `microcode` hook embeds CPU microcode into the initramfs automatically, so a separate `initrd /*-ucode.img` line is not needed. On P15 add `nvidia_drm.modeset=1 rd.driver.blacklist=nouveau`; on T14s AMD replace `intel_iommu=on` with `amd_iommu=on amd_pstate=active`.)*

```bash
nano /boot/loader/entries/arch-hardened.conf
```

Contents:

```text
title   Arch Linux (Hardened)
linux   /vmlinuz-linux-hardened
initrd  /initramfs-linux-hardened.img
options rd.luks.name=YOUR_UUID=cryptroot rd.luks.options=discard root=/dev/mapper/cryptroot rootflags=subvol=@ rw quiet loglevel=3 mem_sleep_default=s2idle lsm=landlock,lockdown,yama,integrity,apparmor,bpf intel_iommu=on
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
initrd  /initramfs-linux-lts.img
options rd.luks.name=YOUR_UUID=cryptroot rd.luks.options=discard root=/dev/mapper/cryptroot rootflags=subvol=@ rw quiet loglevel=3 mem_sleep_default=s2idle lsm=landlock,lockdown,yama,integrity,apparmor,bpf intel_iommu=on
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
rtkit \
evolution-data-server \
earlyoom \
power-profiles-daemon \
sof-firmware \
alsa-ucm-conf \
fprintd \
gnome-software \
mesa \
libva-utils
```

*(Also install GPU drivers: `vulkan-radeon` on T14s AMD, or `vulkan-intel intel-media-driver nvidia-open-dkms nvidia-utils nvidia-prime egl-wayland` on P15 Optimus.)*

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

GNOME 51 uses Wayland by default (`desktop/scripts/gdm-setup.sh` hardens `/etc/gdm/custom.conf` with `WaylandEnable=true`, `DisallowTCP=true`, and XDMCP/autologin disabled). If editing manually:

```bash
nano /etc/gdm/custom.conf
```

Ensure:

```text
WaylandEnable=true
```

---

# PHASE 11 — ZRAM

Do **not** `stow -t / zram`: a symlink into `$HOME` breaks at early boot (home is not mounted when zram-generator runs).

**Option A — Dotfiles (recommended after cloning this repo):**

```bash
cd ~/dotfiles
bash system/scripts/zram-setup.sh
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

Apply (takes effect on the target kernel after reboot; inside `arch-chroot`, `sysctl --system` touches the live ISO kernel):

```bash
sysctl --system
```

`system/scripts/system-setup.sh` also installs `/etc/sysctl.d/99-perf.conf`
(`kernel.perf_event_paranoid = 2`): linux-hardened defaults to 3, which blocks
`perf` for every non-root user. Attaching a debugger to a running process
(`gdb -p`, `strace -p`) still needs `sudo` because of `ptrace_scope = 1`.

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

Configure firewalld (nftables backend, deny inbound). Inside `arch-chroot`, use `firewall-offline-cmd` and `systemctl enable` without `--now` (systemd is not running in chroot):

```bash
pacman -S firewalld
firewall-offline-cmd --set-default-zone=drop
systemctl enable firewalld
# Post-boot (after reboot + cloning dotfiles):
#   bash security/scripts/firewalld-lab-zones.sh   # drop + lab zones; masks ufw
```

*(The Waydroid, Tailscale, Encrypted DNS, and Libvirt sub-sections below use live `firewall-cmd` / `systemctl --now` — run those after rebooting into the installed system.)*

Libvirt: bind `virbr0` to zone `libvirt`. Air-gapped malware net: host-only
`virbr-malware` with bridge `zone="lab-malware"` (iface **and** source
`192.168.200.0/24`; DROP, no masq/forward; DNS off, DHCP advertises
`192.168.200.1`). Details:
[README — firewalld lab zones](../README.md#how-to-firewalld-lab-zones--lab-malware).

Default behavior:

* **deny incoming** — All inbound connections rejected unless explicitly allowed
* **allow outgoing** — All outbound connections permitted

Add SSH rule (post-boot, if needed). Prefer an explicit port over app profiles (inside `arch-chroot`, use `firewall-offline-cmd` and `systemctl enable sshd` without `--now`):

```bash
sudo firewall-cmd --permanent --add-service=ssh
# or: sudo firewall-cmd --permanent --add-port=22/tcp
sudo firewall-cmd --reload
sudo systemctl enable --now sshd
```

Confirm with `firewall-cmd --list-all` and `ss -tlnp | grep ':22'`. Prefer key
auth over passwords. Mask leftover UFW so it never fights firewalld on nftables (omit `--now` in chroot):

```bash
systemctl disable ufw 2>/dev/null || true
systemctl mask ufw 2>/dev/null || true
```

## Waydroid internet (NAT masquerade)

Waydroid bridges the container on `waydroid0` (`192.168.240.1/24`) but provides
no outbound NAT, so containers have no return path and no internet. Bind the
bridge to a zone that allows DHCP/DNS to the host, then enable the idempotent
`waydroid-nat.service` unit (from `system/`, installed by
`system/scripts/system-setup.sh`):

```bash
# host-side DHCP (67) + DNS (53) for the container's dnsmasq
sudo firewall-cmd --permanent --add-port=53/udp
sudo firewall-cmd --permanent --add-port=67/udp
sudo firewall-cmd --reload
sudo systemctl enable --now waydroid-nat.service
```

This service ensures the masquerade rule is added exactly once and survives
firewall reloads. If container forwarding fails, confirm `waydroid0` is in a
zone that permits forward (or use the stock `libvirt` pattern from lab-zones).

## Tailscale + firewalld

Tailscale’s default `netfilter-mode=on` already accepts `tailscale0` in its own
chains ([docs](https://tailscale.com/docs/reference/netfilter-modes)). On a
default-`drop` host still bind the mesh iface and allow WireGuard so policy is
visible if netfilter mode is `off`:

`./install.sh` installs `tailscale` but does not enable the daemon (a network
service stays opt-in; Stage A enables it only when its Tailscale box is ticked).
Without `tailscaled` there is no `tailscale0`, so bind the firewall after it is up:

```bash
sudo systemctl enable --now tailscaled
sudo tailscale up
bash security/scripts/firewalld-tailscale.sh
# equivalent:
#   sudo firewall-cmd --permanent --zone=trusted --change-interface=tailscale0
#   sudo firewall-cmd --permanent --add-port=41641/udp
#   sudo firewall-cmd --reload
```

`./install.sh` runs this when `tailscale` is on PATH. Official lock-down guide
(Ubuntu/UFW wording; map to firewalld above):
[Secure Ubuntu with UFW](https://tailscale.com/docs/how-to/secure-ubuntu-server-with-ufw).

## Encrypted DNS (optional)

Plain Cloudflare DNS via NetworkManager:
`bash security/scripts/network-dns-setup.sh` (also run from `location-setup.sh`).

Encrypted DNS (dnscrypt-proxy on loopback, then point NM at it):

```bash
bash security/scripts/dnscrypt-setup.sh
# daemon only: SKIP_NM=1 bash security/scripts/dnscrypt-setup.sh
```

Listens on `127.0.0.1:53` and `[::1]:53`. NM global DNS
(`/etc/NetworkManager/conf.d/90-dnscrypt-global-dns.conf`) pins every
connection, VPN and Tailscale included, to it; the tailnet `*.ts.net` suffix
still resolves via MagicDNS (`100.100.100.100`). Trade-offs: Proton NetShield
is bypassed, and nothing resolves while dnscrypt-proxy is down. Skip the pin
with `SKIP_NM_GLOBAL=1`. Howto:
[README — ops / privacy kits](../README.md#how-to-ops--privacy-kits).

## Libvirt disposable Kali (virbr0 NAT)

Default zone `drop` rejects unsolicited inbound; guest NAT needs `virbr0` in
stock `libvirt` (forward + masquerade). `firewalld-lab-zones.sh` + kali
`setup` / `start --nat` / `start --lan` bind that; malware guests use
`virbr-malware` → `lab-malware` (see [README howto](../README.md#how-to-firewalld-lab-zones--lab-malware)).

Boot unit `virbr0-up.service` (`system/`, via `system-setup.sh` / kali
`setup`) runs `virsh net-start default` then `ip link set virbr0 up` after
`libvirtd` (avoids `Cannot find device virbr0`). Check:
`systemctl status virbr0-up`. Lab usage:
[fresh-install RE — Disposable Kali](fresh-install-coding-re.md#disposable-kali).

---

# PHASE 14 — THINKPAD OPTIMIZATION

PPD, `sof-firmware`, `alsa-ucm-conf`, and `fprintd` come from Phase 10 / the
matching installer (`fprintd` is D-Bus activated — do not systemctl-enable it).
Optional power diagnostics:

```bash
pacman -S powertop
```

**Power stack note:** this system uses **power-profiles-daemon (PPD)**, or on hosts from `stage-a/` **tuned + `tuned-ppd`** (same GNOME power menu API; see the T14s notes below). Nothing else manages power.

* **TLP is *not* used** — it conflicts with PPD (`PLATFORM_PROFILE.../CPU_ENERGY_PERF_POLICY... not set because power-profiles-daemon is running`). Do not install `tlp`/`tlp-rdw`.
* **thermald is *not* used** — it self-exits on these ThinkPads (`[dytc_lapmode] present: Thermald can't run on this platform`); thermal is firmware-managed (Intel DPTF on P15 / AMD DYTC on T14s). Leave it uninstalled/disabled.
* **Skip `ryzenadj`** on T14s Gen 3 AMD PRO — EC often locks SMU; not part of the profile.

**Shared charge window 70–80** (`arch-install-t14s.sh` + `arch-install-p15.sh`):
seed tmpfiles from `system/templates/thinkpad-charge-thresholds.conf`, install
`/etc/udev/rules.d/61-thinkpad-charge-limit.rules` (`ENV{CHARGE_LIMIT}="70,80"`
so UPower 1.90+ / GNOME Preserve Battery Health does not reset
`charge_control_start_threshold` to `0`), **and** enable
`thinkpad-charge-thresholds.service` (late BAT* sysfs; apply under
`/usr/local/lib/thinkpad/`). Live refresh:
`system/scripts/thinkpad-charge-thresholds.sh` (also `install-re-extras.sh` / profiles).

**P15 Gen 1 (20SU)** extras (`arch-install-p15.sh` + `profiles/thinkpad-p15.sh`):

* Cmdline: `intel_iommu=on` `nvidia_drm.modeset=1` `rd.driver.blacklist=nouveau`
* GPU: `nvidia-open-dkms` + `nvidia-utils` / `nvidia-prime` / `egl-wayland` +
  `mesa` / `vulkan-intel` / `intel-media-driver`; `LIBVA_DRIVER_NAME=iHD`;
  `nvidia.conf`, early KMS MODULES, `nvidia-suspend`/`resume`/`hibernate`,
  `80-nvidia-pm.rules`
* Optional Stage A: `INSTALL_OLLAMA=Y` → `ollama-cuda` on `127.0.0.1:11434`
* Fingerprint: palm-rest Synaptics `06cb:00bd` (`fprintd`)

**T14s Gen 3 AMD (21CQ/21CR)** extras (installer + `profiles/thinkpad-t14s.sh`):

* Cmdline: `amd_iommu=on` `amd_pstate=active` (strip any `intel_iommu` / `i915.*` leftovers; rebuild UKI)
* Power: PPD by default; if the host came from `stage-a/` with
  tuned, `tuned` + `tuned-ppd` (same GNOME power menu API) replace PPD —
  `./install.sh` then skips `power-profiles-daemon` and the profile enables tuned
* GPU / Wi-Fi / FP packages: `packages/thinkpad-t14s.txt` (`mesa` + `vulkan-radeon` + `libva-utils` + `wireless-regdb` + `fprintd`; VA-API via `LIBVA_DRIVER_NAME=radeonsi` in `.shell-exports`, `/etc/environment.d/99-wayland.conf`, and GDM override)
* Touchpad `s2idle` wakeup: `/etc/udev/rules.d/71-thinkpad-t14s-touchpad-wakeup.rules` disables I2C touchpad wakeup (`i2c-ELAN0678:*` / `i2c-SYNA8018:*`) so lid flex in transit does not wake the laptop from `s2idle`
* Fingerprint: power-button Goodix `27c6:6594` (`fprintd`)

---

# Configure Battery Thresholds

*(Post-boot — run from `~/dotfiles` after Phase 27.)*

Without TLP, set ThinkPad charge thresholds via the `thinkpad_acpi` sysfs
interface. Prefer the shared helper (writes live sysfs +
`/etc/tmpfiles.d/thinkpad-charge-thresholds.conf` + late-boot
`thinkpad-charge-thresholds.service`). Auto-applied by
`profiles/thinkpad-t14s.sh` and `provision/scripts/install-re-extras.sh`. Safe to re-run
on P15 (live BAT* → write + persist). On desktop/VM/non-ThinkPad with no
BAT*, the helper plain-skips (no unit). Only ThinkPad DMI may seed BAT0
tmpfiles + service when charge_control_* is not visible yet (late
`thinkpad_acpi`; enable uses `start --no-block` so the helper does not wait):

```bash
bash system/scripts/thinkpad-charge-thresholds.sh
# keep a custom window (example used on some hosts):
# CHARGE_START=75 CHARGE_END=80 bash system/scripts/thinkpad-charge-thresholds.sh
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

*(Post-boot — requires D-Bus `fprintd` on the booted system.)*

```bash
bash system/scripts/fingerprint-setup.sh
# or: fprintd-enroll
```

P15 uses Synaptics `06cb:00bd` (palm rest). T14s Gen 3 AMD uses Goodix
`27c6:6594` (power button). Both work with `fprintd` / `libfprint` on Arch.

---

# PHASE 15 — SNAPSHOTS

`snapper` and `snap-pac` are installed in Phase 6. Because Phase 5 already mounted `@snapshots` at `/.snapshots`, unmount and remove the mount point before `create-config` (use `--no-dbus` and plain `systemctl enable` inside `arch-chroot`):

```bash
umount /.snapshots && rmdir /.snapshots
snapper --no-dbus -c root create-config /
btrfs subvolume delete /.snapshots
mkdir -p /.snapshots && mount -a && chmod 750 /.snapshots
systemctl enable snapper-timeline.timer snapper-cleanup.timer
```

---

# PHASE 16 — FLATPAK SANDBOXING

*(Post-boot — run after Phase 24 reboot.)*

Enable Flathub:

```bash
flatpak remote-add --if-not-exists flathub \
https://flathub.org/repo/flathub.flatpakrepo
```

Apps: `packages/flatpak.txt` (browsers, Proton VPN, Android Studio, Sticky Notes). Stage A
leaves first-boot Flatpaks opt-in (`INSTALL_FLATPAK_APPS=N` by default; browsers + Proton VPN
via `t14s-flatpak-apps.timer` when enabled); `./install.sh` (`provision/scripts/install-flatpaks.sh`)
installs the full list.

---

# PHASE 17 — ROOTLESS PODMAN

*(Post-boot — run as your desktop user after Phase 24 reboot.)*

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
bash ai/scripts/agent-run.sh ~/src/my-job alpine:3.20 sh
# AGENT_NET=pasta bash ai/scripts/agent-run.sh ~/src/my-job alpine:3.20  # allow egress
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
* x86-64-v3 makepkg + `rebuild-v3.sh`, PhotoGIMP, and Dash2Dock: [README — Desktop, GNOME Theme Packs & Optional Apps](../README.md#desktop-gnome-theme-packs--optional-apps) and [GNOME extensions](../README.md#how-to-gnome-extension-zips-fetch-gnome-extensionssh)
* Headroom proxy (Claude / Cursor): [README — AI Tooling & Headroom](../README.md#ai-tooling--headroom)

---

# PHASE 17f — GHIDRA-CLI / LAB-RE (OPTIONAL)

*(Post-boot — run from `~/dotfiles` after Phase 27.)*

```bash
# preferred RE stack (JDK21 + Ghidra + jadx + rizin + rea-agents@6.10.1):
lab-re --check && lab-re
# optional host cargo CLI when pacman ghidra is installed:
bash ai/scripts/install-ghidra-cli.sh
```

* Terminals: kitty (primary: Super+Return, `xdg-terminals.list`, `x-scheme-handler/terminal`) + ghostty + gnome-console + optional contour/alacritty; rice via `desktop/scripts/rice-setup.sh` (Gruvbox default; `rice-theme gruvbox|secops|--dry` covers Kitty/Neovim/Contour wrapper+desktop/htop/bat/fzf/GNOME accent+TextEditor + fastfetch PNG logos). Ptyxis/rio/wezterm/foot pruned.
* ghidra-cli: cargo CLI + host skill under `ai/skills/ghidra-cli-host/`; GUI via `ghidra-gui` (cargo `ghidra` shadows `/usr/bin/ghidra`). An install failure is recorded by `./install.sh`, which exits 1 at the end
* Host `install-rea.sh` is optional only (needs JDK≥21); Stage B AI stack skips it

---

# PHASE 18 — FIRMWARE UPDATES

*(Post-boot — `fwupdmgr` requires a booted system with D-Bus.)*

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

(Stage A enables `Color`, `ILoveCandy`, `VerbosePkgLists`, `CheckSpace`, and `ParallelDownloads` on both the live ISO and target.)

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

(Stage A writes this file with optional `--country` when `REFLECTOR_COUNTRY` is set, otherwise worldwide. Live ISO `reflector` uses `--latest 20`.)

Enable timer (omit `--now` while inside `arch-chroot`):

```bash
systemctl enable reflector.timer
```

---

# PHASE 20 — GNOME PRIVACY

*(Post-boot — requires a GNOME user session.)*

Prefer the unified hardener (GNOME + browsers + IDE/telemetry env):

```bash
bash security/scripts/privacy-hardener.sh
```

Manual GNOME-only (subset; hardener covers more):

```bash
gsettings set org.gnome.desktop.privacy report-technical-problems false
gsettings set org.gnome.desktop.privacy remember-recent-files false
```

Extra kits from `packages/pacman.txt` (after `./install.sh`):

| Tool | Role |
|------|------|
| `mat2` / `exiftool` | Strip or inspect metadata before share/upload |
| `bleachbit` | Periodic UI / cache junk |
| `ops-hygiene.sh` | `paccache` + `flatpak uninstall --unused` + weekly timer |
| `usbguard-setup.sh` | Opt-in USB allowlist (BadUSB) |
| `dnscrypt-setup.sh` | Opt-in encrypted DNS |

Howto: [README — ops / privacy kits](../README.md#how-to-ops--privacy-kits).

---

# PHASE 21 — UNIFIED KERNEL IMAGES (UKIs)

Create cmdline:

```bash
mkdir -p /etc/kernel
nano /etc/kernel/cmdline
```

Contents (single line; on P15 add `nvidia_drm.modeset=1 rd.driver.blacklist=nouveau`, on T14s AMD replace `intel_iommu=on` with `amd_iommu=on amd_pstate=active`):

```text
rd.luks.name=YOUR_UUID=cryptroot rd.luks.options=discard root=/dev/mapper/cryptroot rootflags=subvol=@ rw quiet loglevel=3 mem_sleep_default=s2idle lsm=landlock,lockdown,yama,integrity,apparmor,bpf intel_iommu=on
```

`rd.luks.options=discard` lets `fstrim.timer` reach the SSD through LUKS (the free-block layout becomes visible to someone holding the disk; contents stay encrypted). On an existing install without it: `sudo cryptsetup --allow-discards --persistent refresh cryptroot`, then check `lsblk -D /dev/mapper/cryptroot` (DISC-GRAN non-zero). `lsm=` replaces the deprecated `security=apparmor`.

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
* stale Arch systemd-boot entries (`arch*.conf`; `linux-*.conf` is kept in case another distro owns it)

`bootctl install` replaces the systemd-boot binary; existing `/EFI/Microsoft/` entries remain for dual-boot.

---

# PHASE 22 — APPARMOR VERIFICATION & ENFORCEMENT

*(Post-boot — run after Phase 24 reboot; the live Arch ISO kernel does not enable the AppArmor LSM.)*

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

Sign UKIs **and** systemd-boot (`-s` saves each path to the sbctl db). If
`sbctl verify` still lists unsigned raw kernels (legacy ESP layout), sign those
too:

```bash
sbctl sign -s /boot/EFI/Linux/arch-linux-lts.efi
sbctl sign -s /boot/EFI/Linux/arch-linux-lts-fallback.efi
sbctl sign -s /boot/EFI/Linux/arch-linux-hardened.efi
sbctl sign -s /boot/EFI/Linux/arch-linux-hardened-fallback.efi
sbctl sign -s /boot/EFI/systemd/systemd-bootx64.efi
sbctl sign -s /boot/EFI/BOOT/BOOTX64.EFI
# only if verify still reports them:
sbctl sign -s /boot/vmlinuz-linux
sbctl sign -s /boot/vmlinuz-linux-lts
sbctl sign -s /boot/vmlinuz-linux-hardened
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

*(Post-boot — complete Phase 24 and boot successfully with Secure Boot **disabled** in BIOS first.)*

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
bootctl status  # Measured UKI: yes (when SB + TPM2 active)
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

Remove orphan packages (only if `pacman -Qtdq` prints packages):

```bash
pacman -Qtdq
pacman -Qtdq | sudo pacman -Rns -
```

Ops hygiene (after Phase 27 clones `~/dotfiles`; also runs from `./install.sh` and
`provision/scripts/post-update.sh`):

```bash
bash security/scripts/ops-hygiene.sh
systemctl is-enabled paccache.timer   # expect: enabled
```

---

# PHASE 27 — DOTFILES SETUP

Log into GNOME, open a terminal, and run as your desktop user (never `sudo ./install.sh`):

```bash
git clone https://github.com/HelllGuest/dotfiles.git ~/dotfiles
cd ~/dotfiles
./install.sh   # opens TUI menu on TTY (--gui, --all, --minimal, --only/skip)
```

Full step order, flags, machine profiles, privacy hardening, and `configure.sh` modules live in [README — Installation & Setup](../README.md#script-execution-order-fresh-machine) (also see [configure.sh](../README.md#how-to-configuresh-stage-b-tui), [VM Stage B](../README.md#how-to-stage-b-on-a-stage-a-qcow2), [firewalld](../README.md#how-to-firewalld-lab-zones--lab-malware), and [ops / privacy kits](../README.md#how-to-ops--privacy-kits)).

Useful standalone entrypoints:

```bash
./stow-only.sh && exec zsh                  # config-only ($HOME symlinks, no root)
bash provision/scripts/install-flatpaks.sh  # refresh Flatpaks only
bash provision/scripts/install-aur.sh       # refresh AUR packages only
bash scripts/check.sh --all                 # verify Stage A + Stage B
```

For coding, reverse engineering, and malware-lab stacks, see [fresh-install-coding-re.md](fresh-install-coding-re.md).

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
   / profile owns that file). Then `bash system/scripts/system-setup.sh` (installs
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
sudo dmesg | grep -i iommu   # kernel.dmesg_restrict = 1 (Phase 12)
```

Expected output shows IOMMU entries confirming Intel VT-d or AMD-Vi is active.

---

# Verify Firewall

This tree uses **firewalld** (`nftables`, default zone `drop`). UFW should be
masked. Full howto:
[README — firewalld lab zones](../README.md#how-to-firewalld-lab-zones--lab-malware).

```bash
systemctl is-enabled ufw                  # expect: masked
systemctl is-active firewalld             # expect: active
sudo firewall-cmd --get-default-zone      # expect: drop
sudo firewall-cmd --get-active-zones      # virbr0→libvirt; virbr-malware→lab-malware
sudo firewall-cmd --permanent --zone=lab-malware --list-all
# expect: interfaces: virbr-malware; sources: 192.168.200.0/24; target: DROP
```

If `virbr-malware` still sits under `libvirt` or `block`, re-run
`sudo bash security/scripts/firewalld-lab-zones.sh` on a real TTY (redefines bridge
`zone="lab-malware"`; polkit auth required).

Ops / privacy soft checks: [README — ops / privacy kits](../README.md#how-to-ops--privacy-kits)
(`mat2` / `usbguard` / `dnscrypt-proxy`; `check.sh` prints ○ until enabled).

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

All signed binaries should pass `sbctl verify`. With SB + TPM2 enabled, `bootctl status` should show `Measured UKI: yes`.

UKIs rebuilt with `mkinitcpio -P` are re-signed by sbctl's mkinitcpio hook (see [Phase 23](#phase-23--secure-boot-with-sbctl)).

---

# Verify GDM Wayland

```bash
sudo systemctl status gdm
journalctl -u gdm -n 20
```

Look for "Wayland" in output to confirm session type.
