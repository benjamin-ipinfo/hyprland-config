-- Hyprland config — Apple silicon MacBooks (Fedora Asahi) and amd64 PCs (Fedora)
-- Hyprland >= 0.57 uses Lua config. API stubs: /usr/share/hypr/stubs/hl.meta.lua
-- Docs: https://wiki.hypr.land/configuring/

local function read(path)
    local f = io.open(path, "r")
    if not f then return "" end
    local s = f:read("*a") or ""
    f:close()
    return s
end
local HOME = os.getenv("HOME")

---- MONITORS ----
-- Apple silicon: built-in panel, detected from the device-tree model string, e.g.
--   "Apple MacBook Air (M1, 2020)" / "Apple MacBook Pro (14-inch, M1 Pro, 2021)"
--   Air 13" / Pro 13"  2560x1600         -> scale 1.666667 (looks like 1536x960)
--   Pro 14" (notch)    3024x1964 @120Hz  -> scale 2        (looks like 1512x982, macOS default)
--   Pro 16" (notch)    3456x2234 @120Hz  -> scale 2        (looks like 1728x1117, macOS default)
--   The notch area only exists with kernel arg appledrm.show_notch=1 (install.sh sets it on
--   14"/16"); waybar then uses config-notch.jsonc (bar as tall as the notch, nothing centred).
-- PC (amd64): monitors.lua next to this file, generated on first login by
--   scripts/monitors.py (max resolution, max refresh, scale by pixel density, side by side).
--   Edit it freely, or regenerate with: monitors-setup  (it is not tracked in git).
-- If a mode isn't offered, Hyprland falls back to the preferred mode.
local machine  = read("/proc/device-tree/model")
local is_apple = machine:find("^Apple") ~= nil
local panel    = { notch = false }

if is_apple then
    panel = { mode = "preferred", scale = 1.666667, notch = false }
    if machine:find("14%-inch") then
        panel = { mode = "3024x1964@120", scale = 2, notch = true }
    elseif machine:find("16%-inch") then
        panel = { mode = "3456x2234@120", scale = 2, notch = true }
    end
    hl.monitor({ output = "eDP-1", mode = panel.mode, position = "auto", scale = panel.scale })
else
    local monitors = HOME .. "/.config/hypr/monitors.lua"
    if read(monitors) ~= "" then dofile(monitors) end
end
-- anything not configured above (new/external screens): sensible defaults
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = "auto" })

---- PROGRAMS ----
local terminal = "kitty"
local menu     = "fuzzel"
local files    = "thunar"
local mod      = "SUPER" -- Option key on the Macs (Cmd/Option swapped), Alt key on PCs (Alt/Win swapped)

---- AUTOSTART ----
hl.on("hyprland.start", function()
    -- graphical-session.target for the portals (screen sharing, file pickers);
    -- Hyprland has already exported WAYLAND_DISPLAY etc. to the systemd user manager
    hl.exec_cmd("systemctl --user start hyprland-session.target")
    -- bar: notch layout on the 14"/16" Pros; PCs without Wi-Fi hardware get the wired
    -- layout (ethernet + live traffic + live APU watts, no Wi-Fi/Bluetooth)
    local p = io.popen("ls /sys/class/ieee80211 2>/dev/null")
    local has_wifi = p and p:read("*a") ~= "" or false
    if p then p:close() end
    if panel.notch then
        hl.exec_cmd("waybar -c ~/.config/waybar/config-notch.jsonc")
    elseif not is_apple and not has_wifi then
        hl.exec_cmd("waybar -c ~/.config/waybar/config-wired.jsonc")
    else
        hl.exec_cmd("waybar")
    end
    hl.exec_cmd("mako")
    hl.exec_cmd("hyprpaper")
    hl.exec_cmd("hypridle")
    hl.exec_cmd("systemctl --user start hyprpolkitagent")
    hl.exec_cmd("~/.config/hypr/scripts/battery-notify.sh") -- exits by itself without a battery
    if not is_apple and read(HOME .. "/.config/hypr/monitors.lua") == "" then
        hl.exec_cmd("~/.config/hypr/scripts/monitors.py --apply") -- first login on a PC
    end
end)

hl.on("hyprland.shutdown", function()
    os.execute("systemctl --user stop hyprland-session.target")
end)

---- ENVIRONMENT ----
hl.env("XCURSOR_SIZE", "24")
hl.env("HYPRCURSOR_SIZE", "24")

---- LOOK & FEEL ----
hl.config({
    general = {
        gaps_in     = 0,
        gaps_out    = 0,
        border_size = 2,
        col = {
            active_border   = "rgba(8a8a8aff)",
            inactive_border = "rgba(2a2a2aff)",
        },
        layout = "dwindle",
    },
    decoration = {
        rounding = 8,
        blur = { enabled = false }, -- off: saves GPU work / power
    },
    animations = { enabled = false }, -- no animations: everything instant
    dwindle    = { preserve_split = true },
    misc = {
        force_default_wallpaper  = 0,
        disable_hyprland_logo    = true,
        disable_splash_rendering = true,
        background_color         = "rgb(161616)",
    },
})

---- INPUT: keyboard + touchpad ----
hl.config({
    input = {
        kb_layout    = "us",
        -- PCs: Alt <-> Super swapped, so the mod key sits next to the space bar like
        -- Cmd on a Mac (the Macs swap Cmd/Option in the hid_apple driver instead)
        kb_options   = is_apple and "" or "altwin:swap_alt_win",
        repeat_delay = 225, -- ms before a held key repeats (macOS-fast; default 600)
        repeat_rate  = 40,  -- repeats per second (default 25)
        follow_mouse = 1,
        -- Pointer acceleration: off on PCs (mouse: cursor distance = hand distance),
        -- libinput's adaptive default on the Mac touchpads.
        accel_profile = is_apple and "adaptive" or "flat",
        -- Speed, -1.0 .. 1.0 (0 = the mouse's native DPI, 1:1). With "flat" it is a plain
        -- multiplier of about 1 + sensitivity: -0.3 is ~70% speed, -0.5 ~50%.
        sensitivity  = 0,
        touchpad = {
            natural_scroll       = true,
            tap_to_click         = true,
            clickfinger_behavior = true, -- 2-finger click = right click
            disable_while_typing = true,
        },
    },
})

-- 3-finger horizontal swipe switches workspace
hl.gesture({ fingers = 3, direction = "horizontal", action = "workspace" })

---- KEYBINDS ----
hl.bind(mod .. " + Return",    hl.dsp.exec_cmd(terminal))
hl.bind(mod .. " + E",         hl.dsp.exec_cmd(files))
hl.bind("ALT + Space",         hl.dsp.exec_cmd(menu))
hl.bind(mod .. " + Space",     hl.dsp.exec_cmd(menu))
hl.bind(mod .. " + Q",         hl.dsp.window.close())
hl.bind("ALT + F4",            hl.dsp.window.close())
-- Mac-like screenshots (Super+Shift+3/4 are taken by move-to-workspace)
hl.bind(mod .. " + ALT + 3",   hl.dsp.exec_cmd("~/.config/hypr/scripts/screenshot.sh full"))
hl.bind(mod .. " + ALT + 4",   hl.dsp.exec_cmd("~/.config/hypr/scripts/screenshot.sh area"))
hl.bind("Print",               hl.dsp.exec_cmd("~/.config/hypr/scripts/screenshot.sh area")) -- PC keyboards
hl.bind("SHIFT + Print",       hl.dsp.exec_cmd("~/.config/hypr/scripts/screenshot.sh full"))
hl.bind(mod .. " + L",         hl.dsp.exec_cmd("loginctl lock-session"))
hl.bind(mod .. " + SHIFT + E", hl.dsp.exit())
hl.bind(mod .. " + F",         hl.dsp.window.fullscreen())
hl.bind(mod .. " + V",         hl.dsp.window.float({ action = "toggle" }))
hl.bind(mod .. " + J",         hl.dsp.layout("togglesplit"))

hl.bind(mod .. " + left",  hl.dsp.focus({ direction = "left" }))
hl.bind(mod .. " + right", hl.dsp.focus({ direction = "right" }))
hl.bind(mod .. " + up",    hl.dsp.focus({ direction = "up" }))
hl.bind(mod .. " + down",  hl.dsp.focus({ direction = "down" }))

for i = 1, 10 do
    local key = i % 10
    hl.bind(mod .. " + " .. key,         hl.dsp.focus({ workspace = i }))
    hl.bind(mod .. " + SHIFT + " .. key, hl.dsp.window.move({ workspace = i }))
end

hl.bind(mod .. " + mouse:272", hl.dsp.window.drag(),   { mouse = true })
hl.bind(mod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })

-- MX Master 3S thumb buttons (below the side wheel) → QGIS shortcuts, only when
-- QGIS is focused. Lower = mouse:275 (back), upper = mouse:276 (forward).
local function qgis_shortcut(key)
    return function()
        local w = hl.get_active_window()
        if w and w.class == "org.qgis.qgis" then
            hl.dispatch(hl.dsp.send_shortcut({ mods = "CTRL SHIFT", key = key }))
        end
    end
end
hl.bind("mouse:275", qgis_shortcut("p")) -- lower: Ctrl+Shift+P
hl.bind("mouse:276", qgis_shortcut("i")) -- upper: Ctrl+Shift+I

-- Media / brightness keys (work on the lock screen too)
local held = { locked = true, repeating = true }
hl.bind("XF86AudioRaiseVolume",  hl.dsp.exec_cmd("wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+"), held)
hl.bind("XF86AudioLowerVolume",  hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"),      held)
hl.bind("XF86AudioMute",         hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"),     { locked = true })
-- screen: brightness keys · keyboard backlight: Shift + brightness keys
-- (pkill -RTMIN+8 refreshes the waybar brightness module immediately)
local bl = function(args) return hl.dsp.exec_cmd("brightnessctl -q " .. args .. " && pkill -RTMIN+8 waybar") end
hl.bind("XF86MonBrightnessUp",           bl("-c backlight -e4 -n2 set 5%+"), held)
hl.bind("XF86MonBrightnessDown",         bl("-c backlight -e4 -n2 set 5%-"), held)
hl.bind("SHIFT + XF86MonBrightnessUp",   bl("-d '*kbd_backlight*' set 10%+"),     held)
hl.bind("SHIFT + XF86MonBrightnessDown", bl("-d '*kbd_backlight*' set 10%-"),     held)
hl.bind("XF86AudioPlay",         hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioNext",         hl.dsp.exec_cmd("playerctl next"),       { locked = true })
hl.bind("XF86AudioPrev",         hl.dsp.exec_cmd("playerctl previous"),   { locked = true })

-- Lid (laptops only): logind handles lock/suspend; here we switch the internal panel
-- off while closed and back on when opened. The switch name is looked up in
-- /proc/bus/input/devices ("Apple SMC power/lid events" on Macs, "Lid Switch" on PCs).
local lid = read("/proc/bus/input/devices"):match('N: Name="([^"]*[Ll]id[^"]*)"')
if lid then
    hl.bind("switch:on:"  .. lid, hl.dsp.dpms({ action = "off", monitor = "eDP-1" }), { locked = true })
    hl.bind("switch:off:" .. lid, hl.dsp.dpms({ action = "on",  monitor = "eDP-1" }), { locked = true })
end

---- WINDOW RULES ----
-- Never lock/blank the screen while a fullscreen window is shown (video, slides)
hl.window_rule({
    name  = "idle-inhibit-fullscreen",
    match = { class = ".*" },
    idle_inhibit = "fullscreen",
})
hl.window_rule({
    name  = "suppress-maximize-events",
    match = { class = ".*" },
    suppress_event = "maximize",
})
