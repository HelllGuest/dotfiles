#!/usr/bin/env bash
# lab-workdir.sh — the one place that decides what a lab may mount read-write
# as /work. Sourced by stow/zsh/.shell-functions (lab-* wrappers, bash + zsh)
# and scripts/lab-mcp.sh. Uses LAB_OUT / LAB_SAMPLES / DOTFILES_DIR from the
# caller's environment.
# shellcheck shell=bash

_lab_work_dir() {
    # /work is mounted read-write into the lab (malware samples included), so
    # never hand it the home tree, shell/app config, the dotfiles repo, or the
    # read-only samples dir. Ancestors count too: /home would expose $HOME.
    local cwd home out samples dotfiles reason=""
    cwd=$(pwd -P 2>/dev/null || pwd)
    home=$(readlink -f -- "${HOME:-/}" 2>/dev/null || echo "$HOME")
    out=$(readlink -f -- "$LAB_OUT" 2>/dev/null || echo "$LAB_OUT")
    samples=$(readlink -f -- "$LAB_SAMPLES" 2>/dev/null || echo "$LAB_SAMPLES")
    dotfiles=$(readlink -f -- "${DOTFILES_DIR:-$home/dotfiles}" 2>/dev/null || echo "$home/dotfiles")
    if [[ "$cwd" == "/" || "$cwd" == "$home" || "$home/" == "$cwd"/* ]]; then
        reason="home/root leak"
    elif [[ "$cwd/" == "$home"/.* ]]; then
        reason="hidden config dir under home"
    elif [[ "$cwd" == "$dotfiles" || "$cwd" == "$dotfiles"/* ]]; then
        reason="dotfiles repo"
    elif [[ -n $samples && ( "$cwd" == "$samples" || "$samples" == "$cwd"/* ) ]]; then
        reason="would make read-only samples writable"
    fi
    if [[ -n $reason ]]; then
        echo "lab: refusing to mount $cwd as /work ($reason). Using $out — cd into a project first." >&2
        [[ -d $out ]] || mkdir -p "$out"
        printf '%s' "$out"
        return
    fi
    printf '%s' "$cwd"
}
