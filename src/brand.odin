package pangolin


APP_NAME :: "Pangolin Paints"
APP_TAGLINE :: "Brushstrokes, scale by scale."

LOGO_SIZE :: 16

// A pangolin whose tail is a paint-dipped brush, on a rounded tile.
LOGO_SVG :: #load("../assets/logo.svg", string)

@(private = "file")
logo_cache: map[i32]Texture // by physical size

// Window icon.
brand_init :: proc() {
	ICON_PX :: 256
	pix := svg_render(LOGO_SVG, ICON_PX, ICON_PX, context.temp_allocator)
	gfx_set_icon(pix, ICON_PX, ICON_PX)
}

// Draws the logo LOGO_SIZE * scale logical px wide, rendered at the window's physical resolution.
logo_draw :: proc(x, y, scale: i32) {
	size := LOGO_SIZE * scale
	px := size * i32(gfx.scale)
	t, ok := logo_cache[px]
	if !ok {
		t = tex_from_pixels(svg_render(LOGO_SVG, int(px), int(px), context.temp_allocator), int(px), int(px), .Point)
		logo_cache[px] = t
	}
	draw_tex(t, {0, 0, f32(px), f32(px)}, {f32(x), f32(y), f32(size), f32(size)})
}
