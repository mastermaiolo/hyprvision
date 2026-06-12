#version 300 es
precision highp float;
out vec4 fragColor;
// Matrix Green Shader for Hyprland - Green monochrome terminal effect


in vec2 v_texcoord;
uniform sampler2D tex;

// --- CONFIGURATION ---
const vec3 LUMA = vec3(0.2126, 0.7152, 0.0722);
const vec3 MATRIX_GREEN = vec3(0.0, 1.0, 0.2);  // Bright neon green
const vec3 DARK_GREEN = vec3(0.0, 0.15, 0.05);  // Dark background green
const float BRIGHTNESS_BOOST = 1.3;             // Make it pop
const float CONTRAST = 1.4;                     // Sharper contrast
const float MIN_BRIGHTNESS = 0.05;              // Minimum green level
const float PHOSPHOR_GLOW = 0.1;                // Subtle glow effect

void main() {
    vec4 color = texture(tex, v_texcoord);
    
    // Convert to grayscale
    float gray = dot(color.rgb, LUMA);
    
    // Apply contrast and brightness
    gray = (gray - 0.5) * CONTRAST + 0.5;
    gray *= BRIGHTNESS_BOOST;
    
    // Ensure minimum brightness
    gray = max(gray, MIN_BRIGHTNESS);
    
    // Map to green scale
    vec3 greenColor = mix(DARK_GREEN, MATRIX_GREEN, gray);
    
    // Add phosphor glow to bright areas
    if (gray > 0.6) {
        greenColor += vec3(0.0, PHOSPHOR_GLOW, PHOSPHOR_GLOW * 0.3) * (gray - 0.6);
    }
    
    greenColor = clamp(greenColor, 0.0, 1.0);
    
    fragColor = vec4(greenColor, color.a);
}
