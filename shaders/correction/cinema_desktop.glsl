// HyprVision · Cinema Desktop
// Microcontraste suave + profundidade tonal + mínimo warm tint
#version 300 es
precision highp float;
in vec2 v_texcoord;
layout(location = 0) out vec4 fragColor;
uniform sampler2D tex;

float softS(float v) {
    return mix(v, smoothstep(0.0, 1.0, v), 0.22);
}

void main() {
    vec4 color = texture(tex, v_texcoord);
    color.r = softS(color.r);
    color.g = softS(color.g);
    color.b = softS(color.b);
    color.r = color.r - 0.04 * color.r * color.r;
    color.g = color.g - 0.04 * color.g * color.g;
    color.b = color.b - 0.04 * color.b * color.b;
    float lum = dot(color.rgb, vec3(0.2126, 0.7152, 0.0722));
    color.rgb = mix(vec3(lum), color.rgb, 1.08);
    color.r *= 1.010;
    color.b *= 0.990;
    fragColor = vec4(clamp(color.rgb, 0.0, 1.0), color.a);
}