# Fresh install: coding, reverse engineering, malware analysis

Purpose-oriented guide for this repository on the **Lenovo ThinkPad X1 Yoga Gen 5**
(SKU `20UC`; example hostname `blackbox`). It layers on top of the hardened base
install; it does not replace it.

| Document | Role |
|----------|------|
| [hardened-arch-gnome.md](hardened-arch-gnome.md) | Full phase reference (BIOS → UKI → Secure Boot → GNOME) |
| [../README.md](../README.md) | Dotfiles bootstrap, shell, maintenance |
| This file | Machine profile, purpose stacks, isolation rules |

Automation:

* Bare metal: [`scripts/arch-install.sh`](../scripts/arch-install.sh)
* VM rehearsal: [`scripts/arch-install-vmtest.sh`](../scripts/arch-install-vmtest.sh)
* After first GNOME login: [`../install.sh`](../install.sh)

---

## Target machine (verified)

| Item | Value |
|------|--------|
| Hardware | Lenovo ThinkPad X1 Yoga Gen 5 (`20UC`), chassis convertible |
| Profile | No `profiles/<hostname>.sh` on this box. `apply-profile.sh` falls through to `detect-profile.sh` → `thinkpad-x1` → `profiles/thinkpad-x1.sh` |
| CPU | Intel Core i7-10610U (4C/8T, up to 4.9 GHz), **x86-64-v3** (no AVX-512) |
| RAM | 16 GiB + ~7.7 GiB zram |
| Storage | ~1 TB NVMe; typical layout: EFI + Windows NTFS + recovery + **LUKS2 → btrfs** root |
| GPU | Intel UHD Graphics only (no usable discrete NVIDIA on this chassis) |
| OS target | Arch Linux rolling, `linux-lts` primary / `linux-hardened` fallback UKIs |
| CPU builds | `GOAMD64=v3`, `RUSTFLAGS=-C target-cpu=x86-64-v3` (see README) |

**Fit:** daily coding, static/dynamic RE, and a **light** malware lab. With 16 GiB
RAM, keep analysis VMs small (2–4 GiB). Prefer QEMU/libvirt isolation. Never
detonate unknown samples on the host.

`packages/pacman.txt` may list NVIDIA packages used by other ThinkPad profiles
(e.g. P15). On the X1 Yoga they are usually unused; ignore or skip if nothing
loads.

---

## Purpose of this workstation

1. **Coding** — zsh/bash, Neovim, VSCodium / Cursor, Flutter + Android Studio,
   Node (fnm), Rust / Python (pipx). Go and Docker are goals too, but install
   them separately (not in `packages/pacman.txt`; see Coding stack below).
2. **Reverse engineering** — Ghidra (+ ghidra-cli), plus optional jadx / gdb /
   binwalk / Android tooling; host notes in
   [`skills/ghidra-cli-host/`](../skills/ghidra-cli-host/).
3. **Malware analysis** — host stays clean; samples only in disposable VMs.
   Extra triage packages below are optional and not all listed in
   `packages/pacman.txt`.

---

## Fresh install path

If Windows must stay, choose **MANUAL** partitioning in `arch-install.sh`, reuse
the EFI system partition, and only wipe/recreate the Linux LUKS volume. AUTO
mode wipes the whole disk.

### Stage 0 — BIOS (`F1`)

* Secure Boot: **Disabled** (optional enroll with sbctl after first successful boot;
  see Stage A½)
* Config → Power → Sleep State: **Windows and Linux** if you follow this repo’s
  **s2idle** pin. On ThinkPads, **Linux** turns on classic S3 (`deep`); that
  fights `mem_sleep_default=s2idle` unless you also change cmdline +
  `sleep.conf.d`. Details: [hardened-arch-gnome.md — Phase 1](hardened-arch-gnome.md#phase-1--bios--uefi-configuration)
* Enable: Intel Virtualization Technology, Intel VT-d, Thunderbolt BIOS Assist
* Disable: Intel SGX unless specifically required
* Save: `F10`

### Stage A — Arch ISO (UEFI)

Optional rehearsal on a **working** Arch host that already has this repo checked
out (boots a full install onto a **virtual** disk; real host disks untouched):

```bash
cd /path/to/dotfiles
bash scripts/arch-install-vmtest.sh
```

On the machine, from the official Arch ISO as root:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/HelllGuest/dotfiles/main/scripts/arch-install.sh)
```

What it builds: LUKS2 (argon2id), Btrfs subvolumes including disk-backed `@tmp`,
UKIs (`linux-lts` / `linux-hardened`), systemd-boot, sbctl, minimal GNOME.

Then remove the ISO, reboot, and log into GNOME.

### Stage A½ — Secure Boot (optional; after first good boot, before Stage B)

1. BIOS → clear Secure Boot keys → Setup Mode.
2. `sudo sbctl enroll-keys -m` (`-m` keeps Microsoft keys for a shared ESP / Windows).
3. BIOS → Secure Boot → Enabled.
4. `sbctl status && sbctl verify`.

### Stage B — Dotfiles (requires an active GNOME session)

```bash
git clone https://github.com/HelllGuest/dotfiles.git ~/dotfiles
cd ~/dotfiles
# ThinkPad P15 (hostname p15): optional check, then install (pulls nvidia-* + Optimus profile)
bash scripts/p15-dotfiles-preflight.sh   # skip on X1
./install.sh
# Explicit Optimus re-run if needed: bash profiles/thinkpad-p15.sh
exec zsh
bash scripts/thinkpad-health.sh
reboot   # required after NVIDIA early KMS / nouveau blacklist
```

Step order: [README — what `./install.sh` runs](../README.md#script-execution-order-fresh-machine).

`stow/system/` (kernel cmdline, sleep, logind, i915, makepkg v3, UFW, udev) is
installed by `scripts/system-setup.sh` as root-owned files, not stowed; the
X1-only files (cmdline, i915, sleep, logind, fingerprint rule) install on X1
hardware only; the cmdline gets this machine's booted LUKS UUID. Details:
[hardened-arch-gnome.md — `system/` files](hardened-arch-gnome.md#kernel-cmdline--system-files-installed-not-stowed).
Firewall check: [Verify Firewall](hardened-arch-gnome.md#verify-firewall).

**Sleep drift:** repo files pin `mem_sleep_default=s2idle` and
`MemorySleepMode=s2idle`. A live host may still show `s2idle [deep]` if
`system-setup.sh` never ran or cmdline was edited to `deep`. Check
`/proc/cmdline` and `/sys/power/mem_sleep` after changes.

---

## Coding stack

### From `./install.sh` / package lists

| Layer | What |
|-------|------|
| Shell | zsh (zinit), bash, starship, atuin, fzf, zoxide, direnv |
| Editors | Neovim (Lazy), VSCodium (`vscodium-bin`), Cursor / Antigravity (AUR) |
| Languages | fnm Node 22, rust, `python-pipx`, `flutter-bin`, jdk-openjdk (+ JDK 17 for Android) |
| Mobile | Flatpak Android Studio; `ANDROID_HOME` in `.shell-exports`; alias `as` |
| AI (optional) | `bash scripts/headroom-setup.sh`, then `hr-claude` / `hr-cursor` |
| Local builds | x86-64-v3 makepkg drop-in; `bash scripts/rebuild-v3.sh` after big upgrades |

### Not in `packages/pacman.txt` (install separately)

Docker and Go are common on this workstation but are **not** pulled by
`./install.sh`. Add them after Stage B:

```bash
sudo pacman -S --needed docker docker-compose go
sudo systemctl enable --now docker
sudo usermod -aG docker "$USER"
# newgrp docker   # or log out/in
```

Shell already picks `DOCKER_HOST` only when a Podman socket exists; with Docker
enabled and Podman idle, the CLI uses `/var/run/docker.sock`. Prefer Docker over
Podman unless you intentionally enable `podman.socket`.

Sanity checks:

```bash
~/dotfiles/scripts/check.sh
fnm current
docker ps
go version
```

---

## Reverse engineering stack

### Core

`./install.sh` installs `ghidra`, `jdk-openjdk`, `jdk17-openjdk`, and `rust`
(`packages/pacman.txt`) and runs `scripts/install-ghidra-cli.sh`. Check:

```bash
ghidra doctor
ghidra-gui   # GUI; cargo `ghidra` on PATH shadows /usr/bin/ghidra
```

### Official extras (optional; none are in `pacman.txt`)

A pure `./install.sh` does **not** install these RE/malware-lab companions
(QEMU/libvirt: see [Host virtualization](#host-virtualization)):

```bash
sudo pacman -S --needed \
  jadx gdb binwalk android-tools \
  rizin rz-cutter rz-ghidra hexyl yara strace ltrace smali
```

### AUR extras (optional; use paru/yay after `install-aur.sh`)

```bash
paru -S --needed imhex-bin android-apktool-bin
```

### Ghidra footguns on this machine

From [`skills/ghidra-cli-host/SKILL.md`](../skills/ghidra-cli-host/SKILL.md):

* CLI: `~/.cargo/bin/ghidra`; GUI: `ghidra-gui` → `/opt/ghidra/ghidraRun`
* Exit codes are unreliable; prefer `--json` and check `"status":"success"`
* Android tooling may set `JAVA_HOME` to 17; CLI uses `GHIDRA_CLI_JAVA_HOME` (≥ 21)
* Projects live under `~/ghidra-cli-projects`

Smoke test:

```bash
ghidra doctor
ghidra import /usr/bin/true --project smoke --no-analyze
ghidra program list --project smoke
ghidra project delete smoke
```

---

## Malware analysis

### Isolation rules (non-negotiable)

* Never run unknown samples on the host.
* Use disposable guests with snapshots taken before every run.
* Do not give the guest write access to host directories unless intentional.
* Prefer an isolated virtual network (no bridged LAN) for unknown samples.
* On 16 GiB host RAM: one analysis VM at a time, **2–4 GiB** guest RAM, 2 vCPUs.

### Host virtualization

Install/enable the management stack:

```bash
sudo pacman -S --needed virt-manager qemu-full libvirt edk2-ovmf
sudo systemctl enable --now libvirtd
sudo usermod -aG libvirt "$USER"
# log out/in, then:
virt-manager
```

Use UEFI (OVMF) guests. Prefer a Linux analysis guest; add a Windows guest only
if you accept licensing and risk.

### Optional host triage (static / inert only)

These tools triage binaries or capture traffic; they are not a substitute for a
sandbox. Prefer running dynamic agents (Frida, debuggers against live malware)
inside the guest.

```bash
sudo pacman -S --needed clamav upx wireshark-qt tcpdump mitmproxy nmap   # + yara/binwalk above
```

---

## Hardware constraints (keep these in mind)

* **16 GiB RAM** — avoid heavy parallel builds plus a large VM plus Ghidra.
* **iGPU only** — no CUDA; GPU-heavy ML/RE is a poor fit.
* **Comet Lake = x86-64-v3** — never target v4 in makepkg / `RUSTFLAGS`.
* **Yoga convertible** — tablet rotate / sensors via profile + `iio-sensor-proxy`.
* **zram** — helps under memory pressure; still plan workloads.

---

## One-page checklist

Same order as Stages 0 → A → A½ → B (matches README):

```text
BIOS (SB off, VT-x/d on; Sleep = Windows and Linux for s2idle)
  → Arch ISO → arch-install.sh (AUTO wipe, or MANUAL + reuse EFI)
  → reboot → GNOME login
  → optional: sbctl enroll-keys -m → enable SB in BIOS → sbctl verify
  → clone dotfiles → ./install.sh (installs stow/system/ via system-setup.sh) → exec zsh
  → thinkpad-health.sh → reboot
  → coding extras if needed: docker + go
  → RE: ghidra doctor + ghidra-gui; optional jadx / rz-cutter / …
  → malware: libvirtd + isolated VM only (never host detonation)
```

---

## Related maintenance

General tasks: [README — Maintenance](../README.md#-maintenance). On this machine also:

| Task | Command |
|------|---------|
| ThinkPad health | `bash scripts/thinkpad-health.sh` |
| Secure Boot | `sbctl status && sbctl verify` |
