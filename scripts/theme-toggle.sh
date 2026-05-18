#!/bin/bash

# theme-toggle.sh
# Cycles through available palettes in theming/palettes/ (ignoring base.json)

PALETTE_DIR="theming/palettes"
STATE_FILE="theming/generated/current_theme.txt"

# Get list of palettes (excluding base.json)
PALETTES=($(ls "$PALETTE_DIR"/*.json | xargs -n 1 basename | sed 's/\.json//' | grep -v "base"))

if [ ${#PALETTES[@]} -eq 0 ]; then
    echo "No palettes found!"
    exit 1
fi

# Determine current theme
if [ -f "$STATE_FILE" ]; then
    CURRENT=$(cat "$STATE_FILE")
else
    CURRENT="${PALETTES[0]}"
fi

# Find index of current theme
NEXT_INDEX=0
for i in "${!PALETTES[@]}"; do
   if [[ "${PALETTES[$i]}" == "${CURRENT}" ]]; then
       NEXT_INDEX=$(( (i + 1) % ${#PALETTES[@]} ))
       break
   fi
done

NEXT_THEME="${PALETTES[$NEXT_INDEX]}"

echo "Toggling from $CURRENT to $NEXT_THEME..."
./scripts/theme-switch.sh "$NEXT_THEME"

# Save state
echo "$NEXT_THEME" > "$STATE_FILE"
