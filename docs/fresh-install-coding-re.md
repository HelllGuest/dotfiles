# Fresh install: coding, reverse engineering, malware analysis

Purpose-oriented guide for this repository on the **Lenovo ThinkPad P15 Gen 1**
(type `20SU`; hostname `p15`) and **ThinkPad T14s Gen 3 AMD** (type `21CQ` /
`21CR`). It layers on top of the hardened base install; it does not replace it.

| Document | Role |
|----------|------|
| [hardened-arch-gnome.md](hardened-arch-gnome.md) | Full phase reference (BIOS → UKI → Secure Boot → GNOME) |
| [../README.md](../README.md) | Dotfiles bootstrap, shell, maintenance |
| This file | Machine profile, purpose stacks, isolation rules |

Automation:

* Bare metal Stage A (canonical): [stage-a/](../stage-a/README.md) (`HW_PROFILE=t14s|p15|generic`)
* Thin wrappers (same installer): [`arch-install-t14s.sh`](../scripts/arch-install-t14s.sh) / [`arch-install-p15.sh`](../scripts/arch-install-p15.sh) / [`arch-install.sh`](../scripts/arch-install.sh)
* VM rehearsal: [`arch-install-vmtest.sh`](../provision/scripts/arch-install-vmtest.sh) (`INSTALLER=arch-install-p15.sh` or `arch-install-t14s.sh`)
* After first GNOME login: [`../install.sh`](../install.sh)

**P15 Gen 1:** Stage A with `HW_PROFILE=p15` (canonical repo or
[`arch-install-p15.sh`](../scripts/arch-install-p15.sh) wrapper), then `./install.sh` (detect →
`thinkpad-p15`). Expect `intel_iommu`, `nvidia_drm.modeset`, nouveau blacklist,
`nvidia-open-dkms` + `vulkan-intel` + `LIBVA_DRIVER_NAME=iHD`, charge **70–80**,
optional `ollama-cuda` on `127.0.0.1:11434`.

**T14s Gen 3 AMD:** use the AMD installer, then `./install.sh` (detect →
`thinkpad-t14s`). Expect `amd_iommu` / `amd_pstate`, `mesa` + `vulkan-radeon`,
`fprintd`, and charge thresholds **70–80** via
[`system/scripts/thinkpad-charge-thresholds.sh`](../system/scripts/thinkpad-charge-thresholds.sh).
Health check: [`system/scripts/thinkpad-health.sh`](../system/scripts/thinkpad-health.sh)
covers AMD/NVIDIA/Intel when those modules are present. Details:
[hardened Phase 14](hardened-arch-gnome.md#phase-14--thinkpad-optimization).

---

## Target machines

| Item | P15 Gen 1 (`20SU`) | T14s Gen 3 AMD (`21CQ`/`21CR`) |
|------|--------------------|--------------------------------|
| Profile | hostname `p15` → `profiles/p15.sh` → `thinkpad-p15.sh`, or detect → `thinkpad-p15` | detect → `thinkpad-t14s` |
| CPU | Comet Lake-H, **x86-64-v3** | Ryzen 7 PRO 6850U (Zen 3+), **x86-64-v3** |
| GPU | Intel UHD + NVIDIA Quadro (Optimus / `prime-run`) | Radeon 680M (`amdgpu`, `LIBVA_DRIVER_NAME=radeonsi`) |
| Fingerprint | Synaptics `06cb:00bd` (palm rest) | Goodix `27c6:6594` (power button) |
| Installer | `stage-a/install.sh` `HW_PROFILE=p15` (or thin `arch-install-p15.sh`) | `HW_PROFILE=t14s` (or thin `arch-install-t14s.sh`) |
| OS target | Arch rolling, `linux-lts` primary / `linux-hardened` fallback UKIs | same |
| CPU builds | `GOAMD64=v3`, `RUSTFLAGS=-C target-cpu=x86-64-v3` (see README) | same |

**Fit:** daily coding, static/dynamic RE, and a malware lab in disposable VMs.
Prefer QEMU/libvirt isolation. Never detonate unknown samples on the host.

`packages/pacman.txt` lists Intel and NVIDIA GPU packages used by the P15
profile. `./install.sh` filters them before invoking `pacman -S`: Intel
packages are dropped on T14s Gen 3 AMD (`21CQ`/`21CR`), and NVIDIA packages
are kept only when `has_nvidia_gpu` (PCI vendor `10de`, display class) finds
an NVIDIA card, so VMs and other laptops never build the NVIDIA DKMS module.

---

## Purpose of this workstation

1. **Coding** — zsh/bash, Neovim, VSCodium / Cursor, Flutter + Android Studio,
   Node (fnm), Rust / Python (pipx), rootless Podman (agent sandboxes;
   `packages/pacman.txt`). Go is optional and separate (see Coding stack below).
2. **Reverse engineering** — Ghidra (+ ghidra-cli), REA MCP, RE agent skills,
   plus optional host tools (`packages/re-extra.txt`); host notes in
   [`ai/skills/ghidra-cli-host/`](../ai/skills/ghidra-cli-host/).
3. **Malware analysis** — host stays clean; samples only in disposable VMs.
   Extra triage packages below are optional and not all listed in
   `packages/pacman.txt`.

---

## Fresh install path

If Windows must stay, choose **MANUAL** partitioning in the Stage A installer, reuse
the EFI system partition, and only wipe/recreate the Linux LUKS volume. AUTO
mode wipes the whole disk.

**Reinstall next to Windows (T14s: ESP `nvme0n1p1` shared, Arch on `nvme0n1p5`):**

1. Back up what git does not hold (`~/.ssh`, `~/.gnupg`, secrets env, atuin
   history, `~/.var/app`, unpushed work): `/home` lives on the Arch root and is erased.
2. Save the Windows BitLocker recovery key (new Secure Boot keys usually make
   Windows ask once); turn off Windows Fast Startup.
3. BIOS: Secure Boot → Reset to Setup Mode, Secure Boot off; boot the ISO (F12).
4. Installer → **MANUAL**: ROOT = `nvme0n1p5`, EFI = `nvme0n1p1` with **reuse**
   (default when a FAT32 ESP exists); the review must say `EFI … (reuse)`.
5. The installer keeps `EFI/Microsoft` and the Windows partitions, removes old
   Arch boot files, and writes the firmware entry `Linux Boot Manager` first in
   `BootOrder` (dropping stale ones that point at an older ESP). systemd-boot
   lists Windows Boot Manager.
6. After first boot: Stage A½ below, then `sudo -v && bash scripts/check.sh --all`
   (the Stage A part fails if no firmware entry loads systemd-boot from this ESP).

Rehearsed in a VM with `stage-a/`
`VM_BOOTSTRAP=tests/vm-dual-bootstrap.sh bash tests/vm-run.sh`.

Existing install booting only through the `BOOTX64.EFI` fallback (stale
`Linux Boot Manager` from an earlier ESP; `check.sh --stage-a` reports it):
`efibootmgr` to find the stale `BootNNNN`, `sudo efibootmgr -b NNNN -B`, then
`sudo efibootmgr --create --disk /dev/nvme0n1 --part 1 --label "Linux Boot Manager" --loader '\EFI\systemd\systemd-bootx64.efi'`.

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
bash provision/scripts/arch-install-vmtest.sh
```

On the machine, from the official Arch ISO as root:

```bash
# Canonical (DMI / TUI picks HW_PROFILE):
bash <(curl -fsSL https://raw.githubusercontent.com/HelllGuest/dotfiles/main/stage-a/install.sh)

# Thin wrappers (same installer; pin profile):
bash <(curl -fsSL https://raw.githubusercontent.com/HelllGuest/dotfiles/main/scripts/arch-install-p15.sh)   # HW_PROFILE=p15
bash <(curl -fsSL https://raw.githubusercontent.com/HelllGuest/dotfiles/main/scripts/arch-install-t14s.sh)  # HW_PROFILE=t14s
```

What it builds: LUKS2 (argon2id), Btrfs subvolumes including disk-backed `@tmp`,
UKIs (`linux-lts` / `linux-hardened`), systemd-boot, sbctl, minimal GNOME
(P15 adds Optimus NVIDIA stack + optional ollama-cuda).

Then remove the ISO, reboot, and log into GNOME.

### Stage A½ — Secure Boot (optional; after first good boot, before Stage B)

1. BIOS → clear Secure Boot keys → Setup Mode (required; `enroll-keys` fails if Setup Mode is off).
2. `sudo sbctl verify` — if raw `vmlinuz-*` show unsigned: `sudo sbctl sign -s /boot/vmlinuz-linux{,-lts,-hardened}`.
3. `sudo sbctl enroll-keys -m` (`-m` keeps Microsoft keys for a shared ESP / Windows).
4. BIOS → Secure Boot → Enabled.
5. `sbctl status && sbctl verify`.

Verify Stage A (read-only; runs `stage-a/tests/host-check.sh`, ~80
checks; root-only ones too after `sudo -v`):

```bash
sudo -v && bash ~/dotfiles/scripts/check.sh --stage-a
```

### Stage B — Dotfiles (requires an active GNOME session)

Two paths: modular TUI/GUI (`configure.sh`) or full/selective bootstrap (`./install.sh`; interactive TTY opens a TUI menu, `--gui` uses zenity, `--all` or non-TTY runs the full default install).
Headless / qcow2: see [How to: Stage B VM](../README.md#how-to-stage-b-on-a-stage-a-qcow2)
(or run `bash provision/scripts/vm-stageb-run.sh`).

#### How to: modular TUI (`configure.sh`)

```bash
git clone https://github.com/HelllGuest/dotfiles.git ~/dotfiles
cd ~/dotfiles
bash provision/scripts/p15-dotfiles-preflight.sh   # P15 only; skip on T14s
bash provision/scripts/configure.sh                # dialog → whiptail → plain
# bash provision/scripts/configure.sh --gui        # GNOME zenity GUI
# CONFIGURE_UI=plain bash provision/scripts/configure.sh   # serial / CI / no TTY
```

Module checklist tags, defaults, and fail-fast rules: [README — configure.sh](../README.md#how-to-configuresh-stage-b-tui).

Firewall / malware net: [README — firewalld lab zones](../README.md#how-to-firewalld-lab-zones--lab-malware)
(`bash security/scripts/firewalld-lab-zones.sh`; bridge `zone="lab-malware"`). Ops kits /
usbguard / dnscrypt: [README — ops / privacy kits](../README.md#how-to-ops--privacy-kits).
Desktop look: stock Adwaita via `theme-setup.sh` (EGO Full-pack via
`fetch-gnome-extensions.sh`); [README — install order](../README.md).

#### How to: full or selective bootstrap (`./install.sh`)

```bash
cd ~/dotfiles
bash provision/scripts/p15-dotfiles-preflight.sh   # P15 only
./install.sh                             # interactive TUI menu on TTY (rejects root); --gui for zenity; --all for full unattended
# Selective: ./install.sh --only stow,desktop,check   # or --skip ai,apps (--list shows sections)
# Headless pipe (auto full install): GIT_SETUP_NONINTERACTIVE=1 SKIP_THEME=1 ./install.sh --all
# Explicit Optimus re-run if needed: bash profiles/thinkpad-p15.sh
# Optional REA host MCP (prefer lab-re): bash ai/scripts/install-rea.sh
# Optional Claude CLI: npm install -g @anthropic-ai/claude-code
# Opt-in: bash security/scripts/usbguard-setup.sh ; bash security/scripts/dnscrypt-setup.sh
# Opt-in proxy: systemctl --user enable --now hr-proxy.service && loginctl enable-linger $USER
exec zsh
reboot   # P15: UKI must embed nvidia_drm.modeset=1 + rd.driver.blacklist=nouveau
# after reboot (P15 Optimus):
tr ' ' '\n' </proc/cmdline | grep -E 'nvidia_drm|blacklist=nouveau'
lspci -nnk -d 10de: | grep -A2 'Kernel driver'   # expect: nvidia (not nouveau)
prime-run nvidia-smi -L
```

`git-setup.sh` and the extension fetch stay noninteractive when stdin is not a TTY
(see README [git-setup](../README.md#how-to-git-setupsh-identity--hooks) and
[extensions](../README.md#how-to-gnome-extension-zips-fetch-gnome-extensionssh) howtos).

Step order: [README — what `./install.sh` runs](../README.md#script-execution-order-fresh-machine).

`system/` (sleep, logind, makepkg v3, udev, `virbr0-up.service`, waydroid-nat)
is installed by `system/scripts/system-setup.sh` as root-owned files, not stowed. Kernel
cmdline stays with the installer / machine profile. Details:
[hardened-arch-gnome.md — `system/` files](hardened-arch-gnome.md#kernel-cmdline--system-files-installed-not-stowed).
Firewall: **firewalld** (`drop` / `libvirt` / `lab-malware`) — see
[Verify Firewall](hardened-arch-gnome.md#verify-firewall) and README live health checklist.

**Sleep drift:** repo files pin `mem_sleep_default=s2idle` and
`MemorySleepMode=s2idle`. A live host may still show `s2idle [deep]` (deep
active) if BIOS is **Linux**/S3, `system-setup.sh` never ran, or cmdline was
edited to `deep`. Fix: BIOS → **Windows and Linux**, then
`bash system/scripts/system-setup.sh`, **reboot**, re-check
`/proc/cmdline` + `/sys/power/mem_sleep` (want `[s2idle] deep`).
See [Verify sleep](hardened-arch-gnome.md#verify-sleep-s2idle).

---

## Coding stack

### From `./install.sh` / package lists

| Layer | What |
|-------|------|
| Shell | zsh (zinit), bash, starship, atuin, fzf, zoxide, direnv |
| Editors | Neovim (Lazy), VSCodium (`vscodium-bin`), Cursor / Antigravity (AUR) |
| Languages | fnm Node 22, rust, `python-pipx`, `flutter-bin`, jdk-openjdk (+ JDK 17 for Android) |
| Mobile | Flatpak Android Studio; `ANDROID_HOME` in `.shell-exports`; alias `as` |
| AI stack | `sync-agent-skills` (hub → Claude/Cursor/OpenCode/Kimi/Gemini/Antigravity/Kiro/Codex), Headroom + `hr-*` / optional `hr-proxy.service`, RTK (`install-rtk.sh`), OpenCode + Kimi (+ opt-in Gemini/Codex via `install-coding-agents.sh`), Caveman + Ponytail, curated official + RE skills, Continue FIM→ollama (P15), Obscura, `ai-stack-setup.sh` |
| Labs | `lab-triage` / `lab-re` / `lab-android` / `lab-web` / `lab-detonate` / `lab-mcp` via `firewalld-lab-zones.sh` then `labs-setup.sh` (`cd` into a project for `/work`; app-grid launches default to `/srv/lab/out`, see [README](../README.md)) |
| Local builds | x86-64-v3 makepkg drop-in; `bash system/scripts/rebuild-v3.sh` after big upgrades |

### Containers (Podman — in `pacman.txt`)

After Stage B / `./install.sh`, finish Podman storage + socket (Phase 17):

```bash
mkdir -p ~/.local/share/containers/storage && chattr +C ~/.local/share/containers/storage
systemctl --user enable --now podman.socket
mkdir -p /tmp/agent-smoke && bash ~/dotfiles/ai/scripts/agent-run.sh /tmp/agent-smoke alpine:3.20 echo ok   # optional smoke
```

`DOCKER_HOST` prefers Podman when `podman.socket` is up. If `docker` package is
also installed, disable the system daemon so it does not fight Podman:

```bash
sudo systemctl disable --now docker.service docker.socket
sudo ip link delete docker0 2>/dev/null || true   # leftover bridge
```

Real Docker daemon for one shell: `FORCE_DOCKER=1`.

### Not in `packages/pacman.txt` (install separately)

Go is optional and not pulled by `./install.sh`:

```bash
sudo pacman -S --needed go
```

Sanity checks:

```bash
~/dotfiles/scripts/check.sh         # post-install: Stage A follow-ups + Stage B
~/dotfiles/scripts/check.sh --all   # plus the Stage A host-check
fnm current
podman info   # Rootless: true
go version    # if installed
```

---

## Reverse engineering stack

### Core

`./install.sh` installs `ghidra`, `jdk-openjdk`, `jdk17-openjdk`, and `rust`
(`packages/pacman.txt`) and runs `ai/scripts/install-ghidra-cli.sh`. Check:

```bash
ghidra doctor
ghidra-gui   # GUI; cargo `ghidra` on PATH shadows /usr/bin/ghidra
```

### Official extras (optional; none are in `pacman.txt`)

Manifest: [`packages/re-extra.txt`](../packages/re-extra.txt). Installer:

```bash
bash provision/scripts/install-re-extras.sh
# Installs packages/re-extra.txt (RE tools: jdk11-openjdk, jadx, gdb, binwalk,
# android-tools, rizin, rz-cutter, rz-ghidra, hexyl, yara, strace, ltrace,
# smali, radare2; firmware tools: squashfs-tools, mtd-utils, flashrom,
# uboot-tools, lzop, qemu-user-static, qemu-user-static-binfmt,
# arm-none-eabi-binutils), plus pipx unblob, clamav-freshclam (if clamav is
# installed), and ThinkPad charge thresholds.
```

QEMU/libvirt: see [Host virtualization](#host-virtualization) / [Disposable Kali](#disposable-kali).

### AUR extras (optional; use paru/yay after `install-aur.sh`)

```bash
paru -S --needed imhex-bin android-apktool-bin
```

### AI reverse-engineering (MCP + skills)

Prefer containerized REA inside `lab-re` (`rea-agents@6.10.1` + JDK21/Ghidra/jadx/rizin). Host `install-rea.sh` is optional (needs JDK≥21). `./install.sh` still runs RE skills when npx is available; it does **not** auto-run host REA.

| Layer | What | Install |
|-------|------|---------|
| **REA (lab-re)** | MCP + CLI inside Podman image | `lab-re` / `bash labs/scripts/labs-setup.sh` |
| **REA (host, optional)** | MCP on bare metal when JDK≥21 + tools exist | `bash ai/scripts/install-rea.sh` |
| **leanrea** | Small skill: shell-tool RE, no MCP (cheap triage) | `bash ai/scripts/install-re-skills.sh` |
| **reverse-engineering** | Playbooks + triage scripts (EncidXVII) | same |
| **android-reverse-engineering** | APK/XAPK API recovery (jadx) | same |
| **ghidra-iterative-re** | Safe Ghidra apply→verify loop | same |
| **firmware-extraction** / **firmware-static-analysis** / **firmware-emulation** / **ghidra-re** / **firmware-security-reports** | Firmware/IoT unpack → analyze → emulate (OrbitCurve) | same |
| **ghidra-cli-host** | This machine’s Ghidra CLI footguns | repo `ai/skills/` + sync |

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
lab-re --check && lab-re          # preferred REA + Ghidra/jadx
# optional host MCP: bash ai/scripts/install-rea.sh
bash ai/scripts/install-re-skills.sh
bash ~/dotfiles/scripts/check.sh   # ○/✓ for leanrea, reverse-engineering, …
```

### Ghidra footguns on this machine

From [`ai/skills/ghidra-cli-host/SKILL.md`](../ai/skills/ghidra-cli-host/SKILL.md):

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
and undefines the domain; base stays clean. Script: `labs/scripts/kali-disposable.sh`.
Full shell alias table (`kali`, `kali-up`, `kali-up-nat`, `kali-up-lan`, `kali-lan`, `kali-lan-check`, `kali-wipe`, `kali-stop`, `kali-st`): [desktop/gnome/keybindings.md](../desktop/gnome/keybindings.md#disposable-kali).

```bash
bash labs/scripts/kali-disposable.sh setup    # once: libvirt pkgs + download base + virbr0/libvirt zone
# re-login / newgrp libvirt
kali-up                                  # isolated (samples)
kali-up-nat                              # NAT for apt/cloud-init
kali-up-lan                              # NAT + physical RJ45 (needs cable on host NIC)
# or: kali-lan                           # hot-attach LAN to already-running guest
kali-st
# NAT/LAN: script prints Guest IP + password (saved under VM_DIR/kali-session.password)
kali-wipe                                # back to clean base
```

**Physical LAN:** `--lan` / `attach-lan` sets `nat+lan`: NAT eth0 plus host
`KALI_LAN_IFACE` (default `enp0s31f6`, else first ethernet) as guest eth1 via
macvtap bridge mode. Dual defaults break LAN: host RJ45 must have **no IP**
(wifi keeps default — `labs/scripts/kali-lan-host-prep.sh` / `pkexec kali-lan-host-prep`);
guest eth1 gets DHCP on the LAN **without** gateway/DNS/routes (NAT eth0 is
the only default). Verify with `kali lan-check` (`KALI_LAN_PROBE` overrides the
default `192.168.8.1` gateway ping target). Public DNS on eth0. Cable
required for eth1; NAT works without one.

Base: `/var/lib/libvirt/images/kali-disposable/kali-base.qcow2` (system qemu
cannot read `$HOME`). Each `start` rebuilds `kali-session.qcow2` unless
`KEEP_OVERLAY=1`. No host shares. Defaults: **isolated** net, 4096 MiB RAM,
4 vCPU (`KALI_RAM_MB` / `KALI_VCPUS` / `KALI_NET` / `KALI_VM_DIR` override).

The base image is the official Kali cloud image, pinned by `KALI_IMAGE_URL`
(per-release `cloud-images/kali-<ver>/` folder, not `current/`, which drops
the file at the next release) and checked against `KALI_IMAGE_SHA256` before
install. `--lan` needs a wired NIC (`KALI_LAN_IFACE`); Wi-Fi cannot carry macvtap.

**NAT / firewalld:** `setup` and `start --nat` bind `virbr0` to the stock
`libvirt` zone (forward + masquerade for guest subnet `192.168.122.0/24`) and
bring the bridge up. Prefer `bash security/scripts/firewalld-lab-zones.sh` if zones are
missing ([howto](../README.md#how-to-firewalld-lab-zones--lab-malware)). Boot unit
`virbr0-up.service` (from `system/`, also installed by `setup`) starts the
libvirt `default` network then `ip link set virbr0 up` so the bridge exists
after reboot. Cloud-init NoCloud seed sets hostname `kali-disposable`, enables
password SSH, and uses a fresh `instance-id` each overlay. Isolated login
defaults to `kali`/`kali`. NAT/LAN generates a random password (or
`KALI_PASSWORD`), prints it, and stores it in `kali-session.password` under
`KALI_VM_DIR`.

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

* **P15 Optimus** — Intel iGPU primary + NVIDIA Quadro via `prime-run`; after
  install, reboot so UKI drops `nouveau` and binds `nvidia`.
* **T14s AMD** — no discrete GPU; keep `LIBVA_DRIVER_NAME=radeonsi`.
* **x86-64-v3** — Comet Lake (P15) and Zen 3+ Rembrandt (T14s) both stay at v3;
  never target v4 in makepkg / `RUSTFLAGS`.
* **zram** — helps under memory pressure; still plan workloads.

---

## One-page checklist

Same order as Stages 0 → A → A½ → B (matches README):

```text
BIOS (SB off, VT-x/d on; Sleep = Windows and Linux for s2idle)
  → Arch ISO → stage-a/install.sh (or thin arch-install-*.sh wrappers; AUTO wipe, or MANUAL + reuse EFI)
  → reboot → GNOME login
  → optional: sbctl enroll-keys -m → enable SB in BIOS → sbctl verify
  → clone dotfiles → ./install.sh (installs system/ via system-setup.sh) → exec zsh
  → thinkpad-health.sh → reboot
  → coding extras if needed: go (Podman is already primary)
  → RE: ghidra doctor + ghidra-gui; optional jadx / rz-cutter / …
  → malware: libvirtd + isolated VM only (never host detonation)
```

---

## Related maintenance

General tasks: [README — Maintenance](../README.md#-maintenance). On this machine also:

| Task | Command |
|------|---------|
| ThinkPad health | `bash system/scripts/thinkpad-health.sh` |
| Secure Boot | `sbctl status && sbctl verify` |
