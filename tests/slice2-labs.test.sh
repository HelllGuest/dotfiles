#!/usr/bin/env bash
# Slice 2: labs / AI / rice scaffolding smoke.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
fail() { echo "FAIL: $*" >&2; exit 1; }

for f in \
  "$ROOT/scripts/labs-setup.sh" \
  "$ROOT/scripts/ai-stack-setup.sh" \
  "$ROOT/scripts/rice-setup.sh" \
  "$ROOT/scripts/configure.sh" \
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

for f in "$ROOT/scripts/labs-setup.sh" "$ROOT/scripts/ai-stack-setup.sh" \
  "$ROOT/scripts/rice-setup.sh" "$ROOT/scripts/configure.sh" \
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
      "$_sh" -c 'source "$1"; _lab_work_dir' _ "$ROOT/scripts/lib/lab-workdir.sh" 2>/dev/null)"
    if [[ $_want == refuse ]]; then
      [[ $_got == "$_wd/home/u/labs/out" ]] || fail "$_sh: /work must refuse ${_case%%:*} (got $_got)"
    else
      [[ $_got == "$_dir" ]] || fail "$_sh: /work must allow ${_case%%:*} (got $_got)"
    fi
  done
  for _sysp in /run /run/user/1000 /var/lib /opt /tmp /srv/lab \
      /tmp/.X11-unix /tmp/.ICE-unix /tmp/tmux-1000 /tmp/tmux-1000/x /tmp/ssh-abc123 /tmp/systemd-private-x; do
    _r="$(HOME="$_wd/home/u" LAB_SAMPLES="$_wd/srv/lab/samples" \
      "$_sh" -c 'source "$1"; _lab_path_refusal_reason "$2"' _ "$ROOT/scripts/lib/lab-workdir.sh" "$_sysp")"
    [[ -n $_r ]] || fail "$_sh: _lab_path_refusal_reason must refuse $_sysp"
  done
done
rm -rf "$_wd"; unset -v _wd _sh _case _dir _want _got _sysp _r
# One implementation: lab-* wrappers and lab-mcp.sh both use the shared lib, and
# the wrappers fail closed when it is missing.
grep -q 'source "$(cd "$(dirname "$0")" && pwd)/lib/lab-workdir.sh"' "$ROOT/scripts/lab-mcp.sh" \
  || fail "lab-mcp.sh must use scripts/lib/lab-workdir.sh"
! grep -qE 'refusing|readlink -f -- "\$\{HOME' "$ROOT/scripts/lab-mcp.sh" || fail "lab-mcp.sh must not keep its own work-dir logic"
# Behaviour: lab-mcp's work_dir refuses $HOME under set -u even when LAB_SAMPLES is unset.
_wfn="$(grep -E '^work_dir\(\)' "$ROOT/scripts/lab-mcp.sh")"
_h="$(mktemp -d)"; _h="$(cd "$_h" && pwd -P)"; mkdir -p "$_h/out"
_got="$(cd "$_h" && env -u LAB_SAMPLES HOME="$_h" LAB_OUT="$_h/out" bash -euo pipefail -c \
  'source "$1"; '"$_wfn"'; work_dir' _ "$ROOT/scripts/lib/lab-workdir.sh" 2>/dev/null)"
[[ $_got == "$_h/out" ]] || fail "lab-mcp work_dir must refuse \$HOME without LAB_SAMPLES set (got $_got)"
rm -rf -- "$_h"; unset -v _wfn _h _got
grep -q 'scripts/lib/lab-workdir.sh"' "$ROOT/stow/zsh/.shell-functions" || fail ".shell-functions must source the shared work-dir lib"
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

grep -E 'bash[[:space:]].*install-caveman\.sh' "$ROOT/scripts/ai-stack-setup.sh" \
  && fail "ai-stack must not call install-caveman (full install.sh owns caveman; SETUP_AI = ponytail only)" || true
grep -q 'install-ponytail.sh' "$ROOT/scripts/ai-stack-setup.sh" \
  || fail "ai-stack must still install ponytail"
grep -E 'bash[[:space:]].*install-rea\.sh' "$ROOT/scripts/ai-stack-setup.sh" \
  && fail "ai-stack must not install REA on host (use lab-re)" || true
grep -E 'bash[[:space:]].*install-rea\.sh' "$ROOT/install.sh" \
  && fail "install.sh must not auto-run host install-rea (use lab-re)" || true
grep -q 'AI_STACK_EXTRAS_ONLY=1' "$ROOT/install.sh" \
  || fail "install.sh must run ai-stack extras (Continue / OpenCode / hr-proxy)"
grep -q 'AI_STACK_EXTRAS_ONLY' "$ROOT/scripts/ai-stack-setup.sh" \
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

grep -q 'SETUP_LABS' "$ROOT/scripts/configure.sh" || fail "configure must wire SETUP_LABS"
grep -q 'labs-setup.sh' "$ROOT/scripts/configure.sh" || fail "configure must call labs-setup"
grep -q 'ai-stack-setup.sh' "$ROOT/scripts/configure.sh" || fail "configure must call ai-stack"
grep -q 'rice-setup.sh' "$ROOT/scripts/configure.sh" || fail "configure must call rice-setup"
grep -q 'LABS_SLICE2' "$ROOT/scripts/configure.sh" \
  && fail "Slice 2 placeholders must be gone" || true

# P15 ollama checklist default + no swallowed module failures
grep -q 'OLLAMA_STATE=on' "$ROOT/scripts/configure.sh" \
  || fail "configure must set OLLAMA_STATE=on for P15"
grep -q 'is_p15 -eq 1' "$ROOT/scripts/configure.sh" \
  || fail "configure must gate OLLAMA_STATE on is_p15"
grep -q 'lab-malware' "$ROOT/scripts/configure.sh" \
  || fail "SETUP_FIREWALLD label must mention lab-malware"
# run_mod must not be paired with || true (would hide failures)
grep -E 'run_mod[[:space:]].*\|\|[[:space:]]*true' "$ROOT/scripts/configure.sh" \
  && fail "configure must not swallow run_mod failures with || true" || true
grep -q 'selected SETUP_FIREWALLD' "$ROOT/scripts/configure.sh" \
  || fail "configure must use selected() fail-fast module gates"
grep -q 'CONFIGURE_UI' "$ROOT/scripts/configure.sh" \
  || fail "configure must support CONFIGURE_UI override"
grep -q -- '--add-source=192.168.200.0/24' "$ROOT/scripts/lib/lab-malware-zone.sh" \
  || fail "lab-malware-zone must permanently add source 192.168.200.0/24"
grep -q '67/udp' "$ROOT/scripts/lib/lab-malware-zone.sh" \
  || fail "lab-malware zone must allow DHCP (67/udp) under DROP"
grep -E 'for spec in .*68/udp' "$ROOT/scripts/lib/lab-malware-zone.sh" \
  && fail "lab-malware zone must not open 68/udp (host is DHCP server)" || true
grep -qE "<dns[^>]*enable=['\"]no['\"]" "$ROOT/scripts/firewalld-lab-zones.sh" \
  || fail "virbr-malware XML must set dns enable=no (INetSim owns DNS)"
grep -q 'dhcp-option=6,192.168.200.1' "$ROOT/scripts/firewalld-lab-zones.sh" \
  || fail "virbr-malware DHCP must advertise DNS 192.168.200.1 (INetSim)"
grep -q 'sudo firewall-cmd --permanent --get-zones' "$ROOT/scripts/firewalld-lab-zones.sh" \
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

# Kitty host must not ship a forced Gruvbox theme file (stock colors)
[[ ! -f $ROOT/stow/kitty/.config/kitty/theme.conf ]] \
  || fail "kitty must stay stock (no theme.conf)"

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
grep -qE '^[^#]*dconf write.*/media-keys/' "$ROOT/scripts/gnome-console-setup.sh" \
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
    bash "$ROOT/scripts/ai-stack-setup.sh" >/dev/null
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
    bash "$ROOT/scripts/ai-stack-setup.sh" >/dev/null
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
  _udev_block="$(sed -n '/^# adb udev (host)/,/^unset _legacy_udev$/p' "$ROOT/scripts/labs-setup.sh")"
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
  _py_block="$(sed -n '/^  python3 - "\$obscura_bin" <<'\''PY'\''$/,/^PY$/p' "$ROOT/scripts/install-obscura.sh" | sed '1d;$d')"
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
  PATH="$_rt/bin:$PATH" HOME="$_rt/home" bash "$ROOT/scripts/rice-setup.sh" >/dev/null
  PATH="$_rt/bin:$PATH" HOME="$_rt/home" bash "$ROOT/scripts/rice-setup.sh" >/dev/null
  _n="$(grep -c 'CMD_NOTIFY_THRESHOLD' "$_rt/home/.zshrc.local")"
  [[ "$_n" -eq 1 ]] || fail "rice-setup.sh duplicated CMD_NOTIFY_THRESHOLD in .zshrc.local (count=$_n)"
)

# Behavioral: agent-run.sh shares lib/lab-workdir.sh; refuses sensitive system/socket
# paths (/run, /var/lib, /opt, whole /tmp, /tmp session socket dirs, dirs holding
# a socket), home/hidden/dotfiles/samples; allows project dir.
grep -q 'source "$(cd "$(dirname "$0")" && pwd)/lib/lab-workdir.sh"' "$ROOT/scripts/agent-run.sh" \
  || fail "agent-run.sh must source shared scripts/lib/lab-workdir.sh"
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
        bash "$ROOT/scripts/agent-run.sh" "$_bad" alpine:3.20 >/dev/null 2>&1; then
      fail "agent-run.sh must refuse $_bad"
    fi
  done
  _ok="$(PATH="$_ar/bin:$PATH" HOME="$_ar/home/u" LAB_SAMPLES="$_ar/srv/lab/samples" \
    bash "$ROOT/scripts/agent-run.sh" "$_ar/home/u/proj/a" alpine:3.20 2>&1)"
  [[ "$_ok" == "PODMAN_OK" ]] || fail "agent-run.sh must allow normal project dir (got: $_ok)"
)

# Behavioral: lab-android entrypoint stays stdout-silent when piped (MCP stdio safety).
_ae_out="$(bash "$ROOT/labs/lab-android/entrypoint.sh" printf '%s' '{"jsonrpc":"2.0"}' </dev/null)"
[[ "$_ae_out" == '{"jsonrpc":"2.0"}' ]] || fail "lab-android entrypoint polluted non-tty stdout: $_ae_out"
unset -v _ae_out

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

# Behavioral: multi-theme configs (starship, btop, ghostty, alacritty) parse cleanly
# and rice-theme switches all five tools in an isolated XDG_CONFIG_HOME.
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
        for pal in ("aura_glass", "gruvbox_dark", "secops"):
            assert pal in data["palettes"], f"starship missing palette {pal}"
PY
for _bt in aura_glass gruvbox_dark secops; do
  _bf="$ROOT/stow/btop/.config/btop/themes/${_bt}.theme"
  [[ -f "$_bf" ]] || fail "missing btop theme $_bt"
  grep -qE '^theme\[main_bg\]="#[0-9a-fA-F]{6}"$' "$_bf" \
    && grep -qE '^theme\[cpu_box\]="#[0-9a-fA-F]{6}"$' "$_bf" \
    || fail "btop theme $_bt missing required theme[main_bg/cpu_box] hex keys"
  ! grep -vE '^[[:space:]]*(#|$|theme\[[a-z0-9_]+\]="#[0-9a-fA-F]{6}")' "$_bf" | grep -q . \
    || fail "btop theme $_bt has malformed line"
done
for _gt in aura-glass gruvbox secops; do
  [[ -f "$ROOT/stow/ghostty/.config/ghostty/themes/${_gt}.conf" ]] || fail "missing ghostty theme $_gt"
done
# Active defaults must match one of their shipped templates (no silent drift).
_match_any() {
  local def=$1 f; shift
  for f in "$@"; do cmp -s "$def" "$f" && return 0; done
  return 1
}
_match_any "$ROOT/stow/fastfetch/.config/fastfetch/config.jsonc" \
  "$ROOT"/stow/fastfetch/.config/fastfetch/{aura-glass,gruvbox,minimal,secops}.jsonc \
  || fail "fastfetch/config.jsonc drifted from shipped presets"
_match_any "$ROOT/stow/ghostty/.config/ghostty/theme.conf" \
  "$ROOT"/stow/ghostty/.config/ghostty/themes/*.conf \
  || fail "ghostty/theme.conf drifted from shipped themes"
_match_any "$ROOT/stow/alacritty/.config/alacritty/theme.toml" \
  "$ROOT"/stow/alacritty/.config/alacritty/themes/*.toml \
  || fail "alacritty/theme.toml drifted from shipped themes"
unset -f _match_any
grep -qx 'import = \["theme.toml", "theme.local.toml"\]' "$ROOT/stow/alacritty/.config/alacritty/alacritty.toml" \
  || fail "alacritty.toml must import theme.toml and optional theme.local.toml"
grep -qx 'config-file = ?theme.local.conf' "$ROOT/stow/ghostty/.config/ghostty/config" \
  || fail "ghostty config must load optional theme.local.conf"
grep -qx 'save_config_on_exit = false' "$ROOT/stow/btop/.config/btop/btop.conf" \
  || fail "btop.conf must set save_config_on_exit = false (stowed file)"
(
  _rt="$(mktemp -d)"
  trap 'rm -rf "$_rt"' EXIT
  mkdir -p "$_rt/cfg/fastfetch" "$_rt/cfg/btop/themes" "$_rt/cfg/ghostty/themes" "$_rt/cfg/alacritty/themes" "$_rt/state" "$_rt/empty" "$_rt/bin"
  # Stubs log their arguments: the wrappers must pick the override config.
  for _c in fastfetch btop; do
    printf '#!/bin/sh\necho "%s $*" >>"$RICE_LOG"\n' "$_c" >"$_rt/bin/$_c"; chmod +x "$_rt/bin/$_c"
  done
  cp "$ROOT"/stow/fastfetch/.config/fastfetch/*.jsonc "$_rt/cfg/fastfetch/"
  cp "$ROOT/stow/btop/.config/btop/btop.conf" "$_rt/cfg/btop/"
  cp "$ROOT"/stow/btop/.config/btop/themes/*.theme "$_rt/cfg/btop/themes/"
  cp "$ROOT/stow/starship/.config/starship.toml" "$_rt/cfg/"
  cp "$ROOT/stow/ghostty/.config/ghostty/theme.conf" "$_rt/cfg/ghostty/"
  cp "$ROOT"/stow/ghostty/.config/ghostty/themes/*.conf "$_rt/cfg/ghostty/themes/"
  cp "$ROOT/stow/alacritty/.config/alacritty/theme.toml" "$_rt/cfg/alacritty/"
  cp "$ROOT"/stow/alacritty/.config/alacritty/themes/*.toml "$_rt/cfg/alacritty/themes/"
  export RICE_LOG="$_rt/log"
  _st="$_rt/state/dotfiles/theme"
  # _rs <commands>: run in a fresh shell that sourced .shell-functions (like a new terminal).
  _rs() {
    env -u STARSHIP_CONFIG XDG_CONFIG_HOME="$_rt/cfg" XDG_STATE_HOME="$_rt/state" PATH="$_rt/bin:$PATH" \
      "$_sh" -c 'source "$1"; '"$1" _ "$ROOT/stow/zsh/.shell-functions"
  }
  _tracked_unchanged() {
    cmp -s "$ROOT/stow/fastfetch/.config/fastfetch/config.jsonc" "$_rt/cfg/fastfetch/config.jsonc" \
      && cmp -s "$ROOT/stow/ghostty/.config/ghostty/theme.conf" "$_rt/cfg/ghostty/theme.conf" \
      && cmp -s "$ROOT/stow/alacritty/.config/alacritty/theme.toml" "$_rt/cfg/alacritty/theme.toml" \
      && cmp -s "$ROOT/stow/btop/.config/btop/btop.conf" "$_rt/cfg/btop/btop.conf" \
      && cmp -s "$ROOT/stow/starship/.config/starship.toml" "$_rt/cfg/starship.toml"
  }
  for _sh in bash zsh; do
    command -v "$_sh" >/dev/null || continue
    rm -rf "$_rt/state"; rm -f "$_rt/cfg/ghostty/theme.local.conf" "$_rt/cfg/alacritty/theme.local.toml"
    cp "$ROOT/stow/starship/.config/starship.toml" "$_rt/cfg/"
    cp "$ROOT/stow/btop/.config/btop/btop.conf" "$_rt/cfg/btop/"
    # ff-preset: list, use (saves a name, never touches config.jsonc), ff honours it, reset, traversal
    _fl="$(_rs 'ff-preset')"
    grep -qx aura-glass <<<"$_fl" && grep -qx gruvbox <<<"$_fl" && grep -qx minimal <<<"$_fl" && grep -qx secops <<<"$_fl" \
      || fail "$_sh: ff-preset list missing presets: $_fl"
    _rs 'ff-preset use minimal >/dev/null'
    [[ "$(cat "$_st/fastfetch")" == minimal ]] || fail "$_sh: ff-preset use must save the preset name"
    : >"$RICE_LOG"; _rs 'ff'
    grep -qx "fastfetch --config $_rt/cfg/fastfetch/minimal.jsonc" "$RICE_LOG" || fail "$_sh: ff must use the saved preset: $(cat "$RICE_LOG")"
    : >"$RICE_LOG"; _rs 'ff -c gruvbox'
    grep -qx 'fastfetch -c gruvbox' "$RICE_LOG" || fail "$_sh: ff with arguments must pass them through"
    _rs 'ff-preset reset >/dev/null'
    : >"$RICE_LOG"; _rs 'ff'
    grep -qx 'fastfetch ' "$RICE_LOG" || fail "$_sh: ff after reset must run the repo config.jsonc"
    ! _rs 'ff-preset ../bad >/dev/null 2>&1' || fail "$_sh: ff-preset must reject traversal"
    # rice-theme: names in state, links for ghostty/alacritty, starship active in this shell
    _sc="$(_rs 'rice-theme gruvbox >/dev/null; printf %s "${STARSHIP_CONFIG:-}"')"
    [[ $_sc == "$_st/starship.toml" ]] || fail "$_sh: rice-theme must point STARSHIP_CONFIG at the override (got $_sc)"
    grep -qx "palette = 'gruvbox_dark'" "$_st/starship.toml" || fail "$_sh: rice-theme gruvbox missed starship"
    [[ "$(cat "$_st/fastfetch")" == gruvbox && "$(cat "$_st/btop")" == gruvbox_dark ]] \
      || fail "$_sh: rice-theme gruvbox must save fastfetch/btop names"
    [[ "$(readlink "$_rt/cfg/ghostty/theme.local.conf")" == themes/gruvbox.conf ]] || fail "$_sh: ghostty theme.local.conf must link to themes/gruvbox.conf"
    [[ "$(readlink "$_rt/cfg/alacritty/theme.local.toml")" == themes/gruvbox.toml ]] || fail "$_sh: alacritty theme.local.toml must link to themes/gruvbox.toml"
    : >"$RICE_LOG"; _rs 'btop'
    grep -qx "btop -c $_st/btop.conf --themes-dir $_rt/cfg/btop/themes" "$RICE_LOG" || fail "$_sh: btop must use the override: $(cat "$RICE_LOG")"
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
    _rs 'rice-theme secops >/dev/null'
    grep -qx "palette = 'secops'" "$_st/starship.toml" || fail "$_sh: rice-theme secops missed starship"
    # reset: every override gone, repo defaults back, STARSHIP_CONFIG cleared
    _sc="$(_rs 'rice-theme reset >/dev/null; printf %s "${STARSHIP_CONFIG:-}"')"
    [[ -z $_sc ]] || fail "$_sh: rice-theme reset must clear STARSHIP_CONFIG"
    [[ -z "$(ls -A "$_st")" ]] || fail "$_sh: rice-theme reset left state: $(ls -A "$_st")"
    [[ ! -e $_rt/cfg/ghostty/theme.local.conf && ! -L $_rt/cfg/ghostty/theme.local.conf && ! -L $_rt/cfg/alacritty/theme.local.toml ]] \
      || fail "$_sh: rice-theme reset must remove the theme.local links"
    _tracked_unchanged || fail "$_sh: rice-theme reset modified a tracked config"
    ! _rs 'rice-theme ../bad >/dev/null 2>&1' || fail "$_sh: rice-theme must reject invalid theme names"
    ! XDG_CONFIG_HOME="$_rt/empty" XDG_STATE_HOME="$_rt/state" "$_sh" -c 'source "$1"; rice-theme gruvbox >/dev/null 2>&1' _ "$ROOT/stow/zsh/.shell-functions" \
      || fail "$_sh: rice-theme must fail when no configs exist"
  done
)
unset -v _bt _bf _gt

echo "PASS: slice2-labs.test.sh"
