# ~/.bashrc

# If not running interactively, don't do anything
[[ $- != *i* ]] && return

# 1. Enable bash completion
if [ -f /usr/share/bash-completion/bash_completion ]; then
    . /usr/share/bash-completion/bash_completion
fi

# 2. Modern Bash Settings
shopt -s autocd cdspell histappend cmdhist

# 3. Aliases
alias ls='ls --color=auto'
alias grep='grep --color=auto'
alias v='nvim'

# Load shared exports and functions if they exist
[ -f ~/.shell-exports ] && . ~/.shell-exports
[ -f ~/.shell-aliases ] && . ~/.shell-aliases
[ -f ~/.shell-functions ] && . ~/.shell-functions

# 4. Prompt
if command -v starship >/dev/null 2>&1; then
    eval "$(starship init bash)"
else
    PS1='[\u@\h \W]$ '
fi

# OSC 7: Tell the terminal about the current working directory
# This allows new tabs/windows to open in the same directory
_update_terminal_cwd() {
    printf "\033]7;file://%s%s\a" "$HOSTNAME" "$PWD"
}

if [[ "$TERM" != "linux" && "$TERM" != "dumb" ]]; then
    PROMPT_COMMAND="_update_terminal_cwd${PROMPT_COMMAND:+; $PROMPT_COMMAND}"
fi
