# Hyprland on Fedora Asahi (Apple silicon MacBooks)

My personal, fast and quiet Hyprland desktop for Apple silicon MacBooks running
**Fedora Asahi Remix**. One script takes a fresh *minimal* install to the full desktop.

- **No animations anywhere**: Hyprland, the lock screen, the bar, GTK apps and the terminal.
- **Neutral grey theme** for the desktop, with light-mode apps and websites.
- **Battery friendly**: about 4 W idle with the screen on and about 1.4 W with the lid
  closed on an M1 Air. Charging stops at 90%, and the laptop shuts down cleanly at 2%.
- **Never sleeps**: closing the lid locks and turns off the screen. Sleep (s2idle) is
  unreliable on Asahi and only saves about 1 W.
- Fonts tuned for the Retina panels, hardware-detected screen scale, and notch support
  on the 14"/16" MacBook Pro.

Tested on a **MacBook Air M1** with Fedora Asahi Remix 44 and Hyprland 0.57.
The **MacBook Pro 14"/16" (M1 Pro/Max)** path is supported but hasn't been tested on
real hardware yet.

---

## Install

### 1. Install Fedora Asahi Remix (Minimal)

From macOS, in Terminal:

```sh
curl https://fedora-asahi-remix.org/install | sh
```

Pick **Fedora Asahi Remix … Minimal** and follow the prompts. Boot into it and finish the
first-boot setup: create your user and make it an **administrator** (in the `wheel` group).

### 2. Get online and install git

Log in on the text console, then:

```sh
nmcli device wifi connect "YOUR-SSID" --ask    # or run `nmtui` for a menu
sudo dnf install -y git
```

### 3. Clone and run

```sh
mkdir -p ~/Git && cd ~/Git
git clone https://github.com/benjamin-ipinfo/hyprland-config.git
cd hyprland-config
./install.sh
```

Run it as your **normal user**, not with `sudo`. It asks for your password once and
takes 10–20 minutes, depending on your connection. Everything is logged to
`install.log`, and the script is safe to re-run.

### 4. Reboot

```sh
sudo reboot
```

At the **ly** login screen, choose the session **`Hyprland`** with ← →. Don't pick
"Hyprland (uwsm-managed)". Log in, and ly remembers your choice from then on.

---

## What the script does

| Area | What you get |
|---|---|
| Desktop | Hyprland (Lua config), waybar, hyprlock, hypridle, hyprpaper, mako notifications, fuzzel launcher, kitty terminal |
| Login | `ly` on tty2, no animation, remembers the last user and session |
| Keyboard | `hid_apple`: **Cmd and Option swapped**, **Fn and left Ctrl swapped**, F-keys first. Built into the initramfs, so it applies from early boot. |
| Power | Lid/power key locks, sleep disabled, 90% charge limit (80% if the firmware only allows that), clean shutdown at 2%, low-battery notifications at 15% and 5% |
| Apps | Thunar (+ USB/phone/trash support, thumbnails, archives), Brave (default browser), Firefox + uBlock Origin (work apps), Loupe (images), mpv (video/audio), GNOME Calculator, git, vim, htop, btop |
| Codecs | RPM Fusion ffmpeg (H.264, HEVC, VP9, AV1) |
| Fonts | Brave defaults: Noto Sans / Noto Serif / JetBrains Mono. JetBrainsMono Nerd Font (bar icons), Inter/Liberation/Noto/Roboto in place of Apple and Windows web fonts, color emoji, CJK. No hinting, subpixel RGB antialiasing. |
| Security | SSH server disabled (re-enable: `sudo systemctl enable --now sshd`) |
| Misc | gnome-keyring unlocked at login, standard home folders, power tools (`sensors`, `powertop`) |

Repositories added: COPR `sdegler/hyprland`, RPM Fusion free, and Brave's official repo.

### Per-machine settings (detected automatically)

| Machine | Screen | Notes |
|---|---|---|
| MacBook Air M1 / Pro 13" | 2560×1600, scale 1.667 (looks like 1536×960) | |
| MacBook Pro 14" | 3024×1964 @ 120 Hz, scale 2 (looks like 1512×982) | Adds the kernel argument `appledrm.show_notch=1`; the bar fills the strip beside the notch |
| MacBook Pro 16" | 3456×2234 @ 120 Hz, scale 2 (looks like 1728×1117) | Same notch handling |

If 120 Hz isn't available, Hyprland falls back to the panel's standard mode.

---

## Keys

Because Cmd and Option are swapped, **physical ⌘ Cmd sends Alt**, and **physical ⌥ Option
is the Super key** (shown as *Super* below). The physical left **Ctrl** key acts as
**Fn**, so the media and brightness keys on the top row need left Ctrl held down.

| Keys | Action |
|---|---|
| ⌘ Space (Alt+Space) or Super+Space | App launcher |
| ⌘ F4 (Alt+F4) or Super+Q | Close window |
| Super+Return | Terminal (kitty) |
| Super+E | File manager (Thunar) |
| Super+L | Lock |
| Super+F / Super+V / Super+J | Fullscreen / toggle floating / toggle split |
| Super+←→↑↓ | Move focus |
| Super+1…0 / Super+Shift+1…0 | Switch workspace / move window to workspace |
| Super+Alt+3 / Super+Alt+4 | Screenshot of the full screen / a selected area (saved to `~/Pictures/Screenshots` and copied to the clipboard) |
| Super+drag / Super+right-drag | Move / resize a window |
| Brightness keys | Screen brightness |
| Shift+brightness keys | Keyboard backlight |
| Super+Shift+E | Log out of Hyprland |
| 3-finger swipe | Switch workspace |

**Bar** (top right): click Wi-Fi to open a picker that scans and connects to networks;
right-click it for advanced settings. Click Bluetooth for blueman. On volume, click for
the mixer, right-click to mute and scroll to adjust. On brightness, scroll to change the
screen, click to step the keyboard light and right-click to turn it off. The `W` module
shows the current battery draw.

**Idle**: the screen locks after 5 minutes and turns off after 6 minutes, except while a
window is fullscreen (video, slides). Key repeat is macOS-fast: 225 ms delay, 40/s.

---

## Customizing

All configs live in `dotfiles/` and are **symlinked** into `~/.config`
(`hypr`, `waybar`, `kitty`, `fuzzel`, `mako`, `fontconfig`), so edit them in the repo.

- **Wallpaper**: `wallpaper /path/to/image` (png/jpg/webp/jxl) sets it immediately and
  keeps it after a reboot.
- **Screen scale or mode**: the `MONITORS` section of `dotfiles/hypr/hyprland.lua`.
  Apply changes with `hyprctl reload`.
- **Bar**: `dotfiles/waybar/config.jsonc` and `style.css`. On the notched Pros,
  `config-notch.jsonc` overrides the height and layout.
- **Check the config**: `Hyprland --verify-config`.

Hyprland 0.57 uses a **Lua** config (`hyprland.lua`). Most guides online still show the
old `hyprland.conf` syntax, which no longer works. `hyprctl dispatch` also takes Lua now,
for example `hyprctl dispatch 'hl.dsp.dpms({ action = "off" })'`.

## Updating Hyprland

Hyprland and its libraries are **pinned** (`dnf versionlock`), so a routine `sudo dnf upgrade`
can't pull in a release that breaks the config and leaves you at a broken login. To upgrade
on purpose:

```sh
sudo dnf versionlock clear                   # unpin
sudo dnf upgrade --refresh
Hyprland --verify-config                     # must say "config ok" before you log out
sudo dnf versionlock add $(rpm -qa --qf '%{name}\n' | grep -E '^(hypr|aquamarine$|xdg-desktop-portal-hyprland$)')
```

## Useful commands

```sh
sensors macsmc_hwmon-*      # Total system power and SoC (heatpipe) power
sudo powertop               # Which processes wake the CPU most
cat /sys/class/power_supply/macsmc-battery/charge_control_end_threshold   # Charge limit
echo 100 | sudo tee /sys/class/power_supply/macsmc-battery/charge_control_end_threshold  # Charge to 100% until the next reboot
```

## Undo the "never sleep" policy

```sh
sudo systemctl unmask sleep.target suspend.target hibernate.target hybrid-sleep.target suspend-then-hibernate.target
sudo rm /etc/systemd/logind.conf.d/10-lid-lock.conf
```

## Troubleshooting

- **Install failed partway**: read `install.log`, fix the cause, then run `./install.sh`
  again. Every step is safe to repeat.
- **Hyprland problems**: run `hyprctl configerrors`. Logs are in
  `$XDG_RUNTIME_DIR/hypr/*/hyprland.log`.
- **Keys feel wrong after a kernel update**: rebuild the initramfs with
  `sudo dracut -f --regenerate-all` and reboot.
