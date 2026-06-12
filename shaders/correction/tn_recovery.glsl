// HyprVision · TN Recovery
// Levanta sombras sem explodir o brilho + vibração selectiva de matiz
// Ideal para painéis TN antigos e ecrãs de notebook "lavados"
#version 300 es
precision highp float;
in vec2 v_texcoord;
layout(location = 0) out vec4 fragColor;
uniform sampler2D tex;

float shadowLift(float v) {
    return v + 0.08 * (1.0 - v) * (1.0 - v) * (1.0 - v);
}

vec3 vibrance(vec3 c, float strength) {
    float mx  = max(c.r, max(c.g, c.b));
    float mn  = min(c.r, min(c.g, c.b));
    float sat = mx - mn;
    float lum = dot(c, vec3(0.2126, 0.7152, 0.0722));
    return mix(vec3(lum), c, 1.0 + strength * (1.0 - sat));
}

void main() {
    vec4 color = texture(tex, v_texcoord);
    color.r = shadowLift(color.r);
    color.g = shadowLift(color.g);
    color.b = shadowLift(color.b);
    color.rgb = mix(color.rgb, smoothstep(0.0, 1.0, color.rgb), 0.18);
    color.rgb = vibrance(color.rgb, 0.30);
    color.rgb *= 0.97;
    fragColor = vec4(clamp(color.rgb, 0.0, 1.0), color.a);
}