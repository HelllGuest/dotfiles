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
- **Headroom:** optional pipx install via `scripts/install-headroom.sh`; shell entry points in `.shell-functions` / `.shell-aliases` (`hr-claude`, `hr-cursor`, `hr-proxy`). Cursor needs manual Base URL paste — document in README, not hardcoded in stow.
- Do not reintroduce `.zsh-aliases` / `.zsh-exports` — use the `.shell-*` naming scheme.
- **atuin** config lives in `stow/atuin/`; run `atuin import auto` after first install.

### Stow

- User configs: `stow -R -t "$HOME" <package>` from the `stow/` directory.
- System configs (zram): `sudo stow -R -t / zram`.
- `install.sh` and `stow-only.sh` encode this logic — update docs if you change it.
- Regenerate `all_stow_files.txt` after adding or removing stowed files:
  ```bash
  find stow -type f | sort > all_stow_files.txt
  ```

### Machine profiles (`profiles/`)

- Optional hostname override: `profiles/$(hostname).sh` (e.g. `thinkpad-x1.sh`).
- If no hostname match, `scripts/detect-profile.sh` picks from DMI + chassis + `lspci` (ThinkPad X1, laptop, desktop, NVIDIA).
- `install.sh` sources the primary profile, then `nvidia.sh` on hybrid-GPU machines when it was not already primary.
- `profiles/laptop.sh` delegates to `thinkpad-x1.sh` only on X1 models.
- `profiles/thinkpad-x1.sh` runs `mkinitcpio -P` when kernel cmdline changes; re-sign UKIs with `sbctl sign -s` when `/etc/sbctl/keys` exists (pacman hook does not run on manual rebuilds).

### Packages (`packages/`)

- Keep `pacman.txt`, `aur.txt`, `flatpak.txt`, and `browsers.txt` in sync with configs that depend on them.
- Browser policies live under `browsers/policies/` (`chromium-base.json` + per-browser extras); `scripts/lib/browsers.sh` merges and deploys them.
- Shell plugin packages belong in `pacman.txt`.

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
| Install script behavior | `README.md`, `docs/hardened-arch-gnome.md` |
| Profile / Secure Boot behavior | `README.md`, `docs/hardened-arch-gnome.md` (Phases 23, 27, 28), `CHANGELOG.md` |
| Package list change | `CHANGELOG.md` |
| GNOME / shortcut change | `gnome/keybindings.md`, `CHANGELOG.md` |
| Location / VPN panel change | `README.md`, `CHANGELOG.md`, `scripts/location-setup.sh` help text |
| Container CLI / `DOCKER_HOST` | `README.md`, `docs/hardened-arch-gnome.md`, `CHANGELOG.md` |
| fzf / shell exports | `README.md`, `gnome/keybindings.md`, `CHANGELOG.md` |
| fnm / Node version pins | `README.md`, `CHANGELOG.md`, troubleshooting table |
| Headroom / AI proxy helpers | `README.md`, `docs/hardened-arch-gnome.md` (Phase 17c), `CHANGELOG.md` |
| Troubleshooting table | `README.md` when adding recurring install/shell issues |

---

## Scripts

- All scripts in `scripts/` must be executable (`chmod +x`).
- Use `$HOME`-relative paths or repo-root detection — avoid hardcoding usernames.
- Prefer `set -e` for install scripts; use guarded fallbacks where sudo may fail.

---

## Commit Messages

Use [Conventional Commits](https://www.conventionalcommits.org/):

```
feat: add foo palette
fix: guard zsh hooks in shared shell functions
docs: document zsh-autocomplete setup
```

---

## License

Contributions are licensed under MIT, consistent with the project.
