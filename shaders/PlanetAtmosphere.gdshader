shader_type canvas_item;

uniform vec3 atmosphere_color : source_color = vec3(0.4, 0.7, 1.0);
uniform float atmosphere_thickness : hint_range(0.0, 0.5) = 0.1;
uniform float glow_intensity : hint_range(0.0, 2.0) = 1.0;
uniform float rotation_speed : hint_range(0.0, 2.0) = 0.1;

void fragment() {
    vec2 center = vec2(0.5, 0.5);
    float dist = distance(UV, center);
    
    // Rotating atmosphere effect
    float angle = atan(UV.y - center.y, UV.x - center.x) + TIME * rotation_speed;
    float atmosphere_noise = sin(angle * 8.0) * 0.02 + cos(angle * 12.0) * 0.01;
    
    // Atmospheric glow
    float atmosphere_mask = 1.0 - smoothstep(0.45, 0.5 + atmosphere_thickness, dist + atmosphere_noise);
    float glow_mask = 1.0 - smoothstep(0.4, 0.6 + atmosphere_thickness, dist);
    
    // Limb darkening effect
    float limb_darkening = 1.0 - pow(dist / 0.5, 0.5);
    
    vec3 final_color = atmosphere_color * glow_intensity * limb_darkening;
    float alpha = (atmosphere_mask + glow_mask * 0.3) * glow_intensity;
    
    COLOR = vec4(final_color, alpha);
}