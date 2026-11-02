# Hyprland on Fedora (Apple silicon MacBooks and an amd64 workhorse)

My personal, fast and quiet Hyprland desktop for Apple silicon MacBooks running
**Fedora Asahi Remix**, and for my **amd64 workhorse** desktop running Fedora. A script per
machine takes a fresh *minimal* install to the full desktop:

| Script | Machine |
|---|---|
| `install-asahi.sh` | Apple silicon MacBooks |
| `install-amd64.sh` | The amd64 workhorse: always-on AMD desktop (Ryzen 7 7840HS mini PC, ASUS 5K + portrait Dell) |
| `lib/common.sh` | Steps both share (sourced by the two scripts) |
| `install.sh` | Detects the machine and runs the right script |

- **No animations anywhere**: Hyprland, the lock screen, the bar, GTK apps and the terminal.
- **Neutral grey theme** for the desktop, with light-mode apps and websites.
- **Battery friendly**: about 4 W idle with the screen on and about 1.4 W with the lid
  closed on an M1 Air. Charging stops at 90%, and the laptop shuts down cleanly at 2%.
- **Never sleeps**: closing the lid locks and turns off the screen. Sleep (s2idle) is
  unreliable on Asahi and only saves about 1 W.
- Fonts tuned for the Retina panels, hardware-detected screen scale, and notch support
  on the 14"/16" MacBook Pro.

Tested on a **MacBook Air M1** with Fedora Asahi Remix 44 and Hyprland 0.57.
Supported but not yet tested on real hardware:
- **MacBook Pro 14"/16" (M1 Pro/Max)**

The amd64 script is written for (and tested on) the workhorse. Other AMD PCs work, but
its monitor layout, audio rules and font tuning are specific to that desk.

---

## Install

### 1. Install Fedora Asahi Remix (Minimal)

From macOS, in Terminal:

```sh
curl https://fedora-asahi-remix.org/install | sh
```

Pick **Fedora Asahi Remix … Minimal** and follow the prompts. Boot into it and finish the
first-boot setup: create your user and make it an **administrator** (in the `wheel` group).

<details><summary><b>On a PC instead</b></summary>

Download **Fedora Everything** (the netinstall ISO) from fedoraproject.org, boot it, and in
*Software Selection* choose **Minimal Install**. Create your user as an **administrator**.
Wired network works out of the box. For Wi-Fi, use `nmtui` after the first boot.

`./install.sh` detects the PC and runs `install-amd64.sh`.
</details>

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
| Keyboard (PC) | **Alt and Super swapped** (`altwin:swap_alt_win`, in `hyprland.lua`): the mod key sits next to the space bar, like Cmd on the Macs |
| Keyboard (Mac) | `hid_apple`: **Cmd and Option swapped**, **Fn and left Ctrl swapped**, F-keys first. Built into the initramfs, so it applies from early boot. |
| Power (Mac) | Lid/power key locks, sleep disabled |
| Power (workhorse) | Never sleeps (sleep targets masked: an always-on workhorse). CPU energy preference `balance_power` (`/etc/tmpfiles.d/10-cpu-epp.conf`): lower idle power, full boost under load |
| Battery (Mac) | 90% charge limit if the firmware supports it (80% if it only allows that), clean shutdown at 2%, low-battery notifications at 15% and 5% |
| Workhorse | Hostname `workhorse`, monitor layout (see below), AMD hardware video decoding (`mesa-va-drivers-freeworld`), firmware updates via `fwupd`, USB4 device authorization (`bolt`, `boltctl`), Print-key screenshots, mouse without acceleration |
| Data safety (workhorse) | Btrfs snapshots with snapper: `/` before and after every `dnf` transaction (last 10 kept), `/home` hourly (48 hourly + 7 daily kept, browse `/home/.snapshots`). Monthly btrfs scrub. Security updates installed daily (`dnf5-automatic`), everything else manual. **Not a backup**: nothing leaves the disk yet. |
| Audio (workhorse) | The USB mic's headphone output and the webcam's microphone are hidden (`dotfiles/wireplumber`): sound goes to real outputs, the dedicated mic is the only input. "Webcam" in the launcher shows the raw camera image (mpv). |
| Apps | Thunar (+ USB/phone/trash support, thumbnails, archives), Brave (default browser), Firefox + uBlock Origin (work apps), Loupe (images), mpv (video/audio), GNOME Calculator, git, vim, htop, btop |
| Codecs | RPM Fusion ffmpeg (H.264, HEVC, VP9, AV1) |
| Fonts | Brave defaults: Noto Sans / Noto Serif / JetBrains Mono. JetBrainsMono Nerd Font (bar icons), Inter/Liberation/Noto/Roboto in place of Apple and Windows web fonts, color emoji, CJK. No hinting, subpixel RGB antialiasing. The workhorse adds light hinting and vertical subpixel order (`vrgb`) for the portrait Dell; the 5K at scale 2 looks the same either way. |
| Security | SSH server disabled (re-enable: `sudo systemctl enable --now sshd`); on the workhorse the firewall also closes its port |
| Screen sharing | `hyprland-session.target` starts `graphical-session.target`, which the desktop portal needs (Meet/Zoom screen sharing, file pickers) |
| Console and login | Black and white only (console palette + ly colours). On the workhorse the 5K starts in its native mode, so ly is centred and sharp |
| Misc | gnome-keyring unlocked at login, standard home folders, power tools (`sensors`, `powertop`) |

Repositories added: COPR `sdegler/hyprland`, RPM Fusion free, and Brave's official repo.

### Per-machine settings (detected automatically)

| Machine | Screen | Notes |
|---|---|---|
| MacBook Air M1 / Pro 13" | 2560×1600, scale 1.667 (looks like 1536×960) | |
| MacBook Pro 14" | 3024×1964 @ 120 Hz, scale 2 (looks like 1512×982) | Adds the kernel argument `appledrm.show_notch=1`; the bar fills the strip beside the notch |
| MacBook Pro 16" | 3456×2234 @ 120 Hz, scale 2 (looks like 1728×1117) | Same notch handling |
| Workhorse | ASUS 5K + portrait Dell | Tracked layout (see below) |

### Workhorse monitors

`dotfiles/hypr/monitors-workhorse.lua` (tracked; `install-amd64.sh` links
`monitors.lua` to it). Monitors are matched by name, not port, so moving a cable changes
nothing:
- **ASUS XG27JCG**: 5120×2880 @ 120 Hz, scale 2, primary, workspaces 1–8 and 10.
  The monitor offers 5K @ 165 Hz, but this APU's display engine can't drive it, and the
  monitor rejects anything in between.
- **Dell U2717D**: rotated 90° clockwise (portrait, 1440×2560), right of the ASUS and
  vertically centred, workspace 9 (Super+9). Two windows stack top and bottom, each
  using the full width. 60 Hz: its scaler rejects 68 Hz and up on HDMI and DP (65 Hz
  works over DP, not worth a USB4 port).

**Other monitors**: `monitors-setup` (`hypr/scripts/monitors.py`) writes a fresh
`monitors.lua` from the connected monitors (the tracked layout stays). For each monitor it picks:
- the **native resolution**: the largest mode offered at 59 Hz or more, even when the
  monitor prefers a smaller one (the ASUS XG27JCG 5K prefers 3840×2160). Fake 4K input
  modes on 1440p monitors are ignored
- the **highest refresh rate** offered at that resolution
- the **scale from pixel density**: 2 at 190+ ppi (27" 5K), 1.5 at 150+ ppi (27" 4K),
  otherwise 1 (27" 1440p), so text is the same size on every screen
- **VRR** while a fullscreen app runs, on monitors that can do 100 Hz or more
- a **position** with the highest-resolution monitor on the left and the others to its right

Check the result with `hyprctl monitors`.

If 120 Hz isn't available, Hyprland falls back to the panel's standard mode.

---

## Keys

On the **workhorse**, Alt and Super are swapped: **physical Alt is Super** (next to the
space bar) and the Windows key sends Alt. **Print** captures an area and **Shift+Print**
the whole screen. Everything else in the table works the same. Super+9 is the Dell.

On the **Macs**, because Cmd and Option are swapped, **physical ⌘ Cmd sends Alt**, and **physical ⌥ Option
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

**Bar on PCs without Wi-Fi** (`config-wired.jsonc`): the ethernet link (right-click for
settings), live download/upload in bits per second (kb/s, Mb/s, Gb/s) in place of
Bluetooth, and live APU power in watts (CPU + GPU + SoC, 5-second average; wall power is higher).

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
(`hypr`, `waybar`, `kitty`, `fuzzel`, `mako`, `fontconfig`; on the workhorse also
`wireplumber` and the Webcam launcher), so edit them in the repo.

- **Wallpaper**: `wallpaper /path/to/image` (png/jpg/webp/jxl) sets it immediately and
  keeps it after a reboot.
- **Screen scale or mode**: Macs: the `MONITORS` section of `dotfiles/hypr/hyprland.lua`;
  workhorse: `dotfiles/hypr/monitors-workhorse.lua`. Apply changes with `hyprctl reload`.
- **Mouse speed** (workhorse, no acceleration): `sensitivity` in `hyprland.lua`, -1.0 to
  1.0, roughly a multiplier of 1 + sensitivity (-0.3 ≈ 70%).
- **Firefox address bar**: `dotfiles/firefox/policies.json` (bookmarks only, never
  searches); reinstall it with the `install` line in `lib/common.sh`.
- **Bar**: `dotfiles/waybar/config.jsonc` and `style.css`. PCs without Wi-Fi use
  `config-wired.jsonc` on top of it. On the notched Pros,
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

Workhorse:

```sh
snapper -c home list                # /home snapshots; files are in /home/.snapshots/N/snapshot
sudo snapper -c root list           # / snapshots, one pre/post pair per dnf transaction
sudo snapper -c root undochange N..M   # undo what a dnf transaction changed in /
boltctl                             # USB4/Thunderbolt devices (boltctl authorize <uuid>)
sudo btrfs scrub status /           # last integrity check
fwupdmgr get-updates                # firmware (the BIOS itself only from the vendor's site)
```

Macs:

```sh
sensors macsmc_hwmon-*      # Total system power and SoC (heatpipe) power
sudo powertop               # Which processes wake the CPU most
cat /sys/class/power_supply/macsmc-battery/charge_control_end_threshold   # Charge limit
echo 100 | sudo tee /sys/class/power_supply/macsmc-battery/charge_control_end_threshold  # Charge to 100% until the next reboot
```

## Undo the "never sleep" policy

```sh
sudo systemctl unmask sleep.target suspend.target hibernate.target hybrid-sleep.target suspend-then-hibernate.target
sudo rm /etc/systemd/logind.conf.d/10-lid-lock.conf    # Macs only
```

## Troubleshooting

- **Install failed partway**: read `install.log`, fix the cause, then run `./install.sh`
  again. Every step is safe to repeat.
- **Screen sharing doesn't work**: `systemctl --user is-active graphical-session.target`
  must say `active` (started by `hyprland-session.target` at login).
- **Hyprland problems**: run `hyprctl configerrors`. Logs are in
  `$XDG_RUNTIME_DIR/hypr/*/hyprland.log`.
- **Keys feel wrong after a kernel update**: rebuild the initramfs with
  `sudo dracut -f --regenerate-all` and reboot.
