# Changelog

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
- Waydroid: enabled container internet via NAT masquerade of the `192.168.240.0/24` subnet; persisted as a `*nat` block in tracked `stow/system/etc/ufw/before.rules` (source-based, survives wifi/VPN iface changes). Host-side `ufw allow 53/udp` + `67/udp` for the container's dnsmasq/DHCP.
- Starship: raised `command_timeout` 500 → 1300 ms to stop "git timed out" warnings when `git_metrics` runs `git diff` during fsmonitor warm-up.
- GNOME: disabled keyboard key repeat (`peripherals.keyboard repeat=false`) in `gnome/dconf/user.conf`.
- Power: finalized PPD-only stack — documented removal of TLP (conflicts with power-profiles-daemon) and thermald (self-exits on X1: `dytc_lapmode present, can't run on this platform`; thermal is firmware-managed). Phase 14 install/enable + battery-threshold steps switched to `power-profiles-daemon` and `thinkpad_acpi` sysfs.
- UFW: silenced `[UFW BLOCK]` log spam by silently dropping link-local multicast (`224.0.0.0/4`) + IGMP in `before.rules` (same deny posture, no logging).
- Shell: added terminal-agnostic long-command desktop notifications — `notify-send` fires when an interactive command exceeds `CMD_NOTIFY_THRESHOLD` (default 10s), with ✓/✗ status, exit code and duration. Core + zsh hooks in `.shell-functions`; bash registers via atuin/ble.sh preexec arrays (DEBUG-trap fallback) at the end of `.bashrc`. Works in ghostty, kitty and GNOME Console; skipped on plain TTY/SSH.
- Theme auto-switch: fixed broken day/night switching. Catppuccin GTK theme names were missing the `+default` suffix (installed as `catppuccin-{latte,mocha}-blue-standard+default`) so GTK fell back to Adwaita; corrected in `user.conf` + `extensions.conf`. Set Night Theme Switcher to follow GNOME Night Light (`time/manual-schedule=false`) instead of an un-customized manual schedule, so theme re-syncs on resume/login (no more missed sunrise/sunset).
- Theme auto-switch (NTS v82): Night Theme Switcher v82 dropped built-in gtk/cursor variants; obsolete `gtk-variants` dconf keys were ignored. Added `scripts/night-theme-hook.sh` hooked via NTS sunrise/sunset commands for Catppuccin latte/mocha GTK; NTS `color-scheme` set to prefer-light/prefer-dark; removed hardcoded gtk/color-scheme/cursor from `user.conf`; stopped `theme-switch.sh` forcing prefer-dark when NTS active; Dubai fallback location in `extensions.conf`.

## [1.17.0] - 2026-06-02
- Suspend: switched X1 to S3 `deep` via `sleep.conf.d` (`SuspendState=mem` + `MemorySleepMode=deep`); lower standby drain than s2idle.
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
- Catppuccin colorscheme + palette.lua overlay; vim-kitty-navigator for kitty split navigation.

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
