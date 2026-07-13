#version 300 es
// HyprVision · TN Recovery
// Levanta sombras sem explodir o brilho + vibração selectiva de matiz
// Ideal para painéis TN antigos e ecrãs de notebook "lavados"
precision highp float;
in vec2 v_texcoord;
layout(location = 0) out vec4 fragColor;
uniform sampler2D tex;

// Botões de calibração (afinados ao vivo no painel real)
const float LIFT      = 0.08;  // levantamento de sombras
const float BLACK_TOE = 0.015; // até onde o preto fica intocado (~4/255)
const float SCURVE    = 0.18;  // microcontraste (mix da curva S)
const float VIBRANCE  = 0.45;  // saturação selectiva (só tons lavados)
const float TRIM      = 0.97;  // compensação global do lift

float shadowLift(float v) {
    // preserva o preto puro: lift entra suavemente acima de BLACK_TOE,
    // senão o v=0 vira cinzento (shadowLift(0) = LIFT)
    return v + LIFT * smoothstep(0.0, BLACK_TOE, v)
                    * (1.0 - v) * (1.0 - v) * (1.0 - v);
}

vec3 vibrance(vec3 c, float strength) {
    float mx  = max(c.r, max(c.g, c.b));
    float mn  = min(c.r, min(c.g, c.b));
    float sat = mx - mn;
    float lum = dot(c, vec3(0.2126, 0.7152, 0.0722));
    // peso quadrático: age a sério nos tons lavados, poupa as cores fortes
    float w = (1.0 - sat) * (1.0 - sat);
    return mix(vec3(lum), c, 1.0 + strength * w);
}

void main() {
    vec4 color = texture(tex, v_texcoord);
    color.r = shadowLift(color.r);
    color.g = shadowLift(color.g);
    color.b = shadowLift(color.b);
    color.rgb = mix(color.rgb, smoothstep(0.0, 1.0, color.rgb), SCURVE);
    color.rgb = vibrance(color.rgb, VIBRANCE);
    color.rgb *= TRIM;
    fragColor = vec4(clamp(color.rgb, 0.0, 1.0), color.a);
}