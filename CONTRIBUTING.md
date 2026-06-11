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

- Keep `pacman.txt`, `aur.txt`, and `flatpak.txt` in sync with configs that depend on them.
- Shell plugin packages belong in `pacman.txt`.

### GNOME (`gnome/`)

- Export live settings: `./scripts/backup-gsettings.sh` (writes `gnome/dconf-settings.ini`)
- Ensure `user-theme` is `Default` (not `Generated-Theme`).
- Avoid machine-specific paths unless intentionally updating the reference snapshot.

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
