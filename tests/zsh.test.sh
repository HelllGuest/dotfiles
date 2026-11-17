#!/usr/bin/env bash
# zsh is the login shell and starts fast: compinit once (deferred, dump kept
# fresh), static tool inits cached, no duplicate fnm, no per-start forks.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
fail() { echo "FAIL: $*" >&2; exit 1; }
command -v zsh >/dev/null || { echo "SKIP: zsh not installed"; echo "PASS: zsh.test.sh"; exit 0; }
P="$ROOT/stow/zsh/.zsh-plugins"; Z="$ROOT/stow/zsh/.zshrc"
zsh -n "$P" && zsh -n "$Z" || fail "zsh syntax"

# Static shape: one compinit (deferred), fnm env once, cached inits.
code="$(sed 's/#.*//' "$P" "$Z")"
[[ $(grep -c 'compinit -C -i' <<<"$code") -eq 1 && $(grep -c 'zicompinit' <<<"$code") -eq 0 ]] \
  || fail "compinit must run once (_dot_compinit), not also via zicompinit"
[[ $(grep -c 'fnm env' <<<"$code") -eq 1 ]] || fail "fnm env must be evaluated once"
for t in starship fzf atuin zoxide direnv uv; do
  grep -q "_zsh_cache_eval $t " <<<"$code" || fail "$t init must be cached (_zsh_cache_eval)"
done
grep -qE 'eval "\$\((starship|atuin|zoxide|direnv|uv) ' <<<"$code" && fail "uncached tool init left"
grep -F 'mkdir -p "$(dirname' <<<"$code" | grep -qv ZINIT_HOME && fail "per-start mkdir/dirname forks left (only the one-time zinit clone may)"
grep -q 'zsh login shell' "$ROOT/install.sh" || fail "install.sh must make zsh the login shell"
grep -q -- '--- Login shell ---' "$ROOT/scripts/check.sh" || fail "check.sh must verify the login shell"

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
helpers="$(awk '/^_zsh_cache_dir=/{f=1} f; f&&/^}$/{n++} n==2{exit}' "$P")"
[[ -n $helpers ]] || fail "could not extract _zsh_cache_eval/_dot_compinit"

# _zsh_cache_eval: cached on first use, reused, regenerated when the binary changes.
mkdir -p "$T/bin"
cat >"$T/bin/tool" <<EOF
#!/bin/sh
echo run >>"$T/runs"
echo 'TOOL_LOADED=\$((\${TOOL_LOADED:-0}+1))'
EOF
chmod +x "$T/bin/tool"
run() { XDG_CACHE_HOME="$T/cache" PATH="$T/bin:$PATH" zsh -f -c "$helpers
_zsh_cache_eval tool tool init; print \$TOOL_LOADED"; }
[[ $(run) == 1 ]] || fail "cached init must be sourced"
[[ $(run) == 1 && $(wc -l <"$T/runs") -eq 1 ]] || fail "second shell must reuse the cache (no fork)"
sleep 1; touch "$T/bin/tool"
run >/dev/null
[[ $(wc -l <"$T/runs") -eq 2 ]] || fail "a newer binary must regenerate the cache"
printf '#!/bin/sh\nexit 1\n' >"$T/bin/tool"
[[ -s $T/cache/zsh/init/tool.zsh ]] || fail "cache file missing"
rm -f "$T/cache/zsh/init/tool.zsh"
[[ $(run) == "" ]] && [[ ! -e $T/cache/zsh/init/tool.zsh ]] || fail "failed init must not leave an empty cache"
[[ $(XDG_CACHE_HOME="$T/cache" zsh -f -c "$helpers
_zsh_cache_eval absent no-such-tool-xyz init; print ok") == ok ]] || fail "absent tool must be a no-op"

# _dot_compinit: stale dump → full run + touch (fresh next time); fresh → -C.
dump="$T/zd/.zcompdump"; mkdir -p "$T/zd"
cat >"$T/compinit-stub" <<'EOF'
compinit() { print -r -- "compinit $*" >>"$LOG"; [[ -s ${@[-1]} ]] || print x >"${@[-1]}"; }
EOF
cinit() { LOG="$T/cinit.log" ZDOTDIR="$T/zd" zsh -f -c "source $T/compinit-stub; autoload() { :; }; $helpers
_dot_compinit"; }
cinit; grep -q '^compinit -i -d ' "$T/cinit.log" || fail "missing dump must get a full compinit"
: >"$T/cinit.log"; cinit
grep -q '^compinit -C -i -d ' "$T/cinit.log" || fail "fresh dump must use compinit -C: $(cat "$T/cinit.log")"
touch -d '3 days ago' "$dump"; : >"$T/cinit.log"; cinit
grep -q '^compinit -i -d ' "$T/cinit.log" || fail "dump older than 24h must get a full compinit"
[[ -n $(find "$dump" -mmin -5) ]] || fail "full compinit must refresh the dump mtime (else slow path forever)"

# Real startup budget (interactive, all rc files) when this repo is the stowed one.
if [[ "$(readlink -f "$HOME/.zshrc" 2>/dev/null)" == "$Z" ]]; then
  best=99999
  for _ in 1 2 3 4 5; do
    s=$(date +%s%N); zsh -i -c exit >/dev/null 2>&1; e=$(date +%s%N)
    ms=$(( (e - s) / 1000000 )); (( ms < best )) && best=$ms
  done
  (( best < 250 )) || fail "interactive zsh startup ${best} ms (budget 250 ms)"
  echo "zsh interactive startup: ${best} ms"
fi

echo "PASS: zsh.test.sh"
