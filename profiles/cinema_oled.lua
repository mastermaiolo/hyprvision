-- Pretos profundos estilo OLED e cores vibrantes. Filmes e jogos num LCD.
-- Backlight a 100% e cor neutra: o contraste vem do shader (esmagar
-- pretos com brightness reduzido mataria os realces).
return {
    name = "Cinema OLED", icon = "🌌", category = "experience",
    temperature = 6500, brightness = 1.0, gamma = 1.0,
    shader = "experience/cinema_oled.glsl",
}
