# Changelog

## [Unreleased]
- P15 dotfiles path: `profiles/p15.sh` (hostname alias → `thinkpad-p15.sh`); `install.sh` applies machine profile **after** `pacman.txt` so Optimus NVIDIA packages exist before `nvidia-*.service` / UKI rebuild; `scripts/p15-dotfiles-preflight.sh` checks session/sudo/network/DMI/GPU before clone install.
- system-setup: X1-only files (`/etc/kernel/cmdline`, `i915.conf`, X1 sleep/logind, fingerprint port rule) install only on ThinkPad X1 hardware (`is_thinkpad_x1`; `SYSTEM_IS_X1` override for tests). Otherwise the X1 cmdline replaced the P15 profile's `nvidia_drm.modeset=1` and X1 sleep/port settings applied to other laptops. On non-X1 hosts old stow symlinks to those files are removed (a stowed cmdline is kept as a real file). Tests cover non-X1 and default DMI detection.
- Cleanup: `profiles/thinkpad-x1.sh` drops steps superseded by `install.sh` / `system-setup.sh` (zram materialize, i915 symlink materialize, unconditional UKI rebuild + manual `sbctl sign` — sbctl's mkinitcpio post hook signs rebuilt UKIs — and a second input-override cleanup). Docs de-duplicated: hardened guide Phases 17b–17e now link the README sections; `system/` behavior documented once (hardened Phase 1); `gnome/keybindings.md` keeps shortcuts only; README maintenance table no longer split by a blank line. Hardened guide aligned with `arch-install.sh` (bluez in pacstrap, bluetooth + PPD enabled, `iio-sensor-proxy` not enabled, no duplicate package installs).
- System files: `stow/system/` is no longer stowed to `/`. New `scripts/system-setup.sh` (run by `install.sh`) installs it as root-owned regular files, removes leftover stow symlinks, backs up replaced files to `/var/backups/dotfiles-system/`, rewrites `rd.luks.name=` to the booted LUKS UUID, and reloads ufw/udev or rebuilds UKIs as needed. Fixes a VM-reproduced boot failure: `ufw.service` starts before `/home` mounts, so a stowed `before.rules` dangled and the half-loaded firewall dropped reply traffic (DNS) while `ufw status` showed `active`. Also stops user-writable root config. `scripts/check.sh` flags `/etc` symlinks into `stow/system`; firewall verify steps now check `systemctl is-active ufw` + the `ESTABLISHED` rule.
- system-setup: make parent dirs of managed files root-owned and traversable (a `700` `/etc/environment.d` from a umask-077 copy hid `99-wayland.conf` from the user session); reload ufw when `ufw status` is active (unit may be `failed` with half-loaded rules); `SYSTEM_ROOT`/`PROC_CMDLINE` test mode with `tests/system-setup.test.sh`, run in CI. `check.sh` searches `/etc` with `sudo -n` when cached so 700 dirs are covered.
- GDM: `scripts/gdm-setup.sh` installs greeter files per file as root (was `sudo rsync -a`, which copied the repo owner onto `/etc`, `/etc/systemd`, `/etc/udev`, `/etc/dconf`, `/etc/gdm`: user-writable `/etc`, pacman hook "unsafe path transition"). Re-running it also restores those parent dirs to root and `go+rx` (the old copy also carried the repo's `700` mode).
- install.sh / stow-only.sh (`scripts/lib/skel.sh`): remove unmodified `/etc/skel` copies (e.g. `.bashrc`) that a stow package replaces; on a fresh user they made stow skip the whole `bash` package.
- arch-install-vmtest: default `DISK_SIZE` 80G (full `./install.sh` uses ~40G).
- arch-install: install browser Flatpaks one at a time and report failures. Chrome (extra-data) cannot install inside a chroot (no user namespaces) and previously aborted the whole transaction, skipping Brave, Zen and Proton VPN; failed refs are removed so `install-flatpaks.sh` retries them after first boot.
- Docs / boot: clarify `stow/system/etc/kernel/cmdline` is a machine-specific template; refresh tracked `rd.luks.name=` to the current X1 LUKS UUID; document ThinkPad BIOS Sleep **Windows and Linux** = s2idle vs **Linux** = S3/`deep`, and live `deep` drift; fix Phase 1 anchor to `#phase-1--bios--uefi-configuration`. Updated `docs/fresh-install-coding-re.md`, `docs/hardened-arch-gnome.md`, README, CONTRIBUTING.
- Docs: added `docs/fresh-install-coding-re.md` (ThinkPad X1 Yoga Gen 5 purpose guide: coding, RE, malware isolation); linked from README, hardened guide intro + Phase 27.
- Refactor: index-only `scripts/list-stow-files.sh` for `all_stow_files.txt` (CI + pre-commit; Cache guard in CI); soft-fail ghidra-cli in `install.sh`; dedupe `.gitignore`; document `builds/`, `skills/`, `ai-rules/`, alt terminals, ptyxis/ghidra, Proton seed + extension logout; CONTRIBUTING script map; hardened guide Phase 17f; Dash2Dock Shell 51.
- CPU: makepkg drop-in and shell `GOAMD64`/`RUSTFLAGS` target x86-64-v3; `scripts/rebuild-v3.sh` rebuilds zstd/xz/lz4, signed with a local rebuild-v3 key. extra/ still replaces them on `-Syu`. Documented in README and `docs/hardened-arch-gnome.md` Phase 17b2.
- Headroom: `install-headroom.sh` upgrades in place; docs cover persistent-service (`headroom-default.service`), `--no-telemetry`, shell Base URL exports vs `headroom doctor` warn, MCP (`--force`), and RTK as a separate binary outside `~/.headroom/bin`. Removed obsolete `stow/omniroute` package.
- CI: `.github/workflows/ci.yml` checks `all_stow_files.txt` freshness, `bash -n` on install/profile/scripts, and `scripts/lint-docs.sh` (markdownlint: heading blanks + tables). Kit `pre-commit` refreshes or fails stale `all_stow_files.txt` when `stow/` exists (global `core.hooksPath`; not repo `.git/hooks`).
- Docs: fact-check pass across README, CONTRIBUTING, CHANGELOG, `gnome/keybindings.md`, and `docs/hardened-arch-gnome.md` (sleep, profiles, Starship, install order, keybindings, Zen ID, zram, changelog drift). Headroom version pin dropped; Bash `Ctrl+R` documented; historical 1.15/1.17/1.18 bullets marked superseded; warn that stowed kernel cmdline is machine-specific (LUKS UUID).
- Suspend: stowed kernel cmdline and `sleep.conf.d` use **s2idle** (`mem_sleep_default=s2idle`, `MemorySleepMode=s2idle`); `arch-install.sh` matches. Supersedes the 1.17.0 S3 `deep` claim.
- Profiles: `thinkpad-p15.sh` and P15 detection stay on **main**; `has_nvidia_gpu()` restored in `scripts/lib/dmi.sh`. `apply-profile.sh` applies exactly one profile (no `nvidia.sh`).
- Zen: Flatpak ID is `app.zen_browser.zen` (`arch-install.sh` + hardened guide aligned; old `io.github.zen_browser.zen` was stale).
- Starship: Gruvbox Rainbow (`gruvbox_dark`); `command_timeout = 3000`. Crampack installer remains legacy only.
- Waydroid: NAT masquerade is `waydroid-nat.service`, not a `*nat` block in `ufw/before.rules`.
- Neovim: Catppuccin/`palette.lua` overlay is gone; Lazy fallback colorscheme is `habamax`.
- Zsh: pacman `zsh-autocomplete` was replaced by zinit + fzf-tab (v1.11) and stays removed.
- Kitty: right-click copies the selection to the clipboard (`mouse_map right press ungrabbed copy_to_clipboard`); Shift+right-click still extends the selection.
- Starship: switched to the official [Gruvbox Rainbow](https://starship.rs/presets/gruvbox-rainbow) preset; Crampack installer kept as legacy (`scripts/install-starship-crampack.sh`).
- Packages: added `rtkit` (realtime scheduling for PipeWire/gnome-shell) and `bluez`/`bluez-utils`; `acpi_call-dkms` replaces `acpi_call`/`acpi_call-lts` (dkms builds for `linux-lts` and `linux-hardened`).
- Bluetooth: `bluetooth.service` enabled in `profiles/thinkpad-x1.sh` and the `arch-install.sh` base service list.
- Git: `core.fsmonitor` disabled for repos under `~/.cache/` (includeIf → `no-fsmonitor.conf`) — fsmonitor daemon sockets corrupted yay cache clones (`fatal: not a git repository` on PKGBUILD fetch).
- Gitignore: VSCodium runtime state in the stowed `~/.config/VSCodium` (keeps `User/` settings, keybindings, snippets), third-party GNOME extensions in the stowed extensions dir (keeps `proton-vpn@helllguest`), and Claude Code `settings.local.json.tmp.*` leftovers.
- GNOME input: removed custom touchpad/mouse/keyboard overrides from `gnome/dconf/user.conf`; stock defaults via `scripts/reset-input-defaults.sh`; legacy synaptics udev/inhibit cleanup in `scripts/cleanup-input-overrides.sh`.
- Location: fixed `vpn-location-sync.sh` under `pkexec`/NetworkManager (resolve home coords via `PKEXEC_UID`; `/usr/bin/curl`; installed template at `/usr/local/share/vpn-location-sync/home.geolocation`); Proton VPN panel extension waits for sync and reports success/failure.
- Shell: removed invalid fzf `copy-selection` bind (not in fzf 0.72); safe `FZF_DEFAULT_OPTS` in zsh and bash; `DOCKER_HOST` auto-selects Podman socket when present, otherwise Docker (`/var/run/docker.sock`).
- Health: `check.sh` warns when `/etc` is not owned by root (pacman hook failures).
- Headroom: `scripts/install-headroom.sh` + `scripts/headroom-setup.sh` (pipx `headroom-ai[all]`); shell helpers `hr-claude`, `hr-cursor`, `hr-proxy`; `python-pipx` in `packages/pacman.txt`; wired into `install.sh` and `check.sh`.
- PhotoGIMP: `scripts/install-photogimp.sh` applies [Diolinux/PhotoGIMP](https://github.com/Diolinux/PhotoGIMP) over pacman `gimp` (maps `3.0` → live `~/.config/GIMP/<major.minor>`; skips stale `pluginrc`; patches Flatpak config if present; rewrites `.desktop` Exec to native `gimp`; hides stock `gimp.desktop`); `gimp` + `cfitsio` in `packages/pacman.txt`; wired into `install.sh`.
- Dash2Dock: `scripts/install-dash2dock.sh` installs [Dash2Dock Animated](https://github.com/icedman/dash2dock-lite) from EGO v92 (`dash2dock-lite@icedman.github.com`; AUR package stale); listed in `gnome/extensions.txt` + `user.conf`; wired into `install.sh` / `gnome-session-setup.sh`. Wayland needs logout to load.
- Docs: synced README, CHANGELOG, CONTRIBUTING, `gnome/keybindings.md`, and `docs/hardened-arch-gnome.md` — Docker/Podman, fzf, location sync, GNOME input, fnm, Headroom, PhotoGIMP, Dash2Dock, troubleshooting.
- Refactor: extracted `scripts/apply-profile.sh`, `scripts/lib/dmi.sh`, and `scripts/lib/browsers.sh`; `packages/browsers.txt` is the browser flatpak source of truth; Chromium policies split into base + chrome/brave extras (merged with jq at deploy).
- Browsers: added Google Chrome and LibreWolf flatpaks; `scripts/browser-hardening.sh` deploys managed policies for Chrome/Brave (`browsers/policies/*.json`); Zen prefs via `browsers/zen/user.js` into each profile dir (fixes invalid `.zen/user.js` stow path) plus `/etc/firefox/policies/policies.json`; LibreWolf relies on upstream hardening.
- ThinkPad X1 profile: re-sign UKIs with `sbctl` after `mkinitcpio -P` when Secure Boot keys exist (pacman hook does not run on manual rebuilds).
- Docs: Secure Boot (Phase 23), ESP multiboot cleanup, profile detection, and UKI re-sign flow synced across `README.md`, `CONTRIBUTING.md`, and `docs/hardened-arch-gnome.md`.
- Install: hardware-based profile detection (`scripts/detect-profile.sh`) when `profiles/$(hostname).sh` is missing; picks `thinkpad-x1`, `thinkpad-p15`, or `laptop`. `laptop.sh` delegates to `thinkpad-x1.sh` only on X1 models.
- Installer: on ESP reuse, `arch-install.sh` now removes stale Arch UKIs (`/EFI/Linux/arch-linux*.efi`), legacy `vmlinuz`/`initramfs` on the ESP, and old systemd-boot entries (`arch*.conf`, `linux-*.conf`) before rebuilding — multiboot-safe (Windows/other `/EFI/*` untouched).
- Docs: aligned README, CONTRIBUTING, and `docs/hardened-arch-gnome.md` Phase 27 with current `install.sh` flow (flatpak/AUR auto, `user.conf`, zram materialize, GNOME session requirement); fixed stale VS Code flatpak, battery-threshold, and stow-only claims.
- Install: fixed flatpak installs (`-y` not `--noconfirm`); added `install-flatpaks.sh`, `install-aur.sh`, `bootstrap-aur.sh` (auto paru); wired location setup into `install.sh`.
- Packages: `pacman.txt` syncs `linux-lts`/`linux-hardened`, `starship`, `flatpak`; dropped `linux-zen` and `python-pywal`.
- Starship: restored Crampack palette definitions removed during theming refactor.
- Zen: stow path fixed for Flatpak (`~/.var/app/app.zen_browser.zen/.zen/`).
- GNOME: deduplicated AUR extension installs; `install-extensions.sh` no longer fails headless sessions.
- VPN: polkit rule uses `wheel` group; `proton-connectivity-check.sh` detects Flatpak app; removed hardcoded `jondoe` from `vpn-location-sync.sh`.
- Health: `check.sh` verifies flatpaks, bash/shell symlinks; no duplicate `validate-configs` run.

## [1.19.0] - 2026-06-10
- Installer: added `scripts/arch-install.sh` — curl-able, hardened bare-metal Arch installer implementing `docs/hardened-arch-gnome.md` end-to-end: LUKS2 (argon2id) + Btrfs (`@ @home @snapshots @var_log @var_cache @tmp`) + `linux-lts` primary / `linux-hardened` fallback Unified Kernel Images + systemd-boot + `sbctl` Secure Boot + minimal GNOME. AUTO whole-disk or MANUAL partitioning with EFI optional/reuse (multiboot-safe). Reads prompts from `/dev/tty`; passwords never written to disk. VM-validated end-to-end (boots to GNOME).
- Installer: `scripts/arch-install-vmtest.sh` — UEFI/OVMF qemu harness that serves the installer over loopback and boots the Arch ISO against a blank virtual disk (host untouched); `hostfwd 2222→22` for SSH.
- Kernels: switched primary from `linux-zen` to `linux-lts` (stability) with `linux-hardened` as fallback; dropped zen. UKI presets carry the required `ALL_kver` (without it `mkinitcpio -P` builds no UKIs).
- `/tmp`: `scripts/tmp-to-disk.sh` moves `/tmp` off the RAM-capped tmpfs onto a dedicated btrfs `@tmp` subvolume (`nodatacow`, excluded from snapshots); added `@tmp` to the install guide.
- GNOME: install guide uses a curated minimal set instead of the full `gnome` meta-package.
- ThinkPad: removed obsolete `throttled` and `tp_smapi` (AUR) and `thermald` (pacman) — on 10th-gen Comet Lake the CPU undervolt is locked (Plundervolt microcode), `tp_smapi` is pre-2011 only, and thermal is firmware-managed (DPTF/DYTC). Profile no longer enables them.
- Zsh: hardening (`umask 077`, `NO_CLOBBER`, `RM_STAR_WAIT`, `HIST_VERIFY`, `HISTORY_IGNORE` secret filter, `compinit -i`) + richer autocomplete (autosuggest `history+completion` strategy, fuzzy `_approximate` completer, completion cache).
- Hardening: install adds a `kernel.unprivileged_userns_clone` sysctl (leading-`-`/ignore-if-absent) so Flatpak/Podman/browser sandboxes work under `linux-hardened`.

## [1.18.0] - 2026-06-02
- Waydroid: enabled container internet via NAT masquerade of the `192.168.240.0/24` subnet; persisted as a `*nat` block in tracked `stow/system/etc/ufw/before.rules` (source-based, survives wifi/VPN iface changes). Host-side `ufw allow 53/udp` + `67/udp` for the container's dnsmasq/DHCP. *(Superseded: NAT now lives in `waydroid-nat.service`; see Unreleased.)*
- Starship: raised `command_timeout` 500 → 1300 ms to stop "git timed out" warnings when `git_metrics` runs `git diff` during fsmonitor warm-up. *(Superseded: current `stow/starship` uses 3000 ms; see Unreleased.)*
- GNOME: disabled keyboard key repeat (`peripherals.keyboard repeat=false`) in `gnome/dconf/user.conf`.
- Power: finalized PPD-only stack — documented removal of TLP (conflicts with power-profiles-daemon) and thermald (self-exits on X1: `dytc_lapmode present, can't run on this platform`; thermal is firmware-managed). Phase 14 install/enable + battery-threshold steps switched to `power-profiles-daemon` and `thinkpad_acpi` sysfs.
- UFW: silenced `[UFW BLOCK]` log spam by silently dropping link-local multicast (`224.0.0.0/4`) + IGMP in `before.rules` (same deny posture, no logging).
- Shell: added terminal-agnostic long-command desktop notifications — `notify-send` fires when an interactive command exceeds `CMD_NOTIFY_THRESHOLD` (default 10s), with ✓/✗ status, exit code and duration. Core + zsh hooks in `.shell-functions`; bash registers via atuin/ble.sh preexec arrays (DEBUG-trap fallback) at the end of `.bashrc`. Works in ghostty, kitty and GNOME Console; skipped on plain TTY/SSH.
- Theme auto-switch: fixed broken day/night switching. Catppuccin GTK theme names were missing the `+default` suffix (installed as `catppuccin-{latte,mocha}-blue-standard+default`) so GTK fell back to Adwaita; corrected in `user.conf` + `extensions.conf`. Set Night Theme Switcher to follow GNOME Night Light (`time/manual-schedule=false`) instead of an un-customized manual schedule, so theme re-syncs on resume/login (no more missed sunrise/sunset).
- Theme auto-switch (NTS v82): Night Theme Switcher v82 dropped built-in gtk/cursor variants; obsolete `gtk-variants` dconf keys were ignored. Added `scripts/night-theme-hook.sh` hooked via NTS sunrise/sunset commands for Catppuccin latte/mocha GTK; NTS `color-scheme` set to prefer-light/prefer-dark; removed hardcoded gtk/color-scheme/cursor from `user.conf`; stopped `theme-switch.sh` forcing prefer-dark when NTS active; Dubai fallback location in `extensions.conf`.

## [1.17.0] - 2026-06-02
- Suspend: switched X1 to S3 `deep` via `sleep.conf.d` (`SuspendState=mem` + `MemorySleepMode=deep`); lower standby drain than s2idle. *(Superseded: current cmdline + `sleep.conf.d` pin s2idle; see Unreleased.)*
- Power: hard-disabled unused Synaptics fingerprint reader (06cb:00bd) at its USB port via `72-fingerprint-disable.rules` — kills resume `xHC error`/`usb 1-9` reset spam and idle drain.
- Ghostty: fixed config errors for 1.3.x — dropped removed `gtk-prefer-dark-theme`, `quick-terminal-size = 40%` (unit required), `keybind` key `backquote` (was `grave`); quick terminal now `global:` toggle.

## [1.16.0] - 2026-05-31
- GNOME session: workspaces, touchpad, keyboard repeat, night light (Dubai), power/lid rules.
- Extensions: Blur My Shell, Just Perfection, Tactile, Vitals, Gesture Improvements, Night Theme Switcher.
- Catppuccin GTK day/night stack; `gnome/dconf/user.conf` + `extensions.conf`.
- X1 Yoga tablet mode handler (`yoga-tablet-mode.service`) via iio-sensor-proxy + lid state.

## [1.15.0] - 2026-05-31
- Full Lazy.nvim stack: blink.cmp, Mason LSP, conform, treesitter, telescope, flash, ufo, noice, DAP, neotest.
- Modular layout under `lua/config/` and `lua/plugins/`; `scripts/nvim-setup.sh` for headless plugin/parser sync.
- Catppuccin colorscheme + palette.lua overlay; vim-kitty-navigator for kitty split navigation. *(Superseded: Catppuccin/`palette.lua` removed; Lazy fallback is `habamax`; see Unreleased.)*

## [1.14.0] - 2026-05-31
- Global git config: rebase stack, rerere, histogram diff, delta side-by-side, URL shorthands.
- Global gitignore, conditional work/dev includes, commit hooks (Conventional Commits, branch prefix, pre-push).
- `scripts/git-setup.sh` for identity, GPG/SSH signing, hooks, and maintenance timer; delta colors synced via `theme-switch.sh`.

## [1.13.0] - 2026-05-31
- GDM login screen: Wayland-only, greeter dconf (no user list, fingerprint-ready), solid palette bg.
- Systemd GDM override (OOM, VA-API iHD, restart) and Intel udev Wayland rule for 8086:9b41.
- `scripts/gdm-setup.sh` and optional `scripts/fingerprint-setup.sh`; GDM bg synced via `theme-switch.sh`.
- Skipped fragile gnome-shell.css patching (GNOME 50 path changes).

## [1.12.0] - 2026-05-31
- Production kitty/ghostty configs: performance tuning, splits, quick terminal, paste protection.
- Full 16-color terminal themes synced via `theme-switch.sh`.
- Added GNOME Console setup script and Super+Return → kitty.

## [1.11.0] - 2026-05-31
- Integrated dev shell stack from external config: zinit, atuin, fzf-tab, forgit.
- Added modern CLI aliases (eza, bat, rg, fd, etc.) and fzf git/file helpers.
- Enhanced Crampack Starship with git metrics, runtimes, battery, cmd duration.
- Added `stow/atuin/` and `.shell-git`; optional ble.sh for bash.

## [1.10.1] - 2026-05-31
- Fix i915 tuning for UKI/initramfs: kernel cmdline params and materialize modprobe.d symlinks.

## [1.10.0] - 2026-05-31
- ThinkPad X1 Yoga Gen 5 tuning: i915, kernel cmdline, Wayland env, sleep/logind.
- Switched power stack to `thermald` + `power-profiles-daemon` (TLP removed).
- Added `intel-media-driver`, VA-API, and system config stow package.

## [1.9.1] - 2026-05-31
- Expanded `install-fonts.sh` with 15 top Nerd Font packages for terminals and Crampack Starship.

## [1.9.0] - 2026-05-31
- Added **Crampack** Starship preset (Nerd Font standard) with palette sync via `ts`/`tt`.
- Added `scripts/install-starship-crampack.sh` and upstream one-liner support.
- Removed legacy `theming/templates/starship.toml` generator.

## [1.8.0] - 2026-05-31
- Enabled **zsh-autocomplete** for real-time, no-Tab completion menu.
- Fixed Zsh history persistence (50k lines) and Bash shared-function guard.
- Enhanced **zsh-autosuggestions** with history + completion strategies.
- Updated all documentation: README, CONTRIBUTING, keybindings, hardened guide.

## [1.7.1] - 2026-05-31
- Aligned GNOME dconf snapshot with live system (Default shell theme, wallpaper, battery display).
- Added wallpaper to Zukitwo palette; fixed stow to target `$HOME` in install scripts.
- Renamed ThinkPad profile to `thinkpad-x1.sh` to match hostname detection.
- Tracked zsh completion plugins in pacman; improved health check for stowed config dirs.

## [1.7.0] - 2026-05-30
- Configured **Android SDK** environment variables (`ANDROID_HOME`, `PATH`).
- Added terminal alias `as` for Android Studio (Flatpak).
- Added **Android Studio** to Flatpak tracking list.

## [1.6.0] - 2026-05-30
- Fixed missing pager errors by installing **less**, **man-db**, and **man-pages**.
- Configured **PAGER** and **LESS** environment variables for improved CLI navigation.
- Enabled mouse and scroll wheel support for the pager.

## [1.5.0] - 2026-05-30
- Added **rclone** for cloud storage management (Google Drive, etc.).
- Integrated **zram-generator** configuration into dotfiles tracking.
- Verified system swap performance and compression with `zstd`.

## [1.4.0] - 2026-05-29
- Removed custom GNOME Shell theme generation and infrastructure.
- System now uses the default GNOME Shell theme with custom GTK, Terminal, and Nvim themes.

## [1.3.0] - 2026-05-29
- Integrated **Zukitwo** theme into the dynamic theming engine.
- Created `zukitwo.json` palette based on Zukitwo GTK colors.
- Fixed `Generated-Theme` by importing system default shell styles as a foundation.
- Improved Quick Settings menu layout with flexible resizing and better spacing.
- Added **caveman** tool and extension for token-efficient communication.

## [1.2.0] - 2026-05-29
- Added Bash configuration to dotfiles.
- Implemented CWD (Current Working Directory) tracking for new terminal tabs.
- Added OSC 7 directory reporting to Zsh and Bash.
- Configured Kitty and Ghostty to open new tabs/windows in the current directory.

## [1.1.0] - 2026-05-17
- Added machine profiles support.
- Modularized Zsh configuration.
- Added font and extension installers.
- Added health check and maintenance scripts.
- Improved .gitignore for security and cleanliness.

## [1.0.0] - 2026-05-17
- Initial release with Arch + GNOME structure.
- GNU Stow support.
- Basic Neovim, Zsh, and Terminal configs.
