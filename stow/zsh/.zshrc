# .zshrc

[[ $- != *i* ]] && return

source ~/.shell-exports
source ~/.zsh-plugins
source ~/.shell-aliases
source ~/.shell-functions
source ~/.shell-git

[ -f ~/.config/secrets/env ] && source ~/.config/secrets/env

if command -v fnm >/dev/null 2>&1; then
    eval "$(fnm env --use-on-cd --shell zsh)"
fi

if command -v starship >/dev/null 2>&1; then
    eval "$(starship init zsh)"
fi

[[ -f ~/.zshrc.local ]] && source ~/.zshrc.local
