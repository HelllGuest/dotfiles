#!/usr/bin/env bash
# Slice 2: labs / AI / rice scaffolding smoke.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
fail() { echo "FAIL: $*" >&2; exit 1; }

for f in \
  "$ROOT/labs/scripts/labs-setup.sh" \
  "$ROOT/ai/scripts/ai-stack-setup.sh" \
  "$ROOT/desktop/scripts/rice-setup.sh" \
  "$ROOT/provision/scripts/configure.sh" \
  "$ROOT/labs/lab-triage/Containerfile" \
  "$ROOT/labs/lab-re/Containerfile" \
  "$ROOT/labs/lab-android/Containerfile" \
  "$ROOT/labs/lab-android/entrypoint.sh" \
  "$ROOT/labs/lab-web/Containerfile" \
  "$ROOT/labs/lab-web/compose.yml" \
  "$ROOT/stow/ghostty/.config/ghostty/theme.conf" \
  "$ROOT/stow/continue/.continue/config.yaml" \
  "$ROOT/stow/gnome-text-editor/.local/share/gtksourceview-5/styles/gruvbox-dark.xml" \
  "$ROOT/stow/btop/.config/btop/themes/gruvbox_dark.theme" \
  "$ROOT/stow/applications/.local/share/applications/kali-disposable.desktop"
do
  [[ -f $f ]] || fail "missing $f"
done

grep -q 'podman build --network=host' "$ROOT/labs/scripts/labs-setup.sh" \
  || fail "labs-setup.sh must build with --network=host (isolated nets starve pacman)"
for f in "$ROOT/labs/scripts/labs-setup.sh" "$ROOT/ai/scripts/ai-stack-setup.sh" \
  "$ROOT/desktop/scripts/rice-setup.sh" "$ROOT/provision/scripts/configure.sh" \
  "$ROOT/labs/lab-android/entrypoint.sh"; do
  bash -n "$f" || fail "bash -n $f"
  [[ -x $f ]] || fail "not executable: $f"
done

bash -n "$ROOT/stow/zsh/.shell-functions" || fail "bash -n .shell-functions"

grep -q 'lab-triage()' "$ROOT/stow/zsh/.shell-functions" || fail "lab-triage missing"
grep -q 'lab-re()' "$ROOT/stow/zsh/.shell-functions" || fail "lab-re missing"
grep -q 'lab-android()' "$ROOT/stow/zsh/.shell-functions" || fail "lab-android missing"
grep -q 'lab-web()' "$ROOT/stow/zsh/.shell-functions" || fail "lab-web missing"
grep -q 'hr-opencode()' "$ROOT/stow/zsh/.shell-functions" || fail "hr-opencode missing"
grep -q 'hr-agy()' "$ROOT/stow/zsh/.shell-functions" || fail "hr-agy missing"
grep -q 'CMD_NOTIFY_THRESHOLD:=15' "$ROOT/stow/zsh/.shell-functions" \
  || fail "notify threshold must be 15s"
grep -q 'active_border_color' "$ROOT/stow/zsh/.shell-functions" \
  || fail "kitty lab accents missing"
# Fail only on real bind paths, not comments about refusing secret dirs.
grep -E '(-v|--bind)[[:space:]].*\.ssh|/home/[^/]+/\.ssh|\.gnupg:' \
  "$ROOT/stow/zsh/.shell-functions" \
  && fail "labs must not mount .ssh/.gnupg" || true
grep -q '_lab_work_dir' "$ROOT/stow/zsh/.shell-functions" \
  || fail "labs must guard HOME/root work mounts"
grep -q 'refusing to mount' "$ROOT/stow/zsh/.shell-functions" \
  || fail "labs must warn on HOME/root work mounts"
# Lab images: no remote script piped to a shell; npm installs stay pinned.
for _cf in "$ROOT"/labs/*/Containerfile; do
  ! grep -v '^[[:space:]]*#' "$_cf" | grep -qE '(curl|wget)[^#]*\|[[:space:]]*([A-Z_]+=[^ ]+[[:space:]]+)*(ba|z)?sh\b' \
    || fail "$(basename "$(dirname "$_cf")"): no curl|sh in Containerfiles"
done
! grep -qE 'npm install -g @playwright/mcp playwright$|\|\| *npm install' "$ROOT/labs/lab-web/Containerfile" \
  || fail "lab-web must not fall back to unpinned npm installs"
grep -qE '^\s+chromium \\$' "$ROOT/labs/lab-web/Containerfile" \
  && grep -q 'PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH=/usr/bin/chromium' "$ROOT/labs/lab-web/Containerfile" \
  && grep -q 'PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1' "$ROOT/labs/lab-web/Containerfile" \
  || fail "lab-web must use signed Arch chromium (not Playwright Ubuntu-fallback CDN zip)"
grep -q -- '--executable-path' "$ROOT/labs/lab-web/mcp-playwright.sh" \
  && grep -q -- '--executablePath' "$ROOT/labs/lab-web/mcp-devtools.sh" \
  && grep -q 'exec /usr/local/bin/mcp-playwright' "$ROOT/labs/lab-web/mcp-devtools.sh" \
  || fail "lab-web MCP wrappers must wire Arch chromium path (mcp-devtools delegates to mcp-playwright)"
! grep -q 'npx --yes' "$ROOT/labs/lab-web/Containerfile" "$ROOT/labs/lab-web/mcp-playwright.sh" \
  "$ROOT/labs/lab-web/mcp-devtools.sh" "$ROOT/labs/lab-android/mcp-flutter.sh" "$ROOT/labs/lab-android/mcp-adb.sh" \
  || fail "lab MCP/Containerfile scripts must not run npx --yes (downloads unpinned latest)"
grep -qE '^\s+mise \\$' "$ROOT/labs/lab-web/Containerfile" || fail "lab-web must install mise from pacman"
unset -v _cf

# Labs keep the default seccomp filter (malware-facing); lab-re only adds SYS_PTRACE.
_fns="$ROOT/stow/zsh/.shell-functions"
! grep -v '^\s*#' "$_fns" | grep -q 'seccomp=unconfined' || fail "labs must not disable seccomp"
! grep -v '^\s*#' "$_fns" | grep -qE -- '--privileged|label=disable|apparmor=unconfined|--pid[ =]host|--network[ =]host' \
  || fail "labs must not use privileged/host-namespace podman flags"
_re="$(awk '/^lab-re\(\) \{/{f=1} f; f&&/^}$/{exit}' "$_fns")"
grep -q -- '--cap-add SYS_PTRACE' <<<"$_re" || fail "lab-re needs SYS_PTRACE for gdb attach"
unset -v _fns _re

# /work is mounted rw into the labs: run the real _lab_work_dir (bash + zsh)
# against home, its ancestors, hidden config dirs, the dotfiles repo, samples,
# and sensitive host/socket paths (/run/user, /var/lib, /opt, whole /tmp, /tmp
# session socket dirs, any dir holding a socket).
_wd="$(mktemp -d)"; _wd="$(cd "$_wd" && pwd -P)"
# Samples live outside the fake home so each refusal rule is tested on its own.
mkdir -p "$_wd/home/u/.config/x" "$_wd/home/u/dotfiles/stow" "$_wd/home/u/proj/a" \
  "$_wd/srv/lab/samples/case1" "$_wd/home/u/labs/out"
# A project dir holding a live socket (agent/IDE/tmux style), two levels down.
mkdir -p "$_wd/home/u/sockproj/run"
python3 -c 'import socket,sys; socket.socket(socket.AF_UNIX).bind(sys.argv[1])' "$_wd/home/u/sockproj/run/agent.sock"
for _sh in bash zsh; do
  command -v "$_sh" >/dev/null || continue
  for _case in "home/u:refuse" "home:refuse" ".:refuse" "home/u/.config:refuse" "home/u/.config/x:refuse" \
      "home/u/dotfiles:refuse" "home/u/dotfiles/stow:refuse" "srv/lab:refuse" "srv/lab/samples:refuse" \
      "srv/lab/samples/case1:refuse" "srv:refuse" "home/u/sockproj:refuse" "home/u/sockproj/run:refuse" \
      "home/u/proj:allow" "home/u/proj/a:allow"; do
    _dir="$_wd/${_case%%:*}"; _want=${_case##*:}
    _got="$(cd "$_dir" && HOME="$_wd/home/u" LAB_OUT="$_wd/home/u/labs/out" LAB_SAMPLES="$_wd/srv/lab/samples" \
      "$_sh" -c 'source "$1"; _lab_work_dir' _ "$ROOT/labs/lib/lab-workdir.sh" 2>/dev/null)"
    if [[ $_want == refuse ]]; then
      [[ $_got == "$_wd/home/u/labs/out" ]] || fail "$_sh: /work must refuse ${_case%%:*} (got $_got)"
    else
      [[ $_got == "$_dir" ]] || fail "$_sh: /work must allow ${_case%%:*} (got $_got)"
    fi
  done
  for _sysp in /run /run/user/1000 /var/lib /opt /tmp /srv/lab \
      /tmp/.X11-unix /tmp/.ICE-unix /tmp/tmux-1000 /tmp/tmux-1000/x /tmp/ssh-abc123 /tmp/systemd-private-x; do
    _r="$(HOME="$_wd/home/u" LAB_SAMPLES="$_wd/srv/lab/samples" \
      "$_sh" -c 'source "$1"; _lab_path_refusal_reason "$2"' _ "$ROOT/labs/lib/lab-workdir.sh" "$_sysp")"
    [[ -n $_r ]] || fail "$_sh: _lab_path_refusal_reason must refuse $_sysp"
  done
done
rm -rf "$_wd"; unset -v _wd _sh _case _dir _want _got _sysp _r
# One implementation: lab-* wrappers and lab-mcp.sh both use the shared lib, and
# the wrappers fail closed when it is missing.
grep -q 'lib/lab-workdir.sh' "$ROOT/labs/scripts/lab-mcp.sh" \
  || fail "lab-mcp.sh must use labs/lib/lab-workdir.sh"
! grep -qE 'refusing|readlink -f -- "\$\{HOME' "$ROOT/labs/scripts/lab-mcp.sh" || fail "lab-mcp.sh must not keep its own work-dir logic"
# Behaviour: lab-mcp's work_dir refuses $HOME under set -u even when LAB_SAMPLES is unset.
_wfn="$(grep -E '^work_dir\(\)' "$ROOT/labs/scripts/lab-mcp.sh")"
_h="$(mktemp -d)"; _h="$(cd "$_h" && pwd -P)"; mkdir -p "$_h/out"
_got="$(cd "$_h" && env -u LAB_SAMPLES HOME="$_h" LAB_OUT="$_h/out" bash -euo pipefail -c \
  'source "$1"; '"$_wfn"'; work_dir' _ "$ROOT/labs/lib/lab-workdir.sh" 2>/dev/null)"
[[ $_got == "$_h/out" ]] || fail "lab-mcp work_dir must refuse \$HOME without LAB_SAMPLES set (got $_got)"
rm -rf -- "$_h"; unset -v _wfn _h _got
grep -q 'labs/lib/lab-workdir.sh"' "$ROOT/stow/zsh/.shell-functions" || fail ".shell-functions must source the shared work-dir lib"
[[ $(grep -cF 'work=$(_lab_work_dir) || return 1' "$ROOT/stow/zsh/.shell-functions") -eq 3 ]] \
  || fail "every lab must stop when _lab_work_dir refuses"
_o="$(DOTFILES_DIR=/nonexistent HOME=/tmp bash -c 'source "$1" >/dev/null 2>&1; _lab_work_dir' _ "$ROOT/stow/zsh/.shell-functions" 2>&1)" \
  && fail "missing lab-workdir.sh must fail closed (got: $_o)"
unset -v _o
grep -q 'SYS_PTRACE' "$ROOT/stow/zsh/.shell-functions" \
  || fail "lab-re must add SYS_PTRACE"
grep -q 'seccomp=unconfined' "$ROOT/stow/zsh/.shell-functions" \
  || fail "lab-re must allow seccomp=unconfined for gdb/frida"
# SYS_PTRACE only on lab-re path (not shared default for triage/android/web)
triage_block=$(awk '/^lab-triage\(\)/,/^lab-re\(\)/' "$ROOT/stow/zsh/.shell-functions")
echo "$triage_block" | grep -q 'SYS_PTRACE' \
  && fail "lab-triage must not get SYS_PTRACE" || true

grep -E 'bash[[:space:]].*install-caveman\.sh' "$ROOT/ai/scripts/ai-stack-setup.sh" \
  && fail "ai-stack must not call install-caveman (full install.sh owns caveman; SETUP_AI = ponytail only)" || true
grep -q 'install-ponytail.sh' "$ROOT/ai/scripts/ai-stack-setup.sh" \
  || fail "ai-stack must still install ponytail"
grep -E 'bash[[:space:]].*install-rea\.sh' "$ROOT/ai/scripts/ai-stack-setup.sh" \
  && fail "ai-stack must not install REA on host (use lab-re)" || true
grep -E 'bash[[:space:]].*install-rea\.sh' "$ROOT/install.sh" \
  && fail "install.sh must not auto-run host install-rea (use lab-re)" || true
grep -q 'AI_STACK_EXTRAS_ONLY=1' "$ROOT/install.sh" \
  || fail "install.sh must run ai-stack extras (Continue / OpenCode / hr-proxy)"
grep -q 'AI_STACK_EXTRAS_ONLY' "$ROOT/ai/scripts/ai-stack-setup.sh" \
  || fail "ai-stack-setup.sh must honor AI_STACK_EXTRAS_ONLY"
grep -q 'ollama-setup.sh' "$ROOT/install.sh" \
  || fail "install.sh must run ollama-setup.sh (P15 no-op elsewhere)"
grep -q 'SKIP_OLLAMA' "$ROOT/install.sh" \
  || fail "install.sh must allow SKIP_OLLAMA=1"

grep -q 'jdk21-openjdk' "$ROOT/labs/lab-re/Containerfile" \
  || fail "lab-re must ship jdk21-openjdk"
grep -q 'ghidra' "$ROOT/labs/lab-re/Containerfile" \
  || fail "lab-re must ship ghidra"
grep -q 'jadx' "$ROOT/labs/lab-re/Containerfile" \
  || fail "lab-re must ship jadx"
grep -q 'rizin' "$ROOT/labs/lab-re/Containerfile" \
  || fail "lab-re must ship rizin"
grep -q 'rea-agents' "$ROOT/labs/lab-re/Containerfile" \
  || fail "lab-re must install rea-agents inside image"

grep -q 'SETUP_LABS' "$ROOT/provision/scripts/configure.sh" || fail "configure must wire SETUP_LABS"
grep -q 'labs-setup.sh' "$ROOT/provision/scripts/configure.sh" || fail "configure must call labs-setup"
grep -q 'ai-stack-setup.sh' "$ROOT/provision/scripts/configure.sh" || fail "configure must call ai-stack"
grep -q 'rice-setup.sh' "$ROOT/provision/scripts/configure.sh" || fail "configure must call rice-setup"
grep -q 'LABS_SLICE2' "$ROOT/provision/scripts/configure.sh" \
  && fail "Slice 2 placeholders must be gone" || true

# P15 ollama checklist default + no swallowed module failures
grep -q 'OLLAMA_STATE=on' "$ROOT/provision/scripts/configure.sh" \
  || fail "configure must set OLLAMA_STATE=on for P15"
grep -q 'is_p15 -eq 1' "$ROOT/provision/scripts/configure.sh" \
  || fail "configure must gate OLLAMA_STATE on is_p15"
grep -q 'lab-malware' "$ROOT/provision/scripts/configure.sh" \
  || fail "SETUP_FIREWALLD label must mention lab-malware"
# run_mod must not be paired with || true (would hide failures)
grep -E 'run_mod[[:space:]].*\|\|[[:space:]]*true' "$ROOT/provision/scripts/configure.sh" \
  && fail "configure must not swallow run_mod failures with || true" || true
grep -q 'selected SETUP_FIREWALLD' "$ROOT/provision/scripts/configure.sh" \
  || fail "configure must use selected() fail-fast module gates"
grep -q 'CONFIGURE_UI' "$ROOT/provision/scripts/configure.sh" \
  || fail "configure must support CONFIGURE_UI override"
grep -q -- '--add-source=192.168.200.0/24' "$ROOT/security/lib/lab-malware-zone.sh" \
  || fail "lab-malware-zone must permanently add source 192.168.200.0/24"
grep -q '67/udp' "$ROOT/security/lib/lab-malware-zone.sh" \
  || fail "lab-malware zone must allow DHCP (67/udp) under DROP"
grep -E 'for spec in .*68/udp' "$ROOT/security/lib/lab-malware-zone.sh" \
  && fail "lab-malware zone must not open 68/udp (host is DHCP server)" || true
grep -qE "<dns[^>]*enable=['\"]no['\"]" "$ROOT/security/scripts/firewalld-lab-zones.sh" \
  || fail "virbr-malware XML must set dns enable=no (INetSim owns DNS)"
grep -q 'dhcp-option=6,192.168.200.1' "$ROOT/security/scripts/firewalld-lab-zones.sh" \
  || fail "virbr-malware DHCP must advertise DNS 192.168.200.1 (INetSim)"
grep -qE 'zone=["'\'']lab-malware["'\'']' "$ROOT/security/scripts/firewalld-lab-zones.sh" \
  || fail "virbr-malware bridge XML must set zone=lab-malware (stop libvirt reclaim)"
_fw_zone_ln="$(grep -n -m1 '^ensure_lab_malware_zone$' "$ROOT/security/scripts/firewalld-lab-zones.sh" | cut -d: -f1)"
_fw_start_ln="$(grep -n -m1 'virsh net-start virbr-malware' "$ROOT/security/scripts/firewalld-lab-zones.sh" | cut -d: -f1)"
[[ -n $_fw_zone_ln && -n $_fw_start_ln ]] && (( _fw_zone_ln < _fw_start_ln )) \
  || fail "firewalld-lab-zones must create lab-malware zone before virsh net-start virbr-malware"
unset -v _fw_zone_ln _fw_start_ln
grep -q 'sudo firewall-cmd --permanent --get-zones' "$ROOT/security/scripts/firewalld-lab-zones.sh" \
  || fail "firewalld-lab-zones must query zones with sudo"

grep -q '^bubblewrap$' "$ROOT/packages/pacman.txt" || fail "bubblewrap in pacman.txt"
grep -q '^libnotify$' "$ROOT/packages/pacman.txt" || fail "libnotify in pacman.txt"
grep -q '^btop$' "$ROOT/packages/pacman.txt" || fail "btop in pacman.txt"

grep -q '127.0.0.1:11434' "$ROOT/stow/continue/.continue/config.yaml" \
  || fail "continue must point at local ollama"
grep -q 'maxPromptTokens: 2048' "$ROOT/stow/continue/.continue/config.yaml" \
  || fail "continue FIM token budget"

grep -q 'env_var.LAB_BADGE' "$ROOT/stow/starship/.config/starship.toml" \
  || fail "starship LAB_BADGE badge"

# Kitty ships theme.conf (Gruvbox default) + themes/; rice-theme overrides via theme.local.conf
[[ -f $ROOT/stow/kitty/.config/kitty/theme.conf ]] \
  || fail "kitty must ship theme.conf (Gruvbox default)"
grep -qx 'include theme.conf' "$ROOT/stow/kitty/.config/kitty/kitty.conf" \
  || fail "kitty.conf must include theme.conf"

# Desktop launchers: lab-* are .bashrc functions, so Exec must be an interactive
# bash (bash -lc skips .bashrc); quotes must be spec-valid (double, not single).
APPS="$ROOT/stow/applications/.local/share/applications"
for fn in lab-re lab-android; do
  grep -qx "Exec=bash -ic \"$fn\"" "$APPS/$fn.desktop" \
    || fail "$fn.desktop must use Exec=bash -ic \"$fn\""
done
grep -q "^Exec=.*'" "$APPS"/*.desktop && fail "launcher Exec must not use single quotes"
if command -v desktop-file-validate >/dev/null 2>&1; then
  desktop-file-validate "$APPS"/*.desktop 2>&1 | grep -v ' hint: ' | grep -q . \
    && fail "desktop-file-validate: $(desktop-file-validate "$APPS"/*.desktop 2>&1 | grep -v ' hint: ' | head -1)"
fi
grep -q 'BASH_EXECUTION_STRING' "$ROOT/stow/bash/.bashrc" \
  || fail ".bashrc must not attach ble.sh for bash -ic launchers"
# Terminal=true launchers open in kitty via xdg-terminal-exec.
grep -qx 'xdg-terminal-exec' "$ROOT/packages/pacman.txt" || fail "pacman.txt missing xdg-terminal-exec"
[[ "$(grep -v '^#' "$ROOT/stow/kitty/.config/xdg-terminals.list" | head -1)" == kitty.desktop ]] \
  || fail "xdg-terminals.list must prefer kitty.desktop"

# Re-exec into kitty with no args must not pass an empty argument (bash printf
# '%q ' with zero args yields '', which became podman's container command).
if command -v script >/dev/null 2>&1; then
  STUB="$(mktemp -d)"
  trap 'rm -rf -- "$STUB"' EXIT
  printf '#!/bin/sh\nfor a in "$@"; do printf "<%%s>" "$a"; done; echo\n' >"$STUB/kitty"
  chmod +x "$STUB/kitty"
  for sh in bash zsh; do
    command -v "$sh" >/dev/null 2>&1 || continue
    out="$(script -qec "env -i HOME=/nonexistent TERM=xterm SHELL=/bin/sh PATH=$STUB:/usr/bin:/bin \
      $sh -c 'source \"$ROOT/stow/zsh/.shell-functions\"; _lab_reexec_kitty T \"#000\" lab-re'" /dev/null 2>&1 | tr -d '\r')"
    grep -q '<-c><lab-re >' <<<"$out" || fail "$sh: zero-arg kitty re-exec must run 'lab-re ' (got: $out)"
    grep -q "<lab-re ''" <<<"$out" && fail "$sh: zero-arg kitty re-exec passed an empty argument"
  done
else
  echo "NOTE: skip kitty re-exec check (no script(1) for a pty)"
fi

# Regression checks for Slice 2 / shell / desktop hardening fixes
grep -qE '^[^#]*dconf write.*/media-keys/' "$ROOT/desktop/scripts/gnome-console-setup.sh" \
  && fail "gnome-console-setup.sh must not overwrite GNOME media-keys / custom-keybindings" || true

# Behavioral: .shell-aliases j='cd' (stub zoxide so CI without zoxide runs it)
# and .shell-exports CHROME_EXECUTABLE handling.
(
  _st="$(mktemp -d)"
  trap 'rm -rf "$_st"' EXIT
  mkdir -p "$_st/bin"
  printf '#!/bin/sh\nexit 0\n' >"$_st/bin/zoxide"
  chmod +x "$_st/bin/zoxide"
  _j_alias="$(PATH="$_st/bin:$PATH" bash -c "source '$ROOT/stow/zsh/.shell-aliases'; alias j 2>/dev/null || true")"
  [[ "$_j_alias" == *"='cd'"* ]] || fail ".shell-aliases j must target cd (got: $_j_alias)"
)
(
  _ce_out="$(env -i PATH="/usr/bin:/bin" HOME=/nonexistent bash -c \
    "source '$ROOT/stow/zsh/.shell-exports'; printf '%s|%s' \"\${CHROME_EXECUTABLE:-}\" \"\${PUPPETEER_EXECUTABLE_PATH:-}\"")"
  if [[ ! -x /usr/bin/google-chrome-stable && ! -x /usr/bin/google-chrome && ! -x /usr/bin/chromium ]]; then
    [[ "$_ce_out" == "|" ]] || fail ".shell-exports must leave CHROME_EXECUTABLE unset when no native Chrome exists (got: $_ce_out)"
  fi
  _ce_ov="$(env -i PATH="/usr/bin:/bin" HOME=/nonexistent CHROME_EXECUTABLE=/custom/chrome bash -c \
    "source '$ROOT/stow/zsh/.shell-exports'; printf '%s|%s' \"\${CHROME_PATH:-}\" \"\${PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH:-}\"")"
  [[ "$_ce_ov" == "/custom/chrome|/custom/chrome" ]] || fail ".shell-exports must propagate CHROME_EXECUTABLE override (got: $_ce_ov)"
)

# Behavioral: ai-stack-setup.sh (P15) merges ollama into an existing opencode.json
# without touching the real systemd user session (stub systemctl on PATH), and
# preserves an existing user model and custom provider.ollama config.
(
  _p15_t="$(mktemp -d)"
  trap 'rm -rf "$_p15_t"' EXIT
  mkdir -p "$_p15_t/bin" "$_p15_t/dmi" "$_p15_t/home/.config/opencode"
  printf '#!/bin/sh\nexit 0\n' >"$_p15_t/bin/systemctl"
  chmod +x "$_p15_t/bin/systemctl"
  printf 'ThinkPad P15 Gen 1\n' >"$_p15_t/dmi/product_family"
  printf '20SUS2FJ00\n' >"$_p15_t/dmi/product_name"
  printf 'LENOVO_MT_20SU\n' >"$_p15_t/dmi/product_sku"
  # Case 1: existing MCP/share without ollama/model → adds defaults, keeps existing keys
  printf '{"mcp":{"obscura":{"enabled":true}},"share":"disabled"}\n' \
    >"$_p15_t/home/.config/opencode/opencode.json"
  PATH="$_p15_t/bin:$PATH" HOME="$_p15_t/home" XDG_CONFIG_HOME="$_p15_t/home/.config" \
    DMI_SYSFS_ROOT="$_p15_t/dmi" AI_STACK_EXTRAS_ONLY=1 \
    bash "$ROOT/ai/scripts/ai-stack-setup.sh" >/dev/null
  python3 - "$_p15_t/home/.config/opencode/opencode.json" <<'PY' \
    || fail "ai-stack-setup.sh failed to merge ollama into existing opencode.json"
import json, sys
d = json.load(open(sys.argv[1]))
assert d["mcp"]["obscura"]["enabled"] is True, d
assert d["share"] == "disabled", d
assert d["provider"]["ollama"]["options"]["baseURL"] == "http://127.0.0.1:11434/v1", d
assert d["model"] == "ollama/qwen3.5:4b", d
PY
  # Case 2: existing custom model + provider.ollama.models must not be overwritten
  printf '{"model":"custom/model","provider":{"ollama":{"models":{"mine:1b":{"name":"mine:1b"}}}}}\n' \
    >"$_p15_t/home/.config/opencode/opencode.json"
  PATH="$_p15_t/bin:$PATH" HOME="$_p15_t/home" XDG_CONFIG_HOME="$_p15_t/home/.config" \
    DMI_SYSFS_ROOT="$_p15_t/dmi" AI_STACK_EXTRAS_ONLY=1 \
    bash "$ROOT/ai/scripts/ai-stack-setup.sh" >/dev/null
  python3 - "$_p15_t/home/.config/opencode/opencode.json" <<'PY' \
    || fail "ai-stack-setup.sh overwrote existing model or provider.ollama"
import json, sys
d = json.load(open(sys.argv[1]))
assert d["model"] == "custom/model", d
assert d["provider"]["ollama"]["models"] == {"mine:1b": {"name": "mine:1b"}}, d
PY
)

# Behavioral: labs-setup.sh Android udev rules — fresh install, legacy 0666/plugdev
# rewrite (even if /usr/lib copy exists), and /usr/lib-only preservation.
(
  _ut="$(mktemp -d)"
  trap 'rm -rf "$_ut"' EXIT
  mkdir -p "$_ut/bin" "$_ut/usr" "$_ut/etc"
  printf '#!/bin/sh\nexec "$@"\n' >"$_ut/bin/sudo"
  printf '#!/bin/sh\nexit 0\n' >"$_ut/bin/udevadm"
  chmod +x "$_ut/bin/sudo" "$_ut/bin/udevadm"
  _udev_block="$(sed -n '/^# adb udev (host)/,/^unset _legacy_udev$/p' "$ROOT/labs/scripts/labs-setup.sh")"
  [[ -n "$_udev_block" ]] || fail "labs-setup.sh missing udev block"
  # 1. Fresh install writes 0660 + TAG+="uaccess", no 0666/plugdev
  PATH="$_ut/bin:$PATH" ANDROID_UDEV_USR="$_ut/usr/51-android.rules" \
    ANDROID_UDEV_ETC="$_ut/etc/51-android.rules" bash -euo pipefail -c "$_udev_block" >/dev/null
  grep -q 'TAG+="uaccess"' "$_ut/etc/51-android.rules" || fail "labs-setup udev fresh install missing uaccess"
  grep -qE '0666|plugdev' "$_ut/etc/51-android.rules" && fail "labs-setup udev fresh install wrote 0666/plugdev" || true
  # 2. Legacy /etc file with 0666/plugdev is rewritten even when /usr/lib exists; /usr/lib stays untouched
  printf '# distro copy\n' >"$_ut/usr/51-android.rules"
  printf 'SUBSYSTEM=="usb", ATTR{idVendor}=="18d1", MODE="0666", GROUP="plugdev"\n' >"$_ut/etc/51-android.rules"
  PATH="$_ut/bin:$PATH" ANDROID_UDEV_USR="$_ut/usr/51-android.rules" \
    ANDROID_UDEV_ETC="$_ut/etc/51-android.rules" bash -euo pipefail -c "$_udev_block" >/dev/null
  grep -q 'TAG+="uaccess"' "$_ut/etc/51-android.rules" || fail "labs-setup failed to upgrade legacy 0666/plugdev rule"
  grep -qE '0666|plugdev' "$_ut/etc/51-android.rules" && fail "labs-setup left 0666/plugdev in upgraded rule" || true
  [[ "$(cat "$_ut/usr/51-android.rules")" == "# distro copy" ]] || fail "labs-setup modified /usr/lib udev copy"
  # 3. Clean /usr/lib copy with no /etc file is left alone (no /etc file created)
  rm -f "$_ut/etc/51-android.rules"
  PATH="$_ut/bin:$PATH" ANDROID_UDEV_USR="$_ut/usr/51-android.rules" \
    ANDROID_UDEV_ETC="$_ut/etc/51-android.rules" bash -euo pipefail -c "$_udev_block" >/dev/null
  [[ ! -e "$_ut/etc/51-android.rules" ]] || fail "labs-setup created /etc rule when /usr/lib copy already existed"
)

# Behavioral: install-obscura.sh MCP merge writes Kimi without Cursor dir,
# does NOT create ~/.claude.json without ~/.claude, and writes it when ~/.claude exists.
(
  _ot="$(mktemp -d)"
  trap 'rm -rf "$_ot"' EXIT
  mkdir -p "$_ot/home/.kimi-code"
  _py_block="$(sed -n '/^  python3 - "\$obscura_bin" <<'\''PY'\''$/,/^PY$/p' "$ROOT/ai/scripts/install-obscura.sh" | sed '1d;$d')"
  [[ -n "$_py_block" ]] || fail "install-obscura.sh missing agent MCP merge block"
  HOME="$_ot/home" python3 -c "$_py_block" "/usr/local/bin/obscura" >/dev/null
  [[ -f "$_ot/home/.kimi-code/mcp.json" ]] || fail "install-obscura skipped Kimi MCP when ~/.cursor absent"
  [[ ! -e "$_ot/home/.claude.json" ]] || fail "install-obscura created ~/.claude.json without ~/.claude dir"
  mkdir -p "$_ot/home/.claude"
  HOME="$_ot/home" python3 -c "$_py_block" "/usr/local/bin/obscura" >/dev/null
  [[ -f "$_ot/home/.claude.json" ]] || fail "install-obscura skipped ~/.claude.json when ~/.claude exists"
)

# Behavioral: rice-setup.sh does not duplicate CMD_NOTIFY_THRESHOLD in ~/.zshrc.local
(
  _rt="$(mktemp -d)"
  trap 'rm -rf "$_rt"' EXIT
  mkdir -p "$_rt/bin" "$_rt/home"
  for _c in sudo stow gsettings; do
    printf '#!/bin/sh\nexit 0\n' >"$_rt/bin/$_c"
    chmod +x "$_rt/bin/$_c"
  done
  PATH="$_rt/bin:$PATH" HOME="$_rt/home" bash "$ROOT/desktop/scripts/rice-setup.sh" >/dev/null
  PATH="$_rt/bin:$PATH" HOME="$_rt/home" bash "$ROOT/desktop/scripts/rice-setup.sh" >/dev/null
  _n="$(grep -c 'CMD_NOTIFY_THRESHOLD' "$_rt/home/.zshrc.local")"
  [[ "$_n" -eq 1 ]] || fail "rice-setup.sh duplicated CMD_NOTIFY_THRESHOLD in .zshrc.local (count=$_n)"
)

# Behavioral: agent-run.sh shares lib/lab-workdir.sh; refuses sensitive system/socket
# paths (/run, /var/lib, /opt, whole /tmp, /tmp session socket dirs, dirs holding
# a socket), home/hidden/dotfiles/samples; allows project dir.
grep -q 'lib/lab-workdir.sh' "$ROOT/ai/scripts/agent-run.sh" \
  || fail "agent-run.sh must source shared labs/lib/lab-workdir.sh"
(
  _ar="$(mktemp -d)"; _ar="$(cd "$_ar" && pwd -P)"
  trap 'rm -rf "$_ar"' EXIT
  mkdir -p "$_ar/bin" "$_ar/home/u/.ssh" "$_ar/home/u/dotfiles/sub" "$_ar/home/u/proj/a" "$_ar/srv/lab/samples/case1"
  mkdir -p "$_ar/home/u/sockproj"
  python3 -c 'import socket,sys; socket.socket(socket.AF_UNIX).bind(sys.argv[1])' "$_ar/home/u/sockproj/tmux.sock"
  printf '#!/bin/sh\necho PODMAN_OK\n' >"$_ar/bin/podman"
  chmod +x "$_ar/bin/podman"
  for _bad in "$_ar/home/u" "$_ar/home" "$_ar/home/u/.ssh" "$_ar/home/u/dotfiles" "$_ar/home/u/dotfiles/sub" \
      "$_ar/srv/lab/samples" "$_ar/srv/lab/samples/case1" "$_ar/home/u/sockproj" \
      /run /var/lib /opt /tmp /tmp/.X11-unix "/tmp/tmux-$(id -u)"; do
    [[ -d "$_bad" ]] || continue
    if PATH="$_ar/bin:$PATH" HOME="$_ar/home/u" LAB_SAMPLES="$_ar/srv/lab/samples" \
        bash "$ROOT/ai/scripts/agent-run.sh" "$_bad" alpine:3.20 >/dev/null 2>&1; then
      fail "agent-run.sh must refuse $_bad"
    fi
  done
  _ok="$(PATH="$_ar/bin:$PATH" HOME="$_ar/home/u" LAB_SAMPLES="$_ar/srv/lab/samples" \
    bash "$ROOT/ai/scripts/agent-run.sh" "$_ar/home/u/proj/a" alpine:3.20 2>&1)"
  [[ "$_ok" == "PODMAN_OK" ]] || fail "agent-run.sh must allow normal project dir (got: $_ok)"
)

# Behavioral: lab-android entrypoint stays stdout-silent when piped (MCP stdio safety).
_ae_out="$(bash "$ROOT/labs/lab-android/entrypoint.sh" printf '%s' '{"jsonrpc":"2.0"}' </dev/null)"
[[ "$_ae_out" == '{"jsonrpc":"2.0"}' ]] || fail "lab-android entrypoint polluted non-tty stdout: $_ae_out"
unset -v _ae_out

# Wayland pass-through in lab-android must export XDG_RUNTIME_DIR and check socket exists.
_la_fn="$(awk '/^lab-android\(\) \{/{f=1} f; f&&/^}$/{exit}' "$ROOT/stow/zsh/.shell-functions")"
grep -q 'XDG_RUNTIME_DIR=\${XDG_RUNTIME_DIR}' <<<"$_la_fn" \
  && grep -q -- '-S "\${XDG_RUNTIME_DIR}/\${WAYLAND_DISPLAY}"' <<<"$_la_fn" \
  || fail "lab-android must export XDG_RUNTIME_DIR and guard Wayland bind with -S"
unset -v _la_fn

# Behavioral: fastfetch templates parse cleanly and render without color/schema errors.
for _ff in "$ROOT"/stow/fastfetch/.config/fastfetch/*.jsonc; do
  jq empty "$_ff" || fail "invalid fastfetch JSON: $_ff"
  if command -v fastfetch >/dev/null 2>&1; then
    _ff_out="$(fastfetch --config "$_ff" --pipe false 2>&1)" \
      || fail "fastfetch failed on $_ff: $_ff_out"
    ! grep -q '^Error:' <<<"$_ff_out" \
      || fail "fastfetch reported error on $_ff: $(grep '^Error:' <<<"$_ff_out" | head -1)"
  fi
done
unset -v _ff _ff_out

# Behavioral: multi-theme configs (starship, btop, ghostty, alacritty, kitty, nvim)
# parse cleanly and rice-theme switches them in an isolated XDG_CONFIG_HOME.
python3 - "$ROOT" <<'PY' || fail "TOML config parse failed"
import pathlib, sys, tomllib
root = pathlib.Path(sys.argv[1])
toml_files = [
    root / "stow/starship/.config/starship.toml",
    root / "stow/alacritty/.config/alacritty/alacritty.toml",
    root / "stow/alacritty/.config/alacritty/theme.toml",
    *sorted((root / "stow/alacritty/.config/alacritty/themes").glob("*.toml")),
]
for p in toml_files:
    data = tomllib.loads(p.read_text())
    if p.name == "starship.toml":
        for pal in ("gruvbox_dark", "secops"):
            assert pal in data["palettes"], f"starship missing palette {pal}"
PY
for _bt in gruvbox_dark secops; do
  _bf="$ROOT/stow/btop/.config/btop/themes/${_bt}.theme"
  [[ -f "$_bf" ]] || fail "missing btop theme $_bt"
  grep -qE '^theme\[main_bg\]="#[0-9a-fA-F]{6}"$' "$_bf" \
    && grep -qE '^theme\[cpu_box\]="#[0-9a-fA-F]{6}"$' "$_bf" \
    || fail "btop theme $_bt missing required theme[main_bg/cpu_box] hex keys"
  ! grep -vE '^[[:space:]]*(#|$|theme\[[a-z0-9_]+\]="#[0-9a-fA-F]{6}")' "$_bf" | grep -q . \
    || fail "btop theme $_bt has malformed line"
done
for _gt in gruvbox secops; do
  [[ -f "$ROOT/stow/ghostty/.config/ghostty/themes/${_gt}.conf" ]] || fail "missing ghostty theme $_gt"
  [[ -f "$ROOT/stow/kitty/.config/kitty/themes/${_gt}.conf" ]] || fail "missing kitty theme $_gt"
done
[[ -f "$ROOT/stow/nvim/.config/nvim/colors/rice_gruvbox.lua" ]] \
  && [[ -f "$ROOT/stow/nvim/.config/nvim/colors/rice_secops.lua" ]] \
  || fail "missing nvim rice_* colorschemes"
# Active defaults must match one of their shipped templates (no silent drift).
_match_any() {
  local def=$1 f; shift
  for f in "$@"; do cmp -s "$def" "$f" && return 0; done
  return 1
}
_match_any "$ROOT/stow/fastfetch/.config/fastfetch/config.jsonc" \
  "$ROOT"/stow/fastfetch/.config/fastfetch/{gruvbox,minimal,secops}.jsonc \
  || fail "fastfetch/config.jsonc drifted from shipped presets"
_match_any "$ROOT/stow/ghostty/.config/ghostty/theme.conf" \
  "$ROOT"/stow/ghostty/.config/ghostty/themes/*.conf \
  || fail "ghostty/theme.conf drifted from shipped themes"
_match_any "$ROOT/stow/alacritty/.config/alacritty/theme.toml" \
  "$ROOT"/stow/alacritty/.config/alacritty/themes/*.toml \
  || fail "alacritty/theme.toml drifted from shipped themes"
_match_any "$ROOT/stow/kitty/.config/kitty/theme.conf" \
  "$ROOT"/stow/kitty/.config/kitty/themes/*.conf \
  || fail "kitty/theme.conf drifted from shipped themes"
unset -f _match_any
grep -qx 'import = \["theme.toml", "theme.local.toml"\]' "$ROOT/stow/alacritty/.config/alacritty/alacritty.toml" \
  || fail "alacritty.toml must import theme.toml and optional theme.local.toml"
grep -qx 'config-file = ?theme.local.conf' "$ROOT/stow/ghostty/.config/ghostty/config" \
  || fail "ghostty config must load optional theme.local.conf"
grep -qx 'include theme.local.conf' "$ROOT/stow/kitty/.config/kitty/kitty.conf" \
  || fail "kitty.conf must include theme.local.conf"
grep -q '"type": "auto"' "$ROOT/stow/fastfetch/.config/fastfetch/gruvbox.jsonc" \
  || fail "fastfetch gruvbox must use logo type auto (PNG + fallback)"
grep -q 'logos/gruvbox.png' "$ROOT/stow/fastfetch/.config/fastfetch/gruvbox.jsonc" \
  || fail "fastfetch gruvbox must point at logos/gruvbox.png"
grep -q 'logos/secops.png' "$ROOT/stow/fastfetch/.config/fastfetch/secops.jsonc" \
  || fail "fastfetch secops must point at logos/secops.png"
[[ -f $ROOT/stow/fastfetch/.config/fastfetch/logos/gruvbox.png \
  && -f $ROOT/stow/fastfetch/.config/fastfetch/logos/secops.png ]] \
  || fail "missing fastfetch logo PNGs"
grep -qE '^[[:space:]]*colors: gruvbox-dark$' "$ROOT/stow/contour/.config/contour/contour.yml" \
  || fail "contour.yml default colors must be gruvbox-dark"
grep -qE '^[[:space:]]*secops:$' "$ROOT/stow/contour/.config/contour/contour.yml" \
  || fail "contour.yml must define secops color scheme"
[[ -f $ROOT/stow/gnome-text-editor/.local/share/gtksourceview-5/styles/secops-dark.xml ]] \
  || fail "missing Text Editor secops-dark style scheme"
grep -q '_rice_apply_cli\|_rice_gnome\|_rice_contour' "$ROOT/stow/zsh/.shell-functions" \
  || fail "shell-functions must define rice cli/gnome/contour helpers"
[[ -x $ROOT/stow/contour/.local/bin/contour ]] \
  || fail "missing executable contour rice wrapper"
grep -q '\$HOME/\.local/bin/contour' "$ROOT/stow/contour/.local/share/applications/org.contourterminal.Contour.desktop" \
  || fail "Contour desktop must Exec the rice wrapper via \$HOME/.local/bin/contour"
grep -qE 'alacritty contour$' "$ROOT/desktop/scripts/rice-setup.sh" \
  || grep -q 'alacritty contour' "$ROOT/desktop/scripts/rice-setup.sh" \
  || fail "rice-setup pacman must install contour"
grep -qx 'color_scheme=5' "$ROOT/stow/htop/.config/htop/htoprc" \
  || fail "htoprc default must be Black Night (5) for gruvbox"
grep -q "style-scheme='gruvbox-dark'" "$ROOT/desktop/gnome/dconf/user.conf" \
  || fail "user.conf TextEditor scheme must be gruvbox-dark (rice default)"
grep -q 'JetBrainsMono Nerd Font 13' "$ROOT/desktop/scripts/gnome-console-setup.sh" \
  || fail "gnome-console-setup must set kgx font 13"
grep -q "custom-font='JetBrainsMono Nerd Font 13'" "$ROOT/desktop/gnome/dconf/user.conf" \
  || fail "dconf user.conf Console font must be 13 (session load must not undo console-setup)"
grep -q "monospace-font-name='JetBrainsMono Nerd Font 13'" "$ROOT/desktop/gnome/dconf/user.conf" \
  || fail "dconf user.conf monospace font must be 13"
! grep -q 'custom-font' "$ROOT/desktop/scripts/rice-setup.sh" \
  || fail "rice-setup must not set kgx font (gnome-console-setup + user.conf)"
grep -q 'fail_rice\|RICE_FAILED' "$ROOT/desktop/scripts/rice-setup.sh" \
  || fail "rice-setup must fail loud (no silent || true on stow/pacman)"
grep -qx 'save_config_on_exit = false' "$ROOT/stow/btop/.config/btop/btop.conf" \
  || fail "btop.conf must set save_config_on_exit = false (stowed file)"
(
  _rt="$(mktemp -d)"
  trap 'rm -rf "$_rt"' EXIT
  mkdir -p "$_rt/cfg/fastfetch/logos" "$_rt/cfg/btop/themes" "$_rt/cfg/ghostty/themes" \
    "$_rt/cfg/alacritty/themes" "$_rt/cfg/kitty/themes" "$_rt/cfg/nvim/colors" \
    "$_rt/cfg/contour" "$_rt/cfg/htop" "$_rt/state" "$_rt/empty" "$_rt/bin"
  # Stubs log their arguments: the wrappers must pick the override config.
  for _c in fastfetch btop; do
    printf '#!/bin/sh\necho "%s $*" >>"$RICE_LOG"\n' "$_c" >"$_rt/bin/$_c"; chmod +x "$_rt/bin/$_c"
  done
  printf '#!/bin/sh\necho "htop HTOPRC=${HTOPRC:-} $*" >>"$RICE_LOG"\n' >"$_rt/bin/htop"; chmod +x "$_rt/bin/htop"
  # Contour: real binary stub + stowed rice wrapper (CONTOUR_BIN).
  printf '#!/bin/sh\necho "contour $*" >>"$RICE_LOG"\n' >"$_rt/bin/contour-real"; chmod +x "$_rt/bin/contour-real"
  cp "$ROOT/stow/contour/.local/bin/contour" "$_rt/bin/contour"; chmod +x "$_rt/bin/contour"
  # Never touch the real session bus from rice-theme GNOME hooks.
  printf '#!/bin/sh\necho "gsettings $*" >>"$RICE_LOG"\n' >"$_rt/bin/gsettings"; chmod +x "$_rt/bin/gsettings"
  cp "$ROOT"/stow/fastfetch/.config/fastfetch/*.jsonc "$_rt/cfg/fastfetch/"
  cp "$ROOT"/stow/fastfetch/.config/fastfetch/logos/*.png "$_rt/cfg/fastfetch/logos/" 2>/dev/null || true
  cp "$ROOT/stow/btop/.config/btop/btop.conf" "$_rt/cfg/btop/"
  cp "$ROOT"/stow/btop/.config/btop/themes/*.theme "$_rt/cfg/btop/themes/"
  cp "$ROOT/stow/starship/.config/starship.toml" "$_rt/cfg/"
  cp "$ROOT/stow/ghostty/.config/ghostty/theme.conf" "$_rt/cfg/ghostty/"
  cp "$ROOT"/stow/ghostty/.config/ghostty/themes/*.conf "$_rt/cfg/ghostty/themes/"
  cp "$ROOT/stow/alacritty/.config/alacritty/theme.toml" "$_rt/cfg/alacritty/"
  cp "$ROOT"/stow/alacritty/.config/alacritty/themes/*.toml "$_rt/cfg/alacritty/themes/"
  cp "$ROOT/stow/kitty/.config/kitty/theme.conf" "$_rt/cfg/kitty/"
  cp "$ROOT"/stow/kitty/.config/kitty/themes/*.conf "$_rt/cfg/kitty/themes/"
  cp "$ROOT"/stow/nvim/.config/nvim/colors/rice_*.lua "$_rt/cfg/nvim/colors/"
  cp "$ROOT/stow/contour/.config/contour/contour.yml" "$_rt/cfg/contour/"
  cp "$ROOT/stow/htop/.config/htop/htoprc" "$_rt/cfg/htop/"
  export RICE_LOG="$_rt/log"
  _st="$_rt/state/dotfiles/theme"
  # _rs <commands>: run in a fresh shell that sourced .shell-functions (like a new terminal).
  _rs() {
    env -u STARSHIP_CONFIG XDG_CONFIG_HOME="$_rt/cfg" XDG_STATE_HOME="$_rt/state" \
      CONTOUR_BIN="$_rt/bin/contour-real" PATH="$_rt/bin:$PATH" \
      "$_sh" -c 'source "$1"; '"$1" _ "$ROOT/stow/zsh/.shell-functions"
  }
  _tracked_unchanged() {
    cmp -s "$ROOT/stow/fastfetch/.config/fastfetch/config.jsonc" "$_rt/cfg/fastfetch/config.jsonc" \
      && cmp -s "$ROOT/stow/ghostty/.config/ghostty/theme.conf" "$_rt/cfg/ghostty/theme.conf" \
      && cmp -s "$ROOT/stow/alacritty/.config/alacritty/theme.toml" "$_rt/cfg/alacritty/theme.toml" \
      && cmp -s "$ROOT/stow/kitty/.config/kitty/theme.conf" "$_rt/cfg/kitty/theme.conf" \
      && cmp -s "$ROOT/stow/btop/.config/btop/btop.conf" "$_rt/cfg/btop/btop.conf" \
      && cmp -s "$ROOT/stow/starship/.config/starship.toml" "$_rt/cfg/starship.toml"
  }
  for _sh in bash zsh; do
    command -v "$_sh" >/dev/null || continue
    rm -rf "$_rt/state"
    rm -f "$_rt/cfg/ghostty/theme.local.conf" "$_rt/cfg/alacritty/theme.local.toml" \
      "$_rt/cfg/kitty/theme.local.conf"
    cp "$ROOT/stow/starship/.config/starship.toml" "$_rt/cfg/"
    cp "$ROOT/stow/btop/.config/btop/btop.conf" "$_rt/cfg/btop/"
    # ff-preset: list, use (saves a name, never touches config.jsonc), ff honours it, reset, traversal
    _fl="$(_rs 'ff-preset')"
    grep -qx gruvbox <<<"$_fl" && grep -qx minimal <<<"$_fl" && grep -qx secops <<<"$_fl" \
      || fail "$_sh: ff-preset list missing presets: $_fl"
    _rs 'ff-preset use minimal >/dev/null'
    [[ "$(cat "$_st/fastfetch")" == minimal ]] || fail "$_sh: ff-preset use must save the preset name"
    : >"$RICE_LOG"; _rs 'ff'
    grep -qx "fastfetch --config $_rt/cfg/fastfetch/minimal.jsonc" "$RICE_LOG" || fail "$_sh: ff must use the saved preset: $(cat "$RICE_LOG")"
    : >"$RICE_LOG"; _rs 'ff --pipe false'
    grep -qx "fastfetch --config $_rt/cfg/fastfetch/minimal.jsonc --pipe false" "$RICE_LOG" || fail "$_sh: ff with non-config flags must keep saved preset: $(cat "$RICE_LOG")"
    : >"$RICE_LOG"; _rs 'ff -c gruvbox'
    grep -qx 'fastfetch -c gruvbox' "$RICE_LOG" || fail "$_sh: ff -c must pass through without override"
    _rs 'ff-preset reset >/dev/null'
    : >"$RICE_LOG"; _rs 'ff'
    grep -qx 'fastfetch ' "$RICE_LOG" || fail "$_sh: ff after reset must run the repo config.jsonc"
    ! _rs 'ff-preset ../bad >/dev/null 2>&1' || fail "$_sh: ff-preset must reject traversal"
    # rice-theme --dry alone must error; --dry gruvbox must not write
    ! _rs 'rice-theme --dry >/dev/null 2>&1' || fail "$_sh: rice-theme --dry without a theme must fail"
    _rs 'rice-theme --dry gruvbox >/dev/null'
    [[ ! -e $_st/fastfetch && ! -L $_rt/cfg/ghostty/theme.local.conf && ! -L $_rt/cfg/kitty/theme.local.conf ]] \
      || fail "$_sh: rice-theme --dry must not write state or theme.local links"
    # rice-theme: names in state, links for ghostty/alacritty/kitty, starship + nvim
    _sc="$(_rs 'rice-theme gruvbox >/dev/null; printf %s "${STARSHIP_CONFIG:-}"')"
    [[ $_sc == "$_st/starship.toml" ]] || fail "$_sh: rice-theme must point STARSHIP_CONFIG at the override (got $_sc)"
    grep -qx "palette = 'gruvbox_dark'" "$_st/starship.toml" || fail "$_sh: rice-theme gruvbox missed starship"
    [[ "$(cat "$_st/fastfetch")" == gruvbox && "$(cat "$_st/btop")" == gruvbox_dark ]] \
      || fail "$_sh: rice-theme gruvbox must save fastfetch/btop names"
    [[ "$(cat "$_st/nvim")" == rice_gruvbox ]] || fail "$_sh: rice-theme gruvbox must save nvim colorscheme"
    [[ "$(readlink "$_rt/cfg/ghostty/theme.local.conf")" == themes/gruvbox.conf ]] || fail "$_sh: ghostty theme.local.conf must link to themes/gruvbox.conf"
    [[ "$(readlink "$_rt/cfg/alacritty/theme.local.toml")" == themes/gruvbox.toml ]] || fail "$_sh: alacritty theme.local.toml must link to themes/gruvbox.toml"
    [[ "$(readlink "$_rt/cfg/kitty/theme.local.conf")" == themes/gruvbox.conf ]] || fail "$_sh: kitty theme.local.conf must link to themes/gruvbox.conf"
    [[ ! -e $_st/contour && ! -e $_st/contour.yml ]] \
      || fail "$_sh: rice-theme gruvbox must leave contour on stowed gruvbox-dark (no state copy)"
    _bat="$(_rs 'printf %s "${BAT_THEME:-}"')"
    [[ $_bat == gruvbox-dark ]] || fail "$_sh: rice-theme gruvbox must set BAT_THEME=gruvbox-dark (got $_bat)"
    grep -q 'gsettings set org.gnome.desktop.interface accent-color yellow' "$RICE_LOG" \
      || fail "$_sh: rice-theme gruvbox must set GNOME accent yellow: $(cat "$RICE_LOG")"
    grep -q 'gsettings set org.gnome.TextEditor style-scheme gruvbox-dark' "$RICE_LOG" \
      || fail "$_sh: rice-theme gruvbox must set TextEditor gruvbox-dark"
    : >"$RICE_LOG"; _rs 'htop'
    grep -q "htop HTOPRC=$_st/htoprc" "$RICE_LOG" \
      || fail "$_sh: htop must use state HTOPRC under gruvbox: $(cat "$RICE_LOG")"
    grep -qx 'color_scheme=5' "$_st/htoprc" || fail "$_sh: htop gruvbox must use Black Night (5)"
    : >"$RICE_LOG"; _rs 'btop'
    grep -qx "btop -c $_st/btop.conf --themes-dir $_rt/cfg/btop/themes" "$RICE_LOG" || fail "$_sh: btop must use the override: $(cat "$RICE_LOG")"
    : >"$RICE_LOG"; _rs 'btop -p 1'
    grep -qx "btop -c $_st/btop.conf --themes-dir $_rt/cfg/btop/themes -p 1" "$RICE_LOG" || fail "$_sh: btop with non-config flags must keep override: $(cat "$RICE_LOG")"
    : >"$RICE_LOG"; _rs 'btop -c custom.conf'
    grep -qx 'btop -c custom.conf' "$RICE_LOG" || fail "$_sh: btop -c must pass through without override"
    grep -qx 'color_theme = "gruvbox_dark"' "$_st/btop.conf" || fail "$_sh: btop override missed color_theme"
    _tracked_unchanged || fail "$_sh: rice-theme modified a tracked config"
    # Not frozen: later edits to the stowed files reach the next shell / btop run.
    echo '# repo-update-marker' >>"$_rt/cfg/starship.toml"
    echo '# repo-update-marker' >>"$_rt/cfg/btop/btop.conf"
    _rs 'btop'
    grep -qx '# repo-update-marker' "$_st/starship.toml" || fail "$_sh: a new shell must rebuild the starship override from the repo file"
    grep -qx '# repo-update-marker' "$_st/btop.conf" || fail "$_sh: btop must rebuild its override from the repo file"
    cp "$ROOT/stow/starship/.config/starship.toml" "$_rt/cfg/"
    cp "$ROOT/stow/btop/.config/btop/btop.conf" "$_rt/cfg/btop/"
    # A tampered name is ignored (it would reach sed).
    printf "x'/;e id;#\n" >"$_st/starship"
    _sc="$(_rs 'printf %s "${STARSHIP_CONFIG:-}"')"
    [[ -z $_sc ]] || fail "$_sh: an invalid saved palette must be ignored (got $_sc)"
    # Stale palette / theme names must be dropped (files do not exist).
    printf 'nonexistent_theme\n' >"$_st/starship"
    printf 'nonexistent_theme\n' >"$_st/btop"
    printf 'nonexistent-theme\n' >"$_st/fastfetch"
    _sc="$(_rs 'printf %s "${STARSHIP_CONFIG:-}"')"
    [[ -z $_sc ]] || fail "$_sh: stale starship state must be ignored (got $_sc)"
    [[ ! -e $_st/starship ]] || fail "$_sh: stale starship state file must be removed"
    : >"$RICE_LOG"; _rs 'btop'
    grep -qx 'btop ' "$RICE_LOG" || fail "$_sh: stale btop state must fall back to repo config: $(cat "$RICE_LOG")"
    [[ ! -e $_st/btop ]] || fail "$_sh: stale btop state file must be removed"
    : >"$RICE_LOG"; _rs 'ff'
    grep -qx 'fastfetch ' "$RICE_LOG" || fail "$_sh: stale fastfetch state must fall back: $(cat "$RICE_LOG")"
    [[ ! -e $_st/fastfetch ]] || fail "$_sh: stale fastfetch state file must be removed"
    # Broken theme.local.* links to missing themes must be removed at shell start.
    ln -sfn themes/nonexistent.conf "$_rt/cfg/ghostty/theme.local.conf"
    ln -sfn themes/nonexistent.toml "$_rt/cfg/alacritty/theme.local.toml"
    ln -sfn themes/nonexistent.conf "$_rt/cfg/kitty/theme.local.conf"
    _rs ':'
    [[ ! -e $_rt/cfg/ghostty/theme.local.conf && ! -L $_rt/cfg/ghostty/theme.local.conf ]] \
      || fail "$_sh: dangling ghostty theme.local.conf must be removed"
    [[ ! -e $_rt/cfg/alacritty/theme.local.toml && ! -L $_rt/cfg/alacritty/theme.local.toml ]] \
      || fail "$_sh: dangling alacritty theme.local.toml must be removed"
    [[ ! -L $_rt/cfg/kitty/theme.local.conf && -f $_rt/cfg/kitty/theme.local.conf ]] \
      || fail "$_sh: dangling kitty theme.local.conf must become a stub file"
    : >"$RICE_LOG"
    _rs 'rice-theme secops >/dev/null'
    grep -qx "palette = 'secops'" "$_st/starship.toml" || fail "$_sh: rice-theme secops missed starship"
    [[ "$(cat "$_st/nvim")" == rice_secops ]] || fail "$_sh: rice-theme secops must save nvim colorscheme"
    [[ "$(readlink "$_rt/cfg/kitty/theme.local.conf")" == themes/secops.conf ]] \
      || fail "$_sh: kitty theme.local.conf must link to themes/secops.conf"
    [[ "$(cat "$_st/contour")" == secops ]] || fail "$_sh: rice-theme secops must save contour scheme"
    grep -qE '^[[:space:]]*colors: secops$' "$_st/contour.yml" \
      || fail "$_sh: contour.yml override must set colors: secops"
    grep -q 'accent-color teal' "$RICE_LOG" \
      || fail "$_sh: rice-theme secops must set GNOME accent teal: $(cat "$RICE_LOG")"
    grep -q 'style-scheme secops-dark' "$RICE_LOG" \
      || fail "$_sh: rice-theme secops must set TextEditor secops-dark"
    _bat="$(_rs 'printf %s "${BAT_THEME:-}"')"
    [[ $_bat == Nord ]] || fail "$_sh: rice-theme secops must set BAT_THEME=Nord (got $_bat)"
    : >"$RICE_LOG"; _rs 'htop'
    grep -qx 'color_scheme=7' "$_st/htoprc" || fail "$_sh: htop secops must use Nord (7)"
    : >"$RICE_LOG"; _rs 'contour'
    grep -qx "contour config $_st/contour.yml" "$RICE_LOG" \
      || fail "$_sh: contour wrapper must pass state config: $(cat "$RICE_LOG")"
    : >"$RICE_LOG"; _rs 'contour version'
    grep -qx 'contour version' "$RICE_LOG" \
      || fail "$_sh: contour version must pass through without config inject: $(cat "$RICE_LOG")"
    : >"$RICE_LOG"; _rs 'contour config /tmp/x.yml'
    grep -qx 'contour config /tmp/x.yml' "$RICE_LOG" \
      || fail "$_sh: explicit contour config must pass through: $(cat "$RICE_LOG")"
    # reset: every override gone, repo defaults back, STARSHIP_CONFIG cleared; kitty stub restored
    : >"$RICE_LOG"
    _sc="$(_rs 'rice-theme reset >/dev/null; printf %s "${STARSHIP_CONFIG:-}"')"
    [[ -z $_sc ]] || fail "$_sh: rice-theme reset must clear STARSHIP_CONFIG"
    [[ -z "$(ls -A "$_st")" ]] || fail "$_sh: rice-theme reset left state: $(ls -A "$_st")"
    [[ ! -e $_rt/cfg/ghostty/theme.local.conf && ! -L $_rt/cfg/ghostty/theme.local.conf \
      && ! -L $_rt/cfg/alacritty/theme.local.toml ]] \
      || fail "$_sh: rice-theme reset must remove ghostty/alacritty theme.local links"
    [[ ! -L $_rt/cfg/kitty/theme.local.conf && -f $_rt/cfg/kitty/theme.local.conf ]] \
      || fail "$_sh: rice-theme reset must restore kitty theme.local.conf stub"
    grep -q 'accent-color blue' "$RICE_LOG" \
      || fail "$_sh: rice-theme reset must restore GNOME accent blue"
    grep -q 'style-scheme gruvbox-dark' "$RICE_LOG" \
      || fail "$_sh: rice-theme reset must restore TextEditor gruvbox-dark"
    _tracked_unchanged || fail "$_sh: rice-theme reset modified a tracked config"
    ! _rs 'rice-theme ../bad >/dev/null 2>&1' || fail "$_sh: rice-theme must reject invalid theme names"
    ! XDG_CONFIG_HOME="$_rt/empty" XDG_STATE_HOME="$_rt/state" "$_sh" -c 'source "$1"; rice-theme gruvbox >/dev/null 2>&1' _ "$ROOT/stow/zsh/.shell-functions" \
      || fail "$_sh: rice-theme must fail when no configs exist"
  done
)
unset -v _bt _bf _gt

echo "PASS: slice2-labs.test.sh"
