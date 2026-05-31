# 🌌 Nord Cyberdeck: Arch + GNOME Dotfiles

A clean, modular, and programmable dotfiles ecosystem optimized for **Arch Linux**, **GNOME 50**, and **ThinkPad** hardware. This setup focuses on visual cohesion, privacy hardening, and a frictionless "Scandinavian Cyberdeck" aesthetic.

---

## 🚀 Key Features

- **Dynamic Theming Engine:** A palette-driven system (`JSON` + `SCSS`) that synchronizes colors across GTK 3/4, Terminals, Starship, and Neovim.
- **Privacy Hardened:** Telemetry, usage reporting, and "phoning home" are disabled system-wide (GNOME, VS Code, .NET, etc.).
- **ThinkPad Optimized:** Intelligent hardware detection with specific tweaks for thermal management (`throttled`), fan control (`thinkfan`), and battery thresholds.
- **Elite-Tier Terminal:** Kitty & Ghostty integration with modular Zsh and Bash setups and a dynamically themed Starship prompt.
- **Neovim (Lazy.nvim):** A modular Lua configuration that imports your system-wide palette on the fly.

---

## 🎨 Dynamic Theming

Switch your entire system's aesthetic with a single command or hotkey.

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

---

## 🛠️ Repository Structure

```text
dotfiles/
├── stow/            # Modular configs managed by GNU Stow (Zsh, Nvim, etc.)
├── theming/         # Palettes, templates, and generated theme files
├── profiles/        # Machine-specific tweaks (Desktop, Laptop, ThinkPad)
├── scripts/         # Automation: theme-switching, health checks, updates
├── packages/        # Tracked package lists (Pacman, AUR, Flatpak)
├── gnome/           # GNOME settings (dconf) and extension lists
└── docs/            # Installation guides and system documentation
```

---

## 📚 Documentation

Detailed guides for setting up and maintaining the system:

- **[Hardened Arch Linux + GNOME Guide](docs/hardened-arch-gnome.md):** A step-by-step guide for a security-focused installation on ThinkPad hardware.

---

## 📦 Installation & Setup

### 1. Full Bootstrap (Recommended)
This installs all packages, applies symlinks, and hardens privacy.
```bash
./install.sh
```

### 2. Config Only (No Root)
If you've already installed the packages and just want to apply the symlinks.
```bash
./stow-only.sh
```

### 3. Dependencies
The system will run a health check during installation, but you'll primarily need:
- `stow` (or the included `minimal-stow` fallback)
- `zsh`, `starship`, `neovim`, `rclone`
- `jq`, `dart-sass`, `zram-generator`
- `gnome-shell-extensions` (specifically `user-theme`, `blur-my-shell`, `open-bar`)

---

## 🛡️ Privacy & Security

We take a "quiet by default" approach:
- **GNOME Debloated:** By default, we use `gnome-shell` instead of the full `gnome` group to avoid pre-installed bloatware (Maps, Weather, Epiphany, etc.).
- **Zero Telemetry:** VS Code, GNOME usage stats, and technical reporting are disabled.
- **Opt-Out Defaults:** Global environment variables disable telemetry for development tools.
- **Local Themes:** All CSS and palettes are generated and stored locally.

---

## 🧹 Maintenance

Keep your cyberdeck healthy and up to date:

- **Full Update:** Run `sudo pacman -Syu && ./install.sh && bash scripts/post-update.sh` for a total system and dotfiles refresh.
- **Health Check:** `~/dotfiles/scripts/check.sh`
- **Maintenance Sync:** `~/dotfiles/scripts/post-update.sh` (Updates Flatpaks, Nvim plugins, and system caches).
- **Backup GNOME:** `~/dotfiles/scripts/backup-gsettings.sh`

---

## ⚖️ License
MIT © 2026
