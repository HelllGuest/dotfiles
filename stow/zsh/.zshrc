# .zshrc
source ~/.zsh-exports
source ~/.zsh-aliases
source ~/.zsh-functions
source ~/.zsh-plugins

# Source secrets if they exist
[ -f ~/.config/secrets/env ] && source ~/.config/secrets/env

# Starship prompt
eval "$(starship init zsh)"
