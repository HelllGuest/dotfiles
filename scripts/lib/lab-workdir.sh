#!/usr/bin/env bash
# lab-workdir.sh — the one place that decides what a lab or agent container may
# mount read-write as /work. Sourced by stow/zsh/.shell-functions (lab-* wrappers,
# bash + zsh), scripts/lab-mcp.sh, and scripts/agent-run.sh. Uses LAB_OUT /
# LAB_SAMPLES / DOTFILES_DIR from the caller's environment.
# shellcheck shell=bash

_lab_path_refusal_reason() {
    local target=$1 home samples dotfiles
    home=$(readlink -f -- "${HOME:-/}" 2>/dev/null || echo "${HOME:-/}")
    samples=$(readlink -f -- "${LAB_SAMPLES:-/srv/lab/samples}" 2>/dev/null || echo "${LAB_SAMPLES:-/srv/lab/samples}")
    dotfiles=$(readlink -f -- "${DOTFILES_DIR:-$home/dotfiles}" 2>/dev/null || echo "$home/dotfiles")
    case "$target" in
        /|/etc|/etc/*|/usr|/usr/*|/var|/var/*|/boot|/boot/*|/root|/root/*|\
        /proc|/proc/*|/sys|/sys/*|/dev|/dev/*|/run|/run/*|/opt|/opt/*|/tmp|/srv/lab)
            printf '%s' "sensitive host/system path"
            return 0
            ;;
        # Session sockets in /tmp: X11/ICE (.X11-unix, .ICE-unix…), tmux (send-keys
        # runs commands on the host), ssh-agent, systemd PrivateTmp.
        /tmp/.*|/tmp/tmux-*|/tmp/ssh-*|/tmp/systemd-private-*)
            printf '%s' "session socket dir"
            return 0
            ;;
    esac
    # Any other live socket (agent, IDE, browser) would be reachable from /work:
    # the container runs as the same uid. Checked two levels deep.
    if [[ -d $target ]] && [[ -n "$(find "$target" -maxdepth 2 -type s -print -quit 2>/dev/null)" ]]; then
        printf '%s' "contains a live socket"
        return 0
    fi
    if [[ "$target" == "$home" || "$home/" == "$target"/* ]]; then
        printf '%s' "home/root leak"
    elif [[ "$target/" == "$home"/.* ]]; then
        printf '%s' "hidden config dir under home"
    elif [[ "$target" == "$dotfiles" || "$target" == "$dotfiles"/* ]]; then
        printf '%s' "dotfiles repo"
    elif [[ -n $samples && ( "$target" == "$samples" || "$target" == "$samples"/* || "$samples" == "$target"/* ) ]]; then
        printf '%s' "would make read-only samples writable"
    fi
}

_lab_work_dir() {
    # /work is mounted read-write into the lab (malware samples included), so
    # never hand it system/runtime socket dirs (/run/user, /var, /tmp and its
    # session socket dirs, or any dir holding a socket), the home
    # tree, shell/app config, the dotfiles repo, or the read-only samples dir.
    local cwd out reason
    cwd=$(pwd -P 2>/dev/null || pwd)
    out=$(readlink -f -- "${LAB_OUT:-/srv/lab/out}" 2>/dev/null || echo "${LAB_OUT:-/srv/lab/out}")
    reason=$(_lab_path_refusal_reason "$cwd")
    if [[ -n $reason ]]; then
        echo "lab: refusing to mount $cwd as /work ($reason). Using $out — cd into a project first." >&2
        [[ -d $out ]] || mkdir -p "$out"
        printf '%s' "$out"
        return
    fi
    printf '%s' "$cwd"
}
