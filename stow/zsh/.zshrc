# .zshrc

[[ $- != *i* ]] && return

source ~/.shell-exports
source ~/.zsh-plugins
source ~/.shell-aliases
source ~/.shell-functions
source ~/.shell-git

[ -f ~/.config/secrets/env ] && source ~/.config/secrets/env

# fnm env: .zsh-plugins (once). Starship's full init is cached (_zsh_cache_eval).
_zsh_cache_eval starship starship init zsh --print-full-init

[[ -f ~/.zshrc.local ]] && source ~/.zshrc.local
if (( $+functions[_headroom_apply_env] )); then
    _headroom_apply_env
    unfunction _headroom_apply_env
fi
unset _HEADROOM_AUTO_ANTHROPIC _HEADROOM_AUTO_OPENAI

# Garmin Connect IQ SDK
if [[ -f "$HOME/.Garmin/ConnectIQ/current-sdk.cfg" ]]; then
    export CIQ_HOME="$(<"$HOME/.Garmin/ConnectIQ/current-sdk.cfg")"
    [[ -n "$CIQ_HOME" ]] && _prepend_path "$CIQ_HOME/bin"
fi

