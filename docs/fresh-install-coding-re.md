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

* Bare metal (X1 / generic): [`scripts/arch-install.sh`](../scripts/arch-install.sh)
* Bare metal (T14s Gen 3 AMD, 21CQ/21CR): [`scripts/arch-install-t14s.sh`](../scripts/arch-install-t14s.sh)
* VM rehearsal: [`scripts/arch-install-vmtest.sh`](../scripts/arch-install-vmtest.sh) (`INSTALLER=arch-install-t14s.sh` for the AMD script)
* After first GNOME login: [`../install.sh`](../install.sh)

**T14s Gen 3 AMD note:** this guide’s verified table is the X1 Yoga. On a
**21CQ/21CR** T14s, use the AMD installer, then `./install.sh` (detect →
`thinkpad-t14s`). Expect `amd_iommu` / `amd_pstate`, `mesa` + `vulkan-radeon`,
`fprintd`, and charge thresholds **70–80** via
[`scripts/thinkpad-charge-thresholds.sh`](../scripts/thinkpad-charge-thresholds.sh).
Skip `thinkpad-health.sh` (i915-only). Details:
[hardened Phase 14](hardened-arch-gnome.md#phase-14-thinkpad-optimization).

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
   Node (fnm), Rust / Python (pipx), rootless Podman (agent sandboxes;
   `packages/pacman.txt`). Go is optional and separate (see Coding stack below).
2. **Reverse engineering** — Ghidra (+ ghidra-cli), REA MCP, RE agent skills,
   plus optional host tools (`packages/re-extra.txt`); host notes in
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
# AI tools (also run by install.sh when npm/ghidra present):
#   bash scripts/sync-agent-skills.sh
#   bash scripts/install-coding-agents.sh   # OpenCode + Kimi CLIs + MCP
#   bash scripts/install-caveman.sh         # /caveman voice + skills
#   bash scripts/install-android-ui-skills.sh  # Compose + Material 3
#   bash scripts/install-ghidra-cli.sh
#   bash scripts/install-rea.sh             # optional: INSTALL_HOPPER=1
#   bash scripts/install-re-skills.sh       # leanrea + RE playbooks + Android + Ghidra loop
#   bash scripts/install-re-extras.sh       # optional host pkgs (jadx, rizin, …)
#   bash scripts/install-ecosystem-skills.sh  # packages/agent-skills.txt (Meson/QEMU, Arch triage, web quality, …; owner/repo:skill OK)
#   bash scripts/sync-agent-skills.sh
#   ONLY_CAVEMAN_OPENCODE=1 bash scripts/install-coding-agents.sh
exec zsh
bash scripts/thinkpad-health.sh
reboot   # required: UKI must embed nvidia_drm.modeset=1 + rd.driver.blacklist=nouveau
# after reboot (P15 Optimus):
tr ' ' '\n' </proc/cmdline | grep -E 'nvidia_drm|blacklist=nouveau'
lspci -nnk -d 10de: | grep -A2 'Kernel driver'   # expect: nvidia (not nouveau)
prime-run nvidia-smi -L
```

Step order: [README — what `./install.sh` runs](../README.md#script-execution-order-fresh-machine).

`stow/system/` (kernel cmdline, sleep, logind, i915, makepkg v3, UFW, udev,
`virbr0-up.service`) is installed by `scripts/system-setup.sh` as root-owned
files, not stowed; the X1-only files (cmdline, i915, fingerprint rule) install
on X1 hardware only; the cmdline gets this machine's booted LUKS UUID. Details:
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

### Containers (Podman — in `pacman.txt`)

After Stage B / `./install.sh`, finish Podman storage + socket (Phase 17):

```bash
mkdir -p ~/.local/share/containers/storage && chattr +C ~/.local/share/containers/storage
systemctl --user enable --now podman.socket
bash ~/dotfiles/scripts/agent-run.sh /tmp alpine:3.20 echo ok   # optional smoke
```

`DOCKER_HOST` prefers Podman when `podman.socket` is up. Real Docker daemon for
one shell: `FORCE_DOCKER=1`.

### Not in `packages/pacman.txt` (install separately)

Go is optional and not pulled by `./install.sh`:

```bash
sudo pacman -S --needed go
```

Sanity checks:

```bash
~/dotfiles/scripts/check.sh
fnm current
podman info   # Rootless: true
go version    # if installed
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

Manifest: [`packages/re-extra.txt`](../packages/re-extra.txt). Installer:

```bash
bash scripts/install-re-extras.sh
# same as:
# sudo pacman -S --needed jadx gdb binwalk android-tools rizin rz-cutter \
#   rz-ghidra hexyl yara strace ltrace smali radare2
```

QEMU/libvirt: see [Host virtualization](#host-virtualization) / [Disposable Kali](#disposable-kali).

### AUR extras (optional; use paru/yay after `install-aur.sh`)

```bash
paru -S --needed imhex-bin android-apktool-bin
```

### AI reverse-engineering (MCP + skills)

`./install.sh` already runs REA + RE skills when npm/npx are available.

| Layer | What | Install |
|-------|------|---------|
| **REA** | MCP + CLI across native / JS / .NET / web / Android; uses your Ghidra/jadx | `bash scripts/install-rea.sh` |
| **leanrea** | Small skill: shell-tool RE, no MCP (cheap triage) | `bash scripts/install-re-skills.sh` |
| **reverse-engineering** | Playbooks + triage scripts (EncidXVII) | same |
| **android-reverse-engineering** | APK/XAPK API recovery (jadx) | same |
| **ghidra-iterative-re** | Safe Ghidra apply→verify loop | same |
| **firmware-extraction** / **firmware-static-analysis** / **firmware-emulation** / **ghidra-re** / **firmware-security-reports** | Firmware/IoT unpack → analyze → emulate (OrbitCurve) | same |
| **ghidra-cli-host** | This machine’s Ghidra CLI footguns | repo `skills/` + sync |

Firmware host tools (squashfs, mtd-utils, flashrom, uboot-tools, qemu-user-static, …)
are in [`packages/re-extra.txt`](../packages/re-extra.txt) via `install-re-extras.sh`.
Prefer **unblob** then binwalk for nested images (pipx/`paru` if not in repos).

Manifest: [`packages/agent-skills-re.txt`](../packages/agent-skills-re.txt).

Optional native-only MCP (not installed by default; REA already bridges Ghidra):

* [LaurieWired/GhidraMCP](https://github.com/LaurieWired/GhidraMCP)
* [bethington/ghidra-mcp](https://github.com/bethington/ghidra-mcp)
* IDA: [mrexodia/ida-pro-mcp](https://github.com/mrexodia/ida-pro-mcp) (needs IDA Pro)

Survey (Oct 2026): [AI RE tools compared](https://dev.to/leemie8848/ai-reverse-engineering-tools-compared-rea-ida-mcp-ghidramcp-and-friends-oct-2026-3hfl).

```bash
bash scripts/install-rea.sh
bash scripts/install-re-skills.sh
bash ~/dotfiles/scripts/check.sh   # ○/✓ for leanrea, reverse-engineering, …
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

### Disposable Kali

Immutable qcow2 base + ephemeral session overlay. `wipe` deletes the overlay
and undefines the domain; base stays clean. Script:
`scripts/kali-disposable.sh`. Shell aliases (after stow / `reload`):

| Alias | Action |
|-------|--------|
| `kali` | Pass-through to the script (`kali setup`, `kali status`, …) |
| `kali-up` | `start --isolated` — new overlay, **no guest WAN** (samples) |
| `kali-up-nat` | `start --nat` — guest DHCP + internet (apt / cloud-init) |
| `kali-up-lan` | `start --lan` — NAT + physical ethernet (`enp0s31f6` macvtap → guest eth1) |
| `kali-lan` | `attach-lan` — add physical LAN NIC to a running guest |
| `kali-wipe` | Destroy domain + delete overlay |
| `kali-stop` | Power off; keep overlay |
| `kali-st` | Status |

```bash
bash scripts/kali-disposable.sh setup    # once: libvirt pkgs + download base + UFW/virbr0
# re-login / newgrp libvirt
kali-up                                  # isolated (samples)
kali-up-nat                              # NAT for apt/cloud-init
kali-up-lan                              # NAT + physical RJ45 (needs cable on host NIC)
# or: kali-lan                           # hot-attach LAN to already-running guest
kali-st
# NAT: script prints Guest IP; ssh kali@<ip>  (default password kali — change it)
kali-wipe                                # back to clean base
```

**Physical LAN:** `--lan` / `attach-lan` sets `nat+lan`: NAT eth0 plus host
`KALI_LAN_IFACE` (default `enp0s31f6`, else first ethernet) as guest eth1 via
macvtap bridge mode. Dual defaults break LAN: host RJ45 must have **no IP**
(wifi keeps default — `scripts/kali-lan-host-prep.sh` / `pkexec kali-lan-host-prep`);
guest eth1 gets DHCP on the LAN **without** gateway/DNS/routes (NAT eth0 is
the only default). Verify with `kali lan-check`. Public DNS on eth0. Cable
required for eth1; NAT works without one.

Also listed in [gnome/keybindings.md](../gnome/keybindings.md#disposable-kali).

Base: `/var/lib/libvirt/images/kali-disposable/kali-base.qcow2` (system qemu
cannot read `$HOME`). Each `start` rebuilds `kali-session.qcow2` unless
`KEEP_OVERLAY=1`. No host shares. Defaults: **isolated** net, 4096 MiB RAM,
4 vCPU (`KALI_RAM_MB` / `KALI_VCPUS` / `KALI_NET` / `KALI_VM_DIR` override).

**NAT / UFW:** `setup` and `start --nat` allow traffic on `virbr0`, forward guest
subnet `192.168.122.0/24`, and bring the bridge up. Boot unit
`virbr0-up.service` (from `stow/system/`, also installed by `setup`) starts the
libvirt `default` network then `ip link set virbr0 up` so the bridge exists
after reboot. Cloud-init NoCloud seed sets hostname `kali-disposable`, enables
password SSH, and uses a fresh `instance-id` each overlay. Default login
`kali`/`kali` — change after first SSH.

### Optional host triage (static / inert only)

These tools triage binaries or capture traffic; they are not a substitute for a
sandbox. Prefer running dynamic agents (Frida, debuggers against live malware)
inside the guest.

```bash
sudo pacman -S --needed clamav upx wireshark-qt tcpdump mitmproxy nmap   # + yara/binwalk above
```

### CPE / home gateway without a firmware file (e.g. Brovi H155-381)

**Brovi H155-381** is a 5G CPE (Brovi/ZOWEE). Admin UI is usually
`http://192.168.8.1`. [Vendor support](https://www.brovi-tech.com/service.php)
ships manuals/DoC, **not** a public `.bin`. Updates are **OTA** from
ZOWEE/carrier.

Without an image, leanrea cannot unpack a rootfs. Do this instead:

1. About/System: record **software version** + hardware revision.
2. Update page: if “check update” downloads a package, save it from the browser
   Network tab (analyze offline — do not flash unknown builds).
3. Export config backup; open offline for leftover secrets.
4. Disable WAN/remote admin if present; change Wi‑Fi + admin passwords.
5. From LAN only: `nmap -sV <router-ip>` for open services.

When you have a `.bin`/`.zip`: `unblob -e out file` (or `binwalk -e`), then
`/leanrea` + firmware-static-analysis on `out/`. Prefer `kali-up` (isolated)
for untrusted images. Carrier/region builds differ — wrong flash can brick the
modem.

---

## Hardware constraints (keep these in mind)

* **16 GiB RAM (X1)** — avoid heavy parallel builds plus a large VM plus Ghidra.
* **P15 Optimus** — Intel iGPU primary + NVIDIA Quadro via `prime-run`; after
  install, reboot so UKI drops `nouveau` and binds `nvidia`.
* **Comet Lake = x86-64-v3** — never target v4 in makepkg / `RUSTFLAGS`.
* **Yoga convertible (X1)** — tablet rotate / sensors via profile + `iio-sensor-proxy`.
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
