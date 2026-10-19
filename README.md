# 🌌 Arch Linux + GNOME Dotfiles

A clean, modular, and programmable dotfiles ecosystem optimized for **Arch Linux**, **GNOME Shell 51**, and **ThinkPad** hardware. This setup focuses on visual cohesion, privacy hardening, and a frictionless developer workflow.

---

## 🚀 Key Features

- **Privacy Hardened:** Telemetry, usage reporting, and "phoning home" are disabled system-wide (GNOME, VS Code, .NET, etc.).
- **ThinkPad Optimized:** Hostname or hardware-detected profiles (`thinkpad-x1.sh`, `thinkpad-p15.sh`, or `laptop.sh`) with power-profiles-daemon, tablet auto-rotate, UKIs signed for Secure Boot (sbctl), and a tracked **s2idle** sleep pin (`mem_sleep_default=s2idle`; pair BIOS Sleep State with **Windows and Linux**, not **Linux**/S3 — see `docs/hardened-arch-gnome.md`). Thermal is firmware-managed. Battery charge thresholds are documented in the same guide (manual `thinkpad_acpi` sysfs).
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

**Routing:** Claude Code uses `ANTHROPIC_BASE_URL` from `~/.claude/settings.json`. Interactive shells get `ANTHROPIC_BASE_URL` / `OPENAI_BASE_URL` from the Headroom block in stowed `~/.zshrc` / `~/.bashrc` (and `~/.profile`). If `headroom doctor` warns that those vars are unset, the *current* process never sourced the rc file (common in IDE/agent shells): `source ~/.zshrc`, open a new terminal, or `export ANTHROPIC_BASE_URL=http://127.0.0.1:8787` / `OPENAI_BASE_URL=http://127.0.0.1:8787/v1`.

**Cursor:** still paste Override OpenAI Base URL from `hr-cursor` (IDE does not use shell env for model routing). MCP: `headroom mcp install --force` registers Claude / Codex / OpenCode when detected; add Cursor manually in `~/.cursor/mcp.json` if needed (`command`: `headroom`, `args`: `["mcp","serve"]`).

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

### Starship

Uses the **Gruvbox Rainbow** preset (official [starship preset](https://starship.rs/presets/gruvbox-rainbow)) with Nerd Font symbols. Config: `stow/starship/.config/starship.toml`.

Optional older **Crampack** presets (not in this repo):  
`bash <(curl -fsSL "https://git.new/crampack-sh")`

### Bash (`.bashrc` + `.inputrc`)

- **bash-completion** for commands (Tab; loaded at shell startup)
- **Prefix history search** on `↑` / `↓` via `.inputrc`
- **Menu-complete** on Tab
- Same shared exports, aliases, and functions as Zsh

---

## 🛠️ Repository Structure

```text
dotfiles/
├── stow/            # GNU Stow packages → $HOME (system/ copied to / by system-setup.sh)
│   ├── bash/ zsh/   # shells; shared .shell-* under zsh/
│   ├── system/      # /etc template (i915, sleep, UFW, udev, Wayland env) — copied by scripts/system-setup.sh
│   ├── zram/        # template only — copied by scripts/zram-setup.sh (never stow -t /)
│   ├── gdm/         # template only — copied by scripts/gdm-setup.sh
│   ├── kitty/ ghostty/ alacritty/ contour/ foot/ rio/ wezterm/
│   ├── nvim/ starship/ atuin/ git/ fastfetch/ proton-vpn/ …
│   └── vscode/ cursor/ antigravity/ flutter/ npm/ htop/ …
├── browsers/        # Chromium base + per-browser policy extras; Zen user.js
├── packages/        # pacman.txt, flatpak.txt, browsers.txt, aur.txt
├── profiles/        # Hostname or hardware-detected tweaks
├── scripts/         # Installers + health checks (lib/ shared helpers)
├── tests/           # Script tests (`tests/*.test.sh`, run in CI)
├── gnome/           # dconf snapshots, extensions.txt, keybindings.md
├── docs/            # Hardened install guide + X1 purpose-stack guide
├── builds/          # Optional local PKGBUILDs (e.g. builds/st + scripts/build-st.sh)
├── skills/          # Agent skills shipped with the repo (e.g. ghidra-cli-host)
├── ai-rules/        # Shared AGENTS.md kit + git hooks (AGENTS.md → symlink)
└── .github/         # CI (stow inventory, bash -n, tests/, markdownlint)
```

---

## 📚 Documentation

| Document | Description |
|----------|-------------|
| [README.md](README.md) | Overview, shell setup, installation |
| [CHANGELOG.md](CHANGELOG.md) | Version history |
| [CONTRIBUTING.md](CONTRIBUTING.md) | Contribution guidelines |
| [docs/hardened-arch-gnome.md](docs/hardened-arch-gnome.md) | Full Arch + GNOME install guide (ThinkPad X1) — automated by `scripts/arch-install.sh` |
| [docs/fresh-install-coding-re.md](docs/fresh-install-coding-re.md) | Fresh install for coding, reverse engineering, malware analysis (this machine) |
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
It mirrors [docs/hardened-arch-gnome.md](docs/hardened-arch-gnome.md). Rehearse it
in a UEFI VM first — `scripts/arch-install-vmtest.sh` (OVMF qemu, serves the
installer over loopback; host disks untouched; this is a full VM install, not a
no-op dry-run). Then continue with **1. Full Bootstrap** below to apply the
dotfiles.

### 1. Full Bootstrap (Recommended)
Installs packages, stows configs into `$HOME`, installs `stow/system/` into `/etc` as root-owned files, restores GNOME settings, and runs health checks.
```bash
./install.sh
```

Machine profiles run in `./install.sh` via `scripts/apply-profile.sh` **after** `packages/pacman.txt` (exactly one profile): `profiles/$(hostname).sh` if it exists, otherwise `scripts/detect-profile.sh` (ThinkPad X1 → `thinkpad-x1`, ThinkPad P15 → `thinkpad-p15`, other ThinkPads/laptop chassis → `laptop`). Pacman first so Optimus/NVIDIA packages exist before `thinkpad-p15` enables services and rebuilds UKIs. There is no `nvidia.sh`; Optimus setup is inside `profiles/thinkpad-p15.sh`.

ThinkPad system configs (`i915`, kernel cmdline, sleep, UFW, Wayland env) live in `stow/system/` and are installed by `scripts/system-setup.sh` as **root-owned regular files**, never stow symlinks (re-run it after editing `stow/system/`). Why, and how the cmdline UUID is handled: [hardened guide — `system/` files](docs/hardened-arch-gnome.md#kernel-cmdline--system-files-installed-not-stowed). After tuning, run `scripts/thinkpad-health.sh` and **reboot**.

#### Script execution order (fresh machine)

**Stage A — from the Arch ISO (bare metal):**
```text
scripts/arch-install-vmtest.sh   # optional: full UEFI VM install (host disks untouched)
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
cd ~/dotfiles
bash scripts/p15-dotfiles-preflight.sh   # P15 only — optional readiness check
./install.sh                             # requires GNOME session for dconf/extensions
# hostname p15 → profiles/p15.sh → thinkpad-p15 (Optimus). Or re-run:
# bash profiles/thinkpad-p15.sh
exec zsh
reboot                                   # required after NVIDIA/early-KMS profile
prime-run glxinfo -B | grep -i renderer  # after reboot
scripts/thinkpad-health.sh
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
→ sync-agent-skills.sh → install-caveman.sh (if npm) → install-android-ui-skills.sh (if npx)
→ install-ghidra-cli.sh (if ghidra) → install-rea.sh (if npm) → sync-agent-skills.sh
→ install-photogimp.sh
→ install-dash2dock.sh → install-extensions.sh → check.sh → validate-configs.sh
→ privacy-hardener.sh (incl. browser-hardening.sh)
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

**AI (optional):** `python-pipx` + `headroom` via `scripts/headroom-setup.sh`; `claude` / `cursor` installed separately

**Graphics (optional):** `gimp` + PhotoGIMP via `scripts/install-photogimp.sh`

**GNOME dock:** Dash2Dock Animated via `scripts/install-dash2dock.sh` (EGO; listed in `gnome/extensions.txt`)

**AUR** (via `install-aur.sh`, bootstraps `paru` if needed): `blesh-git`, `curlie`, `forgit`, GNOME shell extensions, `vscodium-bin` (settings in `stow/vscode/`)

**Flatpaks** (via `install-flatpaks.sh`): Brave, Zen, Google Chrome, LibreWolf, Proton VPN, Android Studio. Browser telemetry debloat: `scripts/browser-hardening.sh` (Chrome/Brave `/etc` policies; Zen `user.js` per profile + `/etc/firefox/policies`; LibreWolf upstream-hardened). Launch Zen once before re-running hardening if profiles are new.

**Terminals:** `kitty` (primary; Super+Return), `ghostty`, optional stowed configs for `alacritty`, `contour`, `foot`, `rio`, `wezterm`, plus `gnome-console` (kgx) and `ptyxis`. Optional suckless `st`: `bash scripts/build-st.sh` (`builds/st/`).

Run `scripts/gnome-console-setup.sh` / `scripts/ptyxis-setup.sh` for Console/Ptyxis dconf. **Super+Return → kitty** is in `gnome/dconf/user.conf`.

Clipboard: selecting text auto-copies in kitty and ghostty (`copy_on_select`); in kitty, right-click also copies the selection (Shift+right-click extends it).

**Ghidra:** pacman `ghidra` + `bash scripts/install-ghidra-cli.sh` (cargo CLI; host skill under `skills/ghidra-cli-host/`). GUI: `ghidra-gui` (cargo `ghidra` shadows `/usr/bin/ghidra`).

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
- **Zero Telemetry:** VS Code, GNOME usage stats, and technical reporting are disabled.
- **Opt-Out Defaults:** Global environment variables in `.shell-exports` disable telemetry for development tools.

---

## Troubleshooting

| Symptom | Cause | Fix |
|---------|--------|-----|
| `Can't find an installed Node version matching …` on terminal open | **fnm** `--use-on-cd` + project `engines` / `.nvmrc` | `fnm install 22` or `fnm install` in project; or drop `--use-on-cd` in dotfiles |
| `$FZF_DEFAULT_OPTS: unknown action: copy-selection` | fzf 0.72 lacks `copy-selection` | Fixed in dotfiles; `exec zsh` / `exec bash` |
| `docker` tries Podman socket / `connect: no such file` | Stale `DOCKER_HOST` or Podman socket missing | Current `.shell-exports` auto-picks; `unset DOCKER_HOST`; enable `docker.service` |
| `unsafe path transition /etc` during `pacman` | `/etc` owned by user (old `gdm-setup.sh` used `rsync -a`) | `bash scripts/gdm-setup.sh` (restores root + 755), or `sudo chown root:root /etc && sudo chmod 755 /etc` |
| No network after boot; `ufw.service` failed | `/etc/ufw/before.rules` was a stow symlink into `$HOME` | `bash scripts/system-setup.sh` (installs real files, reloads ufw) |
| Spoof location sync does nothing | `vpn-location-sync` failed under `pkexec` | `bash scripts/location-setup.sh`; panel → Sync spoofed location |
| Touchpad clicks broken after old dotfiles | Legacy synaptics inhibit/udev | `bash scripts/cleanup-input-overrides.sh` (sudo), log out |
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
| Agent skills sync | `bash scripts/sync-agent-skills.sh` |
| Caveman (`/caveman`) | `bash scripts/install-caveman.sh` |
| Android UI skills | `bash scripts/install-android-ui-skills.sh` (Compose + Material 3) |
| REA (MCP + jadx) | `bash scripts/install-rea.sh` (Hopper: `INSTALL_HOPPER=1`) |
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
