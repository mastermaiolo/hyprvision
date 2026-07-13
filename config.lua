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
