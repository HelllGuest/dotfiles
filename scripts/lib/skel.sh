#!/usr/bin/env bash
# Shared cleanup of first-boot files that would block stowing into $HOME.

# useradd -m copies /etc/skel (.bashrc, ...) into a new home; those regular files
# make stow refuse the whole package. Drop only unmodified skel copies that a
# package in $1 (the stow dir) replaces; edited files still conflict and stay.
remove_unmodified_skel() {
  local stow_dir="$1" skel name target
  for skel in "${SKEL_DIR:-/etc/skel}"/.[!.]*; do
    name=${skel##*/}
    target="$HOME/$name"
    if [[ -f "$target" && ! -L "$target" ]] && cmp -s "$skel" "$target" \
      && compgen -G "$stow_dir/*/$name" >/dev/null; then
      echo "Removing unmodified /etc/skel copy $target (replaced by stow)."
      rm -f "$target"
    fi
  done
}

# t14s-arch-install (lib/80-chroot-setup.sh, starship step) writes
# ~/.config/starship.toml and a ~/.zshrc that starts with the starship init
# line, both regular files, so stow refuses the starship and zsh packages.
# Drop the starship.toml default only when unchanged. For ~/.zshrc, lines added
# after the seed (third-party installers append PATH exports) move to
# ~/.zshrc.local, which the stowed .zshrc sources; a ~/.zshrc that does not
# start with the seed line is the user's own and stays.
STAGE_A_STARSHIP_SEED=$'# t14s default — customize after first boot\nadd_newline = false'
# shellcheck disable=SC2016  # the literal line the installer writes
STAGE_A_ZSHRC_SEED='eval "$(starship init zsh)"'
remove_stage_a_seeds() {
  local stow_dir="$1" toml="$HOME/.config/starship.toml" rc="$HOME/.zshrc" first rest
  if [[ -f "$toml" && ! -L "$toml" && -f "$stow_dir/starship/.config/starship.toml" \
    && "$(<"$toml")" == "$STAGE_A_STARSHIP_SEED" ]]; then
    echo "Removing t14s-arch-install default $toml (replaced by stow)."
    rm -f "$toml"
  fi
  [[ -f "$rc" && ! -L "$rc" && -f "$stow_dir/zsh/.zshrc" ]] || return 0
  IFS= read -r first <"$rc" || true
  [[ "$first" == "$STAGE_A_ZSHRC_SEED" ]] || return 0
  rest="$(tail -n +2 "$rc" | grep -vxF "$STAGE_A_ZSHRC_SEED" | grep -v '^[[:space:]]*$' || true)"
  if [[ -n "$rest" ]]; then
    if ! printf '\n# Moved from the t14s-arch-install ~/.zshrc\n%s\n' "$rest" >>"$HOME/.zshrc.local"; then
      echo "Could not write ~/.zshrc.local; leaving $rc in place (stow will refuse zsh)." >&2
      return 1
    fi
    echo "Moved $(wc -l <<<"$rest") line(s) of $rc to ~/.zshrc.local."
  fi
  echo "Removing t14s-arch-install default $rc (replaced by stow)."
  rm -f "$rc"
}
