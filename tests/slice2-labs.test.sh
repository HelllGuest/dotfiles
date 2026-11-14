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

echo "PASS: slice2-labs.test.sh"
