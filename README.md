# 🌌 Arch Linux + GNOME Dotfiles

A clean, modular, and programmable dotfiles ecosystem optimized for **Arch Linux**, **GNOME 50**, and **ThinkPad** hardware. This setup focuses on visual cohesion, privacy hardening, and a frictionless developer workflow.

---

## 🚀 Key Features

- **Privacy Hardened:** Telemetry, usage reporting, and "phoning home" are disabled system-wide (GNOME, VS Code, .NET, etc.).
- **ThinkPad Optimized:** Hostname or hardware-detected profiles (e.g. `thinkpad-x1.sh`) with power-profiles-daemon, tablet auto-rotate, UKI re-signing for Secure Boot, and S3 deep-sleep tuning (thermal is firmware-managed). Battery charge thresholds are documented in `docs/hardened-arch-gnome.md` (manual `thinkpad_acpi` sysfs).
- **Elite-Tier Terminal:** Kitty & Ghostty with shared Zsh/Bash configs, real-time autocomplete, [Crampack](https://github.com/Noktomezo/CrampackForStarship) Starship prompt.
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

**History:** **atuin** powers `Ctrl+R` (sqlite, fuzzy). `↑`/`↓` stay on zsh prefix history-search (atuin up-arrow disabled). Config: `stow/atuin/.config/atuin/config.toml`.

**Shared files:** `.shell-{exports,aliases,functions,git}` sourced by both Zsh and Bash.

### Bash stack

- **ble.sh** (optional AUR) — syntax highlighting and autosuggestions for bash
- Same **fzf**, **zoxide**, **atuin**, **direnv**, **starship** as zsh
- **fzf** preview binds: `Ctrl+F` / `Ctrl+B` page preview; no global `Ctrl+Y` copy bind (fzf 0.72 lacks `copy-selection` — pass `--bind` per invocation if needed)

### Containers (Docker / Podman)

`.shell-exports` sets `DOCKER_HOST` only when the Podman socket exists (`$XDG_RUNTIME_DIR/podman/podman.sock`). Otherwise it is unset so the **Docker** daemon (`/var/run/docker.sock`) is used. Install Docker with `pacman -S docker docker-compose`, enable `docker.service`, and add your user to the `docker` group. After `newgrp docker` or a fresh login, `docker ps` should work without `sudo`.

For Podman-only setups, enable `podman.socket` and ensure the socket path above exists — see [docs/hardened-arch-gnome.md](docs/hardened-arch-gnome.md) Phase 17.

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

**Headroom** compresses tool output and context before it hits the model (70–95% savings). Installed user-local via **pipx** (`python-pipx` in `packages/pacman.txt`).

```bash
bash scripts/headroom-setup.sh    # install + MCP for Claude Code
```

| Command | What it does |
|---------|----------------|
| `hr-claude` | `headroom wrap claude` — proxy + launch Claude Code |
| `hr-cursor` | Start proxy; paste printed Base URL into Cursor → Settings → Models |
| `hr-proxy` | Proxy only on port `8787` (`HEADROOM_PORT` to override) |

Cursor does not read API base URLs from the shell — keep `hr-cursor` running in a terminal while you use Cursor. MCP: `headroom mcp install --agent claude` (Cursor MCP registrar not in Headroom 0.27 yet).

Antigravity CLI (`agy`) and Kiro are not in the stable Headroom agent matrix; use `hr-proxy` manually only if the tool supports a custom base URL.

### Key functions

| Command | Action |
|---------|--------|
| `fe` | Fuzzy file → nvim |
| `rge <pat>` | ripgrep → jump to line in nvim |
| `gai` / `gshow` / `gco` | Interactive git add / log / branch checkout |
| `fcd` | Fuzzy directory jump |
| `Ctrl+R` | atuin history search |
| `Ctrl+T` / `Alt+C` | fzf file / directory picker |

Modern aliases (when installed): `eza`, `bat`, `rg`, `fd`, `dust`, `duf`, `delta`, etc.

### Zsh plugins (legacy note)

Pacman `zsh-autocomplete` removed in v1.11 — replaced by zinit + fzf-tab.

### Starship

Uses the **Crampack** preset ([Noktomezo/CrampackForStarship](https://github.com/Noktomezo/CrampackForStarship)) with Nerd Font symbols. Config: `stow/starship/.config/starship.toml`.

```bash
~/dotfiles/scripts/install-starship-crampack.sh      # Standard (Nerd Font)
```

Presets: `1` Standard · `2` Plain text · `3` Emoji · `4` Full text

### Bash (`.bashrc` + `.inputrc`)

- **bash-completion** for commands (Tab; loaded at shell startup)
- **Prefix history search** on `↑` / `↓` via `.inputrc`
- **Menu-complete** on Tab
- Same shared exports, aliases, and functions as Zsh

---

## 🛠️ Repository Structure

```text
dotfiles/
├── stow/            # GNU Stow packages (symlinked to $HOME, or / for system/)
│   ├── bash/        # .bashrc, .inputrc
│   ├── zsh/         # .zshrc, .zsh-plugins, .shell-*
│   ├── system/      # /etc configs (i915, sleep, UFW, udev) — root stow
│   ├── zram/        # /etc/systemd/zram-generator.conf (requires root stow)
│   ├── git/         # Git config, delta, ignore
│   ├── atuin/       # Shell history (sqlite)
│   ├── gnome-session/ # GNOME user services (tablet handler, etc.)
│   ├── kitty/ ghostty/ # Terminals
│   ├── nvim/        # Neovim (Lazy.nvim)
│   ├── starship/    # Starship prompt
│   └── fastfetch/ proton-vpn/ tmp-cleanup/ …
├── browsers/        # Chromium base + per-browser policy extras; Zen user.js
├── packages/        # pacman.txt, flatpak.txt, browsers.txt, aur.txt
├── profiles/        # Hostname or hardware-detected tweaks (e.g. thinkpad-x1.sh)
├── scripts/         # Health checks, installers (lib/ for shared helpers)
├── gnome/           # GNOME settings (dconf) and extension lists
└── docs/            # Installation guides and system documentation
```

---

## 📚 Documentation

| Document | Description |
|----------|-------------|
| [README.md](README.md) | Overview, shell setup, installation |
| [CHANGELOG.md](CHANGELOG.md) | Version history |
| [CONTRIBUTING.md](CONTRIBUTING.md) | Contribution guidelines |
| [docs/hardened-arch-gnome.md](docs/hardened-arch-gnome.md) | Full Arch + GNOME install guide (ThinkPad X1) — automated by `scripts/arch-install.sh` |
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
```
It mirrors [docs/hardened-arch-gnome.md](docs/hardened-arch-gnome.md). Dry-run it
safely in a UEFI VM first — `scripts/arch-install-vmtest.sh` (OVMF qemu, serves the
installer over loopback, nothing on your host touched). Then continue with **1. Full
Bootstrap** below to apply the dotfiles.

### 1. Full Bootstrap (Recommended)
Installs packages, applies symlinks to `$HOME` and `/etc`, restores GNOME settings, and runs health checks.
```bash
./install.sh
```

Machine profiles run first in `./install.sh`: `profiles/$(hostname).sh` if it exists, otherwise `scripts/detect-profile.sh` picks from hardware (ThinkPad X1 → `thinkpad-x1.sh`, other ThinkPads/laptops → `laptop.sh`, discrete NVIDIA → also `nvidia.sh`).

ThinkPad-specific system configs (`i915`, kernel cmdline, Wayland env) live in `stow/system/` and are applied with `./install.sh`. After tuning, run `scripts/thinkpad-health.sh` and **reboot**.

#### Script execution order (fresh machine)

**Stage A — from the Arch ISO (bare metal):**
```text
scripts/arch-install-vmtest.sh   # optional: dry-run the installer in a UEFI VM
scripts/arch-install.sh          # LUKS + Btrfs(@tmp) + UKI(lts/hardened) + systemd-boot + sbctl + minimal GNOME
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
cd ~/dotfiles && ./install.sh        # requires GNOME session for dconf/extensions
exec zsh
scripts/thinkpad-health.sh → reboot
```

**What `./install.sh` runs, in order:**
```text
profiles/$(hostname).sh or detect-profile.sh → pacman < packages/pacman.txt
→ install-flatpaks.sh → install-aur.sh (bootstraps paru if needed) → install-fonts.sh
→ stow (/etc system + $HOME, skips zram & gdm) → atuin import → zram-setup.sh
→ gnome-session-setup.sh (dconf + ext enable) → location-setup.sh
→ gnome-console-setup.sh → gdm-setup.sh
→ git-setup.sh (interactive) → nvim-setup.sh
→ install-extensions.sh → check.sh → validate-configs.sh → privacy-hardener.sh (incl. browser-hardening.sh)
```

> `scripts/tmp-to-disk.sh` is **not** part of this flow — `arch-install.sh` already
> puts `/tmp` on a disk-backed `@tmp` subvolume. It's only for retrofitting an
> **existing** machine that still has tmpfs `/tmp`.

### 2. Config Only (No Root)
Applies user-level symlinks only. Skips `zram`, `system`, and `gdm` (require root — use `install.sh`).
```bash
./stow-only.sh
```

### 3. Stow zram manually
If `install.sh` could not stow the zram config (existing plain file in `/etc`):
```bash
sudo rm /etc/systemd/zram-generator.conf   # only if content matches stow/zram/
sudo stow -d ~/dotfiles/stow -t / zram
```

### 4. Dependencies
Key runtime dependencies (most surfaced by `scripts/check.sh`):

**Core:** `stow`, `zsh`, `starship`, `neovim`, `flatpak`, `rclone`, `jq`, `dart-sass`, `zram-generator`

**Zsh:** zinit bootstraps on first launch; plugins load via `.zsh-plugins`

**Shell tools:** `atuin`, `fzf`, `fd`, `ripgrep`, `bat`, `eza`, `zoxide`, `direnv`, `git-delta`, `fnm`

**AI (optional):** `python-pipx` + `headroom` via `scripts/headroom-setup.sh`; `claude` / `cursor` installed separately

**AUR** (via `install-aur.sh`, bootstraps `paru` if needed): `blesh-git`, `curlie`, `forgit`, GNOME shell extensions, `visual-studio-code-bin` (telemetry-off settings in `stow/vscode/`)

**Flatpaks** (via `install-flatpaks.sh`): Brave, Zen, Google Chrome, LibreWolf, Proton VPN, Android Studio. Browser telemetry debloat: `scripts/browser-hardening.sh` (Chrome/Brave `/etc` policies; Zen `user.js` per profile + `/etc/firefox/policies`; LibreWolf upstream-hardened). Launch Zen once before re-running hardening if profiles are new.

**Terminals:** `kitty` (primary), `ghostty`, `gnome-console` (kgx quick terminal)

Run `scripts/gnome-console-setup.sh` for Console dconf (scrollback, theme). **Super+Return → kitty** is set in `gnome/dconf/user.conf`.

**GDM:** `scripts/gdm-setup.sh` copies greeter config to `/etc` (not stow — GDM cannot read `$HOME`), enables Wayland, compiles greeter dconf, and enables `gdm.service`. Greeter changes appear after **reboot** (or `sudo systemctl restart gdm`, which logs you out). Optional fingerprint: `scripts/fingerprint-setup.sh`.

**Git:** `stow/git/` + `scripts/git-setup.sh` — delta pager, rebase defaults, global ignore, optional hooks and signing. URL shorthands: `git clone gh:user/repo`.

**Neovim:** `scripts/nvim-setup.sh` — Lazy.nvim plugins, Treesitter parsers, Mason LSP on first launch. Leader = Space.

**GNOME session:** `scripts/gnome-session-setup.sh` — dconf profile, extensions, and X1 Yoga tablet handler. Super+1–4 workspaces. Mouse/touchpad/keyboard use **stock GNOME defaults** (reset on session setup via `scripts/reset-input-defaults.sh`).

**Location spoofing:** `scripts/location-setup.sh` — static GeoClue coords in `/etc/geolocation` (home Dubai; VPN exit when `proton0` is up). Panel extension `proton-vpn@helllguest` shows spoofed coords and **Sync spoofed location** (runs `pkexec vpn-location-sync sync`). Manual: `vpn-location-sync` or `sudo vpn-location-sync sync`.

**Fonts:** Run `scripts/install-fonts.sh` for top Nerd Fonts (JetBrains Mono, Meslo, FiraCode, Cascadia, Iosevka, etc.)

---

## 🛡️ Privacy & Security

We take a "quiet by default" approach:
- **GNOME Debloated:** Uses `gnome-shell` instead of the full `gnome` meta-package where possible.
- **Zero Telemetry:** VS Code, GNOME usage stats, and technical reporting are disabled.
- **Opt-Out Defaults:** Global environment variables in `.shell-exports` disable telemetry for development tools.
- **Starship prompt:** Crampack preset in `stow/starship/` (optional: `scripts/install-starship-crampack.sh` to refresh from upstream).

---

## Troubleshooting

| Symptom | Cause | Fix |
|---------|--------|-----|
| `Can't find an installed Node version matching …` on terminal open | **fnm** `--use-on-cd` + project `engines` / `.nvmrc` | `fnm install 22` or `fnm install` in project; or drop `--use-on-cd` in dotfiles |
| `$FZF_DEFAULT_OPTS: unknown action: copy-selection` | fzf 0.72 lacks `copy-selection` | Fixed in dotfiles; `exec zsh` / `exec bash` |
| `docker` tries Podman socket / `connect: no such file` | Stale `DOCKER_HOST` or Podman socket missing | Current `.shell-exports` auto-picks; `unset DOCKER_HOST`; enable `docker.service` |
| `unsafe path transition /etc` during `pacman` | `/etc` owned by user, not root | `sudo chown root:root /etc && sudo chmod 755 /etc` |
| Spoof location sync does nothing | `vpn-location-sync` failed under `pkexec` | `bash scripts/location-setup.sh`; panel → Sync spoofed location |
| Touchpad clicks broken after old dotfiles | Legacy synaptics inhibit/udev | `bash scripts/cleanup-input-overrides.sh` (sudo), log out |
| `headroom not installed` / `hr-claude` fails | Headroom not set up yet | `bash scripts/headroom-setup.sh` |
| Cursor not using Headroom | Base URL not set in IDE | Run `hr-cursor`, paste URL in Settings → Models; keep proxy terminal open |

---

## 🧹 Maintenance

| Task | Command |
|------|---------|
| Full update | `sudo pacman -Syu && ./install.sh && bash scripts/post-update.sh` |
| Health check | `~/dotfiles/scripts/check.sh` |
| Location sync | `vpn-location-sync` or Proton VPN panel → Sync spoofed location |
| Legacy touchpad cleanup | `bash scripts/cleanup-input-overrides.sh` (sudo; old udev/inhibit only) |
| Secure Boot | `sbctl status && sbctl verify` (after `enroll-keys -m`; re-sign UKIs if you ran `mkinitcpio -P` manually) |
| Post-update sync | `~/dotfiles/scripts/post-update.sh` |
| Backup GNOME | `~/dotfiles/scripts/backup-gsettings.sh` |
| Move /tmp to disk | `sudo ~/dotfiles/scripts/tmp-to-disk.sh` then reboot (off RAM-capped tmpfs → btrfs `@tmp`) |
| Starship preset | `scripts/install-starship-crampack.sh` |
| Reload shell | `exec zsh` |
| Install project Node (fnm) | `fnm install 22` or `fnm install` inside project |
| Headroom (Claude / Cursor) | `bash scripts/headroom-setup.sh` then `hr-claude` or `hr-cursor` |

---

## ⚖️ License
MIT © 2026
