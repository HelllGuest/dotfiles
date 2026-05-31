# 🌌 Nord Cyberdeck: Arch + GNOME Dotfiles

A clean, modular, and programmable dotfiles ecosystem optimized for **Arch Linux**, **GNOME 50**, and **ThinkPad** hardware. This setup focuses on visual cohesion, privacy hardening, and a frictionless "Scandinavian Cyberdeck" aesthetic.

---

## 🚀 Key Features

- **Dynamic Theming Engine:** A palette-driven system (`JSON` + `SCSS`) that synchronizes colors across GTK 3/4, Terminals, Starship, and Neovim.
- **Privacy Hardened:** Telemetry, usage reporting, and "phoning home" are disabled system-wide (GNOME, VS Code, .NET, etc.).
- **ThinkPad Optimized:** Hostname-based machine profiles (e.g. `thinkpad-x1.sh`) with thermal, fan, and battery tweaks.
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

### Zsh plugins (`.zsh-plugins`)

| Plugin | Role |
|--------|------|
| **zsh-autocomplete** | Real-time completion menu as you type (no Tab required) |
| **zsh-autosuggestions** | Ghost-text suggestions from history and completions |
| **zsh-syntax-highlighting** | Command syntax colors (loaded last) |

**Key bindings (Zsh):**

| Key | Action |
|-----|--------|
| Type | Show completions automatically |
| `Tab` | Insert top completion |
| `↑` / `↓` | History / completion menu navigation |
| `→` or `End` | Accept ghost suggestion |
| `Ctrl+R` | Incremental history search |

History: 50,000 lines in `~/.zsh_history` with shared sessions across terminals.

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
├── stow/
│   ├── bash/        # .bashrc, .inputrc
│   ├── zsh/         # .zshrc, .zsh-plugins, .shell-*
│   ├── zram/        # /etc/systemd/zram-generator.conf (requires root stow)
│   ├── kitty/       # Kitty terminal
│   ├── ghostty/     # Ghostty terminal
│   ├── nvim/        # Neovim (Lazy.nvim)
│   ├── starship/    # Starship prompt
│   └── fastfetch/   # System info display
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
| [docs/hardened-arch-gnome.md](docs/hardened-arch-gnome.md) | Full Arch + GNOME install guide (ThinkPad X1) |
| [gnome/keybindings.md](gnome/keybindings.md) | Shell aliases and useful shortcuts |

---

## 📦 Installation & Setup

### 1. Full Bootstrap (Recommended)
Installs packages, applies symlinks to `$HOME` and `/etc`, restores GNOME settings, and runs health checks.
```bash
./install.sh
```

Machine profiles are applied automatically when `profiles/$(hostname).sh` exists (e.g. `thinkpad-x1.sh` for the X1 Yoga Gen 5).

ThinkPad-specific system configs (`i915`, kernel cmdline, Wayland env) live in `stow/system/` and are applied with `./install.sh`. After tuning, run `scripts/thinkpad-health.sh` and **reboot**.

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
The health check (`scripts/check.sh`) validates these during installation:

**Core:** `stow`, `zsh`, `starship`, `neovim`, `rclone`, `jq`, `dart-sass`, `zram-generator`

**Zsh plugins:** `zsh-autocomplete`, `zsh-autosuggestions`, `zsh-syntax-highlighting`

**Shell:** `bash-completion`

**Terminals:** `kitty`, `ghostty`

**Fonts:** Run `scripts/install-fonts.sh` for top Nerd Fonts (JetBrains Mono, Meslo, FiraCode, Cascadia, Iosevka, etc.)

**Theming:** `papirus-icon-theme`; AUR `zukitwo-themes-git` for GTK theme

**GNOME extensions:** `user-theme`, `blur-my-shell`, `open-bar` (see `gnome/extensions.txt`)

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
| Switch theme | `ts <palette>` or `tt` |
| Reload shell | `exec zsh` |

---

## ⚖️ License
MIT © 2026
