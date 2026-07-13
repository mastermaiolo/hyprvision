#version 300 es
// HyprVision · Focus
// Saturação −75% + micro warmth — remove distracção de cor
precision highp float;
in vec2 v_texcoord;
layout(location = 0) out vec4 fragColor;
uniform sampler2D tex;

void main() {
    vec4 color = texture(tex, v_texcoord);
    float lum = dot(color.rgb, vec3(0.2126, 0.7152, 0.0722));
    color.rgb = mix(vec3(lum), color.rgb, 0.25);
    color.rgb = (color.rgb - 0.5) * 1.08 + 0.5;
    color.r *= 1.008;
    color.b *= 0.992;
    fragColor = vec4(clamp(color.rgb, 0.0, 1.0), color.a);
}