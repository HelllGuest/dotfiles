# 🌌 Arch Linux + GNOME Dotfiles

Modular dotfiles and provisioning scripts for **Arch Linux**, **GNOME Shell 51**, and **ThinkPad** hardware (T14s Gen 3 AMD `21CQ`/`21CR`, P15 Gen 1 `20SU`, or generic x86_64).

* **Privacy-first:** Telemetry opt-outs across GNOME, browsers, IDEs, and AI tools; `firewalld` (`nftables`, default `drop`).
* **Two-stage install:** Bare-metal Arch ISO installer ([stage-a/](stage-a/README.md)) plus post-boot Stage B bootstrap (`./install.sh` and `provision/scripts/configure.sh`).
* **Shell & terminals:** Zsh (primary) + Bash sharing `.shell-*` configs, Kitty + Ghostty + Contour + kgx, switchable Gruvbox/SecOps themes (`rice-theme`, `ff-preset`), and Neovim (Lazy.nvim).
* **Isolated labs & AI:** Rootless Podman (`lab-triage`, `lab-re`, `lab-android`, `lab-web`, `lab-detonate`, `lab-mcp`), disposable Kali VM, Headroom token proxy, and unified agent rules/skills.

---

## 🛠️ Repository Structure

```text
dotfiles/
├── install.sh           # Stage B orchestrator (TUI/GUI menu + selective sections)
├── stow-only.sh         # No-root $HOME stow entrypoint
├── uninstall.sh         # Selective uninstaller (default: user units/stow/ai; --all for /etc)
├── Makefile             # Task runner (make ci, test, lint, check, drift, fix, themes, vm-*)
├── stow/                # Deployable $HOME GNU Stow packages only (shells, terminals, editors, …)
├── system/              # Root-owned /etc trees (etc/, gdm/etc/, zram/etc/), templates/, scripts/
├── ai/                  # Agent constitution (rules/), host skills (skills/), lib/, scripts/
├── desktop/             # GNOME dconf/extensions/keybindings (gnome/), lib/, scripts/
├── security/            # Browser policies/prefs (browsers/), lib/, scripts/ (firewall, VPN, DNS, privacy)
├── labs/                # Containerfiles (lab-triage/re/android/web/capture), lib/, scripts/
├── provision/           # Stage B libs (lib/) and installers (scripts/)
├── builds/              # Optional local PKGBUILDs (st/)
├── packages/            # Manifests (pacman.txt, flatpak.txt, aur.txt, agent-skills*.txt, …)
├── profiles/            # Machine profiles (thinkpad-p15, thinkpad-t14s, laptop, p15)
├── scripts/             # Diagnostics & curl-able Stage A handoffs (check.sh, drift.sh, arch-install*.sh)
├── stage-a/             # Canonical Stage A Arch ISO installer (install.sh, lib/, tests/)
├── t14s-arch-install/   # Compatibility curl/local shim → stage-a/install.sh
├── docs/                # hardened-arch-gnome.md, fresh-install-coding-re.md, SECURITY-AUDIT.md
└── tests/               # Smoke & unit tests (*.test.sh)
```

`stow/` holds only `$HOME` packages; root-owned `/etc` files live under `system/` and are installed by `system/scripts/system-setup.sh` (never symlinked into `$HOME`). Full script map: [CONTRIBUTING.md](CONTRIBUTING.md).

## 📚 Documentation

| Document | Purpose |
|----------|---------|
| [stage-a/README.md](stage-a/README.md) | Canonical Stage A Arch ISO installer (T14s, P15, generic x86_64) |
| [docs/hardened-arch-gnome.md](docs/hardened-arch-gnome.md) | Manual phase-by-phase Arch + GNOME reference |
| [docs/fresh-install-coding-re.md](docs/fresh-install-coding-re.md) | Coding, reverse engineering, malware lab, and disposable Kali guide |
| [desktop/gnome/keybindings.md](desktop/gnome/keybindings.md) | Shell aliases, terminal shortcuts, GNOME keys, Proton VPN panel |
| [ai/rules/README.md](ai/rules/README.md) | Shared AI agent rules (`AGENTS.md`), skills, and global git hooks |
| [CONTRIBUTING.md](CONTRIBUTING.md) | Contributor invariants, tests, and subsystem script map |
| [docs/SECURITY-AUDIT.md](docs/SECURITY-AUDIT.md) | Repository security audit (2026-11-16) |
| [CHANGELOG.md](CHANGELOG.md) | Version history |

---

## 📦 Installation & Setup

### 0. Stage A — Bare-metal Arch install (from the ISO)

Run from the official Arch ISO (UEFI, root). Full reference: [stage-a/README.md](stage-a/README.md). Optional VM rehearsal: `bash provision/scripts/arch-install-vmtest.sh`.

```bash
# Direct Stage A installer (DMI-detects T14s / P15 or prompts for generic):
bash <(curl -fsSL https://raw.githubusercontent.com/HelllGuest/dotfiles/main/stage-a/install.sh)

# Thin profile wrappers (same installer, pinned HW_PROFILE):
bash <(curl -fsSL https://raw.githubusercontent.com/HelllGuest/dotfiles/main/scripts/arch-install-t14s.sh)  # t14s
bash <(curl -fsSL https://raw.githubusercontent.com/HelllGuest/dotfiles/main/scripts/arch-install-p15.sh)   # p15
bash <(curl -fsSL https://raw.githubusercontent.com/HelllGuest/dotfiles/main/scripts/arch-install.sh)       # auto
```

*(Legacy URL `.../t14s-arch-install/install.sh` stays as a compatibility shim.)*

### 1. Stage A½ — Secure Boot (optional, after first boot)

```bash
# In BIOS: clear Secure Boot keys → Setup Mode (keep Secure Boot off until enrolled)
sudo sbctl sign -s /boot/vmlinuz-linux{,-lts,-hardened}   # only if sbctl verify flags them
sudo sbctl enroll-keys -m                                 # -m keeps Microsoft keys (dual-boot safe)
# In BIOS: Secure Boot → Enabled, then verify:
sbctl status && sbctl verify
```

### 2. Stage B — Full Bootstrap (`./install.sh`)

Log into GNOME, open a terminal, and run as your desktop user (**never** `sudo ./install.sh`; root is rejected):

```bash
git clone https://github.com/HelllGuest/dotfiles.git ~/dotfiles
cd ~/dotfiles
bash provision/scripts/p15-dotfiles-preflight.sh   # P15 only (optional readiness check)

./install.sh                              # interactive TUI menu on TTY (full install on non-TTY)
./install.sh --gui                        # GNOME GUI dialogs (zenity)
./install.sh --all                        # full default install without prompts (alias: -y / INSTALL_ALL=1)
./install.sh --minimal                    # skip heavy IDE/mobile/RE package bundles (MINIMAL_PACKAGES=1)
./install.sh --only stow,desktop,check    # run only selected sections (--list shows all sections)
./install.sh --skip ai,apps               # run defaults except listed sections
# Optional: CONFIGURE=1 ./install.sh --all  (runs configure.sh checklist during install)
# Step/bundle opt-outs: SKIP_FOXCAGE=1 SKIP_OLLAMA=1 SKIP_THEME=1 SKIP_RICE=1 SKIP_OPS_HYGIENE=1 SKIP_CONFIGURE=1
#                       SKIP_AI_IDES=1 SKIP_MOBILE_DEV=1 SKIP_RE_TOOLS=1 (or --minimal / MINIMAL_PACKAGES=1)

exec zsh
reboot                                    # required on P15 so UKI loads nvidia_drm.modeset
```

#### Script execution order (fresh machine)

```text
reject EUID==0 → parse flags (--all/--minimal/--gui/--tui/--plain/--only/--skip/--list) or TUI/GUI menu
→ sudo -v + keepalive (skipped for check-only runs)
→ cleanup-input-overrides.sh → pacman -Syu packages/pacman.txt (per-package retry) → bootvine enable
→ apply-profile.sh (profiles/$(hostname).sh or detect-profile.sh: thinkpad-p15 / thinkpad-t14s / laptop)
→ install-flatpaks.sh → install-fonts.sh
→ stow ($HOME; removes unmodified /etc/skel + Stage A seeds) → system/scripts/system-setup.sh (/etc regular files)
→ install-aur.sh (bootstraps paru after rustup default stable; --sudoloop unless NOPASSWD without verifypw=any)
→ tmp-semgrep-cleanup.timer → chsh zsh → fnm Node 22 → atuin import → zram-setup.sh
→ gnome-session-setup.sh → location-setup.sh → gnome-console-setup.sh → gdm-setup.sh
→ theme-setup.sh (stock Adwaita) → rice-setup.sh (Contour/htop/fastfetch/GNOME accent; rice-theme gruvbox)
→ git-setup.sh → nvim-setup.sh
→ sync-agent-skills.sh → headroom-setup.sh → install-coding-agents.sh → install-caveman.sh → install-ponytail.sh
→ install-android-ui-skills.sh → install-ghidra-cli.sh → install-obscura.sh → install-re-skills.sh
→ install-ecosystem-skills.sh → sync-agent-skills.sh → caveman OpenCode plugin → ai-stack-setup.sh → ollama-setup.sh (P15)
→ install-photogimp.sh → install-foxcage.sh (if podman) → fetch-gnome-extensions.sh → install-extensions.sh
→ configure.sh (when CONFIGURE=1 / --only configure / custom checklist)
→ privacy-hardener.sh → ops-hygiene.sh → firewalld-tailscale.sh → check.sh → validate-configs.sh
```

Nothing fails silently: every failed step or missing prerequisite is recorded and `./install.sh` exits 1 at the end.

* **GPU filtering:** `pacman.txt` skips Intel GPU packages on T14s AMD and installs NVIDIA packages only when `has_nvidia_gpu` detects a PCI `10de` display device (Optimus config lives in `profiles/thinkpad-p15.sh`).
* **Config only (no root):** `./stow-only.sh` (stows `$HOME` packages and enables `tmp-semgrep-cleanup.timer`; skips `/etc`, `zram`, `gdm`).
* **Uninstall:** `./uninstall.sh [--dry-run|--all|--only …|--skip …|--yes|--list]` (default scope: user `units`, `stow`, `ai`; privileged `/etc` layers `browsers`, `location`, `system` are opt-in; never deletes packages, GNOME dconf, or personal data).

#### Verification (`check.sh`)

```bash
bash scripts/check.sh            # --post (default): Stage A follow-ups + Stage B health & completeness
bash scripts/check.sh --stage-a  # Stage A ISO install (~80 checks via stage-a/tests/host-check.sh; STAGE_A_DIR overrides)
bash scripts/check.sh --all      # both Stage A and Stage B
bash scripts/check.sh --drift    # package (pacman/AUR/Flatpak) & stow symlink drift
bash scripts/check.sh --fix      # safe idempotent fixes (stow, agentsync, browser/GNOME/tailscale), then --post
```

---

## ⚙️ Core Subsystems & How-Tos

### Shell, Terminals & Rice

* **Shared shell files (`stow/zsh/`):** `.shell-exports`, `.shell-aliases`, `.shell-functions`, `.shell-git` are sourced by both Zsh (primary, login shell) and Bash.
* **Zsh (`zinit` turbo, ~50 ms startup):** `fast-syntax-highlighting`, `zsh-autosuggestions`, `zsh-completions`, `fzf-tab`, `autopair`, `you-should-use`, `forgit`. Deferred `_dot_compinit` + cached tool inits under `~/.cache/zsh/init/`.
* **Bash (`.bashrc` + `.inputrc`):** optional `ble.sh` (AUR), `bash-completion`, prefix history on `↑`/`↓`, shared `fzf`/`zoxide`/`atuin`/`direnv`/`starship`.
* **History (`Ctrl+R`):** Atuin runs with `--disable-up-arrow`. Zsh gives `^R` to **fzf**; Bash gives `^R` to **atuin**.
* **Terminals:** `kitty` (primary: `Super+Return`, `x-scheme-handler/terminal`), `ghostty`, `gnome-console` (`kgx`, JetBrainsMono 13), optional `alacritty`/`contour`, and optional suckless `st` (`builds/scripts/build-st.sh`). Commands >15 s in unfocused windows notify natively (kitty/Ghostty/kgx) or via `notify-send` (`CMD_NOTIFY_THRESHOLD`).
* **Rice & themes:** `rice-theme <gruvbox|secops|reset>` (`--dry` to preview; `ff-preset` for Fastfetch only) switches Starship, Fastfetch (custom PNG logos), btop, htop, Ghostty, Alacritty, Kitty, Contour, Neovim, bat/fzf, and GNOME accent/Text Editor via untracked state under `$XDG_STATE_HOME/dotfiles/theme/`. Optional older Crampack presets (not in this repo): `bash <(curl -fsSL "https://git.new/crampack-sh")`.
* **Shortcuts & aliases:** [desktop/gnome/keybindings.md](desktop/gnome/keybindings.md).

### Containers (Podman-first)

Rootless **Podman** is the default for AI sandboxes and labs (`stow/containers` sets `fuse-overlayfs` for `linux-hardened`).

```bash
mkdir -p ~/.local/share/containers/storage && chattr +C ~/.local/share/containers/storage
systemctl --user enable --now podman.socket
# If docker is also installed, keep Podman primary:
sudo systemctl disable --now docker.service docker.socket
```

`.shell-exports` points `DOCKER_HOST` at the Podman socket when present; set `FORCE_DOCKER=1` to use a real Docker daemon. Hardened one-shot sandbox: `ai/scripts/agent-run.sh <project-dir> <image> [cmd…]`. Details: [Phase 17](docs/hardened-arch-gnome.md#phase-17--rootless-podman).

### Node.js (`fnm`)

`fnm` auto-switches versions on `cd` (`--use-on-cd`). If a project pins an uninstalled Node version, run `fnm install` (or `fnm install 22 && fnm default 22`). Remove `--use-on-cd` in `stow/zsh/.zsh-plugins` and `stow/bash/.bashrc` to disable prompts.

### Desktop, GNOME Theme Packs & Optional Apps

* **Default desktop theme:** stock **Adwaita** via `desktop/scripts/theme-setup.sh` (`SKIP_THEME=1` skips). Mouse/touchpad/keyboard reset to stock GNOME defaults (`desktop/scripts/reset-input-defaults.sh`).
* **Optional GNOME theme packs:** `bash desktop/scripts/theme-packs.sh --gui` (`make themes-gui` / `make themes` / **Dotfiles Theme Packs** launcher) installs/uninstalls commit-pinned third-party packs (MacTahoe, GNOME-macOS-Tahoe, WhiteSur, Colloid, Graphite, Fluent, Flat Remix, Material-Gnome, GNOME 51-safe modular Adwaita/Gruvbox stacks, `gse-gdm`, `gdm-settings`) with opt-in `--gdm`/`--firefox`/`--flatpak`, reverting cleanly to stock Adwaita on uninstall.
* **GDM:** `desktop/scripts/gdm-setup.sh` deploys root-owned `/etc` greeter config (Wayland, hidden user list); reboot to apply.
* **Location spoofing:** `security/scripts/location-setup.sh` writes `/etc/geolocation` (from gitignored `system/etc/geolocation.local`, or VPN exit when `proton0` is up, falling back to `0.0` on lookup failure). Sync via `vpn-location-sync` or the Proton VPN panel extension.
* **PhotoGIMP:** `bash provision/scripts/install-photogimp.sh` (SHA-256 verified, maps config into live GIMP 3.x dir, backs up existing config).
* **Sandboxed browser (`foxcage`):** `bash provision/scripts/install-foxcage.sh` (SHA-256 pinned Firefox in rootless Podman; `foxcage @tmp <url>`).
* **x86-64-v3 local builds:** `system/etc/makepkg.conf.d/zz-x86-64-v3.conf` + `stow/pacman` + `GOAMD64=v3`/`RUSTFLAGS`. Rebuild core compression libs (`zstd`/`xz`/`lz4`; optional `ffmpeg`) with `bash system/scripts/rebuild-v3.sh`.

#### How to: GNOME extension zips (`fetch-gnome-extensions.sh`)

```bash
GNOME_EXT_FETCH=1 bash desktop/scripts/install-extensions.sh
# or single extension: bash desktop/scripts/fetch-gnome-extensions.sh --only dash2dock-lite@icedman.github.com
```

Downloads and SHA-256-verifies all 11 EGO zips (Caffeine, Blur My Shell, Dash2Dock Animated, and the Full pack) with GNOME 51 metadata patches where needed. Log out and back in on Wayland after installing.

#### How to: `git-setup.sh` (identity / hooks)

```bash
bash desktop/scripts/git-setup.sh
GIT_SETUP_NONINTERACTIVE=1 bash desktop/scripts/git-setup.sh   # skips prompts; reads GIT_USER_NAME / GIT_USER_EMAIL
```

Shared config lives in tracked `stow/git/.config/git/config`; machine-local identity, signing, and `templateDir` go to `~/.gitconfig` so the repo stays clean.

### AI Tooling & Headroom

`./install.sh` sets up shared agent rules/skills ([ai/rules/README.md](ai/rules/README.md)), OpenCode + Kimi (opt-in pinned Gemini CLI / Codex via `INSTALL_GEMINI_CLI=1` / `INSTALL_CODEX_CLI=1`), Caveman, Ponytail, Obscura CDP/MCP, RE/Android/ecosystem skills, and **Headroom** (pinned pipx token-compression proxy, telemetry off). Optional CLI compressor: `bash ai/scripts/install-rtk.sh`. Optional Claude Code CLI: `npm install -g @anthropic-ai/claude-code`.

```bash
bash ai/scripts/headroom-setup.sh                     # install/upgrade + MCP registration
systemctl --user enable --now hr-proxy.service        # or: headroom install apply --preset persistent-service … --no-telemetry
loginctl enable-linger "$USER"                        # keep proxy alive after logout
headroom doctor
```

Wrappers: `hr-claude`, `hr-cursor` (paste printed Base URL into Cursor → Settings → Models), `hr-opencode`, `hr-agy`, `hr-proxy` (one-shot on `:8787`, override `HEADROOM_PORT`).

### Privacy, Firewall & Labs

* **Privacy hardening:** `stow/privacy` exports telemetry opt-outs; `security/scripts/privacy-hardener.sh` enforces GNOME, browser (`security/browsers/`), IDE, Flutter, and AI policies (`browser-hardening.sh` deploys `/etc` Chrome/Brave policies and Zen/LibreWolf prefs).

#### How to: `configure.sh` (Stage B TUI)

Shared `provision/lib/ui-menu.sh` backend auto-detects **dialog** → **whiptail** → **plain** (dark + cyan focus palette, `whiptail --fullbuttons`), or **zenity** GUI with `--gui` / `CONFIGURE_UI=gui`. Interactive runs loop on a main menu (Modules / Profile / Quit or Back); submenus support `Back` (`b`/`BACK` in plain). `CONFIGURE_ONCE=1` runs one checklist pass. Selected modules **fail-fast**.

| Tag | Default | Runs |
|-----|---------|------|
| `SETUP_FIREWALLD` | on | `firewalld-lab-zones.sh` (`drop` + `virbr0`/`libvirt` + `virbr-malware`/`lab-malware`) |
| `APPLY_PROFILE` | off | `apply-profile.sh` |
| `SETUP_OLLAMA` | **on on P15**; off elsewhere | `ollama-setup.sh` (localhost `127.0.0.1:11434`) |
| `SETUP_LABS` | off | `labs-setup.sh` (`lab-triage`/`re`/`android`/`web` Podman images) |
| `SETUP_DETONATE` | off | `lab-detonate.sh setup` (`lab-capture` + Alpine VM; PolarProxy needs `POLARPROXY_SHA256`) |
| `SETUP_AI` | off | `ai-stack-setup.sh` (Headroom/`hr-proxy`, Ponytail, Continue FIM) |
| `SETUP_RICE` | off | Re-run `rice-setup.sh` (Gruvbox defaults + Contour/htop/fastfetch) |
| `SETUP_THEMES` | off | `desktop/scripts/theme-packs.sh` (GNOME theme packs manager) |

```bash
bash provision/scripts/configure.sh                      # TUI menu loop
bash provision/scripts/configure.sh --gui                # GNOME zenity GUI
CONFIGURE_UI=plain bash provision/scripts/configure.sh   # serial / headless
```

#### How to: ops / privacy kits

Boot screen: `bootvine` (`bootvine.service` + `bootvine-shutdown.service`; LUKS prompt stays stock).

```bash
bash security/scripts/ops-hygiene.sh      # paccache -rk2, flatpak unused, paccache.timer (auto in install.sh)
mat2 ./file.pdf && exiftool ./photo.jpg   # strip/inspect metadata
# Opt-in (do not enable blind on remote hosts):
bash security/scripts/usbguard-setup.sh   # allowlists currently plugged USB devices, then enables
bash security/scripts/dnscrypt-setup.sh   # dnscrypt-proxy on 127.0.0.1 + NM global DNS (SKIP_NM_GLOBAL=1 opts out; tailnet *.ts.net → MagicDNS)
bash security/scripts/network-dns-setup.sh # plain DNS override without dnscrypt (skips bridges/VPNs)
```

#### How to: firewalld lab zones / `lab-malware`

Run `firewalld-lab-zones.sh` before `labs-setup.sh`:

```bash
bash security/scripts/firewalld-lab-zones.sh
sudo firewall-cmd --get-default-zone                # drop
sudo firewall-cmd --get-active-zones                # virbr0→libvirt; virbr-malware→lab-malware
sudo firewall-cmd --permanent --zone=lab-malware --list-all
# target: DROP; masquerade: no; interfaces: virbr-malware; sources: 192.168.200.0/24
```

`virbr-malware` sets `zone="lab-malware"` and `<dns enable="no"/>` (DHCP only, advertises `192.168.200.1` for INetSim; override bind IP with `LAB_CAPTURE_BIND`; Alpine detonation guest password defaults to `DETONATE_LINUX_PASS=detonate`; no ICMP). Lab wrappers (`lab-triage`, `lab-re`, `lab-android`, `lab-web`, `lab-detonate`, `lab-mcp`) refuse mounting `$HOME`, dotfiles, `/srv/lab/samples`, system paths, or socket dirs as `/work` and fall back to `/srv/lab/out` — `cd` into a project dir first. Full RE & disposable Kali guide: [docs/fresh-install-coding-re.md](docs/fresh-install-coding-re.md).

#### How to: Stage B on a Stage A qcow2

Rehearses `configure.sh` + `./install.sh` on a throwaway qcow2 overlay over `~/arch-vmtest/test-disk.qcow2` (from `make vm-a`, requires KVM + OVMF). Note: Stage B always installs the GNOME stack from `pacman.txt` even on a `DESKTOP=N` Stage A disk (there is no no-desktop Stage B).

```bash
bash provision/scripts/vm-stageb-run.sh
# overrides: OVERLAY=0 DISK=… WORK=… SSH_PORT=… RAM=4096 HOST_PKGCACHE=none
```

| `DOTFILES_STAGEB_RESULT` | Meaning | Exit |
|--------------------------|---------|------|
| `PASS` | `configure.sh` and `install.sh` both exited 0 | 0 |
| `PASS_HEADLESS` | `configure.sh` 0; `install.sh` failed only on headless-expected checks (GNOME extensions, Zen `user.js`, zinit, Proton API, `t14s-selftest` bluetooth/pipewire) | 0 |
| `FAIL` | Any other failure | 1 |

---

## Troubleshooting

| Symptom | Cause | Fix |
|---------|--------|-----|
| `Can't find an installed Node version matching …` | `fnm --use-on-cd` + project pin | `fnm install 22` or `fnm install` in project |
| Podman / `lab-*`: `overlay is not supported over btrfs` | `linux-hardened` lacks unprivileged overlayfs | `sudo pacman -S fuse-overlayfs` and `stow -R -d stow -t ~ containers` |
| `docker` fails to connect to Podman socket | `podman.socket` inactive | `systemctl --user enable --now podman.socket` (or `FORCE_DOCKER=1` for dockerd) |
| `s2idle [deep]` after BIOS or kernel changes | BIOS Sleep set to Linux/S3 or cmdline drift | BIOS Sleep = Windows and Linux; `bash system/scripts/system-setup.sh`; reboot |
| Charge thresholds reset on boot | Missing tmpfiles or late-boot unit | `bash system/scripts/thinkpad-charge-thresholds.sh` |
| `check.sh`: Chrome/Brave policies ✗ | `/etc` policy files missing or stale | `bash security/scripts/browser-hardening.sh` |
| `virbr-malware` under `libvirt` / `INVALID_ZONE` | Lab zones not configured before `labs-setup.sh` | `bash security/scripts/firewalld-lab-zones.sh` |
| `lab: refusing to mount /home/… as /work` | Expected safety guardrail (`labs/lib/lab-workdir.sh`) | `cd ~/path/to/project` before running `lab-*` |
| Ghostty needs 2 clicks from app grid | systemd notify unit race | `stow -R -d stow -t ~ ghostty && systemctl --user daemon-reload` |
| `headroom doctor`: Base URL unset | Shell never sourced rc | `source ~/.zshrc`, open a new terminal, or export `ANTHROPIC_BASE_URL=http://127.0.0.1:8787` / `OPENAI_BASE_URL=http://127.0.0.1:8787/v1` |
| Headroom proxy down after reboot | Persistent user unit not enabled or no linger | `systemctl --user enable --now hr-proxy.service && loginctl enable-linger "$USER"` |
| Dash2Dock / `proton-vpn@helllguest` missing | Wayland Shell session not reloaded | Log out and back in (never `gnome-extensions uninstall` a stowed UUID) |
| Proton VPN app stuck on "Loading app" | Server list fetch hung | `bash security/scripts/proton-seed-serverlist.sh` |
| `ghidra` runs CLI instead of GUI | `~/.cargo/bin/ghidra` shadows `/usr/bin/ghidra` | Use `ghidra-gui`; rebuild CLI with `bash ai/scripts/install-ghidra-cli.sh` |
| `ghidra-cli` build fails on `openssl-sys` | Arch ships OpenSSL 4 | `sudo pacman -S openssl-3` and re-run `bash ai/scripts/install-ghidra-cli.sh` |
| Spoof location sync does nothing | Polkit rule / helper not installed | `bash security/scripts/location-setup.sh` |
| Touchpad clicks broken (legacy setup) | Old synaptics udev/inhibit overrides | `bash desktop/scripts/cleanup-input-overrides.sh` and log out |
| `zstd`/`xz`/`lz4` back to stock after `-Syu` | Official upgrade replaced v3 rebuilds | `bash system/scripts/rebuild-v3.sh` |

---

## 🧹 Maintenance

Run `make help` for all task targets (`make ci`, `make test`, `make lint`, `make check`, `make drift`, `make fix`, `make update-full`, `make themes-gui`, `make snapshot`, `make rollback`, `make backup`, `make restore`, `make secrets-init`, `make uninstall-dry`, `make vm-a`, `make vm-b`, `make vm-clean`).

| Task | Command |
|------|---------|
| Full update | `make update-full` (`bash provision/scripts/post-update.sh --full`) |
| Health check / drift / fix | `bash scripts/check.sh [--post\|--stage-a\|--all\|--drift\|--fix]` |
| Refresh stow inventory | `git add stow/… && bash scripts/list-stow-files.sh > all_stow_files.txt` |
| Snapper snapshot / rollback | `make snapshot` / `make rollback ID=<n> APPLY=1` |
| Encrypted personal backup | `make backup` / `make restore ARCHIVE=<file>` (`age` or OpenSSL PBKDF2) |
| Encrypted local overrides | `bash security/scripts/secrets-bootstrap.sh init\|lock\|unlock\|status` |
| GNOME theme packs | `make themes-gui` or `bash desktop/scripts/theme-packs.sh --list` |
| Backup GNOME dconf | `bash desktop/scripts/backup-gsettings.sh` |
| Refresh `/etc` system files | `bash system/scripts/system-setup.sh` |
| Sync agent rules & skills | `bash ai/scripts/sync-agent-skills.sh` |
| Retrofit `/tmp` onto Btrfs `@tmp` | `sudo bash system/scripts/tmp-to-disk.sh` then reboot |
| Docs lint | `bash scripts/lint-docs.sh` |

### Live health checklist (non-destructive)

```bash
uname -r
systemctl is-enabled ufw                                     # expect: masked
systemctl is-active firewalld                                # expect: active
firewall-cmd --get-default-zone                              # expect: drop
firewall-cmd --get-active-zones                              # virbr0→libvirt; virbr-malware→lab-malware
lab-re --check && podman images | grep localhost/lab-
ss -tlnp | grep -E ':8787|:11434'                            # localhost only (11434 on P15 only)
gsettings get org.gnome.desktop.notifications show-in-lock-screen   # false
make ci                                                      # lint, unit tests, Stage A tests, docs lint
```
