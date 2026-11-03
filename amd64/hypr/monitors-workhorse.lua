-- Monitor layout of the amd64 workhorse (ASUS XG27JCG 5K).
-- amd64/install.sh links amd64/hypr/monitors.lua -> this file. Matched by monitor name, so it is
-- harmless elsewhere (no match: common/hypr/hyprland.lua falls back to sensible defaults).
-- `monitors-setup` replaces the link with a freshly generated file (this one stays).
-- Monitors are matched by name (desc:), not port, so the rules follow a cable move.
local ASUS = "desc:ASUSTek COMPUTER INC XG27JCG TBLMQV020680"

-- ASUSTek COMPUTER INC XG27JCG TBLMQV020680 (217 ppi)
hl.monitor({ output = ASUS, mode = "5120x2880@119.99", position = "0x0", scale = 2, vrr = 2 })
