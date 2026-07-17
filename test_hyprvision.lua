#!/usr/bin/env lua5.4
-- HyprVision · self-check (sem frameworks: `lua5.4 test_hyprvision.lua`)
-- Corre fora do Hyprland: `hl` é um mock que regista chamadas.

local ROOT = arg[0]:match("^(.*)/[^/]*$") or "."
package.path = package.path .. ";" .. ROOT .. "/?.lua"

-- sandbox temporária para estado/runtime
local TMP = os.tmpname(); os.remove(TMP); os.execute("mkdir -p '" .. TMP .. "'")

local calls = {}
local mock_hl = {
    config       = function(t) calls[#calls+1] = { "config", t } end,
    monitor      = function(t) calls[#calls+1] = { "monitor", t } end,
    exec_cmd     = function(c) calls[#calls+1] = { "exec", c } end,
    -- corre o callback já: as cadeias (rampa de gamma) são finitas
    timer        = function(fn, opts) calls[#calls+1] = { "timer", opts }; fn() end,
    bind         = function() end,
    dsp          = { exec_cmd = function(c) return c end },
    notification = { create = function() end },
    get_monitors = function()
        return { { name = "eDP-1", width = 1920, height = 1080,
                   refreshRate = 60.0, x = 0, y = 0, scale = 1.0 } }
    end,
}
local function reset_calls() calls = {} end

local core = require("core")
core.setup{ hl = mock_hl, base = ROOT, state_dir = TMP, runtime = TMP }

local T = {}

function T.test_state_roundtrip()
    local st = core.read_state()
    assert(st.profile == "" and st.paper == "off" and st.dim == 0,
           "estado por omissão errado")
    st.profile = "night"; st.dim = 50; st.temperature = 3600; st.paper = "medium"
    core.write_state(st)
    local st2, existed = core.read_state()
    assert(existed, "ficheiro devia existir após write")
    assert(st2.profile == "night" and st2.dim == 50
           and st2.temperature == 3600 and st2.paper == "medium",
           "round-trip perdeu valores")
    assert(type(st2.dim) == "number" and type(st2.brightness) == "number",
           "campos numéricos têm de voltar como números")
end

function T.test_state_ignora_lixo()
    local f = assert(io.open(core.state_file_path(), "w"))
    f:write("profile=night\ndim=abc\nchave_desconhecida=x\nsem_igual\n")
    f:close()
    local st = core.read_state()
    assert(st.profile == "night", "chave válida devia sobreviver")
    assert(st.dim == 0, "número inválido devia cair no default")
end

function T.test_profiles_carregam_todos()
    local all = core.list_profiles()
    assert(#all == 12, "esperava 12 perfis, tenho " .. #all)
    local ids = {}
    for _, p in ipairs(all) do
        ids[p.id] = true
        assert(p.name and p.icon and p.category, p.id .. ": campos em falta")
        assert(p.temperature and p.brightness and p.gamma,
               p.id .. ": gamma em falta")
        if p.shader then
            local f = io.open(ROOT .. "/shaders/" .. p.shader)
            assert(f, p.id .. ": shader não existe: " .. tostring(p.shader))
            f:close()
        end
    end
    for _, id in ipairs({ "night", "reset", "cinema_oled", "tn_recovery" }) do
        assert(ids[id], "falta o perfil " .. id)
    end
    -- ordenação: correction primeiro, system no fim
    assert(all[1].category == "correction", "correction devia vir primeiro")
    assert(all[#all].category == "system", "system devia vir no fim")
end

function T.test_profile_invalido()
    local p, err = core.load_profile("nao_existe")
    assert(p == nil and err, "perfil inexistente devia dar nil, err")
end

function T.test_menu_index()
    core.write_menu_index()
    local f = assert(io.open(TMP .. "/profiles.menu"))
    local n, night = 0, nil
    for line in f:lines() do
        n = n + 1
        local id, icon, name, cat = line:match("^([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)$")
        assert(id and icon and name and cat, "linha malformada: " .. line)
        if id == "night" then night = { icon = icon, name = name } end
    end
    f:close()
    assert(n == 12 and night and night.name == "Night", "índice do menu errado")
end

function T.test_compose()
    local night = ROOT .. "/shaders/experience/night.glsl"
    assert(core.compose(nil, "off", 0) == nil, "nada activo devia dar nil")

    local merged = core.compose(night, "off", 0)
    assert(merged and merged ~= night, "perfil puro tem de ser embrulhado (dither)")
    local src = assert(io.open(merged)):read("*a")
    assert(src:match("precision highp float;"), "highp obrigatório")
    assert(src:match("_profile_main%(%)"), "main do perfil devia ser renomeado")
    assert(src:match("_hash%(gl_FragCoord%.xy%)"), "dither em falta")
    local _, nver = src:gsub("#version", "")
    assert(nver == 1, "#version duplicado")

    local m2 = core.compose(night, "medium", 30)
    local s2 = assert(io.open(m2)):read("*a")
    assert(s2:match("0%.0520"), "intensidade paper errada")
    assert(s2:match("0%.3000"), "intensidade dim errada")

    local dim_only = core.compose(nil, "off", 20)
    assert(dim_only and assert(io.open(dim_only)):read("*a"):match("0%.2000"))
end

function T.test_shader_animated()
    assert(core.shader_is_animated("uniform float time;\nvoid main(){}"))
    assert(not core.shader_is_animated("void main(){}"))
end

function T.test_glsl_valido()
    -- todos os shaders do repo + compostos, via glslangValidator
    local function check(path)
        local p = io.popen("glslangValidator -S frag '" .. path .. "' 2>&1")
        local out = p:read("*a"); local ok = p:close()
        assert(ok, "GLSL inválido: " .. path .. "\n" .. out)
    end
    local p = io.popen("find '" .. ROOT .. "/shaders' -name '*.glsl'")
    local n = 0
    for f in p:lines() do check(f); n = n + 1 end
    p:close()
    local night = ROOT .. "/shaders/experience/night.glsl"
    for _, lvl in ipairs({ "light", "medium", "heavy" }) do
        check(core.compose(night, lvl, 30)); n = n + 1
    end
    check(core.compose(night, "off", 0)); n = n + 1
    print(("  (%d shaders GLSL validados)"):format(n))
end

function T.test_schedule_wrap()
    local slots = {
        { name = "dawn",  enabled = true, hour = 6,  profile = "reset" },
        { name = "night", enabled = true, hour = 21, profile = "night" },
        { name = "off",   enabled = false, hour = 12, profile = "focus" },
        { name = "none",  enabled = true, hour = 13, profile = "none" },
    }
    local function at(h, m) return core.current_slot(slots, h * 60 + m) end
    assert(at(7, 0).name  == "dawn",  "07:00 devia ser dawn")
    assert(at(22, 0).name == "night", "22:00 devia ser night")
    assert(at(2, 0).name  == "night", "02:00 devia herdar night de ontem (wrap)")
    assert(at(12, 30).name == "dawn", "slot disabled/none não conta")
    assert(core.current_slot({}, 600) == nil, "sem slots → nil")
    -- minutos contam
    local ms = { { name = "m", enabled = true, hour = 6, minute = 30, profile = "reset" } }
    assert(core.current_slot(ms, 6 * 60 + 15).name == "m", "wrap com minute")
end

function T.test_battery_transition()
    local cfg = { enabled = true, threshold = 20, plugged = "none",
                  unplugged = "none", low = "eink", restore_after_low = true }
    -- baseline: primeira leitura nunca age
    local p, act = core.battery_transition(cfg, nil, 15, "Discharging")
    assert(p == "low" and act == nil, "baseline não devia agir")
    -- entra em low
    p, act = core.battery_transition(cfg, "unplugged", 15, "Discharging")
    assert(p == "low" and act and act.apply == "eink" and act.remember,
           "entrar em low devia aplicar eink")
    -- sai de low ao ligar o carregador
    p, act = core.battery_transition(cfg, "low", 15, "Charging")
    assert(p == "plugged" and act and act.restore_pre_low,
           "sair de low devia restaurar")
    -- plugged/unplugged com "none" não agem
    p, act = core.battery_transition(cfg, "plugged", 80, "Discharging")
    assert(p == "unplugged" and act == nil, "'none' não devia agir")
    -- sem mudança → sem acção
    p, act = core.battery_transition(cfg, "unplugged", 60, "Discharging")
    assert(act == nil, "sem transição não há acção")
end

local function exec_count(pat)
    local n = 0
    for _, c in ipairs(calls) do
        if c[1] == "exec" and c[2]:match(pat) then n = n + 1 end
    end
    return n
end
local function last_shader_set()
    for i = #calls, 1, -1 do
        local c = calls[i]
        if c[1] == "config" and c[2].decoration
           and c[2].decoration.screen_shader ~= nil then
            return c[2].decoration.screen_shader
        end
    end
    return nil
end

function T.test_apply_night()
    assert(core.apply("night"))
    local sh = last_shader_set()
    assert(sh and sh:match("merged%-"), "screen_shader devia apontar ao composto")
    assert(exec_count("set%-property.*Temperature") > 0, "gamma não foi tocado")
    local st = core.read_state()
    assert(st.profile == "night" and st.temperature == 3600, "estado não gravado")
end

function T.test_overlay_preserva_perfil()
    assert(core.apply("night"))
    core.overlay("dim", 30)
    local st = core.read_state()
    assert(st.profile == "night" and st.dim == 30, "overlay perdeu o perfil")
    local src = assert(io.open(last_shader_set())):read("*a")
    assert(src:match("0%.3000"), "dim não entrou no shader")
end

function T.test_apply_reset_limpa_overlays()
    assert(core.apply("night"))
    core.overlay("paper", "medium")
    core.overlay("dim", 30)
    assert(core.apply("reset"))
    local st = core.read_state()
    assert(st.paper == "off" and st.dim == 0,
           "perfil reset devia limpar paper/dim, ficou paper=" .. st.paper
           .. " dim=" .. st.dim)
end

function T.test_safe_reset_e_backup()
    assert(core.apply("night"))
    reset_calls()
    core.safe_reset()
    assert(last_shader_set() == "", "safe_reset devia limpar o shader")
    local _, existed = core.read_state()
    assert(not existed, "safe_reset devia arquivar o estado")
    assert(io.open(core.state_file_path() .. ".bak"), "state.bak em falta")
    -- recuperação
    reset_calls()
    core.restore_backup()
    local st, ex2 = core.read_state()
    assert(ex2 and st.profile == "night", "restore_backup devia repor night")
    assert(last_shader_set():match("merged%-"), "e reaplicar o shader")
end

function T.test_restore_sem_estado_nao_faz_nada()
    core.restore()
    assert(#calls == 0, "restore sem estado não devia tocar em nada")
end

function T.test_apply_invalido_nao_rebenta()
    local ok, err = core.apply("nao_existe")
    assert(ok == false and err, "perfil inválido devia devolver false, err")
end

function T.test_tick_schedule_baseline()
    local cfg = { schedule = { enabled = true, apply_on_start = false, slots = {
        { name = "always", enabled = true, hour = 0, profile = "night" } } } }
    local mem = {}
    core.tick_schedule(cfg, mem)     -- primeiro tick: só regista
    assert(mem.prev_slot == "always" and last_shader_set() == nil,
           "primeiro tick não devia aplicar (apply_on_start=false)")
end

function T.test_launcher_smoke()
    local sand = TMP .. "/launcher"
    os.execute(("mkdir -p '%s/ui' '%s/state' '%s/rofi' '%s/fakebin'")
               :format(sand, sand, sand, sand))
    os.execute(("cp '%s/ui/launcher.sh' '%s/ui/'"):format(ROOT, sand))
    os.execute(("touch '%s/rofi/hyprvision.rasi'"):format(sand))
    -- estado e índice como o init os deixaria
    local st = assert(io.open(sand .. "/state/state", "w"))
    st:write("profile=reset\nshader=\nicc=\nextra=\npaper=off\ndim=0\n" ..
             "temperature=6500\nbrightness=1.0\ngamma=1.0\n")
    st:close()
    local mi = assert(io.open(sand .. "/state/profiles.menu", "w"))
    mi:write("night\t🌙\tNight\texperience\nreset\t⚡\tReset\tsystem\n")
    mi:close()
    -- fakes: rofi escolhe a linha night; hyprctl regista os evals
    local fk = assert(io.open(sand .. "/fakebin/rofi", "w"))
    fk:write("#!/usr/bin/env bash\ngrep -m1 night\n"); fk:close()
    fk = assert(io.open(sand .. "/fakebin/hyprctl", "w"))
    fk:write(("#!/usr/bin/env bash\necho \"$@\" >> '%s/hyprctl.log'\necho ok\n")
             :format(sand)); fk:close()
    fk = assert(io.open(sand .. "/fakebin/notify-send", "w"))
    fk:write("#!/usr/bin/env bash\nexit 0\n"); fk:close()
    os.execute(("chmod +x '%s/fakebin/'*"):format(sand))

    local rc = os.execute(("PATH='%s/fakebin':$PATH bash '%s/ui/launcher.sh'")
                          :format(sand, sand))
    assert(rc, "launcher saiu com erro")
    local log = assert(io.open(sand .. "/hyprctl.log")):read("*a")
    assert(log:match("eval hv%.apply%('night'%)"),
           "launcher devia invocar hv.apply('night'); log:\n" .. log)
end

function T.test_installer_modo_automatico()
    local sand = TMP .. "/installer_auto"
    os.execute(("mkdir -p '%s/home/.config/hypr' '%s/fakebin'"):format(sand, sand))
    os.execute(("touch '%s/home/.config/hypr/hyprland.lua'"):format(sand))
    for _, b in ipairs({ "rofi", "wl-gammarelay-rs", "notify-send", "hyprctl", "paru" }) do
        local fk = assert(io.open(sand .. "/fakebin/" .. b, "w"))
        fk:write("#!/usr/bin/env bash\nexit 0\n"); fk:close()
    end
    os.execute(("chmod +x '%s/fakebin/'*"):format(sand))

    -- modo 2 (automático): dia = perfil 7 (focus) às 8h, noite = perfil 8 (night) às 21h
    local run = ("PATH='%s/fakebin':$PATH HYPRLAND_INSTANCE_SIGNATURE= LANG=en_GB.UTF-8 " ..
                 "HOME='%s/home' bash '%s/install.sh' >'%s/out.log' 2>&1")
    assert(os.execute(("printf '2\\n7\\n8\\n8\\n21\\n' | " ..
                        run):format(sand, sand, ROOT, sand)),
           "install.sh (modo automático) saiu com erro")

    local cfg_path = sand .. "/home/.config/hypr/hyprvision/config.lua"
    local cfg = assert(io.open(cfg_path)):read("*a")
    assert(cfg:match('name = "day",%s+enabled = true, hour = 8, profile = "focus"'),
           "slot de dia em falta no config.lua:\n" .. cfg)
    assert(cfg:match('name = "night",%s+enabled = true, hour = 21, profile = "night"'),
           "slot de noite em falta no config.lua")
    assert(cfg:match("apply_on_start = true,"), "apply_on_start devia ficar true")

    -- reinstalação: não deve voltar a perguntar nem tocar num config.lua já personalizado
    os.execute(("sed -i 's/menu  = \"SUPER + H\"/menu  = \"SUPER + M\"/' '%s'"):format(cfg_path))
    assert(os.execute((run .. " </dev/null"):format(sand, sand, ROOT, sand)),
           "reinstalação saiu com erro")
    local cfg2 = assert(io.open(cfg_path)):read("*a")
    assert(cfg2:match('menu  = "SUPER %+ M"'),
           "reinstalação devia preservar o config.lua personalizado")
end

function T.test_installer_modo_manual_e_eof()
    local sand = TMP .. "/installer_manual"
    os.execute(("mkdir -p '%s/home/.config/hypr' '%s/fakebin'"):format(sand, sand))
    os.execute(("touch '%s/home/.config/hypr/hyprland.lua'"):format(sand))
    for _, b in ipairs({ "rofi", "wl-gammarelay-rs", "notify-send", "hyprctl", "paru" }) do
        local fk = assert(io.open(sand .. "/fakebin/" .. b, "w"))
        fk:write("#!/usr/bin/env bash\nexit 0\n"); fk:close()
    end
    os.execute(("chmod +x '%s/fakebin/'*"):format(sand))

    -- stdin fechado: nunca deve travar, tem de cair no modo manual por omissão
    local run = ("PATH='%s/fakebin':$PATH HYPRLAND_INSTANCE_SIGNATURE= LANG=zh_CN.UTF-8 " ..
                 "HOME='%s/home' bash '%s/install.sh' </dev/null >'%s/out.log' 2>&1")
    assert(os.execute(run:format(sand, sand, ROOT, sand)),
           "install.sh com stdin fechado devia terminar sem erro")

    local cfg = assert(io.open(sand .. "/home/.config/hypr/hyprvision/config.lua")):read("*a")
    assert(cfg:match("schedule = {%s+enabled = false,"),
           "sem resposta devia desligar o schedule (omissão segura)")
end

function T.test_uninstall_limpa_o_hyprland_lua()
    local sand = TMP .. "/uninstall"
    os.execute(("mkdir -p '%s/home/.config/hypr' '%s/fakebin'"):format(sand, sand))
    os.execute(("touch '%s/home/.config/hypr/hyprland.lua'"):format(sand))
    for _, b in ipairs({ "rofi", "wl-gammarelay-rs", "notify-send", "hyprctl", "paru" }) do
        local fk = assert(io.open(sand .. "/fakebin/" .. b, "w"))
        fk:write("#!/usr/bin/env bash\nexit 0\n"); fk:close()
    end
    os.execute(("chmod +x '%s/fakebin/'*"):format(sand))

    local env = ("PATH='%s/fakebin':$PATH HYPRLAND_INSTANCE_SIGNATURE= LANG=en_GB.UTF-8 HOME='%s/home'")
                :format(sand, sand)
    -- instala (modo manual, sem conflitos de atalho) e confirma que o require lá está
    assert(os.execute(("printf '1\\n' | %s bash '%s/install.sh' >'%s/out.log' 2>&1")
                       :format(env, ROOT, sand)),
           "install.sh saiu com erro")
    local hyprlua_path = sand .. "/home/.config/hypr/hyprland.lua"
    local before = assert(io.open(hyprlua_path)):read("*a")
    assert(before:match('require%("init"%)'), "install.sh devia ter deixado o require(\"init\")")

    assert(os.execute(("%s bash '%s/uninstall.sh' >'%s/out.log' 2>&1"):format(env, ROOT, sand)),
           "uninstall.sh saiu com erro")
    local after = assert(io.open(hyprlua_path)):read("*a")
    assert(not after:match('require%("init"%)'),
           "uninstall.sh devia ter removido o require(\"init\"):\n" .. after)
    assert(not after:match("[Hh]yprvision"),
           "uninstall.sh devia ter removido todas as referências a hyprvision:\n" .. after)
    assert(not os.execute(("test -d '%s/home/.config/hypr/hyprvision'"):format(sand)),
           "uninstall.sh devia ter removido a pasta instalada")
end

function T.test_launcher_language_override()
    local sand = TMP .. "/launcher_lang"
    os.execute(("mkdir -p '%s/ui' '%s/state' '%s/rofi' '%s/fakebin'")
               :format(sand, sand, sand, sand))
    os.execute(("cp '%s/ui/launcher.sh' '%s/ui/'"):format(ROOT, sand))
    os.execute(("touch '%s/rofi/hyprvision.rasi'"):format(sand))
    local cfg = assert(io.open(sand .. "/config.lua", "w"))
    cfg:write('return {\n    language = "en",\n    keys = {},\n}\n'); cfg:close()
    local st = assert(io.open(sand .. "/state/state", "w"))
    st:write("profile=reset\nshader=\nicc=\nextra=\npaper=medium\ndim=0\n" ..
             "temperature=6500\nbrightness=1.0\ngamma=1.0\n")
    st:close()
    local mi = assert(io.open(sand .. "/state/profiles.menu", "w"))
    mi:write("reset\t⚡\tReset\tsystem\n")
    mi:close()
    -- rofi falso: só grava as linhas do menu e não escolhe nada (sai logo)
    local fk = assert(io.open(sand .. "/fakebin/rofi", "w"))
    fk:write(("#!/usr/bin/env bash\ncat > '%s/menu_dump.txt'\n"):format(sand)); fk:close()
    fk = assert(io.open(sand .. "/fakebin/hyprctl", "w"))
    fk:write("#!/usr/bin/env bash\necho ok\n"); fk:close()
    fk = assert(io.open(sand .. "/fakebin/notify-send", "w"))
    fk:write("#!/usr/bin/env bash\nexit 0\n"); fk:close()
    os.execute(("chmod +x '%s/fakebin/'*"):format(sand))

    -- locale do sistema é português, mas config.lua força inglês
    local rc = os.execute(("LANG=pt_PT.UTF-8 PATH='%s/fakebin':$PATH bash '%s/ui/launcher.sh'")
                          :format(sand, sand))
    assert(rc, "launcher saiu com erro")
    local dump = assert(io.open(sand .. "/menu_dump.txt")):read("*a")
    assert(dump:match("Paper Texture"), "language=\"en\" devia forçar inglês:\n" .. dump)
    assert(not dump:match("Textura de Papel"), "não devia usar português com language=\"en\"")
end

-- runner
local names = {}
for k in pairs(T) do names[#names+1] = k end
table.sort(names)
for _, n in ipairs(names) do
    print("• " .. n)
    reset_calls()
    os.remove(core.state_file_path())          -- isolamento entre testes
    os.remove(core.state_file_path() .. ".bak")
    T[n]()
end
os.execute("rm -rf '" .. TMP .. "'")
print(("\n✓ %d testes OK"):format(#names))
