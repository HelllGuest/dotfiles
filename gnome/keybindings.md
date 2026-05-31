# Shortcuts & Shell Commands

Reference for dotfiles-specific commands and common GNOME shortcuts on this setup.

---

## Shell Aliases

Defined in `stow/zsh/.shell-aliases` (shared by Zsh and Bash):

| Alias | Command |
|-------|---------|
| `ts` | `~/dotfiles/scripts/theme-switch.sh` — apply a theme palette |
| `tt` | `~/dotfiles/scripts/theme-toggle.sh` — cycle palettes |
| `v` | `nvim` |
| `as` | `flatpak run com.google.AndroidStudio` |
| `ff` | `fastfetch` |
| `ls` | `ls --color=auto` |
| `grep` | `grep --color=auto` |

---

## Zsh Key Bindings

Configured in `stow/zsh/.zsh-plugins` via **zsh-autocomplete** and **zsh-autosuggestions**:

| Key | Action |
|-----|--------|
| *(type)* | Show completion menu automatically |
| `Tab` | Insert top completion |
| `Shift+Tab` | Expand word / previous completion |
| `↑` / `↓` | Navigate history or completion menu |
| `Alt+↑` / `Alt+↓` | Switch completion / history sections |
| `→` or `End` | Accept full ghost suggestion |
| `Ctrl+R` | Incremental history search |
| `Ctrl+S` | Forward history / menu search |
| `PgUp` / `PgDn` | Scroll completion menu |

---

## Bash Key Bindings

Configured in `stow/bash/.inputrc`:

| Key | Action |
|-----|--------|
| `Tab` | Menu-complete (cycle matches) |
| `Shift+Tab` | Reverse menu-complete |
| `↑` / `↓` | Prefix history search (match typed text) |

Command completion requires `Tab` (no real-time menu in Bash).

---

## Theme Commands

```bash
ts nord          # Nord palette
ts tokyo-night   # Tokyo Night palette
ts zukitwo       # Zukitwo palette
tt               # Cycle to next palette
```

---

## GNOME Defaults

Standard GNOME 50 shortcuts apply. Common ones:

| Shortcut | Action |
|----------|--------|
| `Super` | Activities overview |
| `Super+Tab` | Switch applications |
| `Super+\`` | Switch windows of same app |
| `Super+L` | Lock screen |
| `Super+Shift+S` | Screenshot (region) |
| `Ctrl+Alt+T` | New terminal (if bound in Settings → Keyboard) |

Export or restore custom GNOME keybindings:

```bash
~/dotfiles/scripts/backup-gsettings.sh    # backup all GNOME settings
~/dotfiles/scripts/restore-gsettings.sh   # restore from gnome/dconf-settings.ini
```

---

## Terminal (Kitty)

From `stow/kitty/.config/kitty/kitty.conf`:

| Shortcut | Action |
|----------|--------|
| `Ctrl+Shift+T` | New tab in current directory |
| `Ctrl+Shift+Enter` | New window in current directory |
| `Ctrl+Shift+T` (kitty_mod) | Same via kitty modifier |

OSC 7 CWD reporting is enabled in both Zsh and Bash so new tabs open in the same directory.
