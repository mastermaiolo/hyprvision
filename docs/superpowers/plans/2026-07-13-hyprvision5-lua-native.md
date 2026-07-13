# HyprVision 5.0 (Lua-nativo) — Plano de Implementação

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reescrever o HyprVision como módulo Lua nativo do Hyprland 0.55+, eliminando o daemon/CLI Python, com dither/fp16 para o painel 8-bit.

**Architecture:** `init.lua` (wiring: binds, timers, restore) + `core.lua` (motor testável com `hl` injectado) + `config.lua` (utilizador) + `profiles/*.lua`. O launcher Rofi lê `state/state` (key=value) e envia acções via `hyprctl eval "hv.*"`. Único processo externo: wl-gammarelay-rs.

**Tech Stack:** Lua 5.4 (runtime do Hyprland; testes com `lua5.4` standalone), GLSL ES 3.00, bash+rofi, glslangValidator.

## Global Constraints

- Hyprland ≥ 0.55 com config `hyprland.lua` (parser non-legacy). Spec: `docs/superpowers/specs/2026-07-13-hyprvision5-lua-native-design.md`.
- **API verificada ao vivo (não mudar):** `hl.timer(fn, {timeout=<ms>, type="repeat"|"oneshot"})`; `hl.bind("SUPER + H", fn_ou_dispatcher)`; `hl.config({render={use_fp16=true}})` (tabelas aninhadas); `hl.monitor({output=, mode=, position=, scale=, icc=})`; `hl.notification.create({text=, timeout=, icon=})`; `hl.exec_cmd(cmd)`; `hl.get_monitors()` → lista com `.name/.width/.height/.refreshRate/.x/.y/.scale`; `io`, `io.popen`, `os.date`, `os.time`, `os.rename`, `os.execute` disponíveis.
- **Runtime Lua é recriado em cada reload** (verificado): `init.lua` corre fresco; timers/binds antigos morrem sozinhos. Nunca depender de estado global entre reloads — só do ficheiro `state/state`.
- `hyprctl eval` **não devolve output**: leitura por processos externos é sempre via ficheiros em `state/`.
- Estado em formato **key=value** (uma linha por chave) — não JSON. (Desvio deliberado ao spec, que dizia JSON: bash lê key=value sem dependências. Task 9 actualiza o spec.)
- Comentários e strings de UI em português, como o resto do repo.
- wl-gammarelay-rs D-Bus: bus `rs.wl-gammarelay`, path `/`, iface `rs.wl.gammarelay`; props `Temperature` (sig `q`), `Brightness` (`d`), `Gamma` (`d`).
- Testes: `lua5.4 test_hyprvision.lua` a partir da raiz do repo; sem frameworks, `assert` puro, mesmo estilo do self-check v4.
- Trabalhar na branch `v5`. Commits frequentes, mensagens em português, rodapé `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`.

---

### Task 1: Branch v5, harness de testes e módulo de estado

**Files:**
- Create: `lua/` não existe — os módulos vivem na raiz: `core.lua`
- Create: `test_hyprvision.lua`
- Delete (nesta task não — a remoção do Python é na Task 8)

**Interfaces:**
- Produces: `core.setup{hl=, base=, state_dir=, runtime=}`, `core.read_state() -> tabela, existia:boolean`, `core.write_state(t)`, `core.log(msg)`, `core.state_file_path()`. Campos do estado: `profile, shader, icc, extra, paper, dim, temperature, brightness, gamma` (strings excepto `dim`/`temperature`/`brightness`/`gamma` numéricos).

- [ ] **Step 1: Criar a branch**

```bash
cd /home/maggio/Documentos/projetos-backup-2026-06-26/hyprvision
git checkout -b v5
```

- [ ] **Step 2: Escrever o teste que falha** — criar `test_hyprvision.lua`:

```lua
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
local function calls_matching(kind, pat)
    local n = 0
    for _, c in ipairs(calls) do
        if c[1] == kind and (not pat or tostring(c[2]):match(pat)
           or (kind == "exec" and c[2]:match(pat))) then n = n + 1 end
    end
    return n
end

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
    T[n]()
end
os.execute("rm -rf '" .. TMP .. "'")
print(("\n✓ %d testes OK"):format(#names))
```

- [ ] **Step 3: Correr — tem de falhar**

Run: `lua5.4 test_hyprvision.lua`
Expected: erro `module 'core' not found`

- [ ] **Step 4: Implementar** — criar `core.lua`:

```lua
-- HyprVision 5 · core.lua — motor: estado, perfis, compose, apply.
-- Sem dependência directa de `hl`: recebe-o via setup() para ser
-- testável fora do compositor (lua5.4 test_hyprvision.lua).
local M = {}

M.DEFAULTS = {
    profile = "", shader = "", icc = "", extra = "",
    paper = "off", dim = 0,
    temperature = 6500, brightness = 1.0, gamma = 1.0,
}
local STATE_KEYS = { "profile", "shader", "icc", "extra", "paper", "dim",
                     "temperature", "brightness", "gamma" }

function M.setup(opts)
    M.hl        = assert(opts.hl, "setup: falta hl")
    M.base      = assert(opts.base, "setup: falta base")
    M.state_dir = opts.state_dir or (M.base .. "/state")
    M.runtime   = opts.runtime
                  or ((os.getenv("XDG_RUNTIME_DIR") or "/tmp") .. "/hyprvision")
    os.execute("mkdir -p '" .. M.state_dir .. "' '" .. M.runtime .. "'")
end

function M.state_file_path() return M.state_dir .. "/state" end

function M.log(msg)
    local path = M.state_dir .. "/hyprvision.log"
    local f = io.open(path, "a")
    if not f then return end
    -- rotação simples: acima de 100 KB recomeça (guarda o anterior)
    if f:seek("end") > 100000 then
        f:close(); os.rename(path, path .. ".old"); f = io.open(path, "a")
        if not f then return end
    end
    f:write(os.date("%Y-%m-%d %H:%M:%S ") .. tostring(msg) .. "\n")
    f:close()
end

function M.read_state()
    local st = {}
    for k, v in pairs(M.DEFAULTS) do st[k] = v end
    local f = io.open(M.state_file_path())
    if not f then return st, false end
    for line in f:lines() do
        local k, v = line:match("^([%w_]+)=(.*)$")
        if k and M.DEFAULTS[k] ~= nil then
            if type(M.DEFAULTS[k]) == "number" then
                st[k] = tonumber(v) or M.DEFAULTS[k]
            else
                st[k] = v
            end
        end
    end
    f:close()
    return st, true
end

function M.write_state(st)
    local tmp = M.state_file_path() .. ".tmp"
    local f = assert(io.open(tmp, "w"))
    for _, k in ipairs(STATE_KEYS) do
        local v = st[k]; if v == nil then v = M.DEFAULTS[k] end
        f:write(k .. "=" .. tostring(v) .. "\n")
    end
    f:close()
    os.rename(tmp, M.state_file_path())   -- escrita atómica
end

return M
```

- [ ] **Step 5: Correr — tem de passar**

Run: `lua5.4 test_hyprvision.lua`
Expected: `✓ 2 testes OK`

- [ ] **Step 6: Commit**

```bash
git add core.lua test_hyprvision.lua
git commit -m "v5: core.lua com estado key=value + harness de testes Lua"
```

---

### Task 2: Perfis em Lua, loader e índice do menu

**Files:**
- Create: `profiles/cinema_desktop.lua`, `profiles/tn_recovery.lua`, `profiles/cinema_film.lua`, `profiles/cinema_oled.lua`, `profiles/eink.lua`, `profiles/focus.lua`, `profiles/night.lua`, `profiles/paper.lua`, `profiles/paper_soft.lua`, `profiles/reset.lua`
- Delete: `profiles/correction/`, `profiles/experience/`, `profiles/system/` (os .toml)
- Modify: `core.lua`, `test_hyprvision.lua`

**Interfaces:**
- Consumes: `core.setup`, `M.base`.
- Produces: `core.load_profile(id) -> prof|nil, err` (prof: `{id, name, icon, category, shader?, temperature, brightness, gamma, icc?}`; `shader` é relativo a `shaders/`), `core.list_profiles() -> lista ordenada` (correction → experience → system, nome dentro da categoria), `core.write_menu_index()` → escreve `state/profiles.menu` com linhas `id\ticon\tname\tcategory`.

- [ ] **Step 1: Testes que falham** — acrescentar a `test_hyprvision.lua`:

```lua
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
```

- [ ] **Step 2: Correr — falham** (`attempt to call a nil value 'list_profiles'`)

- [ ] **Step 3: Converter os 10 perfis.** Conteúdo integral (valores copiados dos .toml v4 — o executor confirma cada um com `cat profiles/*/<id>.toml` antes de apagar):

`profiles/night.lua`:
```lua
-- Luz azul mínima. Preservação de melatonina antes de dormir.
return {
    name = "Night", icon = "🌙", category = "experience",
    temperature = 3600, brightness = 0.80, gamma = 1.0,
    shader = "experience/night.glsl",
}
```

`profiles/reset.lua`:
```lua
-- Ecrã neutro: sem shader, gamma de fábrica.
return {
    name = "Reset", icon = "⚡", category = "system",
    temperature = 6500, brightness = 1.0, gamma = 1.0,
    shader = nil,
}
```

Os restantes 8 seguem exactamente o mesmo molde, com `name/icon/category/temperature/brightness/gamma` copiados do respectivo `.toml` e `shader = "<categoria>/<id>.glsl"` (ex.: `correction/tn_recovery.glsl`). Se um `.toml` tiver `[icc]`, copiar para `icc = "<ficheiro>"`. Depois: `git rm -r profiles/correction profiles/experience profiles/system`.

- [ ] **Step 4: Implementar em `core.lua`** (acrescentar antes do `return M`):

```lua
-- ── Perfis ───────────────────────────────────────────────────────────
function M.load_profile(id)
    if not id or id == "" then return nil, "perfil vazio" end
    local path = M.base .. "/profiles/" .. id .. ".lua"
    local chunk = loadfile(path)
    if not chunk then return nil, "perfil não encontrado: " .. id end
    local ok, prof = pcall(chunk)
    if not ok or type(prof) ~= "table" then
        return nil, "perfil inválido: " .. id
    end
    prof.id = id
    return prof
end

local CAT_ORDER = { correction = 1, experience = 2, system = 3 }

function M.list_profiles()
    local out = {}
    local p = io.popen("ls '" .. M.base .. "/profiles' 2>/dev/null")
    if p then
        for f in p:lines() do
            local id = f:match("^(.+)%.lua$")
            if id then
                local prof = M.load_profile(id)
                if prof then out[#out + 1] = prof end
            end
        end
        p:close()
    end
    table.sort(out, function(a, b)
        local ca = CAT_ORDER[a.category] or 9
        local cb = CAT_ORDER[b.category] or 9
        if ca ~= cb then return ca < cb end
        return (a.name or a.id) < (b.name or b.id)
    end)
    return out
end

function M.write_menu_index()
    local f = assert(io.open(M.state_dir .. "/profiles.menu.tmp", "w"))
    for _, p in ipairs(M.list_profiles()) do
        f:write(table.concat({ p.id, p.icon, p.name, p.category }, "\t") .. "\n")
    end
    f:close()
    os.rename(M.state_dir .. "/profiles.menu.tmp", M.state_dir .. "/profiles.menu")
end
```

- [ ] **Step 5: Correr — passam** (`✓ 5 testes OK`)

- [ ] **Step 6: Commit** — `git add -A && git commit -m "v5: perfis em Lua + loader + índice do menu"`

---

### Task 3: Compose GLSL com dither

**Files:**
- Modify: `core.lua`, `test_hyprvision.lua`

**Interfaces:**
- Consumes: `M.runtime`, `M.PAPER_INTENSITY`.
- Produces: `core.compose(shader_abs|nil, paper, dim) -> merged_path|nil` (nil = nada activo → reset), `core.shader_is_animated(src) -> boolean`, `M.PAPER_INTENSITY = {off=0.0, light=0.028, medium=0.052, heavy=0.085}`. **Todo o shader activo passa pelo wrapper** (dither sempre presente — muda o comportamento v4 de "perfil puro passa directo").

- [ ] **Step 1: Testes que falham**:

```lua
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
```

Nota: se `glslangValidator -S frag` reclamar da extensão, o executor replica a invocação exacta do teste Python v4 (`git show main:test_hyprvision.py`, função `test_glsl_syntax`).

- [ ] **Step 2: Correr — falham**

- [ ] **Step 3: Implementar em `core.lua`.** Template com tokens `@X@` substituídos por `gsub` com função (evita a armadilha dos `%` do GLSL em `string.format`):

```lua
-- ── Compose de shaders ───────────────────────────────────────────────
M.PAPER_INTENSITY = { off = 0.0, light = 0.028, medium = 0.052, heavy = 0.085 }

-- linhas globais do perfil que o wrapper re-declara
local GLOBAL_PATTERNS = {
    "^%s*#version", "^%s*precision%s", "^%s*in%s+vec2%s+v_texcoord",
    "^%s*varying%s+vec2%s+v_texcoord", "^%s*layout%s*%(.-%)%s*out%s+vec4%s+fragColor",
    "^%s*out%s+vec4%s+fragColor", "^%s*uniform%s+sampler2D%s+tex",
}

function M.shader_is_animated(src)
    return src:match("uniform%s+float%s+time") ~= nil
end

local function strip_globals(src)
    local out = {}
    for line in (src .. "\n"):gmatch("(.-)\n") do
        local global = false
        for _, pat in ipairs(GLOBAL_PATTERNS) do
            if line:match(pat) then global = true break end
        end
        if not global then out[#out + 1] = line end
    end
    return table.concat(out, "\n")
end

local WRAPPER = [[
#version 300 es
// HyprVision 5 · Shader Composto (gerado automaticamente)
// perfil=@NAME@  paper=@PAPER@  dim=@DIMPCT@%
// highp obrigatório: perfis usam ruído que excede fp16 (mediump em
// Mesa/AMD) → NaN → ecrã preto.
precision highp float;
in vec2 v_texcoord;
layout(location = 0) out vec4 fragColor;
uniform sampler2D tex;

// Hash sem seno (Dave Hoskins) — sem artefactos diagonais nem overflow.
float _hash(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

float _paperNoise(vec2 p) {
    vec2 ip = floor(p);
    vec2 fp = fract(p);
    fp = fp * fp * (3.0 - 2.0 * fp);
    float a = _hash(ip);
    float b = _hash(ip + vec2(1.0, 0.0));
    float c = _hash(ip + vec2(0.0, 1.0));
    float d = _hash(ip + vec2(1.0, 1.0));
    return mix(mix(a, b, fp.x), mix(c, d, fp.x), fp.y);
}

vec4 _fc;

@PROFILE_BODY@

void main() {
    _fc = texture(tex, v_texcoord);

    // Camada 1: Perfil base
@PROFILE_CALL@

    // Camada 2: Paper Texture (superfície e-ink)
    float _pi = @PI@;
    if (_pi > 0.001) {
        // Grão em duas oitavas — 2ª rodada ~37° para quebrar a grelha
        float _g1 = _paperNoise(v_texcoord * 700.0);
        float _g2 = _paperNoise(mat2(0.8, -0.6, 0.6, 0.8) * v_texcoord * 1400.0 + vec2(0.37, 0.63));
        // Mottling de baixa frequência — manchas da polpa
        float _m  = _paperNoise(v_texcoord * 90.0 + vec2(7.13, 3.71));
        // Fibras horizontais subtis (anisotropia do papel)
        float _fib = _paperNoise(vec2(v_texcoord.x * 110.0, v_texcoord.y * 900.0));
        float _tex = (_g1 * 0.55 + _g2 * 0.25 + _m * 0.45 + _fib * 0.35) - 0.80;

        float _lum  = dot(_fc.rgb, vec3(0.2126, 0.7152, 0.0722));
        float _mask = 0.55 + _lum * 0.45;
        // Ganho 3.5 calibrado visualmente (~7/255 rms no heavy)
        _fc.rgb += _tex * _pi * 3.5 * _mask;

        // Papel nunca é preto puro: lift quente das sombras
        vec3  _paperTint = vec3(1.0, 0.97, 0.90) * (0.045 + _m * 0.025);
        float _shadow    = 1.0 - smoothstep(0.0, 0.18, _lum);
        _fc.rgb = mix(_fc.rgb, _paperTint, min(_pi * 4.0, 0.4) * _shadow);

        _fc.r += _g1 * _pi * 0.10;
        _fc.b -= _g1 * _pi * 0.18;
    }

    // Camada 3: Extra Dim
    _fc.rgb *= (1.0 - @DA@);

    // Camada 4: dither ~1 LSB — mata banding das curvas na saída 8-bit
    _fc.rgb += vec3(_hash(gl_FragCoord.xy) - 0.5) / 255.0;

    fragColor = vec4(clamp(_fc.rgb, 0.0, 1.0), _fc.a);
}
]]

local merged_seq = 0

function M.compose(shader_abs, paper, dim)
    paper = paper or "off"; dim = dim or 0
    local pi = M.PAPER_INTENSITY[paper] or 0.0
    local da = dim / 100.0
    if not shader_abs and pi <= 0 and dim <= 0 then return nil end

    local body, call, name = "", "", "none"
    if shader_abs then
        local f = assert(io.open(shader_abs), "shader não existe: " .. shader_abs)
        local raw = f:read("*a"); f:close()
        name = shader_abs:match("([^/]+)$")
        local b = strip_globals(raw)
        -- %f[%w] = fronteira de palavra (equivalente ao \b do v4)
        b = b:gsub("%f[%w]gl_FragColor%f[%W]", "_fc")
        b = b:gsub("%f[%w]fragColor%f[%W]", "_fc")
        b = b:gsub("%f[%w]texture2D%f[%W]", "texture")
        b = b:gsub("void%s+main%s*%(%s*%)", "void _profile_main()")
        body, call = b, "    _profile_main();"
    end

    local src = WRAPPER
        :gsub("@NAME@",  function() return name end)
        :gsub("@PAPER@", function() return paper end)
        :gsub("@DIMPCT@", function() return tostring(dim) end)
        :gsub("@PROFILE_BODY@", function() return body end)
        :gsub("@PROFILE_CALL@", function() return call end)
        :gsub("@PI@", function() return string.format("%.4f", pi) end)
        :gsub("@DA@", function() return string.format("%.4f", da) end)

    merged_seq = merged_seq + 1
    local path = ("%s/merged-%d-%d.glsl"):format(M.runtime, os.time(), merged_seq)
    local f = assert(io.open(path, "w"))
    f:write(src); f:close()
    -- limpa compostos antigos (só os nossos)
    os.execute(("find '%s' -name 'merged-*.glsl' ! -name '%s' -delete")
               :format(M.runtime, path:match("([^/]+)$")))
    M._animated = M.shader_is_animated(src)
    return path
end
```

- [ ] **Step 4: Correr — passam** (com a contagem de shaders impressa)

- [ ] **Step 5: Commit** — `git add -A && git commit -m "v5: compose GLSL em Lua com dither 1 LSB sempre activo"`

---

### Task 4: Lógica adaptativa pura (horário + bateria)

**Files:**
- Modify: `core.lua`, `test_hyprvision.lua`

**Interfaces:**
- Produces: `core.current_slot(slots, now_min) -> slot|nil` (slots: `{name=, hour=, minute=?, profile=, enabled=}`; wrap: antes do primeiro slot do dia vale o último de ontem; ignora `enabled=false` e `profile="none"`), `core.battery_transition(bcfg, prev, cap, status) -> power, action|nil` (power: `"plugged"|"unplugged"|"low"`; action: `{apply=id, remember=true?}` ou `{restore_pre_low=true}`; `prev==nil` é baseline → nunca há acção), `core.read_battery() -> cap|nil, status`.

- [ ] **Step 1: Testes que falham** (semântica copiada dos testes v4 — `git show main:test_hyprvision.py`, `test_schedule_wrap`):

```lua
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
```

- [ ] **Step 2: Correr — falham**

- [ ] **Step 3: Implementar em `core.lua`**:

```lua
-- ── Adaptativo (lógica pura, testável) ──────────────────────────────
function M.current_slot(slots, now_min)
    local best, best_t, latest, latest_t
    for _, s in ipairs(slots or {}) do
        if s.enabled and s.profile and s.profile ~= "none" then
            local t = s.hour * 60 + (s.minute or 0)
            if t <= now_min and (not best_t or t > best_t) then best, best_t = s, t end
            if not latest_t or t > latest_t then latest, latest_t = s, t end
        end
    end
    return best or latest   -- antes do 1º slot de hoje → último de ontem
end

function M.battery_transition(bcfg, prev, cap, status)
    local power
    if status ~= "Discharging" then power = "plugged"
    elseif cap <= (bcfg.threshold or 20) then power = "low"
    else power = "unplugged" end

    if not bcfg.enabled or power == prev or prev == nil then
        return power, nil
    end
    if power == "low" then
        if bcfg.low and bcfg.low ~= "none" then
            return power, { apply = bcfg.low, remember = true }
        end
    elseif prev == "low" and bcfg.restore_after_low then
        return power, { restore_pre_low = true }
    elseif bcfg[power] and bcfg[power] ~= "none" then
        return power, { apply = bcfg[power] }
    end
    return power, nil
end

function M.read_battery()
    for _, b in ipairs({ "BAT0", "BAT1", "BAT2" }) do
        local f = io.open("/sys/class/power_supply/" .. b .. "/capacity")
        if f then
            local cap = tonumber(f:read("*l")); f:close()
            local s = io.open("/sys/class/power_supply/" .. b .. "/status")
            local status = s and s:read("*l") or "Unknown"
            if s then s:close() end
            return cap, status
        end
    end
    return nil, "Unknown"
end
```

- [ ] **Step 4: Correr — passam**

- [ ] **Step 5: Commit** — `git commit -am "v5: horário com wrap e transições de bateria como funções puras"`

---

### Task 5: Orquestração — apply, overlays, gamma, safe-reset, restore, ticks

**Files:**
- Modify: `core.lua`, `test_hyprvision.lua`

**Interfaces:**
- Consumes: tudo das Tasks 1-4; mock `hl` do harness.
- Produces: `core.apply(id) -> ok, err`, `core.overlay(kind, value)` (`kind`: `"paper"` valor `off|light|medium|heavy`, `"dim"` valor 0-50), `core.apply_extra(fname)` (ficheiro em `shaders/extras/`), `core.safe_reset()` (neutro + `state` → `state.bak`), `core.restore()` (reaplica o `state` se existir), `core.restore_backup()` (`state.bak` → `state` + restore), `core.tick_schedule(cfg, mem)`, `core.tick_battery(cfg, mem)` (`mem`: tabela mutável `{prev_slot, prev_power, pre_low}` — vive no init, morre no reload), `core.notify(texto)`.

- [ ] **Step 1: Testes que falham**:

```lua
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
    os.remove(core.state_file_path())
    reset_calls()
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
    os.remove(core.state_file_path())
    os.remove(core.state_file_path() .. ".bak")
    reset_calls()
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
    os.remove(core.state_file_path())
    reset_calls()
    core.tick_schedule(cfg, mem)     -- primeiro tick: só regista
    assert(mem.prev_slot == "always" and last_shader_set() == nil,
           "primeiro tick não devia aplicar (apply_on_start=false)")
end
```

- [ ] **Step 2: Correr — falham**

- [ ] **Step 3: Implementar em `core.lua`**:

```lua
-- ── Escrita no Hyprland ──────────────────────────────────────────────
function M.notify(text)
    pcall(function()
        M.hl.notification.create({ text = text, timeout = 3000, icon = "display" })
    end)
end

local function set_shader(path)
    -- ordem importa (fix v4): shader novo primeiro, tracking depois —
    -- senão o Hyprland revalida o shader antigo e verte avisos de uniform
    M.hl.config({ decoration = { screen_shader = path or "" } })
    M.hl.config({ debug = { damage_tracking = (path and M._animated) and 0 or 2 } })
end

local function set_icc(icc_path)
    for _, m in ipairs(M.hl.get_monitors() or {}) do
        if m.name then
            M.hl.monitor({
                output   = m.name,
                mode     = string.format("%dx%d@%.3f", m.width or 1920,
                                         m.height or 1080, m.refreshRate or 60),
                position = (m.x or 0) .. "x" .. (m.y or 0),
                scale    = m.scale or 1.0,
                icc      = icc_path or "",
            })
        end
    end
end

-- ── Gamma via wl-gammarelay-rs ───────────────────────────────────────
local GAMMA_CMD = "busctl --user %s-property rs.wl-gammarelay / rs.wl.gammarelay %s"

local function gamma_get(prop)
    local p = io.popen((GAMMA_CMD):format("get", prop) .. " 2>/dev/null")
    if not p then return nil end
    local out = p:read("*a"); p:close()
    return tonumber(out and out:match("([%d%.]+)%s*$"))
end

local function gamma_set(prop, sig, val)
    local v = (sig == "q") and tostring(math.floor(val + 0.5))
              or string.format("%.4f", val)
    M.hl.exec_cmd((GAMMA_CMD):format("set", prop) .. " " .. sig .. " " .. v)
end

local function gamma_ramp(temp, bright, gam)
    local cur = {
        Temperature = gamma_get("Temperature") or 6500,
        Brightness  = gamma_get("Brightness") or 1.0,
        Gamma       = gamma_get("Gamma") or 1.0,
    }
    local tgt = { Temperature = temp, Brightness = bright, Gamma = gam }
    local sig = { Temperature = "q", Brightness = "d", Gamma = "d" }
    local STEPS = 10
    local function step(i)
        for prop, t in pairs(tgt) do
            gamma_set(prop, sig[prop], cur[prop] + (t - cur[prop]) * i / STEPS)
        end
        if i < STEPS then
            M.hl.timer(function() step(i + 1) end, { timeout = 35, type = "oneshot" })
        end
    end
    step(1)
end

function M.set_gamma(temp, bright, gam)
    if gamma_get("Temperature") == nil then
        -- pacote sem D-Bus activation: arranca on-demand; instâncias
        -- concorrentes são inofensivas (só uma ganha o nome no bus)
        M.hl.exec_cmd("wl-gammarelay-rs")
        M.hl.timer(function() gamma_ramp(temp, bright, gam) end,
                   { timeout = 600, type = "oneshot" })
    else
        gamma_ramp(temp, bright, gam)
    end
end

-- ── Pipeline ─────────────────────────────────────────────────────────
local function apply_visuals(st)
    local shader_abs = nil
    if st.extra ~= "" then
        shader_abs = M.base .. "/shaders/extras/" .. st.extra
    elseif st.shader ~= "" then
        shader_abs = M.base .. "/shaders/" .. st.shader
    end
    set_shader(M.compose(shader_abs, st.paper, st.dim))
    set_icc(st.icc)
    M.set_gamma(st.temperature, st.brightness, st.gamma)
end

function M.apply(id)
    local prof, err = M.load_profile(id)
    if not prof then M.log("apply: " .. tostring(err)); return false, err end
    local st = M.read_state()
    st.profile     = id
    st.shader      = prof.shader or ""
    st.extra       = ""
    st.icc         = prof.icc or ""
    st.temperature = prof.temperature or 6500
    st.brightness  = prof.brightness or 1.0
    st.gamma       = prof.gamma or 1.0
    apply_visuals(st)
    M.write_state(st)
    M.notify(prof.icon .. " " .. prof.name)
    return true
end

function M.overlay(kind, value)
    local st = M.read_state()
    if kind == "paper" then st.paper = value
    elseif kind == "dim" then st.dim = tonumber(value) or 0
    else return false, "overlay desconhecido: " .. tostring(kind) end
    apply_visuals(st)
    M.write_state(st)
    M.notify(kind == "paper" and ("📄 Paper: " .. st.paper)
             or ("🔅 Dim: " .. st.dim .. "%"))
    return true
end

function M.apply_extra(fname)
    local st = M.read_state()
    st.extra, st.profile, st.shader = fname, "", ""
    apply_visuals(st)
    M.write_state(st)
    M.notify("🌐 " .. fname)
    return true
end

function M.safe_reset()
    set_shader(nil)
    set_icc("")
    M.set_gamma(6500, 1.0, 1.0)
    -- arquiva em vez de apagar: boot seguinte fica neutro (um perfil
    -- roto não volta), mas o menu pode recuperar via restore_backup
    os.rename(M.state_file_path(), M.state_file_path() .. ".bak")
    M.notify("⚡ Reset — ecrã neutro (estado guardado)")
    return true
end

function M.restore()
    local st, existed = M.read_state()
    if not existed then return false end
    apply_visuals(st)
    return true
end

function M.restore_backup()
    if not os.rename(M.state_file_path() .. ".bak", M.state_file_path()) then
        M.notify("Nada para recuperar."); return false
    end
    M.restore()
    local st = M.read_state()
    M.notify("↩ Recuperado: " .. (st.profile ~= "" and st.profile or st.extra))
    return true
end

-- ── Ticks (chamados pelos timers do init; mem morre no reload) ──────
function M.tick_schedule(cfg, mem)
    local sc = cfg.schedule
    if not (sc and sc.enabled) then return end
    local now = tonumber(os.date("%H")) * 60 + tonumber(os.date("%M"))
    local slot = M.current_slot(sc.slots, now)
    if not slot then mem.prev_slot = nil; return end
    if slot.name == mem.prev_slot then return end
    local first = (mem.prev_slot == nil)
    mem.prev_slot = slot.name
    if first and not sc.apply_on_start then return end
    M.notify("🕐 Horário (" .. slot.name .. ") → " .. slot.profile)
    M.apply(slot.profile)
end

function M.tick_battery(cfg, mem)
    local bc = cfg.battery
    if not (bc and bc.enabled) then return end
    local cap, status = M.read_battery()
    if not cap then return end
    local power, act = M.battery_transition(bc, mem.prev_power, cap, status)
    mem.prev_power = power
    if not act then return end
    if act.restore_pre_low then
        if mem.pre_low and mem.pre_low ~= "" then
            M.notify("🔋 Bateria recuperada → " .. mem.pre_low)
            M.apply(mem.pre_low)
        end
        mem.pre_low = nil
    else
        if act.remember then mem.pre_low = M.read_state().profile end
        M.notify("⚠️ Bateria (" .. cap .. "%) → " .. act.apply)
        M.apply(act.apply)
    end
end
```

- [ ] **Step 4: Correr — passam** (`✓ 14 testes OK`)

- [ ] **Step 5: Commit** — `git commit -am "v5: pipeline apply/overlay/reset/restore + gamma com rampa e ticks adaptativos"`

---

### Task 6: config.lua e init.lua

**Files:**
- Create: `config.lua`, `init.lua`
- Delete: `hyprvision_lua.lua` (substituído pelo init)

**Interfaces:**
- Consumes: tudo do `core`; API `hl` real.
- Produces: global `_G.hv` com `apply(id)`, `overlay(kind, val)`, `apply_extra(f)`, `safe_reset()`, `restore_backup()` — a superfície que o launcher invoca via `hyprctl eval`. `config.lua` devolve `{keys={menu=,reset=}, battery={...}, schedule={enabled=, apply_on_start=, slots={...}}}`.

Sem teste unitário (é wiring sobre a API real) — verificação ao vivo na Task 9. O `lua5.4 test_hyprvision.lua` continua a ter de passar (garante que o require de `core` não partiu).

- [ ] **Step 1: Criar `config.lua`** (valores migrados do `daemon_config.toml` actual do utilizador — confirmar com `cat ~/.config/hypr/hyprvision/daemon_config.toml`):

```lua
-- HyprVision · Configuração do utilizador.
-- Editar e correr `hyprctl reload` para aplicar.
-- Em "profile": id de um perfil (ver profiles/) ou "none" para não agir.
return {
    keys = {
        menu  = "SUPER + H",         -- abre o menu Rofi
        reset = "SUPER + SHIFT + H", -- reset de emergência
    },
    battery = {
        enabled = true,
        threshold = 20,        -- % abaixo da qual entra em modo "low"
        plugged   = "none",    -- carregador ligado ("none" = manter)
        unplugged = "none",    -- desligado, bateria ok
        low       = "eink",    -- bateria abaixo do threshold
        restore_after_low = true,
    },
    schedule = {
        enabled = true,
        apply_on_start = false,  -- true = aplica o slot logo no arranque
        slots = {
            { name = "dawn",    enabled = true,  hour = 6,  profile = "reset" },
            { name = "morning", enabled = false, hour = 9,  profile = "cinema_desktop" },
            { name = "noon",    enabled = false, hour = 14, profile = "focus" },
            { name = "evening", enabled = false, hour = 19, profile = "paper_soft" },
            { name = "night",   enabled = true,  hour = 21, profile = "night" },
        },
    },
}
```

- [ ] **Step 2: Criar `init.lua`**:

```lua
-- HyprVision 5 · init.lua — wiring no Hyprland (≥ 0.55, config Lua).
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
```

- [ ] **Step 3: Sanidade** — `lua5.4 test_hyprvision.lua` continua verde; `lua5.4 -e "local f=loadfile('init.lua') assert(f)"` (só parse — não executar fora do Hyprland); `git rm hyprvision_lua.lua`

- [ ] **Step 4: Commit** — `git add -A && git commit -m "v5: init.lua (wiring) e config.lua do utilizador"`

---

### Task 7: launcher.sh v5 + smoke test

**Files:**
- Modify: `ui/launcher.sh` (reescrita), `test_hyprvision.lua`

**Interfaces:**
- Consumes: `state/state` (key=value), `state/profiles.menu` (`id\ticon\tname\tcategory`), `state/state.bak` (presença → linha "Recuperar"), `hyprctl eval "hv.…"`.
- Produces: menu com a mesma cara do v4 (pango, submenus paper/dim/extras) menos o submenu daemon; nova entrada "↩ Recuperar último estado" quando existe `state.bak`.

- [ ] **Step 1: Smoke test que falha** — acrescentar a `test_hyprvision.lua` (corre o launcher real com `rofi`/`hyprctl`/`notify-send` falsos; padrão herdado da regressão v4.1.0 do `set -e`):

```lua
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
```

- [ ] **Step 2: Correr — falha** (o launcher actual chama o CLI Python)

- [ ] **Step 3: Reescrever `ui/launcher.sh`**:

```bash
#!/usr/bin/env bash
# HyprVision 5 · Launcher Rofi
# Lê o estado de state/state (o `hyprctl eval` não devolve output — o
# ficheiro é a interface de leitura) e envia acções via hyprctl eval.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"
STATE="$BASE_DIR/state/state"
MENU_IDX="$BASE_DIR/state/profiles.menu"
ROFI_THEME="$BASE_DIR/rofi/hyprvision.rasi"

sv() {   # valor de uma chave do estado (default $2)
    local v=""
    [[ -f "$STATE" ]] && v=$(grep -m1 "^$1=" "$STATE" | cut -d= -f2-) || true
    echo "${v:-${2:-}}"
}

hv() {   # invoca a superfície Lua
    hyprctl eval "hv.$1" >/dev/null
}

PROFILE=$(sv profile reset); EXTRA=$(sv extra); PAPER=$(sv paper off); DIM=$(sv dim 0)
STATUS="◈ ${EXTRA:-$PROFILE}"
[[ "$PAPER" != "off" ]] && STATUS="$STATUS  📄$PAPER"
[[ "$DIM" != "0" ]] && STATUS="$STATUS  🔅$DIM%"

rofi_menu() { rofi -dmenu -p "$1" -theme "$ROFI_THEME" -no-custom -markup-rows -format s; }
pick_id()   { grep -o '\[[^]]*\]' | tail -1 | tr -d '[]'; }
dim_row()   { printf '%s   <span alpha="30%%" size="small">[%s]</span>\n' "$1" "$2"; }
sep()       { printf '<span alpha="55%%" style="italic">──  %s  ──</span>\n' "$1"; }

main_rows() {
    local last_cat="" id icon name cat mark
    while IFS=$'\t' read -r id icon name cat; do
        if [[ "$cat" != "$last_cat" ]]; then
            case "$cat" in
                correction) sep "🔧 CORRECTION" ;;
                experience) sep "🎭 EXPERIENCE" ;;
                system)     sep "⚙️  SYSTEM" ;;
                *)          sep "$cat" ;;
            esac
            last_cat="$cat"
        fi
        mark=""; [[ "$id" == "$PROFILE" && -z "$EXTRA" ]] && mark="  ✓"
        dim_row "$icon $name$mark" "$id"
    done < "$MENU_IDX"

    sep "🧩 OVERLAYS · EXTRAS"
    local pm=""; [[ "$PAPER" != "off" ]] && pm="  ✓"
    dim_row "📄 Paper Texture: $PAPER  ▸$pm" "__paper__"
    local dm=""; [[ "$DIM" != "0" ]] && dm="  ✓"
    dim_row "🔅 Extra Dim: ${DIM}%  ▸$dm" "__dim__"
    local em=""; [[ -n "$EXTRA" ]] && em="  ✓"
    dim_row "🌐 Shaders extra${EXTRA:+: $EXTRA}  ▸$em" "__extras__"
    [[ -f "$STATE.bak" ]] && dim_row "↩ Recuperar último estado" "__recover__"
    dim_row "📝 Editar configuração" "__config__"
}

back_row() { dim_row "↩ Voltar" "__back__"; }

choice=$(main_rows | rofi_menu "$STATUS") || exit 0
[[ -z "$choice" ]] && exit 0
[[ "$choice" == *"──"* ]] && exec "$0"
ID=$(echo "$choice" | pick_id)
# `if`, nunca `[[ ]] &&` no fim de bloco: regressão set -e da v4.1.0
if [[ -z "$ID" ]]; then exec "$0"; fi

case "$ID" in
    __paper__)
        SEL=$({ back_row
                for lvl in off light medium heavy; do
                    mark=""; [[ "$lvl" == "$PAPER" ]] && mark="  ✓"
                    dim_row "📄 $lvl$mark" "$lvl"
                done; } | rofi_menu "📄 Paper Texture" | pick_id) || true
        [[ -z "${SEL:-}" ]] && exit 0
        if [[ "$SEL" == "__back__" ]]; then exec "$0"; fi
        hv "overlay('paper', '$SEL')"
        ;;
    __dim__)
        SEL=$({ back_row
                for lvl in 0 10 20 30 40 50; do
                    mark=""; [[ "$lvl" == "$DIM" ]] && mark="  ✓"
                    dim_row "🔅 $lvl%$mark" "$lvl"
                done; } | rofi_menu "🔅 Extra Dim" | pick_id) || true
        [[ -z "${SEL:-}" ]] && exit 0
        if [[ "$SEL" == "__back__" ]]; then exec "$0"; fi
        hv "overlay('dim', $SEL)"
        ;;
    __extras__)
        EXTRAS_DIR="$BASE_DIR/shaders/extras"
        mapfile -t EXTRAS < <(find "$EXTRAS_DIR" \( -name "*.glsl" -o -name "*.frag" \) \
            -printf "%f\n" 2>/dev/null | sort)
        if ((${#EXTRAS[@]} == 0)); then
            rofi -e "Pasta extras vazia.\n\nColoca .glsl em:\n$EXTRAS_DIR" \
                -theme "$ROFI_THEME" || true
            exit 0
        fi
        SEL=$({ back_row
                for f in "${EXTRAS[@]}"; do
                    mark=""; [[ "$f" == "$EXTRA" ]] && mark="  ✓"
                    dim_row "🌐 ${f%.*}$mark" "$f"
                done; } | rofi_menu "🌐 Shaders extra" | pick_id) || true
        [[ -z "${SEL:-}" ]] && exit 0
        if [[ "$SEL" == "__back__" ]]; then exec "$0"; fi
        hv "apply_extra('$SEL')"
        ;;
    __recover__)
        hv "restore_backup()"
        ;;
    __config__)
        CONFIG="$BASE_DIR/config.lua"
        EDITOR_CMD=""
        for ed in "${VISUAL:-}" "${EDITOR:-}" code gedit kate nano; do
            if [[ -n "$ed" ]] && command -v "${ed%% *}" &>/dev/null; then
                EDITOR_CMD="$ed"; break
            fi
        done
        if [[ -z "$EDITOR_CMD" ]]; then
            xdg-open "$CONFIG" 2>/dev/null || \
                notify-send -a HyprVision "Config" "Edita manualmente: $CONFIG"
        else
            case "${EDITOR_CMD%% *}" in
                code|gedit|kate) $EDITOR_CMD "$CONFIG" & disown ;;
                *)
                    TERM_CMD=""
                    for t in foot kitty alacritty wezterm ghostty konsole xterm; do
                        command -v "$t" &>/dev/null && { TERM_CMD="$t"; break; }
                    done
                    if [[ -n "$TERM_CMD" ]]; then
                        $TERM_CMD -e $EDITOR_CMD "$CONFIG" & disown
                    else
                        xdg-open "$CONFIG" 2>/dev/null || true
                    fi ;;
            esac
        fi
        notify-send -a HyprVision "Config" "Após guardar: hyprctl reload"
        ;;
    *)
        hv "apply('$ID')"
        ;;
esac
```

- [ ] **Step 4: Correr — todos passam** (`✓ 15 testes OK`)

- [ ] **Step 5: Commit** — `git commit -am "v5: launcher lê state/ e fala hv.* via hyprctl eval; entrada de recuperação"`

---

### Task 8: Instalador, remoção do Python, docs

**Files:**
- Modify: `install.sh`, `uninstall.sh`, `README.md`, `CHANGELOG.md`
- Delete: `bin/hyprvision`, `bin/hyprvision-daemon`, `core/*.py` (o pacote inteiro `core/`), `test_hyprvision.py`, `daemon_config.example.toml`, `hyprvision.conf.example`

**Interfaces:**
- Produces: `install.sh` que instala os .lua/perfis/shaders/ui/rofi em `$DEST`, remove artefactos v4 do destino (`bin/`, `core/`, `daemon_config.toml`, `hyprvision_lua.lua`), garante o bloco `require` no `hyprland.lua` (removendo o bloco v4 `hyprvision_lua` se existir) e termina com `hyprctl reload` se dentro do Hyprland. Requisito: `hyprland.lua` obrigatório (v5 é Lua-only; sem ele, aborta com mensagem a apontar para a v4).

- [ ] **Step 1: Reescrever `install.sh`**:

```bash
#!/usr/bin/env bash
# HyprVision 5 · Instalador (Hyprland ≥ 0.55 com config hyprland.lua)
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST="$HOME/.config/hypr/hyprvision"
HYPRLUA="$HOME/.config/hypr/hyprland.lua"

echo "── HyprVision 5 · instalação ──"
[[ -f "$HYPRLUA" ]] || {
    echo "✗ $HYPRLUA não existe. O v5 requer config Lua (parser non-legacy)."
    echo "  Para hyprland.conf clássico usa a v4 (branch main)."
    exit 1
}
command -v rofi &>/dev/null || echo "⚠  rofi em falta (menu não funcionará)"
command -v wl-gammarelay-rs &>/dev/null || \
    echo "⚠  wl-gammarelay-rs em falta (temperatura/brightness desactivados)"

# daemon v4 ainda a correr? pára-o
pkill -f hyprvision-daemon 2>/dev/null || true

mkdir -p "$DEST"
rsync -a --delete \
    --exclude 'state/' --exclude '.git/' --exclude 'docs/' \
    --exclude 'install.sh' --exclude 'uninstall.sh' \
    --exclude 'test_hyprvision.lua' --exclude 'README.md' --exclude 'CHANGELOG.md' \
    --filter 'protect config.lua' \
    "$SRC"/ "$DEST"/
chmod +x "$DEST/ui/launcher.sh"
[[ -f "$DEST/config.lua" ]] || cp "$SRC/config.lua" "$DEST/config.lua"
echo "✓ Ficheiros em $DEST (config.lua preservado)"

# remove o require v4 e garante o v5 (idempotente)
sed -i '/hyprvision_lua/d' "$HYPRLUA"
if ! grep -q 'hyprvision/init' "$HYPRLUA" && ! grep -q 'require("init")' "$HYPRLUA"; then
    cat >> "$HYPRLUA" <<'LUA'

-- HyprVision 5
package.path = package.path .. ";" .. os.getenv("HOME") .. "/.config/hypr/hyprvision/?.lua"
require("init")
LUA
    echo "✓ require adicionado ao hyprland.lua"
fi

if [[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]]; then
    hyprctl reload >/dev/null && echo "✓ Hyprland recarregado — HyprVision activo"
fi
echo "── Pronto. Menu: SUPER+H · Reset: SUPER+SHIFT+H ──"
```

Nota `--delete` + `--filter 'protect config.lua'`: limpa os artefactos v4 do destino (bin/, core/, hyprvision_lua.lua, daemon_config.toml) preservando a config do utilizador. `state/` está em `--exclude`, logo também sobrevive.

- [ ] **Step 2: Actualizar `uninstall.sh`** — trocar a paragem do daemon por `pkill -f hyprvision-daemon || true`, repor neutro via `hyprctl eval "hv.safe_reset()"` (com `|| true`), remover `$DEST` e as linhas `hyprvision` do `hyprland.lua` (`sed -i '/hyprvision/d'`).

- [ ] **Step 3: Apagar o Python e actualizar docs**

```bash
git rm -r bin core test_hyprvision.py daemon_config.example.toml hyprvision.conf.example
```

`CHANGELOG.md` — nova secção no topo:

```markdown
## v5.0.0 — 2026-07-13

Reescrita Lua-nativa. O HyprVision passa a viver dentro do Hyprland.

### Alterado
- **Zero Python, zero daemon próprio**: `init.lua` + `core.lua` correm no runtime
  Lua do compositor; horário e bateria via `hl.timer`, reaplicação pós-reload
  via re-execução do init (o runtime é recriado em cada reload — verificado).
- Perfis passam de TOML para `profiles/*.lua`; config do daemon → `config.lua`.
- O launcher lê `state/state` (key=value) e envia acções via `hyprctl eval "hv.*"`.
- Gamma continua no wl-gammarelay-rs (rampas de hardware), com rampa suave
  de 10 passos e arranque on-demand.

### Adicionado
- **Dither ~1 LSB** sempre activo no shader composto + `render:use_fp16` +
  `render:icc_vcgt_enabled` — menos banding no painel 8-bit.
- **Safe-reset recuperável**: arquiva o estado em `state.bak` em vez de o
  apagar; entrada "Recuperar último estado" no menu.
- `test_hyprvision.lua` (lua5.4 standalone, `hl` mock) com smoke test do launcher.

### Removido
- CLI `hyprvision`, `hyprvision-daemon`, `core/*.py`, listener socket2,
  PID files, parser TOML, submenu do daemon no Rofi.
```

`README.md` — actualizar: requisitos (Hyprland ≥ 0.55 com `hyprland.lua`, lua5.4 só para testes), instalação (`./install.sh`), arquitectura (parágrafo: módulo Lua, sem daemon), e trocar referências ao CLI/daemon pelo menu + `hyprctl eval "hv.apply('night')"` para scripting.

- [ ] **Step 4: Sanidade + commit**

```bash
lua5.4 test_hyprvision.lua && bash -n install.sh && bash -n uninstall.sh && bash -n ui/launcher.sh
git add -A && git commit -m "v5: instalador Lua-only, remoção do Python, docs 5.0.0"
```

---

### Task 9: Instalação ao vivo e verificação

**Files:**
- Modify: nenhum (fix-forward se algo falhar; cada fix é commit próprio)
- Modify: `docs/superpowers/specs/2026-07-13-hyprvision5-lua-native-design.md` (nota do desvio key=value + resolução da incógnita do reload)

Checklist ao vivo (executor corre; itens visuais pedem confirmação ao utilizador):

- [ ] **Step 1:** `./install.sh` — sem erros; `hyprctl reload` incluído corre; `state/hyprvision.log` ganha a linha `carregado (init)`.
- [ ] **Step 2:** `hyprctl eval "hv.apply('night')"` → `hyprctl getoption decoration:screen_shader` devolve `merged-*.glsl`; `busctl --user get-property rs.wl-gammarelay / rs.wl.gammarelay Temperature` → `q 3600`; `state/state` tem `profile=night`.
- [ ] **Step 3:** menu real (fake-rofi contra o launcher instalado, como no smoke test mas com hyprctl real): escolher paper `medium` → shader recomposto com `0.0520` e `state` com `paper=medium`.
- [ ] **Step 4:** `hyprctl reload` → em ≤2 s o shader volta (restore no init); estado intacto.
- [ ] **Step 5:** `hyprctl eval "hv.safe_reset()"` → shader vazio, 6500K, `state.bak` existe; `hv.restore_backup()` → night volta.
- [ ] **Step 6:** `pgrep -f hyprvision` → nada (zero processos nossos); `pgrep wl-gammarelay-rs` → 1.
- [ ] **Step 7:** timers: `hyprctl eval` com um slot de teste 1 minuto no futuro (config temporária), esperar o tick de 60 s, confirmar aplicação; repor config.
- [ ] **Step 8 (utilizador):** com Night activo, degradê escuro (ex.: wallpaper com céu) — banding visivelmente menor que na v4; Super+H e Super+Shift+H a funcionar.
- [ ] **Step 9:** actualizar o spec (desvio key=value; incógnita do reload resolvida: runtime recriado), commit final `git commit -am "v5: verificação ao vivo + spec actualizado"`.

---

## Self-review (feito)

- **Cobertura do spec:** módulos ✓ (T1/T5/T6), perfis Lua ✓ (T2), compose+dither ✓ (T3), adaptativo ✓ (T4/T5/T6), gamma/rampa/on-demand ✓ (T5), estado/interface launcher ✓ (T1/T7), safe-reset .bak + recuperar ✓ (T5/T7), fp16/vcgt ✓ (T6), robustez pcall/log ✓ (T5/T6), testes ✓ (T1-T7), install/migração ✓ (T8), critérios de sucesso ✓ (T9). Desvio documentado: estado key=value em vez de JSON (T9 actualiza o spec).
- **Placeholders:** nenhum — todo o código está integral; os 8 perfis restantes da T2 são cópia mecânica do molde com valores dos .toml existentes no repo.
- **Consistência de tipos/nomes:** `hv.*` (init T6) = chamadas do launcher (T7) ✓; campos do estado (T1) = usados em T5/T7 ✓; `profiles.menu` (T2) = parsing do launcher (T7) ✓; assinatura `hl.timer(fn, {timeout, type})` uniforme ✓.
