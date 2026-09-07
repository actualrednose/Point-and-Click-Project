shader_type canvas_item;

uniform float hovered : hint_range(0.0, 1.0) = 0.0;
uniform vec4 glow_color : source_color = vec4(1.0, 0.84, 0.31, 1.0);
uniform float glow_width_px : hint_range(1.0, 12.0) = 4.0;
uniform float intensity : hint_range(0.0, 3.0) = 1.0;

void fragment() {
    vec4 col = texture(TEXTURE, UV);

    // Ring-sample around this pixel; keep the strongest hit.
    float ring = 0.0;
    const int N = 16;
    for (int i = 0; i < N; i++) {
        float ang = TAU * float(i) / float(N);
        vec2 dir = vec2(cos(ang), sin(ang));
        // Two radii give the glow a soft outer falloff.
        ring = max(ring, texture(TEXTURE, UV + dir * glow_width_px * TEXTURE_PIXEL_SIZE).a);
        ring = max(ring, 0.55 * texture(TEXTURE, UV + dir * glow_width_px * 0.5 * TEXTURE_PIXEL_SIZE).a);
    }

    // Only paint OUTSIDE the silhouette: (1 - col.a) suppresses the
    // object's own pixels so the art stays untouched.
    float amount = clamp(ring * intensity, 0.0, 1.0)
        * hovered * (1.0 - col.a);

    COLOR = vec4(mix(col.rgb, glow_color.rgb, amount),
                 max(col.a, amount * glow_color.a));
}