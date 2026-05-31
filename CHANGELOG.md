# Changelog

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
