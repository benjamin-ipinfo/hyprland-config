#!/usr/bin/env bash
# Prints current battery power draw in watts as JSON for waybar.
# power_now is in microwatts (macsmc-battery: negative = discharging). Some PC batteries
# only expose current_now/voltage_now. No battery (desktop): print nothing -> module hidden.
# System battery: type Battery, but not a wireless mouse/keyboard (those have scope=Device)
BAT=""
for p in /sys/class/power_supply/*; do
  [ "$(cat "$p/type" 2>/dev/null)" = Battery ] && [ "$(cat "$p/scope" 2>/dev/null)" != Device ] && { BAT=$p; break; }
done   # macsmc-battery on Macs, BAT0/BAT1 on PC laptops, empty on desktops
[ -n "$BAT" ] || { echo '{"text":""}'; exit 0; }
if [ -r "$BAT/power_now" ]; then
  uw=$(<"$BAT/power_now")
else
  uw=$(awk -v i="$(cat "$BAT/current_now" 2>/dev/null || echo 0)" -v v="$(cat "$BAT/voltage_now" 2>/dev/null || echo 0)" 'BEGIN { printf "%d", i * v / 1000000 }')
fi
status=$(<"$BAT/status")
w=$(awk -v u="$uw" 'BEGIN { if (u < 0) u = -u; printf "%.1f", u / 1000000 }')

case "$status" in
  Charging)    icon="󰂄"; class="charging"; tip="Charging at ${w} W" ;;
  Discharging) icon="󱐋"; class="discharging"; tip="Drawing ${w} W from battery" ;;
  *)           icon="󰚥"; class="ac"; tip="On AC (${status}), battery ${w} W" ;;
esac

printf '{"text":"%s %sW","tooltip":"%s","class":"%s"}\n' "$icon" "$w" "$tip" "$class"
