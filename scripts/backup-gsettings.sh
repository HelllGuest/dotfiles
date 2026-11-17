#!/bin/bash
# backup-gsettings.sh — snapshot live dconf into gnome/dconf/user.conf.
# dconf dump only lists non-default keys, so a snapshot taken before the
# repo's privacy/hardening keys were applied would silently drop them; they
# are re-asserted after the dump. GSETTINGS_OUT overrides the target (tests).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${GSETTINGS_OUT:-$REPO_ROOT/gnome/dconf/user.conf}"

echo "Backing up GNOME settings to $OUT..."
tmp="$(mktemp)"
trap 'rm -f -- "$tmp"' EXIT
dconf dump / > "$tmp"
python3 - "$tmp" <<'PY'
import configparser
import sys

ENFORCED = {
    "org/gnome/desktop/notifications": {"show-in-lock-screen": "false"},
    "org/gnome/desktop/media-handling": {"autorun-never": "true"},
    "org/gnome/desktop/privacy": {
        "report-technical-problems": "false",
        "send-software-usage-stats": "false",
        "remember-recent-files": "false",
    },
}
path = sys.argv[1]
conf = configparser.ConfigParser(interpolation=None, strict=False, delimiters=("=",))
conf.optionxform = str  # dconf keys and paths are case-sensitive
conf.read(path)
for section, keys in ENFORCED.items():
    if not conf.has_section(section):
        conf.add_section(section)
    for key, value in keys.items():
        conf.set(section, key, value)
with open(path, "w", encoding="utf-8") as fh:
    conf.write(fh, space_around_delimiters=False)
PY
cp -- "$tmp" "$OUT"
echo "Done: $OUT"
