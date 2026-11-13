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

* Bare metal (P15 / generic Intel): [`scripts/arch-install.sh`](../scripts/arch-install.sh)
* Bare metal (T14s Gen 3 AMD, 21CQ/21CR): [`scripts/arch-install-t14s.sh`](../scripts/arch-install-t14s.sh)
* VM rehearsal: [`scripts/arch-install-vmtest.sh`](../scripts/arch-install-vmtest.sh) (`INSTALLER=arch-install-t14s.sh` for the AMD script)
* After first GNOME login: [`../install.sh`](../install.sh)

**T14s Gen 3 AMD:** use the AMD installer, then `./install.sh` (detect →
`thinkpad-t14s`). Expect `amd_iommu` / `amd_pstate`, `mesa` + `vulkan-radeon`,
`fprintd`, and charge thresholds **70–80** via
[`scripts/thinkpad-charge-thresholds.sh`](../scripts/thinkpad-charge-thresholds.sh).
Health check: [`scripts/thinkpad-health.sh`](../scripts/thinkpad-health.sh)
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
| Installer | `arch-install.sh` | `arch-install-t14s.sh` |
| OS target | Arch rolling, `linux-lts` primary / `linux-hardened` fallback UKIs | same |
| CPU builds | `GOAMD64=v3`, `RUSTFLAGS=-C target-cpu=x86-64-v3` (see README) | same |

**Fit:** daily coding, static/dynamic RE, and a malware lab in disposable VMs.
Prefer QEMU/libvirt isolation. Never detonate unknown samples on the host.

`packages/pacman.txt` lists Intel and NVIDIA GPU packages used by the P15
profile. On T14s Gen 3 AMD (`21CQ`/`21CR`), `./install.sh` automatically
filters those packages out before invoking `pacman -S`.

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

Two paths: modular TUI (`configure.sh`) or full bootstrap (`./install.sh`).

#### How to: modular TUI (`configure.sh`)

```bash
git clone https://github.com/HelllGuest/dotfiles.git ~/dotfiles
cd ~/dotfiles
bash scripts/p15-dotfiles-preflight.sh   # P15 only; skip on T14s
bash scripts/configure.sh                # dialog → whiptail → plain
```

Checklist tags (fail-fast on module error):

| Tag | Default | Effect |
|-----|---------|--------|
| `MIGRATE_FIREWALLD` | on | drop + `libvirt`/`virbr0` + `lab-malware`/`virbr-malware` |
| `APPLY_PROFILE` | off | re-run machine profile |
| `SETUP_OLLAMA` | on **only on P15** | `ollama-setup.sh` → `127.0.0.1:11434` |
| `SETUP_LABS` | off | build/pull lab images; shell wrappers |
| `SETUP_DETONATE` | off | `lab-detonate.sh setup` |
| `SETUP_AI` | off | Headroom/`hr-*`, Ponytail, Continue FIM (not Caveman) |
| `SETUP_RICE` | off | Gruvbox + `show-in-lock-screen false` |

Full howto table: [README — configure.sh](../README.md#how-to-configuresh-stage-b-tui).

#### How to: full bootstrap (`./install.sh`)

```bash
cd ~/dotfiles
bash scripts/p15-dotfiles-preflight.sh   # P15 only
./install.sh                             # Caveman + Ponytail + packages + stow + …
# Explicit Optimus re-run if needed: bash profiles/thinkpad-p15.sh
# Optional REA host MCP (prefer lab-re): bash scripts/install-rea.sh
exec zsh
reboot   # P15: UKI must embed nvidia_drm.modeset=1 + rd.driver.blacklist=nouveau
# after reboot (P15 Optimus):
tr ' ' '\n' </proc/cmdline | grep -E 'nvidia_drm|blacklist=nouveau'
lspci -nnk -d 10de: | grep -A2 'Kernel driver'   # expect: nvidia (not nouveau)
prime-run nvidia-smi -L
```

Step order: [README — what `./install.sh` runs](../README.md#script-execution-order-fresh-machine).

`stow/system/` (sleep, logind, makepkg v3, udev, `virbr0-up.service`, waydroid-nat)
is installed by `scripts/system-setup.sh` as root-owned files, not stowed. Kernel
cmdline stays with the installer / machine profile. Details:
[hardened-arch-gnome.md — `system/` files](hardened-arch-gnome.md#kernel-cmdline--system-files-installed-not-stowed).
Firewall: **firewalld** (`drop` / `libvirt` / `lab-malware`) — see
[Verify Firewall](hardened-arch-gnome.md#verify-firewall) and README live health checklist.

**Sleep drift:** repo files pin `mem_sleep_default=s2idle` and
`MemorySleepMode=s2idle`. A live host may still show `s2idle [deep]` (deep
active) if BIOS is **Linux**/S3, `system-setup.sh` never ran, or cmdline was
edited to `deep`. Fix: BIOS → **Windows and Linux**, then
`bash scripts/system-setup.sh`, **reboot**, re-check
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
| AI stack | Headroom + `hr-*`, OpenCode + Kimi (`install-coding-agents.sh`), Caveman + Ponytail (complementary; `./install.sh` both, SETUP_AI = Ponytail), Continue FIM→ollama (P15), Obscura, `ai-stack-setup.sh` / `sync-agent-skills.sh` |
| Labs | `lab-triage` / `lab-re` / `lab-android` / `lab-web` / `lab-detonate` / `lab-mcp` via `labs-setup.sh` |
| Local builds | x86-64-v3 makepkg drop-in; `bash scripts/rebuild-v3.sh` after big upgrades |

### Containers (Podman — in `pacman.txt`)

After Stage B / `./install.sh`, finish Podman storage + socket (Phase 17):

```bash
mkdir -p ~/.local/share/containers/storage && chattr +C ~/.local/share/containers/storage
systemctl --user enable --now podman.socket
bash ~/dotfiles/scripts/agent-run.sh /tmp alpine:3.20 echo ok   # optional smoke
```

`DOCKER_HOST` prefers Podman when `podman.socket` is up. If `docker` package is
also installed, disable the system daemon so it does not fight Podman:

```bash
sudo systemctl disable --now docker.service docker.socket
```

Real Docker daemon for one shell: `FORCE_DOCKER=1`.

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

Prefer containerized REA inside `lab-re` (`rea-agents@6.9.0` + JDK21/Ghidra/jadx/rizin). Host `install-rea.sh` is optional (needs JDK≥21). `./install.sh` still runs RE skills when npx is available; it does **not** auto-run host REA.

| Layer | What | Install |
|-------|------|---------|
| **REA (lab-re)** | MCP + CLI inside Podman image | `lab-re` / `bash scripts/labs-setup.sh` |
| **REA (host, optional)** | MCP on bare metal when JDK≥21 + tools exist | `bash scripts/install-rea.sh` |
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
lab-re --check && lab-re          # preferred REA + Ghidra/jadx
# optional host MCP: bash scripts/install-rea.sh
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
# NAT/LAN: script prints Guest IP + password (saved under VM_DIR/kali-session.password)
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
