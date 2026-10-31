#!/usr/bin/env bash
# =============================================================================
# Hyprland desktop for Fedora Asahi Remix (Apple silicon MacBooks)
#
# Reproduces the full setup on a fresh *minimal* Fedora Asahi install.
# Tested on: MacBook Air M1 (Fedora Asahi Remix 44). Hardware-specific values
# (screen scale, backlight, battery) are detected at runtime, so it also suits
# MacBook Pro M1 Pro/Max.
#
# Usage (as your normal user, not root; sudo will ask for your password):
#   sudo dnf install -y git
#   git clone https://github.com/benjamin-ipinfo/hyprland-config.git ~/Git/hyprland-config
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
[ "$EUID" -ne 0 ] || { echo "Run as your normal user, not root."; exit 1; }
FEDORA=$(rpm -E %fedora)
MODEL=$(tr -d '\0' < /proc/device-tree/model 2>/dev/null || echo unknown)
step "Detected: $MODEL, Fedora $FEDORA, $(uname -r)"

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
step "Repositories: Hyprland COPR, ungoogled-chromium COPR, RPM Fusion free, Brave"
sudo dnf -y install dnf5-plugins policycoreutils-python-utils
# Hyprland is not in Fedora; sdegler/hyprland builds for aarch64 (solopasha doesn't for F44)
sudo dnf -y copr enable sdegler/hyprland
# Official Fedora build linked from the ungoogled-chromium GitHub README
sudo dnf -y copr enable wojnilowicz/ungoogled-chromium
# Full ffmpeg (HEVC etc.)
sudo dnf -y install "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-${FEDORA}.noarch.rpm"
# Brave (runs fine on Asahi's 16K pages)
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
  # power diagnostics: `sensors`, `sudo powertop`; upower does the 2% power-off
  powertop lm_sensors upower
  # secrets (unlocked at login by ly's PAM)
  gnome-keyring gnome-keyring-pam
  # file manager + trash/USB/phones, thumbnails, archives
  Thunar thunar-volman thunar-archive-plugin tumbler ffmpegthumbnailer
  gvfs gvfs-mtp file-roller
  # everyday apps / tools
  xdg-user-dirs xdg-utils git vim-enhanced htop btop loupe gnome-calculator mpv
  # browsers: Brave = default, ungoogled-chromium = logged-in work apps
  brave-browser ungoogled-chromium
  # fonts: UI/bar + good on-screen replacements for web fonts + emoji + CJK
  jetbrains-mono-fonts-all fontawesome-fonts-all
  liberation-sans-fonts liberation-serif-fonts liberation-mono-fonts
  google-noto-serif-vf-fonts google-noto-color-emoji-fonts rsms-inter-vf-fonts
  google-roboto-fonts default-fonts-cjk-sans
)
sudo dnf -y install --refresh "${PKGS[@]}"
# RPM Fusion ffmpeg replaces Fedora's ffmpeg-free libraries
sudo dnf -y install --allowerasing ffmpeg

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
# 3. Keyboard + console (baked into the initramfs, rebuilt at the end)
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
  NOTCH=appledrm.show_notch=1
  # current kernels (BLS entries)
  sudo grubby --update-kernel=ALL --args="$NOTCH"
  # future kernels: kernel-install reads /etc/kernel/cmdline, grub2-mkconfig reads /etc/default/grub
  if [ -f /etc/kernel/cmdline ] && ! grep -q "$NOTCH" /etc/kernel/cmdline; then
    sudo sed -i "1 s/\$/ $NOTCH/" /etc/kernel/cmdline
  fi
  if [ -f /etc/default/grub ] && ! grep -q "$NOTCH" /etc/default/grub; then
    sudo sed -i "s/^GRUB_CMDLINE_LINUX_DEFAULT=\"\\(.*\\)\"/GRUB_CMDLINE_LINUX_DEFAULT=\"\\1 $NOTCH\"/" /etc/default/grub
  fi
  sudo grubby --info=ALL | grep -E '^(kernel|args)='
fi

# =============================================================================
# 4. Services, login manager
# =============================================================================
step "Bluetooth, ly on tty2, boot to graphical target"
sudo systemctl enable bluetooth.service
sudo systemctl disable getty@tty2.service || true
sudo systemctl enable ly@tty2.service
sudo systemctl set-default graphical.target

step "ly: no animation, plain VT colours, remember last user (SELinux label for save file)"
sudo sed -i 's/^animation = .*/animation = none/; s/^full_color = .*/full_color = false/; s/^save = .*/save = true/' \
  /etc/ly/config.ini
# ly runs as xdm_t and may not create files in /etc; pre-create a writable save file
sudo semanage fcontext -a -t xdm_var_lib_t '/etc/ly/save\.txt' 2>/dev/null \
  || sudo semanage fcontext -m -t xdm_var_lib_t '/etc/ly/save\.txt'
sudo touch /etc/ly/save.txt
sudo restorecon /etc/ly/save.txt

# =============================================================================
# 5. Power: lid locks (never sleeps), battery care
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

step "Battery: stop charging at 90% (falls back to 80% if this SMC firmware only allows 80/100)"
LIMIT_FILE=/sys/class/power_supply/macsmc-battery/charge_control_end_threshold
LIMIT=90
echo 90 | sudo tee "$LIMIT_FILE" >/dev/null 2>&1 || true
if [ "$(cat "$LIMIT_FILE" 2>/dev/null)" != 90 ]; then
  LIMIT=80
  echo 80 | sudo tee "$LIMIT_FILE" >/dev/null 2>&1 || true
fi
echo "ACTION==\"add|change\", SUBSYSTEM==\"power_supply\", KERNEL==\"macsmc-battery\", ATTR{charge_control_end_threshold}=\"$LIMIT\"" \
  | sudo tee /etc/udev/rules.d/90-battery-charge-limit.rules
sudo udevadm control --reload
echo "charge limit now: $(cat "$LIMIT_FILE" 2>/dev/null || echo 'not supported')%"

step "UPower: clean power-off at 2% (low-battery notifications: hypr/scripts/battery-notify.sh)"
sudo mkdir -p /etc/UPower/UPower.conf.d
printf '[UPower]\nCriticalPowerAction=PowerOff\nPercentageAction=2.0\n' \
  | sudo tee /etc/UPower/UPower.conf.d/10-poweroff.conf

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
chmod +x "$DOT"/waybar/scripts/*.sh "$DOT"/hypr/scripts/*.sh
ln -sfn "$HOME/.config/hypr/scripts/wallpaper.sh" "$HOME/.local/bin/wallpaper"
fc-cache -f

step "Default wallpaper (only if none chosen yet; change with: wallpaper /path/img)"
WP="/usr/share/backgrounds/f${FEDORA}/default/f${FEDORA}-01-night.jxl"
if [ ! -e "$HOME/Pictures/wallpapers/current" ] && [ -e "$WP" ]; then
  ln -sfn "$WP" "$HOME/Pictures/wallpapers/current"
fi

# =============================================================================
# 7. User session settings
# =============================================================================
step "GTK: no animations, light apps/websites, unhinted subpixel fonts (227+ ppi panels)"
gsettings set org.gnome.desktop.interface enable-animations false
gsettings set org.gnome.desktop.interface color-scheme 'prefer-light'
gsettings set org.gnome.desktop.interface gtk-theme 'Adwaita'
gsettings set org.gnome.desktop.interface font-hinting 'none'
gsettings set org.gnome.desktop.interface font-antialiasing 'rgba'
gsettings set org.gnome.desktop.interface font-rgba-order 'rgb'

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
step "Rebuild initramfs for every installed kernel (keyboard + console font apply from early boot)"
sudo dracut -f --regenerate-all

step "Validate Hyprland config"
Hyprland --verify-config 2>&1 | sed -n '/Config parsing result/,$p'

step "Done. Reboot and pick \"Hyprland\" in ly (not \"Hyprland (uwsm-managed)\")."
