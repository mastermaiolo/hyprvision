#version 300 es
precision highp float;
out vec4 fragColor;
// 1. ABSOLUTE FIRST: Require GLES 3.2 to match Hyprland's TEXVERTSRC320
// CRITICAL FIX: Use highp to handle large uptime values from std::chrono::steady_clock

// Hyprland standard inputs
in vec2 v_texcoord;
uniform sampler2D tex;
uniform float time;

// Output for GLES 3.2 (MUST be lowercase 'fragColor' to match the C++ plugin wrapper)

// --- GLITCH SETTINGS ---
// Adjust these variables to customize the glitch behavior
const float minInterval = 2.0;    // Minimum seconds between glitches
const float maxInterval = 5.0;    // Maximum seconds between glitches
const float glitchDuration = 0.2; // How long the glitch lasts in seconds
const float intensity = 0.02;     // How far the tear/chromatic shift travels
const float direction = 0.5;      // 0.0 = 100% Horizontal, 1.0 = 100% Vertical, 0.5 = 50/50 mix

// --- NEW WOBBLE SETTINGS ---
const float wobbleSpeed = 0.0;   // How fast the wobble oscillates
const float wobbleAmount = 0.0;  // How far the wobble stretches
const float wobblePhase = 0.0;   // Phase offset between RGB channels (0.0 = together, >0.0 = separated)

// Simple pseudo-random hash function based on time
float hash(float n) {
    return fract(sin(n) * 43758.5453123);
}

void main() {
    // Wrap the time to prevent highp from eventually breaking down over weeks of system uptime
    float t = mod(time, 3600.0); // Resets the time math every hour
    
    // Determine the start of the current glitch cycle using the max interval as a grid
    float seed = floor(t / maxInterval);
    
    // Calculate a pseudo-random time within the current maxInterval grid
    float nextGlitchTime = seed * maxInterval + hash(seed) * (maxInterval - minInterval);
    
    // Check if we are currently within an active glitch window (1.0 if yes, 0.0 if no)
    float isGlitching = step(nextGlitchTime, t) * step(t, nextGlitchTime + glitchDuration);
    
    vec2 uv = v_texcoord;
    
    if (isGlitching > 0.0) {
        // --- VIOLENT STUTTER ---
        // Quantize time during the glitch so the effect "jumps" like missing frames instead of sliding smoothly
        float stutterTime = floor(t * 15.0) / 15.0; // 15 'frames' per second stutter rate
        
        // Calculate tearing strength based on intensity and the new stuttered time
        float tearStrength = hash(stutterTime) * intensity;
        
        // Calculate chromatic aberration shift based on intensity
        float shift = (intensity * 0.2) * hash(stutterTime);
        
        // --- BLENDED DIRECTIONAL LOGIC ---
        // Calculate the raw horizontal displacement
        // Step 0.8 means ~20% of the screen rows tear at once
        float tearRow = step(0.8, hash(uv.y * 10.0 + stutterTime));
        float offsetX = tearRow * tearStrength;
        
        // Calculate the raw vertical displacement
        // Step 0.8 means ~20% of the screen columns tear at once
        float tearCol = step(0.8, hash(uv.x * 10.0 + stutterTime));
        float offsetY = tearCol * tearStrength;
        
        // Determine the weights for each axis based on the direction float
        float weightX = 1.0 - direction;
        float weightY = direction;
        
        // Apply the weighted tearing displacements to create a base UV coordinate for the entire frame
        vec2 baseUV = uv + vec2(offsetX * weightX, offsetY * weightY);
        
        // --- WOBBLE EFFECT (OUT OF PHASE) ---
        // Calculate independent wobbles for Red, Green, and Blue by adding phase offsets to the sine wave
        // We use the original 'uv' to calculate the wave so the curve stays fluid across tear boundaries
        vec2 wobbleR = vec2(
            sin(uv.y * 25.0 + t * wobbleSpeed + wobblePhase) * wobbleAmount * weightX,
            sin(uv.x * 25.0 + t * wobbleSpeed + wobblePhase) * wobbleAmount * weightY
        );
        
        vec2 wobbleG = vec2(
            sin(uv.y * 25.0 + t * wobbleSpeed) * wobbleAmount * weightX,
            sin(uv.x * 25.0 + t * wobbleSpeed) * wobbleAmount * weightY
        );
        
        vec2 wobbleB = vec2(
            sin(uv.y * 25.0 + t * wobbleSpeed - wobblePhase) * wobbleAmount * weightX,
            sin(uv.x * 25.0 + t * wobbleSpeed - wobblePhase) * wobbleAmount * weightY
        );
        
        // Create a blended chromatic shift vector for the hard jump
        vec2 shiftVec = vec2(shift * weightX, shift * weightY);
        
        // Chromatic Aberration: sample Red, Green, Blue from the torn coordinates + their unique wobbles
        // Using 'texture()' instead of 'texture()' for GLES 3.2 compatibility
        float r = texture(tex, baseUV + shiftVec + wobbleR).r;
        float g = texture(tex, baseUV + wobbleG).g;
        float b = texture(tex, baseUV - shiftVec + wobbleB).b;
        
        fragColor = vec4(r, g, b, 1.0);
    } else {
        // Regular rendering when not glitching
        fragColor = texture(tex, uv);
    }
}