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
