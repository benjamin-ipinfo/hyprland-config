-- Monitor layout of the amd64 workhorse (ASUS XG27JCG 5K + Dell U2717D portrait).
-- amd64/install.sh links amd64/hypr/monitors.lua -> this file. Matched by monitor name, so it is
-- harmless elsewhere (no match: common/hypr/hyprland.lua falls back to sensible defaults).
-- `monitors-setup` replaces the link with a freshly generated file (this one stays).
-- Monitors are matched by name (desc:), not port, so the rules follow a cable move.
local ASUS = "desc:ASUSTek COMPUTER INC XG27JCG TBLMQV020680"
local DELL = "desc:Dell Inc. DELL U2717D 67YGV755575S"

-- ASUSTek COMPUTER INC XG27JCG TBLMQV020680 (217 ppi)
hl.monitor({ output = ASUS, mode = "5120x2880@119.99", position = "0x0", scale = 2, vrr = 2 })

-- Dell Inc. DELL U2717D 67YGV755575S (108 ppi)
-- Dell is physically rotated 90° clockwise (portrait, 1440x2560 logical). Placed right of
-- the ASUS and vertically centred on it (y = (1440 - 2560) / 2). If the picture is upside
-- down, use transform = 3 instead of 1. Dwindle splits by aspect ratio, so on a portrait
-- screen two windows stack top/bottom, each using the full 1440 width.
-- 60 Hz is the limit: 70 Hz over HDMI shows "not supported" (EDID max 88 kHz line rate).
hl.monitor({ output = DELL, mode = "2560x1440@59.95", position = "2560x-560", scale = 1, vrr = 0, transform = 1 })

-- Workspaces: 1-8 and 10 live on the ASUS (1 is the default there), 9 on the Dell.
for _, ws in ipairs({ 1, 2, 3, 4, 5, 6, 7, 8, 10 }) do
    hl.workspace_rule({ workspace = tostring(ws), monitor = ASUS, default = (ws == 1) })
end
hl.workspace_rule({ workspace = "9", monitor = DELL, default = true })
