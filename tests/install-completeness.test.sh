#!/usr/bin/env bash
# install.sh and its installers must not skip silently: failures are recorded,
# AUR/flatpak installers retry per package and exit non-zero on anything
# missing, and check.sh flags missing packages, empty dock slots and shortcuts.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
fail() { echo "FAIL: $*" >&2; exit 1; }
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT

# --- install.sh: no quiet "skipped" fallbacks -------------------------------
code="$(sed -e 's/#.*//' "$ROOT/install.sh")"
if grep -nE '\|\|[[:space:]]*(echo|true)' <<<"$code"; then
  fail "install.sh swallows a step failure (use run_step / fail_step)"
fi
if grep -nE 'echo "Skipping [^"]*\((npm|npx|node|podman|pacman)' <<<"$code"; then
  fail "install.sh skips a step for a missing pacman.txt prerequisite (use need_cmd)"
fi
grep -q 'pacman -Syu --needed --noconfirm -- "\${pkgs\[@\]}"' "$ROOT/install.sh" \
  || fail "install.sh must install pacman.txt with -Syu (stale sync db aborts the batch)"
grep -q 'sudo -n -v' "$ROOT/install.sh" || fail "install.sh must keep sudo alive"

# run_step / need_cmd record failures and continue.
helpers="$(awk '/^INSTALL_FAILED=0$/{f=1} f; f&&/^echo "Starting installation..."$/{exit}' "$ROOT/install.sh")"
out="$(bash -c "$helpers"'
run_step "Demo" false
run_step "Ok" true
need_cmd definitely-not-a-command-xyz "Demo tool" || true
printf "%s|" "$INSTALL_FAILED" "${INSTALL_FAIL_REASONS[@]}"' 2>/dev/null | tail -1)"
[[ $out == "1|Demo failed — re-run: false|Demo tool not installed: 'definitely-not-a-command-xyz' missing (packages/pacman.txt install failed?)|" ]] \
  || fail "run_step/need_cmd must record failures: $out"

# --- stubs --------------------------------------------------------------------
mkdir -p "$T/bin" "$T/repo/provision/scripts" "$T/repo/provision/lib" "$T/repo/packages"
cp "$ROOT/provision/scripts/install-aur.sh" "$ROOT/provision/scripts/install-flatpaks.sh" "$T/repo/provision/scripts/"
cp "$ROOT/provision/lib/pkg-lists.sh" "$T/repo/provision/lib/"
# pacman: installed set lives in $T/installed.
cat >"$T/bin/pacman" <<EOF
#!/bin/sh
[ "\$1" = -Q ] && grep -qx "\$2" "$T/installed"
EOF
# yay: batch always fails; single install succeeds unless the name is "broken".
cat >"$T/bin/yay" <<EOF
#!/bin/sh
echo "\$*" >>"$T/yay.log"
shift 4
[ "\$#" -eq 1 ] || exit 1
[ "\$1" = broken ] && exit 1
echo "\$1" >>"$T/installed"
EOF
printf '#!/bin/sh\n"$@"\n' >"$T/bin/sudo"
chmod +x "$T/bin/"*
# Minimal PATH: real yay/paru/flatpak/sudo must never be reachable.
mkdir -p "$T/core"
for c in bash sh sed grep cat tr dirname env mktemp rm; do
  ln -s "$(command -v "$c")" "$T/core/$c"
done
SP="$T/bin:$T/core"

# --- install-aur.sh -----------------------------------------------------------
printf '%s\n' '# comment' 'forgit  # inline' 'blesh-git' >"$T/repo/packages/aur.txt"
: >"$T/installed"
PATH="$SP" bash "$T/repo/provision/scripts/install-aur.sh" >"$T/out" 2>&1 \
  || fail "install-aur.sh must succeed when per-package retry installs all: $(cat "$T/out")"
grep -q -- '--sudoloop' "$T/yay.log" || fail "AUR helper must run with --sudoloop"
grep -qx forgit "$T/installed" && grep -qx blesh-git "$T/installed" \
  || fail "per-package retry must install every AUR entry (inline comment stripped)"
printf '%s\n' forgit broken >"$T/repo/packages/aur.txt"
if PATH="$SP" bash "$T/repo/provision/scripts/install-aur.sh" >"$T/out" 2>&1; then
  fail "install-aur.sh must exit 1 when a package stays missing"
fi
grep -q '✗ AUR packages not installed: broken' "$T/out" || fail "must name the missing AUR package: $(cat "$T/out")"
rm "$T/bin/yay"
if PATH="$SP" bash "$T/repo/provision/scripts/install-aur.sh" >"$T/out" 2>&1; then
  fail "install-aur.sh must exit 1 without an AUR helper"
fi

# --- install-flatpaks.sh --------------------------------------------------------
printf '%s\n' '# c' 'org.a.App' 'org.b.Broken' 'org.c.User' >"$T/repo/packages/flatpak.txt"
echo org.c.User >"$T/fpuser"   # already installed --user by the user
cat >"$T/bin/flatpak" <<EOF
#!/bin/sh
case "\$1" in
  remote-add) exit 0 ;;
  install) last=""; for a; do last="\$a"; done
           [ "\$#" -eq 6 ] || exit 1
           [ "\$last" = org.b.Broken ] && exit 1
           echo "\$last" >>"$T/fp" ;;
  list) case " \$* " in
          *" --user "*) cat "$T/fpuser" ;;
          *" --system "*) cat "$T/fp" 2>/dev/null ;;
          *) cat "$T/fp" "$T/fpuser" 2>/dev/null ;;
        esac ;;
esac
EOF
chmod +x "$T/bin/flatpak"
if PATH="$SP" bash "$T/repo/provision/scripts/install-flatpaks.sh" >"$T/out" 2>&1; then
  fail "install-flatpaks.sh must exit 1 when an app stays missing"
fi
grep -qx org.a.App "$T/fp" || fail "per-app retry must install the good app"
grep -q '✗ flatpaks not installed: org.b.Broken$' "$T/out" || fail "must name only the missing flatpak: $(cat "$T/out")"
! grep -qx org.c.User "$T/fp" || fail "an app installed --user must not get a second --system copy"

# --- dock / shortcut coverage in the lists --------------------------------------
list() { sed -e 's/#.*//' -e 's/[[:space:]]//g' -e '/^$/d' "$ROOT/packages/$1"; }
for p in extension-manager gnome-tweaks gnome-characters nautilus gnome-text-editor wl-clipboard; do
  list pacman.txt | grep -qx "$p" || fail "pacman.txt must include $p"
done
list flatpak.txt | grep -qx com.vixalien.sticky || fail "flatpak.txt must include Sticky (dock favorite)"

# check.sh section exists and uses check_fail (install.sh fails on it).
block="$(awk '/^echo "--- Install completeness ---"$/{f=1} f&&/^echo "--- AUR list ---"$/{exit} f' "$ROOT/scripts/check.sh" "$ROOT"/scripts/check.d/*.sh)"
for want in 'pacman.txt packages' 'aur.txt packages' 'flatpaks not installed' 'dock favorites with no installed app' 'runs nothing' 'GNOME extensions not installed'; do
  grep -q "$want" <<<"$block" || fail "check.sh completeness must cover: $want"
done


# --- install.sh: login shell, atuin import, kernel upgrade -------------------
blk() { awk -v s="$1" -v e="$2" 'index($0,s)==1{f=1} f&&index($0,e)==1{exit} f' "$ROOT/install.sh"; }
shell_blk="$(blk '# 2.0 Login shell' '# 2.1 Bootstrap')"
[[ -n $shell_blk ]] || fail "install.sh login-shell step not found"
mkdir -p "$T/sh/bin" "$T/sh/etc"
for c in cut readlink mkdir; do [[ -e $T/core/$c ]] || ln -s "$(command -v "$c")" "$T/core/$c"; done
cat >"$T/sh/bin/getent" <<EOF
#!/bin/sh
echo "u:x:1000:1000::/home/u:\$LOGIN_SHELL"
EOF
printf '#!/bin/sh\necho "$*" >>"%s/sh/usermod.log"\n' "$T" >"$T/sh/bin/usermod"
printf '#!/bin/sh\n"$@"\n' >"$T/sh/bin/sudo"
printf '#!/bin/sh\n' >"$T/sh/bin/zsh"
chmod +x "$T/sh/bin/"*
run_shell_blk() {  # LOGIN_SHELL, /etc/shells content
  printf '%s\n' "$2" >"$T/sh/etc/shells"
  LOGIN_SHELL="$1" USER=u PATH="$T/sh/bin:$T/core" bash -c "$helpers
${shell_blk//\/etc\/shells/$T/sh/etc/shells}
echo FAILED=\$INSTALL_FAILED" 2>&1
}
out="$(run_shell_blk /bin/bash "$T/sh/bin/zsh")"
grep -q -- "-s $T/sh/bin/zsh u" "$T/sh/usermod.log" 2>/dev/null && grep -qx FAILED=0 <<<"$out" \
  || fail "bash login shell must be switched to zsh: $out"
rm -f "$T/sh/usermod.log"
out="$(run_shell_blk "$T/sh/bin/zsh" "$T/sh/bin/zsh")"
[[ ! -e $T/sh/usermod.log ]] && grep -qx FAILED=0 <<<"$out" || fail "zsh login shell must be left alone: $out"
out="$(run_shell_blk /bin/bash /bin/bash)"
grep -qx FAILED=1 <<<"$out" || fail "zsh missing from /etc/shells must be a recorded failure: $out"

atuin_blk="$(blk '# The rc files keep history under XDG_STATE_HOME' '# 2.3 Materialize zram')"
[[ -n $atuin_blk ]] || fail "install.sh atuin step not found"
printf '#!/bin/sh\necho "HISTFILE=$HISTFILE $*" >>"%s/sh/atuin.log"\n' "$T" >"$T/sh/bin/atuin"
chmod +x "$T/sh/bin/atuin"
out="$(XDG_STATE_HOME="$T/state" PATH="$T/sh/bin:$T/core" bash -c "$helpers
$atuin_blk
echo FAILED=\$INSTALL_FAILED" 2>&1)"
grep -qx FAILED=0 <<<"$out" && [[ ! -e $T/sh/atuin.log ]] && grep -q 'no shell history yet' <<<"$out" \
  || fail "fresh install without history must not fail or call atuin: $out"
mkdir -p "$T/state/zsh"; echo ': 1:0;ls' >"$T/state/zsh/history"
out="$(XDG_STATE_HOME="$T/state" XDG_DATA_HOME="$T/data" PATH="$T/sh/bin:$T/core" bash -c "$helpers
$atuin_blk
echo FAILED=\$INSTALL_FAILED" 2>&1)"
grep -qx "HISTFILE=$T/state/zsh/history import zsh" "$T/sh/atuin.log" \
  || fail "atuin must import the XDG zsh history via HISTFILE: $(cat "$T/sh/atuin.log" 2>/dev/null)"
out="$(XDG_STATE_HOME="$T/state" XDG_DATA_HOME="$T/data" PATH="$T/sh/bin:$T/core" bash -c "$helpers
$atuin_blk
echo FAILED=\$INSTALL_FAILED" 2>&1)"
[[ $(grep -c 'import zsh' "$T/sh/atuin.log") -eq 1 ]] && grep -q 'already imported' <<<"$out" \
  || fail "re-running install.sh must not re-import (atuin duplicates entries): $(cat "$T/sh/atuin.log")"
grep -q '/usr/lib/modules/$(uname -r)' "$ROOT/install.sh" || fail "install.sh must detect a kernel upgraded mid-run"
grep -q 'need_cmd npm "OpenCode/Kimi" "$NODE_SRC"' "$ROOT/install.sh" || fail "npm comes from fnm, not pacman.txt (need_cmd hint)"

# --- check.sh completeness: behaviour with stubs ------------------------------
C="$T/chk"
mkdir -p "$C/bin" "$C/repo/packages" "$C/repo/desktop/gnome" "$C/repo/desktop/scripts" "$C/repo/provision/lib" "$C/home/.local/share/applications" \
  "$C/home/.local/share/gnome-shell/extensions/good@ext"
cp "$ROOT/provision/lib/pkg-lists.sh" "$ROOT/provision/lib/dmi.sh" "$C/repo/provision/lib/"
cp "$ROOT/desktop/scripts/theme-setup.sh" "$C/repo/desktop/scripts/"
printf '%s\n' present missing-pkg >"$C/repo/packages/pacman.txt"
printf '%s\n' aur-present >"$C/repo/packages/aur.txt"
printf '%s\n' org.ok.App org.gone.App >"$C/repo/packages/flatpak.txt"
printf '%s\n' good@ext gone@ext >"$C/repo/desktop/gnome/extensions.txt"
: >"$C/home/.local/share/applications/ok.desktop"
printf '%s\n' present aur-present >"$C/installed"
cat >"$C/bin/pacman" <<EOF
#!/bin/sh
[ "\$1" = -Q ] && grep -qx "\$2" "$C/installed"
EOF
printf '#!/bin/sh\n[ "$1" = list ] && echo org.ok.App\n' >"$C/bin/flatpak"
cat >"$C/bin/gsettings" <<'EOF'
#!/bin/sh
case "$*" in
  list-schemas) echo org.gnome.shell ;;
  "get org.gnome.shell favorite-apps") echo "['ok.desktop', 'gone.desktop']" ;;
  "get org.gnome.settings-daemon.plugins.media-keys custom-keybindings") echo "['/k0/', '/k1/', '/k2/']" ;;
  *custom-keybinding:/k0/\ command) echo "'present-cmd'" ;;
  *custom-keybinding:/k1/\ command) echo "'not-installed-cmd --flag'" ;;
  *custom-keybinding:/k2/\ command) echo "''" ;;
  *\ name) echo "'Shortcut'" ;;
esac
EOF
printf '#!/bin/sh\n' >"$C/bin/present-cmd"; printf '#!/bin/sh\n' >"$C/bin/wl-copy"
chmod +x "$C/bin/"*
cblock="$(awk '/^echo "--- Install completeness ---"$/{f=1} f&&/^echo "--- AUR list ---"$/{exit} f' "$ROOT/scripts/check.sh" "$ROOT"/scripts/check.d/*.sh)"
out="$(HOME="$C/home" XDG_CONFIG_HOME="$C/home/.config" XDG_CACHE_HOME="$C/home/.cache" XDG_DATA_HOME="$C/home/.local/share" DMI_SYSFS_ROOT="$C/none" PCI_SYSFS_ROOT="$C/none" \
  THEME_OLD_GDM_BIN="$C/none" THEME_OLD_GDM_HOOK="$C/none" \
  REPO_ROOT="$C/repo" PATH="$C/bin:$T/core" bash -c 'CHECK_FAILED=0; check_fail() { printf "✗ %s\n" "$*"; CHECK_FAILED=$((CHECK_FAILED+1)); }
'"$cblock"'
echo "FAILS=$CHECK_FAILED"' 2>&1)"
for want in '✗ pacman.txt packages not installed: missing-pkg' '✓ all aur.txt packages installed' \
  '✗ flatpaks not installed: org.gone.App' '✗ dock favorites with no installed app (empty icon): gone.desktop' \
  "✗ shortcut 'Shortcut': 'not-installed-cmd' not installed" "✗ shortcut 'Shortcut' runs nothing (empty command)" \
  '✗ GNOME extensions not installed: gone@ext'; do
  grep -qF -- "$want" <<<"$out" || fail "check.sh completeness must report: $want
$out"
done
grep -qx 'FAILS=6' <<<"$out" || fail "check.sh must count each problem as a failure: $out"
! grep -q "present-cmd' not installed" <<<"$out" || fail "installed shortcut command must pass"

# --- ai-rules/install.sh: missing jq is a failure, not a skip -----------------
K="$T/kit"
mkdir -p "$K/home/.config/Code/User" "$K/src"
cp -r "$ROOT/ai/rules" "$K/src/ai-rules"          # outside the git checkout: no agentsync on the repo
for c in mkdir cp mv ln find chmod rmdir basename head tail sort cmp git realpath touch awk wc cut install diff ls date; do
  [[ -e $T/core/$c ]] || ln -s "$(command -v "$c")" "$T/core/$c"
done
if HOME="$K/home" XDG_CONFIG_HOME="$K/home/.config" XDG_DATA_HOME="$K/home/.local/share" \
   PATH="$T/core" bash "$K/src/ai-rules/install.sh" "$K/target" >"$K/out" 2>&1; then
  fail "ai-rules/install.sh must exit 1 when jq is missing"
fi
grep -q "✗ jq missing: telemetry opt-outs not merged into $K/home/.config/Code/User/settings.json" "$K/out" \
  || fail "ai-rules must name the unmerged settings file: $(tail -5 "$K/out")"
grep -q 'Finished with .* failure' "$K/out" || fail "ai-rules must summarise failures"

# Every stow package is probed, not just a fixed symlink list (htoprc/.zshrc slipped past).
grep -q 'stow -d "$REPO_ROOT/stow" -n -R -t "$HOME"' "$ROOT/scripts/check.sh" "$ROOT"/scripts/check.d/*.sh \
  || fail "check.sh must dry-run stow for every package"
echo "PASS: install-completeness.test.sh"
