# Contributing to Dotfiles

Thank you for helping improve this setup. Follow these guidelines to keep the repo consistent and reproducible.

---

## Workflow

1. Fork the repo and create a feature branch.
2. Make focused changes — one concern per commit when possible.
3. Run `./scripts/check.sh` before committing (`--stage-a` / `--all` also verify the Arch ISO install).
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
- **x86-64-v3:** `stow/system/etc/makepkg.conf.d/zz-x86-64-v3.conf` retunes local/AUR C/C++/Rust/Go builds for this Comet Lake CPU. User overlay: `stow/pacman/.config/pacman/makepkg.conf`. Rebuild hot extra/ packages with `scripts/rebuild-v3.sh` (default: zstd xz lz4), signed by a local rebuild-v3 key. Repo upgrades overwrite those packages; re-run the script. Do not use v4 (no AVX-512).
- **Headroom:** pinned pipx install via `scripts/install-headroom.sh` (`HEADROOM_VERSION`; no auto-upgrade, bump the pin deliberately); setup via `scripts/headroom-setup.sh`; shell entry points in `.shell-functions` (`hr-claude`, `hr-cursor`, `hr-opencode`, `hr-agy`, `hr-proxy`) — do not also alias those names in `.shell-aliases`. Prefer `headroom install apply --preset persistent-service … --no-telemetry` or `systemctl --user enable --now hr-proxy.service` over one-shot `hr-proxy` for always-on. Stowed shell rc may export `ANTHROPIC_BASE_URL` / `OPENAI_BASE_URL` for interactive shells; Cursor still needs manual Base URL paste in the IDE. RTK is separate (not under `~/.headroom/bin`). Document behavior in the README Headroom section when changing setup scripts.
- **PhotoGIMP:** optional; `scripts/install-photogimp.sh` verifies `PHOTO_SHA256` and overwrites GIMP config under `~/.config/GIMP/<major.minor>`. Bump `PHOTO_URL` and `PHOTO_SHA256` together. Do not commit user GIMP config into stow.
- **Dash2Dock / EGO extensions:** `scripts/fetch-gnome-extensions.sh` pins every EGO `*_TAG` + `*_SHA256` (11 zips; supports `--only <uuid>`), and `scripts/install-dash2dock.sh` delegates to it. Keep UUIDs in `gnome/extensions.txt` and `gnome/dconf/user.conf` `enabled-extensions`. Wayland: log out/in after install.
- Do not reintroduce `.zsh-aliases` / `.zsh-exports` — use the `.shell-*` naming scheme.
- **atuin** config lives in `stow/atuin/`; run `atuin import auto` after first install.

### Stow

- User configs: `stow -R -t "$HOME" <package>` from the `stow/` directory. Do not re-add tracked repo-root convenience links (`.zshrc`, `.zsh-plugins`, `.config/*`); those are gitignored — stow owns the real trees under `stow/`.
- System configs: `bash scripts/system-setup.sh` (via `install.sh`) installs `stow/system/` as root-owned regular files. Never `stow -t / system` or `stow -t / zram`: `/etc` symlinks into `$HOME` dangle at early boot and make root config user-writable. **zram:** `scripts/zram-setup.sh`. Kernel cmdline is owned by the installer / machine profile (P15 / T14s), not `stow/system/`. Firewall is firewalld (nftables); lab zones via `scripts/firewalld-lab-zones.sh`. UKIs rebuild when a managed `modprobe.d` file changes.
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
- If no hostname match, `scripts/detect-profile.sh` picks from DMI product strings + chassis type: `thinkpad-p15`, `thinkpad-t14s`, or `laptop` (no desktop/NVIDIA-only profile; no `lspci` in detect-profile).
- `install.sh` installs `packages/pacman.txt` first, then `apply-profile.sh` sources **exactly one** profile (NVIDIA/Optimus packages must exist before `thinkpad-p15` enables services / rebuilds UKIs). Optimus setup is inside `profiles/thinkpad-p15.sh` (`has_nvidia_gpu` in `scripts/lib/dmi.sh`). There is no `nvidia.sh`.
- `profiles/laptop.sh` delegates to `thinkpad-t14s.sh` when DMI type is **21CQ/21CR** (`is_thinkpad_t14s`; other T14s gens do not match); otherwise it applies the general laptop fallback.
- Bare-metal Stage A is **only** [t14s-arch-install](https://github.com/HelllGuest/t14s-arch-install) (`HW_PROFILE=t14s|p15`). Dotfiles `scripts/arch-install{,-t14s,-p15}.sh` are thin handoffs via `scripts/lib/stage-a-handoff.sh` (local checkout or GitHub fetch). Do not re-embed LUKS/pacstrap bodies here.
- After Stage A: `./install.sh` → `profiles/thinkpad-t14s.sh` / `thinkpad-p15.sh` refresh charge thresholds (`scripts/thinkpad-charge-thresholds.sh`) and machine packages. VM: `INSTALLER=arch-install-t14s.sh` or `arch-install-p15.sh scripts/arch-install-vmtest.sh`.
- Identity helpers for Stage B tooling: `scripts/lib/install-identity.sh`. Stage A identity lives in the public installer. Test fixtures `LOCALE_FILES` / `KEYMAP_DIR` need `IDENTITY_OVERRIDES=1`.
- Machine profiles own `/etc/kernel/cmdline` (e.g. `thinkpad-p15.sh` writes `/etc/modprobe.d/nvidia.conf`, appends `nvidia_drm.modeset=1` and `rd.driver.blacklist=nouveau`, then rebuilds UKIs). UKI rebuilds go through `mkinitcpio -P`; sbctl's mkinitcpio post hook signs each rebuilt UKI. A live `/proc/cmdline` without those flags means reboot (or UKI rebuild) was skipped.
- `stow/system/etc/systemd/system/virbr0-up.service` starts the libvirt `default` network then brings `virbr0` up (boot race fix). `system-setup.sh` enables it when the unit file changes; `scripts/kali-disposable.sh setup` also installs/enables it.

### Packages (`packages/`)

- Keep `pacman.txt`, `aur.txt`, `flatpak.txt`, and `browsers.txt` in sync with configs that depend on them.
- `evolution-data-server` — required by `gnome-shell-calendar-server` (`libecal` / `libedataserver`).
- `wireless-regdb` — provides `/usr/lib/firmware/regulatory.db` (Wi-Fi regdomain).
- Browser policies: `browsers/policies/chromium-base.json` (Chrome + Brave) merged with brand overlays `chrome-extra.json` (Google AI/services) and `brave-extra.json` (Brave services); missing overlay = base only. Validate names against the current [Chrome policy list](https://chromeenterprise.google/policies/) and brave-core `policy_definitions/BraveSoftware` (names are case-sensitive; unknown, `cloud_only` and removed keys are silently ignored). Zen: `zen-policies.json` + `browsers/zen/user.js`. LibreWolf: `browsers/librewolf/librewolf.overrides.cfg`. Deploy via `scripts/lib/browsers.sh` / `browser-hardening.sh`.
- Shell plugin packages: pacman extras in `pacman.txt`; AUR plugins such as **forgit** and **blesh-git** belong in `aur.txt`.

### Install order (`install.sh`)

- Rejects root (`EUID == 0`). Never document `sudo ./install.sh`.
- AUR (`install-aur.sh`) runs **after** `system-setup.sh` so paru/makepkg see `zz-x86-64-v3.conf`.
- `sync-agent-skills.sh` runs **before** `headroom-setup.sh` (agent config dirs must exist).
- `gnome-session-setup.sh` must not `stow --adopt` (overwrites tracked files).
- EXIT sudo-keepalive trap: `pkill -P` then `kill` (no `|| true`; banned by `tests/install-completeness.test.sh`).
- `privacy-hardener.sh`: on browser-hardening failure set `FAILED=1`, finish layers 3–7, `exit "$FAILED"`.

### GNOME (`gnome/`)

- Export live settings: `./scripts/backup-gsettings.sh` (overwrites `gnome/dconf/user.conf`; re-asserts the lock-screen, autorun and privacy keys after the dump, so add new hardening keys to its `ENFORCED` table)
- Theme is stock Adwaita via `scripts/theme-setup.sh` (no Aura Glass; purges Aura/Orchis leftovers). Do not add `gtk-theme` / `icon-theme` / `cursor-theme` / `cursor-size` or the `user-theme` / `blur-my-shell` trees to `user.conf`, `extensions.conf` or `stow/gdm/…/00-login-screen` (`backup-gsettings.sh` drops them; `tests/theme.test.sh` enforces it). Keep the Full-pack UUIDs in `gnome/extensions.txt` and `user.conf` `enabled-extensions`; fetch via `scripts/fetch-gnome-extensions.sh`.
- Primary terminal is kitty (`Super+Return`, `xdg-terminals.list`, `x-scheme-handler/terminal` via `gnome-console-setup.sh`).
- Avoid machine-specific paths unless intentionally updating the reference snapshot.
- Do **not** commit touchpad/mouse/keyboard overrides unless deliberately changing from stock GNOME defaults; session setup resets peripherals via `scripts/reset-input-defaults.sh`.

### Location / VPN panel (`scripts/location-setup.sh`, `stow/proton-vpn/`)

- Home template: `stow/system/etc/geolocation`; runtime file: `/etc/geolocation`.
- `vpn-location-sync.sh` must work as root via `pkexec` and NetworkManager dispatcher — test with `sudo vpn-location-sync sync` and panel **Sync spoofed location**. As root it reads home coords only from root-owned `/usr/local/share/vpn-location-sync/home.geolocation` (never the user's repo), and validates lookup results before writing `/etc/geolocation`.
- After script changes, re-run `location-setup.sh` to install `/usr/local/bin/vpn-location-sync` and polkit rule.

---

## Documentation to Update

| Change type | Update |
|-------------|--------|
| New shell feature / plugin | `README.md`, `CHANGELOG.md` |
| New stow package | `README.md`, `all_stow_files.txt`, `CHANGELOG.md` |
| Install script behavior | `README.md` (canonical howtos), `docs/hardened-arch-gnome.md` (phases), `docs/fresh-install-coding-re.md` (purpose stacks; link README howtos, do not fork them) |
| `stow/system/` / `system-setup.sh` | `docs/hardened-arch-gnome.md` (Phase 1 `system/` files section), `tests/system-setup.test.sh`, `CHANGELOG.md` |
| Profile / Secure Boot behavior | `README.md`, `docs/hardened-arch-gnome.md` (Phases 23, 27, 28), `CHANGELOG.md` |
| Package list change | `CHANGELOG.md` |
| GNOME / shortcut change | `gnome/keybindings.md`, `CHANGELOG.md` |
| Location / VPN panel change | `README.md`, `CHANGELOG.md`, `scripts/location-setup.sh` help text |
| Container CLI / `DOCKER_HOST` | `README.md`, `docs/hardened-arch-gnome.md`, `CHANGELOG.md` |
| fzf / shell exports | `README.md`, `gnome/keybindings.md`, `CHANGELOG.md` |
| fnm / Node version pins | `README.md`, `CHANGELOG.md`, troubleshooting table |
| Headroom / AI agents / skills | `README.md` (Headroom / Maintenance), `docs/fresh-install-coding-re.md`, `ai-rules/` (`AGENTS.md`, `skills/*/SKILL.md`, then `ai-rules/install.sh`), `CHANGELOG.md` |
| Shared agent constitution | Edit `ai-rules/AGENTS.md` (repo kit); run `ai-rules/install.sh` to publish `~/dev/ai-rules` and refresh Claude/Kiro skill links |
| Privacy / telemetry / browsers | `README.md` (Privacy + Flatpaks), `CONTRIBUTING.md` (packages), `docs/hardened-arch-gnome.md` (Phase 27), `stow/privacy`, `scripts/lib/telemetry.sh`, `CHANGELOG.md` |
| PhotoGIMP / GIMP (pin bump) | `scripts/install-photogimp.sh` (`PHOTO_URL` + `PHOTO_SHA256`), `README.md` (PhotoGIMP section), `CHANGELOG.md` |
| foxcage (pin bump) | `scripts/install-foxcage.sh` header (update steps), `tests/foxcage.test.sh` pins, `README.md`, `CHANGELOG.md` |
| Ponytail (pin bump) | `scripts/install-ponytail.sh` (`PONYTAIL_TAG` + `PONYTAIL_COMMIT`), `tests/ai-install-scripts.test.sh`, `README.md`, `CHANGELOG.md` |
| Kali image (pin bump) | `scripts/kali-disposable.sh` `KALI_IMAGE_URL` (per-release `cloud-images/kali-<ver>/`, never `current/`) + `KALI_IMAGE_SHA256` from that dir's `SHA256SUMS`; `CHANGELOG.md` |
| Dash2Dock / EGO extensions (pin bump) | `scripts/fetch-gnome-extensions.sh` (`*_TAG` + `*_SHA256`), `README.md` (Dash2Dock / extensions), `CHANGELOG.md` |
| Troubleshooting table | `README.md` when adding recurring install/shell issues |
| CI / lint / tests / stow inventory | `.github/workflows/ci.yml`, `scripts/lint-docs.sh`, `tests/`, `CHANGELOG.md` |

---

## Scripts

- All scripts in `scripts/` and `tests/` must be executable (`chmod +x`). `bash -n`
  on `scripts/**/*.sh`, `install.sh`, `stow-only.sh`, `profiles/*.sh`, and `labs/**/*.sh` runs in CI.
- Tests: `tests/*.test.sh`, run by CI. `bash tests/system-setup.test.sh` runs
  `system-setup.sh` against a fake root (`SYSTEM_ROOT`), no sudo.
- Markdown: `bash scripts/lint-docs.sh` (header spacing + tables). CI runs it;
  keep it out of `validate-configs.sh`.
- Use `$HOME`-relative paths or repo-root detection — avoid hardcoding usernames.
- Prefer `set -e` for install scripts. In `install.sh` wrap steps in `run_step` and prerequisites in `need_cmd`; never `|| echo "…skipped"` / `|| true` a step (tests/install-completeness.test.sh enforces it).
- Shared helpers and templates live in `scripts/lib/` (`dmi.sh`, `install-identity.sh`, `browsers.sh`, `telemetry.sh`, `agent-skills.sh`, `input.sh`, `lab-workdir.sh` (shared lab `/work` guard), `pkg-lists.sh` (package-list parsing shared by `install.sh`, installers and `check.sh`), `progress.sh` (step bars for `install.sh` / `configure.sh`), `rust-toolchain.sh` (`ensure_rust_toolchain` for `rustup` hosts), `skel.sh`, `ui-menu.sh` (shared TUI/GUI/plain menus for `install.sh` / `configure.sh`), `thinkpad-charge-thresholds.conf`, `apply-charge-thresholds.sh.tmpl`, `thinkpad-charge-thresholds.service.tmpl`). VS Code settings telemetry merge lives once in `ai-rules/lib/vscode-settings-merge.sh` (sourced by `telemetry.sh` + `ai-rules/install.sh`).
  Prefer sourcing those over copying snippets.
- Health checks: `scripts/check.sh` holds the modes (`--post` / `--stage-a` / `--all`), `check_fail`
  and the Stage A helpers; each area lives in `scripts/check.d/NN-area.sh`, sourced at top level in
  name order (shared `check_fail` / `CHECK_FAILED` / `REPO_ROOT`). A new check is a new file there;
  its number sets where it prints. Use `✓` for pass, `check_fail` for `✗`, `○` for hints.

### Script map (keep flat; group by role)

| Role | Scripts |
|------|---------|
| Bootstrap | `install.sh`, `configure.sh` (Stage B TUI), `vm-stageb-run.sh` / `vm-stageb-guest.sh`, `stow-only.sh`, `minimal-stow.sh`, thin Stage A handoffs `arch-install{,-t14s,-p15}.sh` + `lib/stage-a-handoff.sh` (canonical: t14s-arch-install), `arch-install-vmtest.sh`, `p15-dotfiles-preflight.sh`, `apply-profile.sh`, `detect-profile.sh` |
| Containers / VM / labs | `agent-run.sh` (hardened rootless Podman; `stow/containers`, whose `storage.conf` sets `fuse-overlayfs` as `mount_program` for linux-hardened), `kali-disposable.sh`, `kali-lan-host-prep.sh`, `labs-setup.sh`, `lab-detonate.sh`, `lab-mcp.sh`, `lib/lab-malware-zone.sh` (iface + `192.168.200.0/24` → `lab-malware`) |
| Packages | `install-flatpaks.sh`, `install-aur.sh`, `bootstrap-aur.sh`, `install-fonts.sh` |
| GNOME / desktop | `gnome-session-setup.sh`, `install-extensions.sh`, `fetch-gnome-extensions.sh` (SHA-256 pinned EGO zips + `--only`), `install-dash2dock.sh` (wrapper), `gnome-console-setup.sh`, `rice-setup.sh`, `theme-setup.sh` (stock Adwaita), `gdm-setup.sh`, `backup-gsettings.sh`, `restore-gsettings.sh`, `reset-input-defaults.sh`, `cleanup-input-overrides.sh` |
| Location / VPN / firewall | `location-setup.sh`, `vpn-location-sync.sh`, `proton-connectivity-check.sh`, `proton-seed-serverlist.sh`, `firewalld-lab-zones.sh` (libvirt + lab-malware), `firewalld-tailscale.sh`, `ollama-setup.sh`, `dnscrypt-setup.sh` (encrypted DNS; NM via `network-dns-setup.sh`) |
| Dev tools | `git-setup.sh`, `nvim-setup.sh`, `headroom-setup.sh`, `install-headroom.sh`, `ai-stack-setup.sh`, `sync-agent-skills.sh`, `install-coding-agents.sh`, `install-ecosystem-skills.sh`, `install-caveman.sh`, `install-ponytail.sh` (commit-pinned), `install-android-ui-skills.sh`, `install-rea.sh` (optional host; prefer `lab-re`), `install-re-skills.sh` (`packages/agent-skills-re.txt`), `install-re-extras.sh` (`packages/re-extra.txt`), `install-ghidra-cli.sh`, `install-obscura.sh` (Obscura CDP/MCP), `install-photogimp.sh` (SHA-256 pinned), `install-foxcage.sh` (foxcage: Firefox in rootless Podman; pinned commit + SHA-256), `browser-hardening.sh`, `privacy-hardener.sh` (`lib/telemetry.sh`, `stow/privacy`) |
| System | `system-setup.sh`, `zram-setup.sh`, `tmp-to-disk.sh`, `network-dns-setup.sh`, `ops-hygiene.sh` (paccache + flatpak unused), `usbguard-setup.sh`, `fingerprint-setup.sh`, `thinkpad-health.sh`, `thinkpad-charge-thresholds.sh` (70–80 tmpfiles + late-boot service; T14s profile + `install-re-extras.sh`), `rebuild-v3.sh`, `build-st.sh` |
| Validate | `check.sh`, `validate-configs.sh`, `lint-docs.sh`, `list-stow-files.sh`, `post-update.sh` |

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
