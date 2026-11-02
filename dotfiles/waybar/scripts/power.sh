#!/usr/bin/env bash
# Prints current battery power draw in watts as JSON for waybar.
# power_now is in microwatts (macsmc-battery: negative = discharging). Some PC batteries
# only expose current_now/voltage_now. No battery (desktop): print nothing -> module hidden.
# System battery: type Battery, but not a wireless mouse/keyboard (those have scope=Device)
#
# power.sh --live  (config-wired.jsonc, PCs without battery): APU package power from the
# amdgpu sensor (PPT = CPU + GPU + SoC), one JSON line every 5 s (average of 1 s
# samples), never exits. Wall power is higher (RAM, SSD, NIC, PSU losses). RAPL would be similar but is root-only.
if [ "${1:-}" = --live ]; then
  f=""
  for h in /sys/class/hwmon/hwmon*; do
    [ "$(cat "$h/name" 2>/dev/null)" = amdgpu ] || continue
    for x in power1_input power1_average; do [ -r "$h/$x" ] && { f=$h/$x; break 2; }; done
  done
  [ -n "$f" ] || { echo '{"text":""}'; exec sleep infinity; }   # no sensor: hidden
  # Sample every second, show the 5-second average (instant readings jump around too much)
  while :; do
    sum=0
    for _ in 1 2 3 4 5; do sum=$(( sum + $(<"$f") )); sleep 1; done
    d=$(( sum / 500000 ))   # 5 samples in µW -> average in tenths of a watt
    printf '{"text":"󱐋 %d.%dW","tooltip":"APU package power (CPU + GPU + SoC), 5 s average: %d.%d W\\nWall power is higher (RAM, SSD, network, PSU)"}\n' \
      $((d / 10)) $((d % 10)) $((d / 10)) $((d % 10))
  done
fi

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
