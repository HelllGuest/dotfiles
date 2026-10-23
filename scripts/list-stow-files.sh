#!/usr/bin/env bash
# list-stow-files.sh — print git-indexed files under stow/ (gitignore-aware).
# Used by CI, pre-commit, and regenerating all_stow_files.txt.
#
# Only lists paths in the git index (tracked or staged). Untracked files are
# omitted so CI on a clean checkout matches the committed inventory.
# After adding a new stow path: git add it, then regenerate this file.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT" || exit 1

if [[ ! -d stow ]]; then
  echo "error: stow/ missing under $REPO_ROOT" >&2
  exit 1
fi

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "error: $REPO_ROOT is not a git work tree (list-stow-files needs git index)" >&2
  exit 1
fi

# Index only (no -o): excludes untracked + respects .gitignore for never-added junk.
# LC_ALL=C: stable order on Arch (UTF-8) and GitHub runners (often C) so CI
# "Stow inventory freshness" does not fail on case/locale sort alone.
git ls-files -- stow | LC_ALL=C sort
