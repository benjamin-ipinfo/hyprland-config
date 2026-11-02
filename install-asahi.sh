#!/usr/bin/env bash
# =============================================================================
# Hyprland desktop for Apple silicon MacBooks on Fedora Asahi Remix.
# Reproduces the full setup on a fresh *minimal* install. Shared steps: lib/common.sh.
#   Mac-only here: keyboard swaps, console font, notch (14"/16" Pro), "never sleep" lid
#   policy, battery charge limit, power-off at 2%. Panel scale per model: hyprland.lua.
# Tested on: MacBook Air M1 (Fedora Asahi Remix 44).
#
# Usage (as your normal user, not root; sudo asks for your password once):
#   ./install.sh   (detects the Mac and runs this script)   reboot, pick "Hyprland" in ly
# Idempotent: safe to re-run. Output is appended to install.log.
# =============================================================================
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

if ! { [ -r /proc/device-tree/compatible ] && tr -d '\0' < /proc/device-tree/compatible | grep -q apple; }; then
  echo "Not an Apple silicon Mac: use install-amd64.sh (or ./install.sh to pick automatically)."; exit 1
fi
MODEL=$(tr -d '\0' < /proc/device-tree/model)
# System battery (macsmc-battery). Wireless mice/keyboards also report type=Battery but
# with scope=Device: skip those.
BAT=""
for p in /sys/class/power_supply/*; do
  if [ "$(cat "$p/type" 2>/dev/null || true)" = Battery ] && [ "$(cat "$p/scope" 2>/dev/null || true)" != Device ]; then
    BAT=$p; break
  fi
done
step "Detected: $MODEL | $(uname -m) | Fedora $FEDORA, $(uname -r)"

sudo_keepalive
common_upgrade
common_repos
# Mac extras: Bluetooth GUI, backlight keys, UPower (2% power-off)
common_packages blueman brightnessctl upower
common_pin_hyprland
common_browsers
common_nerd_font

# =============================================================================
# Keyboard, console, notch (baked into the initramfs)
# =============================================================================
step "Keyboard: Cmd<->Option swapped (Cmd sends Alt), Fn<->left Ctrl swapped, F-keys first"
echo 'options hid_apple swap_fn_leftctrl=1 fnmode=2 swap_opt_cmd=1' \
  | sudo tee /etc/modprobe.d/hid_apple.conf
step "Console: US keymap, large font for the Retina panel"
printf 'KEYMAP="us"\nFONT="latarcyrheb-sun32"\n' | sudo tee /etc/vconsole.conf

# MacBook Pro 14"/16": use the full panel incl. the strip beside the notch. hyprland.lua then
# sets 3024x1964@120 (14") / 3456x2234@120 (16") at scale 2 and waybar fills the notch strip.
if [[ "$MODEL" == *"14-inch"* || "$MODEL" == *"16-inch"* ]]; then
  step "MacBook Pro 14/16\": kernel arg appledrm.show_notch=1 (takes effect after reboot)"
  kernel_args appledrm.show_notch=1
fi

# =============================================================================
# Services, login
# =============================================================================
step "Bluetooth"
sudo systemctl enable bluetooth.service
common_login

# =============================================================================
# Power
# =============================================================================
step "logind: lid/power key lock, never suspend (s2idle is unreliable; screen-off idle ~1.4 W)"
sudo mkdir -p /etc/systemd/logind.conf.d
sudo tee /etc/systemd/logind.conf.d/10-lid-lock.conf >/dev/null <<'EOF'
[Login]
HandleLidSwitch=lock
HandleLidSwitchExternalPower=lock
HandleLidSwitchDocked=ignore
# Touch ID/power key: short press locks (like macOS); holding it still hard-powers-off
HandlePowerKey=lock
HandleSuspendKey=ignore
HandleHibernateKey=ignore
EOF
# undo: sudo systemctl unmask sleep.target suspend.target hibernate.target hybrid-sleep.target suspend-then-hibernate.target
sudo systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target suspend-then-hibernate.target

if [ -n "$BAT" ]; then
  LIMIT_FILE="$BAT/charge_control_end_threshold"
  if [ -e "$LIMIT_FILE" ]; then
    step "Battery: stop charging at 90% (falls back to 80% if the firmware only allows 80/100)"
    LIMIT=90
    echo 90 | sudo tee "$LIMIT_FILE" >/dev/null 2>&1 || true
    if [ "$(cat "$LIMIT_FILE" 2>/dev/null)" != 90 ]; then
      LIMIT=80
      echo 80 | sudo tee "$LIMIT_FILE" >/dev/null 2>&1 || true
    fi
    echo "ACTION==\"add|change\", SUBSYSTEM==\"power_supply\", KERNEL==\"$(basename "$BAT")\", ATTR{charge_control_end_threshold}=\"$LIMIT\"" \
      | sudo tee /etc/udev/rules.d/90-battery-charge-limit.rules
    sudo udevadm control --reload
    echo "charge limit now: $(cat "$LIMIT_FILE" 2>/dev/null || echo '?')%"
  else
    warn "This battery has no charge limit control; skipping."
  fi

  step "UPower: clean power-off at 2% (low-battery notifications: hypr/scripts/battery-notify.sh)"
  sudo mkdir -p /etc/UPower/UPower.conf.d
  printf '[UPower]\nCriticalPowerAction=PowerOff\nPercentageAction=2.0\n' \
    | sudo tee /etc/UPower/UPower.conf.d/10-poweroff.conf
fi

# =============================================================================
# Dotfiles, session, finish
# =============================================================================
common_dotfiles
common_session

step "Rebuild initramfs for every installed kernel (keyboard + console font apply from early boot)"
sudo dracut -f --regenerate-all

common_verify
step "Done. Reboot and pick \"Hyprland\" in ly (not \"Hyprland (uwsm-managed)\")."
