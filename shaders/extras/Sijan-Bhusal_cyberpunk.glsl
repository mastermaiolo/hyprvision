#version 300 es
precision highp float;
out vec4 fragColor;
// Cyberpunk Shader for Hyprland - Neon color grading with chromatic aberration


in vec2 v_texcoord;
uniform sampler2D tex;

// --- CONFIGURATION ---
const float CHROMATIC_ABERRATION = 0.002;  // Strength of RGB split effect
const float SATURATION_BOOST = 1.5;        // Increase color vibrancy
const float CONTRAST = 1.3;                // Punchier contrast
const vec3 NEON_TINT = vec3(0.1, 0.2, 0.3); // Cyan/magenta bias
const float GLOW_INTENSITY = 0.15;         // Subtle glow on bright areas
const float SCANLINE_INTENSITY = 0.05;     // Subtle scanline effect

void main() {
    vec2 uv = v_texcoord;
    
    // Chromatic aberration - split RGB channels
    float r = texture(tex, uv + vec2(CHROMATIC_ABERRATION, 0.0)).r;
    float g = texture(tex, uv).g;
    float b = texture(tex, uv - vec2(CHROMATIC_ABERRATION, 0.0)).b;
    float a = texture(tex, uv).a;
    
    vec3 color = vec3(r, g, b);
    
    // Boost saturation for neon effect
    vec3 gray = vec3(dot(color, vec3(0.299, 0.587, 0.114)));
    color = mix(gray, color, SATURATION_BOOST);
    
    // Apply contrast
    color = (color - 0.5) * CONTRAST + 0.5;
    
    // Neon color grading - enhance cyan/magenta
    color += NEON_TINT * dot(color, vec3(0.333));
    
    // Add glow to bright areas
    float luminance = dot(color, vec3(0.2126, 0.7152, 0.0722));
    if (luminance > 0.7) {
        color += vec3(GLOW_INTENSITY) * (luminance - 0.7);
    }
    
    // Subtle scanlines for CRT effect
    float scanline = sin(v_texcoord.y * 1080.0) * SCANLINE_INTENSITY;
    color -= scanline;
    
    color = clamp(color, 0.0, 1.0);
    
    fragColor = vec4(color, a);
}
