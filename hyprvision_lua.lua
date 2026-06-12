-- ╔══════════════════════════════════════════════════════════════════╗
-- ║  HyprVision v4 · Integração Lua (Hyprland ≥ 0.55)               ║
-- ║  Adiciona no fim do teu hyprland.lua:                            ║
-- ║    require("hyprvision_lua")                                     ║
-- ╚══════════════════════════════════════════════════════════════════╝

local INSTALL = os.getenv("HOME") .. "/.config/hypr/hyprvision"
local CLI     = INSTALL .. "/bin/hyprvision"
local UI      = INSTALL .. "/ui/launcher.sh"
local mainMod = "SUPER"

-- ── Keybinds ────────────────────────────────────────────────────────
hl.bind(mainMod .. " + F9",       hl.dsp.exec_cmd(UI))
hl.bind(mainMod .. " SHIFT + F9", hl.dsp.exec_cmd(
    "foot --title='HyprVision' -- bash -c '" .. CLI .. " --status; read'"
))

-- ── Restore ao iniciar o Hyprland ───────────────────────────────────
hl.on("hyprland.start", function()
    hl.timer(1500, function()
        hl.exec_cmd(CLI .. " --restore")
        hl.notification.create({
            text    = "HyprVision v4 carregado ◈",
            timeout = 3000,
            icon    = "display"
        })
    end)
end)

-- ── Timer solar (substitui o daemon bash se quiseres) ───────────────
-- Descomenta para usar em vez do hyprvision-daemon
--
-- local function check_solar()
--     local hour = tonumber(os.date("%H"))
--     local sf   = (os.getenv("XDG_RUNTIME_DIR") or "/tmp") .. "/hyprvision_state.json"
--     local f    = io.open(sf, "r")
--     local profile = "none"
--     if f then
--         local raw = f:read("*a"); f:close()
--         profile = raw:match('"active_profile"%s*:%s*"([^"]+)"') or "none"
--     end
--     local is_night = (hour >= 21) or (hour < 6)
--     if is_night and profile ~= "night" then
--         hl.exec_cmd(CLI .. " --apply night")
--     elseif not is_night and profile == "night" then
--         hl.exec_cmd(CLI .. " --apply reset")
--     end
-- end
-- hl.timer(300000, check_solar, true)
-- hl.on("hyprland.start", function() hl.timer(3000, check_solar) end)

print("[HyprVision Lua] Módulo carregado · keybind: ver daemon_config.toml [keybinds]")
