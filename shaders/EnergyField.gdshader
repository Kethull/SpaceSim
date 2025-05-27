shader_type canvas_item;

uniform float field_strength : hint_range(0.0, 2.0) = 1.0;
uniform vec3 field_color : source_color = vec3(0.2, 1.0, 0.8);
uniform float pulse_speed : hint_range(0.1, 5.0) = 2.0;
uniform int wave_count : hint_range(3, 10) = 6;

void fragment() {
    vec2 center = vec2(0.5, 0.5);
    float dist = distance(UV, center);
    float angle = atan(UV.y - center.y, UV.x - center.x);
    
    // Create energy waves
    float waves = 0.0;
    for (int i = 0; i < wave_count; i++) {
        float wave_phase = float(i) * 2.0 / float(wave_count);
        waves += sin(dist * 20.0 + TIME * pulse_speed + wave_phase) * 0.5;
    }
    waves = (waves + float(wave_count) * 0.5) / float(wave_count);
    
    // Radial pulse
    float pulse = sin(dist * 15.0 - TIME * pulse_speed * 2.0) * 0.5 + 0.5;
    
    // Combine effects
    float intensity = waves * pulse * field_strength;
    intensity *= 1.0 - smoothstep(0.0, 0.5, dist); // Fade at edges
    
    // Color variation
    vec3 color = field_color;
    color.r += sin(angle * 3.0 + TIME) * 0.1;
    color.g += cos(angle * 4.0 + TIME * 1.3) * 0.1;
    color.b += sin(angle * 5.0 + TIME * 0.7) * 0.1;
    
    COLOR = vec4(color, intensity);
}