#version 300 es
precision highp float;
out vec4 fragColor;


in vec2 v_texcoord;

uniform sampler2D tex;

// Configuration
const float pixel_size = 4.0; 
const float color_levels = 8.0;      // 6 levels per channel approx = 216 colors (Web Safe/Retro style)
const float dither_strength = 0.04;    // Adjust the intensity of the pattern
const float sharpen_amount = 0.2;      // Adjust 0.0 (off) to 1.0 (very sharp)
const float scanline_intensity = 0.15; // 0.0 (off) to 1.0 (black lines)

// NEW: CRT Curvature Configuration
const float warp_intensity = 0.00;   // 0.0 (flat) to 0.2 (very curved). Adjust this!
const float vignette_intensity = 0.0; // Darkening at the corners. 1.0 = heavy black corners.

// NEW: Vibrance & Brightness Controls
const float brightness_gain = 1.15;   // Boost overall light (1.0 is neutral)
const float saturation_boost = 1.2;   // Make colors "pop" more (1.0 is neutral)
const float gamma_correction = 0.9;   // Pull shadows up (Lower is brighter)

// 4x4 Bayer Dither Matrix
float dither_table[16] = float[](
    0.0, 0.5, 0.125, 0.625,
    0.75, 0.25, 0.875, 0.375,
    0.1875, 0.6875, 0.0625, 0.5625,
    0.9375, 0.4375, 0.8125, 0.3125
);

// Helper function to calculate curvature
vec2 curve_coordinates(vec2 uv) {
    vec2 p = (uv * 2.0) - 1.0;
    p *= 1.0 + (pow(p.yx, vec2(2.0)) * warp_intensity);
    return (p / 2.0) + 0.5;
}

void main() {
    // 0. Apply Curvature FIRST
    vec2 curved_uv = curve_coordinates(v_texcoord);
    
    // Safety check: Don't sample if coordinates warped off-screen
    if (curved_uv.x < 0.0 || curved_uv.x > 1.0 || curved_uv.y < 0.0 || curved_uv.y > 1.0) {
        fragColor = vec4(0.0, 0.0, 0.0, 1.0);
        return;
    }

    vec2 res = vec2(textureSize(tex, 0));
    vec2 step = pixel_size / res; 
    
    // 1. Pixelate Coordinates (using curved_uv)
    vec2 p = curved_uv * res;
    p = floor(p / pixel_size) * pixel_size + (pixel_size * 0.5);
    vec2 block_uv = p / res;

    // 2. Sharpening Pass
    vec3 center = texture(tex, block_uv).rgb;
    vec3 left   = texture(tex, block_uv + vec2(-step.x, 0.0)).rgb;
    vec3 right  = texture(tex, block_uv + vec2(step.x, 0.0)).rgb;
    vec3 up     = texture(tex, block_uv + vec2(0.0, step.y)).rgb;
    vec3 down   = texture(tex, block_uv + vec2(0.0, -step.y)).rgb;

    vec3 edges = (4.0 * center) - (left + right + up + down);
    vec3 color_rgb = center + (edges * sharpen_amount);

    // 3. NEW: Vibrance & Brightening Pass
    // A. Apply Gain
    color_rgb *= brightness_gain;

    // B. Apply Gamma (helps with midtones getting crushed)
    color_rgb = pow(color_rgb, vec3(gamma_correction));

    // C. Apply Saturation
    float luma = dot(color_rgb, vec3(0.299, 0.587, 0.114));
    color_rgb = mix(vec3(luma), color_rgb, saturation_boost);

    // 4. Apply Ordered Dithering
    int x = int(mod(p.x, 4.0));
    int y = int(mod(p.y, 4.0));
    float dither_shift = dither_table[x + (y * 4)] - 0.5;
    color_rgb += dither_shift * dither_strength;

    // 5. Quantize Color
    if (color_levels > 0.0) {
        color_rgb = floor(color_rgb * color_levels) / color_levels;
    }

    // 6. Scanline Overlay
    float scanline = sin(curved_uv.y * res.y * (3.14159 / pixel_size));
    float scanline_mul = 1.0 - (abs(scanline) * scanline_intensity);
    color_rgb *= scanline_mul;
    
    // 7. Vignette & Corner Feathering
    vec2 vignette_uv = (v_texcoord * 2.0) - 1.0;
    float vignette = 1.0 - dot(vignette_uv, vignette_uv) * 0.15; 
    float round_corner = pow(16.0 * v_texcoord.x * v_texcoord.y * (1.0-v_texcoord.x) * (1.0-v_texcoord.y), vignette_intensity);
    
    color_rgb *= (vignette * round_corner);

   fragColor = vec4(color_rgb, 1.0);
   
}