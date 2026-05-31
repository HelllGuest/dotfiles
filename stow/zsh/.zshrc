# .zshrc
source ~/.shell-exports
source ~/.shell-aliases
source ~/.shell-functions
source ~/.zsh-plugins

# Source secrets if they exist
[ -f ~/.config/secrets/env ] && source ~/.config/secrets/env

# Starship prompt
eval "$(starship init zsh)"
