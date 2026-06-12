// HyprVision · Cinema Film
// Curva S intensa + vinheta + granulação fina + warm split-tone
#version 300 es
precision highp float;
in vec2 v_texcoord;
layout(location = 0) out vec4 fragColor;
uniform sampler2D tex;

float hash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float filmCurve(float v) {
    float s = smoothstep(0.0, 1.0, v);
    float r = mix(v, s, 0.45);
    return r - 0.06 * r * r;
}

void main() {
    vec4 color = texture(tex, v_texcoord);
    color.r = filmCurve(color.r);
    color.g = filmCurve(color.g);
    color.b = filmCurve(color.b);
    // Lift de pretos (crush suave — filmes não têm preto puro)
    color.rgb = color.rgb * 0.93 + 0.025;
    // Vibrance selectiva
    float lum = dot(color.rgb, vec3(0.2126, 0.7152, 0.0722));
    float sat = length(color.rgb - vec3(lum));
    color.rgb = mix(vec3(lum), color.rgb, 1.0 + 0.15 * (1.0 - sat));
    // Split-tone: sombras quentes, altas frias
    float luminance = dot(color.rgb, vec3(0.299, 0.587, 0.114));
    color.rgb *= mix(vec3(1.03, 0.99, 0.93), vec3(0.97, 0.99, 1.04), luminance);
    // Vinheta
    vec2 c = v_texcoord - 0.5;
    float vig = smoothstep(0.0, 1.0, clamp(1.0 - dot(c, c) * 1.4, 0.0, 1.0));
    color.rgb *= mix(0.72, 1.0, vig);
    // Grão de filme
    color.rgb += hash(v_texcoord * 1000.0) * 0.035 - 0.0175;
    fragColor = vec4(clamp(color.rgb, 0.0, 1.0), color.a);
}