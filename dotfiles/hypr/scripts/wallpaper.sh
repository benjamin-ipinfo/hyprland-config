#!/usr/bin/env bash
# wallpaper.sh /path/to/image   — set wallpaper now and keep it after reboot.
# Supports png/jpg/webp/jxl. No argument: show the current one.
set -e
link="$HOME/Pictures/wallpapers/current"
if [ -z "${1:-}" ]; then readlink -f "$link"; exit 0; fi
img=$(realpath "$1")
ln -sfn "$img" "$link"                          # persists (hyprpaper.conf reads this)
hyprctl hyprpaper wallpaper ",$img" >/dev/null  # apply live, all monitors
echo "Wallpaper: $img"
