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
