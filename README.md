# 🌌 Arch Linux + GNOME Dotfiles

A clean, modular, and programmable dotfiles ecosystem optimized for **Arch Linux**, **GNOME Shell 51**, and **ThinkPad** hardware. This setup focuses on visual cohesion, privacy hardening, and a frictionless developer workflow.

---

## 🚀 Key Features

- **Privacy Hardened:** Telemetry, usage reporting, and "phoning home" are disabled system-wide (GNOME, VS Code, .NET, etc.).
- **ThinkPad Optimized:** Hostname or hardware-detected profiles (`thinkpad-x1.sh`, `thinkpad-p15.sh`, `thinkpad-t14s.sh`, or `laptop.sh`) with power-profiles-daemon (or tuned + `tuned-ppd` on hosts from `t14s-arch-install`), UKIs signed for Secure Boot (sbctl), and a tracked **s2idle** sleep pin (`mem_sleep_default=s2idle`; pair BIOS Sleep State with **Windows and Linux**, not **Linux**/S3 — see `docs/hardened-arch-gnome.md`). X1 Yoga also gets tablet auto-rotate (`iio-sensor-proxy`). Thermal is firmware-managed. Charge window **70–80** via `scripts/thinkpad-charge-thresholds.sh` (tmpfiles + `thinkpad-charge-thresholds.service` for late BAT*; used by T14s profile + `install-re-extras.sh`).
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

* `stow/system/etc/makepkg.conf.d/99-x86-64-v3.conf` (via `scripts/system-setup.sh`)
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

UUID `dash2dock-lite@icedman.github.com` is in `gnome/extensions.txt` and `gnome/dconf/user.conf`. EGO zip still declares Shell ≤50; the install script patches `metadata.json` for **Shell 51** (unofficial — may still break). Other non-AUR zips (blur, caffeine, clipboard) install via `scripts/fetch-gnome-extensions.sh` (`GNOME_EXT_FETCH=1 bash scripts/install-extensions.sh`). **Wayland:** log out → log in (`Meta.restart` is disabled). Prefs: `gnome-extensions prefs dash2dock-lite@icedman.github.com`.

### Shortcuts

Shell functions (`fe`, `rge`, `gai`, `fcd`, …), `Ctrl+R` / `Ctrl+T` / `Alt+C`, terminal and GNOME keys: [gnome/keybindings.md](gnome/keybindings.md). Modern aliases (when installed): `eza`, `bat`, `rg`, `fd`, `dust`, `duf`, `delta`, etc.

Disposable Kali lab (libvirt overlay): `kali-up` (isolated) / `kali-up-nat` / `kali-up-lan` (NAT + physical RJ45) / `kali-lan` / `kali-wipe` / `kali-stop` / `kali-st` / `kali` — see [keybindings](gnome/keybindings.md#disposable-kali) and [fresh-install RE guide](docs/fresh-install-coding-re.md#disposable-kali). NAT needs `virbr0-up.service` + UFW virbr0 rules (kali `setup` / system-setup). Physical LAN uses macvtap on `KALI_LAN_IFACE` (default `enp0s31f6`) → guest eth1.

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
│   ├── system/      # /etc template (i915, sleep, UFW, udev, Wayland) → system-setup.sh
│   ├── containers/  # rootless Podman containers.conf
│   ├── privacy/     # telemetry opt-out environment.d
│   ├── zram/ gdm/   # templates → zram-setup.sh / gdm-setup.sh
│   ├── kitty/ ghostty/ alacritty/ contour/ foot/ rio/ wezterm/
│   └── nvim/ starship/ atuin/ git/ vscode/ cursor/ … 
├── browsers/        # chromium-base (+ brave-extra); zen; LibreWolf
├── packages/        # pacman.txt, flatpak.txt, aur.txt, re-extra.txt, thinkpad-t14s.txt, …
├── profiles/        # thinkpad-x1 | thinkpad-p15 | thinkpad-t14s | laptop | p15
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
| [docs/hardened-arch-gnome.md](docs/hardened-arch-gnome.md) | Full Arch + GNOME guide — `arch-install.sh` (X1) / `arch-install-t14s.sh` (21CQ/21CR) |
| [docs/fresh-install-coding-re.md](docs/fresh-install-coding-re.md) | Purpose stacks (coding / RE / malware lab); T14s note for AMD path |
| [gnome/keybindings.md](gnome/keybindings.md) | Shell aliases and useful shortcuts |

---

## 📦 Installation & Setup

### 0. Bare-metal Arch install (from the ISO)
For a fresh machine, the automated installer builds the whole hardened base —
LUKS2 (argon2id) + Btrfs subvolumes (incl. disk-backed `@tmp`) + `linux-lts`
(primary) / `linux-hardened` (fallback) Unified Kernel Images + systemd-boot +
`sbctl` Secure Boot + minimal GNOME — before you clone these dotfiles:
```bash
# from the Arch ISO (UEFI, as root). AUTO wipe, or MANUAL with EFI optional/reuse.
bash <(curl -fsSL https://raw.githubusercontent.com/HelllGuest/dotfiles/main/scripts/arch-install.sh)

# ThinkPad T14s Gen 3 AMD (21CQ/21CR) — same stack, AMD cmdline/hostname:
bash <(curl -fsSL https://raw.githubusercontent.com/HelllGuest/dotfiles/main/scripts/arch-install-t14s.sh)
```
Generic path mirrors [docs/hardened-arch-gnome.md](docs/hardened-arch-gnome.md).
Rehearse in a UEFI VM first — `scripts/arch-install-vmtest.sh` (OVMF qemu; host
disks untouched). T14s script in VM: `INSTALLER=arch-install-t14s.sh scripts/arch-install-vmtest.sh`
(confirm past the DMI warn). Then continue with **1. Full Bootstrap** below.

### 1. Full Bootstrap (Recommended)
Installs packages, stows configs into `$HOME`, installs `stow/system/` into `/etc` as root-owned files, restores GNOME settings, and runs health checks.
```bash
./install.sh
```

Machine profiles run in `./install.sh` via `scripts/apply-profile.sh` **after** `packages/pacman.txt` (exactly one profile): `profiles/$(hostname).sh` if it exists, otherwise `scripts/detect-profile.sh` (ThinkPad X1 → `thinkpad-x1`, ThinkPad P15 → `thinkpad-p15`, ThinkPad T14s → `thinkpad-t14s`, other ThinkPads/laptop chassis → `laptop`). Pacman first so Optimus/NVIDIA packages exist before `thinkpad-p15` enables services and rebuilds UKIs (on `thinkpad-t14s` AMD hosts, `./install.sh` skips the Intel/NVIDIA GPU packages in `packages/pacman.txt`). There is no `nvidia.sh`; Optimus setup is inside `profiles/thinkpad-p15.sh`.

ThinkPad system configs (`i915`, kernel cmdline, sleep, UFW, Wayland env) live in `stow/system/` and are installed by `scripts/system-setup.sh` as **root-owned regular files**, never stow symlinks (re-run it after editing `stow/system/`). Why, and how the cmdline UUID is handled: [hardened guide — `system/` files](docs/hardened-arch-gnome.md#kernel-cmdline--system-files-installed-not-stowed). After tuning on **X1**, run `scripts/thinkpad-health.sh` (i915-focused) and **reboot**. On **T14s Gen 3 AMD**, skip that script; check `cat /sys/power/mem_sleep`, `lscpu | grep -i ryzen`, `grep -E 'amd_iommu|amd_pstate' /proc/cmdline`, and charge thresholds under `/sys/class/power_supply/BAT*/charge_control_*_threshold` instead. Installer + profile pull `mesa` / `vulkan-radeon` / `fprintd` (libva via mesa).

#### Script execution order (fresh machine)

**Stage A — from the Arch ISO (bare metal):**
```text
scripts/arch-install-vmtest.sh   # optional: full UEFI VM install (host disks untouched)
scripts/arch-install.sh          # LUKS + Btrfs(@tmp) + UKI(lts/hardened) + systemd-boot + sbctl + minimal GNOME
scripts/arch-install-t14s.sh     # T14s Gen 3 AMD (21CQ/21CR): amd_iommu + amd_pstate + mesa/vulkan-radeon
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
./install.sh                             # requires GNOME session for dconf/extensions
# hostname p15 → profiles/p15.sh → thinkpad-p15 (Optimus). Or re-run:
# bash profiles/thinkpad-p15.sh
exec zsh
reboot                                   # UKI must embed nvidia_drm.modeset + nouveau blacklist
# after reboot (P15): expect Kernel driver in use: nvidia
lspci -nnk -d 10de: | grep -A2 'Kernel driver'
prime-run nvidia-smi -L
scripts/thinkpad-health.sh       # X1 only (i915); T14s: check amd_iommu/amd_pstate + mem_sleep
scripts/thinkpad-charge-thresholds.sh  # tmpfiles + late-boot service; profile / install-re-extras call it
```

**What `./install.sh` runs, in order:**
```text
cleanup-input-overrides.sh
→ pacman < packages/pacman.txt
→ apply-profile.sh (hostname e.g. p15, or detect-profile.sh — after packages so NVIDIA DKMS exists)
→ install-flatpaks.sh → install-aur.sh (bootstraps paru)
→ install-fonts.sh → stow ($HOME; system/ via system-setup.sh; skips zram & gdm)
→ fnm install/default 22 → atuin import → zram-setup.sh
→ gnome-session-setup.sh → location-setup.sh → gnome-console-setup.sh → ptyxis-setup.sh
→ gdm-setup.sh → git-setup.sh → nvim-setup.sh → headroom-setup.sh
→ sync-agent-skills.sh → install-coding-agents.sh (OpenCode + Kimi + MCP; if npm)
→ install-caveman.sh (if npm) → install-ponytail.sh (if node) → install-android-ui-skills.sh (if npx)
→ install-ghidra-cli.sh (if ghidra) → install-rea.sh (if npm)
→ install-obscura.sh (headless browser + MCP)
→ install-re-skills.sh (leanrea / RE playbooks / Android RE / Ghidra loop)
→ install-ecosystem-skills.sh (packages/agent-skills.txt; owner/repo or owner/repo:skill; if npx)
→ sync-agent-skills.sh → caveman OpenCode plugin refresh
→ install-photogimp.sh → install-foxcage.sh (if podman; SKIP_FOXCAGE=1 skips)
→ install-dash2dock.sh → install-extensions.sh
→ privacy-hardener.sh (incl. browser-hardening.sh)
→ check.sh → validate-configs.sh
```

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

**AI (optional):** `python-pipx` + `headroom` (`scripts/headroom-setup.sh`), OpenCode + Kimi Code (`scripts/install-coding-agents.sh`), Caveman `v4.1.0` (`scripts/install-caveman.sh`), Ponytail `v5.3.3` (`scripts/install-ponytail.sh`), Obscura CDP/MCP (`scripts/install-obscura.sh`), and `scripts/sync-agent-skills.sh` (mirrors `~/.agents/skills` + global `AGENTS.md`/`CLAUDE.md`/`GEMINI.md` across Claude Code, Cursor, OpenCode, Kimi, Gemini CLI, Antigravity, and Kiro)

**Graphics (optional):** `gimp` + PhotoGIMP via `scripts/install-photogimp.sh`

**Sandboxed browser (optional):** [foxcage](https://gitlab.com/grepular/foxcage) runs Firefox in a rootless Podman container (`scripts/install-foxcage.sh`, pinned commit + SHA-256; needs Wayland, `podman`, `passt`, `xdg-dbus-proxy`). `foxcage @tmp <url>` opens a throwaway cage. Not set as default browser; opt in with `xdg-settings set default-web-browser foxcage.desktop`.

**GNOME dock:** Dash2Dock Animated via `scripts/install-dash2dock.sh` (EGO; listed in `gnome/extensions.txt`)

**AUR** (via `install-aur.sh`, bootstraps `paru` if needed): `blesh-git`, `curlie`, `forgit`, GNOME shell extensions, `vscodium-bin` (settings in `stow/vscode/`)

**Flatpaks** (via `install-flatpaks.sh`): Brave, Zen, Google Chrome, LibreWolf, Proton VPN, Android Studio. Chrome may be `--system` or `--user`; both satisfy `check.sh` / hardening presence checks. Browser telemetry debloat: `scripts/browser-hardening.sh` (Chrome = `chromium-base` only; Brave = base + `brave-extra`; Zen `user.js` per real profile + Flatpak `systemconfig` + `/etc/firefox/policies` for native; LibreWolf upstream + `librewolf.overrides.cfg`). Launch Zen once before re-running hardening if profiles are new. `/etc` policy paths need sudo.

**Terminals:** `kitty` (primary; Super+Return), `ghostty`, optional stowed configs for `alacritty`, `contour`, `foot`, `rio`, `wezterm`, plus `gnome-console` (kgx) and `ptyxis`. Optional suckless `st`: `bash scripts/build-st.sh` (`builds/st/`).

Run `scripts/gnome-console-setup.sh` / `scripts/ptyxis-setup.sh` for Console/Ptyxis dconf. **Super+Return → kitty** is in `gnome/dconf/user.conf`.

Clipboard: selecting text auto-copies in kitty and ghostty (`copy_on_select`); in kitty, right-click also copies the selection (Shift+right-click extends it).

**Ghidra / RE AI:** pacman `ghidra` + `bash scripts/install-ghidra-cli.sh` (cargo CLI; host skill under `skills/ghidra-cli-host/`). GUI: `ghidra-gui` (cargo `ghidra` shadows `/usr/bin/ghidra`). REA MCP: `bash scripts/install-rea.sh`. Extra agent skills: `bash scripts/install-re-skills.sh`. Optional host tools: `bash scripts/install-re-extras.sh`. Details: [fresh-install RE guide](docs/fresh-install-coding-re.md#ai-reverse-engineering-mcp--skills).

**GDM:** `scripts/gdm-setup.sh` copies greeter config to `/etc` (not stow — GDM cannot read `$HOME`), enables Wayland, compiles greeter dconf, and enables `gdm.service`. Greeter changes appear after **reboot** (or `sudo systemctl restart gdm`, which logs you out). Optional fingerprint: `scripts/fingerprint-setup.sh`.

**Git:** `stow/git/` + `scripts/git-setup.sh` — delta pager, rebase defaults, global ignore, optional hooks and signing. URL shorthands: `git clone gh:user/repo`.

**Neovim:** `scripts/nvim-setup.sh` — Lazy.nvim plugins, Treesitter parsers, Mason LSP on first launch. Leader = Space.

**GNOME session:** `scripts/gnome-session-setup.sh` — dconf profile, Dash2Dock install, extensions, and X1 Yoga tablet handler. Super+1–4 workspaces. Mouse/touchpad/keyboard use **stock GNOME defaults** (reset on session setup via `scripts/reset-input-defaults.sh`).

**Location spoofing:** `scripts/location-setup.sh` — static GeoClue coords in `/etc/geolocation` (home Dubai; VPN exit when `proton0` is up). Panel extension `proton-vpn@helllguest` shows spoofed coords and **Sync spoofed location** (runs `pkexec vpn-location-sync sync`). Manual: `vpn-location-sync` or `sudo vpn-location-sync sync`.

**Fonts:** Run `scripts/install-fonts.sh` for top Nerd Fonts (JetBrains Mono, Meslo, FiraCode, Cascadia, Iosevka, etc.)

---

## 🛡️ Privacy & Security

We take a "quiet by default" approach:
- **GNOME Debloated:** Uses `gnome-shell` instead of the full `gnome` meta-package where possible.
- **Opt-out defaults:** `stow/privacy` → `~/.config/environment.d/90-telemetry-optout.conf` (GUI session + `.shell-exports`). `scripts/privacy-hardener.sh` covers GNOME, browsers, IDE/Claude merges (Cursor-only `cursor.general.*` on Cursor trees; strips leftovers elsewhere), Flutter `reporting=0`, Headroom/AI. Re-run after upgrades: `bash scripts/privacy-hardener.sh`.

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
| No network after boot; `ufw.service` failed | `/etc/ufw/before.rules` was a stow symlink into `$HOME` | `bash scripts/system-setup.sh` (installs real files, reloads ufw) |
| `ufw allow OpenSSH` → could not find profile | Arch UFW has no OpenSSH app profile (Ubuntu-only name) | `sudo ufw allow 22/tcp comment 'ssh'` then `sudo ufw reload`; enable `sshd` |
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
| REA (MCP + jadx) | `bash scripts/install-rea.sh` (Hopper: `INSTALL_HOPPER=1`) |
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

---

## ⚖️ License
MIT © 2026
