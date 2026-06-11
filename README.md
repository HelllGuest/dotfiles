# 🌌 Nord Cyberdeck: Arch + GNOME Dotfiles

A clean, modular, and programmable dotfiles ecosystem optimized for **Arch Linux**, **GNOME 50**, and **ThinkPad** hardware. This setup focuses on visual cohesion, privacy hardening, and a frictionless "Scandinavian Cyberdeck" aesthetic.

---

## 🚀 Key Features

- **Dynamic Theming Engine:** A palette-driven system (`JSON` + `SCSS`) that synchronizes colors across GTK 3/4, Terminals, Starship, and Neovim.
- **Privacy Hardened:** Telemetry, usage reporting, and "phoning home" are disabled system-wide (GNOME, VS Code, .NET, etc.).
- **ThinkPad Optimized:** Hostname-based machine profiles (e.g. `thinkpad-x1.sh`) with power-profiles-daemon, battery charge thresholds, tablet auto-rotate, and S3 deep-sleep tuning (thermal is firmware-managed).
- **Elite-Tier Terminal:** Kitty & Ghostty with shared Zsh/Bash configs, real-time autocomplete, [Crampack](https://github.com/Noktomezo/CrampackForStarship) Starship prompt, and dynamic theming.
- **Neovim (Lazy.nvim):** A modular Lua configuration that imports your system-wide palette on the fly.

---

## 🐚 Shell Configuration

Zsh is the primary shell. Bash is fully supported for scripts and fallback sessions.

### Shared files (`stow/zsh/`)

| File | Purpose |
|------|---------|
| `.shell-exports` | Environment variables (editor, pager, Android SDK, telemetry opt-outs) |
| `.shell-aliases` | Shared aliases (`ts`, `tt`, `v`, `as`, etc.) |
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

### Starship (Crampack)

Uses the **Crampack** preset ([Noktomezo/CrampackForStarship](https://github.com/Noktomezo/CrampackForStarship)) with Nerd Font symbols. Config: `stow/starship/.config/starship.toml`.

| System palette | Crampack palette |
|----------------|------------------|
| `nord` | `mellow` |
| `tokyo-night` | `fervor` |
| `zukitwo` | `blaze` |

`ts` / `tt` switch the Crampack palette automatically. Install or refresh from upstream:

```bash
~/dotfiles/scripts/install-starship-crampack.sh      # Standard (Nerd Font)
bash <(curl -fsSL "https://git.new/crampack-sh")    # Upstream interactive installer
```

Presets: `1` Standard · `2` Plain text · `3` Emoji · `4` Full text

### Bash (`.bashrc` + `.inputrc`)

- **bash-completion** for commands (Tab; lazy-loaded per command)
- **Prefix history search** on `↑` / `↓` via `.inputrc`
- **Menu-complete** on Tab
- Same shared exports, aliases, and functions as Zsh

---

## 🎨 Dynamic Theming

Switch your entire system's aesthetic with a single command.

### Switch Theme
```bash
ts nord          # Apply the Nord palette
ts tokyo-night   # Apply Tokyo Night palette
ts zukitwo       # Apply Zukitwo palette
```

### Toggle Themes
```bash
tt              # Cycle through all available palettes
```

### How it works
1. **Source:** Pick a palette from `theming/palettes/`.
2. **Compile:** `dart-sass` compiles SCSS templates into CSS for GTK.
3. **Propagate:** Updates terminal configs, generates a Neovim Lua palette, and sets the wallpaper.
4. **Consistency:** All apps and terminals stay in sync with the selected palette.

GNOME Shell uses the **Default** theme; GTK, terminals, and Neovim follow the active palette.

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
│   └── fastfetch/ proton-vpn/ tmp-cleanup/ zen/ …
├── theming/         # Palettes, templates, and generated theme files
├── profiles/        # Hostname-based tweaks (e.g. thinkpad-x1.sh)
├── scripts/         # Theme switching, health checks, installers
├── packages/        # Tracked package lists (Pacman, AUR, Flatpak)
├── gnome/           # GNOME settings (dconf) and extension lists
└── docs/            # Installation guides and system documentation
```

---

## 📚 Documentation

| Document | Description |
|----------|-------------|
| [README.md](README.md) | Overview, shell setup, theming, installation |
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

Machine profiles are applied automatically when `profiles/$(hostname).sh` exists (e.g. `thinkpad-x1.sh` for the X1 Yoga Gen 5).

ThinkPad-specific system configs (`i915`, kernel cmdline, Wayland env) live in `stow/system/` and are applied with `./install.sh`. After tuning, run `scripts/thinkpad-health.sh` and **reboot**.

#### Script execution order (fresh machine)

**Stage A — from the Arch ISO (bare metal):**
```text
scripts/arch-install-vmtest.sh   # optional: dry-run the installer in a UEFI VM
scripts/arch-install.sh          # LUKS + Btrfs(@tmp) + UKI(lts/hardened) + systemd-boot + sbctl + minimal GNOME
→ reboot, remove ISO
```

**Stage B — first boot (GDM login → terminal):**
```text
git clone https://github.com/HelllGuest/dotfiles.git ~/dotfiles
cd ~/dotfiles && ./install.sh        # orchestrates everything below
yay -S --needed - < packages/aur.txt # AUR (manual)
flatpak install -y $(grep -v '^#' packages/flatpak.txt)
ts <theme> && scripts/install-starship-crampack.sh
exec zsh
scripts/thinkpad-health.sh → reboot
```

**What `./install.sh` runs, in order:**
```text
profiles/$(hostname).sh → pacman < packages/pacman.txt → install-fonts.sh
→ stow (/etc system + $HOME, skips zram & gdm) → zram-setup.sh
→ gnome-session-setup.sh → gnome-console-setup.sh → gdm-setup.sh
→ git-setup.sh (interactive) → nvim-setup.sh → wallpaper.sh
→ install-extensions.sh → check.sh → validate-configs.sh → privacy-hardener.sh
```

> `scripts/tmp-to-disk.sh` is **not** part of this flow — `arch-install.sh` already
> puts `/tmp` on a disk-backed `@tmp` subvolume. It's only for retrofitting an
> **existing** machine that still has tmpfs `/tmp`.

### 2. Config Only (No Root)
Applies user-level symlinks only. Skips `zram` (requires sudo).
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

**Core:** `stow`, `zsh`, `starship`, `neovim`, `rclone`, `jq`, `dart-sass`, `zram-generator`

**Zsh:** zinit bootstraps on first launch; plugins load via `.zsh-plugins`

**Shell tools:** `atuin`, `fzf`, `fd`, `ripgrep`, `bat`, `eza`, `zoxide`, `direnv`, `git-delta`

**Optional AUR:** `blesh-git`, `curlie`, `forgit`

**Terminals:** `kitty` (primary), `ghostty`, `gnome-console` (kgx quick terminal)

Run `scripts/gnome-console-setup.sh` for Console dconf + Super+Return → kitty.

**GDM:** `scripts/gdm-setup.sh` deploys Wayland login screen config to `/etc` (requires sudo). Optional fingerprint: `scripts/fingerprint-setup.sh`. Restart GDM or reboot to see greeter changes.

**Git:** `stow/git/` + `scripts/git-setup.sh` — delta pager, rebase defaults, global ignore, optional hooks and signing. URL shorthands: `git clone gh:user/repo`.

**Neovim:** `scripts/nvim-setup.sh` — Lazy.nvim plugins, Treesitter parsers, Mason LSP on first launch. Leader = Space.

**GNOME session:** `scripts/gnome-session-setup.sh` — dconf profile, extensions, Catppuccin day/night, X1 Yoga tablet handler. Super+1–4 workspaces.

**Fonts:** Run `scripts/install-fonts.sh` for top Nerd Fonts (JetBrains Mono, Meslo, FiraCode, Cascadia, Iosevka, etc.)

**Theming:** `papirus-icon-theme`; AUR `zukitwo-themes-git` for GTK theme

**GNOME extensions:** blur-my-shell, vitals, nightthemeswitcher (see `gnome/extensions.txt`, AUR in `packages/aur.txt`)

---

## 🛡️ Privacy & Security

We take a "quiet by default" approach:
- **GNOME Debloated:** Uses `gnome-shell` instead of the full `gnome` meta-package where possible.
- **Zero Telemetry:** VS Code, GNOME usage stats, and technical reporting are disabled.
- **Opt-Out Defaults:** Global environment variables in `.shell-exports` disable telemetry for development tools.
- **Local Themes:** All CSS and palettes are generated and stored locally.

---

## 🧹 Maintenance

| Task | Command |
|------|---------|
| Full update | `sudo pacman -Syu && ./install.sh && bash scripts/post-update.sh` |
| Health check | `~/dotfiles/scripts/check.sh` |
| Post-update sync | `~/dotfiles/scripts/post-update.sh` |
| Backup GNOME | `~/dotfiles/scripts/backup-gsettings.sh` |
| Move /tmp to disk | `sudo ~/dotfiles/scripts/tmp-to-disk.sh` then reboot (off RAM-capped tmpfs → btrfs `@tmp`) |
| Switch theme | `ts <palette>` or `tt` |
| Reload shell | `exec zsh` |

---

## ⚖️ License
MIT © 2026
