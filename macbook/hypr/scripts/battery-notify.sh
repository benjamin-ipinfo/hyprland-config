#!/usr/bin/env bash
# Low-battery notifications (mako). Warns once at 15% and once at 5% per discharge.
# UPower powers off cleanly at 2% (/etc/UPower/UPower.conf.d/10-poweroff.conf).
# System battery: type Battery, but not a wireless mouse/keyboard (those have scope=Device)
BAT=""
for p in /sys/class/power_supply/*; do
  [ "$(cat "$p/type" 2>/dev/null)" = Battery ] && [ "$(cat "$p/scope" 2>/dev/null)" != Device ] && { BAT=$p; break; }
done   # macsmc-battery on Macs, BAT0/BAT1 on PC laptops, empty on desktops
[ -n "$BAT" ] || exit 0   # desktop: nothing to watch
warned=100
while sleep 60; do
  cap=$(<"$BAT/capacity"); status=$(<"$BAT/status")
  if [ "$status" != Discharging ]; then warned=100; continue; fi
  if [ "$cap" -le 5 ] && [ "$warned" -gt 5 ]; then
    notify-send -u critical -a battery "Battery critical: ${cap}%" "Plug in now — powering off at 2%."; warned=5
  elif [ "$cap" -le 15 ] && [ "$warned" -gt 15 ]; then
    notify-send -u normal -a battery "Battery low: ${cap}%" "Plug in soon."; warned=15
  fi
done
