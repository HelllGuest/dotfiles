#!/usr/bin/env bash
# lint-docs.sh — markdownlint on repo *.md (header spacing + tables).
# Not part of validate-configs.sh. CI sets CI=true and fails if the linter is missing.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

lint_cmd=()
if command -v markdownlint-cli2 >/dev/null 2>&1; then
  lint_cmd=(markdownlint-cli2)
elif command -v markdownlint >/dev/null 2>&1; then
  lint_cmd=(markdownlint)
elif command -v npx >/dev/null 2>&1; then
  lint_cmd=(npx --yes markdownlint-cli2)
else
  if [[ "${CI:-}" == "true" ]]; then
    echo "ERROR: markdownlint-cli2 / markdownlint / npx required in CI." >&2
    exit 1
  fi
  echo "skip: install markdownlint-cli2 (or npx) to lint markdown"
  exit 0
fi

# cli2: globs + #ignore. markdownlint(1): paths only. Both honor .markdownlintignore.
if [[ "${lint_cmd[0]}" == "markdownlint" ]]; then
  mapfile -t md_files < <(find . -type f -name '*.md' \
    ! -path './.git/*' ! -path './node_modules/*' ! -path './stow/*' | sort)
  "${lint_cmd[@]}" "${md_files[@]}"
else
  "${lint_cmd[@]}" '**/*.md' '#.git' '#node_modules' '#stow'
fi
