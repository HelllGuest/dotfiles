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



# Added by Antigravity CLI installer
export PATH="/home/songoku/.local/bin:$PATH"
