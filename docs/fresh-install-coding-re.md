# Fresh Install: Coding, Reverse Engineering & Malware Analysis

Purpose-stack guide for **ThinkPad P15 Gen 1** (`20SU`, hostname `p15`) and **ThinkPad T14s Gen 3 AMD** (`21CQ`/`21CR`). Layers on top of the base install in [stage-a/README.md](../stage-a/README.md) and [README.md](../README.md).

## Target Machines

| Item | P15 Gen 1 (`20SU`) | T14s Gen 3 AMD (`21CQ`/`21CR`) |
|------|--------------------|--------------------------------|
| Profile | `profiles/p15.sh` → `thinkpad-p15.sh` | `detect-profile.sh` → `thinkpad-t14s.sh` |
| CPU | Comet Lake-H (**x86-64-v3**) | Ryzen 7 PRO 6850U (**x86-64-v3**) |
| GPU | Intel UHD + NVIDIA Quadro (`prime-run`, `LIBVA_DRIVER_NAME=iHD`) | Radeon 680M (`amdgpu`, `LIBVA_DRIVER_NAME=radeonsi`) |
| Fingerprint | Synaptics `06cb:00bd` | Goodix `27c6:6594` |
| Stage A | `HW_PROFILE=p15` (`scripts/arch-install-p15.sh`) | `HW_PROFILE=t14s` (`scripts/arch-install-t14s.sh`) |

* Both profiles enforce **70–80** battery charge thresholds (`system/scripts/thinkpad-charge-thresholds.sh`) and **s2idle** sleep (BIOS Sleep State = **Windows and Linux**). Details: [hardened Phase 14](hardened-arch-gnome.md#phase-14--thinkpad-optimization).
* `install.sh` skips Intel GPU packages on T14s and installs NVIDIA packages only when an NVIDIA display device is detected on PCI.

## Install Flow

1. **BIOS (`F1`):** Secure Boot **Disabled** (enroll later), Sleep **Windows and Linux** (`s2idle`), Virtualization / VT-d / SVM **Enabled**.
2. **Stage A (Arch ISO, UEFI, root):** run `stage-a/install.sh` (or `scripts/arch-install-{p15,t14s}.sh`) — full instructions and dual-boot MANUAL ESP reuse in [stage-a/README.md](../stage-a/README.md). Optional VM rehearsal: `bash provision/scripts/arch-install-vmtest.sh`.
3. **Stage A½ (optional Secure Boot):** clear keys to Setup Mode in BIOS, run `sudo sbctl verify && sudo sbctl enroll-keys -m`, re-enable Secure Boot. Verify Stage A: `sudo -v && bash ~/dotfiles/scripts/check.sh --stage-a`.
4. **Stage B (GNOME session terminal):** clone repo, run `./install.sh` (or `CONFIGURE=1 ./install.sh --all`), then optional `bash provision/scripts/configure.sh`. Canonical order, flags, and headless VM notes: [README — Installation & Setup](../README.md#script-execution-order-fresh-machine).
5. **P15 post-reboot check:** verify UKI loaded NVIDIA (`lspci -nnk -d 10de: | grep -A2 'Kernel driver'` → `nvidia`; `prime-run nvidia-smi -L`).

## Coding Stack

Installed by `./install.sh`:

| Layer | Tools |
|-------|-------|
| Shell | Zsh (`zinit`), Bash, Starship, Atuin, fzf, zoxide, direnv |
| Editors | Neovim (Lazy.nvim), VSCodium, Cursor, Antigravity (AUR) |
| Languages | `fnm` Node 22, Rust, `python-pipx`, `flutter-bin`, JDK + JDK 17 (Android); Go optional (`sudo pacman -S --needed go`) |
| Mobile | Flatpak Android Studio (`as`), `ANDROID_HOME` in `.shell-exports` |
| AI stack | `sync-agent-skills`, Headroom (`hr-*`), optional RTK (`install-rtk.sh`), OpenCode, Kimi, Caveman, Ponytail, Obscura, Continue FIM → Ollama (P15) |
| Containers | Rootless Podman primary (`DOCKER_HOST` wired automatically; setup & Docker escape hatch in [README — Containers](../README.md#containers-podman-first)) |
| Labs | `lab-triage`, `lab-re`, `lab-android`, `lab-web`, `lab-detonate`, `lab-mcp` (`firewalld-lab-zones.sh` then `labs-setup.sh`) |

Sanity check: `bash ~/dotfiles/scripts/check.sh --all`, `fnm current`, `podman info` (`Rootless: true`).

## Reverse Engineering Stack

* **Core (`./install.sh`):** `ghidra`, `jdk-openjdk`, `jdk17-openjdk`, `rust`, and `ai/scripts/install-ghidra-cli.sh`.
* **Official extras (opt-in):** `bash provision/scripts/install-re-extras.sh` installs [`packages/re-extra.txt`](../packages/re-extra.txt) (`jadx`, `gdb`, `binwalk`, `rizin`, `rz-cutter`, `rz-ghidra`, `yara`, `strace`, `ltrace`, `radare2`, `smali`, `squashfs-tools`, `mtd-utils`, `flashrom`, `uboot-tools`, `qemu-user-static`, `arm-none-eabi-binutils`), `pipx` `unblob`, and charge thresholds.
* **AUR extras (optional):** `paru -S --needed imhex-bin android-apktool-bin`.

### AI Reverse Engineering (MCP & Skills)

Prefer containerized REA inside `lab-re` (`rea-agents@6.10.1` + JDK 21 + Ghidra + jadx + rizin). Host `ai/scripts/install-rea.sh` is optional (needs JDK ≥ 21). RE skills (`packages/agent-skills-re.txt`: `leanrea`, `reverse-engineering`, `android-reverse-engineering`, `ghidra-iterative-re`, `firmware-*`, `ghidra-cli-host`) install via `bash ai/scripts/install-re-skills.sh`.

```bash
lab-re --check && lab-re
bash ai/scripts/install-re-skills.sh
```

### Ghidra Host Notes (`ai/skills/ghidra-cli-host/SKILL.md`)

* CLI lives at `~/.cargo/bin/ghidra` (shadows `/usr/bin/ghidra`); launch GUI with `ghidra-gui` (`/opt/ghidra/ghidraRun`).
* Prefer `--json` and check `"status":"success"` (exit codes are unreliable).
* Uses `GHIDRA_CLI_JAVA_HOME` (≥ 21) so Android's JDK 17 does not conflict. Projects live in `~/ghidra-cli-projects`.
* Smoke test: `ghidra doctor && ghidra import /usr/bin/true --project smoke --no-analyze && ghidra project delete smoke`.

## Malware Analysis

### Isolation Rules

* Never run unknown samples on the host.
* Use disposable UEFI guests with clean snapshots before every run; never expose host directories read-write unless intentional.
* Keep unknown samples on an isolated virtual network (no bridged LAN).
* On 16 GiB RAM: run one analysis VM at a time (2–4 GiB guest RAM, 2 vCPUs).

Optional static/inert host triage tools: `sudo pacman -S --needed clamav upx wireshark-qt tcpdump mitmproxy nmap`.

### Host Virtualization

```bash
sudo pacman -S --needed virt-manager qemu-full libvirt edk2-ovmf
sudo systemctl enable --now libvirtd
sudo usermod -aG libvirt "$USER"   # log out/in after
```

### Disposable Kali

Immutable qcow2 base (`/var/lib/libvirt/images/kali-disposable/kali-base.qcow2`, SHA-256 verified) plus ephemeral session overlay via `labs/scripts/kali-disposable.sh`. Alias reference: [desktop/gnome/keybindings.md](../desktop/gnome/keybindings.md#disposable-kali).

```bash
bash labs/scripts/kali-disposable.sh setup   # once: libvirt pkgs, verified base image, virbr0/libvirt zone
kali-up                                      # isolated session (default; login kali/kali)
kali-up-nat                                  # NAT for apt/cloud-init (prints IP + generated password)
kali-up-lan                                  # NAT + physical RJ45 (macvtap; wired NIC required)
kali-lan-check                               # verify host RJ45 has no IP and guest eth1 reaches LAN
kali-wipe                                    # destroy overlay; base stays untouched
```

* **Physical LAN (`--lan` / `kali-lan`):** attaches `KALI_LAN_IFACE` (default `enp0s31f6`, else first wired NIC; Wi-Fi cannot carry macvtap) as guest `eth1` without gateway/DNS so NAT `eth0` stays the sole default route. `labs/scripts/kali-lan-host-prep.sh` clears any host IP on that RJ45 port. Override probe target with `KALI_LAN_PROBE` (default `192.168.8.1`).
* **Overrides:** `KALI_RAM_MB`, `KALI_VCPUS`, `KALI_NET`, `KALI_VM_DIR`, `KEEP_OVERLAY=1`, `KALI_PASSWORD`.
* **Firewalld:** `virbr0` binds to `libvirt` (`firewalld-lab-zones.sh`; [README — firewalld](../README.md#how-to-firewalld-lab-zones--lab-malware)); `virbr0-up.service` brings it up at boot.

### CPE / Home Gateway Without a Firmware File (e.g. Brovi H155-381)

**Brovi H155-381** (5G CPE, admin UI typically `http://192.168.8.1`) ships OTA updates rather than public `.bin` downloads. Without an image:

1. Record software version and hardware revision from the admin UI.
2. If an update check fetches a package, capture it from the browser Network tab (inspect offline; never flash unknown builds).
3. Export a config backup and inspect it offline for hardcoded/leaked secrets; disable WAN admin and rotate passwords.
4. From LAN only, scan open services with `nmap -sV <router-ip>`.
5. Once you have a `.bin`/`.zip`, unpack inside an isolated `kali-up` guest with `unblob -e out file` (or `binwalk -e`) and run `/leanrea` + firmware skills on `out/`.

## Hardware Constraints

* **P15 Optimus:** reboot after install so UKI drops `nouveau` and binds `nvidia`; launch GPU tasks with `prime-run`.
* **T14s AMD:** keep `LIBVA_DRIVER_NAME=radeonsi`.
* **x86-64-v3:** keep makepkg and `RUSTFLAGS` at v3 (never v4).

## One-Page Checklist

```text
BIOS (SB off, VT-x/d on, Sleep = Windows and Linux)
  → Arch ISO → stage-a/install.sh (AUTO wipe or MANUAL + reuse EFI) → reboot → GNOME login
  → optional Secure Boot: sbctl enroll-keys -m → enable SB in BIOS → sbctl verify
  → clone dotfiles → ./install.sh → optional configure.sh → exec zsh
  → bash system/scripts/thinkpad-health.sh → reboot
  → coding: optional go (Podman is primary)
  → RE: lab-re --check / ghidra doctor / optional install-re-extras.sh
  → malware: libvirtd + isolated kali-up / lab-detonate only
```

Maintenance: [README — Maintenance](../README.md#-maintenance), plus `bash system/scripts/thinkpad-health.sh` and `sbctl status && sbctl verify`.
