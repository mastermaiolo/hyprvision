-- HyprVision · Integração Lua (Hyprland ≥ 0.55 com config hyprland.lua)
-- O install.sh acrescenta ao teu hyprland.lua:
--   package.path = package.path .. ";" .. os.getenv("HOME") .. "/.config/hypr/hyprvision/?.lua"
--   require("hyprvision_lua")
-- Espelha o hyprvision.conf.example: restore + daemon no arranque, dois binds.

local INSTALL = os.getenv("HOME") .. "/.config/hypr/hyprvision"
local CLI     = INSTALL .. "/bin/hyprvision"

-- Keybinds (mesmos defaults da instalação .conf)
hl.bind("SUPER + H",         hl.dsp.exec_cmd(INSTALL .. "/ui/launcher.sh"))
hl.bind("SUPER + SHIFT + H", hl.dsp.exec_cmd(CLI .. " --safe-reset"))

-- Arranque: daemon + restore do último perfil (pequeno delay para o
-- compositor assentar antes de aplicar shader/gamma)
hl.on("hyprland.start", function()
    hl.exec_cmd(INSTALL .. "/bin/hyprvision-daemon")
    hl.exec_cmd("sh -c 'sleep 1.5; " .. CLI .. " --restore'")
end)
