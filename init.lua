-- HyprVision · init.lua — wiring no Hyprland (≥ 0.55, config Lua).
-- O runtime Lua é recriado em cada reload, por isso este ficheiro corre
-- sempre fresco: binds, timers e restore sem duplicações. O install.sh
-- acrescenta ao hyprland.lua:
--   package.path = package.path .. ";" .. os.getenv("HOME") .. "/.config/hypr/hyprvision/?.lua"
--   require("init")
local HOME = os.getenv("HOME")
local BASE = HOME .. "/.config/hypr/hyprvision"
package.path = package.path .. ";" .. BASE .. "/?.lua"

local core = require("core")
local cfg  = require("config")
core.setup{ hl = hl, base = BASE }

-- pcall em tudo o que corre dentro do compositor: um perfil roto nunca
-- pode derrubar um handler
local function guard(name, fn)
    return function(...)
        local ok, err = pcall(fn, ...)
        if not ok then
            core.log(name .. ": " .. tostring(err))
            core.notify("HyprVision: erro em " .. name .. " (ver hyprvision.log)")
        end
    end
end

-- superfície pública para o launcher (hyprctl eval "hv.…")
_G.hv = {
    apply          = guard("apply",          core.apply),
    overlay        = guard("overlay",        core.overlay),
    apply_extra    = guard("apply_extra",    core.apply_extra),
    safe_reset     = guard("safe_reset",     core.safe_reset),
    restore_backup = guard("restore_backup", core.restore_backup),
}

-- render p/ painel 8-bit: curvas em fp16 interno + VCGT ICC por KMS
hl.config({ render = { use_fp16 = true, icc_vcgt_enabled = true } })

hl.bind(cfg.keys.menu,  hl.dsp.exec_cmd(BASE .. "/ui/launcher.sh"))
hl.bind(cfg.keys.reset, _G.hv.safe_reset)

core.write_menu_index()

-- restore no load: cobre arranque E reload (o reload limpa screen_shader);
-- pequeno delay para o compositor assentar
hl.timer(guard("restore", core.restore), { timeout = 800, type = "oneshot" })

-- adaptativo (mem morre no reload — o 1º tick restabelece a baseline)
local mem = {}
hl.timer(guard("schedule", function() core.tick_schedule(cfg, mem) end),
         { timeout = 60000, type = "repeat" })
hl.timer(guard("battery", function() core.tick_battery(cfg, mem) end),
         { timeout = 30000, type = "repeat" })

core.log("carregado (init)")
