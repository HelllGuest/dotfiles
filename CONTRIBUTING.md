# Contributing to Dotfiles

Guidelines and invariants for keeping this repository reproducible and CI-green.

## Workflow

1. Create a focused branch (one concern per commit when possible).
2. Run `make ci` and `bash scripts/check.sh` before committing (`--stage-a`, `--all`, `--drift`, `--fix`).
3. Keep docs accurate (prefer one canonical howto in `README.md`; link from other docs rather than forking).
4. Add a concise entry under `[Unreleased]` in `CHANGELOG.md`.

## Repository Invariants

### Shell & Stow (`stow/`, `system/`)

* **Shared shell settings** live in `stow/zsh/.shell-{exports,aliases,functions,git}` (never reintroduce `.zsh-aliases`/`.zsh-exports`). Guard zsh-only code with `[[ -n "$ZSH_VERSION" ]]`.
* **`fzf`:** do not add `copy-selection` to `FZF_DEFAULT_OPTS` (unsupported in fzf 0.72).
* **`DOCKER_HOST`:** set in `.shell-exports` only when `podman.socket` exists.
* **Headroom wrappers** (`hr-claude`, `hr-cursor`, `hr-opencode`, `hr-agy`, `hr-proxy`) live in `.shell-functions` — do not alias those names in `.shell-aliases`. Never place RTK inside `~/.headroom/bin`.
* **x86-64-v3:** keep `zz-x86-64-v3.conf` at v3 (never v4; target ThinkPads lack AVX-512).
* **`stow/` vs `system/`:** stow only `$HOME` packages (`stow -R -d stow -t "$HOME" <pkg>`). Root-owned `/etc` files live under `system/` and are installed by `system/scripts/system-setup.sh` (never symlink `/etc` into `$HOME`).
* **Stow inventory:** regenerate after adding/removing tracked files under `stow/` (index-only — never bare `find stow`):
  ```bash
  git add stow/…
  bash scripts/list-stow-files.sh > all_stow_files.txt
  ```

### Install Order & Profiles (`install.sh`, `profiles/`, `packages/`)

* **`install.sh` rejects root (`EUID == 0`).** Never document `sudo ./install.sh`.
* **Order:** `packages/pacman.txt` installs **before** `provision/scripts/apply-profile.sh` (NVIDIA/Optimus packages must exist before `thinkpad-p15.sh` runs); `system-setup.sh` runs **before** `install-aur.sh` (makepkg v3); `sync-agent-skills.sh` runs **before** `headroom-setup.sh` (agent dirs must exist).
* **Profile selection:** `profiles/$(hostname).sh` if present, else `provision/scripts/detect-profile.sh` (`thinkpad-p15`, `thinkpad-t14s`, or `laptop`). Machine profiles own `/etc/kernel/cmdline` and rebuild UKIs via `mkinitcpio -P` (signed by sbctl's hook).
* **No silent skips:** wrap steps in `run_step` and prerequisites in `need_cmd` (no `|| echo "…skipped"` / `|| true`). Keep the `INSTALL_FAILED=0`..`echo "Starting installation..."` block, column-0 `packages/pacman.txt` anchors, and `pkill -P` EXIT trap intact (asserted by tests).
* **Stage A:** canonical code lives only in `stage-a/` (`scripts/arch-install*.sh` and `t14s-arch-install/install.sh` are thin handoffs/shims; do not duplicate installer logic).
* **Packages & pins:** keep `pacman.txt`, `aur.txt`, `flatpak.txt`, and `browsers.txt` aligned with dependent configs. When bumping pinned tools/images (`install-photogimp.sh`, `install-foxcage.sh`, `install-ponytail.sh`, `fetch-gnome-extensions.sh`, `kali-disposable.sh`), update URL/tag + SHA-256 + matching tests together.

### GNOME & Security (`desktop/`, `security/`)

* **Theme & dconf:** stock Adwaita via `desktop/scripts/theme-setup.sh`. Do not add `gtk-theme`/`icon-theme`/`cursor-theme`/`user-theme`/`blur-my-shell` keys to `desktop/gnome/dconf/user.conf` (`backup-gsettings.sh` strips them and re-asserts enforced privacy keys; `tests/theme.test.sh` checks this). Keep `gnome-session-setup.sh` free of `stow --adopt`.
* **Input:** keep stock GNOME touchpad/mouse/keyboard defaults (`reset-input-defaults.sh`).
* **Location / VPN:** `vpn-location-sync.sh` runs as root via `pkexec`/NM dispatcher and reads only `/usr/local/share/vpn-location-sync/home.geolocation` (never user-writable repo paths). Re-run `security/scripts/location-setup.sh` after changes.
* **Browser policies:** edit `security/browsers/policies/chromium-base.json` plus brand overlays (`chrome-extra.json`, `brave-extra.json`), validating key names against upstream policy schemas.

## Scripts, Helpers & Tests

* Every `.sh` script must be executable (`chmod +x`), avoid hardcoded usernames, and pass `bash -n` + `ShellCheck -x -S warning -s bash` (`make lint`).
* Run tests via `make test` (`tests/*.test.sh`), `make test-stage-a` (`stage-a/tests/`), and `bash scripts/lint-docs.sh` (all run in CI via `make ci`).
* **Health checks:** `scripts/check.sh` sources `scripts/check.d/NN-area.sh` in numeric order. Add new checks as numbered files using `✓`, `check_fail`, and `○`.
* **Shared libraries (source, do not copy):**
  * `provision/lib/`: `dmi.sh`, `pkg-lists.sh`, `progress.sh`, `rust-toolchain.sh`, `skel.sh`, `stage-a-handoff.sh`, `ui-menu.sh`
  * `system/templates/`: ThinkPad charge threshold templates
  * `ai/lib/`: `agent-skills.sh` (+ `ai/rules/lib/vscode-settings-merge.sh` for JSON telemetry merges)
  * `desktop/lib/`: `input.sh`
  * `security/lib/`: `browsers.sh`, `telemetry.sh`, `lab-malware-zone.sh`
  * `labs/lib/`: `lab-workdir.sh`

### Subsystem Script Map

| Subsystem | Path | Key entrypoints |
|-----------|------|-----------------|
| Orchestration | root & `provision/` | `install.sh`, `stow-only.sh`, `uninstall.sh`, `provision/scripts/{configure,apply-profile,detect-profile,install-flatpaks,install-aur,bootstrap-aur,install-fonts,install-photogimp,install-foxcage,install-re-extras,post-update,p15-dotfiles-preflight,arch-install-vmtest,vm-stageb-run,vm-stageb-guest}.sh` |
| System | `system/` | `system/scripts/{system-setup,zram-setup,tmp-to-disk,fingerprint-setup,rebuild-v3,thinkpad-charge-thresholds,thinkpad-health,snapshot}.sh` |
| AI tooling | `ai/` | `ai/scripts/{sync-agent-skills,headroom-setup,install-headroom,install-rtk,ai-stack-setup,ollama-setup,agent-run,install-coding-agents,install-caveman,install-ponytail,install-android-ui-skills,install-ecosystem-skills,install-re-skills,install-rea,install-ghidra-cli,install-obscura}.sh` + `ai/rules/` |
| Desktop | `desktop/` | `desktop/scripts/{gnome-session-setup,gnome-console-setup,install-extensions,fetch-gnome-extensions,install-dash2dock,rice-setup,theme-setup,theme-packs,gdm-setup,backup-gsettings,restore-gsettings,reset-input-defaults,cleanup-input-overrides,git-setup,nvim-setup}.sh` |
| Security | `security/` | `security/scripts/{privacy-hardener,browser-hardening,firewalld-lab-zones,firewalld-tailscale,location-setup,vpn-location-sync,proton-connectivity-check,proton-seed-serverlist,network-dns-setup,dnscrypt-setup,usbguard-setup,ops-hygiene,secrets-bootstrap,personal-backup}.sh` |
| Labs & VMs | `labs/` | `labs/scripts/{labs-setup,lab-detonate,lab-mcp,kali-disposable,kali-lan-host-prep}.sh` |
| Local builds | `builds/` | `builds/scripts/build-st.sh` |
| Diagnostics & Stage A | `scripts/`, `stage-a/` | `scripts/{check,drift,validate-configs,lint-docs,list-stow-files,minimal-stow,arch-install*}.sh`, `scripts/check.d/*.sh`, `stage-a/` |

## Commit Messages & License

Use [Conventional Commits](https://www.conventionalcommits.org/) (`feat:`, `fix:`, `docs:`, `refactor:`, `chore:`). Contributions are licensed under MIT.
