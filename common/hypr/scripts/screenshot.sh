#!/usr/bin/env bash
# screenshot.sh full|area — saves to ~/Pictures/Screenshots and copies to clipboard.
dir="$HOME/Pictures/Screenshots"; mkdir -p "$dir"
f="$dir/$(date +%F_%H-%M-%S).png"
case "${1:-full}" in
  area) geo=$(slurp) || exit 0; grim -g "$geo" "$f" ;;
  *)    grim "$f" ;;
esac
wl-copy < "$f" && notify-send -a screenshot -i "$f" "Screenshot saved" "$f"
