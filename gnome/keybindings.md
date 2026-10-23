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
| `kali` / `kali-up` / `kali-wipe` / `kali-stop` / `kali-st` | Disposable Kali (see below) |

Modern CLI aliases (when installed): `eza`, `bat`, `rg`, `fd`, etc.

### Disposable Kali

Defined in `stow/zsh/.shell-aliases` when
`~/dotfiles/scripts/kali-disposable.sh` exists. Full lab notes:
[fresh-install-coding-re.md](../docs/fresh-install-coding-re.md#disposable-kali).

| Alias | Action |
|-------|--------|
| `kali <cmd>` | `scripts/kali-disposable.sh` (`setup` / `start` / `stop` / `wipe` / `status` / `fetch`) |
| `kali-up` | New ephemeral overlay + boot **isolated** (no guest WAN) |
| `kali-up-nat` | Same with NAT (updates / cloud-init) |
| `kali-wipe` | Destroy domain + delete overlay; base untouched |
| `kali-stop` | Power off; keep overlay |
| `kali-st` | Status |

```bash
kali setup          # once: packages + download base
kali-up             # isolated session (samples)
kali-up-nat         # NAT when guest needs internet
kali-wipe           # reset to clean base
```

---

## Zsh / Bash productivity

| Key / Command | Action |
|---------------|--------|
| `Ctrl+R` | History search: **fzf** on Zsh (`fzf --zsh` after atuin), **atuin** on Bash (atuin after `fzf --bash`) |
| `Ctrl+T` | fzf file picker |
| `Alt+C` | fzf directory jump |
| `Ctrl+F` / `Ctrl+B` | fzf preview page down / up (in `FZF_DEFAULT_OPTS`) |
| `fe` | Fuzzy open file in nvim |
| `rge <pat>` | Ripgrep + open match in nvim |
| `gai` / `gshow` / `gco` | Interactive git add / log / branch checkout (`gco` fzf picker is Zsh; Bash keeps alias `git checkout`) |
| `fcd` | Fuzzy cd with tree preview |

fzf **0.72** does not support `copy-selection`. To copy the current line to the clipboard:

```bash
fzf --bind='ctrl-y:execute-silent(echo -n {} | wl-copy)'
```

Zsh also uses **fzf-tab** and **forgit** (`gfga`, `gfglo`, etc.).

---

## Setup-only tools

fnm Node pins, Headroom (`hr-claude` / `hr-cursor` / `hr-proxy`), PhotoGIMP, and
Dash2Dock are documented in the [README](../README.md) shell section.

---

## Zsh Key Bindings

Configured in `stow/zsh/.zsh-plugins` via **zinit** plugins:

| Key | Action |
|-----|--------|
| `Tab` / fzf-tab | Completion picker with previews |
| `↑` / `↓` | Prefix history search |
| `→` or `End` | Accept ghost suggestion |
| `Ctrl+R` | fzf history (`fzf --zsh` overwrites atuin's `^R`) |

---

## Bash Key Bindings

`.inputrc` plus `stow/bash/.bashrc` (`fzf --bash` then `atuin init bash`):

| Key | Action |
|-----|--------|
| `Tab` | Menu-complete (cycle matches) |
| `Shift+Tab` | Reverse menu-complete |
| `↑` / `↓` | Prefix history search (match typed text) |
| `Ctrl+R` | **atuin** history (loads after fzf, so atuin owns `^R`) |
| `Ctrl+T` / `Alt+C` | fzf file / directory picker |

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

If the app grid needs two clicks: D-Bus unit race. Stow ships
`~/.config/systemd/user/app-com.mitchellh.ghostty.service.d/override.conf`
(`Type=notify`). After pull: `stow -R -t ~ ghostty` from `~/dotfiles/stow`, then
`systemctl --user daemon-reload`.



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
| `Shift+Print` | Screenshot (region) — GNOME default; not remapped in this repo |
| `Super+Return` | **kitty** (via custom binding) |

```bash
~/dotfiles/scripts/backup-gsettings.sh   # writes gnome/dconf/user.conf
~/dotfiles/scripts/restore-gsettings.sh  # loads gnome/dconf/user.conf
```

OSC 7 CWD reporting is enabled in Zsh and Bash so new tabs open in the same directory.

---

## Proton VPN panel (`proton-vpn@helllguest`)

Status-area menu for connect/disconnect and **Spoofed location** (reads `/etc/geolocation`).

| Action | Notes |
|--------|--------|
| Sync spoofed location | Runs `pkexec vpn-location-sync sync` — needs `location-setup.sh` + wheel polkit rule |
| Manual sync | `vpn-location-sync` or `sudo vpn-location-sync sync` |

Coords follow VPN exit when `proton0` is up; home (Dubai) when disconnected. Does not spoof browser geolocation (WebRTC/IP).
