#!/usr/bin/env bash
# =============================================================================
# Hyprland desktop for the amd64 workhorse: always-on AMD desktop (Ryzen 7 7840HS /
# Radeon 780M mini PC, ASUS XG27JCG 5K, wired network, no
# Bluetooth, no battery). Reproduces the full setup on a fresh *minimal* Fedora install.
# Shared steps: common/lib.sh. Machine dotfiles: this folder (amd64/).
#   Here: AMD video decoding, firmware updates, native console mode, never sleep, CPU
#   energy preference, USB4 authorization, btrfs snapshots + scrub, automatic security
#   updates, firewall, hostname, audio fixes, monitor layout.
#
# Usage (as your normal user, not root; sudo asks for your password once):
#   ./install.sh   (detects the PC and runs this script)   reboot, pick "Hyprland" in ly
# Idempotent: safe to re-run. Output is appended to install.log.
# =============================================================================
source "$(dirname "${BASH_SOURCE[0]}")/../common/lib.sh"

HOSTNAME_WANTED=workhorse

[ "$(uname -m)" = x86_64 ] || { echo "Not an amd64 machine: use macbook/install.sh."; exit 1; }
MODEL="$(cat /sys/class/dmi/id/sys_vendor 2>/dev/null || true) $(cat /sys/class/dmi/id/product_name 2>/dev/null || true)"
GPU=unknown
for v in /sys/class/drm/card*/device/vendor; do
  case "$(cat "$v" 2>/dev/null)" in
    0x1002) GPU=amd ;;
    0x10de) GPU=nvidia ;;
  esac
done
step "Detected: $MODEL | gpu=$GPU | Fedora $FEDORA, $(uname -r)"
[ "$GPU" = amd ] || warn "Written for AMD graphics (found: $GPU). Video decoding and some tuning won't apply."

sudo_keepalive
common_upgrade
common_repos
common_packages \
  fwupd libva-utils \
  bolt \
  snapper libdnf5-plugin-actions btrfsmaintenance \
  dnf5-plugin-automatic

if [ "$GPU" = amd ]; then
  step "AMD: hardware video decoding (H.264/HEVC/AV1) via RPM Fusion's Mesa VA-API driver"
  # Fedora's mesa-va-drivers has the patented codecs disabled; the freeworld build replaces it.
  # Pinned to the exact Fedora mesa version: if RPM Fusion hasn't caught up yet, retry later.
  sudo dnf -y install --allowerasing mesa-va-drivers-freeworld \
    || warn "mesa-va-drivers-freeworld not installable right now (RPM Fusion lagging Fedora's mesa). Re-run later."
fi
common_pin_hyprland
common_browsers
common_nerd_font

# =============================================================================
# Identity, network, login
# =============================================================================
step "Hostname: $HOSTNAME_WANTED"
sudo hostnamectl set-hostname "$HOSTNAME_WANTED"

step "Firewall: close the SSH port (sshd is disabled; reopen with --add-service=ssh)"
sudo firewall-cmd -q --permanent --remove-service=ssh 2>/dev/null || true
sudo firewall-cmd -q --reload
echo "open services: $(sudo firewall-cmd --list-services)"

common_login

# Some monitors prefer a smaller mode than their panel (the ASUS XG27JCG 5K prefers
# 3840x2160). The text console and ly then run upscaled and off-centre. Force the native
# mode at boot (fake 4K input modes of 1440p monitors excluded, as in
# hypr/scripts/monitors.py). Hyprland sets the real modes at login.
for c in /sys/class/drm/card*-*; do
  [ "$(cat "$c/status" 2>/dev/null)" = connected ] || continue
  name=${c#*card?-}; pref=$(head -1 "$c/modes")
  n=$(grep -vxE '3840x2160|4096x2160' "$c/modes" | sort -t x -k1,1n -k2,2n -u | tail -1)
  [ -n "$n" ] && [ "$n" != "$pref" ] || continue
  step "Console: $name at its native ${n} at boot (prefers ${pref})"
  kernel_args "video=$name:${n}@60"
done
step "Console: US keymap, large font for the 5K (as on the Retina Macs)"
printf 'KEYMAP="us"\nFONT="latarcyrheb-sun32"\n' | sudo tee /etc/vconsole.conf
sudo dracut -f

# =============================================================================
# Hardware: firmware, power, USB4
# =============================================================================
step "Firmware updates: fwupd (check with: fwupdmgr get-updates)"
# This board's UEFI has no capsule updates: BIOS updates come from the vendor's site.
sudo systemctl enable --now fwupd-refresh.timer 2>/dev/null || true

# Always-on workhorse (long-running jobs, `claude rc`): nothing may suspend it, not even
# a keyboard sleep key. Displays are switched off by hypridle (DPMS) instead.
step "Never sleep; CPU energy preference balance_power (lower idle power, full boost under load)"
# undo: sudo systemctl unmask sleep.target suspend.target hibernate.target hybrid-sleep.target suspend-then-hibernate.target
sudo systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target suspend-then-hibernate.target
# amd-pstate-epp (active mode): bias the hardware governor towards efficiency. Cores still
# boost to max under sustained load. Revert by deleting the file (Fedora's default is
# balance_performance); try live with:
#   echo balance_performance | sudo tee /sys/devices/system/cpu/cpufreq/policy*/energy_performance_preference
if [ -e /sys/devices/system/cpu/cpufreq/policy0/energy_performance_preference ]; then
  echo 'w /sys/devices/system/cpu/cpufreq/policy*/energy_performance_preference - - - - balance_power' \
    | sudo tee /etc/tmpfiles.d/10-cpu-epp.conf
  sudo systemd-tmpfiles --create /etc/tmpfiles.d/10-cpu-epp.conf || true
  echo "EPP now: $(cat /sys/devices/system/cpu/cpufreq/policy0/energy_performance_preference)"
fi

# USB4 here runs at security level "user": without boltd, docks and storage enclosures
# stay unauthorized. boltd is D-Bus activated; manage devices with: boltctl
step "USB4/Thunderbolt: bolt authorizes docks and enclosures (installed above)"
boltctl list 2>/dev/null || true

# =============================================================================
# Data safety: snapshots, scrub, security updates
# =============================================================================
step "Btrfs snapshots: snapper for / (before/after every dnf transaction) and /home (hourly)"
[ -e /etc/snapper/configs/root ] || sudo snapper -c root create-config /
[ -e /etc/snapper/configs/home ] || sudo snapper -c home create-config /home
# /: only dnf pre/post pairs, keep the last 10 (no timeline)
sudo snapper -c root set-config TIMELINE_CREATE=no NUMBER_LIMIT=10 NUMBER_LIMIT_IMPORTANT=5
# /home: hourly, keep 48 hourly + 7 daily; the user can browse /home/.snapshots
sudo snapper -c home set-config TIMELINE_CREATE=yes TIMELINE_CLEANUP=yes \
  TIMELINE_LIMIT_HOURLY=48 TIMELINE_LIMIT_DAILY=7 TIMELINE_LIMIT_WEEKLY=0 \
  TIMELINE_LIMIT_MONTHLY=0 TIMELINE_LIMIT_QUARTERLY=0 TIMELINE_LIMIT_YEARLY=0 \
  ALLOW_USERS="$USER" SYNC_ACL=yes
sudo systemctl enable --now snapper-timeline.timer snapper-cleanup.timer
# dnf5: pre/post snapshot of / around every transaction (libdnf5 actions plugin)
sudo mkdir -p /etc/dnf/libdnf5-plugins/actions.d
sudo tee /etc/dnf/libdnf5-plugins/actions.d/snapper.actions >/dev/null <<'EOF'
# Snapper pre/post snapshots of / around every dnf transaction (installed by amd64/install.sh)
pre_transaction::::/usr/bin/sh -c echo\ "tmp.cmd=$(ps\ -o\ command\ --no-headers\ -p\ '${pid}')"
pre_transaction::::/usr/bin/sh -c echo\ "tmp.snapper_pre_number=$(snapper\ create\ -t\ pre\ -c\ number\ -p\ -d\ '${tmp.cmd}')"
post_transaction::::/usr/bin/sh -c [\ -n\ "${tmp.snapper_pre_number}"\ ]\ &&\ snapper\ create\ -t\ post\ --pre-number\ "${tmp.snapper_pre_number}"\ -c\ number\ -d\ "${tmp.cmd}"\ ;\ echo\ tmp.snapper_pre_number\ ;\ echo\ tmp.cmd
EOF

step "Btrfs scrub: monthly checksum check of the whole filesystem (/ and /home share it)"
sudo sed -i 's|^BTRFS_SCRUB_MOUNTPOINTS=.*|BTRFS_SCRUB_MOUNTPOINTS="/"|; s|^BTRFS_SCRUB_PERIOD=.*|BTRFS_SCRUB_PERIOD="monthly"|' \
  /etc/sysconfig/btrfsmaintenance
# only the scrub: fstrim.timer already trims, and balance isn't needed on a single disk
sudo systemctl enable --now btrfs-scrub.timer

step "Automatic security updates (daily; everything else stays manual, Hyprland stays pinned)"
sudo tee /etc/dnf/automatic.conf >/dev/null <<'EOF'
# Installed by amd64/install.sh. Run by dnf5-automatic.timer (daily).
[commands]
upgrade_type = security
download_updates = yes
apply_updates = yes
# a kernel/firmware fix waits for the next manual reboot
reboot = never

[emitters]
emit_via = stdio
EOF
sudo systemctl enable --now dnf5-automatic.timer

# =============================================================================
# Dotfiles, session
# =============================================================================
# A monitors.lua generated by monitors-setup before the common/ + amd64/ layout lived in
# dotfiles/hypr/: keep it (a link there pointed at the tracked workhorse layout: not needed)
OLD_MON="$REPO_DIR/dotfiles/hypr/monitors.lua"
if [ -f "$OLD_MON" ] && [ ! -L "$OLD_MON" ] && [ ! -e "$MACHINE_DIR/hypr/monitors.lua" ]; then
  mv "$OLD_MON" "$MACHINE_DIR/hypr/monitors.lua"
fi
common_dotfiles
step "Workhorse dotfiles: monitor layout, audio rules, webcam viewer"
# Monitor layout (ASUS 5K), matched by monitor name. `monitors-setup`
# regenerates a plain monitors.lua for other monitors. Loaded by amd64/hypr/machine.lua.
[ -e "$MACHINE_DIR/hypr/monitors.lua" ] || ln -sfn monitors-workhorse.lua "$MACHINE_DIR/hypr/monitors.lua"
ln -sfn "$MACHINE_DIR/hypr/scripts/monitors.py" "$HOME/.local/bin/monitors-setup"
# WirePlumber: the USB mic's headphone output is hidden (it was picked as the speaker)
ln -sfn "$MACHINE_DIR/wireplumber" "$HOME/.config/wireplumber"
# "Webcam" in the launcher: raw camera image in mpv
mkdir -p "$HOME/.local/share/applications"
ln -sfn "$MACHINE_DIR/applications/webcam.desktop" "$HOME/.local/share/applications/webcam.desktop"

common_session

common_verify
step "Done. Reboot and pick \"Hyprland\" in ly (not \"Hyprland (uwsm-managed)\")."
echo "Set in the BIOS by hand: power on after AC loss (comes back after an outage), and"
echo "HD Audio enabled (when it's off, the 3.5mm jack is missing: 'no codecs found' in dmesg)."
