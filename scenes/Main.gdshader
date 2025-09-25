shader_type canvas_item;

/* Godot 4.x: textura de pantalla */
uniform sampler2D SCREEN_TEXTURE : hint_screen_texture;

/* ========= CONTROLES (LIMPIOS POR DEFECTO) ========= */
uniform float brightness_boost : hint_range(0.0, 2.0) = 1.05;
uniform float contrast_boost   : hint_range(0.5, 2.0) = 1.02;

/* Scanlines (solo horizontales) */
uniform float scanline_strength : hint_range(0.0, 1.0) = 0.22;

/* Aberración cromática (px, muy sutil) */
uniform float chroma_px         : hint_range(0.0, 2.0) = 0.12;

/* Bleed/Bloom horizontal (muy bajo para no ensuciar) */
uniform float bleed_px          : hint_range(0.0, 3.0) = 0.40;
uniform float bleed_strength    : hint_range(0.0, 1.0) = 0.12;

/* Curvatura y viñeta (ligeras) */
uniform float curvature         : hint_range(0.0, 0.5) = 0.05;
uniform float vignette_strength : hint_range(0.0, 1.0) = 0.12;

/* Ruido leve */
uniform float noise_amount      : hint_range(0.0, 0.1) = 0.008;

/* Atenuar efecto en blancos/flash */
uniform float flash_scanline_dampen : hint_range(0.0, 1.0) = 0.9;

/* --------- OPCIONAL: MÁSCARA RGB (DESACTIVADA) ---------
   Si quieres columnas RGB, pon enable_mask=1.0. Para pixel-art pequeño
   suele generar moiré, por eso viene desactivada. */
uniform float enable_mask   : hint_range(0.0, 1.0) = 0.0;  // 0 = off, 1 = on
uniform float mask_strength : hint_range(0.0, 1.0) = 0.30;
uniform float mask_scale_px : hint_range(1.0, 8.0) = 2.0;

float rand(vec2 co){ return fract(sin(dot(co, vec2(12.9898,78.233))) * 43758.5453); }

vec3 phosphor_mask(vec2 uv, float res_x, float strength, float scale_px) {
    float px = uv.x * res_x;
    float band = floor(px / max(scale_px, 1.0));
    float m = mod(band, 3.0); // 0=R,1=G,2=B
    vec3 w = (m < 0.5) ? vec3(1.0,0.15,0.15)
           : (m < 1.5) ? vec3(0.15,1.0,0.15)
                       : vec3(0.15,0.15,1.0);
    return mix(vec3(1.0), w, strength);
}

void fragment() {
    vec2 uv = SCREEN_UV;
    vec2 center = uv - 0.5;

    // Curvatura sutil
    vec2 bend = center * (1.0 + curvature * dot(center, center));
    vec2 cuv = bend + 0.5;

    vec2 res = vec2(textureSize(SCREEN_TEXTURE, 0));

    // Aberración cromática mínima (solo horizontal)
    vec2 chroma_uv = vec2(chroma_px / res.x, 0.0);
    vec3 base = texture(SCREEN_TEXTURE, cuv).rgb;
    float r = texture(SCREEN_TEXTURE, cuv + chroma_uv).r;
    float g = base.g;
    float b = texture(SCREEN_TEXTURE, cuv - chroma_uv).b;
    vec3 col = vec3(r,g,b);

    // Bleed horizontal muy suave
    if (bleed_px > 0.0 && bleed_strength > 0.0) {
        vec2 off = vec2(bleed_px / res.x, 0.0);
        vec3 left  = texture(SCREEN_TEXTURE, cuv - off).rgb;
        vec3 right = texture(SCREEN_TEXTURE, cuv + off).rgb;
        col = mix(col, (left + right) * 0.5, bleed_strength);
    }

    // Atenuar en flashes (blancos)
    float luma = dot(col, vec3(0.299, 0.587, 0.114));
    float flash = smoothstep(0.7, 1.0, luma);

    // Scanlines horizontales
    float rows = res.y;
    float scan = sin(uv.y * rows * 3.14159265);
    float sl_strength = scanline_strength * (1.0 - flash * flash_scanline_dampen);
    float sl = mix(1.0, 0.84, sl_strength * (0.5 + 0.5 * scan * scan));
    col *= sl;

    // (Opcional) máscara RGB — por defecto OFF para evitar “suciedad”
    if (enable_mask > 0.5) {
        col *= phosphor_mask(uv, res.x, mask_strength, mask_scale_px);
    }

    // Viñeta leve
    float rlen = length(center) * 1.41421356;
    col *= (1.0 - vignette_strength * smoothstep(0.6, 1.0, rlen));

    // Brillo/contraste suaves
    col = (col - 0.5) * contrast_boost + 0.5;
    col *= brightness_boost;

    // Ruido sutil
    col += (rand(uv + TIME) - 0.5) * 2.0 * noise_amount;

    COLOR = vec4(col, 1.0);
}
