#!/usr/bin/env bash
# Prints current battery power draw in watts as JSON for waybar.
# macsmc-battery reports power_now in microwatts (negative = discharging).
BAT=$(ls -d /sys/class/power_supply/*battery* 2>/dev/null | head -n1)   # macsmc-battery
uw=$(<"$BAT/power_now")
status=$(<"$BAT/status")
w=$(awk -v u="$uw" 'BEGIN { if (u < 0) u = -u; printf "%.1f", u / 1000000 }')

case "$status" in
  Charging)    icon="󰂄"; class="charging"; tip="Charging at ${w} W" ;;
  Discharging) icon="󱐋"; class="discharging"; tip="Drawing ${w} W from battery" ;;
  *)           icon="󰚥"; class="ac"; tip="On AC (${status}), battery ${w} W" ;;
esac

printf '{"text":"%s %sW","tooltip":"%s","class":"%s"}\n' "$icon" "$w" "$tip" "$class"
