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
- **Plugin load order in `.zsh-plugins`:**
  1. `zsh-autocomplete` (provides `compinit` — do not call `compinit` separately)
  2. Set `ZSH_AUTOSUGGEST_*` variables
  3. `zsh-autosuggestions`
  4. `zsh-syntax-highlighting` (always last)
- Do not reintroduce `.zsh-aliases` / `.zsh-exports` — use the `.shell-*` naming scheme.

### Stow

- User configs: `stow -R -t "$HOME" <package>` from the `stow/` directory.
- System configs (zram): `sudo stow -R -t / zram`.
- `install.sh` and `stow-only.sh` encode this logic — update docs if you change it.
- Regenerate `all_stow_files.txt` after adding or removing stowed files:
  ```bash
  find stow -type f | sort > all_stow_files.txt
  ```

### Machine profiles (`profiles/`)

- Name profiles after the hostname: `profiles/$(hostname).sh` (e.g. `thinkpad-x1.sh`).
- `install.sh` sources the matching profile automatically.
- `profiles/laptop.sh` can delegate to hardware-specific profiles.

### Theming (`theming/`)

- Add new palettes as JSON in `theming/palettes/` (use `"extends"` for shared keys).
- Set `"crampack_palette"` (`mellow` | `lush` | `fervor` | `blaze`) for Starship sync via `theme-switch.sh`.
- GTK-only: do not add GNOME Shell SCSS templates (removed in v1.4).
- Run `scripts/theme-switch.sh <palette>` to regenerate derived configs.
- Starship uses the vendored **Crampack** preset; refresh with `scripts/install-starship-crampack.sh`.

### Packages (`packages/`)

- Keep `pacman.txt`, `aur.txt`, and `flatpak.txt` in sync with configs that depend on them.
- Shell plugin packages belong in `pacman.txt`.

### GNOME (`gnome/`)

- Export live settings: `./scripts/backup-gsettings.sh > gnome/dconf-settings.ini`
- Ensure `user-theme` is `Default` (not `Generated-Theme`).
- Avoid machine-specific paths unless intentionally updating the reference snapshot.

---

## Documentation to Update

| Change type | Update |
|-------------|--------|
| New shell feature / plugin | `README.md`, `CHANGELOG.md` |
| New stow package | `README.md`, `all_stow_files.txt`, `CHANGELOG.md` |
| Install script behavior | `README.md`, `docs/hardened-arch-gnome.md` |
| New palette | `README.md`, `CHANGELOG.md` |
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
