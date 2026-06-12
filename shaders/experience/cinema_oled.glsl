#version 300 es
// HyprVision · Cinema OLED
// Simula painel OLED num LCD: pretos esmagados a zero com toe suave,
// cores vibrantes (vibrance selectivo) e realces com punch.
precision highp float;
in vec2 v_texcoord;
layout(location = 0) out vec4 fragColor;
uniform sampler2D tex;

void main() {
    vec4 color = texture(tex, v_texcoord);
    float lum = dot(color.rgb, vec3(0.2126, 0.7152, 0.0722));

    // ── Pretos OLED ──────────────────────────────────────────────
    // Remove o pedestal de luminância e re-expande com toe suave:
    // tudo abaixo de ~3.5% vira preto puro, sem corte duro (evita banding)
    float crushed = max(lum - 0.035, 0.0) / 0.965;
    crushed = pow(crushed, 1.08);
    float scale = (lum > 0.0001) ? crushed / lum : 0.0;
    color.rgb *= scale;

    // ── Vibrance ─────────────────────────────────────────────────
    // Reforça mais as cores pouco saturadas, poupa as já saturadas
    // (evita o aspecto caricatural de um boost de saturação cru)
    float lum2 = dot(color.rgb, vec3(0.2126, 0.7152, 0.0722));
    float sat  = length(color.rgb - vec3(lum2));
    float vib  = 1.0 + 0.30 * (1.0 - clamp(sat * 1.8, 0.0, 1.0));
    color.rgb  = mix(vec3(lum2), color.rgb, vib);

    // ── Punch nos realces ────────────────────────────────────────
    color.rgb *= 1.0 + 0.05 * smoothstep(0.60, 1.0, lum2);

    fragColor = vec4(clamp(color.rgb, 0.0, 1.0), color.a);
}
