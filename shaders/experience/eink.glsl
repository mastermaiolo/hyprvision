// HyprVision · E-Ink
// Preto e branco + alcance dinâmico comprimido — tipo Kindle/eReader
#version 300 es
precision highp float;
in vec2 v_texcoord;
layout(location = 0) out vec4 fragColor;
uniform sampler2D tex;

void main() {
    vec4 color = texture(tex, v_texcoord);
    float lum = dot(color.rgb, vec3(0.2126, 0.7152, 0.0722));
    // Compressão de alcance: remove brancos duros e pretos puros
    lum = lum * 0.82 + 0.06;
    // Curva S suave para microcontraste no texto
    lum = mix(lum, smoothstep(0.0, 1.0, lum), 0.20);
    // Warm tint de lâmpada de leitura
    vec3 eink = vec3(lum * 1.02, lum * 1.00, lum * 0.92);
    // Boost de contraste local nos médios (texto mais nítido)
    float mid = smoothstep(0.3, 0.7, lum);
    eink *= (1.0 + mid * 0.06);
    fragColor = vec4(clamp(eink, 0.0, 1.0), color.a);
}