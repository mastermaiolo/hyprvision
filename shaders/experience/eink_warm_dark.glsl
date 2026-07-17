#version 300 es
// HyprVision · E-Ink Warm Dark
// Variante do E-Ink com temperatura mais quente e cinzas/pretos mais profundos
precision highp float;
in vec2 v_texcoord;
layout(location = 0) out vec4 fragColor;
uniform sampler2D tex;

void main() {
    vec4 color = texture(tex, v_texcoord);
    float lum = dot(color.rgb, vec3(0.2126, 0.7152, 0.0722));
    // Menos compressão de alcance: pretos mais fundos, brancos ainda suaves
    lum = lum * 0.90 + 0.02;
    // Curva S mais marcada para mais contraste nos cinzas
    lum = mix(lum, smoothstep(0.0, 1.0, lum), 0.30);
    // Warm tint acentuado (mais laranja/âmbar, menos azul)
    vec3 eink = vec3(lum * 1.08, lum * 0.97, lum * 0.80);
    // Boost de contraste local nos médios (texto mais nítido)
    float mid = smoothstep(0.3, 0.7, lum);
    eink *= (1.0 + mid * 0.08);
    fragColor = vec4(clamp(eink, 0.0, 1.0), color.a);
}
