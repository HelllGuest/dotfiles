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

HISTFILE="${XDG_STATE_HOME}/bash/history"
HISTSIZE=100000
HISTFILESIZE=200000
HISTCONTROL=ignoreboth:erasedups
HISTIGNORE='ls:ll:la:cd:pwd:exit:clear:cl:q:history'
HISTTIMEFORMAT='%F %T  '
mkdir -p "$(dirname "$HISTFILE")"

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

if [[ -f "${XDG_DATA_HOME}/blesh/ble.sh" ]]; then
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
    printf '\033]7;file://%s%s\a' "$HOSTNAME" "$PWD"
}
if [[ "$TERM" != "linux" && "$TERM" != "dumb" ]]; then
    PROMPT_COMMAND="_update_terminal_cwd${PROMPT_COMMAND:+; $PROMPT_COMMAND}"
fi

[ -f ~/.config/secrets/env ] && source ~/.config/secrets/env
[[ -f ~/.bashrc.local ]] && source ~/.bashrc.local
