#!/usr/bin/env bash
# Shared /etc/skel cleanup before stowing into $HOME.

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
