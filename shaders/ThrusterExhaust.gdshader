shader_type canvas_item;

uniform float intensity : hint_range(0.0, 2.0) = 1.0;
uniform vec3 flame_color : source_color = vec3(0.2, 0.8, 1.0);
uniform float temperature : hint_range(1000.0, 4000.0) = 3000.0;
uniform float time_scale : hint_range(0.1, 5.0) = 2.0;

varying vec2 world_position;

vec3 temperature_to_color(float temp) {
    // Blackbody radiation approximation
    if (temp < 2500.0) {
        return vec3(1.0, 0.4, 0.1); // Red-orange
    } else if (temp < 3500.0) {
        return vec3(1.0, 0.8, 0.3); // Yellow-white
    } else {
        return vec3(0.8, 0.9, 1.0); // Blue-white
    }
}

void fragment() {
    vec2 center = vec2(0.5, 0.5);
    float dist = distance(UV, center);
    
    // Create turbulent flame effect
    float noise1 = sin(UV.x * 10.0 + TIME * time_scale) * 0.1;
    float noise2 = cos(UV.y * 8.0 + TIME * time_scale * 0.7) * 0.1;
    float turbulence = noise1 + noise2;
    
    // Flame shape with turbulence
    float flame_mask = 1.0 - smoothstep(0.2, 0.5, dist + turbulence);
    flame_mask *= intensity;
    
    // Temperature-based color
    vec3 color = temperature_to_color(temperature);
    color = mix(color, flame_color, 0.3);
    
    // Add intensity variation
    float intensity_var = 0.8 + 0.2 * sin(TIME * time_scale * 3.0);
    color *= intensity_var;
    
    COLOR = vec4(color, flame_mask * intensity);
}