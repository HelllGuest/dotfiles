# 🌌 Arch Linux + GNOME Dotfiles

A clean, modular, and programmable dotfiles ecosystem optimized for **Arch Linux**, **GNOME Shell 51**, and **ThinkPad** hardware. This setup focuses on visual cohesion, privacy hardening, and a frictionless developer workflow.

---

## 🚀 Key Features

- **Privacy Hardened:** Telemetry, usage reporting, and "phoning home" are disabled system-wide (GNOME, VS Code, .NET, etc.).
- **ThinkPad Optimized:** Hostname or hardware-detected profiles (`thinkpad-p15.sh`, `thinkpad-t14s.sh`, or `laptop.sh`) with power-profiles-daemon (or tuned + `tuned-ppd` on hosts from `t14s-arch-install`), UKIs signed for Secure Boot (sbctl), and a tracked **s2idle** sleep pin (`mem_sleep_default=s2idle`; pair BIOS Sleep State with **Windows and Linux**, not **Linux**/S3 — see `docs/hardened-arch-gnome.md`). Firewall: **firewalld** (`nftables`, default `drop`). Stage B modules: `bash scripts/configure.sh` (firewalld, labs, AI stack, Gruvbox rice). Lab wrappers: `lab-triage` / `lab-re` / `lab-android` / `lab-web` / `lab-detonate` / `lab-mcp` (see `scripts/labs-setup.sh`, `lab-detonate.sh`, `lab-mcp.sh`). Thermal is firmware-managed. Charge window **70–80** via `scripts/thinkpad-charge-thresholds.sh`.
- **Elite-Tier Terminal:** Kitty & Ghostty with shared Zsh/Bash configs, real-time autocomplete, [Gruvbox Rainbow](https://starship.rs/presets/gruvbox-rainbow) Starship prompt.
- **Neovim (Lazy.nvim):** A modular Lua configuration.

---

## 🐚 Shell Configuration

Zsh is the primary shell. Bash is fully supported for scripts and fallback sessions.

### Shared files (`stow/zsh/`)

| File | Purpose |
|------|---------|
| `.shell-exports` | Environment variables (editor, pager, Android SDK, telemetry opt-outs, container CLI socket) |
| `.shell-aliases` | Shared aliases (`v`, `as`, `ff`, etc.) |
| `.shell-functions` | Shared functions (`mkcd`, `backup`); zsh-only OSC 7 CWD hook |
| `.shell-git` | Git helpers and forgit settings |

Both `~/.zshrc` and `~/.bashrc` source these files.

### Zsh stack (`.zsh-plugins` via **zinit**)

| Tool | Role |
|------|------|
| **zinit** (turbo) | Plugin manager, deferred load |
| **fast-syntax-highlighting** | Syntax colors (Wayland-safe) |
| **zsh-autosuggestions** | Inline history suggestions |
| **zsh-completions** | Extended completion database |
| **fzf-tab** | fzf completion picker with previews |
| **autopair** | Auto-close brackets/quotes |
| **you-should-use** | Alias usage hints |
| **forgit** | fzf git UI |

**History:** **atuin** is initialized with `--disable-up-arrow` (sqlite). `↑`/`↓` stay on prefix history-search. **`Ctrl+R`:** Zsh loads atuin then `fzf --zsh`, so **fzf** owns `^R`; Bash loads `fzf --bash` then atuin, so **atuin** owns `^R`. Config: `stow/atuin/.config/atuin/config.toml`.

### Bash stack (`.bashrc` + `.inputrc`)

- **ble.sh** (optional AUR) — syntax highlighting and autosuggestions for bash
- **bash-completion** for commands (Tab; loaded at shell startup)
- **Prefix history search** on `↑` / `↓` and **menu-complete** on Tab via `.inputrc`
- Same **fzf**, **zoxide**, **atuin**, **direnv**, **starship**, and shared `.shell-*` files as Zsh
- **fzf** preview binds: `Ctrl+F` / `Ctrl+B` page preview; no global `Ctrl+Y` copy bind (fzf 0.72 lacks `copy-selection` — pass `--bind` per invocation if needed)

### Containers (Podman-first; Docker optional)

**Default for AI agents / sandboxes:** rootless **Podman** (`packages/pacman.txt`). After install:

```bash
mkdir -p ~/.local/share/containers/storage && chattr +C ~/.local/share/containers/storage
systemctl --user enable --now podman.socket
# optional: loginctl enable-linger "$USER"  # keeps socket after logout
```

`.shell-exports` sets `DOCKER_HOST` to the Podman socket when it exists, so `docker` talks to Podman. That is intentional. If the `docker` package is installed, disable the system daemon so Podman stays primary:

```bash
sudo systemctl disable --now docker.service docker.socket
systemctl --user enable --now podman.socket
```

Escape hatch for a real Docker daemon: `FORCE_DOCKER=1` (with `/var/run/docker.sock`), or stop `podman.socket`.

Hardened one-shot runs: `scripts/agent-run.sh <project-dir> <image> [cmd…]` (read-only, cap-drop ALL, network none by default; never mounts runtime sockets). User defaults: `stow/containers` → `~/.config/containers/containers.conf`. Full notes: [Phase 17](docs/hardened-arch-gnome.md#phase-17--rootless-podman).

### Node.js (fnm)

**fnm** is in `packages/pacman.txt` and hooks in `.zsh-plugins` / `.bashrc` with `--use-on-cd`. When you open a terminal or `cd` into a project, fnm reads `.nvmrc`, `.node-version`, or `package.json` `engines.node` and switches Node versions.

If you see:

```text
Can't find an installed Node version matching >=22.12.0.
Do you want to install it? answer [y/N]:
```

the project pins a Node version you have not installed via fnm yet. Install once:

```bash
fnm install 22          # or: fnm install   (inside the project)
fnm default 22          # optional global default
```

To disable per-directory auto-switching (no prompt on shell start), remove `--use-on-cd` from `stow/zsh/.zsh-plugins` and `stow/bash/.bashrc`.

**uv** shell completions load from `.zsh-plugins` when installed.

### Headroom (Claude / Cursor token compression)

**Headroom** compresses tool output and context before it hits the model (savings vary; see [upstream](https://github.com/headroomlabs-ai/headroom)). Installed user-local via **pipx** (`python-pipx` in `packages/pacman.txt`). `scripts/install-headroom.sh` installs or upgrades `headroom-ai[all]`.

```bash
bash scripts/headroom-setup.sh    # install/upgrade + MCP registration
```

After setup, prefer a **systemd user** persistent proxy (survives logout when linger is on):

```bash
headroom install apply --preset persistent-service --runtime python --scope user \
  --providers auto --profile default --port 8787 --backend anthropic --mode token --no-telemetry
loginctl enable-linger "$USER"   # once, so it survives logout
systemctl --user status headroom-default.service   # enabled + active
headroom doctor
```

| Command | What it does |
|---------|----------------|
| `hr-claude` | `headroom wrap claude` — proxy + launch Claude Code |
| `hr-cursor` | Start proxy; paste printed Base URL into Cursor → Settings → Models |
| `hr-proxy` | One-shot proxy on port `8787` (`HEADROOM_PORT` to override) |

**Routing & MCP:** `scripts/headroom-setup.sh` sets `ANTHROPIC_BASE_URL` and `ENABLE_TOOL_SEARCH` in `~/.claude/settings.json` and registers the `headroom` MCP server across Claude Code, Cursor (`~/.cursor/mcp.json`), OpenCode (`~/.config/opencode/opencode.json`), Kimi Code (`~/.kimi-code/mcp.json`), Gemini CLI (`~/.gemini/settings.json`), and Antigravity (`~/.gemini/config/mcp_config.json`). Interactive shells also get `ANTHROPIC_BASE_URL` / `OPENAI_BASE_URL` from stowed `~/.zshrc` / `~/.bashrc` (and `~/.profile`). If `headroom doctor` warns that those vars are unset, the *current* process never sourced the rc file (common in IDE/agent shells): `source ~/.zshrc`, open a new terminal, or `export ANTHROPIC_BASE_URL=http://127.0.0.1:8787` / `OPENAI_BASE_URL=http://127.0.0.1:8787/v1`.

**Cursor model proxy:** paste the Override OpenAI Base URL printed by `hr-cursor` into Cursor → Settings → Models (the IDE does not read shell env for model routing).

**RTK:** Headroom 0.34+ no longer bundles [RTK](https://github.com/rtk-ai/rtk). Keep the binary under e.g. `~/.local/share/rtk/rtk` (symlink from `~/.local/bin/rtk`). Do **not** put it in `~/.headroom/bin`; `headroom wrap` / some `init` paths purge managed copies there. Telemetry stays off (`HEADROOM_TELEMETRY=off`, `--no-telemetry`).

Antigravity CLI (`agy`) and Kiro: point at `http://127.0.0.1:8787/v1` only if that tool accepts a custom OpenAI-compatible base URL.

### x86-64-v3 local builds

This ThinkPad (Comet Lake) is **x86-64-v3**, not v4. Official extra/ packages stay generic `x86-64`. For local/AUR builds:

* `stow/system/etc/makepkg.conf.d/zz-x86-64-v3.conf` (via `scripts/system-setup.sh`)
* `stow/pacman/.config/pacman/makepkg.conf` (user overlay)
* `.shell-exports` sets `GOAMD64=v3` and `RUSTFLAGS=-C target-cpu=x86-64-v3`

Rebuild compression libs used by pacman/tar:

```bash
bash scripts/rebuild-v3.sh
```

Packages are signed with a local rebuild-v3 key (`~/.local/share/rebuild-v3/gnupg`, local-signed into pacman; `pacman -Qi` shows Validated By: Signature). `pacman -Syu` puts extra/ binaries back when those packages update; re-run the script. ffmpeg/zlib are opt-in: `bash scripts/rebuild-v3.sh ffmpeg`.

### PhotoGIMP (GIMP Photoshop layout)

Optional [PhotoGIMP](https://github.com/Diolinux/PhotoGIMP) patch on pacman **gimp** (`packages/pacman.txt`). Install/reapply:

```bash
bash scripts/install-photogimp.sh
```

Maps the upstream `3.0` config tree into the live dir (`~/.config/GIMP/3.2` on GIMP 3.2.x), skips stale `pluginrc`, bumps `config-version`, also patches Flatpak GIMP config when `org.gimp.GIMP` is installed, rewrites the PhotoGIMP `.desktop` `Exec` to native `gimp` (upstream zip is Flatpak/`gimp-3.0`-only), hides stock `gimp.desktop`, installs icons, and backs up existing config to `~/GIMP-<ver>-backup-YYYYMMDD`. Launch: app menu **PhotoGIMP**, or `gimp`.

### Dash2Dock Animated

Animated GNOME dock ([Dash2Dock Lite](https://github.com/icedman/dash2dock-lite) / EGO #4994). AUR `gnome-shell-extension-dash2dock-lite` is stale — install from EGO:

```bash
bash scripts/install-dash2dock.sh
```

UUID `dash2dock-lite@icedman.github.com` is in `gnome/extensions.txt` and `gnome/dconf/user.conf`. EGO zip still declares Shell ≤50; the install script patches `metadata.json` for **Shell 51** (unofficial — may still break). Other non-AUR zips (blur, caffeine, clipboard) install via `scripts/fetch-gnome-extensions.sh` (`GNOME_EXT_FETCH=1 bash scripts/install-extensions.sh`). Clipboard builds from a pinned GitHub commit and needs `tsc` (prefers pacman `typescript`; else non-interactive `npx --yes`). **Wayland:** log out → log in (`Meta.restart` is disabled). Prefs: `gnome-extensions prefs dash2dock-lite@icedman.github.com`.

### Shortcuts

Shell functions (`fe`, `rge`, `gai`, `fcd`, …), `Ctrl+R` / `Ctrl+T` / `Alt+C`, terminal and GNOME keys: [gnome/keybindings.md](gnome/keybindings.md). Modern aliases (when installed): `eza`, `bat`, `rg`, `fd`, `dust`, `duf`, `delta`, etc.

Disposable Kali lab (libvirt overlay): `kali-up` (isolated) / `kali-up-nat` / `kali-up-lan` (NAT + physical RJ45) / `kali-lan` / `kali-wipe` / `kali-stop` / `kali-st` / `kali` — see [keybindings](gnome/keybindings.md#disposable-kali) and [fresh-install RE guide](docs/fresh-install-coding-re.md#disposable-kali). NAT needs `virbr0` in firewalld **libvirt** zone (`firewalld-lab-zones.sh`). Physical LAN uses macvtap on `KALI_LAN_IFACE` (default `enp0s31f6`) → guest eth1.

### Starship

Uses the **Gruvbox Rainbow** preset (official [starship preset](https://starship.rs/presets/gruvbox-rainbow)) with Nerd Font symbols. Config: `stow/starship/.config/starship.toml`.

Optional older **Crampack** presets (not in this repo):  
`bash <(curl -fsSL "https://git.new/crampack-sh")`

---

## 🛠️ Repository Structure

```text
dotfiles/
├── install.sh       # First-boot orchestrator (pacman → profile → stow → agents…)
├── stow/            # GNU Stow packages → $HOME (system/zram/gdm via setup scripts, not stow -t /)
│   ├── bash/ zsh/   # shells; shared .shell-* under zsh/
│   ├── system/      # /etc template (sleep, firewalld-era units, udev, Wayland) → system-setup.sh
│   ├── containers/  # rootless Podman containers.conf
│   ├── privacy/     # telemetry opt-out environment.d
│   ├── zram/ gdm/   # templates → zram-setup.sh / gdm-setup.sh
│   ├── kitty/ ghostty/ alacritty/ contour/
│   └── nvim/ starship/ atuin/ git/ vscode/ cursor/ … 
├── browsers/        # chromium-base (+ brave-extra); zen; LibreWolf
├── packages/        # pacman.txt, flatpak.txt, aur.txt, re-extra.txt, thinkpad-t14s.txt, …
├── profiles/        # thinkpad-p15 | thinkpad-t14s | laptop | p15
├── scripts/         # Installers, setup, check (lib/ = dmi, charge conf, shared helpers)
├── tests/           # Smoke tests (`*.test.sh`, CI)
├── gnome/           # dconf, extensions.txt, keybindings.md
├── docs/            # hardened-arch-gnome.md + fresh-install-coding-re.md
├── builds/          # Optional local PKGBUILDs (e.g. builds/st)
├── skills/          # Host skills (ghidra-cli-host, obscura-host)
├── ai-rules/        # Shared AGENTS.md kit + git hooks
└── .github/         # CI (stow inventory, bash -n, tests/, markdownlint)
```

Layout stays flat on purpose: GNU Stow package roots, curl-able installers, and
`packages/*.txt` manifests. Do not nest `scripts/` by feature — keep
`CONTRIBUTING.md` script map as the index.

---

## 📚 Documentation

| Document | Description |
|----------|-------------|
| [README.md](README.md) | Overview, shell setup, installation |
| [CHANGELOG.md](CHANGELOG.md) | Version history |
| [CONTRIBUTING.md](CONTRIBUTING.md) | Contribution guidelines |
| [docs/hardened-arch-gnome.md](docs/hardened-arch-gnome.md) | Full Arch + GNOME guide — dual-host Stage A + firewalld |
| [docs/fresh-install-coding-re.md](docs/fresh-install-coding-re.md) | Purpose stacks (coding / RE / malware lab); lab-re + Stage B configure |
| [t14s-arch-install](https://github.com/HelllGuest/t14s-arch-install) | Preferred Stage A ISO installer (T14s 21CQ/21CR + P15 20SU) |
| [gnome/keybindings.md](gnome/keybindings.md) | Shell aliases and useful shortcuts |

---

## 📦 Installation & Setup

### 0. Bare-metal Arch install (Stage A, from the ISO)

**Canonical Stage A:** **[t14s-arch-install](https://github.com/HelllGuest/t14s-arch-install)**
(`HW_PROFILE=t14s|p15`, TUI/DRYRUN/answers). Seeds **firewalld** (`nftables`,
default zone `drop`); optional P15 `ollama-cuda` on `127.0.0.1:11434`.

```bash
# Preferred (from Arch ISO, UEFI, root):
bash <(curl -fsSL https://raw.githubusercontent.com/HelllGuest/t14s-arch-install/main/install.sh)

# Thin URL-stable wrappers in this repo (hand off to the same installer):
bash <(curl -fsSL https://raw.githubusercontent.com/HelllGuest/dotfiles/main/scripts/arch-install-t14s.sh)  # HW_PROFILE=t14s
bash <(curl -fsSL https://raw.githubusercontent.com/HelllGuest/dotfiles/main/scripts/arch-install-p15.sh)   # HW_PROFILE=p15
bash <(curl -fsSL https://raw.githubusercontent.com/HelllGuest/dotfiles/main/scripts/arch-install.sh)       # DMI detect
```

Manual phases: [docs/hardened-arch-gnome.md](docs/hardened-arch-gnome.md).
Rehearse: `scripts/arch-install-vmtest.sh`. Then **1. Full Bootstrap** (Stage B).

### 1. Full Bootstrap (Recommended)
Installs packages, stows configs into `$HOME`, installs `stow/system/` into `/etc` as root-owned files, restores GNOME settings, and runs health checks.
```bash
./install.sh
# Optional: run Stage B TUI modules during install (fails hard if a module fails):
# CONFIGURE=1 ./install.sh
# Headless / serial: CONFIGURE=1 CONFIGURE_UI=plain ./install.sh
# Skip foxcage / ollama: SKIP_FOXCAGE=1 SKIP_OLLAMA=1 ./install.sh
```

Machine profiles run in `./install.sh` via `scripts/apply-profile.sh` **after** `packages/pacman.txt` (exactly one profile): `profiles/$(hostname).sh` if it exists, otherwise `scripts/detect-profile.sh` (ThinkPad P15 → `thinkpad-p15`, ThinkPad T14s Gen 3 AMD 21CQ/21CR → `thinkpad-t14s`, other ThinkPads/laptop chassis → `laptop`). Pacman first so Optimus/NVIDIA packages exist before `thinkpad-p15` enables services and rebuilds UKIs (on `thinkpad-t14s` AMD hosts, `./install.sh` skips the Intel/NVIDIA GPU packages in `packages/pacman.txt`, including `egl-wayland`). There is no `nvidia.sh`; Optimus setup is inside `profiles/thinkpad-p15.sh`.

ThinkPad system configs (kernel cmdline templates, sleep, Wayland env, units) live in `stow/system/` and are installed by `scripts/system-setup.sh` as **root-owned regular files**, never stow symlinks (re-run it after editing `stow/system/`). Why, and how the cmdline UUID is handled: [hardened guide — `system/` files](docs/hardened-arch-gnome.md#kernel-cmdline--system-files-installed-not-stowed). On **T14s Gen 3 AMD**, check `cat /sys/power/mem_sleep`, `lscpu | grep -i ryzen`, `grep -E 'amd_iommu|amd_pstate' /proc/cmdline`, and charge thresholds under `/sys/class/power_supply/BAT*/charge_control_*_threshold`. On **P15**, verify Optimus/`prime-run` after reboot (`lspci -nnk -d 10de:`, charge 70–80). Installer + profile pull `mesa` / `vulkan-radeon` / `fprintd` (libva via mesa) on AMD; P15 Stage A (`arch-install-p15.sh` or `t14s-arch-install` `HW_PROFILE=p15`) seeds NVIDIA Optimus + optional ollama-cuda, and `profiles/thinkpad-p15.sh` refreshes it.

#### Script execution order (fresh machine)

**Stage A — from the Arch ISO (bare metal):**
```text
# Canonical: HelllGuest/t14s-arch-install (HW_PROFILE=t14s|p15)
# Thin wrappers (scripts/arch-install{,-t14s,-p15}.sh) only hand off — no second body
scripts/arch-install-vmtest.sh   # optional UEFI VM rehearsal (host disks untouched)
scripts/arch-install-t14s.sh     # → HW_PROFILE=t14s
scripts/arch-install-p15.sh      # → HW_PROFILE=p15
scripts/arch-install.sh          # → DMI detect / TUI radio
→ reboot, remove ISO
```

**Stage A½ — enable Secure Boot (optional, after first boot works with SB disabled in BIOS):**
```text
BIOS → clear Secure Boot keys → Setup Mode
sudo sbctl enroll-keys -m          # -m keeps Microsoft keys (Windows on shared ESP)
BIOS → Secure Boot → Enabled
sbctl status && sbctl verify
```

**Stage B — first boot (log into GNOME, open terminal, then):**
```text
git clone https://github.com/HelllGuest/dotfiles.git ~/dotfiles
cd ~/dotfiles
bash scripts/p15-dotfiles-preflight.sh   # P15 only — optional readiness check
bash scripts/configure.sh                # modular TUI (preferred for labs/AI/rice/firewalld)
# or full bootstrap:
./install.sh                             # requires GNOME session for dconf/extensions
# hostname p15 → profiles/p15.sh → thinkpad-p15 (Optimus). Or re-run:
# bash profiles/thinkpad-p15.sh
exec zsh
reboot                                   # UKI must embed nvidia_drm.modeset + nouveau blacklist
# after reboot (P15): expect Kernel driver in use: nvidia
lspci -nnk -d 10de: | grep -A2 'Kernel driver'
prime-run nvidia-smi -L
scripts/thinkpad-charge-thresholds.sh  # tmpfiles + late-boot service; profile / install-re-extras call it
```

#### How to: `configure.sh` (Stage B TUI)

UI backend (auto): **dialog** if present, else **whiptail**, else plain checklist
on the TTY (Arch often has whiptail only — `pacman -S dialog` optional). Force
with `CONFIGURE_UI=plain|dialog|whiptail` (use `plain` on serial / CI / no TTY).
Abort/Cancel exits without running modules. Selected modules **fail-fast** (a
failing module stops the script; no silent `|| true`).

| Tag | Default | Runs |
|-----|---------|------|
| `SETUP_FIREWALLD` | on | `firewalld-lab-zones.sh` → drop + `virbr0`/`libvirt` + `virbr-malware`/`lab-malware` (iface + `192.168.200.0/24`) |
| `APPLY_PROFILE` | off | `apply-profile.sh` |
| `SETUP_OLLAMA` | **on for P15 (20SU)**; off on T14s | `ollama-setup.sh` (skipped with msg if not P15) |
| `SETUP_LABS` | off | `labs-setup.sh` (triage/re/android/web images) |
| `SETUP_DETONATE` | off | `lab-detonate.sh setup` (capture + VMs) |
| `SETUP_AI` | off | `ai-stack-setup.sh` (Headroom/`hr-*`, Ponytail, Continue FIM; **not** Caveman — full `./install.sh` already did cores + extras + P15 ollama) |
| `SETUP_RICE` | off | `rice-setup.sh` (Gruvbox + lock-screen notifications off) |

```bash
bash scripts/configure.sh
CONFIGURE_UI=plain bash scripts/configure.sh   # headless / serial
# Re-run anytime; SETUP_FIREWALLD is safe to repeat.
```

Full `./install.sh` still installs Caveman + Ponytail. `SETUP_AI` alone is
Ponytail-oriented (complementary hooks; no duplicate caveman install).

#### How to: ops / privacy kits

Packages land from `packages/pacman.txt` on `./install.sh`: `pacman-contrib`,
`mat2`, `perl-image-exiftool` (`exiftool`), `bleachbit`, `usbguard`,
`dnscrypt-proxy`. AUR also lists `bootvine-git` (boot animation).

```bash
# Auto on install / post-update (SKIP_OPS_HYGIENE=1 to skip):
bash scripts/ops-hygiene.sh
#   paccache -rk2 · flatpak uninstall --unused · enable paccache.timer

mat2 ./report.pdf          # strip metadata before share/upload
exiftool ./photo.jpg       # inspect / edit EXIF
bleachbit                  # GUI junk cleaner

# Opt-in (do not enable blind on remote hosts):
bash scripts/usbguard-setup.sh   # allowlist plugged devices, then enable
bash scripts/dnscrypt-setup.sh   # dnscrypt-proxy on 127.0.0.1/::1 + NM DNS
# Tailscale MagicDNS may override NM DNS while connected — expected.
```

`check.sh` soft-probes these (○ until packages/services are present). Plain DNS
override without encrypt: `bash scripts/network-dns-setup.sh` (or `--all-wifi`).

#### How to: firewalld lab zones / `lab-malware`

```bash
bash scripts/firewalld-lab-zones.sh
# or only the malware zone:
source scripts/lib/lab-malware-zone.sh && ensure_lab_malware_zone
```

Expected zones:

```text
default zone: drop
virbr0          → libvirt          (kali-disposable / NAT guests)
virbr-malware   → lab-malware      (iface + source 192.168.200.0/24; DROP; no masq/forward)
```

`ensure_lab_malware_zone` (shared by `firewalld-lab-zones` + `lab-detonate`) binds **both**
the interface and the `192.168.200.0/24` source, unbinds `virbr-malware` from
`libvirt`/`block`, and uses `sudo` for permanent queries (polkit). Hosts
upgraded from Slice 1 may still show the bridge under `libvirt` or `block`.

```bash
sudo firewall-cmd --get-default-zone          # drop
sudo firewall-cmd --get-active-zones          # virbr-malware under lab-malware only
sudo firewall-cmd --permanent --zone=lab-malware --list-all
# expect: interfaces: virbr-malware; sources: 192.168.200.0/24; target: DROP; masquerade: no
```

#### How to: Stage B on a Stage A qcow2

Needs `~/arch-vmtest/test-disk.qcow2` from `t14s-arch-install` `tests/vm-run.sh`,
KVM, and edk2 OVMF. Host mounts this repo read-only via 9p.

```bash
bash scripts/vm-stageb-run.sh
# overrides: DISK=… GUEST_USER=t14svm GUEST_PASS=… LUKS_PASS=… RAM=4096
```

Guest (`vm-stageb-guest.sh`): `CONFIGURE_UI=plain` + empty checklist line →
defaults (`SETUP_FIREWALLD` on), then `./install.sh` with
`SKIP_CONFIGURE=1`, `SKIP_FOXCAGE=1`, `SKIP_OLLAMA=1`,
`GIT_SETUP_NONINTERACTIVE=1`. Temporary NOPASSWD is removed before RESULT.

| RESULT | Meaning | Harness exit |
|--------|---------|--------------|
| `PASS` | configure + install both 0 | 0 |
| `PASS_CONFIGURE` | configure 0; install soft-fail (minimal Stage A / no GNOME) | 0 |
| `FAIL` | configure failed (or guest aborted) | 1 |

Wait budget: 150 min (nested pacman is slow).

#### How to: `git-setup.sh` (identity / hooks)

```bash
bash scripts/git-setup.sh
GIT_SETUP_NONINTERACTIVE=1 bash scripts/git-setup.sh
```

Interactive: prompts for name/email, hooks, optional GPG/SSH signing.
Noninteractive when `GIT_SETUP_NONINTERACTIVE=1` **or** stdin is not a TTY:
skips prompts, enables hooks template, applies default name/email if unset
(or placeholder `your@email.com`).

#### How to: GNOME extension zips (`fetch-gnome-extensions.sh`)

```bash
GNOME_EXT_FETCH=1 bash scripts/install-extensions.sh
# or: bash scripts/fetch-gnome-extensions.sh
```

Installs EGO blur/caffeine, builds pinned `gnome-clipboard` (needs `tsc`:
pacman `typescript` preferred, else `npx --yes`), then Dash2Dock. Safe to
re-run. Enable via `install-extensions.sh`; Wayland needs log out → log in.

**Lab commands (after `labs-setup.sh` / configure SETUP_LABS):**
```text
lab-triage | lab-re | lab-android | lab-web | lab-detonate | lab-mcp
```

**What `./install.sh` runs, in order:**
```text
cleanup-input-overrides.sh
→ pacman < packages/pacman.txt
→ apply-profile.sh (hostname e.g. p15, or detect-profile.sh — after packages so NVIDIA DKMS exists)
→ install-flatpaks.sh → install-aur.sh (bootstraps paru)
→ install-fonts.sh → stow ($HOME; system/ via system-setup.sh; skips zram & gdm)
→ fnm install/default 22 → atuin import → zram-setup.sh
→ gnome-session-setup.sh → location-setup.sh → gnome-console-setup.sh
→ gdm-setup.sh → git-setup.sh → nvim-setup.sh → headroom-setup.sh
→ sync-agent-skills.sh → install-coding-agents.sh (OpenCode + Kimi + MCP; if npm)
→ install-caveman.sh (if npm) → install-ponytail.sh (if node) → install-android-ui-skills.sh (if npx)
→ install-ghidra-cli.sh (if ghidra)
→ install-obscura.sh (headless browser + MCP)
→ install-re-skills.sh (leanrea / RE playbooks / Android RE / Ghidra loop)
→ install-ecosystem-skills.sh (packages/agent-skills.txt; owner/repo or owner/repo:skill; if npx)
→ sync-agent-skills.sh → caveman OpenCode plugin refresh
→ ai-stack-setup.sh (AI_STACK_EXTRAS_ONLY=1: Continue FIM, P15 OpenCode↔ollama, hr-proxy)
→ ollama-setup.sh (P15 only; SKIP_OLLAMA=1 skips; no-op elsewhere)
→ install-photogimp.sh → install-foxcage.sh (if podman; SKIP_FOXCAGE=1 skips)
→ install-dash2dock.sh → install-extensions.sh
→ privacy-hardener.sh (incl. browser-hardening.sh)
→ ops-hygiene.sh (paccache + flatpak unused + paccache.timer; SKIP_OPS_HYGIENE=1 skips)
→ firewalld-tailscale.sh (if tailscale) → check.sh → validate-configs.sh
```
Opt-in after install (not auto): `bash scripts/usbguard-setup.sh`,
`bash scripts/dnscrypt-setup.sh`. See
[How to: ops / privacy kits](#how-to-ops--privacy-kits).
REA backends: use `lab-re` (JDK21/Ghidra/jadx/rizin + `rea-agents@6.9.0`). Optional host MCP only:
`bash scripts/install-rea.sh` (needs host JDK≥21).

> `scripts/tmp-to-disk.sh` is **not** part of this flow — `arch-install.sh` already
> puts `/tmp` on a disk-backed `@tmp` subvolume. It's only for retrofitting an
> **existing** machine that still has tmpfs `/tmp`.

### 2. Config Only (No Root)
Applies user-level symlinks only (removes unmodified `/etc/skel` copies such as `.bashrc` that would block stow). Skips `zram`, `system`, and `gdm` (require root — use `install.sh`).
```bash
./stow-only.sh
```

### 3. zram config
Do **not** `stow -t / zram` (a symlink into `$HOME` breaks at early boot). `install.sh` runs `scripts/zram-setup.sh`, which copies a real file to `/etc/systemd/zram-generator.conf`. Re-run that script to refresh.

### 4. Dependencies
Key runtime dependencies (`scripts/check.sh` asserts binaries, shell tools, symlinks, fonts, optional AI, and Zen `user.js` when present; it does **not** check `rclone`, `dart-sass`, or `zram-generator`):

**Core:** `stow`, `zsh`, `starship`, `neovim`, `flatpak`, `rclone`, `jq`, `dart-sass`, `zram-generator`

**Zsh:** zinit bootstraps on first launch; plugins load via `.zsh-plugins`

**Shell tools:** `atuin`, `fzf`, `fd`, `ripgrep`, `bat`, `eza`, `zoxide`, `direnv`, `git-delta`, `fnm`

**AI:** `./install.sh` installs the full stack: Headroom (`hr-claude` / `hr-cursor` / `hr-opencode` / `hr-agy` / `hr-proxy`), OpenCode + Kimi, Caveman `v4.1.0` + Ponytail `v5.3.3`, Continue FIM config, Obscura CDP/MCP, ecosystem + RE skills, hub sync; on P15 also `ollama-setup.sh` (CUDA + qwen pulls; `SKIP_OLLAMA=1` opts out). `configure.sh` `SETUP_AI` runs `ai-stack-setup.sh` (Headroom/Ponytail/Continue; **not** Caveman). Modular re-run: `bash scripts/ai-stack-setup.sh`

**Graphics (optional):** `gimp` + PhotoGIMP via `scripts/install-photogimp.sh`

**Sandboxed browser (optional):** [foxcage](https://gitlab.com/grepular/foxcage) runs Firefox in a rootless Podman container (`scripts/install-foxcage.sh`, pinned commit + SHA-256; needs Wayland, `podman`, `passt`, `xdg-dbus-proxy`). `foxcage @tmp <url>` opens a throwaway cage. Not set as default browser; opt in with `xdg-settings set default-web-browser foxcage.desktop`.

**GNOME dock:** Dash2Dock Animated via `scripts/install-dash2dock.sh` (EGO; listed in `gnome/extensions.txt`)

**AUR** (via `install-aur.sh`, bootstraps `paru` if needed): `blesh-git`, `bootvine-git`, `curlie`, `forgit`, GNOME shell extensions, `vscodium-bin` (settings in `stow/vscode/`)

**Flatpaks** (via `install-flatpaks.sh`): Brave, Zen, Google Chrome, LibreWolf, Proton VPN, Android Studio. Chrome may be `--system` or `--user`; both satisfy `check.sh` / hardening presence checks. Browser telemetry debloat: `scripts/browser-hardening.sh` (Chrome = `chromium-base` only; Brave = base + `brave-extra`; Zen `user.js` per real profile + Flatpak `systemconfig` + `/etc/firefox/policies` for native; LibreWolf upstream + `librewolf.overrides.cfg`). Launch Zen once before re-running hardening if profiles are new. `/etc` policy paths need sudo.

**Terminals:** `kitty` (primary; Super+Return), `ghostty`, optional `alacritty` / `contour`, plus `gnome-console` (kgx). Rice: `bash scripts/rice-setup.sh` (Gruvbox accents; privacy: `show-in-lock-screen false`). Optional suckless `st`: `bash scripts/build-st.sh` (`builds/st/`).

Run `scripts/gnome-console-setup.sh` for Console dconf. **Super+Return → kitty** is in `gnome/dconf/user.conf`.

Clipboard: selecting text auto-copies in kitty and ghostty (`copy_on_select`); in kitty, right-click also copies the selection (Shift+right-click extends it).

**Ghidra / RE AI:** prefer `lab-re` (container: JDK21 + Ghidra + jadx + rizin + `rea-agents@6.9.0`). Optional host: pacman `ghidra` + `bash scripts/install-ghidra-cli.sh` / `bash scripts/install-rea.sh` (needs JDK≥21). Extra skills: `bash scripts/install-re-skills.sh`. Details: [fresh-install RE guide](docs/fresh-install-coding-re.md#ai-reverse-engineering-mcp--skills).

**GDM:** `scripts/gdm-setup.sh` copies greeter config to `/etc` (not stow — GDM cannot read `$HOME`), enables Wayland, compiles greeter dconf, and enables `gdm.service`. Greeter changes appear after **reboot** (or `sudo systemctl restart gdm`, which logs you out). Optional fingerprint: `scripts/fingerprint-setup.sh`.

**Git:** `stow/git/` + `scripts/git-setup.sh` — delta pager, rebase defaults, global ignore, optional hooks and signing. Headless: see [How to: git-setup.sh](#how-to-git-setupsh-identity--hooks). URL shorthands: `git clone gh:user/repo`.

**Neovim:** `scripts/nvim-setup.sh` — Lazy.nvim plugins, Treesitter parsers, Mason LSP on first launch. Leader = Space.

**GNOME session:** `scripts/gnome-session-setup.sh` — dconf profile, Dash2Dock install, and extensions. Super+1–4 workspaces. Mouse/touchpad/keyboard use **stock GNOME defaults** (reset on session setup via `scripts/reset-input-defaults.sh`).

**Location spoofing:** `scripts/location-setup.sh` — static GeoClue coords in `/etc/geolocation` (home Dubai; VPN exit when `proton0` is up). Panel extension `proton-vpn@helllguest` shows spoofed coords and **Sync spoofed location** (runs `pkexec vpn-location-sync sync`). Manual: `vpn-location-sync` or `sudo vpn-location-sync sync`.

**Fonts:** Run `scripts/install-fonts.sh` for top Nerd Fonts (JetBrains Mono, Meslo, FiraCode, Cascadia, Iosevka, etc.)

---

## 🛡️ Privacy & Security

We take a "quiet by default" approach:
- **GNOME Debloated:** Uses `gnome-shell` instead of the full `gnome` meta-package where possible.
- **Opt-out defaults:** `stow/privacy` → `~/.config/environment.d/90-telemetry-optout.conf` (GUI session + `.shell-exports`). `scripts/privacy-hardener.sh` covers GNOME, browsers, IDE/Claude merges (Cursor-only `cursor.general.*` on Cursor trees; strips leftovers elsewhere), Flutter `reporting=0`, Headroom/AI. Rice also sets `org.gnome.desktop.notifications show-in-lock-screen false`. Re-run after upgrades: `bash scripts/privacy-hardener.sh` / `bash scripts/rice-setup.sh`.
- **Ops / privacy kits:** `mat2` + `exiftool` (strip metadata before share), `bleachbit` (UI junk), `ops-hygiene.sh` (paccache + flatpak unused; hooked from `install.sh` / `post-update.sh`), opt-in `usbguard-setup.sh` / `dnscrypt-setup.sh`. Full howto: [ops / privacy kits](#how-to-ops--privacy-kits).

---

## Troubleshooting

| Symptom | Cause | Fix |
|---------|--------|-----|
| `Can't find an installed Node version matching …` on terminal open | **fnm** `--use-on-cd` + project `engines` / `.nvmrc` | `fnm install 22` or `fnm install` in project; or drop `--use-on-cd` in dotfiles |
| `$FZF_DEFAULT_OPTS: unknown action: copy-selection` | fzf 0.72 lacks `copy-selection` | Fixed in dotfiles; `exec zsh` / `exec bash` |
| `docker` tries Podman socket / `connect: no such file` | Stale `DOCKER_HOST` or Podman socket missing | `systemctl --user enable --now podman.socket`; new shell; or `FORCE_DOCKER=1` for real dockerd |
| `s2idle [deep]` / `mem_sleep_default=deep` after upgrades | Cmdline or BIOS drifted from s2idle pin | BIOS Sleep = Windows and Linux; `bash scripts/system-setup.sh`; reboot |
| Charge thresholds reset every boot | Missing tmpfiles **and/or** late-boot unit (`thinkpad_acpi` BAT* can appear after tmpfiles) | `bash scripts/thinkpad-charge-thresholds.sh` (optional `CHARGE_START`/`CHARGE_END`; installs tmpfiles + `thinkpad-charge-thresholds.service`) |
| `check.sh`: Chrome / Brave policies ✗ | `/etc` policy files missing or stale | `bash scripts/browser-hardening.sh` (needs sudo for `/etc`) |
| `evolution-data-server` / `wireless-regdb` (or any `pacman.txt` package) missing | Older `install.sh` fed `#` comment lines to pacman (`target not found: # …`), aborting the whole package step | Pull, then re-run `./install.sh` (comments are stripped now) |
| `unsafe path transition /etc` during `pacman` | `/etc` owned by user (old `gdm-setup.sh` used `rsync -a`) | `bash scripts/gdm-setup.sh` (restores root + 755), or `sudo chown root:root /etc && sudo chmod 755 /etc` |
| No inbound / wrong default zone | firewalld zones not applied or default ≠ `drop` | `bash scripts/firewalld-lab-zones.sh`; `sudo firewall-cmd --get-default-zone` |
| `virbr-malware` listed under `libvirt` / `block` | Pre-`lab-malware` bind left over | [firewalld howto](#how-to-firewalld-lab-zones--lab-malware); confirm iface + `192.168.200.0/24` |
| `INVALID_ZONE: lab-malware` | Zone never created on this host | Same as above (`lib/lab-malware-zone.sh`) |
| Stage B VM hangs on Name/Email or `npx` prompt | Interactive git / clipboard build on serial | Pull fixes; harness sets `GIT_SETUP_NONINTERACTIVE` + non-interactive `tsc` |
| `DOTFILES_STAGEB_RESULT=PASS_CONFIGURE` | Install soft-failed on minimal Stage A | Expected without full GNOME; firewalld path still OK |
| SSH blocked after lab-zones | drop zone has no 22/tcp | `sudo firewall-cmd --permanent --add-service=ssh && sudo firewall-cmd --reload` (only if you need SSH) |
| Spoof location sync does nothing | `vpn-location-sync` failed under `pkexec` | `bash scripts/location-setup.sh`; panel → Sync spoofed location |
| Touchpad clicks broken after old dotfiles | Legacy synaptics inhibit/udev | `bash scripts/cleanup-input-overrides.sh` (sudo), log out |
| Ghostty needs 2 clicks / fails from app grid | systemd `notify-reload` vs late SIGUSR2 ([#14394](https://github.com/ghostty-org/ghostty/discussions/14394)) | Stow `ghostty` drop-in sets `Type=notify`; `systemctl --user daemon-reload` |
| `headroom not installed` / `hr-claude` fails | Headroom not set up yet | `bash scripts/headroom-setup.sh` |
| `headroom doctor`: Base URL unset | Current shell never sourced rc | `source ~/.zshrc` or new terminal; Claude Code uses settings.json |
| Headroom proxy down after reboot | User service not lingering | `systemctl --user enable --now headroom-default.service`; `loginctl enable-linger $USER` |
| Cursor not using Headroom | Base URL not set in IDE | Run `hr-cursor`, paste URL in Settings → Models; keep proxy terminal open |
| zstd/xz/lz4 back to extra/ after `-Syu` | Repo upgrade replaced v3 rebuilds | `bash scripts/rebuild-v3.sh` then `sudo pacman -U` if sudo -n fails |
| PhotoGIMP layout missing after GIMP update | Config dir version bump / patch not reapplied | `bash scripts/install-photogimp.sh` |
| Dash2Dock missing after install | Wayland Shell has not reloaded | Log out → log in; or `bash scripts/install-dash2dock.sh` then logout |
| `proton-vpn@helllguest` missing from `gnome-extensions list` | Shell session cache stale / after uninstall | Log out → log in; never `gnome-extensions uninstall` a stowed UUID (deletes tree) |
| Proton VPN app stuck on "Loading app" | Server list fetch hung | `bash scripts/proton-seed-serverlist.sh` (or `--kill`) |
| `ghidra` CLI is the GUI / wrong Java | cargo bin shadows `/usr/bin/ghidra` | Use `ghidra-gui`; re-run `bash scripts/install-ghidra-cli.sh` |

---

## 🧹 Maintenance

| Task | Command |
|------|---------|
| Full update | `sudo pacman -Syu && ./install.sh && bash scripts/post-update.sh` |
| Ops hygiene | `bash scripts/ops-hygiene.sh` — `paccache -rk2`, `flatpak uninstall --unused`, enable `paccache.timer` |
| Metadata strip | `mat2 file.pdf` / `exiftool file.jpg` (share/upload path) |
| UI junk cleaner | `bleachbit` (GUI) or `bleachbit -c …` |
| USB allowlist | `bash scripts/usbguard-setup.sh` (generates rules from plugged devices, then enables) |
| Encrypted DNS | `bash scripts/dnscrypt-setup.sh` (dnscrypt-proxy → 127.0.0.1; MagicDNS may override while Tailscale is up) |
| Health check | `~/dotfiles/scripts/check.sh` |
| Docs lint | `~/dotfiles/scripts/lint-docs.sh` (CI also runs this + `all_stow_files.txt` + `bash -n` + `tests/*.test.sh`) |
| System files (`stow/system/`) | `bash scripts/system-setup.sh` |
| Refresh stow inventory | `git add stow/…` then `bash scripts/list-stow-files.sh > all_stow_files.txt` (index only) |
| Location sync | `vpn-location-sync` or Proton VPN panel → Sync spoofed location |
| Optional st (suckless) | `bash scripts/build-st.sh` |
| Agent skills sync | `bash scripts/sync-agent-skills.sh` (hub → Claude/Cursor/OpenCode/Kimi/Gemini/Antigravity/Kiro) |
| OpenCode + Kimi | `bash scripts/install-coding-agents.sh` (pinned npm CLIs + MCP) |
| Ecosystem skills | `bash scripts/install-ecosystem-skills.sh` (`packages/agent-skills.txt`; optional `owner/repo:skill1,skill2`) |
| Caveman (`/caveman`) | `bash scripts/install-caveman.sh` |
| Ponytail (`/ponytail`) | `bash scripts/install-ponytail.sh` |
| Android UI skills | `bash scripts/install-android-ui-skills.sh` (Compose + Material 3) |
| REA in lab-re | `lab-re` / rebuild `podman build -t localhost/lab-re labs/lab-re` (`rea-agents@6.9.0`) |
| REA host MCP (optional) | `bash scripts/install-rea.sh` (needs JDK≥21; Hopper: `INSTALL_HOPPER=1`) |
| Labs / detonate / MCP | `bash scripts/labs-setup.sh`; `lab-detonate` / `lab-mcp` |
| Stage B TUI | `bash scripts/configure.sh` ([howto](#how-to-configuresh-stage-b-tui)); `CONFIGURE_UI=plain` for serial/CI |
| Stage B VM harness | `bash scripts/vm-stageb-run.sh` (needs Stage A `test-disk.qcow2`) |
| Gruvbox rice | `bash scripts/rice-setup.sh` |
| Live lab/firewall health | See checklist below |
| Obscura (CDP/MCP) | `bash scripts/install-obscura.sh` ([docs](https://docs.obscura.sh/)) |
| foxcage (Firefox in rootless Podman) | `bash scripts/install-foxcage.sh` ([upstream](https://gitlab.com/grepular/foxcage)); then `foxcage`, `foxcage @tmp <url>`; `install.sh` runs it when `podman` exists (`SKIP_FOXCAGE=1` skips) |
| RE skills (leanrea, …) | `bash scripts/install-re-skills.sh` |
| RE host extras (jadx, rizin, …) | `bash scripts/install-re-extras.sh` |
| ghidra-cli | `bash scripts/install-ghidra-cli.sh` |
| Legacy touchpad cleanup | `bash scripts/cleanup-input-overrides.sh` (sudo; old udev/inhibit only) |
| Secure Boot | `sbctl status && sbctl verify` (after `enroll-keys -m`; `mkinitcpio -P` re-signs UKIs via sbctl's hook) |
| Backup GNOME | `~/dotfiles/scripts/backup-gsettings.sh` |
| Move /tmp to disk | `sudo ~/dotfiles/scripts/tmp-to-disk.sh` then reboot (off RAM-capped tmpfs → btrfs `@tmp`) |
| Reload shell | `exec zsh` |
| Install project Node (fnm) | `fnm install 22` or `fnm install` inside project |
| Headroom (Claude / Cursor) | `bash scripts/headroom-setup.sh`; prefer `headroom-default.service`; then `hr-claude` / `hr-cursor` |
| x86-64-v3 rebuilds | `bash scripts/rebuild-v3.sh` |
| PhotoGIMP | `bash scripts/install-photogimp.sh` |
| Dash2Dock | `bash scripts/install-dash2dock.sh` then log out/in (Wayland) |

### Live health checklist (non-destructive)

```bash
uname -r
systemctl is-enabled ufw                  # expect: masked
systemctl is-active firewalld             # expect: active
firewall-cmd --get-default-zone           # expect: drop
firewall-cmd --get-active-zones           # virbr0→libvirt; virbr-malware→lab-malware only
sudo firewall-cmd --permanent --zone=lab-malware --list-all
#   target: DROP; masquerade: no; interfaces: virbr-malware; sources: 192.168.200.0/24

lab-re --check
podman images | grep localhost/lab-
# From $HOME, lab wrappers refuse mounting home as /work (fallback /srv/lab/out):
cd ~ && source ~/.shell-functions && _lab_work_dir   # expect /srv/lab/out + refuse message

ss -tlnp | grep -E ':8787|:11434'
# 8787 → 127.0.0.1 only (Headroom). 11434 → 127.0.0.1 only on P15; absent on T14s.
gsettings get org.gnome.desktop.notifications show-in-lock-screen   # false

# Ops / privacy (soft — ○ until enabled):
command -v mat2 exiftool bleachbit paccache usbguard dnscrypt-proxy
systemctl is-enabled paccache.timer          # expect: enabled after ops-hygiene
systemctl is-active usbguard                 # active only after usbguard-setup
systemctl is-active dnscrypt-proxy           # active only after dnscrypt-setup

for t in ~/dotfiles/tests/*.test.sh; do bash "$t" || break; done
bash ~/t14s-arch-install/tests/smoke.test.sh   # if that repo is present
```

---

## ⚖️ License
MIT © 2026
