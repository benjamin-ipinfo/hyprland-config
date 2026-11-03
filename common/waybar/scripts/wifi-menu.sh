#!/usr/bin/env bash
# Wi-Fi picker (fuzzel): click the waybar network icon -> scan -> pick -> connect.
#  - known networks connect directly, open ones too
#  - secured new networks ask for the password (fuzzel password prompt)
#  - enterprise (802.1X) / anything fancy -> "Advanced settings…" (nm-connection-editor)
set -u
menu() { fuzzel --dmenu --index --minimal-lines --lines 15 --width 50 "$@"; }
note() { notify-send -a wifi -t 3000 "$@"; }

# icons (Nerd Font, written as escapes so they survive copy/paste)
I_SIG=($'\U000F092F' $'\U000F091F' $'\U000F0922' $'\U000F0925' $'\U000F0928')  # 0..4 bars
I_LOCK=$'\U000F033E'; I_ON=$'\U000F012C'; I_SCAN=$'\U000F0450'; I_OFF=$'\U000F05AA'; I_GEAR=$'\U000F0493'

if [ "$(nmcli radio wifi)" = disabled ]; then
  pick=$(printf '%s  Turn Wi-Fi on\n' "$I_ON" | menu --prompt 'Wi-Fi off › ') || exit 0
  nmcli radio wifi on && note "Wi-Fi on" "Scanning…"
  sleep 3
fi

note "Wi-Fi" "Scanning for networks…"
# -e no: no escaping; SSID is the last field, so split on the first 3 colons only
mapfile -t raw < <(nmcli -t -e no -f IN-USE,SIGNAL,SECURITY,SSID dev wifi list --rescan yes)
mapfile -t known < <(nmcli -t -f NAME,TYPE con show | awk -F: '$2=="802-11-wireless"{print $1}')

declare -A sig sec inuse
order=()
for line in "${raw[@]}"; do
  u=${line%%:*}; rest=${line#*:}; s=${rest%%:*}; rest=${rest#*:}; k=${rest%%:*}; ssid=${rest#*:}
  [ -z "$ssid" ] && continue                         # hidden networks
  if [ -z "${sig[$ssid]+x}" ]; then order+=("$ssid"); sig[$ssid]=0; fi
  [ "$s" -gt "${sig[$ssid]}" ] && sig[$ssid]=$s && sec[$ssid]=$k
  [ "$u" = "*" ] && inuse[$ssid]=1
done

# sort: connected first, then by signal
mapfile -t ssids < <(for x in "${order[@]}"; do printf '%s\t%03d\t%s\n' "${inuse[$x]:-0}" "${sig[$x]}" "$x"; done \
                      | sort -t$'\t' -k1,1r -k2,2r | cut -f3-)

entries=()
for x in "${ssids[@]}"; do
  s=${sig[$x]}; icon=${I_SIG[$(( s >= 80 ? 4 : s >= 60 ? 3 : s >= 40 ? 2 : s >= 20 ? 1 : 0 ))]}
  tag=""
  [ -n "${inuse[$x]:-}" ] && tag+="  (connected)"
  printf '%s\n' "${known[@]}" | grep -Fxq -- "$x" && [ -z "${inuse[$x]:-}" ] && tag+="  (saved)"
  lock=""; [ -n "${sec[$x]}" ] && [ "${sec[$x]}" != "--" ] && lock=" $I_LOCK"
  entries+=("$icon  $x$lock$tag")
done
entries+=("$I_SCAN  Rescan" "$I_OFF  Turn Wi-Fi off" "$I_GEAR  Advanced settings…")

idx=$(printf '%s\n' "${entries[@]}" | menu --prompt 'Wi-Fi › ' --placeholder 'type to filter') || exit 0
n=${#ssids[@]}
case $(( idx - n )) in
  0) exec "$0" ;;
  1) nmcli radio wifi off && note "Wi-Fi off"; exit 0 ;;
  2) exec nm-connection-editor ;;
esac
ssid=${ssids[$idx]}
[ -n "${inuse[$ssid]:-}" ] && { note "Wi-Fi" "Already connected to $ssid"; exit 0; }

if printf '%s\n' "${known[@]}" | grep -Fxq -- "$ssid"; then
  note "Wi-Fi" "Connecting to $ssid…"
  if nmcli con up id "$ssid" >/dev/null 2>&1; then note "Wi-Fi" "Connected to $ssid"; exit 0; fi
  # saved password probably wrong/changed -> fall through and ask again
  nmcli con delete id "$ssid" >/dev/null 2>&1
fi

security=${sec[$ssid]}
if [[ "$security" == *802.1X* ]]; then
  note "Wi-Fi" "$ssid uses enterprise login — opening advanced settings"; exec nm-connection-editor
fi

if [ -z "$security" ] || [ "$security" = "--" ]; then
  note "Wi-Fi" "Connecting to $ssid (open network)…"
  out=$(nmcli dev wifi connect "$ssid" 2>&1)
else
  pw=$(fuzzel --dmenu --password --prompt-only "Password for $ssid › ") || exit 0
  [ -z "$pw" ] && exit 0
  note "Wi-Fi" "Connecting to $ssid…"
  out=$(nmcli dev wifi connect "$ssid" password "$pw" 2>&1)
fi

if [ $? -eq 0 ]; then
  note "Wi-Fi" "Connected to $ssid"
else
  nmcli con delete id "$ssid" >/dev/null 2>&1   # don't keep a broken profile
  notify-send -a wifi -u critical "Wi-Fi: couldn't connect to $ssid" "${out##*Error: }"
fi
