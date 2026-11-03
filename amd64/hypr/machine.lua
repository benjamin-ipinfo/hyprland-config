-- amd64 desktop part of the Hyprland config (the workhorse and other AMD PCs).
-- Loaded by common/hypr/hyprland.lua through ~/.config/hypr-platform (-> amd64/).
-- Returns a function the shared config calls with { read, HOME, mod }; it returns
-- { input = <input settings>, autostart = <function run at login> }.
return function(ctx)
    local read = ctx.read
    local here = ctx.HOME .. "/.config/hypr-platform/hypr"

    ---- MONITORS ----
    -- monitors.lua next to this file (not in git): on the workhorse a link to
    -- monitors-workhorse.lua (amd64/install.sh); elsewhere generated on first login by
    -- scripts/monitors.py (max resolution, max refresh, scale by pixel density, side by
    -- side). Edit it freely, or regenerate with: monitors-setup
    local monitors = here .. "/monitors.lua"
    local has_monitors = read(monitors) ~= ""
    if has_monitors then dofile(monitors) end

    ---- INPUT (merged into the shared input section) ----
    local input = {
        -- Alt <-> Super swapped, so the mod key sits next to the space bar like Cmd on a Mac
        kb_options    = "altwin:swap_alt_win",
        -- no pointer acceleration: cursor distance = hand distance. Speed: `sensitivity`
        -- in common/hypr/hyprland.lua
        accel_profile = "flat",
    }

    ---- MOUSE BUTTONS ----
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

    return {
        input = input,
        autostart = function()
            -- Bar: PCs without Wi-Fi hardware get the wired layout (ethernet + live
            -- traffic + live APU watts, no Wi-Fi/Bluetooth) on top of the shared bar
            local p = io.popen("ls /sys/class/ieee80211 2>/dev/null")
            local has_wifi = p and p:read("*a") ~= "" or false
            if p then p:close() end
            if has_wifi then
                hl.exec_cmd("waybar")
            else
                hl.exec_cmd("waybar -c ~/.config/hypr-platform/waybar/config-wired.jsonc"
                    .. " -s ~/.config/waybar/style.css")
            end
            if not has_monitors then
                hl.exec_cmd(here .. "/scripts/monitors.py --apply") -- first login on a PC
            end
        end,
    }
end
