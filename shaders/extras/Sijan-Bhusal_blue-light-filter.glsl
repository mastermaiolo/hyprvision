#version 300 es
precision highp float;
out vec4 fragColor;
// Blue Light Filter Shader for Hyprland - Reduces blue light for evening use


in vec2 v_texcoord;
uniform sampler2D tex;

// --- CONFIGURATION ---
// Adjust WARMTH: 0.0 = no filter, 1.0 = maximum warmth
const float WARMTH = 0.7;

// Color temperature adjustment
const float INTENSITY = 0.85;  // Overall intensity (0.0-1.0)

// Time-based presets (adjust WARMTH above to match your preference):
// Morning/Afternoon: 0.3-0.5 (light filter)
// Evening: 0.6-0.7 (moderate filter)  
// Night: 0.8-1.0 (strong filter)

void main() {
    vec4 color = texture(tex, v_texcoord);
    
    // Reduce blue channel based on warmth setting
    float blueReduction = 1.0 - (WARMTH * 0.7);
    color.b *= blueReduction;
    
    // Slightly reduce green for better color balance
    float greenReduction = 1.0 - (WARMTH * 0.3);
    color.g *= greenReduction;
    
    // Boost red slightly for warmer tone
    float redBoost = 1.0 + (WARMTH * 0.1);
    color.r *= redBoost;
    
    // Apply overall intensity
    color.rgb *= INTENSITY;
    
    // Ensure we don't exceed valid color range
    color = clamp(color, 0.0, 1.0);
    
    fragColor = color;
}
