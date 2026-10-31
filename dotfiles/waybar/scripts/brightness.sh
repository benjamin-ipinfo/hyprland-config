#!/usr/bin/env bash
# Screen + keyboard backlight for waybar (JSON).
#   brightness.sh            -> print status
#   brightness.sh kbd-cycle  -> keyboard backlight 0 -> 25 -> 50 -> 75 -> 100 -> 0 %
SCREEN=$(ls /sys/class/backlight 2>/dev/null | head -n1)        # apple-panel-bl on Apple silicon
KBD=$(ls /sys/class/leds 2>/dev/null | grep -m1 kbd_backlight)    # kbd_backlight, tpacpi::kbd_backlight, ...
pct() { brightnessctl -m -d "$1" | cut -d, -f4 | tr -d '%'; }

if [ "${1:-}" = kbd-cycle ]; then
  [ -n "$KBD" ] || exit 0
  k=$(pct "$KBD")
  next=$(( (k / 25 + 1) * 25 )); [ "$next" -gt 100 ] && next=0
  brightnessctl -q -d "$KBD" set "${next}%"
  exit 0
fi

# Desktop monitors have no backlight device: print nothing -> module hidden
[ -n "$SCREEN" ] || [ -n "$KBD" ] || { echo '{"text":""}'; exit 0; }
text=""; tip=""
if [ -n "$SCREEN" ]; then s=$(pct "$SCREEN"); text=$(printf '\U000F00E0 %s%%' "$s"); tip="Screen: $s%"; fi
if [ -n "$KBD" ]; then k=$(pct "$KBD"); text="$text  $(printf '\U000F030C %s%%' "$k")"; tip="$tip  ·  Keyboard: $k%"; fi
printf '{"text":"%s","tooltip":"%s\\nscroll: screen · click: keyboard step · right-click: keyboard off\\nShift+brightness keys: keyboard"}\n' "${text# }" "${tip#  · }"
