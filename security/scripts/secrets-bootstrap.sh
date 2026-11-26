#!/usr/bin/env bash
# secrets-bootstrap.sh — encrypt/decrypt local machine overrides outside git.
#
# Stores secrets in ${XDG_CONFIG_HOME:-$HOME/.config}/dotfiles/:
#   local.env       plaintext overrides (mode 0600, never tracked in git)
#   local.env.age   encrypted archive (when age is installed)
#   local.env.enc   encrypted archive (OpenSSL AES-256-CBC PBKDF2 fallback)
#
# Usage: bash security/scripts/secrets-bootstrap.sh <init|lock|unlock|status>
# Env (optional):
#   DOTFILES_SECRETS_DIR   override directory (default: ~/.config/dotfiles)
#   DOTFILES_AGE_RECIPIENT age public key (otherwise passphrase mode)
#   DOTFILES_AGE_IDENTITY  age identity file for unlock
#   DOTFILES_SECRETS_PASS  passphrase for non-interactive openssl backend
set -euo pipefail
umask 077

SECRETS_DIR="${DOTFILES_SECRETS_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/dotfiles}"
PLAIN="$SECRETS_DIR/local.env"
AGE_FILE="$SECRETS_DIR/local.env.age"
ENC_FILE="$SECRETS_DIR/local.env.enc"

TMP_SECRETS=""
trap '[[ -n ${TMP_SECRETS:-} ]] && rm -f "$TMP_SECRETS"' EXIT

usage() { sed -n '2,14p' "$0"; }

check_perms() {
    local f=$1 perm
    [[ -f $f ]] || return 0
    perm="$(stat -c '%a' "$f" 2>/dev/null || stat -f '%Lp' "$f" 2>/dev/null || echo '')"
    if [[ $perm != 600 ]]; then
        echo "✗ $f has mode $perm (expected 600) — chmod 600 $f" >&2
        return 1
    fi
    return 0
}

do_lock() {
    [[ -f $PLAIN ]] || { echo "✗ missing $PLAIN — run: bash security/scripts/secrets-bootstrap.sh init" >&2; exit 1; }
    chmod 600 "$PLAIN"
    mkdir -p "$SECRETS_DIR"
    chmod 700 "$SECRETS_DIR"
    if command -v age >/dev/null 2>&1 && [[ -z ${DOTFILES_FORCE_OPENSSL:-} ]]; then
        TMP_SECRETS="$(mktemp "$SECRETS_DIR/.local.env.age.XXXXXX")"
        chmod 600 "$TMP_SECRETS"
        if [[ -n ${DOTFILES_AGE_RECIPIENT:-} ]]; then
            age -r "$DOTFILES_AGE_RECIPIENT" -o "$TMP_SECRETS" "$PLAIN"
        else
            age -p -o "$TMP_SECRETS" "$PLAIN"
        fi
        mv -f "$TMP_SECRETS" "$AGE_FILE"
        TMP_SECRETS=""
        chmod 600 "$AGE_FILE"
        echo "✓ encrypted $PLAIN -> $AGE_FILE (age)"
    elif command -v openssl >/dev/null 2>&1; then
        TMP_SECRETS="$(mktemp "$SECRETS_DIR/.local.env.enc.XXXXXX")"
        chmod 600 "$TMP_SECRETS"
        local pass_args=()
        if [[ -n ${DOTFILES_SECRETS_PASS:-} ]]; then
            pass_args=(-pass env:DOTFILES_SECRETS_PASS)
        fi
        openssl enc -aes-256-cbc -pbkdf2 -iter 600000 -salt \
            "${pass_args[@]}" -in "$PLAIN" -out "$TMP_SECRETS"
        mv -f "$TMP_SECRETS" "$ENC_FILE"
        TMP_SECRETS=""
        chmod 600 "$ENC_FILE"
        echo "✓ encrypted $PLAIN -> $ENC_FILE (openssl aes-256-cbc pbkdf2)"
    else
        echo "✗ need age or openssl to encrypt $PLAIN" >&2
        exit 1
    fi
}

do_init() {
    mkdir -p "$SECRETS_DIR"
    chmod 700 "$SECRETS_DIR"
    if [[ ! -f $PLAIN ]]; then
        cat >"$PLAIN" <<'EOF'
# Local machine overrides (mode 0600, never commit to git).
# Sourced automatically by desktop/scripts/git-setup.sh when present and 0600.
# GIT_USER_NAME="Your Name"
# GIT_USER_EMAIL="you@example.com"
# GIT_SIGNING_KEY=""
EOF
        chmod 600 "$PLAIN"
        echo "✓ created template $PLAIN (mode 0600)"
    else
        chmod 600 "$PLAIN"
        echo "○ keeping existing $PLAIN"
    fi
    do_lock
}

do_unlock() {
    local backend=""
    if [[ -f $AGE_FILE && -z ${DOTFILES_FORCE_OPENSSL:-} ]]; then
        command -v age >/dev/null 2>&1 || { echo "✗ $AGE_FILE requires age (sudo pacman -S age)" >&2; exit 1; }
        backend=age
    elif [[ -f $ENC_FILE ]]; then
        command -v openssl >/dev/null 2>&1 || { echo "✗ $ENC_FILE requires openssl" >&2; exit 1; }
        backend=openssl
    elif [[ -f $AGE_FILE ]]; then
        command -v age >/dev/null 2>&1 || { echo "✗ $AGE_FILE requires age (sudo pacman -S age)" >&2; exit 1; }
        backend=age
    else
        echo "✗ no encrypted archive found ($AGE_FILE or $ENC_FILE)" >&2
        exit 1
    fi
    mkdir -p "$SECRETS_DIR"
    chmod 700 "$SECRETS_DIR"
    TMP_SECRETS="$(mktemp "$SECRETS_DIR/.local.env.XXXXXX")"
    chmod 600 "$TMP_SECRETS"
    if [[ $backend == age ]]; then
        if [[ -n ${DOTFILES_AGE_IDENTITY:-} ]]; then
            age -d -i "$DOTFILES_AGE_IDENTITY" -o "$TMP_SECRETS" "$AGE_FILE"
        else
            age -d -o "$TMP_SECRETS" "$AGE_FILE"
        fi
    else
        local pass_args=()
        if [[ -n ${DOTFILES_SECRETS_PASS:-} ]]; then
            pass_args=(-pass env:DOTFILES_SECRETS_PASS)
        fi
        openssl enc -d -aes-256-cbc -pbkdf2 -iter 600000 \
            "${pass_args[@]}" -in "$ENC_FILE" -out "$TMP_SECRETS"
    fi
    mv -f "$TMP_SECRETS" "$PLAIN"
    TMP_SECRETS=""
    chmod 600 "$PLAIN"
    echo "✓ decrypted -> $PLAIN (mode 0600)"
}

do_status() {
    local rc=0
    if [[ -f $PLAIN ]]; then
        echo "✓ plaintext present: $PLAIN"
        check_perms "$PLAIN" || rc=1
    else
        echo "○ plaintext absent: $PLAIN"
    fi
    if [[ -f $AGE_FILE ]]; then
        echo "✓ age archive present: $AGE_FILE"
    elif [[ -f $ENC_FILE ]]; then
        echo "✓ openssl archive present: $ENC_FILE"
    else
        echo "○ no encrypted archive yet — bash security/scripts/secrets-bootstrap.sh init"
    fi
    return "$rc"
}

case ${1:-} in
    init) do_init ;;
    lock) do_lock ;;
    unlock) do_unlock ;;
    status) do_status ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
esac
