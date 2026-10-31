#!/usr/bin/env bash
# Screen + keyboard backlight for waybar (JSON).
#   brightness.sh            -> print status
#   brightness.sh kbd-cycle  -> keyboard backlight 0 -> 25 -> 50 -> 75 -> 100 -> 0 %
SCREEN=$(ls /sys/class/backlight | head -n1)   # apple-panel-bl on Apple silicon
KBD=kbd_backlight
pct() { brightnessctl -m -d "$1" | cut -d, -f4 | tr -d '%'; }

if [ "${1:-}" = kbd-cycle ]; then
  k=$(pct "$KBD")
  next=$(( (k / 25 + 1) * 25 )); [ "$next" -gt 100 ] && next=0
  brightnessctl -q -d "$KBD" set "${next}%"
  exit 0
fi

s=$(pct "$SCREEN"); k=$(pct "$KBD")
printf '{"text":"\U000F00E0 %s%%  \U000F030C %s%%","tooltip":"Screen: %s%%  ·  Keyboard: %s%%\\nscroll: screen · click: keyboard step · right-click: keyboard off\\nShift+brightness keys: keyboard"}\n' "$s" "$k" "$s" "$k"
