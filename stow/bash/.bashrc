# ~/.bashrc

[[ $- != *i* ]] && return

if [[ -f /usr/share/bash-completion/bash_completion ]]; then
    # shellcheck disable=SC1091
    source /usr/share/bash-completion/bash_completion
fi

export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
export XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
export XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"

# Privacy / hardening (parity with zsh). umask 077 = owner-only for files
# created in this interactive shell (same as zsh); not telemetry-specific.
umask 077
HISTFILE="${XDG_STATE_HOME}/bash/history"
HISTSIZE=100000
HISTFILESIZE=200000
HISTCONTROL=ignoreboth:erasedups
# Colon patterns. Prefer --flag / KEY= forms (avoid bare password/SECRET globs).
# Protects bash HISTFILE only; atuin has its own history_filter for the DB.
HISTIGNORE='ls:ll:la:cd:pwd:exit:clear:cl:q:history:*--password*:*--token*:*API_KEY=*:*_TOKEN=*:*PASSWORD=*:*SECRET=*:*Bearer *'
HISTTIMEFORMAT='%F %T  '
mkdir -p "$(dirname "$HISTFILE")"
[[ -f "$HISTFILE" ]] && chmod 600 "$HISTFILE" 2>/dev/null

shopt -s histappend cmdhist histreedit autocd cdspell dirspell
shopt -s checkwinsize globstar dotglob extglob nocaseglob checkjobs

PROMPT_COMMAND="${PROMPT_COMMAND:+$PROMPT_COMMAND;} history -a; history -n"

bind 'set completion-ignore-case on'
bind 'set completion-map-case on'
bind 'set show-all-if-ambiguous on'
bind 'set mark-symlinked-directories on'
bind 'set colored-completion-prefix on'
bind 'set colored-stats on'
bind 'set visible-stats on'
bind '"\e[A": history-search-backward'
bind '"\e[B": history-search-forward'
bind '"\e[1;5C": forward-word'
bind '"\e[1;5D": backward-word'

[ -f ~/.shell-exports ] && . ~/.shell-exports
[ -f ~/.shell-aliases ] && . ~/.shell-aliases
[ -f ~/.shell-functions ] && . ~/.shell-functions
[ -f ~/.shell-git ] && . ~/.shell-git

if command -v fzf >/dev/null 2>&1; then
    export FZF_DEFAULT_OPTS='
      --height=40%
      --layout=reverse
      --border=rounded
      --preview-window=right:55%:wrap
      --bind=ctrl-f:preview-page-down
      --bind=ctrl-b:preview-page-up
    '
    eval "$(fzf --bash)"
    export FZF_DEFAULT_COMMAND='fd --type f --hidden --follow --exclude .git'
    export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
    export FZF_ALT_C_COMMAND='fd --type d --hidden --follow --exclude .git'
fi

if command -v zoxide >/dev/null 2>&1; then
    eval "$(zoxide init bash --cmd cd)"
fi

if command -v atuin >/dev/null 2>&1; then
    eval "$(atuin init bash --disable-up-arrow)"
fi

if command -v direnv >/dev/null 2>&1; then
    eval "$(direnv hook bash)"
fi

if command -v fnm >/dev/null 2>&1; then
    eval "$(fnm env --use-on-cd --shell bash)"
fi

# Not for `bash -ic CMD` (desktop launchers): no line editor needed to run one command.
if [[ -f "${XDG_DATA_HOME}/blesh/ble.sh" && -z "${BASH_EXECUTION_STRING:-}" ]]; then
    # shellcheck disable=SC1091
    source "${XDG_DATA_HOME}/blesh/ble.sh" --attach=none
    bleopt editor=nvim 2>/dev/null || true
    ble-attach
fi

if command -v starship >/dev/null 2>&1; then
    eval "$(starship init bash)"
else
    PS1='[\u@\h \W]$ '
fi

_update_terminal_cwd() {
    local ret=$?   # keep the command's status for starship_precmd
    printf '\033]7;file://%s%s\a' "$HOSTNAME" "$PWD"
    return "$ret"
}
if [[ "$TERM" != "linux" && "$TERM" != "dumb" ]]; then
    PROMPT_COMMAND="_update_terminal_cwd${PROMPT_COMMAND:+; $PROMPT_COMMAND}"
fi

# Long-command desktop notification (core defined in ~/.shell-functions).
# Registered after atuin/ble.sh so we extend their bash-preexec arrays when
# present; otherwise fall back to a DEBUG trap + PROMPT_COMMAND.
if declare -F _cmd_notify_end >/dev/null 2>&1; then
    _cmd_notify_bp_pre()  { _cmd_notify_start "$1"; }
    _cmd_notify_bp_post() { _cmd_notify_end; }
    if [[ -n "${preexec_functions+x}" || -n "${precmd_functions+x}" ]]; then
        preexec_functions+=(_cmd_notify_bp_pre)
        precmd_functions+=(_cmd_notify_bp_post)
    else
        trap '_cmd_notify_start "$BASH_COMMAND"' DEBUG
        PROMPT_COMMAND="_cmd_notify_end${PROMPT_COMMAND:+; $PROMPT_COMMAND}"
    fi
fi

# VTE terminals (GNOME Console …): vte.sh reports command end + status, which
# Console turns into unfocused-window notifications. Loaded last and its
# precmd moved first, so it records the command's real $? (vte.sh appends it).
if [[ -n "${VTE_VERSION:-}" && -r /etc/profile.d/vte.sh ]]; then
    _pc=("${PROMPT_COMMAND[@]}")
    # shellcheck source=/dev/null
    . /etc/profile.d/vte.sh
    declare -F _vte_fix_postexec >/dev/null && _vte_fix_postexec
    if declare -F __vte_precmd >/dev/null; then
        PROMPT_COMMAND=(__vte_precmd "${_pc[@]}" __vte_osc7)
    fi
    unset _pc
fi

# Owner-only before loading (same as zsh: .zsh-plugins chmods it).
if [ -f ~/.config/secrets/env ]; then
    chmod 600 ~/.config/secrets/env 2>/dev/null
    # shellcheck disable=SC1090
    source ~/.config/secrets/env
fi
[[ -f ~/.bashrc.local ]] && source ~/.bashrc.local

# >>> headroom persistent env >>>
export HEADROOM_PORT="8787"
export HEADROOM_HOST="127.0.0.1"
export HEADROOM_MODE="token"
export HEADROOM_BACKEND="anthropic"
export HEADROOM_TELEMETRY="off"
export ANTHROPIC_BASE_URL="http://127.0.0.1:8787"
export ENABLE_TOOL_SEARCH="true"
export OPENAI_BASE_URL="http://127.0.0.1:8787/v1"
# <<< headroom persistent env <<<


# Added by Antigravity CLI installer
export PATH="/home/songoku/.local/bin:$PATH"
