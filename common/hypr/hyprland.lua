-- Hyprland config shared by every machine (Apple silicon MacBooks and amd64 desktops).
-- Hyprland >= 0.57 uses Lua config. API stubs: /usr/share/hypr/stubs/hl.meta.lua
-- Docs: https://wiki.hypr.land/configuring/
--
-- Machine-specific parts (monitors, keyboard/mouse/touchpad, extra binds, which bar to
-- start) live in the machine's folder of the repo: macbook/ or amd64/. The installer
-- links ~/.config/hypr-platform to that folder; its hypr/machine.lua is loaded below.

local function read(path)
    local f = io.open(path, "r")
    if not f then return "" end
    local s = f:read("*a") or ""
    f:close()
    return s
end
local HOME = os.getenv("HOME")

---- PROGRAMS ----
local terminal = "kitty"
local menu     = "fuzzel"
local files    = "thunar"
local mod      = "SUPER" -- Option key on the Macs (Cmd/Option swapped), Alt key on PCs (Alt/Win swapped)

---- MACHINE ----
-- machine.lua returns function(ctx) -> { input = {...}, autostart = function() ... end }
local machine = {}
local machine_lua = HOME .. "/.config/hypr-platform/hypr/machine.lua"
if read(machine_lua) ~= "" then
    machine = dofile(machine_lua)({ read = read, HOME = HOME, mod = mod }) or {}
end
-- anything not configured by machine.lua (new/external screens): sensible defaults.
-- If a mode isn't offered, Hyprland falls back to the preferred mode.
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = "auto" })

---- AUTOSTART ----
hl.on("hyprland.start", function()
    -- graphical-session.target for the portals (screen sharing, file pickers);
    -- Hyprland has already exported WAYLAND_DISPLAY etc. to the systemd user manager
    hl.exec_cmd("systemctl --user start hyprland-session.target")
    hl.exec_cmd("mako")
    hl.exec_cmd("hyprpaper")
    hl.exec_cmd("hypridle")
    hl.exec_cmd("systemctl --user start hyprpolkitagent")
    -- the bar and anything else machine-specific
    if machine.autostart then machine.autostart() else hl.exec_cmd("waybar") end
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

---- INPUT ----
-- Shared settings here; key swaps, pointer acceleration and the touchpad come from
-- machine.lua (its `input` table is merged in, its values win).
local input = {
    kb_layout    = "us",
    repeat_delay = 225, -- ms before a held key repeats (macOS-fast; default 600)
    repeat_rate  = 40,  -- repeats per second (default 25)
    follow_mouse = 1,
    -- Speed, -1.0 .. 1.0 (0 = the mouse's native DPI, 1:1). With "flat" acceleration
    -- it is a plain multiplier of about 1 + sensitivity: -0.3 is ~70% speed, -0.5 ~50%.
    sensitivity  = 0,
}
for k, v in pairs(machine.input or {}) do input[k] = v end
hl.config({ input = input })

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

-- Media keys (work on the lock screen too). Brightness keys: macbook/hypr/machine.lua
local held = { locked = true, repeating = true }
hl.bind("XF86AudioRaiseVolume",  hl.dsp.exec_cmd("wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+"), held)
hl.bind("XF86AudioLowerVolume",  hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"),      held)
hl.bind("XF86AudioMute",         hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"),     { locked = true })
hl.bind("XF86AudioPlay",         hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioNext",         hl.dsp.exec_cmd("playerctl next"),       { locked = true })
hl.bind("XF86AudioPrev",         hl.dsp.exec_cmd("playerctl previous"),   { locked = true })

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
