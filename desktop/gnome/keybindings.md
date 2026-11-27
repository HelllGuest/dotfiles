# Shortcuts & Shell Commands

Quick reference for dotfiles aliases, shell bindings, terminals, GNOME keys, and the Proton VPN panel.

## Shell Aliases & Productivity (`stow/zsh/`)

| Command / Key | Action |
|---------------|--------|
| `v` / `as` | `nvim` / `flatpak run com.google.AndroidStudio` |
| `fe` / `rge <pat>` | Fuzzy open file / ripgrep match in `nvim` |
| `fcd` | Fuzzy `cd` with tree preview |
| `gai` / `gshow` / `gco` | Interactive git add / log / branch checkout (`forgit`: `gfga`, `gfglo`, … in Zsh) |
| `ff` / `ff-preset [use] <name\|reset>` | Fastfetch with active preset (`gruvbox`, `minimal`, `secops`) |
| `rice-theme [--dry] [name\|reset]` | Switch theme (`gruvbox`, `secops`) across terminals, Neovim, Starship, Fastfetch, btop/htop, bat/fzf, and GNOME accent/Text Editor |
| `Ctrl+R` | History search (**fzf** in Zsh; **atuin** in Bash) |
| `Ctrl+T` / `Alt+C` | fzf file / directory picker (`Ctrl+F` / `Ctrl+B` scroll preview) |
| `Tab` | Zsh: `fzf-tab` picker; Bash: `menu-complete` (`Shift+Tab` reverses) |
| `↑` / `↓` | Prefix history search (both shells); Zsh `→`/`End` accepts ghost suggestion |

Modern CLI replacements when installed: `eza`, `bat`, `rg`, `fd`, `dust`, `duf`, `delta`. For clipboard copy in fzf 0.72 (lacks `copy-selection`), pass `--bind='ctrl-y:execute-silent(echo -n {} | wl-copy)'`.

### Disposable Kali

Aliases active when `~/dotfiles/labs/scripts/kali-disposable.sh` exists (details: [docs/fresh-install-coding-re.md](../../docs/fresh-install-coding-re.md#disposable-kali)):

| Alias | Action |
|-------|--------|
| `kali <cmd>` | `setup` / `start` / `stop` / `wipe` / `status` / `attach-lan` / `lan-check` / `fetch` |
| `kali-up` / `kali-up-nat` / `kali-up-lan` | Boot fresh overlay: isolated / NAT / NAT + physical RJ45 (`macvtap`) |
| `kali-lan` / `kali-lan-check` | Hot-attach physical LAN / verify host RJ45 + guest `eth1` |
| `kali-stop` / `kali-wipe` / `kali-st` | Power off (keep overlay) / destroy overlay / status |

## Terminals

### Kitty (primary — `Super+Return`)

| Shortcut | Action |
|----------|--------|
| `Ctrl+Shift+T` / `Enter` | New tab / window (same cwd; OSC 7 enabled in Zsh & Bash) |
| `Ctrl+Shift+\` / `-` | Vertical / horizontal split |
| `Ctrl+H/J/K/L` | Navigate splits |
| `Ctrl+Shift+H` / `G` | Scrollback in `bat` / last command output |
| `Ctrl+Shift+E` | URL hints (`Ctrl+Shift+P` then `F` path / `W` word) |

Dev session: `kitty --session ~/.config/kitty/sessions/dev.conf`.

### Ghostty (`Super+Shift+Return`)

| Shortcut | Action |
|----------|--------|
| `` Ctrl+` `` | Quick drop-down terminal (top, 40%) |
| `Ctrl+Shift+D` / `E` | Vertical / horizontal split (`Ctrl+Shift+H/J/K/L` navigates) |
| `Ctrl+Shift+I` | Inspector |

### GNOME Console (`kgx`)

Throwaway terminal configured by `desktop/scripts/gnome-console-setup.sh` (100k scrollback, night theme, transparency; `x-scheme-handler/terminal` remains `kitty.desktop`).

## GNOME Shortcuts

| Shortcut | Action |
|----------|--------|
| `Super` / `Super+Tab` / `Super+L` | Activities / switch apps / lock screen |
| `Super+Return` / `Super+Shift+Return` | **Kitty** / **Ghostty** |
| `Super+.` / `Super+C` | Characters / clipboard passthrough (`wl-paste \| wl-copy`) |
| `Super+B` / `Super+E` | Browser / Files |
| `Shift+Print` | Region screenshot (GNOME default) |

Backup/restore dconf: `desktop/scripts/{backup,restore}-gsettings.sh`.

## Proton VPN Panel (`proton-vpn@helllguest`)

Activates existing NetworkManager Proton profiles created by the official app (does not call Proton's API). Protocol / Copy Server IP require `connection_persistence.json`; **Open app for Fastest…** launches the app.

* **Sync spoofed location:** runs `pkexec vpn-location-sync sync` (manual: `vpn-location-sync` or `sudo vpn-location-sync sync`). Uses VPN exit when `proton0` is up, or `system/etc/geolocation.local` when disconnected (GeoClue only; does not spoof browser WebRTC/IP).
