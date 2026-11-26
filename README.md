# 🌌 Arch Linux + GNOME Dotfiles

A clean, modular, and programmable dotfiles ecosystem optimized for **Arch Linux**, **GNOME Shell 51**, and **ThinkPad** hardware. This setup focuses on visual cohesion, privacy hardening, and a frictionless developer workflow.

---

## 🚀 Key Features

- **Privacy Hardened:** Telemetry, usage reporting, and "phoning home" are disabled system-wide (GNOME, VS Code, .NET, etc.).
- **ThinkPad Optimized:** Hostname or hardware-detected profiles (`thinkpad-p15.sh`, `thinkpad-t14s.sh`, or `laptop.sh`) with power-profiles-daemon (or tuned + `tuned-ppd` on hosts from `t14s-arch-install`), UKIs signed for Secure Boot (sbctl), and a tracked **s2idle** sleep pin (`mem_sleep_default=s2idle`; pair BIOS Sleep State with **Windows and Linux**, not **Linux**/S3 — see `docs/hardened-arch-gnome.md`). Firewall: **firewalld** (`nftables`, default `drop`). Stage B modules: `bash provision/scripts/configure.sh` (firewalld, labs, AI stack, terminal/CLI rice). Lab wrappers: `lab-triage` / `lab-re` / `lab-android` / `lab-web` / `lab-detonate` / `lab-mcp` (see `labs/scripts/labs-setup.sh`, `lab-detonate.sh`, `lab-mcp.sh`). Thermal is firmware-managed. Charge window **70–80** via `system/scripts/thinkpad-charge-thresholds.sh`.
- **Elite-Tier Terminal:** Kitty (stock host colors; Gruvbox accents for `lab-*`) & Ghostty with shared Zsh/Bash configs, real-time autocomplete, and switchable Gruvbox / SecOps themes (`rice-theme`, `ff-preset`; stored as untracked local overrides) across Starship, Fastfetch, btop, Ghostty, and Alacritty.
- **Neovim (Lazy.nvim):** A modular Lua configuration.

---

## 🐚 Shell Configuration

Zsh is the primary shell. Bash is fully supported for scripts and fallback sessions.

### Shared files (`stow/zsh/`)

| File | Purpose |
|------|---------|
| `.shell-exports` | Environment variables (editor, pager, Android SDK, telemetry opt-outs, container CLI socket) |
| `.shell-aliases` | Shared aliases (`v`, `as`, etc.) |
| `.shell-functions` | Shared functions (`mkcd`, `backup`, `ff`, `rice-theme`, lab wrappers); zsh-only OSC 7 CWD hook |
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

**Default shell + startup:** `./install.sh` makes zsh the login shell (`usermod -s`; Stage A already does at `useradd`) and `check.sh` fails if it is not. Interactive startup ≈50 ms: `compinit` runs once, deferred after the first prompt (`_dot_compinit`: daily full run with the insecure-dir audit, dump touched + `zcompile`d so the fast path is actually taken), static tool inits (starship, fzf, atuin, zoxide, direnv, uv) are sourced from `~/.cache/zsh/init/` and regenerated when the tool's binary changes (`_zsh_cache_eval`), `fnm env` runs once. `tests/zsh.test.sh` keeps a 250 ms budget.

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
# leftover bridge from a prior daemon (optional cleanup):
sudo ip link delete docker0 2>/dev/null || true
systemctl --user enable --now podman.socket
```

Escape hatch for a real Docker daemon: `FORCE_DOCKER=1` (with `/var/run/docker.sock`), or stop `podman.socket`.

Hardened one-shot runs: `ai/scripts/agent-run.sh <project-dir> <image> [cmd…]` (read-only, cap-drop ALL, network none by default; never mounts runtime sockets). User defaults: `stow/containers` → `~/.config/containers/containers.conf`. Full notes: [Phase 17](docs/hardened-arch-gnome.md#phase-17--rootless-podman).

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

**Headroom** compresses tool output and context before it hits the model (savings vary; see [upstream](https://github.com/headroomlabs-ai/headroom)). Installed user-local via **pipx** (`python-pipx` in `packages/pacman.txt`). `ai/scripts/install-headroom.sh` installs `headroom-ai[all]` at the pinned `HEADROOM_VERSION` (reinstalls only on mismatch; bump the pin to upgrade).

```bash
bash ai/scripts/headroom-setup.sh    # install/upgrade + MCP registration
```

`./install.sh` runs `sync-agent-skills.sh` **before** `headroom-setup.sh` so `~/.claude`, `~/.cursor`, and the other agent dirs exist for MCP merges. After setup, prefer a **systemd user** persistent proxy (survives logout when linger is on). Either the upstream preset or the repo unit:

```bash
# Option A — upstream persistent service:
headroom install apply --preset persistent-service --runtime python --scope user \
  --providers auto --profile default --port 8787 --backend anthropic --mode token --no-telemetry
systemctl --user status headroom-default.service

# Option B — repo unit (what ai-stack-setup.sh can enable):
systemctl --user enable --now hr-proxy.service

loginctl enable-linger "$USER"   # once, so it survives logout
headroom doctor
```

Claude Code CLI is optional (`○` in `check.sh` until installed): `npm install -g @anthropic-ai/claude-code` (after fnm Node 22).

| Command | What it does |
|---------|----------------|
| `hr-claude` | `headroom wrap claude` — proxy + launch Claude Code |
| `hr-cursor` | Start proxy; paste printed Base URL into Cursor → Settings → Models |
| `hr-opencode` | Proxy + launch OpenCode |
| `hr-agy` | Proxy + launch Antigravity CLI (`agy`) |
| `hr-proxy` | One-shot proxy on port `8787` (`HEADROOM_PORT` to override) |

**Routing & MCP:** `ai/scripts/headroom-setup.sh` sets `ANTHROPIC_BASE_URL` and `ENABLE_TOOL_SEARCH` in `~/.claude/settings.json` and registers the `headroom` MCP server across Claude Code, Cursor (`~/.cursor/mcp.json`), OpenCode (`~/.config/opencode/opencode.json`), Kimi Code (`~/.kimi-code/mcp.json`), Gemini CLI (`~/.gemini/settings.json`), and Antigravity (`~/.gemini/config/mcp_config.json`). Interactive shells also get `ANTHROPIC_BASE_URL` / `OPENAI_BASE_URL` from stowed `~/.zshrc` / `~/.bashrc` (and `~/.profile`). If `headroom doctor` warns that those vars are unset, the *current* process never sourced the rc file (common in IDE/agent shells): `source ~/.zshrc`, open a new terminal, or `export ANTHROPIC_BASE_URL=http://127.0.0.1:8787` / `OPENAI_BASE_URL=http://127.0.0.1:8787/v1`.

**Cursor model proxy:** paste the Override OpenAI Base URL printed by `hr-cursor` into Cursor → Settings → Models (the IDE does not read shell env for model routing).

**RTK:** Headroom 0.34+ no longer bundles [RTK](https://github.com/rtk-ai/rtk). Install the SHA-256-pinned binary via `bash ai/scripts/install-rtk.sh` (`~/.local/share/rtk/rtk` + symlink `~/.local/bin/rtk`). Do **not** put it in `~/.headroom/bin`; `headroom wrap` / some `init` paths purge managed copies there. Telemetry stays off (`HEADROOM_TELEMETRY=off`, `--no-telemetry`).

Antigravity CLI (`agy`) and Kiro: point at `http://127.0.0.1:8787/v1` only if that tool accepts a custom OpenAI-compatible base URL.

### x86-64-v3 local builds

This ThinkPad (Comet Lake) is **x86-64-v3**, not v4. Official extra/ packages stay generic `x86-64`. For local/AUR builds:

* `system/etc/makepkg.conf.d/zz-x86-64-v3.conf` (via `system/scripts/system-setup.sh`)
* `stow/pacman/.config/pacman/makepkg.conf` (user overlay)
* `.shell-exports` sets `GOAMD64=v3` and `RUSTFLAGS=-C target-cpu=x86-64-v3`

Rebuild compression libs used by pacman/tar:

```bash
bash system/scripts/rebuild-v3.sh
```

Packages are signed with a local rebuild-v3 key (`~/.local/share/rebuild-v3/gnupg`, local-signed into pacman; `pacman -Qi` shows Validated By: Signature). `pacman -Syu` puts extra/ binaries back when those packages update; re-run the script. ffmpeg/zlib are opt-in: `bash system/scripts/rebuild-v3.sh ffmpeg`.

### PhotoGIMP (GIMP Photoshop layout)

Optional [PhotoGIMP](https://github.com/Diolinux/PhotoGIMP) patch on pacman **gimp** (`packages/pacman.txt`). Install/reapply:

```bash
bash provision/scripts/install-photogimp.sh
```

Verifies `PHOTO_SHA256` before unpacking, maps the upstream `3.0` config tree into the live dir (`~/.config/GIMP/3.2` on GIMP 3.2.x), skips stale `pluginrc`, bumps `config-version`, also patches Flatpak GIMP config when `org.gimp.GIMP` is installed, rewrites the PhotoGIMP `.desktop` `Exec` to native `gimp` (upstream zip is Flatpak/`gimp-3.0`-only), hides stock `gimp.desktop`, installs icons, and backs up existing config to `~/GIMP-<ver>-backup-YYYYMMDD`. Launch: app menu **PhotoGIMP**, or `gimp`.

### Dash2Dock Animated

Animated GNOME dock ([Dash2Dock Lite](https://github.com/icedman/dash2dock-lite) / EGO #4994). AUR `gnome-shell-extension-dash2dock-lite` is stale — install from EGO:

```bash
bash desktop/scripts/install-dash2dock.sh
```

UUID `dash2dock-lite@icedman.github.com` is in `desktop/gnome/extensions.txt` and `desktop/gnome/dconf/user.conf`. `install-dash2dock.sh` delegates the SHA-256-verified EGO download and Shell 51 `metadata.json` patch to `desktop/scripts/fetch-gnome-extensions.sh --only dash2dock-lite@icedman.github.com` (unofficial patch — may still break). Caffeine, Blur My Shell, Status Tray, Tiling Assistant, and the rest of the Full pack also install with pinned SHA-256 checksums via `desktop/scripts/fetch-gnome-extensions.sh` (`GNOME_EXT_FETCH=1 bash desktop/scripts/install-extensions.sh`). Custom OSD and Restart To get the same Shell 51 metadata patch when upstream lags. **Wayland:** log out → log in (`Meta.restart` is disabled). Prefs: `gnome-extensions prefs dash2dock-lite@icedman.github.com`.

### Shortcuts

Shell functions (`fe`, `rge`, `gai`, `fcd`, …), `Ctrl+R` / `Ctrl+T` / `Alt+C`, terminal and GNOME keys: [desktop/gnome/keybindings.md](desktop/gnome/keybindings.md). Modern aliases (when installed): `eza`, `bat`, `rg`, `fd`, `dust`, `duf`, `delta`, etc.

Disposable Kali lab (libvirt overlay): `kali-up` (isolated) / `kali-up-nat` / `kali-up-lan` (NAT + physical RJ45) / `kali-lan` / `kali-lan-check` / `kali-wipe` / `kali-stop` / `kali-st` / `kali` — see [keybindings](desktop/gnome/keybindings.md#disposable-kali) and [fresh-install RE guide](docs/fresh-install-coding-re.md#disposable-kali). NAT needs `virbr0` in firewalld **libvirt** zone (`firewalld-lab-zones.sh`). Physical LAN uses macvtap on `KALI_LAN_IFACE` (default `enp0s31f6`, else the first wired NIC) → guest eth1 (`KALI_LAN_PROBE` overrides the `lan-check` ping target, default `192.168.8.1`). macvtap needs a wired NIC; Wi-Fi-only hosts (T14s without a USB Ethernet adapter) can use isolated or NAT only.

### Starship

Based on the [Gruvbox Rainbow](https://starship.rs/presets/gruvbox-rainbow) layout with Nerd Font symbols and two built-in palettes: `gruvbox_dark` (default) and `secops`. Config: `stow/starship/.config/starship.toml`. Switch across Starship, Fastfetch, btop, Ghostty, and Alacritty with `rice-theme <gruvbox|secops>` (or Fastfetch-only presets via `ff-preset`).

Optional older **Crampack** presets (not in this repo):  
`bash <(curl -fsSL "https://git.new/crampack-sh")`

---

## 🛠️ Repository Structure

```text
dotfiles/
├── install.sh           # Top-level Stage B orchestrator (TUI/GUI menu + selective sections)
├── stow-only.sh         # No-root $HOME stow entrypoint
├── uninstall.sh         # Safe selective uninstaller (default: user units/stow/ai; --all for /etc)
├── Makefile             # Task runner (make ci, test, lint, check, drift, fix, uninstall, vm-b)
├── stow/                # Pure deployable $HOME GNU Stow packages only
│   ├── bash/ zsh/       # shells; shared .shell-* under zsh/
│   ├── containers/      # rootless Podman containers.conf + storage.conf
│   ├── privacy/         # telemetry opt-out environment.d
│   ├── kitty/ ghostty/ alacritty/ contour/
│   ├── nvim/ starship/ atuin/ git/ vscode/ cursor/ antigravity/
│   ├── fastfetch/ btop/ htop/ continue/ flutter/ npm/
│   └── applications/ gnome-text-editor/ proton-vpn/ tmp-cleanup/ pacman/ …
├── system/              # Root-owned /etc trees (etc/, gdm/etc/, zram/etc/), templates/, scripts/
├── ai/                  # AI constitution (rules/), host skills (skills/), lib/, scripts/
├── desktop/             # GNOME dconf/extensions/keybindings (gnome/), lib/, scripts/
├── security/            # Browser policies/prefs (browsers/), lib/, scripts/ (firewall, VPN, DNS, privacy, secrets)
├── labs/                # Containerfiles (lab-triage/re/android/web/capture), MCP example, lib/, scripts/
├── provision/           # Stage B installation/provisioning libs (lib/) and subsystem installers (scripts/)
├── builds/              # Optional local PKGBUILDs (st/) and build scripts (scripts/build-st.sh)
├── packages/            # Package manifests (pacman.txt, flatpak.txt, aur.txt, agent-skills*.txt, …)
├── profiles/            # Machine profiles (thinkpad-p15, thinkpad-t14s, laptop, p15)
├── scripts/             # Diagnostics & curl-able entrypoints (check.sh + check.d/, drift.sh, validate-configs.sh, lint-docs.sh, list-stow-files.sh, minimal-stow.sh, arch-install*.sh)
├── t14s-arch-install/   # Canonical Stage A Arch ISO installer (install.sh, lib/, tests/)
├── docs/                # hardened-arch-gnome.md, fresh-install-coding-re.md, SECURITY-AUDIT.md
├── tests/               # Smoke & unit tests (*.test.sh, CI)
└── .github/             # CI (stow inventory, bash -n, ShellCheck, tests/, Stage A tests, markdownlint)
```

Domain ownership keeps `stow/` strictly for deployable `$HOME` packages, isolates root-owned `/etc` trees under `system/`, consolidates AI tooling under `ai/`, and separates orchestration (`install.sh`, `stow-only.sh`, `provision/`) from subsystem implementations. See [CONTRIBUTING.md](CONTRIBUTING.md) for the full subsystem script map.

---

## 📚 Documentation

| Document | Description |
|----------|-------------|
| [README.md](README.md) | Overview, shell setup, installation |
| [CHANGELOG.md](CHANGELOG.md) | Version history |
| [CONTRIBUTING.md](CONTRIBUTING.md) | Contribution guidelines |
| [docs/hardened-arch-gnome.md](docs/hardened-arch-gnome.md) | Full Arch + GNOME guide — dual-host Stage A + firewalld |
| [docs/fresh-install-coding-re.md](docs/fresh-install-coding-re.md) | Purpose stacks (coding / RE / malware lab); lab-re + Stage B configure |
| [docs/SECURITY-AUDIT.md](docs/SECURITY-AUDIT.md) | Security audit of this repository (2026-11-16) |
| [t14s-arch-install/](t14s-arch-install/README.md) | Canonical Stage A ISO installer (T14s 21CQ/21CR, P15 20SU, generic x86_64) |
| [desktop/gnome/keybindings.md](desktop/gnome/keybindings.md) | Shell aliases and useful shortcuts |

---

## 📦 Installation & Setup

### 0. Bare-metal Arch install (Stage A, from the ISO)

**Canonical Stage A:** **[t14s-arch-install/](t14s-arch-install/README.md)**
(`HW_PROFILE=t14s|p15|generic`, TUI/DRYRUN/answers). Seeds **firewalld** (`nftables`,
default zone `drop`); optional P15 `ollama-cuda` on `127.0.0.1:11434`.

```bash
# Direct Stage A installer (from Arch ISO, UEFI, root):
bash <(curl -fsSL https://raw.githubusercontent.com/HelllGuest/dotfiles/main/t14s-arch-install/install.sh)

# Thin profile wrappers (hand off to the same in-repo installer):
bash <(curl -fsSL https://raw.githubusercontent.com/HelllGuest/dotfiles/main/scripts/arch-install-t14s.sh)  # HW_PROFILE=t14s
bash <(curl -fsSL https://raw.githubusercontent.com/HelllGuest/dotfiles/main/scripts/arch-install-p15.sh)   # HW_PROFILE=p15
bash <(curl -fsSL https://raw.githubusercontent.com/HelllGuest/dotfiles/main/scripts/arch-install.sh)       # DMI detect
```

Manual phases: [docs/hardened-arch-gnome.md](docs/hardened-arch-gnome.md).
Rehearse: `provision/scripts/arch-install-vmtest.sh`. Then **1. Full Bootstrap** (Stage B).

### 1. Full Bootstrap (Recommended)
Installs packages, stows configs into `$HOME`, installs `system/` into `/etc` as root-owned files, restores GNOME settings, and runs health checks. Run as your desktop user (**not** `sudo ./install.sh`; it rejects `EUID == 0`).

On an interactive TTY, `./install.sh` opens a **TUI menu** (`dialog` / `whiptail` / `plain`, shared via `provision/lib/ui-menu.sh`) with presets (Full, Custom checklist, Core, Dotfiles & desktop, AI & RE, Stage B modules, Health check). Non-TTY sessions (CI / headless VM) and `--all` run the full default install with no prompts. A GNOME GUI mode (`zenity`) is available via `--gui` or the stowed **Dotfiles Installer** app-grid launcher (`dotfiles-installer.desktop`).

```bash
./install.sh                              # interactive TUI menu on TTY (full install on non-TTY)
./install.sh --gui                        # GNOME GUI dialogs (zenity)
./install.sh --all                        # full default install without prompts (alias: -y / INSTALL_ALL=1)
./install.sh --only stow,desktop,check    # run only selected sections (no menu)
./install.sh --skip ai,apps               # run defaults except listed sections
./install.sh --list                       # list all section names
# Optional: run Stage B TUI modules during full install (fails hard if a module fails):
# CONFIGURE=1 ./install.sh --all
# Headless / serial: CONFIGURE=1 CONFIGURE_UI=plain ./install.sh --all
# Skip foxcage / ollama / theme: SKIP_FOXCAGE=1 SKIP_OLLAMA=1 SKIP_THEME=1 ./install.sh --all
```

Machine profiles run in `./install.sh` via `provision/scripts/apply-profile.sh` **after** `packages/pacman.txt` (exactly one profile): `profiles/$(hostname).sh` if it exists, otherwise `provision/scripts/detect-profile.sh` (ThinkPad P15 → `thinkpad-p15`, ThinkPad T14s Gen 3 AMD 21CQ/21CR → `thinkpad-t14s`, other ThinkPads/laptop chassis → `laptop`). Pacman first so Optimus/NVIDIA packages exist before `thinkpad-p15` enables services and rebuilds UKIs (GPU packages in `packages/pacman.txt`: the Intel packages are skipped on the AMD T14s, and the NVIDIA packages (`nvidia-open-dkms`, `nvidia-prime`, `nvidia-utils`, `egl-wayland`) are installed only when `has_nvidia_gpu` finds an NVIDIA display device on PCI, so the T14s, VMs and other laptops skip the NVIDIA stack and its DKMS builds). There is no `nvidia.sh`; Optimus setup is inside `profiles/thinkpad-p15.sh`.

ThinkPad system configs (kernel cmdline templates, sleep, Wayland env, units) live in `system/` and are installed by `system/scripts/system-setup.sh` as **root-owned regular files**, never stow symlinks (re-run it after editing `system/`). Why, and how the cmdline UUID is handled: [hardened guide — `system/` files](docs/hardened-arch-gnome.md#kernel-cmdline--system-files-installed-not-stowed). On **T14s Gen 3 AMD**, check `cat /sys/power/mem_sleep`, `lscpu | grep -i ryzen`, `grep -E 'amd_iommu|amd_pstate' /proc/cmdline`, and charge thresholds under `/sys/class/power_supply/BAT*/charge_control_*_threshold`. On **P15**, verify Optimus/`prime-run` after reboot (`lspci -nnk -d 10de:`, charge 70–80). Installer + profile pull `mesa` / `vulkan-radeon` / `fprintd` (libva via mesa) on AMD; P15 Stage A (`arch-install-p15.sh` or `t14s-arch-install` `HW_PROFILE=p15`) seeds NVIDIA Optimus + optional ollama-cuda, and `profiles/thinkpad-p15.sh` refreshes it.

#### Script execution order (fresh machine)

**Stage A — from the Arch ISO (bare metal):**
```text
# Canonical: t14s-arch-install/install.sh (HW_PROFILE=t14s|p15|generic)
# Thin wrappers (scripts/arch-install{,-t14s,-p15}.sh) only hand off — no second body
provision/scripts/arch-install-vmtest.sh   # optional UEFI VM rehearsal (host disks untouched)
scripts/arch-install-t14s.sh     # → HW_PROFILE=t14s
scripts/arch-install-p15.sh      # → HW_PROFILE=p15
scripts/arch-install.sh          # → DMI detect / TUI radio
→ reboot, remove ISO
```

**Stage A½ — enable Secure Boot (optional, after first boot works with SB disabled in BIOS):**
```text
BIOS → clear Secure Boot keys → Setup Mode   # required; enroll fails if Setup Mode is off
sudo sbctl sign -s /boot/vmlinuz-linux{,-lts,-hardened}   # if sbctl verify still lists them
sudo sbctl enroll-keys -m          # -m keeps Microsoft keys (Windows on shared ESP)
BIOS → Secure Boot → Enabled
sbctl status && sbctl verify
```

**Stage B — first boot (log into GNOME, open terminal, then):**
```text
git clone https://github.com/HelllGuest/dotfiles.git ~/dotfiles
cd ~/dotfiles
bash provision/scripts/p15-dotfiles-preflight.sh   # P15 only — optional readiness check
bash provision/scripts/configure.sh                # modular TUI/GUI (--gui for zenity; labs/AI/rice/firewalld)
# interactive bootstrap menu (or --gui / --all / --only …):
./install.sh                             # TTY opens TUI menu; --all runs full bootstrap (needs GNOME session)
# hostname p15 → profiles/p15.sh → thinkpad-p15 (Optimus). Or re-run:
# bash profiles/thinkpad-p15.sh
exec zsh
reboot                                   # UKI must embed nvidia_drm.modeset + nouveau blacklist
# after reboot (P15): expect Kernel driver in use: nvidia
lspci -nnk -d 10de: | grep -A2 'Kernel driver'
prime-run nvidia-smi -L
system/scripts/thinkpad-charge-thresholds.sh  # tmpfiles + late-boot service; profile / install-re-extras call it
```

#### How to: `configure.sh` (Stage B TUI)

UI backend (shared with `install.sh` in `provision/lib/ui-menu.sh`): auto-detects
**dialog** → **whiptail** → **plain** on the TTY (Arch often has whiptail only —
`pacman -S dialog` optional), or **zenity** GUI with `--gui` / `CONFIGURE_UI=gui`.
Force with `--tui|--gui|--plain` or `CONFIGURE_UI=plain|tui|dialog|whiptail|gui|zenity`
(use `plain` on serial / CI / no TTY).
Theme matches Stage A (blue screen, cyan chrome, backtitle `Dotfiles configure · Stage B`).
Interactive runs open an archdi-style **main menu** (Modules / Profile / Quit) that
loops until Quit (plain menu: Ctrl-D quits, a bad number asks again).
`CONFIGURE_ONCE=1` (what `./install.sh` sets) does one checklist pass then exits. Module runs show a UTF-8/`#` progress bar (`provision/lib/progress.sh`);
`./install.sh` `run_step` uses the same bar. Checklist Cancel returns to the menu
(or aborts in one-shot mode). Selected modules **fail-fast** (a failing module
stops the script; no silent `|| true`).

| Tag | Default | Runs |
|-----|---------|------|
| `SETUP_FIREWALLD` | on | `firewalld-lab-zones.sh` → drop + `virbr0`/`libvirt` + `virbr-malware`/`lab-malware` (iface + `192.168.200.0/24`) |
| `APPLY_PROFILE` | off | `apply-profile.sh` |
| `SETUP_OLLAMA` | **on for P15 (20SU)**; off on T14s | `ollama-setup.sh` (skipped with msg if not P15) |
| `SETUP_LABS` | off | `labs-setup.sh` (triage/re/android/web images) |
| `SETUP_DETONATE` | off | `lab-detonate.sh setup` (capture + VMs; PolarProxy only with `POLARPROXY_SHA256=<verified sha256>`) |
| `SETUP_AI` | off | `ai-stack-setup.sh` (Headroom/`hr-*`, Ponytail, Continue FIM; **not** Caveman — full `./install.sh` already did cores + extras + P15 ollama) |
| `SETUP_RICE` | off | `rice-setup.sh` (Gruvbox / SecOps rice + lock-screen notifications off) |

```bash
bash provision/scripts/configure.sh                      # TUI menu loop (dialog/whiptail/plain)
bash provision/scripts/configure.sh --gui                # GNOME GUI dialogs (zenity)
CONFIGURE_ONCE=1 bash provision/scripts/configure.sh     # one checklist (install.sh)
CONFIGURE_UI=plain bash provision/scripts/configure.sh   # serial: plain menu loop
CONFIGURE_UI=plain bash provision/scripts/configure.sh </dev/null   # no TTY: one-shot, defaults
# Re-run anytime; SETUP_FIREWALLD is safe to repeat.
```

Full `./install.sh` still installs Caveman + Ponytail. `SETUP_AI` alone is
Ponytail-oriented (complementary hooks; no duplicate caveman install).

#### How to: ops / privacy kits

Packages land from `packages/pacman.txt` on `./install.sh`: `pacman-contrib`,
`mat2`, `perl-image-exiftool` (`exiftool`), `bleachbit`, `usbguard`,
`dnscrypt-proxy`. Boot screen: `bootvine` (official repo; a live tree of
systemd jobs instead of scrolling log lines). `./install.sh` enables
`bootvine.service` and `bootvine-shutdown.service` for the boot after the root
is unlocked and for shutdown. It does not add the `sd-bootvine` initrd hook, so
the LUKS prompt stays the stock one. Disable: `sudo systemctl disable
bootvine.service bootvine-shutdown.service`.

```bash
# Auto on install / post-update (SKIP_OPS_HYGIENE=1 to skip):
bash security/scripts/ops-hygiene.sh
#   paccache -rk2 · flatpak uninstall --unused · enable paccache.timer

mat2 ./report.pdf          # strip metadata before share/upload
exiftool ./photo.jpg       # inspect / edit EXIF
bleachbit                  # GUI junk cleaner

# Opt-in (do not enable blind on remote hosts):
bash security/scripts/usbguard-setup.sh   # allowlist plugged devices, then enable
bash security/scripts/dnscrypt-setup.sh   # dnscrypt-proxy on 127.0.0.1/::1 + NM DNS
# Pins all NM DNS to 127.0.0.1 via 90-dnscrypt-global-dns.conf (tailnet
# *.ts.net → 100.100.100.100). Bypasses Proton NetShield; DNS fails if
# dnscrypt-proxy stops. Opt out of the pin: SKIP_NM_GLOBAL=1.
```

`check.sh` soft-probes these (○ until packages/services are present). Plain DNS
override without encrypt: `bash security/scripts/network-dns-setup.sh` (or `--all-wifi`);
it skips bridge/tun/vpn ifaces (`virbr0`, `docker0`, …) so one bad connection
does not abort the rest.

#### How to: firewalld lab zones / `lab-malware`

```bash
bash security/scripts/firewalld-lab-zones.sh
# or only the malware zone:
source security/lib/lab-malware-zone.sh && ensure_lab_malware_zone
```

Expected zones:

```text
default zone: drop
virbr0          → libvirt          (kali-disposable / NAT guests)
virbr-malware   → lab-malware      (iface + source 192.168.200.0/24; DROP; no masq/forward)
```

`virbr-malware` is defined with `<dns enable="no"/>` and
`zone="lab-malware"` on the bridge (so libvirt does not reclaim it into the
stock `libvirt` zone). Libvirt's dnsmasq only serves DHCP (`67/udp`, allowed in
`lab-malware`) and advertises `192.168.200.1`
as the guest's DNS server. Nothing answers on `:53` until INetSim runs
(`lab-detonate.sh`), so lookups never reach real DNS. The zone has no ICMP
rule: guests cannot ping the gateway; test with a port instead.

`ensure_lab_malware_zone` (shared by `firewalld-lab-zones` + `lab-detonate`) binds **both**
the interface and the `192.168.200.0/24` source, unbinds `virbr-malware` from
`libvirt`/`block`, and uses `sudo` (or direct `firewall-cmd` when already root).
Hosts upgraded before `zone="lab-malware"` on the bridge XML may still show the
iface under `libvirt` until `firewalld-lab-zones.sh` redefines the network.

```bash
sudo firewall-cmd --get-default-zone          # drop
sudo firewall-cmd --get-active-zones          # virbr-malware under lab-malware only
sudo firewall-cmd --permanent --zone=lab-malware --list-all
# expect: interfaces: virbr-malware; sources: 192.168.200.0/24; target: DROP; masquerade: no
#   ports include 21/tcp 25/tcp 53/udp 53/tcp 67/udp 80/tcp 443/tcp 10080/tcp 10443/tcp
ss -ulpn | grep '192.168.200.1:53'            # empty until INetSim runs (no libvirt DNS)
```

#### How to: Stage B on a Stage A qcow2

Needs `~/arch-vmtest/test-disk.qcow2` from `t14s-arch-install` `tests/vm-run.sh`,
KVM, and edk2 OVMF. Host mounts this repo read-only via 9p.

```bash
bash provision/scripts/vm-stageb-run.sh
# overrides: DISK=… GUEST_USER=t14svm GUEST_PASS=… LUKS_PASS=… RAM=4096
# two VMs at once: distinct WORK=… (logs, fifo) and SSH_PORT=… (host → guest :22)
```

Stage B always installs the GNOME stack from `pacman.txt`, so a Stage A run
without a desktop (`DESKTOP=N`) still ends with GNOME; there is no supported
no-desktop Stage B. Use `T14S_VM_DESKTOP=Y` (t14s-arch-install `tests/vm-run.sh`)
to rehearse the GNOME Stage A path as well.

Guest (`vm-stageb-guest.sh`): `CONFIGURE_UI=plain` + empty checklist line →
defaults (`SETUP_FIREWALLD` on), then `./install.sh` with
`SKIP_CONFIGURE=1`, `SKIP_FOXCAGE=1`, `SKIP_OLLAMA=1`, `SKIP_THEME=1`,
`GIT_SETUP_NONINTERACTIVE=1`, under `dbus-run-session` (dconf writes need a
session bus). `vm-stageb-run.sh` reuses Stage A's `OVMF_VARS.fd`. Temporary NOPASSWD is removed before RESULT.

| RESULT | Meaning | Harness exit |
|--------|---------|--------------|
| `PASS` | configure + install both 0 | 0 |
| `PASS_HEADLESS` | configure 0; install failed only on headless-expected checks (GNOME extensions, Zen `user.js`, zinit, Proton API, `t14s-selftest` bluetooth/pipewire) | 0 |
| `FAIL` | configure failed, any other install failure, or guest aborted | 1 |

Wait budget: 150 min (nested pacman is slow).

#### How to: `git-setup.sh` (identity / hooks)

```bash
bash desktop/scripts/git-setup.sh
GIT_SETUP_NONINTERACTIVE=1 bash desktop/scripts/git-setup.sh
```

Interactive: prompts for name/email, hooks, optional GPG/SSH signing.
Noninteractive when `GIT_SETUP_NONINTERACTIVE=1` **or** stdin is not a TTY:
skips prompts and enables the hooks template. Identity comes from
`GIT_USER_NAME` / `GIT_USER_EMAIL` or an existing config; with neither, it is
left unset (no built-in name/email) and the script prints how to set it.

Shared settings live in the tracked `stow/git/.config/git/config`. Machine-local
settings (name/email, signing key, credential helper, `templateDir`) go to
`~/.gitconfig`, which the script creates first, so running it never modifies
the repo. git reads both files; `~/.gitconfig` wins on conflicts.

#### How to: GNOME extension zips (`fetch-gnome-extensions.sh`)

```bash
GNOME_EXT_FETCH=1 bash desktop/scripts/install-extensions.sh
# or: bash desktop/scripts/fetch-gnome-extensions.sh [--only <uuid>]
```

Downloads and SHA-256-verifies all 11 EGO zips (Caffeine, Blur My Shell, 8 Full-pack, Dash2Dock). Safe to re-run. Enable via `install-extensions.sh`; Wayland needs log out → log in.

**Lab commands (run `firewalld-lab-zones.sh` before `labs-setup.sh` / configure `SETUP_FIREWALLD` + `SETUP_LABS`):**
```text
lab-triage | lab-re | lab-android | lab-web | lab-detonate | lab-mcp
```
`/work` safety guardrail (`labs/lib/lab-workdir.sh`): launching any `lab-*` wrapper or `lab-mcp` from `$HOME` (including the GNOME app-grid launchers `Lab RE` and `Lab Android`), `~/dotfiles`, hidden dirs under `$HOME`, `/srv/lab/samples`, system/runtime paths, or any directory holding a live socket prints `lab: refusing to mount <dir> as /work (<reason>). Using /srv/lab/out — cd into a project first.` and mounts `/srv/lab/out` as scratch `/work` instead. This is expected (not a failure) so container code cannot reach `~/.ssh`, `~/.gnupg`, or dotfiles. To work on a project, `cd` into its directory first (for example `cd ~/dev/app && lab-android`).

`lab-detonate.sh capture-up` keeps INetSim logs and captured SMTP/FTP/HTTP-POST data under `/srv/lab/capture` (`inetsim-data/`); the container runs read-only with minimal caps (`LAB_CAPTURE_BIND` overrides `192.168.200.1`). `lab-detonate.sh linux-define` seeds Alpine `nocloud` cloud-init (`DETONATE_LINUX_PASS`, default `detonate`) and powers off cleanly before taking the `clean` snapshot. PolarProxy starts only if its hash matches the one verified at setup. Interactive lab images build with rootless Podman using `--network=host` (pasta/slirp throttles multi-GB pacman pulls). `lab-capture` builds in rootful Podman via `lab-detonate.sh setup` so `capture-up`'s `sudo podman run` sees it; `lab-web` uses signed Arch `chromium`; `lab-android` shares persistent named volumes `lab-android-flutter` and `lab-android-sdk` with `lab-mcp.sh` and forwards the Wayland socket (with `XDG_RUNTIME_DIR`) only when it exists. On linux-hardened that needs `fuse-overlayfs` (in `pacman.txt`) and the stowed `containers` package (`storage.conf`); `bash scripts/check.sh` reports it under "Podman (rootless)".

**What `./install.sh` runs, in order:**
```text
reject EUID==0 (never sudo ./install.sh)
→ parse flags (--all/--gui/--tui/--plain/--only/--skip/--list) or open TUI/GUI menu on interactive TTY
→ sudo -v once + keep-alive (skipped for check-only runs; pkill -P then kill on EXIT; long AUR builds no longer time out sudo)
→ cleanup-input-overrides.sh
→ pacman -Syu packages/pacman.txt (one batch; on failure retried per package)
→ bootvine enable (bootvine.service + bootvine-shutdown.service)
→ apply-profile.sh (hostname e.g. p15, or detect-profile.sh — after packages so NVIDIA DKMS exists)
→ install-flatpaks.sh → install-fonts.sh
→ stow ($HOME; system/ via system-setup.sh installs makepkg x86-64-v3; skips zram & gdm)
→ install-aur.sh (after system-setup; bootstraps paru after `rustup default stable`; --sudoloop; per-package retry)
→ tmp-semgrep-cleanup.timer enable (user unit) → login shell → zsh (usermod, if not already)
→ fnm install/default/use 22 (default/use only if install succeeds) → atuin import → zram-setup.sh
→ gnome-session-setup.sh → location-setup.sh → gnome-console-setup.sh
→ gdm-setup.sh → theme-setup.sh (stock Adwaita; SKIP_THEME=1 skips) → git-setup.sh → nvim-setup.sh
→ sync-agent-skills.sh (creates agent dirs) → headroom-setup.sh
→ install-coding-agents.sh (OpenCode + Kimi + MCP; if npm)
→ install-caveman.sh (if npm) → install-ponytail.sh (if node) → install-android-ui-skills.sh (if npx)
→ install-ghidra-cli.sh (if ghidra)
→ install-obscura.sh (headless browser + MCP)
→ install-re-skills.sh (leanrea / RE playbooks / Android RE / Ghidra loop)
→ install-ecosystem-skills.sh (packages/agent-skills.txt; owner/repo or owner/repo:skill; if npx)
→ sync-agent-skills.sh → caveman OpenCode plugin refresh
→ ai-stack-setup.sh (AI_STACK_EXTRAS_ONLY=1: Continue FIM, P15 OpenCode↔ollama, hr-proxy)
→ ollama-setup.sh (P15 only; SKIP_OLLAMA=1 skips; no-op elsewhere)
→ install-photogimp.sh → install-foxcage.sh (if podman; SKIP_FOXCAGE=1 skips)
→ fetch-gnome-extensions.sh (Caffeine, Blur My Shell, 8 Full-pack, Dash2Dock) → install-extensions.sh
→ configure.sh one checklist pass (with CONFIGURE=1, --only configure, or custom checklist; SKIP_CONFIGURE=1 skips the hint)
→ privacy-hardener.sh (incl. browser-hardening.sh)
→ ops-hygiene.sh (paccache + flatpak unused + paccache.timer; SKIP_OPS_HYGIENE=1 skips)
→ firewalld-tailscale.sh (if tailscale) → check.sh → validate-configs.sh
```
Nothing is skipped quietly: every failed step, and every step whose prerequisite
from `pacman.txt` is missing (npm, npx, node, podman, ghidra, …), is listed at
the end and `./install.sh` exits 1. Only explicit `SKIP_*=1` opt-outs or
menu/`--only`/`--skip` section selection skip.
`check.sh` ("Install completeness") fails on any missing pacman/AUR/Flatpak
package, dock icon without an app, shortcut whose command is missing, or
listed extension that is not installed.

`check.sh` modes (`--post`, `--stage-a`, `--all`, `--drift` are read-only; `--fix` runs safe idempotent fixes then re-checks):

```bash
bash scripts/check.sh            # --post (default, what ./install.sh runs): Stage A
                                 # follow-ups (Secure Boot, sbctl signatures, first-boot
                                 # Flatpaks, t14s-selftest) + everything Stage B sets up
bash scripts/check.sh --stage-a  # Arch ISO install: runs t14s-arch-install
                                 # tests/host-check.sh (~80 checks), as root too if sudo is cached
bash scripts/check.sh --all      # both Stage A and Stage B
bash scripts/check.sh --drift    # package (pacman/AUR/Flatpak) & stow symlink drift
bash scripts/check.sh --fix      # safe idempotent fixes (stow, agentsync, browser/GNOME/tailscale), then --post
```

`--stage-a` uses the in-repo `t14s-arch-install/` directory (override via
`T14S_INSTALLER_DIR`). Its FAILs count only on the T14s Gen 3 AMD (21CQ/21CR), the
hardware `host-check.sh` targets; on other hosts they are shown as informational.

**Theme:** stock **Adwaita** (GTK + icons + empty User Themes name) via
`desktop/scripts/theme-setup.sh`. Extension UUIDs stay in
`desktop/gnome/dconf/user.conf` (Blur My Shell, Status Tray, Tiling Assistant,
and the rest). `desktop/gnome/dconf/*.conf` leave gtk-theme / icon / cursor and the
extension look trees unset; `backup-gsettings.sh` drops those from snapshots.
On apply it clears leftover Orchis greeter bits (`theme-sync.service`, Orchis user
theme copy, `~/.config/gtk-4.0` Orchis links) and hints if old `orchis-theme` /
`tela-icon-theme` / `bibata-cursor-theme-bin` packages remain. `check.sh`
verifies Adwaita keys only. Opt out: `SKIP_THEME=1`. GNOME Tweaks and Extension
Manager are installed from `pacman.txt`.

**Command-finished notifications:** kitty (`notify_on_cmd_finish`), Ghostty
(`notify-on-command-finish`) and GNOME Console (via `vte.sh`) notify natively when
a command over 15 s ends in an unfocused window (bash and zsh; the terminal is
detected as the shell's parent process); elsewhere (Alacritty, Contour, tmux,
nested shells) the shell hook sends `notify-send` (`CMD_NOTIFY_THRESHOLD`; the
native 15 s lives in the kitty/Ghostty configs).
Opt-in after install (not auto): `bash security/scripts/usbguard-setup.sh`,
`bash security/scripts/dnscrypt-setup.sh`. See
[How to: ops / privacy kits](#how-to-ops--privacy-kits).
REA backends: use `lab-re` (JDK21/Ghidra/jadx/rizin + `rea-agents@6.10.1`). Optional host MCP only:
`bash ai/scripts/install-rea.sh` (needs host JDK≥21).

> `system/scripts/tmp-to-disk.sh` is **not** part of this flow — `arch-install.sh` already
> puts `/tmp` on a disk-backed `@tmp` subvolume. It's only for retrofitting an
> **existing** machine that still has tmpfs `/tmp`.

### 2. Config Only (No Root)
Applies user-level symlinks only from `stow/` (first removes unmodified `/etc/skel` copies such as `.bashrc`, and the t14s-arch-install `~/.zshrc` / `starship.toml` seeds, that would block stow; lines appended to the seeded `.zshrc` move to `~/.zshrc.local`), then enables `tmp-semgrep-cleanup.timer`. Root-owned `/etc` trees live under `system/` (not `stow/`) and are installed by `install.sh` / `system/scripts/system-setup.sh`.
```bash
./stow-only.sh
```

### 2b. Uninstall
Safely removes dotfiles symlinks, user systemd units, and AI kit/hub links (unmodified rule copies + stock `~/.claude/CLAUDE.md` stub; unsets kit `core.hooksPath`) without deleting installed packages, GNOME `dconf` user settings, or personal data (`~/.ssh`, `~/.gnupg`, `~/.gitconfig`, browser profiles, secrets). Privileged `/etc` layers (`browsers`, `location`, `system`) are opt-in via `--all` or `--only`; non-interactive runs require `--yes` (`-y`) or `--dry-run` (`-n`).
```bash
./uninstall.sh --list                      # list all sections (default vs opt-in)
./uninstall.sh --dry-run                   # preview default user-level uninstall (units, stow, ai)
./uninstall.sh                             # interactive user-level uninstall (no sudo)
./uninstall.sh --all --dry-run             # preview full uninstall incl. browsers, location, system
./uninstall.sh --only stow,ai --yes        # non-interactive selective uninstall (or --skip ...)
```

### 3. zram config
Do **not** `stow -t / zram` (a symlink into `$HOME` breaks at early boot). `install.sh` runs `system/scripts/zram-setup.sh`, which copies a real file to `/etc/systemd/zram-generator.conf`. Re-run that script to refresh.

### 4. Dependencies
Key runtime dependencies (`scripts/check.sh` asserts binaries, shell tools, symlinks, fonts, optional AI, and Zen `user.js` when present; every `packages/pacman.txt` / `aur.txt` / `flatpak.txt` entry is checked under "Install completeness"):

**Core** (`check.d/10-core-tools.sh`): `stow`, `zsh`, `starship`, `nvim`, `kitty`, `ghostty`, `fastfetch`, `btop`, `htop`, `dconf`, `jq`. Also required by completeness: `flatpak` (every `flatpak.txt` app) and `zram-generator` (via `zram-setup.sh` → `/etc/systemd/zram-generator.conf`).

**Zsh:** zinit bootstraps on first launch; plugins load via `.zsh-plugins`

**Shell tools** (also asserted): `atuin`, `fzf`, `fd`, `ripgrep` (`rg`), `bat`, `eza`, `zoxide`, `direnv`, `git-delta` (`delta`). `fnm` (Node) and `rclone` are in `pacman.txt` but optional for `check.sh`.

**AI:** `./install.sh` installs the full stack: Headroom (`hr-claude` / `hr-cursor` / `hr-opencode` / `hr-agy` / `hr-proxy`), OpenCode + Kimi (opt-in pinned Gemini CLI / Codex via `install-coding-agents.sh`), Caveman `v4.2.0` (SHA-256) + Ponytail `v5.3.3` (`PONYTAIL_COMMIT` SHA), Continue FIM config, Obscura CDP/MCP, ecosystem + curated official + RE skills, and hub sync across Claude, Cursor, OpenCode, Kimi, Gemini CLI, Antigravity, Kiro, and Codex; on P15 also `ollama-setup.sh` (CUDA + qwen pulls; `SKIP_OLLAMA=1` opts out). Optional SHA-256-pinned RTK CLI compressor: `bash ai/scripts/install-rtk.sh`. `configure.sh` `SETUP_AI` runs `ai-stack-setup.sh` (Headroom/Ponytail/Continue; **not** Caveman). Modular re-run: `bash ai/scripts/ai-stack-setup.sh`

**Graphics (optional):** `gimp` + PhotoGIMP via `provision/scripts/install-photogimp.sh`

**Sandboxed browser (optional):** [foxcage](https://gitlab.com/grepular/foxcage) runs Firefox in a rootless Podman container (`provision/scripts/install-foxcage.sh`, pinned commit + SHA-256; needs Wayland, `podman`, `passt`, `xdg-dbus-proxy`, plus `fuse-overlayfs`, set as `mount_program` in `stow/containers` `storage.conf` because linux-hardened has no unprivileged overlayfs). `foxcage @tmp <url>` opens a throwaway cage. Not set as default browser; opt in with `xdg-settings set default-web-browser foxcage.desktop`.

**GNOME dock:** Dash2Dock Animated via `desktop/scripts/install-dash2dock.sh` (EGO; listed in `desktop/gnome/extensions.txt`)

**AUR** (via `install-aur.sh`, bootstraps `paru` if needed): `blesh-git`, `forgit`, `gnome-shell-extension-just-perfection-desktop`, `vscodium-bin` (settings in `stow/vscode/`), `flutter-bin`, `cursor-bin`, `antigravity-ide`

**Flatpaks** (via `install-flatpaks.sh`): Brave, Zen, Google Chrome, LibreWolf, Proton VPN, Android Studio, Sticky Notes. Chrome may be `--system` or `--user`; both satisfy `check.sh` / hardening presence checks. Browser telemetry debloat: `security/scripts/browser-hardening.sh` (Chrome = `chromium-base` + `chrome-extra`, which turns off Google AI features (AI Mode, Help Me Write, Gemini on pages, on-device model download); Brave = base + `brave-extra`; `check.sh` fails if the deployed Chrome/Brave policy differs from the repo; verify in `chrome://policy` / `brave://policy`; Zen `user.js` per real profile + Flatpak `systemconfig` + `/etc/firefox/policies` for native; LibreWolf upstream + `librewolf.overrides.cfg`). Launch Zen once before re-running hardening if profiles are new. `/etc` policy paths need sudo.

**Terminals:** `kitty` (primary: Super+Return, `xdg-terminals.list`, and `x-scheme-handler/terminal`), `ghostty`, optional `alacritty` / `contour`, plus `gnome-console` (kgx). Rice: `bash desktop/scripts/rice-setup.sh` (Gruvbox default; switch with `rice-theme gruvbox|secops`; privacy: `show-in-lock-screen false`). Optional suckless `st`: `bash builds/scripts/build-st.sh` (`builds/st/`).

`desktop/scripts/gnome-console-setup.sh` sets Console dconf and registers `kitty.desktop` for `x-scheme-handler/terminal`. **Super+Return → kitty** is in `desktop/gnome/dconf/user.conf`.

Clipboard: selecting text auto-copies in kitty and ghostty (`copy_on_select`); in kitty, right-click also copies the selection (Shift+right-click extends it).

**Ghidra / RE AI:** prefer `lab-re` (container: JDK21 + Ghidra + jadx + rizin + `rea-agents@6.10.1`). Optional host: pacman `ghidra` + `bash ai/scripts/install-ghidra-cli.sh` / `bash ai/scripts/install-rea.sh` (needs JDK≥21). Extra skills: `bash ai/scripts/install-re-skills.sh`. Details: [fresh-install RE guide](docs/fresh-install-coding-re.md#ai-reverse-engineering-mcp--skills).

**GDM:** `desktop/scripts/gdm-setup.sh` copies greeter config to `/etc` (not stow — GDM cannot read `$HOME`), enables Wayland, compiles greeter dconf, and enables `gdm.service`. Greeter changes appear after **reboot** (or `sudo systemctl restart gdm`, which logs you out). Optional fingerprint: `system/scripts/fingerprint-setup.sh`.

**Git:** `stow/git/` + `desktop/scripts/git-setup.sh` — delta pager, rebase defaults, global ignore, optional hooks and signing. Headless: see [How to: git-setup.sh](#how-to-git-setupsh-identity--hooks). URL shorthands: `git clone gh:user/repo`.

**Neovim:** `desktop/scripts/nvim-setup.sh` — Lazy.nvim plugins, Treesitter parsers, Mason LSP on first launch. Leader = Space.

**GNOME session:** `desktop/scripts/gnome-session-setup.sh` — dconf profile, EGO fetch (Caffeine, Blur My Shell, Full-pack, Dash2Dock), and extension enable. Super+1–4 workspaces. Mouse/touchpad/keyboard use **stock GNOME defaults** (reset on session setup via `desktop/scripts/reset-input-defaults.sh`).

**Location spoofing:** `security/scripts/location-setup.sh` — static GeoClue coords in `/etc/geolocation` (home from gitignored `system/etc/geolocation.local`, else a Greenwich placeholder; VPN exit when `proton0` is up, retrying once on transient lookup failure and falling back to a neutral `0.0` placeholder so home coords never stay active during VPN). Panel extension `proton-vpn@helllguest` shows spoofed coords and **Sync spoofed location** (runs `pkexec vpn-location-sync sync`). Manual: `vpn-location-sync` or `sudo vpn-location-sync sync`. As root (dispatcher / `pkexec`) it only reads the root-owned copy in `/usr/local/share/vpn-location-sync/`, never your home directory, so re-run `location-setup.sh` after editing `geolocation.local`.

**Fonts:** Run `provision/scripts/install-fonts.sh` for top Nerd Fonts (JetBrains Mono, Meslo, FiraCode, Cascadia, Iosevka, etc.)

---

## 🛡️ Privacy & Security

We take a "quiet by default" approach:
- **GNOME Debloated:** Uses `gnome-shell` instead of the full `gnome` meta-package where possible.
- **Opt-out defaults:** `stow/privacy` → `~/.config/environment.d/90-telemetry-optout.conf` (GUI session + `.shell-exports`). `security/scripts/privacy-hardener.sh` covers GNOME, browsers, IDE/Claude merges (Cursor-only `cursor.general.*` on Cursor trees; strips leftovers elsewhere), Flutter `reporting=0`, Headroom/AI. Rice also sets `org.gnome.desktop.notifications show-in-lock-screen false`. Re-run after upgrades: `bash security/scripts/privacy-hardener.sh` / `bash desktop/scripts/rice-setup.sh`.
- **Ops / privacy kits:** `mat2` + `exiftool` (strip metadata before share), `bleachbit` (UI junk), `ops-hygiene.sh` (paccache + flatpak unused; hooked from `install.sh` / `post-update.sh`), opt-in `usbguard-setup.sh` / `dnscrypt-setup.sh`. Full howto: [ops / privacy kits](#how-to-ops--privacy-kits).

---

## Troubleshooting

| Symptom | Cause | Fix |
|---------|--------|-----|
| `Can't find an installed Node version matching …` on terminal open | **fnm** `--use-on-cd` + project `engines` / `.nvmrc` | `fnm install 22` or `fnm install` in project; or drop `--use-on-cd` in dotfiles |
| `$FZF_DEFAULT_OPTS: unknown action: copy-selection` | fzf 0.72 lacks `copy-selection` | Fixed in dotfiles; `exec zsh` / `exec bash` |
| Podman / foxcage / `lab-*`: `kernel does not support overlay fs: 'overlay' is not supported over btrfs`, or `podman build`: `mount overlay … operation not permitted` | linux-hardened has no unprivileged overlayfs (`CONFIG_OVERLAY_FS_UNPRIVILEGED` unset); the btrfs wording is misleading | `sudo pacman -S fuse-overlayfs`; `stow -R containers` (`storage.conf` sets `mount_program`) |
| `docker` tries Podman socket / `connect: no such file` | Stale `DOCKER_HOST` or Podman socket missing | `systemctl --user enable --now podman.socket`; new shell; or `FORCE_DOCKER=1` for real dockerd |
| `s2idle [deep]` / `mem_sleep_default=deep` after upgrades | Cmdline or BIOS drifted from s2idle pin | BIOS Sleep = Windows and Linux; `bash system/scripts/system-setup.sh`; reboot |
| Charge thresholds reset every boot | Missing tmpfiles **and/or** late-boot unit (`thinkpad_acpi` BAT* can appear after tmpfiles) | `bash system/scripts/thinkpad-charge-thresholds.sh` (optional `CHARGE_START`/`CHARGE_END`; installs tmpfiles + `thinkpad-charge-thresholds.service`) |
| `check.sh`: Chrome / Brave policies ✗ | `/etc` policy files missing or stale | `bash security/scripts/browser-hardening.sh` (needs sudo for `/etc`) |
| `evolution-data-server` / `wireless-regdb` (or any `pacman.txt` package) missing | Older `install.sh` fed `#` comment lines to pacman (`target not found: # …`), aborting the whole package step | Pull, then re-run `./install.sh` (comments are stripped now) |
| `unsafe path transition /etc` during `pacman` | `/etc` owned by user (old `gdm-setup.sh` used `rsync -a`) | `bash desktop/scripts/gdm-setup.sh` (restores root + 755), or `sudo chown root:root /etc && sudo chmod 755 /etc` |
| No inbound / wrong default zone | firewalld zones not applied or default ≠ `drop` | `bash security/scripts/firewalld-lab-zones.sh`; `sudo firewall-cmd --get-default-zone` |
| `virbr-malware` listed under `libvirt` / `block` | Bridge XML missing `zone=lab-malware`, or pre-bind leftover | `sudo bash security/scripts/firewalld-lab-zones.sh` (redefines + rebinds; needs a real TTY/polkit auth); [howto](#how-to-firewalld-lab-zones--lab-malware) |
| `lab-detonate status` hangs / waits for password | Old script used interactive `sudo` for firewalld/podman | Pull latest: status uses `sudo -n` + `virsh -c qemu:///system`; setup/capture still need sudo |
| `ERR virbr-malware missing` / `INVALID_ZONE: lab-malware` | `firewalld-lab-zones.sh` not run before `labs-setup.sh`, or older script started `virbr-malware` before creating `lab-malware` | `bash security/scripts/firewalld-lab-zones.sh && bash labs/scripts/labs-setup.sh` ([howto](#how-to-firewalld-lab-zones--lab-malware)) |
| `lab: refusing to mount /home/… as /work (home/root leak). Using /srv/lab/out` | Expected safety guardrail (`labs/lib/lab-workdir.sh`) blocks mounting `$HOME`, dotfiles, hidden dirs, samples, and socket dirs read-write; GNOME app-grid launchers start in `$HOME` | Not an error (`/srv/lab/out` is mounted as scratch `/work`); to mount a project, run `cd ~/path/to/project && lab-android` (or `lab-re` / `lab-triage` / `lab-web`) |
| Stage B VM hangs on Name/Email prompt | Interactive git setup on serial | Pull fixes; harness sets `GIT_SETUP_NONINTERACTIVE` |
| `DOTFILES_STAGEB_RESULT=PASS_HEADLESS` | Install failed only on checks that need a desktop session / launched apps | Expected on a headless VM; the guest log lists each ✗ |
| SSH blocked after lab-zones | drop zone has no 22/tcp | `sudo firewall-cmd --permanent --add-service=ssh && sudo firewall-cmd --reload` (only if you need SSH) |
| Spoof location sync does nothing | `vpn-location-sync` failed under `pkexec` | `bash security/scripts/location-setup.sh`; panel → Sync spoofed location |
| Touchpad clicks broken after old dotfiles | Legacy synaptics inhibit/udev | `bash desktop/scripts/cleanup-input-overrides.sh` (sudo), log out |
| Ghostty needs 2 clicks / fails from app grid | systemd `notify-reload` vs late SIGUSR2 ([#14394](https://github.com/ghostty-org/ghostty/discussions/14394)) | Stow `ghostty` drop-in sets `Type=notify`; `systemctl --user daemon-reload` |
| `headroom not installed` / `hr-claude` fails | Headroom not set up yet | `bash ai/scripts/headroom-setup.sh` |
| `headroom doctor`: Base URL unset | Current shell never sourced rc | `source ~/.zshrc` or new terminal; Claude Code uses settings.json |
| Headroom proxy down after reboot | No persistent user service, or not lingering | `systemctl --user enable --now hr-proxy.service` (repo unit, from `ai-stack-setup.sh`) or `headroom-default.service` (after `headroom install apply`); `loginctl enable-linger $USER` |
| Cursor not using Headroom | Base URL not set in IDE | Run `hr-cursor`, paste URL in Settings → Models; keep proxy terminal open |
| zstd/xz/lz4 back to extra/ after `-Syu` | Repo upgrade replaced v3 rebuilds | `bash system/scripts/rebuild-v3.sh` then `sudo pacman -U` if sudo -n fails |
| PhotoGIMP layout missing after GIMP update | Config dir version bump / patch not reapplied | `bash provision/scripts/install-photogimp.sh` |
| Dash2Dock missing after install | Wayland Shell has not reloaded | Log out → log in; or `bash desktop/scripts/install-dash2dock.sh` then logout |
| `proton-vpn@helllguest` missing from `gnome-extensions list` | Shell session cache stale / after uninstall | Log out → log in; never `gnome-extensions uninstall` a stowed UUID (deletes tree) |
| Proton VPN app stuck on "Loading app" | Server list fetch hung | `bash security/scripts/proton-seed-serverlist.sh` (or `--kill`) |
| `ghidra` CLI is the GUI / wrong Java | cargo bin shadows `/usr/bin/ghidra` | Use `ghidra-gui`; re-run `bash ai/scripts/install-ghidra-cli.sh` |
| ghidra-cli: every command fails, "GhidraCliBridge not found" / doctor: `DataType cannot be converted to List<DataType>` | Ghidra 12.2 removed `DataTypeManager.remove(DataType, TaskMonitor)`; ghidra-cli v0.2.2 (and upstream master) still calls it | `bash ai/scripts/install-ghidra-cli.sh` builds v0.2.2 from the pinned commit with that call patched to `remove(DataType)`; `ghidra doctor` → "bridge script compiles... OK" |
| ghidra-cli build: `openssl-sys` "only compatible with OpenSSL … 3" | Arch ships OpenSSL 4; ghidra-cli locks an older `openssl-sys` | `sudo pacman -S openssl-3`, then re-run `bash ai/scripts/install-ghidra-cli.sh` (it builds against the compat package) |

---

## 🧹 Maintenance

| Task | Command |
|------|---------|
| Task runner (`Makefile`) | `make help` (`make ci`, `make test`, `make check`, `make drift`, `make fix`, `make uninstall-dry`, `make uninstall`, `make update-full`, `make vm-b`, `make vm-clean`) |
| Uninstall | `./uninstall.sh [--dry-run\|--all\|--only …\|--yes]` (`make uninstall-dry` / `make uninstall`) |
| Full update | `bash provision/scripts/post-update.sh --full` (or `sudo pacman -Syu && ./install.sh && bash provision/scripts/post-update.sh`) |
| Minimal package install | `./install.sh --minimal` (or `MINIMAL_PACKAGES=1` / `SKIP_AI_IDES=1` / `SKIP_MOBILE_DEV=1` / `SKIP_RE_TOOLS=1`) |
| Encrypted local overrides | `bash security/scripts/secrets-bootstrap.sh init\|lock\|unlock\|status` (`~/.config/dotfiles/local.env`, `age` or OpenSSL PBKDF2) |
| Ops hygiene | `bash security/scripts/ops-hygiene.sh` — `paccache -rk2`, `flatpak uninstall --unused`, enable `paccache.timer` |
| Metadata strip | `mat2 file.pdf` / `exiftool file.jpg` (share/upload path) |
| UI junk cleaner | `bleachbit` (GUI) or `bleachbit -c …` |
| USB allowlist | `bash security/scripts/usbguard-setup.sh` (generates rules from plugged devices, then enables) |
| Encrypted DNS | `bash security/scripts/dnscrypt-setup.sh` (dnscrypt-proxy → 127.0.0.1; NM global DNS pins 127.0.0.1; tailnet names → MagicDNS) |
| Health check / drift / fix | `~/dotfiles/scripts/check.sh [--post\|--stage-a\|--all\|--drift\|--fix]` |
| Docs lint | `~/dotfiles/scripts/lint-docs.sh` (CI also runs this + secret scan + `all_stow_files.txt` + `bash -n` + `ShellCheck` + `tests/*.test.sh` + `t14s-arch-install/tests/` + Arch container smoke) |
| System files (`system/`) | `bash system/scripts/system-setup.sh` |
| Refresh stow inventory | `git add stow/…` then `bash scripts/list-stow-files.sh > all_stow_files.txt` (index only) |
| Location sync | `vpn-location-sync` or Proton VPN panel → Sync spoofed location |
| Optional st (suckless) | `bash builds/scripts/build-st.sh` |
| Agent skills sync | `bash ai/scripts/sync-agent-skills.sh` (hub → Claude/Cursor/OpenCode/Kimi/Gemini/Antigravity/Kiro/Codex) |
| OpenCode + Kimi (+ opt-in Gemini/Codex) | `bash ai/scripts/install-coding-agents.sh` (pinned npm CLIs + MCP; `INSTALL_GEMINI_CLI=1`, `INSTALL_GEMINI_EXTENSIONS=1`, `INSTALL_CODEX_CLI=1`) |
| RTK CLI compressor | `bash ai/scripts/install-rtk.sh` (SHA-256 pinned `rtk-ai/rtk` → `~/.local/share/rtk/rtk`) |
| Ecosystem skills | `bash ai/scripts/install-ecosystem-skills.sh` (`packages/agent-skills.txt`; optional `owner/repo:skill1,skill2`) |
| Caveman (`/caveman`) | `bash ai/scripts/install-caveman.sh` |
| Ponytail (`/ponytail`) | `bash ai/scripts/install-ponytail.sh` |
| Android UI skills | `bash ai/scripts/install-android-ui-skills.sh` (Compose + Material 3) |
| REA in lab-re | `lab-re` / rebuild `podman build -t localhost/lab-re labs/lab-re` (`rea-agents@6.10.1`) |
| REA host MCP (optional) | `bash ai/scripts/install-rea.sh` (needs JDK≥21; Hopper: `INSTALL_HOPPER=1`) |
| Labs / detonate / MCP | `bash security/scripts/firewalld-lab-zones.sh && bash labs/scripts/labs-setup.sh`; `lab-detonate` / `lab-mcp` |
| Stage B TUI / GUI | `bash provision/scripts/configure.sh [--gui]` ([howto](#how-to-configuresh-stage-b-tui)); `./install.sh --gui` (or **Dotfiles Installer** app-grid launcher) for selective bootstrap; `CONFIGURE_UI=plain` for serial/CI |
| Stage B VM harness | `bash provision/scripts/vm-stageb-run.sh` (uses qcow2 overlay over Stage A `test-disk.qcow2` by default; `OVERLAY=0` writes directly) |
| Terminal / CLI rice | `bash desktop/scripts/rice-setup.sh`; switch theme with `rice-theme` / `ff-preset` |
| Live lab/firewall health | See checklist below |
| Obscura (CDP/MCP) | `bash ai/scripts/install-obscura.sh` ([docs](https://docs.obscura.sh/)) |
| foxcage (Firefox in rootless Podman) | `bash provision/scripts/install-foxcage.sh` ([upstream](https://gitlab.com/grepular/foxcage)); then `foxcage`, `foxcage @tmp <url>`; `install.sh` runs it when `podman` exists (`SKIP_FOXCAGE=1` skips) |
| RE skills (leanrea, …) | `bash ai/scripts/install-re-skills.sh` |
| RE host extras (jadx, rizin, …) | `bash provision/scripts/install-re-extras.sh` |
| ghidra-cli | `bash ai/scripts/install-ghidra-cli.sh` |
| Legacy touchpad cleanup | `bash desktop/scripts/cleanup-input-overrides.sh` (sudo; old udev/inhibit only) |
| Secure Boot | `sbctl status && sbctl verify` (after `enroll-keys -m`; `mkinitcpio -P` re-signs UKIs via sbctl's hook) |
| Backup GNOME | `~/dotfiles/desktop/scripts/backup-gsettings.sh` |
| Move /tmp to disk | `sudo ~/dotfiles/system/scripts/tmp-to-disk.sh` then reboot (off RAM-capped tmpfs → btrfs `@tmp`) |
| Reload shell | `exec zsh` |
| Install project Node (fnm) | `fnm install 22` or `fnm install` inside project |
| Headroom (Claude / Cursor) | `bash ai/scripts/headroom-setup.sh`; optional persistent proxy: `hr-proxy.service` or `headroom-default.service`; then `hr-claude` / `hr-cursor` |
| x86-64-v3 rebuilds | `bash system/scripts/rebuild-v3.sh` |
| PhotoGIMP | `bash provision/scripts/install-photogimp.sh` |
| Dash2Dock | `bash desktop/scripts/install-dash2dock.sh` then log out/in (Wayland) |

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
# lab wrappers + lab-mcp refuse /, $HOME, its ancestors, hidden dirs under it
# and the dotfiles repo as /work (labs/lib/lab-workdir.sh; fallback /srv/lab/out):
cd ~ && source ~/.shell-functions && _lab_work_dir   # expect /srv/lab/out + refuse message

ss -tlnp | grep -E ':8787|:11434'
# 8787 → 127.0.0.1 only (Headroom). 11434 → 127.0.0.1 only on P15; absent on T14s.
gsettings get org.gnome.desktop.notifications show-in-lock-screen   # false

# Ops / privacy (soft — ○ until enabled):
command -v mat2 exiftool bleachbit paccache usbguard dnscrypt-proxy
systemctl is-enabled paccache.timer          # expect: enabled after ops-hygiene
systemctl is-active usbguard                 # active only after usbguard-setup
systemctl is-active dnscrypt-proxy           # active only after dnscrypt-setup

for t in ~/dotfiles/tests/*.test.sh; do bash "$t" || break; done   # KALI_TEST_NET=1 adds live Kali URL probe
bash ~/dotfiles/t14s-arch-install/tests/smoke.test.sh
bash ~/dotfiles/t14s-arch-install/tests/host-check.test.sh
```

---

## ⚖️ License
MIT © 2026
