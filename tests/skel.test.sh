#!/usr/bin/env bash
# First-boot files that block stow are cleared before stowing: unmodified
# /etc/skel copies and the t14s-arch-install starship.toml / ~/.zshrc seeds.
# shellcheck disable=SC2016  # single quotes hold literal shell lines
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
fail() { echo "FAIL: $*" >&2; exit 1; }

for f in install.sh stow-only.sh; do
  grep -q '^remove_stage_a_seeds "\$PWD/stow"' "$ROOT/$f" || fail "$f must call remove_stage_a_seeds"
done
# The seeds must match what the installer writes (checked when a checkout exists).
INST="${T14S_INSTALLER_DIR:-$HOME/t14s-arch-install}/lib/80-chroot-setup.sh"
if [[ -f $INST ]]; then
  if ! grep -qxF '# t14s default — customize after first boot' "$INST" \
    || ! grep -qF "'eval \"\$(starship init zsh)\"'" "$INST"; then
    fail "t14s-arch-install starship/.zshrc seed changed: update remove_stage_a_seeds"
  fi
fi

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
# shellcheck source=scripts/lib/skel.sh
source "$ROOT/scripts/lib/skel.sh"
STOW="$T/stow"
mkdir -p "$STOW/zsh" "$STOW/starship/.config"
: >"$STOW/zsh/.zshrc"; : >"$STOW/starship/.config/starship.toml"

seed_home() {
  HOME="$T/home"; rm -rf "$HOME"; mkdir -p "$HOME/.config"
  # Exactly what t14s-arch-install writes (tee heredoc / printf + tee -a).
  printf '%s\n' '# t14s default — customize after first boot' 'add_newline = false' >"$HOME/.config/starship.toml"
  printf '%s\n' 'eval "$(starship init zsh)"' >"$HOME/.zshrc"
}

# Pure seeds: both removed, no .zshrc.local created.
seed_home
remove_stage_a_seeds "$STOW" >/dev/null
[[ ! -e $HOME/.zshrc && ! -e $HOME/.config/starship.toml ]] || fail "seeds not removed"
[[ ! -e $HOME/.zshrc.local ]] || fail ".zshrc.local created with nothing to keep"

# Appended lines survive in .zshrc.local (as on the T14s: a PATH export).
seed_home
echo 'export PATH="$HOME/.local/bin:$PATH"' >>"$HOME/.zshrc"
remove_stage_a_seeds "$STOW" >/dev/null
[[ ! -e $HOME/.zshrc ]] || fail "seeded .zshrc with extra lines not removed"
grep -qxF 'export PATH="$HOME/.local/bin:$PATH"' "$HOME/.zshrc.local" || fail "appended line lost"
grep -qF 'starship init' "$HOME/.zshrc.local" && fail "seed line copied into .zshrc.local"

# Edited starship.toml and a user's own .zshrc are left alone.
seed_home
echo 'format = "$all"' >>"$HOME/.config/starship.toml"
printf '%s\n' 'source ~/.oh-my-zsh/oh-my-zsh.sh' 'eval "$(starship init zsh)"' >"$HOME/.zshrc"
remove_stage_a_seeds "$STOW" >/dev/null
[[ -f $HOME/.config/starship.toml && -f $HOME/.zshrc ]] || fail "user-edited files removed"

# Symlinks (already stowed) are never touched.
seed_home
rm "$HOME/.zshrc"; ln -s "$STOW/zsh/.zshrc" "$HOME/.zshrc"
remove_stage_a_seeds "$STOW" >/dev/null
[[ -L $HOME/.zshrc ]] || fail "stowed symlink removed"

# Packages absent from the stow dir: nothing removed.
seed_home
remove_stage_a_seeds "$T/empty" >/dev/null
[[ -f $HOME/.zshrc && -f $HOME/.config/starship.toml ]] || fail "removed without a replacing package"

# Unmodified /etc/skel copy removed, edited copy kept.
SKEL_DIR="$T/skel"; mkdir -p "$SKEL_DIR" "$STOW/bash"
echo 'skel' >"$SKEL_DIR/.bashrc"; : >"$STOW/bash/.bashrc"
seed_home; cp "$SKEL_DIR/.bashrc" "$HOME/.bashrc"
remove_unmodified_skel "$STOW" >/dev/null
[[ ! -e $HOME/.bashrc ]] || fail "unmodified skel copy not removed"
echo 'mine' >"$HOME/.bashrc"
remove_unmodified_skel "$STOW" >/dev/null
[[ -f $HOME/.bashrc ]] || fail "edited .bashrc removed"

echo "PASS: skel.test.sh"
