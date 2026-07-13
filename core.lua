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

return M
