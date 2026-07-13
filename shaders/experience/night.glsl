#version 300 es
// HyprVision · Night
// Corte agressivo de azul + orange cast suave + brilho reduzido
precision highp float;
in vec2 v_texcoord;
layout(location = 0) out vec4 fragColor;
uniform sampler2D tex;

void main() {
    vec4 color = texture(tex, v_texcoord);
    color.b *= 0.55;
    color.g *= 0.90;
    color.rgb *= 0.82;
    // Compressão de altos — sem picos de brilho que agridem a retina
    color.rgb = 1.0 - (1.0 - color.rgb) * (1.0 - color.rgb * 0.12);
    color.r *= 1.08;
    color.g *= 0.97;
    fragColor = vec4(clamp(color.rgb, 0.0, 1.0), color.a);
}