#!/usr/bin/env bash
# =============================================================================
# Hyprland desktop for Fedora — Apple silicon MacBooks (Fedora Asahi Remix) and
# amd64 PCs (Fedora, AMD/Intel graphics).
#
# Reproduces the full setup on a fresh *minimal* Fedora install. The hardware is
# detected at the start and only the matching steps run:
#   Apple silicon  keyboard swaps, notch, "never sleep" lid policy, Mac charge limit,
#                  built-in panel scale per model (in hyprland.lua)
#   PC             AMD hardware video decoding, firmware updates (fwupd), multi-monitor
#                  auto-setup on first login (hypr/scripts/monitors.py), normal sleep
#   any laptop     battery charge limit (if the firmware supports it), power-off at 2%
# Tested on: MacBook Air M1 (Fedora Asahi Remix 44). PC path: written for an AMD
# desktop (AMD GPU, 5K + 1440p monitors), not yet run on real hardware.
#
# Usage (as your normal user, not root; sudo will ask for your password):
#   sudo dnf install -y git
#   git clone https://github.com/benjamin-ipinfo/hyprland-config.git ~/Git/hyprland-config
#     (PC support lives on the amd64 branch until merged: add  -b amd64)
#   cd ~/Git/hyprland-config && ./install.sh
#   reboot, pick "Hyprland" in ly
#
# Idempotent: safe to re-run. Output is appended to install.log.
# =============================================================================
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOT="$REPO_DIR/dotfiles"
exec > >(tee -a "$REPO_DIR/install.log") 2>&1

step() { printf '\n\033[1;34m==> [%s] %s\033[0m\n' "$(date '+%F %T')" "$*"; }
warn() { printf '\033[1;33m!!  %s\033[0m\n' "$*"; }
# Add kernel args to the current kernels and to future ones. Idempotent: an existing arg
# with the same key is replaced (for video= the key includes the connector, e.g.
# video=DP-1, so one per monitor). grubby updates the BLS entries; kernel-install reads
# /etc/kernel/cmdline, grub2-mkconfig reads GRUB_CMDLINE_LINUX in /etc/default/grub.
kernel_args() {
  local a key re o f
  for a in "$@"; do
    case "$a" in video=*:*) key=${a%%:*} ;; *) key=${a%%=*} ;; esac
    re="${key//./\\.}[=:][^ \"]*"
    for o in $(sudo grubby --info=ALL | grep -oE "[ \"]$re" | tr -d ' "' | sort -u); do
      sudo grubby --update-kernel=ALL --remove-args="$o"
    done
    sudo grubby --update-kernel=ALL --args="$a"
    for f in /etc/kernel/cmdline /etc/default/grub; do
      [ -f "$f" ] || continue
      sudo sed -i -E "s#[ ]$re##g" "$f"
      if [ "$f" = /etc/kernel/cmdline ]; then
        sudo sed -i "1 s#[ ]*\$# $a#" "$f"
      else
        sudo sed -i -E "s#^GRUB_CMDLINE_LINUX=\"(.*)\"#GRUB_CMDLINE_LINUX=\"\\1 $a\"#" "$f"
      fi
    done
  done
}
[ "$EUID" -ne 0 ] || { echo "Run as your normal user, not root."; exit 1; }
FEDORA=$(rpm -E %fedora)

# =============================================================================
# 0. Detect hardware
# =============================================================================
if [ -r /proc/device-tree/compatible ] && tr -d '\0' < /proc/device-tree/compatible | grep -q apple; then
  PLATFORM=asahi
  MODEL=$(tr -d '\0' < /proc/device-tree/model)
  GPU=apple
else
  PLATFORM=pc
  MODEL="$(cat /sys/class/dmi/id/sys_vendor 2>/dev/null || true) $(cat /sys/class/dmi/id/product_name 2>/dev/null || true)"
  GPU=unknown
  for v in /sys/class/drm/card*/device/vendor; do
    case "$(cat "$v" 2>/dev/null)" in
      0x1002) GPU=amd ;;
      0x8086) [ "$GPU" = unknown ] && GPU=intel ;;
      0x10de) GPU=nvidia ;;
    esac
  done
fi
# System battery (macsmc-battery on Macs, BAT0/BAT1 on PC laptops; empty on desktops).
# Wireless mice/keyboards also report type=Battery but with scope=Device: skip those.
BAT=""
for p in /sys/class/power_supply/*; do
  if [ "$(cat "$p/type" 2>/dev/null || true)" = Battery ] && [ "$(cat "$p/scope" 2>/dev/null || true)" != Device ]; then
    BAT=$p; break
  fi
done
FORM=desktop; [ -n "$BAT" ] && FORM=laptop
step "Detected: $MODEL | platform=$PLATFORM ($(uname -m)) gpu=$GPU form=$FORM | Fedora $FEDORA, $(uname -r)"
if [ "$GPU" = nvidia ]; then
  warn "NVIDIA GPU detected: this script does not install NVIDIA drivers (akmod-nvidia from RPM"
  warn "Fusion nonfree + Hyprland env vars). Hyprland will likely not start on nouveau. Continuing."
fi

# Ask for the sudo password once and keep it alive (the full install takes >5 min)
sudo -v
while sleep 50; do sudo -n true; done 2>/dev/null &
SUDO_KEEPALIVE=$!
trap 'kill $SUDO_KEEPALIVE 2>/dev/null' EXIT

step "Update the base system first (avoids partial upgrades with COPR packages)"
sudo dnf -y upgrade --refresh

# =============================================================================
# 1. Repositories
# =============================================================================
step "Repositories: Hyprland COPR, RPM Fusion free, Brave"
sudo dnf -y install dnf5-plugins policycoreutils-python-utils
# sdegler/hyprland builds for aarch64 and x86_64 (solopasha doesn't for F44 aarch64)
sudo dnf -y copr enable sdegler/hyprland
# Full ffmpeg (HEVC etc.) and AMD hardware video decoding
sudo dnf -y install "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-${FEDORA}.noarch.rpm"
# Brave (also runs fine on Asahi's 16K pages)
sudo dnf config-manager addrepo --overwrite \
  --from-repofile=https://brave-browser-rpm-release.s3.brave.com/brave-browser.repo

# =============================================================================
# 2. Packages
# =============================================================================
step "Install packages"
PKGS=(
  # compositor + ecosystem
  hyprland xdg-desktop-portal-hyprland xdg-desktop-portal-gtk hyprpolkitagent
  hyprlock hypridle hyprpaper "f${FEDORA}-backgrounds-base"
  # bar, login manager, terminal, launcher, notifications
  waybar ly kitty fuzzel mako libnotify
  # audio / bluetooth / network GUIs (opened from the bar)
  pipewire-pulseaudio pavucontrol blueman network-manager-applet
  # hardware keys, screenshots, clipboard
  brightnessctl playerctl grim slurp wl-clipboard
  # power diagnostics: `sensors`, `sudo powertop`; upower does the 2% power-off on laptops
  powertop lm_sensors upower
  # secrets (unlocked at login by ly's PAM)
  gnome-keyring gnome-keyring-pam
  # file manager + trash/USB/phones, thumbnails, archives
  Thunar thunar-volman thunar-archive-plugin tumbler ffmpegthumbnailer
  gvfs gvfs-mtp file-roller
  # everyday apps / tools (python3: monitor auto-setup script)
  xdg-user-dirs xdg-utils git vim-enhanced htop btop loupe gnome-calculator mpv python3
  # browsers: Brave = default, Firefox (+ uBlock Origin) = logged-in work apps
  brave-browser firefox mozilla-ublock-origin
  # fonts: UI/bar + good on-screen replacements for web fonts + emoji + CJK
  jetbrains-mono-fonts-all fontawesome-fonts-all
  liberation-sans-fonts liberation-serif-fonts liberation-mono-fonts
  google-noto-serif-vf-fonts google-noto-color-emoji-fonts rsms-inter-vf-fonts
  google-roboto-fonts default-fonts-cjk-sans
)
if [ "$PLATFORM" = pc ]; then
  # firmware updates (Macs get firmware through macOS instead); `vainfo` to check video decoding
  PKGS+=(fwupd libva-utils)
fi
sudo dnf -y install --refresh "${PKGS[@]}"
# RPM Fusion ffmpeg replaces Fedora's ffmpeg-free libraries. RPM Fusion sometimes lags a
# Fedora update by a few days; then this can't resolve yet: don't abort, just re-run later.
sudo dnf -y install --allowerasing ffmpeg \
  || warn "RPM Fusion ffmpeg not installable right now (repo lagging?). Re-run ./install.sh later."

if [ "$GPU" = amd ]; then
  step "AMD: hardware video decoding (H.264/HEVC/AV1) via RPM Fusion's Mesa VA-API driver"
  # Fedora's mesa-va-drivers has the patented codecs disabled; the freeworld build replaces it
  # Pinned to the exact Fedora mesa version: if RPM Fusion hasn't caught up yet, retry later
  sudo dnf -y install --allowerasing mesa-va-drivers-freeworld \
    || warn "mesa-va-drivers-freeworld not installable right now (RPM Fusion lagging Fedora's mesa). Re-run ./install.sh later."
fi
if [ "$GPU" = intel ]; then
  warn "Intel GPU: for hardware video decoding add RPM Fusion nonfree and install intel-media-driver."
fi

step "Pin Hyprland packages (COPR updates can break the Lua config; upgrade on purpose, see README)"
mapfile -t HYPR_PKGS < <(rpm -qa --qf '%{name}\n' | grep -E '^(hypr|aquamarine$|xdg-desktop-portal-hyprland$)' | sort -u)
sudo dnf versionlock add "${HYPR_PKGS[@]}"

step "Firefox: address bar never web-searches, suggests from bookmarks only, never history (policy)"
# Firefox always needs a default engine; with keyword.enabled off it is never used from
# the address bar. Change suggestions in dotfiles/firefox/policies.json, check about:policies.
sudo install -Dm644 "$DOT/firefox/policies.json" /etc/firefox/policies/policies.json

step "Brave default fonts for new profiles (pages without their own CSS fonts)"
# Applied on Brave's first run; Standard/Sans = Noto Sans, Serif = Noto Serif, Fixed = JetBrains Mono
echo '{"webkit":{"webprefs":{"fonts":{"standard":{"Zyyy":"Noto Sans"},"sansserif":{"Zyyy":"Noto Sans"},"serif":{"Zyyy":"Noto Serif"},"fixed":{"Zyyy":"JetBrains Mono"}}}}}' \
  | sudo tee /opt/brave.com/brave/initial_preferences >/dev/null

step "JetBrainsMono Nerd Font (bar icons; not packaged in Fedora)"
NF_DIR="$HOME/.local/share/fonts/JetBrainsMonoNerd"
if ! ls "$NF_DIR"/*.ttf >/dev/null 2>&1; then
  tmp=$(mktemp -d)
  curl -fsSL -o "$tmp/nf.tar.xz" \
    https://github.com/ryanoasis/nerd-fonts/releases/download/v3.4.0/JetBrainsMono.tar.xz
  mkdir -p "$tmp/x"
  tar -xJf "$tmp/nf.tar.xz" -C "$tmp/x"
  mkdir -p "$(dirname "$NF_DIR")"
  rm -rf "$NF_DIR"
  mv "$tmp/x" "$NF_DIR"
  rm -rf "$tmp"
fi
fc-cache -f

# =============================================================================
# 3. Apple silicon only: keyboard, console, notch (baked into the initramfs)
# =============================================================================
if [ "$PLATFORM" = asahi ]; then
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
fi

# =============================================================================
# 4. Services, login manager
# =============================================================================
step "Security: no SSH server (re-enable with: sudo systemctl enable --now sshd)"
sudo systemctl disable --now sshd.service 2>/dev/null || true

step "Bluetooth (if there is an adapter), ly on tty2, boot to graphical target"
if ls /sys/class/bluetooth/hci* >/dev/null 2>&1; then
  sudo systemctl enable bluetooth.service
else
  echo "No Bluetooth adapter: bluetooth.service left disabled."
fi
sudo systemctl disable getty@tty2.service || true
sudo systemctl enable ly@tty2.service
sudo systemctl set-default graphical.target

step "ly + text console: black and white only, remember last user (SELinux label for save file)"
# Console palette: black, mid grey (bright black), everything else white. Applies to the
# text console and ly (boot messages, errors and the login box), so nothing is blue/red.
GREY=0,255,255,255,255,255,255,255,128,255,255,255,255,255,255,255
kernel_args "vt.default_red=$GREY" "vt.default_grn=$GREY" "vt.default_blu=$GREY"
# ly in eight-colour mode: text, border and errors (bold) all white on the default black.
# (True-colour values like 0x00FFFFFF are not valid in eight-colour mode.)
sudo sed -i -E 's/^animation = .*/animation = none/; s/^full_color = .*/full_color = false/; s/^save = .*/save = true/;
  s/^(fg|border_fg) = .*/\1 = 0x00000008/; s/^error_fg = .*/error_fg = 0x01000008/; s/^bg = .*/bg = 0x00000000/' \
  /etc/ly/config.ini
# ly runs as xdm_t and may not create files in /etc; pre-create a writable save file
sudo semanage fcontext -a -t xdm_var_lib_t '/etc/ly/save\.txt' 2>/dev/null \
  || sudo semanage fcontext -m -t xdm_var_lib_t '/etc/ly/save\.txt'
sudo touch /etc/ly/save.txt
sudo restorecon /etc/ly/save.txt

if [ "$PLATFORM" = pc ]; then
  # Some monitors prefer a smaller mode than their panel (the ASUS XG27JCG 5K prefers
  # 3840x2160). The text console and ly then run upscaled and off-centre on a framebuffer
  # sized for the largest screen. Force the native mode at boot (fake 4K input modes of
  # 1440p monitors excluded, as in hypr/scripts/monitors.py).
  for c in /sys/class/drm/card*-*; do
    [ "$(cat "$c/status" 2>/dev/null)" = connected ] || continue
    pref=$(head -1 "$c/modes"); big=$(sort -t x -k1,1n -k2,2n -u "$c/modes" | tail -1)
    [ -n "$big" ] && [ "$big" != "$pref" ] || continue
    case "$big" in 3840x2160|4096x2160) continue ;; esac
    step "Console: ${c#*card?-} at its native ${big} at boot (prefers ${pref})"
    kernel_args "video=${c#*card?-}:${big}@60"
  done

  step "Firmware updates: fwupd (check with: fwupdmgr get-updates)"
  sudo systemctl enable --now fwupd-refresh.timer 2>/dev/null || true
fi

# =============================================================================
# 5. Power
# =============================================================================
if [ "$PLATFORM" = asahi ]; then
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
fi
# PC laptops keep Fedora's defaults: sleep works (lid = suspend, power button = power off).
if [ "$PLATFORM" = pc ] && [ "$FORM" = desktop ]; then
  # Always-on workhorse (long-running jobs, `claude rc`): nothing may suspend it, not even
  # a keyboard sleep key. Displays are switched off by hand / hypridle (DPMS) instead.
  step "Desktop: never sleep; CPU energy preference balance_power (lower idle power, full boost under load)"
  # undo: sudo systemctl unmask sleep.target suspend.target hibernate.target hybrid-sleep.target suspend-then-hibernate.target
  sudo systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target suspend-then-hibernate.target
  # amd-pstate-epp / intel_pstate (active mode): bias the hardware governor towards
  # efficiency. Cores still boost to max under sustained load. Revert by deleting the file
  # (Fedora's default is balance_performance); try live with:
  #   echo balance_performance | sudo tee /sys/devices/system/cpu/cpufreq/policy*/energy_performance_preference
  if [ -e /sys/devices/system/cpu/cpufreq/policy0/energy_performance_preference ]; then
    echo 'w /sys/devices/system/cpu/cpufreq/policy*/energy_performance_preference - - - - balance_power' \
      | sudo tee /etc/tmpfiles.d/10-cpu-epp.conf
    sudo systemd-tmpfiles --create /etc/tmpfiles.d/10-cpu-epp.conf || true
    echo "EPP now: $(cat /sys/devices/system/cpu/cpufreq/policy0/energy_performance_preference)"
  fi
fi

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
# 6. Dotfiles (symlinked: edit them in this repo)
# =============================================================================
step "Link dotfiles into ~/.config"
mkdir -p "$HOME/.config" "$HOME/.local/bin" "$HOME/Pictures/wallpapers" "$HOME/Pictures/Screenshots"
for app in hypr waybar kitty fuzzel mako fontconfig; do
  target="$HOME/.config/$app"
  if [ -e "$target" ] && [ ! -L "$target" ]; then mv "$target" "$target.bak.$(date +%s)"; fi
  ln -sfn "$DOT/$app" "$target"
done
chmod +x "$DOT"/waybar/scripts/*.sh "$DOT"/hypr/scripts/*.sh "$DOT"/hypr/scripts/*.py
ln -sfn "$HOME/.config/hypr/scripts/wallpaper.sh" "$HOME/.local/bin/wallpaper"
# PCs: monitors.lua is generated on first Hyprland login; `monitors-setup` regenerates it
ln -sfn "$HOME/.config/hypr/scripts/monitors.py" "$HOME/.local/bin/monitors-setup"
if [ "$PLATFORM" = pc ]; then
  # Light hinting for scale-1 (~100 ppi) monitors; scale-2 screens still render like the
  # Macs because Chromium/GTK4 ignore hinting there. Not in git (fontconfig/local.conf).
  ln -sfn lowdpi-hinting.conf "$DOT/fontconfig/local.conf"
fi
fc-cache -f

step "Default wallpaper (only if none chosen yet; change with: wallpaper /path/img)"
WP="/usr/share/backgrounds/f${FEDORA}/default/f${FEDORA}-01-night.jxl"
if [ ! -e "$HOME/Pictures/wallpapers/current" ] && [ -e "$WP" ]; then
  ln -sfn "$WP" "$HOME/Pictures/wallpapers/current"
fi

# =============================================================================
# 7. User session settings
# =============================================================================
step "GTK: no animations, light apps/websites, unhinted subpixel fonts"
gsettings set org.gnome.desktop.interface enable-animations false
gsettings set org.gnome.desktop.interface color-scheme 'prefer-light'
gsettings set org.gnome.desktop.interface gtk-theme 'Adwaita'
gsettings set org.gnome.desktop.interface font-hinting 'none'
gsettings set org.gnome.desktop.interface font-antialiasing 'rgba'
gsettings set org.gnome.desktop.interface font-rgba-order 'rgb'
if [ "$PLATFORM" = pc ]; then
  # PCs: vertical subpixels for a portrait (rotated clockwise) monitor, as in lowdpi-hinting.conf
  gsettings set org.gnome.desktop.interface font-rgba-order 'vrgb'
fi

step "Keyring socket, standard folders"
systemctl --user enable gnome-keyring-daemon.socket
xdg-user-dirs-update

step "Default apps: Brave (web/PDF), Thunar (folders), Loupe (images), mpv (audio/video)"
xdg-settings set default-web-browser brave-browser.desktop || true
for m in x-scheme-handler/http x-scheme-handler/https text/html application/xhtml+xml application/pdf; do
  xdg-mime default brave-browser.desktop "$m"
done
xdg-mime default thunar.desktop inode/directory
mimes() { grep -h '^MimeType=' "/usr/share/applications/$1" | cut -d= -f2 | tr ';' ' '; }
# shellcheck disable=SC2046
xdg-mime default org.gnome.Loupe.desktop $(mimes org.gnome.Loupe.desktop)
# shellcheck disable=SC2046
xdg-mime default mpv.desktop $(mimes mpv.desktop)

# =============================================================================
# 8. Finish
# =============================================================================
if [ "$PLATFORM" = asahi ]; then
  step "Rebuild initramfs for every installed kernel (keyboard + console font apply from early boot)"
  sudo dracut -f --regenerate-all
fi

step "Validate Hyprland config"
Hyprland --verify-config 2>&1 | sed -n '/Config parsing result/,$p'

step "Done. Reboot and pick \"Hyprland\" in ly (not \"Hyprland (uwsm-managed)\")."
if [ "$PLATFORM" = pc ]; then
  echo "On first login the monitors are configured automatically (max resolution/refresh,"
  echo "scale by pixel density). Check with: hyprctl monitors   Re-run with: monitors-setup"
fi
