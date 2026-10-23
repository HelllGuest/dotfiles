# Contributing to Dotfiles

Thank you for helping improve this setup. Follow these guidelines to keep the repo consistent and reproducible.

---

## Workflow

1. Fork the repo and create a feature branch.
2. Make focused changes — one concern per commit when possible.
3. Run `./scripts/check.sh` before committing.
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
- **x86-64-v3:** `stow/system/etc/makepkg.conf.d/99-x86-64-v3.conf` retunes local/AUR C/C++/Rust/Go builds for this Comet Lake CPU. User overlay: `stow/pacman/.config/pacman/makepkg.conf`. Rebuild hot extra/ packages with `scripts/rebuild-v3.sh` (default: zstd xz lz4), signed by a local rebuild-v3 key. Repo upgrades overwrite those packages; re-run the script. Do not use v4 (no AVX-512).
- **Headroom:** optional pipx install/upgrade via `scripts/install-headroom.sh`; setup via `scripts/headroom-setup.sh`; shell entry points in `.shell-functions` (`hr-claude`, `hr-cursor`, `hr-proxy`) — do not also alias those names in `.shell-aliases`. Prefer `headroom install apply --preset persistent-service … --no-telemetry` over one-shot `hr-proxy` for always-on. Stowed shell rc may export `ANTHROPIC_BASE_URL` / `OPENAI_BASE_URL` for interactive shells; Cursor still needs manual Base URL paste in the IDE. RTK is separate (not under `~/.headroom/bin`). Document behavior in the README Headroom section when changing setup scripts.
- **PhotoGIMP:** optional; `scripts/install-photogimp.sh` overwrites GIMP config under `~/.config/GIMP/<major.minor>`. Do not commit user GIMP config into stow.
- **Dash2Dock:** install via `scripts/install-dash2dock.sh` (EGO zip, not stale AUR). Keep UUID in `gnome/extensions.txt` and `gnome/dconf/user.conf` `enabled-extensions`. Wayland: log out/in after install.
- Do not reintroduce `.zsh-aliases` / `.zsh-exports` — use the `.shell-*` naming scheme.
- **atuin** config lives in `stow/atuin/`; run `atuin import auto` after first install.

### Stow

- User configs: `stow -R -t "$HOME" <package>` from the `stow/` directory. Do not re-add tracked repo-root convenience links (`.zshrc`, `.zsh-plugins`, `.config/*`); those are gitignored — stow owns the real trees under `stow/`.
- System configs: `bash scripts/system-setup.sh` (via `install.sh`) installs `stow/system/` as root-owned regular files. Never `stow -t / system` or `stow -t / zram`: `/etc` symlinks into `$HOME` dangle at early boot and make root config user-writable. **zram:** `scripts/zram-setup.sh`.
- X1-only files (`X1_ONLY` in `system-setup.sh`) install only on ThinkPad X1 hardware. `stow/system/etc/kernel/cmdline` is one of them: `system-setup.sh` rewrites `rd.luks.name=` to the booted LUKS UUID and rebuilds UKIs when it changes.
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

- Optional hostname override: `profiles/$(hostname).sh` (e.g. `thinkpad-x1.sh`).
- If no hostname match, `scripts/detect-profile.sh` picks from DMI product strings + chassis type: `thinkpad-x1`, `thinkpad-p15`, or `laptop` (no desktop/NVIDIA-only profile; no `lspci` in detect-profile).
- `install.sh` installs `packages/pacman.txt` first, then `apply-profile.sh` sources **exactly one** profile (NVIDIA/Optimus packages must exist before `thinkpad-p15` enables services / rebuilds UKIs). Optimus setup is inside `profiles/thinkpad-p15.sh` (`has_nvidia_gpu` in `scripts/lib/dmi.sh`). There is no `nvidia.sh`.
- `profiles/laptop.sh` delegates to `thinkpad-x1.sh` only on X1 models.
- On ThinkPad X1 hardware, `system-setup.sh` (run after the profile) installs the X1-only `stow/system/` files (cmdline, i915, fingerprint rule), so `thinkpad-x1.sh` must not edit them. Other profiles skip those files and may manage their own (e.g. `thinkpad-p15.sh` writes `/etc/modprobe.d/nvidia.conf`, appends `nvidia_drm.modeset=1` and `rd.driver.blacklist=nouveau` to `/etc/kernel/cmdline`, then rebuilds UKIs). Gating is by DMI hardware (`is_thinkpad_x1`), not hostname. UKI rebuilds go through `mkinitcpio -P`; sbctl's mkinitcpio post hook signs each rebuilt UKI. A live `/proc/cmdline` without those flags means reboot (or UKI rebuild) was skipped.
- `stow/system/etc/systemd/system/virbr0-up.service` starts the libvirt `default` network then brings `virbr0` up (boot race fix). `system-setup.sh` enables it when the unit file changes; `scripts/kali-disposable.sh setup` also installs/enables it.

### Packages (`packages/`)

- Keep `pacman.txt`, `aur.txt`, `flatpak.txt`, and `browsers.txt` in sync with configs that depend on them.
- `evolution-data-server` — required by `gnome-shell-calendar-server` (`libecal` / `libedataserver`).
- `wireless-regdb` — provides `/usr/lib/firmware/regulatory.db` (Wi-Fi regdomain).
- Browser policies: `browsers/policies/chromium-base.json` (Chrome uses this alone); optional brand overlays (`brave-extra.json`; omit file = base only). Zen: `zen-policies.json` + `browsers/zen/user.js`. LibreWolf: `browsers/librewolf/librewolf.overrides.cfg`. Deploy via `scripts/lib/browsers.sh` / `browser-hardening.sh`.
- Shell plugin packages: pacman extras in `pacman.txt`; AUR plugins such as **forgit** and **blesh-git** belong in `aur.txt`.

### GNOME (`gnome/`)

- Export live settings: `./scripts/backup-gsettings.sh` (overwrites `gnome/dconf/user.conf`)
- Ensure `user-theme` is `Default` (not `Generated-Theme`).
- Avoid machine-specific paths unless intentionally updating the reference snapshot.
- Do **not** commit touchpad/mouse/keyboard overrides unless deliberately changing from stock GNOME defaults; session setup resets peripherals via `scripts/reset-input-defaults.sh`.

### Location / VPN panel (`scripts/location-setup.sh`, `stow/proton-vpn/`)

- Home template: `stow/system/etc/geolocation`; runtime file: `/etc/geolocation`.
- `vpn-location-sync.sh` must work as root via `pkexec` and NetworkManager dispatcher — test with `sudo vpn-location-sync sync` and panel **Sync spoofed location**.
- After script changes, re-run `location-setup.sh` to install `/usr/local/bin/vpn-location-sync` and polkit rule.

---

## Documentation to Update

| Change type | Update |
|-------------|--------|
| New shell feature / plugin | `README.md`, `CHANGELOG.md` |
| New stow package | `README.md`, `all_stow_files.txt`, `CHANGELOG.md` |
| Install script behavior | `README.md`, `docs/hardened-arch-gnome.md`, `docs/fresh-install-coding-re.md` (purpose stacks) |
| `stow/system/` / `system-setup.sh` | `docs/hardened-arch-gnome.md` (Phase 1 `system/` files section), `tests/system-setup.test.sh`, `CHANGELOG.md` |
| Profile / Secure Boot behavior | `README.md`, `docs/hardened-arch-gnome.md` (Phases 23, 27, 28), `CHANGELOG.md` |
| Package list change | `CHANGELOG.md` |
| GNOME / shortcut change | `gnome/keybindings.md`, `CHANGELOG.md` |
| Location / VPN panel change | `README.md`, `CHANGELOG.md`, `scripts/location-setup.sh` help text |
| Container CLI / `DOCKER_HOST` | `README.md`, `docs/hardened-arch-gnome.md`, `CHANGELOG.md` |
| fzf / shell exports | `README.md`, `gnome/keybindings.md`, `CHANGELOG.md` |
| fnm / Node version pins | `README.md`, `CHANGELOG.md`, troubleshooting table |
| Headroom / AI proxy helpers | `README.md` (Headroom section), `CHANGELOG.md` |
| Privacy / telemetry / browsers | `README.md` (Privacy + Flatpaks), `CONTRIBUTING.md` (packages), `docs/hardened-arch-gnome.md` (Phase 27), `stow/privacy`, `scripts/lib/telemetry.sh`, `CHANGELOG.md` |
| PhotoGIMP / GIMP | `README.md` (PhotoGIMP section), `CHANGELOG.md` |
| Dash2Dock / GNOME dock | `README.md` (Dash2Dock section), `CHANGELOG.md` |
| Troubleshooting table | `README.md` when adding recurring install/shell issues |
| CI / lint / tests / stow inventory | `.github/workflows/ci.yml`, `scripts/lint-docs.sh`, `tests/`, `CHANGELOG.md` |

---

## Scripts

- All scripts in `scripts/` and `tests/` must be executable (`chmod +x`). `bash -n`
  on `scripts/**/*.sh`, `install.sh`, `stow-only.sh`, and `profiles/*.sh` runs in CI.
- Tests: `tests/*.test.sh`, run by CI. `bash tests/system-setup.test.sh` runs
  `system-setup.sh` against a fake root (`SYSTEM_ROOT`), no sudo.
- Markdown: `bash scripts/lint-docs.sh` (header spacing + tables). CI runs it;
  keep it out of `validate-configs.sh`.
- Use `$HOME`-relative paths or repo-root detection — avoid hardcoding usernames.
- Prefer `set -e` for install scripts; use guarded fallbacks where sudo may fail.
- Shared helpers live in `scripts/lib/` (`dmi.sh`, `browsers.sh`, `telemetry.sh`, `input.sh`, `skel.sh`).
  Prefer sourcing those over copying snippets.

### Script map (keep flat; group by role)

| Role | Scripts |
|------|---------|
| Bootstrap | `install.sh`, `stow-only.sh`, `minimal-stow.sh`, `arch-install.sh`, `arch-install-vmtest.sh`, `apply-profile.sh`, `detect-profile.sh` |
| Packages | `install-flatpaks.sh`, `install-aur.sh`, `bootstrap-aur.sh`, `install-fonts.sh` |
| GNOME / desktop | `gnome-session-setup.sh`, `install-extensions.sh`, `fetch-gnome-extensions.sh`, `install-dash2dock.sh`, `gnome-console-setup.sh`, `ptyxis-setup.sh`, `gdm-setup.sh`, `backup-gsettings.sh`, `restore-gsettings.sh`, `reset-input-defaults.sh`, `cleanup-input-overrides.sh` |
| Location / VPN | `location-setup.sh`, `vpn-location-sync.sh`, `proton-connectivity-check.sh`, `proton-seed-serverlist.sh` |
| Dev tools | `git-setup.sh`, `nvim-setup.sh`, `headroom-setup.sh`, `install-headroom.sh`, `sync-agent-skills.sh`, `install-coding-agents.sh`, `install-ecosystem-skills.sh`, `install-caveman.sh`, `install-android-ui-skills.sh`, `install-rea.sh`, `install-re-skills.sh` (`packages/agent-skills-re.txt`), `install-re-extras.sh` (`packages/re-extra.txt`), `install-ghidra-cli.sh`, `install-photogimp.sh`, `browser-hardening.sh`, `privacy-hardener.sh` (`lib/telemetry.sh`, `stow/privacy`) |
| System | `system-setup.sh`, `zram-setup.sh`, `tmp-to-disk.sh`, `network-dns-setup.sh`, `fingerprint-setup.sh`, `thinkpad-health.sh`, `rebuild-v3.sh`, `build-st.sh` |
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
