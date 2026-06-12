// HyprVision · Paper Soft
// Versão mais quente e suave do Paper — sessões longas de escrita
#version 300 es
precision highp float;
in vec2 v_texcoord;
layout(location = 0) out vec4 fragColor;
uniform sampler2D tex;

float paperNoise(vec2 p) {
    vec2 ip = floor(p);
    vec2 fp = fract(p);
    fp = fp * fp * (3.0 - 2.0 * fp);
    float a = fract(sin(dot(ip,               vec2(127.1, 311.7))) * 43758.5);
    float b = fract(sin(dot(ip + vec2(1,0),   vec2(127.1, 311.7))) * 43758.5);
    float c = fract(sin(dot(ip + vec2(0,1),   vec2(127.1, 311.7))) * 43758.5);
    float d = fract(sin(dot(ip + vec2(1,1),   vec2(127.1, 311.7))) * 43758.5);
    return mix(mix(a, b, fp.x), mix(c, d, fp.x), fp.y);
}

void main() {
    vec4 color = texture(tex, v_texcoord);
    color.rgb = color.rgb * 0.86 + 0.04;
    color.rgb *= vec3(1.06, 0.97, 0.76);
    float lum = dot(color.rgb, vec3(0.2126, 0.7152, 0.0722));
    color.rgb = mix(vec3(lum), color.rgb, 0.55);
    float grain = paperNoise(v_texcoord * 800.0) * 0.028 - 0.014;
    color.rgb += grain * (1.0 - lum * 0.6);
    vec2 ctr = v_texcoord - 0.5;
    color.rgb *= clamp(1.0 - dot(ctr, ctr) * 0.8, 0.85, 1.0);
    fragColor = vec4(clamp(color.rgb, 0.0, 1.0), color.a);
}