# shellcheck shell=bash
# =============================================================================
# Shared by macbook/install.sh and amd64/install.sh (sourced, not run). Holds the helpers
# and the steps both machines run identically; each machine's script calls them in order
# around its own steps. Nothing here checks the platform.
#   COMMON       common/: dotfiles every machine shares (linked into ~/.config)
#   MACHINE_DIR  macbook/ or amd64/: the sourcing script's folder, linked as
#                ~/.config/hypr-platform (machine.lua, machine-only scripts and configs)
# =============================================================================
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMMON="$REPO_DIR/common"
MACHINE_DIR="$(cd "$(dirname "${BASH_SOURCE[1]}")" && pwd)"
exec > >(tee -a "$REPO_DIR/install.log") 2>&1

step() { printf '\n\033[1;34m==> [%s] %s\033[0m\n' "$(date '+%F %T')" "$*"; }
warn() { printf '\033[1;33m!!  %s\033[0m\n' "$*"; }

[ "$EUID" -ne 0 ] || { echo "Run as your normal user, not root."; exit 1; }
FEDORA=$(rpm -E %fedora)

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

# Ask for the sudo password once and keep it alive (the full install takes >5 min)
sudo_keepalive() {
  sudo -v
  while sleep 50; do sudo -n true; done 2>/dev/null &
  SUDO_KEEPALIVE=$!
  trap 'kill $SUDO_KEEPALIVE 2>/dev/null' EXIT
}

common_upgrade() {
  step "Update the base system first (avoids partial upgrades with COPR packages)"
  sudo dnf -y upgrade --refresh
}

common_repos() {
  step "Repositories: Hyprland COPR, RPM Fusion free, Brave"
  sudo dnf -y install dnf5-plugins policycoreutils-python-utils
  # sdegler/hyprland builds for aarch64 and x86_64 (solopasha doesn't for F44 aarch64)
  sudo dnf -y copr enable sdegler/hyprland
  # Full ffmpeg (HEVC etc.)
  sudo dnf -y install "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-${FEDORA}.noarch.rpm"
  # Brave (also runs fine on Asahi's 16K pages)
  sudo dnf config-manager addrepo --overwrite \
    --from-repofile=https://brave-browser-rpm-release.s3.brave.com/brave-browser.repo
}

# Packages every machine gets; the platform scripts add their own (COMMON_PKGS + extra)
COMMON_PKGS=(
  # compositor + ecosystem
  hyprland xdg-desktop-portal-hyprland xdg-desktop-portal-gtk hyprpolkitagent
  hyprlock hypridle hyprpaper "f${FEDORA}-backgrounds-base"
  # bar, login manager, terminal, launcher, notifications
  waybar ly kitty fuzzel mako libnotify
  # audio / network GUIs (opened from the bar)
  pipewire-pulseaudio pavucontrol network-manager-applet
  # media keys, screenshots, clipboard
  playerctl grim slurp wl-clipboard
  # diagnostics: `sensors`, `sudo powertop`
  powertop lm_sensors
  # secrets (unlocked at login by ly's PAM)
  gnome-keyring gnome-keyring-pam
  # file manager + trash/USB/phones, thumbnails, archives
  Thunar thunar-volman thunar-archive-plugin tumbler ffmpegthumbnailer
  gvfs gvfs-mtp file-roller
  # everyday apps / tools
  xdg-user-dirs xdg-utils git vim-enhanced htop btop loupe gnome-calculator mpv python3
  # browsers: Brave = default, Firefox (+ uBlock Origin) = logged-in work apps
  brave-browser firefox mozilla-ublock-origin
  # fonts: UI/bar + good on-screen replacements for web fonts + emoji + CJK
  jetbrains-mono-fonts-all fontawesome-fonts-all
  liberation-sans-fonts liberation-serif-fonts liberation-mono-fonts
  google-noto-serif-vf-fonts google-noto-color-emoji-fonts rsms-inter-vf-fonts
  google-roboto-fonts default-fonts-cjk-sans
)

# usage: common_packages extra-pkg...
common_packages() {
  step "Install packages"
  sudo dnf -y install --refresh "${COMMON_PKGS[@]}" "$@"
  # RPM Fusion ffmpeg replaces Fedora's ffmpeg-free libraries. RPM Fusion sometimes lags a
  # Fedora update by a few days; then this can't resolve yet: don't abort, just re-run later.
  sudo dnf -y install --allowerasing ffmpeg \
    || warn "RPM Fusion ffmpeg not installable right now (repo lagging?). Re-run the installer later."
}

common_pin_hyprland() {
  step "Pin Hyprland packages (COPR updates can break the Lua config; upgrade on purpose, see README)"
  local HYPR_PKGS
  mapfile -t HYPR_PKGS < <(rpm -qa --qf '%{name}\n' | grep -E '^(hypr|aquamarine$|xdg-desktop-portal-hyprland$)' | sort -u)
  sudo dnf versionlock add "${HYPR_PKGS[@]}"
}

common_browsers() {
  step "Firefox: address bar never web-searches, suggests from bookmarks only, never history (policy)"
  # Firefox always needs a default engine; with keyword.enabled off it is never used from
  # the address bar. Change suggestions in dotfiles/firefox/policies.json, check about:policies.
  sudo install -Dm644 "$COMMON/firefox/policies.json" /etc/firefox/policies/policies.json

  step "Brave default fonts for new profiles (pages without their own CSS fonts)"
  # Applied on Brave's first run; Standard/Sans = Noto Sans, Serif = Noto Serif, Fixed = JetBrains Mono
  echo '{"webkit":{"webprefs":{"fonts":{"standard":{"Zyyy":"Noto Sans"},"sansserif":{"Zyyy":"Noto Sans"},"serif":{"Zyyy":"Noto Serif"},"fixed":{"Zyyy":"JetBrains Mono"}}}}}' \
    | sudo tee /opt/brave.com/brave/initial_preferences >/dev/null
}

common_nerd_font() {
  step "JetBrainsMono Nerd Font (bar icons; not packaged in Fedora)"
  local NF_DIR="$HOME/.local/share/fonts/JetBrainsMonoNerd" tmp
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
}

common_login() {
  step "Security: no SSH server (re-enable with: sudo systemctl enable --now sshd)"
  sudo systemctl disable --now sshd.service 2>/dev/null || true

  step "ly on tty2, boot to graphical target"
  sudo systemctl disable getty@tty2.service || true
  sudo systemctl enable ly@tty2.service
  sudo systemctl set-default graphical.target

  step "ly + text console: black and white only, remember last user (SELinux label for save file)"
  # Console palette: black, mid grey (bright black), everything else white. Applies to the
  # text console and ly (boot messages, errors and the login box), so nothing is blue/red.
  local GREY=0,255,255,255,255,255,255,255,128,255,255,255,255,255,255,255
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
}

common_dotfiles() {
  step "Link dotfiles into ~/.config (common/ + ~/.config/hypr-platform -> $(basename "$MACHINE_DIR")/)"
  mkdir -p "$HOME/.config" "$HOME/.local/bin" "$HOME/Pictures/wallpapers" "$HOME/Pictures/Screenshots"
  local app target
  for app in hypr waybar kitty fuzzel mako fontconfig; do
    target="$HOME/.config/$app"
    if [ -e "$target" ] && [ ! -L "$target" ]; then mv "$target" "$target.bak.$(date +%s)"; fi
    ln -sfn "$COMMON/$app" "$target"
  done
  # the machine's own folder; common/hypr/hyprland.lua loads hypr/machine.lua from it
  ln -sfn "$MACHINE_DIR" "$HOME/.config/hypr-platform"
  # graphical-session.target for the portals (screen sharing), started by hyprland.lua
  mkdir -p "$HOME/.config/systemd/user"
  ln -sfn "$COMMON/systemd/hyprland-session.target" "$HOME/.config/systemd/user/hyprland-session.target"
  systemctl --user daemon-reload
  find "$COMMON" "$MACHINE_DIR" -path '*/scripts/*' \( -name '*.sh' -o -name '*.py' \) -exec chmod +x {} +
  # Before the common/ + macbook/ + amd64/ layout everything lived in dotfiles/; git leaves
  # that folder behind holding only the per-machine links (monitors.lua, local.conf).
  if [ -d "$REPO_DIR/dotfiles" ] && [ -z "$(find "$REPO_DIR/dotfiles" ! -type d ! -type l)" ]; then
    rm -rf "$REPO_DIR/dotfiles"
  fi
  ln -sfn "$HOME/.config/hypr/scripts/wallpaper.sh" "$HOME/.local/bin/wallpaper"

  step "Default wallpaper (only if none chosen yet; change with: wallpaper /path/img)"
  local WP="/usr/share/backgrounds/f${FEDORA}/default/f${FEDORA}-01-night.jxl"
  if [ ! -e "$HOME/Pictures/wallpapers/current" ] && [ -e "$WP" ]; then
    ln -sfn "$WP" "$HOME/Pictures/wallpapers/current"
  fi
}

common_session() {
  step "GTK: no animations, light apps/websites, unhinted subpixel fonts"
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
  local m
  for m in x-scheme-handler/http x-scheme-handler/https text/html application/xhtml+xml application/pdf; do
    xdg-mime default brave-browser.desktop "$m"
  done
  xdg-mime default thunar.desktop inode/directory
  mimes() { grep -h '^MimeType=' "/usr/share/applications/$1" | cut -d= -f2 | tr ';' ' '; }
  # shellcheck disable=SC2046
  xdg-mime default org.gnome.Loupe.desktop $(mimes org.gnome.Loupe.desktop)
  # shellcheck disable=SC2046
  xdg-mime default mpv.desktop $(mimes mpv.desktop)
}

common_verify() {
  fc-cache -f
  step "Validate Hyprland config"
  Hyprland --verify-config 2>&1 | sed -n '/Config parsing result/,$p'
}
