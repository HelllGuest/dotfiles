# Shortcuts & Shell Commands

Reference for dotfiles-specific commands and common GNOME shortcuts on this setup.

---

## Shell Aliases

Defined in `stow/zsh/.shell-aliases` (shared by Zsh and Bash):

| Alias | Command |
|-------|---------|
| `v` | `nvim` |
| `as` | `flatpak run com.google.AndroidStudio` |
| `ff` | `fastfetch` |

Modern CLI aliases (when installed): `eza`, `bat`, `rg`, `fd`, etc.

---

## Zsh / Bash productivity

| Key / Command | Action |
|---------------|--------|
| `Ctrl+R` | **atuin** fuzzy history search |
| `Ctrl+T` | fzf file picker |
| `Alt+C` | fzf directory jump |
| `fe` | Fuzzy open file in nvim |
| `rge <pat>` | Ripgrep + open match in nvim |
| `gai` / `gshow` / `gco` | Interactive git add / log / branch checkout |
| `fcd` | Fuzzy cd with tree preview |

Zsh also uses **fzf-tab** and **forgit** (`gfga`, `gfglo`, etc.).

---

## Zsh Key Bindings

Configured in `stow/zsh/.zsh-plugins` via **zinit** plugins:

| Key | Action |
|-----|--------|
| `Tab` / fzf-tab | Completion picker with previews |
| `↑` / `↓` | Prefix history search |
| `→` or `End` | Accept ghost suggestion |
| `Ctrl+R` | atuin history (replaces default) |

---

## Bash Key Bindings

Configured in `stow/bash/.inputrc`:

| Key | Action |
|-----|--------|
| `Tab` | Menu-complete (cycle matches) |
| `Shift+Tab` | Reverse menu-complete |
| `↑` / `↓` | Prefix history search (match typed text) |

Optional **ble.sh** adds syntax highlighting and autosuggestions.

---

## Terminal (Kitty)

Primary terminal — **Super+Return** or `kitty`.

| Shortcut | Action |
|----------|--------|
| `Ctrl+Shift+T` | New tab (cwd) |
| `Ctrl+Shift+Enter` | New window (cwd) |
| `Ctrl+Shift+\` | Vertical split |
| `Ctrl+Shift+-` | Horizontal split |
| `Ctrl+H/J/K/L` | Navigate splits (vim-style) |
| `Ctrl+Shift+H` | Scrollback in bat |
| `Ctrl+Shift+G` | Last command output only |
| `Ctrl+Shift+E` | URL hints |
| `Ctrl+Shift+P` then `F` | Path hints |
| `Ctrl+Shift+P` then `W` | Word hints |

Dev workspace:

```bash
kitty --session ~/.config/kitty/sessions/dev.conf
```

---

## Terminal (Ghostty)

| Shortcut | Action |
|----------|--------|
| `Ctrl+`` ` | Quick drop-down terminal (top, 40%) |
| `Ctrl+Shift+D` / `E` | Vertical / horizontal split |
| `Ctrl+Shift+I` | Inspector |
| `Ctrl+Shift+H/J/K/L` | Split navigation |

Multiline paste protection enabled.

---

## GNOME Console (kgx)

Quick throwaway terminal — `kgx`. Tuned by `scripts/gnome-console-setup.sh` (100k scrollback, night theme, 5% transparency).

---

## GNOME Defaults

| Shortcut | Action |
|----------|--------|
| `Super` | Activities overview |
| `Super+Tab` | Switch applications |
| `Super+L` | Lock screen |
| `Super+Shift+S` | Screenshot (region) |
| `Super+Return` | **kitty** (via custom binding) |

```bash
~/dotfiles/scripts/backup-gsettings.sh
~/dotfiles/scripts/restore-gsettings.sh
```

OSC 7 CWD reporting is enabled in Zsh and Bash so new tabs open in the same directory.
