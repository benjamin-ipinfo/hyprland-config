-- MacBook (Apple silicon, Fedora Asahi Remix) part of the Hyprland config.
-- Loaded by common/hypr/hyprland.lua through ~/.config/hypr-platform (-> macbook/).
-- Returns a function the shared config calls with { read, HOME, mod }; it returns
-- { input = <input settings>, autostart = <function run at login> }.
return function(ctx)
    local read = ctx.read

    ---- MONITOR: built-in panel ----
    -- Model from the device tree, e.g. "Apple MacBook Air (M1, 2020)" /
    -- "Apple MacBook Pro (14-inch, M1 Pro, 2021)":
    --   Air 13" / Pro 13"  2560x1600         -> scale 1.666667 (looks like 1536x960)
    --   Pro 14" (notch)    3024x1964 @120Hz  -> scale 2        (looks like 1512x982, macOS default)
    --   Pro 16" (notch)    3456x2234 @120Hz  -> scale 2        (looks like 1728x1117, macOS default)
    -- The strip beside the notch only exists with kernel arg appledrm.show_notch=1
    -- (macbook/install.sh sets it on 14"/16"); until that reboot the modes above aren't
    -- offered and Hyprland falls back to the preferred mode.
    local model = read("/proc/device-tree/model")
    local panel = { mode = "preferred", scale = 1.666667 }
    if model:find("14%-inch") then
        panel = { mode = "3024x1964@120", scale = 2 }
    elseif model:find("16%-inch") then
        panel = { mode = "3456x2234@120", scale = 2 }
    end
    hl.monitor({ output = "eDP-1", mode = panel.mode, position = "auto", scale = panel.scale })
    local notch = read("/proc/cmdline"):find("appledrm.show_notch=1", 1, true) ~= nil

    ---- INPUT (merged into the shared input section) ----
    local input = {
        kb_options    = "", -- Cmd/Option are swapped in the hid_apple driver instead
        accel_profile = "adaptive", -- libinput's default for the touchpad
        touchpad = {
            natural_scroll       = true,
            tap_to_click         = true,
            clickfinger_behavior = true, -- 2-finger click = right click
            disable_while_typing = true,
        },
    }
    -- 3-finger horizontal swipe switches workspace
    hl.gesture({ fingers = 3, direction = "horizontal", action = "workspace" })

    ---- BRIGHTNESS KEYS ----
    -- screen: brightness keys · keyboard backlight: Shift + brightness keys
    -- (pkill -RTMIN+8 refreshes the waybar brightness module immediately)
    local held = { locked = true, repeating = true }
    local bl = function(args) return hl.dsp.exec_cmd("brightnessctl -q " .. args .. " && pkill -RTMIN+8 waybar") end
    hl.bind("XF86MonBrightnessUp",           bl("-c backlight -e4 -n2 set 5%+"), held)
    hl.bind("XF86MonBrightnessDown",         bl("-c backlight -e4 -n2 set 5%-"), held)
    hl.bind("SHIFT + XF86MonBrightnessUp",   bl("-d '*kbd_backlight*' set 10%+"), held)
    hl.bind("SHIFT + XF86MonBrightnessDown", bl("-d '*kbd_backlight*' set 10%-"), held)

    ---- LID ----
    -- logind handles lock; here the panel switches off while closed and back on when
    -- opened. Switch name from /proc/bus/input/devices ("Apple SMC power/lid events").
    local lid = read("/proc/bus/input/devices"):match('N: Name="([^"]*[Ll]id[^"]*)"')
    if lid then
        hl.bind("switch:on:"  .. lid, hl.dsp.dpms({ action = "off", monitor = "eDP-1" }), { locked = true })
        hl.bind("switch:off:" .. lid, hl.dsp.dpms({ action = "on",  monitor = "eDP-1" }), { locked = true })
    end

    return {
        input = input,
        autostart = function()
            -- Bar: common/waybar/config.jsonc. On a notched 14"/16" Pro the bar is as tall
            -- as the notch strip (74 px = 37 logical px at scale 2), like the macOS menu
            -- bar: a two-line override that includes the shared config is written to the
            -- runtime dir, so the shared config stays the only bar config in the repo.
            -- (Workspaces are already on the left; the centre would be behind the notch.)
            if notch then
                local cfg = (os.getenv("XDG_RUNTIME_DIR") or "/tmp") .. "/waybar-notch.jsonc"
                local f = io.open(cfg, "w")
                if f then
                    f:write('{ "include": ["~/.config/waybar/config.jsonc"], "height": 37 }\n')
                    f:close()
                    hl.exec_cmd("waybar -c " .. cfg .. " -s ~/.config/waybar/style.css")
                else
                    hl.exec_cmd("waybar")
                end
            else
                hl.exec_cmd("waybar")
            end
            -- low-battery notifications (15% / 5%)
            hl.exec_cmd("~/.config/hypr-platform/hypr/scripts/battery-notify.sh")
        end,
    }
end
