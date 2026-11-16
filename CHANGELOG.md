# Changelog

## [Unreleased]
- fix(podman): add `fuse-overlayfs` to `pacman.txt`. linux-hardened builds without `CONFIG_OVERLAY_FS_UNPRIVILEGED`, so rootless Podman (foxcage, `lab-*`, `agent-run.sh`) failed with "kernel does not support overlay fs: 'overlay' is not supported over btrfs". The btrfs part of that message is misleading; overlay mounts in a user namespace are denied on any filesystem. `stow/containers` ships `storage.conf` with `mount_program = fuse-overlayfs` (image layers auto-detect FUSE, but `podman build` context overlays only use it when set). `install-foxcage.sh` warns when `fuse-overlayfs` is missing and `check.sh` fails when Podman storage is unusable or `mount_program` is unset.
- fix(install): `./install.sh` drops `rust` from the `pacman.txt` transaction when `rustup` is installed (Stage A installs `rustup`). The `rust`/`rustup` conflict made `--noconfirm` abort the whole transaction, so none of the listed packages installed (kitty, ghostty, stow, zoxide, …).
- fix(podman): add `fuse-overlayfs` to `pacman.txt`. linux-hardened builds without `CONFIG_OVERLAY_FS_UNPRIVILEGED`, so rootless Podman (foxcage, `lab-*`, `agent-run.sh`) failed with "kernel does not support overlay fs: 'overlay' is not supported over btrfs". The btrfs part of that message is misleading; overlay mounts in a user namespace are denied on any filesystem. `stow/containers` ships `storage.conf` with `mount_program = fuse-overlayfs` (image layers auto-detect FUSE, but `podman build` context overlays only use it when set). `install-foxcage.sh` warns when `fuse-overlayfs` is missing and `check.sh` fails when Podman storage is unusable or `mount_program` is unset.
- privacy: home location is no longer published. `stow/system/etc/geolocation` is a Greenwich placeholder; the real location goes in gitignored `stow/system/etc/geolocation.local`, preferred by `location-setup.sh` and `vpn-location-sync`. GeoClue drop-in renamed to `99-static-location.conf` (old `99-static-*.conf` removed on setup).
- fix: `git-setup.sh` has no built-in name/email (identity from `GIT_USER_NAME`/`GIT_USER_EMAIL`, existing config, or prompts), no longer deletes `stow/git/.config/git/*` through a folded `~/.config/git` stow dir, and writes machine-local settings (identity, signing, credential helper, `templateDir`) to `~/.gitconfig` instead of the tracked config.
- fix(gpu): `has_nvidia_gpu` reads PCI sysfs (vendor `0x10de`, class `0x03*`); the old `lspci` regex matched any VGA device. `./install.sh` installs `nvidia-open-dkms`/`nvidia-prime`/`nvidia-utils`/`egl-wayland` only when an NVIDIA display device exists (T14s, VMs, other laptops skip it).
- fix(vm-stageb): `PASS_CONFIGURE` (passed any `install.sh` failure) replaced by `PASS_HEADLESS` — pass only when every failure is a headless-expected health check (GNOME extensions, Zen `user.js`, zinit, Proton API).
- Verified: fresh Stage A + Stage B VM run (`PASS_HEADLESS`, git config deployed, no NVIDIA build); live `virbr-malware` guest gets a `192.168.200.x` lease with DNS `192.168.200.1` and no real DNS / internet.
- Stage A handoff harden: vmtest serves local trees; resolve `main`→SHA once (or `T14S_REF` override); clear curl errors; usbguard `list-devices` + `allow-device -p`; virbr-malware `dns enable=no` + `dhcp-option=6,192.168.200.1` + DHCP `67/udp` on lab-malware.
- Stage A: collapse four installers — `arch-install{,-t14s,-p15}.sh` are thin handoffs via `lib/stage-a-handoff.sh` to canonical [t14s-arch-install](https://github.com/HelllGuest/t14s-arch-install) (`HW_PROFILE=t14s|p15`). Docs + tests retargeted.
- Docs: ops/privacy howto in README + Phase 13/20/26/27 + Verify in hardened guide + fresh-install; install order lists `ops-hygiene.sh`.
- Privacy/ops: `pacman-contrib`/`mat2`/`perl-image-exiftool`/`bleachbit`/`usbguard`/`dnscrypt-proxy` in `pacman.txt`; `ops-hygiene.sh` (paccache + flatpak unused + weekly timer; hooked from `install.sh`/`post-update.sh`); opt-in `usbguard-setup.sh` + `dnscrypt-setup.sh` (NM via `network-dns-setup.sh` IPv6 env).
- AUR: add `bootvine-git` (systemd boot vine animation; [AUR](https://aur.archlinux.org/packages/bootvine-git)).
- Stage A/B always install `github-cli` (`gh`) and `glab` (base + `packages/pacman.txt`).
- Rename `firewalld-migrate.sh` → `firewalld-lab-zones.sh`; configure tag `SETUP_FIREWALLD`. No migrate wrapper. Stage A/B always install `htop`/`btop`/`fastfetch`/`firewalld`. Stage B VM harness + `CONFIGURE_UI` + noninteractive git/tsc. Docs howtos updated.
- fix(install): `./install.sh` completes the AI stack — `AI_STACK_EXTRAS_ONLY=1` Continue/OpenCode↔ollama/`hr-proxy`, plus P15 `ollama-setup.sh` (`SKIP_OLLAMA=1` opts out).
- fix(install): Stage B GDM udev keeps NVIDIA `0x10de` (P15 Optimus Wayland); T14s pacman filter drops `egl-wayland`; `stow`/`apply-profile`/`check.sh` ✗ fail `install.sh` via `fail_step` / non-zero exit.
- Stage A: add `scripts/arch-install-p15.sh` (curl-able P15 Gen 1 / 20SU Optimus mirror of `arch-install-t14s.sh`) — `intel-ucode`, `intel_iommu` + `nvidia_drm.modeset` + nouveau blacklist, `nvidia-open-dkms`/`vulkan-intel`/`iHD`, charge thresholds, firewalld drop, optional `INSTALL_OLLAMA`, nvidia suspend/PM udev (profile parity); `tests/thinkpad-p15.test.sh`; README/CONTRIBUTING/fresh-install/hardened Phase 14 document the P15 path (prefer public `t14s-arch-install` `HW_PROFILE=p15` for TUI).
- Privacy: expand `90-telemetry-optout.conf` (OTEL_SDK_DISABLED, HINT/ET/Deno/Terraform, …); `privacy-hardener.sh` always syncs environment.d from stow kit + npm fund/update-notifier off.
- fix(firewalld): `ensure_lab_malware_zone` unbinds `virbr-malware` from `libvirt`+`block`, fails on critical bind/reload/ports, tolerates ALREADY_ENABLED, postchecks libvirt/block clear, warns if firewalld inactive; migrate fail-fast on virbr0/libvirt bind. Docs: Kali NAT uses firewalld/`libvirt` (not UFW) incl. `gnome/keybindings.md`; configure notes optional `dialog`.
- Docs: Stage B `configure.sh` howto (module table, P15 ollama default, fail-fast) in README + fresh-install + t14s-arch-install; live health checklist + `lab-malware` rebind note.
- fix(configure): P15 `SETUP_OLLAMA` defaults on; modules fail-fast (no swallowed `run_mod` errors); migrate label mentions `lab-malware`.
- Cleanup (Slices 1/2/2B): drop `ufw-tailscale.sh` + empty `stow/gnome-session` / `stow/system/etc/{kernel,modprobe.d}`; stop auto-running host `install-rea.sh` from `install.sh` (prefer `lab-re`); shared `lib/lab-malware-zone.sh` so `firewalld-lab-zones` + `lab-detonate` both bind `virbr-malware` → `lab-malware` (not legacy `block`); REA pin `6.9.0` on optional host scripts; `arch-install.sh` ollama gate uses `lib/dmi.sh`; zsh fully stow-managed; docs sync Stage A dual-host / Stage B configure / labs / AI / rice.
- Slice 2b: `lab-detonate.sh` — disposable Linux/Windows VMs on `virbr-malware`, INetSim capture image + optional PolarProxy, `lab-malware` firewalld zone for gateway ports only. `lab-mcp.sh` + lab-web Playwright/Chrome DevTools MCP and lab-android Flutter/adb MCP (host example: `labs/mcp-host.example.json`).
- lab-re: ship `jdk21-openjdk`, `ghidra`, `jadx`, `rizin`, and `rea-agents@6.9+` inside the Podman image; Stage B AI stack no longer runs host `install-rea.sh` (bare metal stays JDK-free).

- Slice 2 labs / AI / rice: `lab-triage`/`lab-re`/`lab-android`/`lab-web` wrappers in `.shell-functions` (Kitty Gruvbox accents, Podman/`bwrap`, samples at `/srv/lab`); Containerfiles under `labs/`; `scripts/labs-setup.sh`, `ai-stack-setup.sh` (Headroom/`hr-opencode`/`hr-agy`, Continue FIM→ollama, OpenCode local models on P15), `rice-setup.sh` (Ghostty/Alacritty Gruvbox, kgx night, btop/fastfetch, GtkSourceView, `.desktop` launchers). Stage B `configure.sh` wires `SETUP_LABS`/`SETUP_AI`/`SETUP_RICE`. Packages: `bubblewrap`, `libnotify`, `btop`.
- Slice 1 dual-host / firewalld / terminals: Stage A (`t14s-arch-install` + `arch-install*.sh`) detects T14s (21CQ/21CR) or P15 (20SU), seeds firewalld (`nftables`, default `drop`) instead of UFW, optional P15 `ollama-cuda` on `127.0.0.1:11434`. Stage B adds `scripts/configure.sh` + `firewalld-lab-zones.sh` (virbr0→`libvirt`, host-only `virbr-malware`→`lab-malware`) + `ollama-setup.sh`. Pruned `ptyxis`/`rio`/`wezterm`/`foot`; keep kitty/ghostty/alacritty/gnome-console.
- Removed: ThinkPad X1 Yoga support (profile, tablet rotate / `iio-sensor-proxy`, X1-only `stow/system` cmdline + `i915.conf` + fingerprint-disable udev rule). Kept profiles are P15 + T14s Gen 3 AMD (+ `laptop` fallback). `fingerprint-setup.sh` / `thinkpad-health.sh` / docs are machine-neutral for those hosts.
- makepkg: renamed `stow/system/etc/makepkg.conf.d/99-x86-64-v3.conf` → `zz-x86-64-v3.conf`. makepkg sources `conf.d` in glob order, and pacman's `rust.conf` sets `RUSTFLAGS` outright, so the `99-` file lost `-C target-cpu=x86-64-v3` (found by `t14s-arch-install` `tests/host-check.sh` on the T14s). `system-setup.sh` removes the old file when it is ours (stow symlink or x86-64-v3 tuning); references in the user overlay, `rebuild-v3.sh`, `arch-install-t14s.sh`, README, and CONTRIBUTING updated.
- foxcage: added `scripts/install-foxcage.sh` (`grepular/foxcage` pinned to commit `349056e5afd0`; the foxcage script and icon are SHA-256 verified, while the Firefox build foxcage downloads from Mozilla at first launch is not pinned) installing to `~/.local/share/foxcage` with a `~/.local/bin/foxcage` link and running `foxcage --install` for the desktop entry; does not change the default browser. `install.sh` step 3.6a runs it when `podman` is present (`SKIP_FOXCAGE=1` opts out); `check.sh` reports it; `packages/pacman.txt` adds `xdg-dbus-proxy`.
- AI stack (Headroom / Caveman v4.1.0 / Ponytail v5.3.3 / all-agent skills+rules+MCP): added `scripts/install-ponytail.sh` (`DietrichGebert/ponytail` `v5.3.3` for Claude Code, Cursor hooks, OpenCode plugin+commands, Gemini CLI extension, Antigravity plugin, Kiro steering, and hub skills); updated `scripts/install-caveman.sh` and `scripts/install-coding-agents.sh` to `v4.1.0` (`2e39b2a9b4ce47620757abc8a55ad33a23dd65217f8a998135108f92f83c00a1`) with `~/.claude/tmp` `EXDEV` workaround and native Antigravity plugin staging; expanded `scripts/sync-agent-skills.sh` to mirror all hub skills and global `AGENTS.md`/`CLAUDE.md`/`GEMINI.md` rules across Claude, Cursor, OpenCode, Kimi, Gemini CLI (`~/.gemini/skills`), Antigravity (`~/.gemini/config/skills`), and Kiro (`~/.kiro/skills`); updated `scripts/headroom-setup.sh` and `scripts/install-obscura.sh` to wire `headroom` and `obscura` MCP across all detected agents and route Claude settings via `ANTHROPIC_BASE_URL`.
- T14s / Ghostty / Shell / AI: `./install.sh` skips Intel/NVIDIA GPU and X1 tablet sensor packages (`intel-media-driver`, `vulkan-intel`, `nvidia-open-dkms`, `nvidia-prime`, `nvidia-utils`, `iio-sensor-proxy`) on ThinkPad T14s Gen 3 AMD (`21CQ`/`21CR`), prepends user tool paths at startup, and re-runs `fnm use 22 && eval "$(fnm env --shell bash)"` after `fnm install 22`; `.shell-exports`, `system-setup.sh` (`99-wayland.conf`), and `gdm-setup.sh` set `LIBVA_DRIVER_NAME=radeonsi` on AMD Radeon (`amdgpu`) hosts; `61-gdm-wayland.rules` adds AMD (`0x1002`); `71-thinkpad-t14s-touchpad-wakeup.rules` disables I2C touchpad (`i2c-ELAN0678:*` / `i2c-SYNA8018:*`) `s2idle` wakeup; `61-thinkpad-charge-limit.rules` sets `ENV{CHARGE_LIMIT}="70,80"` on `BAT*` so UPower 1.90+ / GNOME Preserve Battery Health does not reset `charge_control_start_threshold` to `0`; `gnome-session-setup.sh` and `validate-configs.sh` gate `iio-sensor-proxy` and `yoga-tablet-mode.service` on `is_thinkpad_x1`; `packages/thinkpad-t14s.txt` and `arch-install-t14s.sh` add `libva-utils` and `wireless-regdb`; `stow/ghostty` updates `scrollback-limit` → `scrollback-limit-bytes` for Ghostty 1.4+; `.shell-exports` prepends `~/.opencode/bin`; `install-coding-agents.sh` passes `--allow-scripts=opencode-ai`; `vscode-settings-merge.sh` preserves stow symlinks instead of replacing them with regular files; `install-ghidra-cli.sh` bootstraps `rustup default stable` when unconfigured and falls back to unlocked Cargo build for OpenSSL 4.1+; `sync-agent-skills.sh` and `ai-rules/install.sh` keep `~/.claude/skills` as a real directory so hub skill symlinks do not write back into `~/dev/ai-rules/skills`; `check.sh` verifies active UFW + `tailscale0` via `systemctl`/`/etc/ufw/user.rules` without requiring cached `sudo`.
- Fix: `./install.sh` step 1 installed **nothing** since 2026-10-23 — `packages/pacman.txt` gained `#` comment lines and pacman does not skip them on stdin (`error: target not found: # …` aborts the whole transaction). Comments, trailing comments and blank lines are now stripped first; `tests/thinkpad-t14s.test.sh` runs the real block with stub pacman.
- Power: hosts installed by `t14s-arch-install` with tuned + `tuned-ppd` (provides/conflicts `power-profiles-daemon`) no longer break `./install.sh` — `packages/pacman.txt` skips `power-profiles-daemon` when `tuned-ppd` is present (else `--noconfirm` refuses the removal and aborts the whole transaction); `profiles/thinkpad-t14s.sh` / `laptop.sh` enable `tuned` + `tuned-ppd` instead of PPD there.
- Installer identity / TUI (`arch-install-t14s.sh` + `arch-install.sh`): validate hostname (RFC 1123), username (≤32, not existing user/group), timezone (path + TZif), locale, and keymap **before** any wipe/LUKS; AUTO partitioning deferred until after those prompts; keymap via `localectl` first (`grep -qxF`), then exact on-disk map fallback (directory required only then); reject glob/regex names; banner borders aligned; finish text is DESKTOP-aware (GDM only when GNOME requested) and T14s summary adds charge-service verify lines. Canonical validators in `scripts/lib/install-identity.sh` (curl-able installers embed copies; drift-checked in `tests/thinkpad-t14s.test.sh`).
- Kali disposable: `kali status` no longer exits 1 when the overlay image is missing (`set -e` safe).
- T14s charge: `arch-install-t14s.sh` (not generic `arch-install.sh`) seeds tmpfiles **and** `thinkpad-charge-thresholds.service` (`After=multi-user.target`; apply under `/usr/local/lib/thinkpad/`). Helper installs the same stack when BAT* exists; if charge_control_* is missing, only ThinkPad DMI may seed (non-blocking `start --no-block`) — desktop/VM/non-ThinkPad plain-skips. `install -m 644/755`, shared `scripts/lib/*.tmpl` (must be tracked) + installer parity test; removes legacy apply under `/usr/local/lib/t14s/`.
- Docs: host-audit remediation paths — sleep drift → `system-setup.sh` + reboot; charge tmpfiles + `CHARGE_START`/`END`; Podman-first disable `docker.service`; Chrome user/system Flatpak; troubleshooting rows for pacman.txt gaps / browser-hardening sudo.
- T14s addons: `packages/thinkpad-t14s.txt` + `scripts/lib/thinkpad-charge-thresholds.conf` (installer heredoc sync-tested); `scripts/thinkpad-charge-thresholds.sh`; profile + `arch-install-t14s.sh`; `check.sh` probe. Docs Phase 14 / README structure. Public `t14s-arch-install` shares the charge/AMD stack (apply under `/usr/local/lib/thinkpad/`) but keeps its own TUI/identity helpers (FQDN hostnames, etc.). Skip ryzenadj/TLP/thermald.
- Podman-first agent sandboxes: `podman` stack in `pacman.txt`; `scripts/agent-run.sh`; `stow/containers` (`no_new_privileges`); `.shell-exports` keeps Podman `DOCKER_HOST` with `FORCE_DOCKER=1` escape; Phase 17 / README / fresh-install docs aligned (Docker no longer primary).
- T14s Gen 3 AMD: `scripts/arch-install-t14s.sh` (curl-able; `amd_iommu`/`amd_pstate`, `amd-ucode`, hostname `thinkpad-t14s`); `profiles/thinkpad-t14s.sh` repairs Intel cmdline leftovers + rebuilds UKIs; `is_thinkpad_t14s` matches type **21CQ/21CR** only; `INSTALLER=` for `arch-install-vmtest.sh`; `tests/thinkpad-t14s.test.sh`.
- Obscura: `scripts/install-obscura.sh` installs stealth+render binary to `~/.local/bin`, wires MCP for OpenCode/Cursor/Claude, host skill `skills/obscura-host`; hooked in `install.sh` + `check.sh` + sync host-skill refresh.
- Dedup scripts: `scripts/lib/agent-skills.sh` shared by ecosystem + RE skill installers; `ai-rules/lib/vscode-settings-merge.sh` single VS Code telemetry merge (telemetry.sh + ai-rules/install.sh). Telemetry falls back to inferred repo root if `REPO_ROOT` is wrong; ai-rules creates `User/` only when the IDE config root already exists.
- Agent skills (usage-aligned): ecosystem installer supports `owner/repo:skill` filters; packs for Meson/QEMU, Arch triage, hardening/git, web quality, agent-browser, superpowers workflows, OpenAI pdf/playwright; RE adds malware/mobile/Windows/forensics + memory-forensics. `check.sh` probes new skills. `ai-rules/install.sh` no longer merges `cursor.general.*` into Code/VSCodium (strips leftovers; was polluting stow + live settings via `sync-agent-skills`).
- Kali disposable physical LAN: macvtap eth1; host RJ45 flushed (`kali-lan-host-prep` + polkit); guest eth1 DHCP without gateway/DNS; `lan-check`; dual-gateway/wifi clash fixed; aliases `kali-up-lan` / `kali-lan` / `kali-lan-check`.
- Tailscale: `packages/pacman.txt` + `scripts/firewalld-tailscale.sh` (allow `tailscale0` / `41641/udp` / route); wired in `install.sh` + `check.sh`; hardened-guide section. Docs: Brovi H155-381 CPE admin-only RE path (no public firmware).
- Docs: Kali default **isolated** (was wrongly NAT); NAT/UFW/`virbr0-up` + cloud-init SSH notes; P15 post-reboot NVIDIA checks; libvirt firewall section in hardened guide; CONTRIBUTING packages/`virbr0-up`/cmdline flags.
- Host log fixes: `evolution-data-server` + `wireless-regdb` in `pacman.txt` (CalendarServer libs, Wi-Fi `regulatory.db`); `virbr0-up.service` in `stow/system` waits for libvirt default net (fixes boot race `Cannot find device virbr0`); kali setup installs/enables the unit.
- P15 Optimus: harden nouveau kill (`install nouveau /bin/false`, `rd.driver.blacklist=nouveau` on cmdline) so proprietary NVIDIA binds after reboot; rebuild UKI embeds `/etc/kernel/cmdline`. Kali UFW also allows `192.168.122.0/24` forward.
- Double-check fixes: RE skills manifest supports `owner/repo:skill` (firmware-pentest); check.sh probes security-reports+pentest; Kali default net isolated + cloud-init seed for DHCP; UFW `virbr0` forward + WAN route + admin-up so guest NAT/SSH works; print lease by hostname/`domifaddr` (not stale IPs); cloud-init forces password SSH + unique instance-id; clamav-freshclam + BAT-only charge tmpfiles in install-re-extras; gnome-session stow `--adopt`/soft-fail; drop Cursor keys from Code/VSCodium; `tests/kali-disposable.test.sh`.
- Host RE extras on P15 path: triage pkgs (clamav/upx/wireshark/mitmproxy/nmap), AUR imhex+apktool, frida-tools+jefferson+unblob (pipx), firmwalker mirror + GhidraMCP tree under `~/tools`, `firmware-pentest` skill, `kali-up` defaults to isolated (`kali-up-nat` for WAN), battery charge 70–80 via tmpfiles, SSH key auth, browser-hardening honors `SUDO_ASKPASS`.
- RE AI stack: `scripts/install-re-skills.sh` + `packages/agent-skills-re.txt` (leanrea, EncidXVII reverse-engineering, Android RE, ghidra-iterative-re, OrbitCurve firmware-RE); `scripts/install-re-extras.sh` + `packages/re-extra.txt` (jadx/rizin/… + squashfs/mtd/flashrom/uboot/qemu-user-static); wired after REA in `install.sh`; `check.sh` probes RE + firmware skills. Docs in fresh-install RE guide.
- Disposable Kali lab: `scripts/kali-disposable.sh` (libvirt + immutable qcow2 base + ephemeral overlay; `wipe` resets). Shell aliases `kali` / `kali-up` / `kali-wipe` / `kali-stop` / `kali-st`. Docs: README Shortcuts, `gnome/keybindings.md#disposable-kali`, `docs/fresh-install-coding-re.md#disposable-kali`.
- Sleep: `s2idle.conf` + `thinkpad-lid.conf` install on all hosts (was X1-only `thinkpad-x1.conf`); MemorySleepMode=s2idle. On AC: no idle sleep (`sleep-inactive-ac-type=nothing`) and no lid sleep (`HandleLidSwitchExternalPower=ignore`); battery still idle/lid suspends. Drop obsolete GNOME `lid-close-*` keys (gone in current gnome-settings-daemon).
- zram: raise generator cap to `min(ram / 2, 32768)` (was 8192) for high-RAM hosts like P15.
- Docs: UFW SSH on Arch uses `ufw allow 22/tcp` (no `OpenSSH` app profile); hardened Phase 13 + README troubleshooting.
- Base cleanup: untrack root convenience symlinks (`.zshrc`, `.zsh-plugins`, `.config/*` → stow only; gitignore); drop empty `chrome-extra.json` (Chrome = `chromium-base` only); Cursor-only keys via `*/Cursor/*` + `*/.cursor/*` (merge strips leftovers on non-Cursor; `check.sh` flags foreign keys); wipe local `builds/st` makepkg outputs; drop unused `install-starship-crampack.sh` (README keeps upstream Crampack one-liner); `.gitignore` covers Claude Code runtime under `.claude/`.
- Docs: README owns browser policy detail; hardened Phase 27 points at README Flatpaks; CONTRIBUTING privacy row + `scripts/lib/telemetry.sh`; Privacy bullets de-duplicated; Unreleased no longer retells Cursor/chrome-extra (see Base cleanup).
- CI: `list-stow-files.sh` uses `LC_ALL=C sort` so `all_stow_files.txt` matches GitHub runners (fixes false “Stow inventory freshness” failures from locale sort).
- Privacy/telemetry unified: single `stow/privacy/.config/environment.d/90-telemetry-optout.conf` (CLI+GUI), `.shell-exports` sources it; `scripts/privacy-hardener.sh` + `scripts/lib/telemetry.sh` cover GNOME, browsers, VS Code-family/Claude merges, Flutter reporting=0, Headroom/AI. Expanded opt-outs (Go, Turbo, Wrangler, gcloud, gh, Expo, Yarn, …). `check.sh` probes the layer. Removed unrelated `GOOGLE_API_USE_CLIENT_CERTIFICATE` from the old export list. Follow-up: Kimi MCP merge (no clobber), `ln -sfnT` brand links, REA pin parity `6.7.0`, privacy-hardener before `check.sh`, Remote Control warning in env file. AI-tool pass: Gemini `privacy.usageStatisticsEnabled=false`, Cursor `privacyMode=enabled`, OpenCode `share=disabled`/`autoupdate=false`/`openTelemetry=false`, `KIMI_DISABLE_TELEMETRY`, Claude `skipWebFetchPreflight` + marketplace autoinstall off, drop Kimi `custom-keep` test MCP. Browser pass: stronger Chromium base (CloudReporting/DomainReliability/PasswordLeakDetection/…), Zen Flatpak `systemconfig` + profile `user.js`, LibreWolf overrides, Brave Flatpak policy path; user-writable deploys before `/etc` sudo, `sudo -n` off-TTY, drop removed `ChromeCleanupReportingEnabled` + non-telemetry `OfferToSaveLogins`, DoH off, `zen_systemconfig_dir` arch, stale CloudReporting is `✗`. Shell pass: bash `umask 077` + secret `HISTIGNORE` + `chmod 600` history; atuin `secrets_filter` + secret `history_filter`; `ensure_atuin` realpath-skips stow kit; tighter `--password` / `KEY=` filters. (Cursor path gating / chrome-extra removal: Base cleanup.)
- Fresh Arch AI stack reproducible end-to-end: `scripts/install-coding-agents.sh` (pinned `opencode-ai@1.19.4` + `@moonshot-ai/kimi-code@2.3.0`, OpenCode/Kimi MCP for headroom+rea, Caveman OpenCode plugin), `scripts/install-ecosystem-skills.sh` + `packages/agent-skills.txt` (cloudflare/emil/vercel/… packs to Cursor/Claude/OpenCode/`kimi-code-cli`), `sync-agent-skills.sh` mirrors hub → OpenCode + Kimi. Wired into `install.sh` (3.5b–3.5i); skill sync before AI installers (kit fallback) and again after (hub mirror); installers use `SKIP_SKILL_SYNC=1`. `check.sh` / README / fresh-install / P15 preflight / tests updated. README/CONTRIBUTING profile order = pacman then profile.
- Ghostty: stow systemd user drop-in `Type=notify` for `app-com.mitchellh.ghostty.service` so GNOME D-Bus launch works on recent systemd (stock `notify-reload` races with late SIGUSR2 → click does nothing until retry).
- AI tools reproducible on any host (incl. P15): `scripts/sync-agent-skills.sh` (ai-rules kit + `~/.agents` hub → Claude/Cursor/OpenCode/Kimi), `scripts/install-caveman.sh` (JuliusBrussee/caveman `v4.0.1` + SHA-256 of installer), `scripts/install-android-ui-skills.sh` (pinned `android-compose-design` commit + `material-3` `v1.1.1`), `scripts/install-rea.sh` (rea-agents, jadx JAR, MCP for detected agents, VSCodium). `check.sh` reports optional hub skills. Hopper still opt-in: `INSTALL_HOPPER=1`.
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
- Starship: switched to the official [Gruvbox Rainbow](https://starship.rs/presets/gruvbox-rainbow) preset (`gruvbox_dark`, `command_timeout = 3000`; Crampack helper script removed, upstream one-liner kept in README).
- Waydroid: NAT masquerade is `waydroid-nat.service`, not a `*nat` block in `ufw/before.rules`.
- Neovim: Catppuccin/`palette.lua` overlay is gone; Lazy fallback colorscheme is `habamax`.
- Zsh: pacman `zsh-autocomplete` was replaced by zinit + fzf-tab (v1.11) and stays removed.
- Kitty: right-click copies the selection to the clipboard (`mouse_map right press ungrabbed copy_to_clipboard`); Shift+right-click still extends the selection.
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
- Theme auto-switch (NTS v82): Night Theme Switcher v82 dropped built-in gtk/cursor variants; obsolete `gtk-variants` dconf keys were ignored. Added `scripts/night-theme-hook.sh` hooked via NTS sunrise/sunset commands for Catppuccin latte/mocha GTK; NTS `color-scheme` set to prefer-light/prefer-dark; removed hardcoded gtk/color-scheme/cursor from `user.conf`; stopped `theme-switch.sh` forcing prefer-dark when NTS active; fallback location in `extensions.conf`.

## [1.17.0] - 2026-06-02
- Suspend: switched X1 to S3 `deep` via `sleep.conf.d` (`SuspendState=mem` + `MemorySleepMode=deep`); lower standby drain than s2idle. *(Superseded: current cmdline + `sleep.conf.d` pin s2idle; see Unreleased.)*
- Power: hard-disabled unused Synaptics fingerprint reader (06cb:00bd) at its USB port via `72-fingerprint-disable.rules` — kills resume `xHC error`/`usb 1-9` reset spam and idle drain.
- Ghostty: fixed config errors for 1.3.x — dropped removed `gtk-prefer-dark-theme`, `quick-terminal-size = 40%` (unit required), `keybind` key `backquote` (was `grave`); quick terminal now `global:` toggle.

## [1.16.0] - 2026-05-31
- GNOME session: workspaces, touchpad, keyboard repeat, night light, power/lid rules.
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
