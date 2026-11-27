#!/usr/bin/env bash
# personal-backup.sh — encrypted backup/restore of personal machine state outside git.
#
# Reuses secrets-bootstrap.sh's age / OpenSSL AES-256-CBC PBKDF2 conventions:
#   DOTFILES_AGE_RECIPIENT  age public key (or interactive passphrase when unset)
#   DOTFILES_AGE_IDENTITY   age identity file for restore
#   DOTFILES_SECRETS_PASS   passphrase for non-interactive OpenSSL backend
#   DOTFILES_FORCE_OPENSSL  force OpenSSL backend even when age is installed
#
# Default items backed up (relative to $HOME, skipped if absent):
#   .ssh  .gnupg  .config/secrets  .config/dotfiles/local.env
#   .zshrc.local  .bashrc.local  .gitconfig.local
#
# Usage:
#   bash security/scripts/personal-backup.sh backup [OUT_FILE]
#   bash security/scripts/personal-backup.sh restore <ARCHIVE> [--dry-run] [--force]
#   bash security/scripts/personal-backup.sh verify <ARCHIVE>
set -euo pipefail
umask 077

DEFAULT_ITEMS=(
  .ssh
  .gnupg
  .config/secrets
  .config/dotfiles/local.env
  .zshrc.local
  .bashrc.local
  .gitconfig.local
)

TMP_DIR=""
cleanup() { [[ -n ${TMP_DIR:-} && -d $TMP_DIR ]] && rm -rf -- "$TMP_DIR"; }
trap cleanup EXIT

usage() { sed -n '2,18p' "$0"; }

choose_backend() {
  if command -v age >/dev/null 2>&1 && [[ -z ${DOTFILES_FORCE_OPENSSL:-} ]]; then
    printf 'age\n'
  elif command -v openssl >/dev/null 2>&1; then
    printf 'openssl\n'
  else
    echo "error: need 'age' or 'openssl'" >&2
    return 1
  fi
}

encrypt_file() {
  local backend=$1 src=$2 dst=$3
  if [[ $backend == age ]]; then
    if [[ -n ${DOTFILES_AGE_RECIPIENT:-} ]]; then
      age -r "$DOTFILES_AGE_RECIPIENT" -o "$dst" "$src"
    else
      age -p -o "$dst" "$src"
    fi
  else
    local pass_args=()
    [[ -n ${DOTFILES_SECRETS_PASS:-} ]] && pass_args=(-pass env:DOTFILES_SECRETS_PASS)
    openssl enc -aes-256-cbc -pbkdf2 -iter 600000 -salt "${pass_args[@]}" -in "$src" -out "$dst"
  fi
}

is_age_archive() {
  local archive=$1 hdr=""
  hdr="$(head -c 19 "$archive" 2>/dev/null | tr -d '\0' || true)"
  [[ $hdr == "age-encryption.org/" || $archive == *.age ]]
}

decrypt_file() {
  local archive=$1 dst=$2
  if is_age_archive "$archive"; then
    command -v age >/dev/null 2>&1 || { echo "error: age required to decrypt $archive" >&2; return 1; }
    if [[ -n ${DOTFILES_AGE_IDENTITY:-} ]]; then
      age -d -i "$DOTFILES_AGE_IDENTITY" -o "$dst" "$archive"
    else
      age -d -o "$dst" "$archive"
    fi
  else
    command -v openssl >/dev/null 2>&1 || { echo "error: openssl required to decrypt $archive" >&2; return 1; }
    local pass_args=()
    [[ -n ${DOTFILES_SECRETS_PASS:-} ]] && pass_args=(-pass env:DOTFILES_SECRETS_PASS)
    openssl enc -d -aes-256-cbc -pbkdf2 -iter 600000 "${pass_args[@]}" -in "$archive" -out "$dst"
  fi
}

# Validate archive entries: reject absolute paths, '..' segments, special devices,
# and symlinks/hardlinks resolving outside $HOME. Prints existing conflicting paths.
audit_tar_and_conflicts() {
  local tar_file=$1 home_dir=$2
  python3 - "$tar_file" "$home_dir" <<'PY'
import os, sys, tarfile
from pathlib import PurePosixPath

tar_path, home = sys.argv[1], os.path.realpath(sys.argv[2])
conflicts = []
with tarfile.open(tar_path, "r:*") as tf:
    for m in tf.getmembers():
        name = m.name
        p = PurePosixPath(name)
        if p.is_absolute() or ".." in p.parts:
            sys.stderr.write(f"error: refusing unsafe tar path: {name}\n")
            sys.exit(1)
        if not (m.isfile() or m.isdir() or m.issym() or m.islnk()):
            sys.stderr.write(f"error: refusing special tar entry: {name}\n")
            sys.exit(1)
        if m.issym() or m.islnk():
            target = m.linkname
            if os.path.isabs(target):
                sys.stderr.write(f"error: refusing absolute link target in tar: {name} -> {target}\n")
                sys.exit(1)
            base = os.path.dirname(os.path.normpath(os.path.join(home, name))) if m.issym() else home
            resolved = os.path.normpath(os.path.join(base, target))
            if resolved != home and not resolved.startswith(home + os.sep):
                sys.stderr.write(f"error: refusing link escaping HOME: {name} -> {target}\n")
                sys.exit(1)
        if not m.isdir() and os.path.lexists(os.path.join(home, name)):
            conflicts.append(name)
for c in conflicts:
    print(c)
PY
}

cmd_backup() {
  local out="${1:-}"
  local backend ext
  backend="$(choose_backend)"
  ext="tar.gz.enc"
  [[ $backend == age ]] && ext="tar.gz.age"

  local default_dir="${DOTFILES_BACKUP_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/backups}"
  if [[ -z $out ]]; then
    mkdir -p "$default_dir"
    chmod 700 "$default_dir"
    out="$default_dir/personal-$(hostname -s 2>/dev/null || echo host)-$(date +%Y%m%d-%H%M%S).${ext}"
  else
    mkdir -p "$(dirname "$out")"
  fi

  local present=() item
  local -a items=("${DEFAULT_ITEMS[@]}")
  if [[ -n ${DOTFILES_BACKUP_ITEMS:-} ]]; then
    read -r -a items <<<"$DOTFILES_BACKUP_ITEMS"
  fi
  for item in "${items[@]}"; do
    [[ $item == /* || $item =~ (^|/)\.\.(/|$) ]] && { echo "error: backup item must be relative to \$HOME: $item" >&2; exit 2; }
    [[ -e "$HOME/$item" ]] && present+=("$item")
  done
  if (( ${#present[@]} == 0 )); then
    echo "error: none of the configured personal items exist under $HOME" >&2
    exit 1
  fi

  TMP_DIR="$(mktemp -d)"
  chmod 700 "$TMP_DIR"
  local tar_tmp="$TMP_DIR/payload.tar.gz"
  local enc_tmp="$TMP_DIR/payload.enc"
  tar -C "$HOME" -czf "$tar_tmp" "${present[@]}"
  encrypt_file "$backend" "$tar_tmp" "$enc_tmp"
  chmod 600 "$enc_tmp"
  mv -f "$enc_tmp" "$out"
  chmod 600 "$out"
  echo "✓ backed up ${#present[@]} item(s) (${present[*]}) -> $out ($backend, mode 0600)"
}

cmd_verify() {
  local archive="${1:-}"
  [[ -n $archive && -f $archive ]] || { echo "error: missing archive '$archive'" >&2; exit 2; }
  TMP_DIR="$(mktemp -d)"
  chmod 700 "$TMP_DIR"
  local tar_tmp="$TMP_DIR/payload.tar.gz"
  decrypt_file "$archive" "$tar_tmp"
  tar -tzf "$tar_tmp"
  echo "✓ verified archive: $archive"
}

cmd_restore() {
  local archive="" dry_run=0 force=0
  while (($#)); do
    case $1 in
      -n|--dry-run) dry_run=1 ;;
      -f|--force) force=1 ;;
      -h|--help) usage; exit 0 ;;
      -*) echo "error: unknown restore option '$1'" >&2; exit 2 ;;
      *) [[ -z $archive ]] && archive=$1 || { echo "error: unexpected arg '$1'" >&2; exit 2; } ;;
    esac
    shift
  done
  [[ -n $archive && -f $archive ]] || { echo "error: missing archive '$archive'" >&2; exit 2; }

  TMP_DIR="$(mktemp -d)"
  chmod 700 "$TMP_DIR"
  local tar_tmp="$TMP_DIR/payload.tar.gz"
  decrypt_file "$archive" "$tar_tmp"

  local audit_out conflicts=()
  audit_out="$(audit_tar_and_conflicts "$tar_tmp" "$HOME")"
  if [[ -n $audit_out ]]; then
    mapfile -t conflicts <<<"$audit_out"
  fi

  if (( dry_run )); then
    echo "[dry-run] would restore into $HOME:"
    tar -tzf "$tar_tmp" | sed 's/^/  /'
    if (( ${#conflicts[@]} > 0 )); then
      echo "[dry-run] existing files (require --force): ${conflicts[*]}"
    fi
    return 0
  fi

  if (( ${#conflicts[@]} > 0 && ! force )); then
    echo "error: refusing to overwrite existing files without --force: ${conflicts[*]}" >&2
    exit 1
  fi

  tar -C "$HOME" --no-same-owner -xzf "$tar_tmp"
  [[ -d "$HOME/.ssh" ]] && chmod 700 "$HOME/.ssh"
  [[ -d "$HOME/.gnupg" ]] && chmod 700 "$HOME/.gnupg"
  [[ -d "$HOME/.config/secrets" ]] && chmod 700 "$HOME/.config/secrets"
  [[ -f "$HOME/.config/dotfiles/local.env" ]] && chmod 600 "$HOME/.config/dotfiles/local.env"
  echo "✓ restored personal backup into $HOME from $archive"
}

case ${1:-} in
  backup) shift; cmd_backup "$@" ;;
  restore) shift; cmd_restore "$@" ;;
  verify) shift; cmd_verify "$@" ;;
  -h|--help) usage; exit 0 ;;
  *) usage >&2; exit 2 ;;
esac
