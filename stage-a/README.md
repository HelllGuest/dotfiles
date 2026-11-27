# stage-a (formerly t14s-arch-install)

Hardened **Arch Linux** Stage A installer for **ThinkPad T14s Gen 3 AMD** (`21CQ`/`21CR`), **ThinkPad P15 Gen 1** (`20SU`, Optimus NVIDIA), and **generic x86_64 UEFI** (`HW_PROFILE=generic`, auto-detects CPU/GPU/`x86-64-v3`).

* **Core stack:** UEFI + systemd-boot + UKIs (`linux-lts` default; optional `linux-hardened`/`linux`/`linux-zen`) + `sbctl` + LUKS2 (`argon2id`) + Btrfs subvolumes/Snapper (or ext4/XFS) + AppArmor + `firewalld` (`nftables`, default `drop`, UFW masked) + zram + `s2idle` + ThinkPad 70–80 charge window (skipped on VMs/non-ThinkPads).
* **Interactive & unattended:** TUI by default (`dialog` → `whiptail` → `plain`), or `T14S_NONINTERACTIVE=1` with answers + mode-`0600` secrets file.
* **UX inspiration:** [archfi](https://github.com/MatMoul/archfi) and [archdi-pkg](https://github.com/MatMoul/archdi-pkg) (not ported: i18n packs, DE zoo, multi-bootloader, BIOS modes).
* **Stage B (dotfiles):** lives in the parent repo ([../README.md](../README.md): `./install.sh` and `provision/scripts/configure.sh`).

---

## Requirements & BIOS

* Official Arch ISO, **UEFI**, root shell, working network, ESP + ≥8 GB root (shared ESP ideally ≥1 GB).
* BIOS (`F1`): Secure Boot **Disabled** (enroll after first boot), Sleep **Windows and Linux** (`s2idle`), AMD **SVM** / Intel **VT-x** + **IOMMU** enabled.

## Run (from the Arch ISO)

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/HelllGuest/dotfiles/main/stage-a/install.sh)
```

*(Legacy URL `.../t14s-arch-install/install.sh` remains as a compatibility shim.)*

Use `bash <(curl …)` so menus keep a TTY. Override UI with `T14S_UI=dialog|whiptail|plain`.

### Reinstall Next to Windows (shared ESP)

1. Back up `/home` (Arch root is erased), save the Windows BitLocker recovery key, and disable Windows Fast Startup.
2. BIOS: Secure Boot → Reset to Setup Mode, Secure Boot off; boot Arch ISO.
3. Choose **MANUAL**: `ROOT` = existing Arch partition, `EFI` = existing FAT32 ESP with **reuse** (default whenever a FAT32 ESP exists; Review must show `EFI … (reuse)`).
4. `EFI/Microsoft` and Windows partitions are untouched; old Arch files are cleaned (`CLEAN_ESP_ARCH=Y`), `BOOTX64.EFI`/`loader.conf` are backed up as `*.pre-arch.bak`, and `Linux Boot Manager` is placed first in `BootOrder`.
5. After first boot: `sudo sbctl verify && sudo sbctl enroll-keys -m` (if not enrolled during install), enable Secure Boot, and run `bash tests/host-check.sh`.

Rehearse in a VM: `VM_BOOTSTRAP=tests/vm-dual-bootstrap.sh FRESH=1 bash tests/vm-run.sh`.

---

## What Gets Installed

### Always Installed (base)

* `base`, `base-devel`, `linux-lts` (+ headers), `linux-firmware` + matching CPU ucode (`amd-ucode`/`intel-ucode`), `cryptsetup`, FS tools (`btrfs-progs`/`snapper`/`snap-pac` for `btrfs`, `e2fsprogs`, or `xfsprogs`), `networkmanager`, `sudo`, `zsh`, `git`, `vim`, `nano`, `reflector`, `pacman-contrib`, `mkinitcpio`, `zram-generator`, `apparmor`, `firewalld`, `sbctl`, `efibootmgr`, `xdg-user-dirs`, `wireless-regdb`.
* Configures GPT/LUKS2, Btrfs subvolumes (`@`, `@home`, `@snapshots`, `@var_log`, `@var_cache`, `@tmp` with `nodatacow`, `compress=zstd:3`), UKIs under `/boot/EFI/Linux/`, kernel cmdline (`rd.luks.name`, `rd.luks.options=discard`, IOMMU/pstate, `mem_sleep_default=s2idle`, AppArmor LSM), `/etc/systemd/sleep.conf.d/s2idle.conf`, `99-security.conf` sysctl, `pacman.conf` (`Color`, `ILoveCandy`, `VerbosePkgLists`, `ParallelDownloads`, `DisableDownloadTimeout`), `/etc/makepkg.conf.d/t14s.conf` (`x86-64-v3`, `!debug`, `lto`), Snapper limits, `%wheel` sudoers, and ThinkPad charge/touchpad/lid rules (unless `SKIP_THINKPAD_HW=Y`).
* Saves mode-`0600` answers (never passwords) to `/tmp/t14s-answers.env` and `/root/t14s-answers.env`; shreds `/root/.install-secrets` and chroot scripts; sets `SNAP_PAC_SKIP=y` during chroot.

### Optional Presets & Checklists

Presets **`gnome`**, **`dev`**, **`minimal`**, and **`vm`** (Quick VM) seed the checklists:

* **Quick VM (`PRESET=vm`, auto-selected in interactive VMs):** fast 4-screen path (Profile + Headless/GNOME → Disk → Identity/SSH key → Review). Defaults to unencrypted `ext4`, 1G ESP, skips `linux-firmware`/ucode (`VM_FAST_PKG=Y`), enables `sshd` + `ttyS0` serial console, and installs the matching VM guest agent (`qemu-guest-agent`/`spice-vdagent`, `open-vm-tools`, or `virtualbox-guest-utils`).
* **Core:** minimal GNOME Wayland + hardened GDM + Flatpak/Flathub, opt-in first-boot Flatpak apps (`INSTALL_FLATPAK_APPS=Y`, off by default: Brave/Zen/LibreWolf/ProtonVPN via `t14s-flatpak-apps.timer`), Bluetooth, Nerd Fonts, `sbctl` enroll, `sshd`, CUPS, `skip_reflector`, `tuned` (+ `tuned-ppd`), TLP (console-only), thinkfan AUR note, Snapper `@home`, `btrfs-assistant`, `[multilib]`, `yay` (`yay-bin`, pinned `YAY_BIN_COMMIT`), extra UKI kernels (`linux-hardened`/`linux`/`linux-zen`), Plymouth, `/usr/local/bin/t14s-selftest`, `CLEAN_ESP_ARCH`, and Chrome Flatpak helper (`~/install-chrome-flatpak.sh`).
* **Dev / CLI:** dev toolchains (`neovim`, `python`/`pipx`, `nodejs`, `go`, `rustup`, `clang`/`gdb`/`cmake`/`ninja`/`meson`, `gh`/`glab`/`lazygit`, `code` with GNOME), CLI bundle (`ripgrep`, `fd`, `fzf`, `bat`, `eza`, `jq`, `git-delta`, `btop`, `fastfetch`), Starship, rootless Podman, Docker, libvirt/QEMU, Ollama (P15/generic, `127.0.0.1:11434`), and common utilities (`tmux`, `htop`, `rsync`, `smartmontools`, …).
* **Network:** Avahi/mDNS, WireGuard, Tailscale, fail2ban, `FW_SYNCTHING` / `FW_KDECONNECT` firewalld ports, plus free-form `T14S_EXTRA_PKGS`.

---

## TUI, Controls & Safety

### Screens (1–11)

1. Welcome · 2. Hardware (DMI / profile) · 3. Profile preset · 4. Disk (+ SMART hint) · 5. Partition (`AUTO` / `MANUAL`) · 6. LUKS passphrase & wipe · 7. Identity (hostname, timezone, locale, keymap, user, passwords) · 8. Storage (`ParallelDownloads`, FS, Btrfs compress, zram) · 9. Extras checklists, reflector country, hook · 10. Review & Erase confirm · 11. Install (progress gauge + log).

### Message severity

Uses **per-severity** `DIALOGRC` / `NEWT_COLORS` layered on an 8-color console-safe dark blue/cyan base (white-on-blue focus; no bold black fg or bright bg; severity badge text always shown so status is **not color-only**):

* **`ui_msg` / `die` (Continue only):** `info` (cyan), `warn` (yellow), `error` (red), `critical` (red+yellow), `ok` (green).
* **`ui_yesno` only:** `critical` (**Continue** / **Abort**), `erase` (**Erase** / **Abort**, default No), `warn`/`error`/`info` (**Yes** / **No**).

### Controls

* Buttons: **Next** / **Abort** on menus (**Next** / **Back** on text/password inputs once a prior step exists); **Continue** on messages; **Erase** / **Abort** on wipe confirms. `whiptail` uses `--fullbuttons` for high-contrast button focus.
* Arrows move; **Space** toggles; **Enter** = Next; **Tab** moves to buttons. (`Esc` aborts in `dialog`; in `whiptail`, Tab to Abort.)
* **Back / Previous:** menus, radios, and checklists include a **back** row once a prior step exists; inputs use **Back** (`<<` or `:back` in plain mode); declining Review's Erase confirm offers **Back** or **Jump** to any active step.
* Menus offer **[log]** and **[help]** (live log: `/tmp/t14s-install.*.log`; saved to `/var/log/t14s-install.log` mode `0600`). Scroll tall boxes with arrows, then **Tab** + **Enter**.

### Safety model

* Nothing on disk changes before the final Erase confirm (interactive AUTO requires typing the disk path + second confirm). Unattended mode wipes only after answers, `T14S_PASS_FILE`, and `T14S_I_WILL_ERASE=1` all validate.
* Packages prefetch into target cache first (`PREFETCH_TRIES=4`, `PREFETCH_BACKOFF=10`), so mirror failures abort cleanly before modifying the root. Optional package failures warn and continue (summary written to `/root/t14s-post-install.txt`).
* UKI build requires ≥64 MB free on ESP; `sbctl verify` must pass before enroll. Stuck on pacstrap? Switch to `Ctrl+Alt+F2` and `tail -f /tmp/t14s-install.*.log`.

---

## Unattended Mode

Destructive; invalid/missing answers `die` immediately. Ambient password env vars are ignored — pass secrets only via mode-`0600` `T14S_PASS_FILE`.

```bash
T14S_NONINTERACTIVE=1 T14S_I_WILL_ERASE=1 \
T14S_ANSWERS=/path/to/t14s-answers.env \
T14S_PASS_FILE=/path/to/secrets.env \
bash install.sh
# Optional remote hook: T14S_POST_HOOK_I_UNDERSTAND=1 T14S_POST_HOOK_SHA256=<64-hex> (T14S_DEFAULT_HOOK_URL sets preset default)
# Dry-run answers output: T14S_ANSWERS_OUT=/tmp/t14s-answers.env (mode 0600, no passwords)
```

Required in answers: `DISK`, `MODE`, `HOSTNAME`, `TIMEZONE`, `LOCALE`, `KEYMAP`, `USERNAME`, plus `ESP_MB` (`1024|2048|4096`) for AUTO or `EFI_PART` + `ROOT_PART` for MANUAL.

### Answers schema

`PRESET` `HW_PROFILE` `DESKTOP` `ENROLL_SB` `ENABLE_SSHD` `SKIP_REFLECTOR` `REFLECTOR_COUNTRY` `SKIP_THINKPAD_HW` `FW_SYNCTHING` `FW_KDECONNECT` `POST_HOOK_URL` `PACMAN_PARALLEL` `LUKS_WIPE` `HOSTNAME` `TIMEZONE` `LOCALE` `KEYMAP` `USERNAME` `MODE` `ESP_MB` `FORMAT_EFI` `DISK` `EFI_PART` `ROOT_PART` `ENCRYPT_ROOT` `ROOT_FS` `BTRFS_COMPRESS` `ZRAM_SIZE` `CLEAN_ESP_ARCH` `INSTALL_BLUETOOTH` `INSTALL_FLATPAK_APPS` `INSTALL_NERD_FONTS` `INSTALL_MULTILIB` `INSTALL_YAY` `INSTALL_TUNED` `INSTALL_DEVTOOLS` `INSTALL_BTRFS_ASSISTANT` `INSTALL_SNAPPER_HOME` `INSTALL_LINUX_HARDENED` `INSTALL_LINUX_STABLE` `INSTALL_LINUX_ZEN` `INSTALL_OLLAMA` `INSTALL_VM_GUEST` `VM_FAST_PKG` `VM_SERIAL_CONSOLE` `SSH_PUBKEY` `EXTRA_PKGS_LIST`. (Prefer `Y`/`N`; flags accept `1/y/yes/on`.)

---

## After First Boot & Stage B

```bash
# Quick checks after removing ISO and rebooting:
cat /sys/power/mem_sleep                                    # expect [s2idle]
lsblk -D /dev/mapper/cryptroot                              # non-zero DISC-GRAN = TRIM active
firewall-cmd --get-default-zone                             # expect drop
t14s-selftest                                               # if enabled
# Full read-only verification (~80 checks) before cloning dotfiles:
curl -fsSLO https://raw.githubusercontent.com/HelllGuest/dotfiles/main/stage-a/tests/host-check.sh
sudo bash host-check.sh                                     # or after cloning ~/dotfiles: scripts/check.sh --all
```

* **Stage B (dotfiles):** clone `~/dotfiles` and run `./install.sh` (see [../README.md](../README.md#how-to-configuresh-stage-b-tui), [firewalld zones](../README.md#how-to-firewalld-lab-zones--lab-malware), [Stage B VM](../README.md#how-to-stage-b-on-a-stage-a-qcow2), [health checklist](../README.md#live-health-checklist-non-destructive)).
* **First-boot Flatpaks (`INSTALL_FLATPAK_APPS=Y`):** `t14s-flatpak-apps.timer` retries every 5 min once online until `/var/lib/t14s/flatpak-apps.done`. Chrome helper uses `flatpak install --user -y flathub com.google.Chrome`.
* **Dev tools:** run `rustup default stable` once per user.

---

## ESP / EFI layout

The ESP is FAT with fixed standard paths: `EFI/Linux/arch-linux-*.efi` (UKIs), `EFI/systemd/systemd-bootx64.efi`, `EFI/BOOT/BOOTX64.EFI` (fallback), `loader/loader.conf`, and NVRAM entry `Linux Boot Manager` (written via `efibootmgr` from the live ISO).

### Can everything live under one directory?

**No** — firmware requires `EFI/BOOT/BOOTX64.EFI`, systemd-boot requires `EFI/systemd/` and `loader/`, and UKI auto-discovery uses `EFI/Linux/*.efi`. Keeping the standard layout with `CLEAN_ESP_ARCH=Y` avoids clutter without touching `EFI/Microsoft` or other OS dirs:

| Always cleared (pacstrap safety) | Also cleared when `CLEAN_ESP_ARCH=Y` |
| -------------------------------- | ------------------------------------ |
| `vmlinuz-linux*`, `initramfs-linux*`, `*-ucode.img` | `EFI/Linux/arch*.efi`, `loader/entries/arch*.conf`, `EFI/arch` |

`FORMAT_EFI=1` wipes the ESP (flag ignored while formatting, saved as `Y`). `linux-*.conf` is never deleted automatically.

## Securing the EFI (ESP)

Security comes from a **signed boot chain** (`sbctl` signs UKIs + systemd-boot) + BIOS supervisor password + LUKS2 root (never store keyfiles/passphrases on the ESP):

1. BIOS: clear Secure Boot keys → **Setup Mode**.
2. In the installed OS: `sbctl status && sbctl verify && sudo sbctl enroll-keys -m` (`-m` keeps Microsoft keys for dual-boot).
3. BIOS: Secure Boot → **Enabled** + supervisor password. After kernel updates, `sbctl`'s pacman hook resigns UKIs (`sudo sbctl sign-all` if `sbctl verify` ever reports unsigned files).

---

## Rehearse in a VM & Develop

```bash
FRESH=1 bash tests/vm-run.sh                                          # headless minimal VM install (9p host pkgcache; HOST_PKGCACHE=none disables)
T14S_VM_DESKTOP=Y FRESH=1 bash tests/vm-run.sh                        # GNOME desktop VM install
VM_BOOTSTRAP=tests/vm-dual-bootstrap.sh FRESH=1 bash tests/vm-run.sh  # dual-boot ESP reuse rehearsal
T14S_DRYRUN=1 bash install.sh                                         # wizard + review only (no disk writes; saves answers to T14S_ANSWERS_OUT)
```

Real installs refuse to run outside `/run/archiso` (`T14S_ALLOW_NON_ISO=1` overrides on disposable live media).

### Code Layout & CI

```text
install.sh              # thin curl orchestrator (loads lib/ and sources steps in order)
lib/00..80-*.sh         # common, UI/theme/screens/progress, answers, hardware, disk, packages, firewall, chroot entry
lib/steps/01..30-*.sh   # top-level stages (01–12 wizard, DRYRUN exits at 12; 20–30 execute)
lib/chroot/01..12-*.sh  # target chroot stages (deployed by 23-install-chroot.sh)
tests/                  # smoke.test.sh, host-check.sh, host-check.test.sh, vm-run.sh, vm-*bootstrap.sh
```

* Local `lib/` next to `install.sh` (or `T14S_LIB_DIR=./lib`) runs offline. Remote curl resolves `main` **once** to a commit SHA (override with `T14S_REF` or `T14S_BASE_URL`) so all fetched modules match one commit.
* Run checks locally: `bash tests/smoke.test.sh && bash tests/host-check.test.sh` (or `make test-stage-a` from repo root).

## License

MIT — see [LICENSE](LICENSE).
