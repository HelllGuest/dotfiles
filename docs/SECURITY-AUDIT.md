# Security audit: dotfiles repository

Date: 2026-11-16. Scope: this repository as of `5092258` plus the uncommitted
bootvine / package-list / ghidra-cli changes in the same working tree. The
public installer [`t14s-arch-install`](https://github.com/HelllGuest/t14s-arch-install)
was checked for secrets only.

Classification used below:

* **Confirmed vulnerability**: exploitable as described; reproduced or proven.
* **Configuration weakness**: an insecure default or gap with a realistic impact.
* **Potential**: plausible, not demonstrated.
* **Info**: observation or recommendation.

## Method and tools

| Tool | Use |
| --- | --- |
| ShellCheck 0.11 (`-S warning`) | All 125 shell files (scripts, libs, hooks, stowed shell config, dispatcher) |
| `git grep -P` pattern scans | `eval`, remote code piped to shells, `sudo -E`, world-writable `chmod`, dynamic `source`, unguarded `rm -rf`, downloads, container flags |
| Local regex secret scanner (Python, no network) | Working tree and all 138 commits of history; installer repo (48 commits). Reports file and rule only, never values |
| Podman (rootless) | Behavioural tests of lab hardening against the real lab images |
| Repo test suite | 14 test files that day (4 added, several extended), all passing; later grew to 22 `tests/*.test.sh` |
| Mutation testing | Each fix reverted in a scratch copy; the regression test must fail (all caught; see the final run in the report below) |

Not available and not installed (no authorization to install or upload):
Semgrep, Bandit, Gitleaks, TruffleHog, Trivy, Checkov, Lynis, hadolint. The
regex scanner and pattern scans stand in for Gitleaks/Semgrep; there was no
image vulnerability scan (Trivy) and no host audit (Lynis).

Areas inspected: `scripts/` and `scripts/lib/` (88), `stow/` (83, including
`stow/system` root-installed files, git hook templates, shell rc files),
`profiles/`, `packages/`, `ai-rules/` (agent settings, global git hooks),
`labs/` (5 Containerfiles, entrypoints, MCP wrappers), `builds/st`,
`browsers/` (Chromium/Brave/Chrome policies, LibreWolf, Zen), `gnome/` dconf,
`tests/`, `.github/`, polkit rules, udev rules, systemd units, the
NetworkManager dispatcher, sysctl/logind/sleep drop-ins and the GeoClue config.

## Findings

### Confirmed vulnerabilities (fixed)

| # | Sev | File | Issue |
| --- | --- | --- | --- |
| V1 | HIGH | `scripts/vpn-location-sync.sh` | Root (NM dispatcher, or **pkexec without a password** via `50-vpn-location-sync.rules`) ran `install -m 0644 <user's geolocation(.local)> /etc/geolocation`. The source is user-writable and `install` follows symlinks, so any process of the user could plant a symlink to e.g. `/etc/shadow` and have root publish it world-readable. Proven: `install` copies a symlinked 0600 file to a 0644 file. |
| V2 | HIGH | `stow/zsh/.shell-functions` (`_lab_work_dir`), `scripts/lab-mcp.sh` (`work_dir`, a second copy found in the double-check) | Labs mount the current directory read-write as `/work`. Only `$HOME` and `/` were refused, by exact match: starting a lab in `/home` mounted the whole home tree, and `~/.config`, `~/.ssh` or `~/dotfiles` were handed to malware labs read-write. |
| V3 | MEDIUM | `scripts/kali-lan-host-prep.sh` | Runs as root without a password (pkexec + `50-kali-lan-host-prep.rules`) and accepted any interface name: any user process could make root unmanage, flush and drop routes on Wi-Fi or the VPN tunnel (`proton0`), a silent network DoS or VPN bypass. |
| V4 | MEDIUM | `stow/zsh/.shell-functions` (`lab-re`) | `--security-opt seccomp=unconfined` removed the syscall filter for analysed binaries. Proven unnecessary: gdb runs and attaches under the default filter (only ASLR-disable warns). |
| V5 | MEDIUM | `scripts/lab-detonate.sh`, `labs/lab-capture/` | INetSim, which parses malware traffic, ran in a **rootful, host-network** container with the default capability set. |
| V6 | MEDIUM | `ai-rules/git-hooks/{pre-push,pre-commit}`, `stow/git/.config/git/templates/hooks/pre-push` | Installed as the global `core.hooksPath`, they ran repo-defined code in **every** repository: `npm/pnpm run lint`, `cargo check` (build scripts, proc-macros) on push; and `scripts/list-stow-files.sh` on commit in any repo containing `stow/` + `all_stow_files.txt`. Cloning and pushing/committing in a hostile repo meant code execution. |
| V7 | MEDIUM | `scripts/install-headroom.sh` | headroom proxies every Anthropic/OpenAI request (`ANTHROPIC_BASE_URL`), so it sees API keys, yet it was installed unpinned and **auto-upgraded** (`headroom update -y`) to whatever PyPI served. |
| V8 | MEDIUM | `labs/lab-web/Containerfile` | `curl https://mise.run \| sh` (unverified remote script) at build time; failed pinned npm installs fell back to unpinned latest. |
| V9 | MEDIUM | `scripts/lab-detonate.sh` | PolarProxy "latest" zip downloaded without verification and **executed on the host**. |
| V10 | LOW | `scripts/lab-detonate.sh` | Alpine detonation base image downloaded without checksum. |
| V11 | LOW | `scripts/arch-install-vmtest.sh` | Arch ISO downloaded without checksum before booting it. |

### Configuration weaknesses (fixed)

| # | Sev | File | Issue |
| --- | --- | --- | --- |
| C1 | MEDIUM | `scripts/dnscrypt-setup.sh` | DNS was pinned to dnscrypt per existing connection only; any network joined later used its DHCP DNS in plaintext. |
| C2 | LOW-MED | `browsers/policies/chromium-base.json`, `browsers/zen/user.js` | No WebRTC IP-leak protection (Chromium family and Zen); LibreWolf already has it by default. |
| C3 | LOW | `scripts/vpn-location-sync.sh` | When the tunnel had no carrier, the exit-IP lookup fell back to the real egress (sends the ISP address to ipapi.co). Network data was written to `/etc` unvalidated; the curl binary path came from an environment variable in a root script. |
| C4 | LOW | `gnome/dconf/user.conf` | Notification content shown on the lock screen; removable-media autorun prompts enabled. |
| C5 | LOW | `stow/bash/.bashrc` | `~/.config/secrets/env` sourced without enforcing 0600 (zsh already did). |

### Unresolved (needs a decision)

| # | Sev | Issue |
| --- | --- | --- |
| U1 | MEDIUM (HIGH if the repo is ever made public) | Commit `56634c1` (2026-06-07) contains real home coordinates in `stow/system/etc/geolocation` (about 11 m precision). The current tree holds only a placeholder, but history keeps it. The repo is **private** with no forks, so exposure is limited to the account and collaborators. Fix requires rewriting history (`git filter-repo --path stow/system/etc/geolocation --invert-paths` or a blob replacement) and force-pushing, which is destructive and was not done without explicit approval. Do this before ever publishing the repo. |

### Potential issues / info (documented, not changed)

* **Supply chain, unpinned (LOW):** 15 agent-skill packs in `packages/agent-skills.txt` track their default branches (skills are instructions agents follow, some with scripts); Flutter `stable` branch clone (interactive `lab-android` only; follow-up 2026-11-20: lab MCP wrappers execute baked binaries directly with `npx --offline --no` fallback, and `lab-web` uses signed Arch `chromium`); `unblob` (pipx) and `markdownlint-cli2` (npx) unpinned. Recommendation: pin to reviewed commits/versions.
* **Stage A trust (INFO):** `stage-a-handoff.sh` fetches the installer over HTTPS pinned to one resolved commit, without a signature. Trust root is the GitHub account plus TLS. Pin `T14S_REF` to a reviewed SHA for reinstalls. The documented `bash <(curl …/dotfiles/main/scripts/arch-install.sh)` one-liner cannot work while this repo is private.
* **Lab surface (INFO):** `lab-android` passes `/dev/kvm` and the Wayland socket; `lab-web` and `lab-android` have network (`pasta`). Malware labs (`lab-triage`, `lab-re`) use `--network none`. PolarProxy, if installed, listens on all interfaces and relies on the `lab-malware` firewalld zone.
* **Capture logs (INFO):** after V5 the host log directory becomes `root:101` 0775 (gid 101 is unused on this host): readable by the user, deleting needs sudo.
* **opencode (INFO):** `permission.skill: {"*": "allow"}` auto-loads skills (not shell commands). **Claude settings:** no tool permissions granted; `skipWebFetchPreflight: true` trades Anthropic's domain pre-check for privacy.
* **Foot-guns (INFO):** `PONYTAIL_DIR` (env) is passed to `rm -rf`; two interactive `cd` helpers lack `|| return` (no destructive follow-up).
* **Host state at audit time (INFO, not repo issues):** dnscrypt-proxy and usbguard (and 32 other `pacman.txt` packages) were not installed, so the laptop used plaintext DNS to 1.1.1.1. Running `./install.sh` and `scripts/dnscrypt-setup.sh` applies the repo's intent.
* **Address in docs (INFO):** the LTE router's vendor-default address appears in `docs/fresh-install-coding-re.md` and (2026-11-20 follow-up) as the default `KALI_LAN_PROBE` target in `scripts/kali-disposable.sh`.

### Reviewed with no finding

polkit rules (scoped to two fixed paths; arguments now validated), udev rules,
`virbr0-up` / `waydroid-nat` units (no user-writable paths), `system-setup.sh`
(root-owned regular files, never symlinks into `$HOME`), sysctl / logind /
sleep drop-ins, GeoClue static-only config, NM dispatcher (root, clean env,
calls a root-owned path), `lab-malware` firewalld zone (DROP, no masquerade or
forwards) and `virbr-malware` (no `<forward>`; redefined if one appears),
USBGuard setup (refuses empty policy; rules 0600), `tmp-to-disk.sh` (`nosuid,nodev`),
`install-caveman.sh` / `install-foxcage.sh` / `kali-disposable.sh` / `builds/st`
(SHA-pinned), opencode / kimi / rea-agents (version-pinned), git config
(libsecret helper, `fsckObjects`), browser telemetry prefs, no `eval` of
untrusted data, no `sudo -E`, no world-writable `chmod`.

### False positives

* Double-check: the first INetSim hardening broke mail capture and V2 missed `lab-mcp.sh`; both are corrected above.
* Secret scan `assign_secret` hits in 10 test files: each is the test's own `echo "PASS: <name>.test.sh"` line.
* Private IPs: QEMU `10.0.2.2`, libvirt `192.168.122.0/24`, lab subnets `192.168.200.0/24` and `192.168.240.0/24`, a CPE DNS sinkhole address in a comment.
* Installer `url_creds` hit: a URL-validation regex, not a credential.
* ShellCheck: 19 × SC2139 (intentional define-time alias expansion), 6 × SC1090 (dynamic `source` of the user's own rc files), 4 × SC2034 / 2 × SC2155 (style), 2 × SC2164 (see foot-guns).

## Remediation and verification

| # | Fix | Verification |
| --- | --- | --- |
| V1, C3 | Root uses only the root-owned `/usr/local/share/vpn-location-sync/home.geolocation` (no symlink, uid 0); repo lookup only for unprivileged runs. Lat/lon must be decimal degrees in range; label stripped of control chars. No unbound lookup. `CURL=/usr/bin/curl` fixed. | `tests/vpn-location-sync.test.sh`: runs a retargeted copy as uid 0 in a user namespace: planted symlink ignored, symlinked installed copy refused, newline/garbage/out-of-range coords rejected, no lookup when NM says connected but the tunnel has no carrier. |
| V2 | One implementation in `scripts/lib/lab-workdir.sh`, used by the `lab-*` wrappers, `lab-mcp.sh`, and (2026-11-20 follow-up) `agent-run.sh`: refuses `/`, `/etc/*`, `/usr/*`, `/var/*`, `/boot/*`, `/root/*`, `/proc/*`, `/sys/*`, `/dev/*`, `/run/*` (including `/run/user/$UID` session sockets), `/opt/*`, whole `/tmp` and its session socket dirs (`/tmp/.*`, `tmux-*`, `ssh-*`, `systemd-private-*`), any dir holding a socket two levels down, `/srv/lab`, `$HOME` and its ancestors, hidden dirs under `$HOME`, the dotfiles repo, and the samples dir (ancestors + `/srv/lab/samples/*` subdirectories); defaults `LAB_SAMPLES` under `set -u`. Wrappers fail closed: each caller returns when the check refuses, and a stub refuses if the lib is missing. | `tests/slice2-labs.test.sh` runs the real function in bash **and** zsh over 13 directory cases plus sensitive host paths (`/run`, `/run/user/1000`, `/var/lib`, `/opt`, `/tmp`, `/srv/lab`, `/tmp/.X11-unix`, `/tmp/tmux-*`, `/tmp/ssh-*`) and a project dir holding a real socket, checks `lab-mcp.sh` under `set -u` without `LAB_SAMPLES`, checks `agent-run.sh` sources `lib/lab-workdir.sh`, and verifies a missing lib fails closed. |
| V3 | `valid_lan_iface`: IFNAMSIZ-safe name, physical device, ARPHRD_ETHER, not wireless. | `tests/kali-disposable.test.sh` with a fake sysfs (Wi-Fi, `proton0`, bridge, veth, traversal and long names rejected); read-only run on this host rejected `wlp1s0`, `tailscale0`, `docker0`, `virbr0`, `lo`. |
| V4 | Removed `seccomp=unconfined`; kept `SYS_PTRACE`. | gdb run + attach tested in `lab-re` under the default filter; test forbids `seccomp=unconfined`, `--privileged`, `label=disable`, host namespaces in labs. |
| V5 | `--cap-drop ALL` + `NET_BIND_SERVICE,SETUID,SETGID,CHOWN`, `no-new-privileges`, `--read-only --tmpfs /tmp`; container recreated each start. Captures (SMTP mbox, FTP uploads, HTTP POST bodies) are host volumes under `$CAPTURE_LOG/inetsim-data/`, so they survive the recreate and stay writable on the read-only root; the entrypoint makes every writable dir `root:inetsim` 0775. | Rootless runs of the real image: ports 21/25/53/80/443 bound; the no-caps control failed. The double-check found the first version (read-only, no data volumes) **broke SMTP capture** (`451`, "Read-only file system"); with the volumes, an SMTP message was stored on the host, also with the rebuilt image's real entrypoint. HTTP POST / FTP upload capture was **not confirmed**: the hand-written probe failed identically on a writable root, so it shows no regression but proves nothing either. Follow-up 2026-11-20: `lab-capture` now builds in rootful Podman, `lab-malware` opens `21/tcp` and `25/tcp`, and rootful `capture-up` under `--read-only` was verified live in a QEMU VM (INetSim Up on `192.168.200.1:21/25/80`). Static test in `tests/slice2b-detonate-mcp.test.sh`. |
| V6 | Repo code runs only with `git config --local hooks.trusted true` (never cloned); inventory hook also in `~/dotfiles`. | `tests/git-hooks.test.sh` with throwaway repos: untrusted repo scripts do not run, trusted ones do, bogus value is untrusted, `~/dotfiles` still works. |
| V7 | `HEADROOM_VERSION=0.44.0` exact pin; reinstall only on mismatch; no auto-update. | `tests/ai-install-scripts.test.sh`; installed version already 0.44.0. |
| V8 | `mise` from the Arch repo (`pacman`); pinned npm only (2026-11-20 follow-up: Arch signed `chromium` replaces Playwright's Ubuntu-20.04 CDN zip; MCP wrappers execute baked binaries with `npx --offline --no`). | Test forbids `curl\|sh` and `npx --yes` in Containerfiles/MCP wrappers. Follow-up 2026-11-20: full rootless `lab-web` build, offline `mcp-playwright`/`mcp-devtools` `0.0.39`, headless Chromium render under `--cap-drop ALL --network none`, and live MCP JSON-RPC `initialize` handshake verified in a QEMU VM. |
| V9 | PolarProxy installed only with `POLARPROXY_SHA256`; mismatch aborts. Setup records the installed binary's hash; `capture-up` runs only a binary with a matching record, so downloads from before this fix are not started. | Functional tests: skipped without hash, wrong hash refused; unverified or modified binary not started, verified one started. |
| V10 | Alpine images pinned to the SHA-512s published by Alpine (fetched 2026-11-16); mismatch discarded; an existing image is re-checked against the pins before use. | Functional test: tampered download rejected and removed, matching image installed, pre-existing unpinned image refused. |
| V11 | ISO verified against `sha256sums.txt` before use. | ShellCheck; same logic as the installer repo's `vm-run.sh`. |
| C1 | `install_nm_global_dns`: `/etc/NetworkManager/conf.d/90-dnscrypt-global-dns.conf` with `[global-dns-domain-*] servers=127.0.0.1,::1` (opt out: `SKIP_NM_GLOBAL=1`). Global DNS also overrides Tailscale and Proton VPN DNS: when Tailscale is logged in, its MagicDNS suffix gets its own section (`100.100.100.100`) plus a search domain; a malformed suffix is ignored. Proton NetShield filtering is bypassed (lookups still go to dnscrypt through the tunnel). Fails closed: if dnscrypt-proxy stops, nothing resolves. | Parsed by `NetworkManager --print-config` (all sections accepted); tests cover the tailnet section and a config-injection suffix. Not applied to this host. |
| C2 | `WebRtcIPHandling: default_public_interface_only`; Zen `ice.default_address_only` + `ice.no_host`. | `tests/ai-install-scripts.test.sh`. |
| C4 | `show-in-lock-screen=false`, `autorun-never=true`. | `tests/privacy-ops.test.sh` parses the dconf file. |
| C5 | `chmod 600` before `source`. | `tests/privacy-ops.test.sh` checks ordering. |
| C4 (cont.) | `backup-gsettings.sh` re-asserts the enforced privacy keys after `dconf dump`, so a snapshot cannot silently drop them. | Test with a stub dump (other keys preserved verbatim); real dump round-trip: 255 live keys preserved, GLib parses the result. |
| V1 (CI) | Static checks of the root branch run even where user namespaces are unavailable (GitHub runners skip the namespace tests). | Verified with `unshare` stubbed to fail: namespace tests skip, static checks still run. |
| V6 (cont.) | The pre-push gate stays silent in repos with nothing to check. | `tests/git-hooks.test.sh`. |
| Config | `inetsim.conf` used option names INetSim ignores (`http_port`, `https_port`, `dns_port`, `create_html_index`); renamed to `*_bind_port`, dead option removed. | INetSim run: no unknown-option warnings, ports still bound. |

Final state **as of that audit day**: all 14 test files then present passed;
ShellCheck showed no new warnings on the 27 changed shell files; docs lint 0
issues; stow inventory unchanged. No host configuration was changed during the
audit, no secrets were printed, and no destructive host commands ran.

> **Snapshot drift (post-audit):** 22 `tests/*.test.sh` as of 2026-11-22.
> `gdm-shell-theme.sh` / greeter hook removed with Aura → stock Adwaita
> (`theme-setup.sh`). `virbr-malware` bridge now sets `zone="lab-malware"`.

## Actions for the operator

These applied the audit fixes to a machine (none were run *during* the 2026-11-16
audit). On the T14s blackbox host (2026-11-22): stock Adwaita, Podman primary
(`docker.service` disabled, `podman.socket` user-enabled), `usbguard` +
`dnscrypt-proxy` active, `hr-proxy.service` enabled, Claude CLI present; Secure
Boot still needs BIOS Setup Mode before `sbctl enroll-keys -m`.

1. **Urgent (if not yet):** `bash scripts/location-setup.sh`. Re-run after any
   edit to `geolocation.local`.
2. `bash ai-rules/install.sh`: refresh global hooks in `~/dev/ai-rules` (V6),
   then `git config --local hooks.trusted true` in projects that should keep
   pre-push checks.
3. `./install.sh` as desktop user (rejects root): packages + stow; AUR after
   `system-setup.sh`; `sync-agent-skills` before `headroom-setup`.
4. `bash scripts/dnscrypt-setup.sh` / `bash scripts/usbguard-setup.sh` (opt-in).
5. `bash scripts/browser-hardening.sh`: WebRTC policies (C2); or via
   `privacy-hardener.sh` (continues layers 3–7 if browsers fail).
6. `bash scripts/labs-setup.sh`: rebuild `lab-capture` / `lab-web` (V5, V8).
7. Decide on U1 (history rewrite) before making this repository public.
