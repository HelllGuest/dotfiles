# Contributing to Dotfiles

Thank you for helping improve this setup. Follow these guidelines to keep the repo consistent and reproducible.

---

## Workflow

1. Fork the repo and create a feature branch.
2. Make focused changes — one concern per commit when possible.
3. Run `make ci` and `./scripts/check.sh` before committing (`--stage-a` / `--all` verify Stage A; `--drift` audits package/stow drift; `--fix` applies safe idempotent fixes).
4. Update relevant documentation (see below).
5. Add a `CHANGELOG.md` entry under `[Unreleased]` or a new version section.

---

## Repository Conventions

### Shell configs (`stow/zsh/`, `stow/bash/`)

- **Shared settings** go in `.shell-exports`, `.shell-aliases`, or `.shell-functions`.
- **Zsh-only** code must be guarded with `[[ -n "$ZSH_VERSION" ]]` in shared files.
- **Plugin load order in `.zsh-plugins`:** managed by **zinit** (see README shell section).
- **fnm:** uses `fnm env --use-on-cd` in zsh and bash — documents project Node pins; install versions with `fnm install` before opening those trees, or remove `--use-on-cd` if unwanted.
- **fzf:** do not add `copy-selection` to `FZF_DEFAULT_OPTS` (unsupported in fzf 0.72); use per-invocation `--bind` with `wl-copy` / `xclip` if needed.
- **Containers:** `DOCKER_HOST` in `.shell-exports` only when Podman socket exists; do not force Podman when Docker is the target runtime.
- **x86-64-v3:** `system/etc/makepkg.conf.d/zz-x86-64-v3.conf` retunes local/AUR C/C++/Rust/Go builds for this Comet Lake CPU. User overlay: `stow/pacman/.config/pacman/makepkg.conf`. Rebuild hot extra/ packages with `system/scripts/rebuild-v3.sh` (default: zstd xz lz4), signed by a local rebuild-v3 key. Repo upgrades overwrite those packages; re-run the script. Do not use v4 (no AVX-512).
- **Headroom:** pinned pipx install via `ai/scripts/install-headroom.sh` (`HEADROOM_VERSION`; no auto-upgrade, bump the pin deliberately); setup via `ai/scripts/headroom-setup.sh`; shell entry points in `.shell-functions` (`hr-claude`, `hr-cursor`, `hr-opencode`, `hr-agy`, `hr-proxy`) — do not also alias those names in `.shell-aliases`. Prefer `headroom install apply --preset persistent-service … --no-telemetry` or `systemctl --user enable --now hr-proxy.service` over one-shot `hr-proxy` for always-on. Stowed shell rc may export `ANTHROPIC_BASE_URL` / `OPENAI_BASE_URL` for interactive shells; Cursor still needs manual Base URL paste in the IDE. RTK is separate (not under `~/.headroom/bin`). Document behavior in the README Headroom section when changing setup scripts.
- **PhotoGIMP:** optional; `provision/scripts/install-photogimp.sh` verifies `PHOTO_SHA256` and overwrites GIMP config under `~/.config/GIMP/<major.minor>`. Bump `PHOTO_URL` and `PHOTO_SHA256` together. Do not commit user GIMP config into stow.
- **Dash2Dock / EGO extensions:** `desktop/scripts/fetch-gnome-extensions.sh` pins every EGO `*_TAG` + `*_SHA256` (11 zips; supports `--only <uuid>`), and `desktop/scripts/install-dash2dock.sh` delegates to it. Keep UUIDs in `desktop/gnome/extensions.txt` and `desktop/gnome/dconf/user.conf` `enabled-extensions`. Wayland: log out/in after install.
- Do not reintroduce `.zsh-aliases` / `.zsh-exports` — use the `.shell-*` naming scheme.
- **atuin** config lives in `stow/atuin/`; run `atuin import auto` after first install.

### Stow

- User configs: `stow -R -t "$HOME" <package>` from the `stow/` directory. Do not re-add tracked repo-root convenience links (`.zshrc`, `.zsh-plugins`, `.config/*`); those are gitignored — stow owns the real trees under `stow/`.
- System configs: `bash system/scripts/system-setup.sh` (via `install.sh`) installs `system/` as root-owned regular files. Never `stow -t / system` or `stow -t / zram`: `/etc` symlinks into `$HOME` dangle at early boot and make root config user-writable. **zram:** `system/scripts/zram-setup.sh`. Kernel cmdline is owned by the installer / machine profile (P15 / T14s), not `system/`. Firewall is firewalld (nftables); lab zones via `security/scripts/firewalld-lab-zones.sh`. UKIs rebuild when a managed `modprobe.d` file changes.
- `install.sh` and `stow-only.sh` encode this logic — update docs if you change it.
- Regenerate `all_stow_files.txt` after adding or removing stowed files:
  ```bash
  git add stow/…   # index new paths first
  bash scripts/list-stow-files.sh > all_stow_files.txt   # script pins LC_ALL=C sort
  ```
  Listing is **index-only** (`git ls-files -- stow`): tracked or staged paths.
  Untracked files are omitted so CI matches a clean checkout. Do **not** use bare
  `find stow` (VSCodium Cache / foreign GNOME extensions). Kit `pre-commit` and
  CI both call `scripts/list-stow-files.sh`.

### Machine profiles (`profiles/`)

- Optional hostname override: `profiles/$(hostname).sh` (e.g. `p15.sh` → `thinkpad-p15.sh`).
- If no hostname match, `provision/scripts/detect-profile.sh` picks from DMI product strings + chassis type: `thinkpad-p15`, `thinkpad-t14s`, or `laptop` (no desktop/NVIDIA-only profile; no `lspci` in detect-profile).
- `install.sh` installs `packages/pacman.txt` first, then `apply-profile.sh` sources **exactly one** profile (NVIDIA/Optimus packages must exist before `thinkpad-p15` enables services / rebuilds UKIs). Optimus setup is inside `profiles/thinkpad-p15.sh` (`has_nvidia_gpu` in `provision/lib/dmi.sh`). There is no `nvidia.sh`.
- `profiles/laptop.sh` delegates to `thinkpad-t14s.sh` when DMI type is **21CQ/21CR** (`is_thinkpad_t14s`; other T14s gens do not match); otherwise it applies the general laptop fallback.
- Bare-metal Stage A is **only** in-repo [stage-a/](stage-a/README.md) (`HW_PROFILE=t14s|p15|generic`; legacy `t14s-arch-install/install.sh` is a curl/local compatibility shim). Dotfiles `scripts/arch-install{,-t14s,-p15}.sh` are thin handoffs via `provision/lib/stage-a-handoff.sh` (prefers in-repo `stage-a/`, remote fetches from `HelllGuest/dotfiles`). Do not re-embed LUKS/pacstrap bodies in `scripts/`.
- After Stage A: `./install.sh` → `profiles/thinkpad-t14s.sh` / `thinkpad-p15.sh` refresh charge thresholds (`system/scripts/thinkpad-charge-thresholds.sh`) and machine packages. VM: `INSTALLER=arch-install-t14s.sh` or `arch-install-p15.sh provision/scripts/arch-install-vmtest.sh`.
- Stage A identity validators live in `stage-a/lib/00-common.sh` (test fixtures `LOCALE_FILES` / `KEYMAP_DIR` need `T14S_IDENTITY_OVERRIDES=1`).
- Machine profiles own `/etc/kernel/cmdline` (e.g. `thinkpad-p15.sh` writes `/etc/modprobe.d/nvidia.conf`, appends `nvidia_drm.modeset=1` and `rd.driver.blacklist=nouveau`, then rebuilds UKIs). UKI rebuilds go through `mkinitcpio -P`; sbctl's mkinitcpio post hook signs each rebuilt UKI. A live `/proc/cmdline` without those flags means reboot (or UKI rebuild) was skipped.
- `system/etc/systemd/system/virbr0-up.service` starts the libvirt `default` network then brings `virbr0` up (boot race fix). `system-setup.sh` enables it when the unit file changes; `labs/scripts/kali-disposable.sh setup` also installs/enables it.

### Packages (`packages/`)

- Keep `pacman.txt`, `aur.txt`, `flatpak.txt`, and `browsers.txt` in sync with configs that depend on them.
- `evolution-data-server` — required by `gnome-shell-calendar-server` (`libecal` / `libedataserver`).
- `wireless-regdb` — provides `/usr/lib/firmware/regulatory.db` (Wi-Fi regdomain).
- Browser policies: `security/browsers/policies/chromium-base.json` (Chrome + Brave) merged with brand overlays `chrome-extra.json` (Google AI/services) and `brave-extra.json` (Brave services); missing overlay = base only. Validate names against the current [Chrome policy list](https://chromeenterprise.google/policies/) and brave-core `policy_definitions/BraveSoftware` (names are case-sensitive; unknown, `cloud_only` and removed keys are silently ignored). Zen: `zen-policies.json` + `security/browsers/zen/user.js`. LibreWolf: `security/browsers/librewolf/librewolf.overrides.cfg`. Deploy via `security/lib/browsers.sh` / `browser-hardening.sh`.
- Shell plugin packages: pacman extras in `pacman.txt`; AUR plugins such as **forgit** and **blesh-git** belong in `aur.txt`.

### Install order (`install.sh`)

- Rejects root (`EUID == 0`). Never document `sudo ./install.sh`.
- Interactive TTY opens the shared `provision/lib/ui-menu.sh` TUI menu (presets + custom checklist); `--all`/`-y`/non-TTY run the full default install; `--gui`/`--tui`/`--plain`, `--only`, `--skip`, and `--list` control UI/sections. Only `check`-only runs skip `sudo -v`. Keep the `INSTALL_FAILED=0`..`echo "Starting installation..."` helper block and column-0 `packages/pacman.txt` anchors intact (`tests/bootvine.test.sh`, `tests/install-completeness.test.sh`, `tests/thinkpad-t14s.test.sh`).
- AUR (`install-aur.sh`) runs **after** `system-setup.sh` so paru/makepkg see `zz-x86-64-v3.conf`.
- `sync-agent-skills.sh` runs **before** `headroom-setup.sh` (agent config dirs must exist).
- `gnome-session-setup.sh` must not `stow --adopt` (overwrites tracked files).
- EXIT sudo-keepalive trap: `pkill -P` then `kill` (no `|| true`; banned by `tests/install-completeness.test.sh`).
- `privacy-hardener.sh`: on browser-hardening failure set `FAILED=1`, finish layers 3–7, `exit "$FAILED"`.

### GNOME (`desktop/gnome/`)

- Export live settings: `./desktop/scripts/backup-gsettings.sh` (overwrites `desktop/gnome/dconf/user.conf`; re-asserts the lock-screen, autorun and privacy keys after the dump, so add new hardening keys to its `ENFORCED` table)
- Theme is stock Adwaita via `desktop/scripts/theme-setup.sh` (Orchis greeter scrub only). Do not add `gtk-theme` / `icon-theme` / `cursor-theme` / `cursor-size` or the `user-theme` / `blur-my-shell` trees to `user.conf`, `extensions.conf` or `system/gdm/…/00-login-screen` (`backup-gsettings.sh` drops them; `tests/theme.test.sh` enforces it). Keep the Full-pack UUIDs in `desktop/gnome/extensions.txt` and `user.conf` `enabled-extensions`; fetch via `desktop/scripts/fetch-gnome-extensions.sh`.
- Primary terminal is kitty (`Super+Return`, `xdg-terminals.list`, `x-scheme-handler/terminal` via `gnome-console-setup.sh`).
- Avoid machine-specific paths unless intentionally updating the reference snapshot.
- Do **not** commit touchpad/mouse/keyboard overrides unless deliberately changing from stock GNOME defaults; session setup resets peripherals via `desktop/scripts/reset-input-defaults.sh`.

### Location / VPN panel (`security/scripts/location-setup.sh`, `stow/proton-vpn/`)

- Home template: `system/etc/geolocation`; runtime file: `/etc/geolocation`.
- `vpn-location-sync.sh` must work as root via `pkexec` and NetworkManager dispatcher — test with `sudo vpn-location-sync sync` and panel **Sync spoofed location**. As root it reads home coords only from root-owned `/usr/local/share/vpn-location-sync/home.geolocation` (never the user's repo), and validates lookup results before writing `/etc/geolocation`.
- After script changes, re-run `location-setup.sh` to install `/usr/local/bin/vpn-location-sync` and polkit rule.

---

## Documentation to Update

| Change type | Update |
|-------------|--------|
| New shell feature / plugin | `README.md`, `CHANGELOG.md` |
| New stow package | `README.md`, `all_stow_files.txt`, `CHANGELOG.md` |
| Install script behavior | `README.md` (canonical howtos), `docs/hardened-arch-gnome.md` (phases), `docs/fresh-install-coding-re.md` (purpose stacks; link README howtos, do not fork them) |
| `system/` / `system-setup.sh` | `docs/hardened-arch-gnome.md` (Phase 1 `system/` files section), `tests/system-setup.test.sh`, `CHANGELOG.md` |
| Profile / Secure Boot behavior | `README.md`, `docs/hardened-arch-gnome.md` (Phases 23, 27, 28), `CHANGELOG.md` |
| Package list change | `CHANGELOG.md` |
| GNOME / shortcut change | `desktop/gnome/keybindings.md`, `CHANGELOG.md` |
| Location / VPN panel change | `README.md`, `CHANGELOG.md`, `security/scripts/location-setup.sh` help text |
| Container CLI / `DOCKER_HOST` | `README.md`, `docs/hardened-arch-gnome.md`, `CHANGELOG.md` |
| fzf / shell exports | `README.md`, `desktop/gnome/keybindings.md`, `CHANGELOG.md` |
| fnm / Node version pins | `README.md`, `CHANGELOG.md`, troubleshooting table |
| Headroom / AI agents / skills | `README.md` (Headroom / Maintenance), `docs/fresh-install-coding-re.md`, `ai/rules/` (`AGENTS.md`, `skills/*/SKILL.md`, then `ai/rules/install.sh`), `CHANGELOG.md` |
| Shared agent constitution | Edit `ai/rules/AGENTS.md` (repo kit); run `ai/rules/install.sh` to publish `~/dev/ai-rules` and refresh Claude/Kiro/Cursor/Gemini/Antigravity/Codex skill links and rules |
| Privacy / telemetry / browsers | `README.md` (Privacy + Flatpaks), `CONTRIBUTING.md` (packages), `docs/hardened-arch-gnome.md` (Phase 27), `stow/privacy`, `security/lib/telemetry.sh`, `CHANGELOG.md` |
| PhotoGIMP / GIMP (pin bump) | `provision/scripts/install-photogimp.sh` (`PHOTO_URL` + `PHOTO_SHA256`), `README.md` (PhotoGIMP section), `CHANGELOG.md` |
| foxcage (pin bump) | `provision/scripts/install-foxcage.sh` header (update steps), `tests/foxcage.test.sh` pins, `README.md`, `CHANGELOG.md` |
| Ponytail (pin bump) | `ai/scripts/install-ponytail.sh` (`PONYTAIL_TAG` + `PONYTAIL_COMMIT`), `tests/ai-install-scripts.test.sh`, `README.md`, `CHANGELOG.md` |
| Kali image (pin bump) | `labs/scripts/kali-disposable.sh` `KALI_IMAGE_URL` (per-release `cloud-images/kali-<ver>/`, never `current/`) + `KALI_IMAGE_SHA256` from that dir's `SHA256SUMS`; `CHANGELOG.md` |
| Dash2Dock / EGO extensions (pin bump) | `desktop/scripts/fetch-gnome-extensions.sh` (`*_TAG` + `*_SHA256`), `README.md` (Dash2Dock / extensions), `CHANGELOG.md` |
| Troubleshooting table | `README.md` when adding recurring install/shell issues |
| CI / lint / tests / stow inventory | `.github/workflows/ci.yml`, `scripts/lint-docs.sh`, `tests/`, `CHANGELOG.md` |

---

## Scripts

- All executable scripts across repo root (`install.sh`, `stow-only.sh`, `uninstall.sh`), `scripts/`, `provision/scripts/`, `system/scripts/`, `ai/scripts/`, `desktop/scripts/`, `security/scripts/`, `labs/scripts/`, `builds/scripts/`, and `tests/` must be executable (`chmod +x`). `bash -n` and `ShellCheck` (`-x -S warning -s bash`) run across all subsystem directories in CI (`make lint`).
- Tests: `tests/*.test.sh` and `stage-a/tests/{host-check,smoke}.test.sh` (+ Stage A ShellCheck), all run by CI (`make test` / `make ci`). `bash tests/system-setup.test.sh` runs `system/scripts/system-setup.sh` against a fake root (`SYSTEM_ROOT`), no sudo.
- Markdown: `bash scripts/lint-docs.sh` (header spacing + tables). CI runs it; keep it out of `validate-configs.sh`.
- Use `$HOME`-relative paths or repo-root detection — avoid hardcoding usernames.
- Prefer `set -e` for install scripts. In `install.sh` wrap steps in `run_step` and prerequisites in `need_cmd`; never `|| echo "…skipped"` / `|| true` a step (`tests/install-completeness.test.sh` enforces it).
- Shared helpers and templates live with their owning subsystem:
  - `provision/lib/`: `dmi.sh`, `pkg-lists.sh`, `progress.sh`, `rust-toolchain.sh`, `skel.sh`, `stage-a-handoff.sh`, `ui-menu.sh`
  - `system/templates/`: `thinkpad-charge-thresholds.conf`, `apply-charge-thresholds.sh.tmpl`, `thinkpad-charge-thresholds.service.tmpl`
  - `ai/lib/`: `agent-skills.sh`; telemetry JSON merges live once in `ai/rules/lib/vscode-settings-merge.sh` (sourced by `security/lib/telemetry.sh` + `ai/rules/install.sh`)
  - `desktop/lib/`: `input.sh`
  - `security/lib/`: `browsers.sh`, `telemetry.sh`, `lab-malware-zone.sh`
  - `labs/lib/`: `lab-workdir.sh`
  Prefer sourcing those over copying snippets.
- Health checks: `scripts/check.sh` holds the modes (`--post` / `--stage-a` / `--all` / `--drift` / `--fix`), `check_fail`, and the Stage A helpers; each area lives in `scripts/check.d/NN-area.sh`, sourced at top level in name order (shared `check_fail` / `CHECK_FAILED` / `REPO_ROOT`). A new check is a new file there; its number sets where it prints. Use `✓` for pass, `check_fail` for `✗`, `○` for hints.

### Subsystem script map

| Subsystem | Path | Scripts & modules |
|-----------|------|-------------------|
| Orchestration | repo root & `provision/` | `install.sh`, `stow-only.sh`, `uninstall.sh`, `provision/scripts/{configure,apply-profile,detect-profile,install-flatpaks,install-aur,bootstrap-aur,install-fonts,install-photogimp,install-foxcage,install-re-extras,post-update,p15-dotfiles-preflight,arch-install-vmtest,vm-stageb-run,vm-stageb-guest}.sh` |
| System | `system/` | `system/scripts/{system-setup,zram-setup,tmp-to-disk,fingerprint-setup,rebuild-v3,thinkpad-charge-thresholds,thinkpad-health}.sh` + `system/{etc,gdm/etc,zram/etc,templates}/` |
| AI tooling | `ai/` | `ai/scripts/{sync-agent-skills,headroom-setup,install-headroom,install-rtk,ai-stack-setup,ollama-setup,agent-run,install-coding-agents,install-caveman,install-ponytail,install-android-ui-skills,install-ecosystem-skills,install-re-skills,install-rea,install-ghidra-cli,install-obscura}.sh` + `ai/{rules,skills,lib}/` |
| Desktop | `desktop/` | `desktop/scripts/{gnome-session-setup,gnome-console-setup,install-extensions,fetch-gnome-extensions,install-dash2dock,rice-setup,theme-setup,theme-packs,gdm-setup,backup-gsettings,restore-gsettings,reset-input-defaults,cleanup-input-overrides,git-setup,nvim-setup}.sh` + `desktop/{gnome,lib}/` |
| Security & networking | `security/` | `security/scripts/{privacy-hardener,browser-hardening,firewalld-lab-zones,firewalld-tailscale,location-setup,vpn-location-sync,proton-connectivity-check,proton-seed-serverlist,network-dns-setup,dnscrypt-setup,usbguard-setup,ops-hygiene,secrets-bootstrap}.sh` + `security/{browsers,lib}/` |
| Labs & VMs | `labs/` | `labs/scripts/{labs-setup,lab-detonate,lab-mcp,kali-disposable,kali-lan-host-prep}.sh` + `labs/{lab-*,mcp-host.example.json,lib}/` |
| Local builds | `builds/` | `builds/scripts/build-st.sh` + `builds/st/` |
| Diagnostics & Stage A handoffs | `scripts/` | `scripts/{check,drift,validate-configs,lint-docs,list-stow-files,minimal-stow}.sh`, `scripts/check.d/*.sh`, thin curl-able Stage A handoffs `scripts/arch-install{,-t14s,-p15}.sh` (canonical Stage A: `stage-a/`, shim: `t14s-arch-install/install.sh`) |

---

## Commit Messages

Use [Conventional Commits](https://www.conventionalcommits.org/):

```
feat: add foo palette
fix: guard zsh hooks in shared shell functions
docs: document system-setup cmdline handling
```

---

## License

Contributions are licensed under MIT, consistent with the project.
