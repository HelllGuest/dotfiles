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

# Garmin Connect IQ SDK
if [[ -f "$HOME/.Garmin/ConnectIQ/current-sdk.cfg" ]]; then
    export CIQ_HOME="$(<"$HOME/.Garmin/ConnectIQ/current-sdk.cfg")"
    [[ -n "$CIQ_HOME" ]] && _prepend_path "$CIQ_HOME/bin"
fi

