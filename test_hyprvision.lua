#!/usr/bin/env lua5.4
-- HyprVision 5 · self-check (sem frameworks: `lua5.4 test_hyprvision.lua`)
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
    assert(#all == 10, "esperava 10 perfis, tenho " .. #all)
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
    assert(n == 10 and night and night.name == "Night", "índice do menu errado")
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
