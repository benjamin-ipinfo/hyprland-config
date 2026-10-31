-- Hyprland config — MacBook Air M1 (Fedora Asahi)
-- Hyprland >= 0.57 uses Lua config. API stubs: /usr/share/hypr/stubs/hl.meta.lua
-- Docs: https://wiki.hypr.land/configuring/

---- MONITORS ----
-- Per-machine panel settings, detected from the device-tree model string, e.g.
--   "Apple MacBook Air (M1, 2020)" / "Apple MacBook Pro (14-inch, M1 Pro, 2021)"
--   Air 13" / Pro 13"  2560x1600         -> scale 1.666667 (looks like 1536x960)
--   Pro 14" (notch)    3024x1964 @120Hz  -> scale 2        (looks like 1512x982, macOS default)
--   Pro 16" (notch)    3456x2234 @120Hz  -> scale 2        (looks like 1728x1117, macOS default)
-- The notch area only exists with kernel arg appledrm.show_notch=1 (install.sh sets it on
-- 14"/16"); waybar then uses config-notch.jsonc (bar as tall as the notch, nothing centred).
-- If a mode isn't offered by the kernel, Hyprland falls back to the preferred mode.
local function model()
    local f = io.open("/proc/device-tree/model", "r")
    if not f then return "" end
    local m = f:read("*a") or ""
    f:close()
    return m
end
local machine = model()
local panel = { mode = "preferred", scale = 1.666667, notch = false }
if machine:find("14%-inch") then
    panel = { mode = "3024x1964@120", scale = 2, notch = true }
elseif machine:find("16%-inch") then
    panel = { mode = "3456x2234@120", scale = 2, notch = true }
end
hl.monitor({ output = "eDP-1", mode = panel.mode, position = "auto", scale = panel.scale })
hl.monitor({ output = "",      mode = "preferred", position = "auto", scale = "auto" })

---- PROGRAMS ----
local terminal = "kitty"
local menu     = "fuzzel"
local files    = "thunar"
local mod      = "SUPER" -- the Cmd key

---- AUTOSTART ----
hl.on("hyprland.start", function()
    hl.exec_cmd(panel.notch and "waybar -c ~/.config/waybar/config-notch.jsonc" or "waybar")
    hl.exec_cmd("mako")
    hl.exec_cmd("hyprpaper")
    hl.exec_cmd("hypridle")
    hl.exec_cmd("systemctl --user start hyprpolkitagent")
    hl.exec_cmd("~/.config/hypr/scripts/battery-notify.sh")
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

---- INPUT: Mac keyboard + trackpad ----
hl.config({
    input = {
        kb_layout    = "us",
        follow_mouse = 1,
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
hl.bind("SHIFT + XF86MonBrightnessUp",   bl("-d kbd_backlight set 10%+"),         held)
hl.bind("SHIFT + XF86MonBrightnessDown", bl("-d kbd_backlight set 10%-"),         held)
hl.bind("XF86AudioPlay",         hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioNext",         hl.dsp.exec_cmd("playerctl next"),       { locked = true })
hl.bind("XF86AudioPrev",         hl.dsp.exec_cmd("playerctl previous"),   { locked = true })

-- Lid: logind locks the session (HandleLidSwitch=lock, no suspend); here we
-- just switch the internal panel off while closed and back on when opened.
local lid = "Apple SMC power/lid events"
hl.bind("switch:on:"  .. lid, hl.dsp.dpms({ action = "off", monitor = "eDP-1" }), { locked = true })
hl.bind("switch:off:" .. lid, hl.dsp.dpms({ action = "on",  monitor = "eDP-1" }), { locked = true })

---- WINDOW RULES ----
hl.window_rule({
    name  = "suppress-maximize-events",
    match = { class = ".*" },
    suppress_event = "maximize",
})
