# Definitive Hardened Arch Linux + GNOME Wayland Guide

## For the Lenovo ThinkPad X1 Yoga Gen 5

### Modern Security, Power Management, Btrfs Snapshots, UKIs, and Secure Boot

This guide builds a modern Arch Linux workstation with:

* UEFI boot
* LUKS2 full-disk encryption
* Btrfs subvolumes
* GNOME on Wayland
* linux-zen primary kernel
* linux-lts fallback kernel
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
```

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
linux-zen \
linux-zen-headers \
linux-lts \
linux-lts-headers \
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
useradd -m -G wheel -s /bin/bash yourusername
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
default arch-zen.conf
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

# Create Zen Boot Entry

```bash
nano /boot/loader/entries/arch-zen.conf
```

Contents:

```text
title   Arch Linux (Zen)
linux   /vmlinuz-linux-zen
initrd  /intel-ucode.img
initrd  /initramfs-linux-zen.img
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

```bash
pacman -S \
gnome \
gdm \
apparmor \
ufw \
zram-generator \
flatpak \
fwupd \
bolt \
xdg-desktop-portal \
xdg-desktop-portal-gnome \
pipewire \
pipewire-pulse \
wireplumber \
earlyoom
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

---

# PHASE 14 — THINKPAD OPTIMIZATION

Install:

```bash
pacman -S \
tlp \
tlp-rdw \
thermald \
powertop \
sof-firmware \
alsa-ucm-conf \
fprintd \
iio-sensor-proxy
```

Enable:

```bash
systemctl enable --now tlp
systemctl enable --now thermald
systemctl enable --now iio-sensor-proxy
```

---

# Configure Battery Thresholds

Edit:

```bash
nano /etc/tlp.conf
```

Set:

```ini
START_CHARGE_THRESH_BAT0=70
STOP_CHARGE_THRESH_BAT0=80
```

---

# Fingerprint Enrollment

```bash
fprintd-enroll
```

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
flatpak install flathub com.visualstudio.code
flatpak install flathub org.mozilla.firefox
```

Optional scoped filesystem access:

```bash
flatpak override --filesystem=~/Projects com.visualstudio.code
```

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

```bash
echo 'export DOCKER_HOST="unix://$XDG_RUNTIME_DIR/podman/podman.sock"' >> ~/.bashrc
source ~/.bashrc
```

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

# Configure linux-zen UKI Preset

Edit:

```bash
nano /etc/mkinitcpio.d/linux-zen.preset
```

Contents:

```ini
PRESETS=('default' 'fallback')

default_uki="/boot/EFI/Linux/arch-linux-zen.efi"
default_options=""

fallback_uki="/boot/EFI/Linux/arch-linux-zen-fallback.efi"
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

Install:

```bash
pacman -S sbctl
```

Check status:

```bash
sbctl status
```

System should be in:

```text
Setup Mode
```

If not:

* enter BIOS
* clear Secure Boot keys
* return to Setup Mode

---

# Create Keys

```bash
sbctl create-keys
```

---

# Enroll Keys

```bash
sbctl enroll-keys -m
```

`-m` also imports Microsoft keys for broader firmware/device compatibility.

---

# Sign UKIs

```bash
sbctl sign -s /boot/EFI/Linux/arch-linux-zen.efi
sbctl sign -s /boot/EFI/Linux/arch-linux-zen-fallback.efi

sbctl sign -s /boot/EFI/Linux/arch-linux-lts.efi
sbctl sign -s /boot/EFI/Linux/arch-linux-lts-fallback.efi
```

Verify signatures:

```bash
sbctl verify
```

---

# IMPORTANT

Only remove old loader entries AFTER confirming UKIs boot correctly.

If UKIs work properly:

```bash
rm /boot/loader/entries/arch-zen.conf
rm /boot/loader/entries/arch-lts.conf
```

---

# Re-enable Secure Boot

Return to BIOS:

```text
Security → Secure Boot → Enabled
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

# PHASE 27 — VERIFICATION

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
tlp-stat -b
```

---

# Verify Secure Boot

```bash
sbctl status
```

Expected:

```text
Secure Boot: enabled
```

---

# Verify GDM Wayland

```bash
sudo systemctl status gdm
journalctl -u gdm -n 20
```

Look for "Wayland" in output to confirm session type.
