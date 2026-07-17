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

-- ── Escrita no Hyprland ──────────────────────────────────────────────
function M.notify(text)
    pcall(function()
        M.hl.notification.create({ text = text, timeout = 3000 })
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
            local spec = {
                output   = m.name,
                mode     = string.format("%dx%d@%.3f", m.width or 1920,
                                         m.height or 1080, m.refreshRate or 60),
                position = (m.x or 0) .. "x" .. (m.y or 0),
                scale    = m.scale or 1.0,
            }
            -- hl.monitor rejeita icc="" — omitir o campo limpa o perfil
            if icc_path and icc_path ~= "" then spec.icc = icc_path end
            M.hl.monitor(spec)
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
    if prof.paper then st.paper = prof.paper end
    if prof.dim   then st.dim   = prof.dim   end
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

return M
