-- Levanta sombras e adiciona vibração selectiva. Ideal para painéis TN
-- antigos e notebooks lavados.
return {
    name = "TN Recovery", icon = "🖥️", category = "correction",
    temperature = 5800, brightness = 1.0, gamma = 1.12,
    shader = "correction/tn_recovery.glsl",
}
