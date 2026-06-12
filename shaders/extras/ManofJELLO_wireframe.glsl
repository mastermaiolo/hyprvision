#version 300 es
precision highp float;
out vec4 fragColor;

// Input texture coordinates from the vertex shader (replaces 'in')
in vec2 v_texcoord;

// Explicit output color (replaces 'fragColor')

uniform sampler2D tex;
uniform float time; // Used if you want to add animation later

// --- USER INPUT: RGB (0 to 255) ---
// Change these three values to any standard RGB color
const vec3 RAW_RGB = vec3(255.0, 107.0, 0.0); 

// --- CONFIGURATION LEVELS ---
// Tweak these values to change the intensity of the effects
const float EDGE_STRENGTH = 0.6;     // Sensitivity of wireframe detection
const float CRT_CURVATURE = 0.1;    // Degree of screen bulging (0.0 = flat)
const float VIGNETTE_SIZE = 0.1;     // Intensity of corner darkening
const float PHOSPHOR_GLOW = 0.1;     // Blur/Persistence level (0.0 = sharp, 1.0+ = heavy blur)

// New Scanline Control (0.0 to 1.0)
const float scanline_intensity = 0.15; 
// Adjust this to change thickness of lines (usually 1.0 or 2.0)
const float pixel_size = 1.0;         

// Helper function to convert RGB to grayscale luminance
float intensity(vec4 color) {
    // standard weights for human eye perception
    return dot(color.rgb, vec3(0.299, 0.587, 0.114));
}

// CRT Lens Distortion: Spherizes the UV coordinates
vec2 curve(vec2 uv) {
    uv = uv * 2.0 - 1.0; // Shift origin to center (-1.0 to 1.0)
    vec2 offset = abs(uv.yx) / vec2(6.0, 4.0); // Curvature ratio
    uv = uv + uv * offset * offset * CRT_CURVATURE;
    uv = uv * 0.5 + 0.5; // Shift back to (0.0 to 1.0)
    return uv;
}

void main() {
    // Dynamically define resolution from the input texture
    // textureSize(tex, 0) gets the width/height of the desktop frame
    vec2 resolution = vec2(textureSize(tex, 0));

    // CONVERSION: Normalize the user-friendly 0-255 RGB to 0.0-1.0
    vec3 WIRE_COLOR = RAW_RGB / 255.0;

    // 1. Apply CRT Curvature
    vec2 curved_uv = curve(v_texcoord);
    
    // Kill pixels outside the curved bounds (creates the black "monitor bezel" look)
    if (curved_uv.x < 0.0 || curved_uv.x > 1.0 || curved_uv.y < 0.0 || curved_uv.y > 1.0) {
        fragColor = vec4(0.0, 0.0, 0.0, 1.0);
        return;
    }

    // 2. Sobel Edge Detection (The Wireframe logic)
    // Samples 8 surrounding pixels to find color gradients/edges
    vec2 pixelStep = 1.0 / resolution;
    float x = pixelStep.x;
    float y = pixelStep.y;

    // Sample the 3x3 neighborhood
    float t_tl = intensity(texture(tex, curved_uv + vec2(-x,  y))); // Top-Left
    float t_tc = intensity(texture(tex, curved_uv + vec2( 0,  y))); // Top-Center
    float t_tr = intensity(texture(tex, curved_uv + vec2( x,  y))); // Top-Right
    float t_ml = intensity(texture(tex, curved_uv + vec2(-x,  0))); // Mid-Left
    float t_mr = intensity(texture(tex, curved_uv + vec2( x,  0))); // Mid-Right
    float t_bl = intensity(texture(tex, curved_uv + vec2(-x, -y))); // Bottom-Left
    float t_bc = intensity(texture(tex, curved_uv + vec2( 0, -y))); // Bottom-Center
    float t_br = intensity(texture(tex, curved_uv + vec2( x, -y))); // Bottom-Right

    // Sobel Kernels for horizontal and vertical change
    // Horizontal: [ -1 0 1 ]  Vertical: [ -1 -2 -1 ]
    //             [ -2 0 2 ]            [  0  0  0 ]
    //             [ -1 0 1 ]            [  1  2  1 ]
    float gradX = (t_tr + 2.0 * t_mr + t_br) - (t_tl + 2.0 * t_ml + t_bl);
    float gradY = (t_bl + 2.0 * t_bc + t_br) - (t_tl + 2.0 * t_tc + t_tr);
    
    // Calculate total magnitude of the edge (the "wireframe" line)
    float edge = sqrt(gradX * gradX + gradY * gradY);
    
    // Smooth the lines for a cleaner look
    float wireAlpha = smoothstep(0.1, EDGE_STRENGTH, edge);

    // 3. Phosphor Persistence / Glow effect
    // We add a subtle horizontal and vertical blur to the wireframe lines.
    float blurOffset = PHOSPHOR_GLOW / resolution.x; 
    
    float glowSamples = 
        intensity(texture(tex, curved_uv + vec2( blurOffset, 0.0))) +
        intensity(texture(tex, curved_uv + vec2(-blurOffset, 0.0))) +
        intensity(texture(tex, curved_uv + vec2(0.0,  blurOffset))) +
        intensity(texture(tex, curved_uv + vec2(0.0, -blurOffset)));
    
    wireAlpha += (glowSamples * 0.25) * PHOSPHOR_GLOW;

    // Initialize RGB based on wireframe alpha
    vec3 color_rgb = WIRE_COLOR * wireAlpha;

    // 4. Pixel-Perfect Scanline Effect
    // Uses the provided fragment logic for intensity and resolution-based scaling
    float scanline = sin(curved_uv.y * resolution.y * (3.14159 / pixel_size));
    float scanline_mul = 1.0 - (abs(scanline) * scanline_intensity);
    color_rgb *= scanline_mul;

    // 5. Vignette (Simulates the darkening of old CRT corners)
    float vignette = curved_uv.x * curved_uv.y * (1.0 - curved_uv.x) * (1.0 - curved_uv.y);
    vignette = pow(16.0 * vignette, VIGNETTE_SIZE);
    color_rgb *= vignette;

    // Final fragment output
    fragColor = vec4(color_rgb, 1.0);
}