#!/usr/bin/env bash
# Global git hooks (core.hooksPath) run in every repo, including untrusted
# clones: repo-defined code may only run where the user set hooks.trusted
# (local config, never cloned) or, for the inventory hook, in ~/dotfiles.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
fail() { echo "FAIL: $*" >&2; exit 1; }
for h in "$ROOT/ai-rules/git-hooks/pre-push" "$ROOT/ai-rules/git-hooks/pre-commit"; do bash -n "$h" || fail "bash -n $h"; done
cmp -s "$ROOT/ai-rules/git-hooks/pre-push" "$ROOT/stow/git/.config/git/templates/hooks/pre-push" \
  || fail "template pre-push must match ai-rules/git-hooks/pre-push"
T="$(mktemp -d)"; trap 'rm -rf -- "$T"' EXIT
export GIT_CONFIG_GLOBAL="$T/gitconfig" GIT_CONFIG_NOSYSTEM=1 HOME="$T/home"
mkdir -p "$T/bin" "$HOME"
# Stand-in for npm: running the repo's "lint" script = repo code execution.
printf '#!/bin/sh\necho ran >"%s/npm-ran"\nexit 0\n' "$T" >"$T/bin/npm"; chmod +x "$T/bin/npm"
newrepo() { git init -q "$1"; }

# pre-push
newrepo "$T/evil"; printf '{"scripts":{"lint":"x"}}\n' >"$T/evil/package.json"
(cd "$T/evil" && PATH="$T/bin:/usr/bin:/bin" bash "$ROOT/ai-rules/git-hooks/pre-push" origin x </dev/null >/dev/null 2>&1) \
  || fail "pre-push must not block pushes from untrusted repos"
[[ ! -e $T/npm-ran ]] || fail "pre-push ran repo scripts in an untrusted repo"
git -C "$T/evil" config --local hooks.trusted true
(cd "$T/evil" && PATH="$T/bin:/usr/bin:/bin" bash "$ROOT/ai-rules/git-hooks/pre-push" origin x </dev/null >/dev/null 2>&1) || true
[[ -e $T/npm-ran ]] || fail "pre-push must still run checks in trusted repos"
rm -f "$T/npm-ran"; git -C "$T/evil" config --local hooks.trusted yes-please
(cd "$T/evil" && PATH="$T/bin:/usr/bin:/bin" bash "$ROOT/ai-rules/git-hooks/pre-push" origin x </dev/null >/dev/null 2>&1) || true
[[ ! -e $T/npm-ran ]] || fail "invalid hooks.trusted value must count as untrusted"

# Repos with nothing to check (no package.json/Cargo.toml/…) get no skip note.
newrepo "$T/plain"
_o="$(cd "$T/plain" && bash "$ROOT/ai-rules/git-hooks/pre-push" origin x </dev/null 2>&1)" || fail "pre-push failed in a plain repo"
[[ -z $_o ]] || fail "pre-push must stay silent when there is nothing to check: $_o"
_o="$(cd "$T/evil" && git config --local --unset hooks.trusted; bash "$ROOT/ai-rules/git-hooks/pre-push" origin x </dev/null 2>&1)" || true
grep -q 'checks skipped (untrusted repo' <<<"$_o" || fail "untrusted repo with checks must say they were skipped: $_o"
unset -v _o

# pre-commit (stow inventory): runs scripts/list-stow-files.sh from the repo.
mkrepo_inv() { newrepo "$1"; mkdir -p "$1/stow" "$1/scripts"; : >"$1/all_stow_files.txt"
  printf '#!/bin/sh\necho ran >"%s/inv-ran"\n' "$T" >"$1/scripts/list-stow-files.sh"; }
mkrepo_inv "$T/evil2"
(cd "$T/evil2" && bash "$ROOT/ai-rules/git-hooks/pre-commit" >/dev/null 2>&1) || true
[[ ! -e $T/inv-ran ]] || fail "pre-commit ran a repo script in an untrusted repo"
mkrepo_inv "$HOME/dotfiles"
(cd "$HOME/dotfiles" && bash "$ROOT/ai-rules/git-hooks/pre-commit" >/dev/null 2>&1) || true
[[ -e $T/inv-ran ]] || fail "pre-commit must keep working in ~/dotfiles"
rm -f "$T/inv-ran"; git -C "$T/evil2" config --local hooks.trusted true
(cd "$T/evil2" && bash "$ROOT/ai-rules/git-hooks/pre-commit" >/dev/null 2>&1) || true
[[ -e $T/inv-ran ]] || fail "pre-commit must run in repos marked trusted"

echo "PASS: git-hooks.test.sh"
