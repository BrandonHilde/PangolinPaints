package pangolin

import "core:math"
import rl "vendor:raylib"

tex_canvas: rl.Texture2D
tex_checker: rl.Texture2D
tex_w, tex_h: int
tex_doc: ^Doc // document whose pixels are in tex_canvas
tex_mips_dirty: bool
tex_filter: rl.TextureFilter

render_init :: proc() {
	img := rl.GenImageColor(2, 2, rl.BLANK)
	a := Color{204, 204, 212, 255}
	b := Color{150, 150, 162, 255}
	rl.ImageDrawPixel(&img, 0, 0, a)
	rl.ImageDrawPixel(&img, 1, 1, a)
	rl.ImageDrawPixel(&img, 1, 0, b)
	rl.ImageDrawPixel(&img, 0, 1, b)
	tex_checker = rl.LoadTextureFromImage(img)
	rl.UnloadImage(img)
	rl.SetTextureFilter(tex_checker, .POINT)
	rl.SetTextureWrap(tex_checker, .REPEAT)
}

textures_ensure :: proc(d: ^Doc) {
	if tex_canvas.id != 0 && tex_w == d.w && tex_h == d.h && tex_doc == d {
		return
	}
	if tex_canvas.id == 0 || tex_w != d.w || tex_h != d.h {
		if tex_canvas.id != 0 {
			rl.UnloadTexture(tex_canvas)
		}
		img := rl.GenImageColor(i32(d.w), i32(d.h), rl.BLANK)
		tex_canvas = rl.LoadTextureFromImage(img)
		rl.UnloadImage(img)
		rl.SetTextureWrap(tex_canvas, .CLAMP)
		tex_filter = .POINT
		rl.SetTextureFilter(tex_canvas, .POINT)
		tex_w, tex_h = d.w, d.h
	}
	tex_doc = d
	// a different document (or size): upload everything
	doc_refresh_comp(d)
	d.tex_dirty = doc_box(d)
}

render_refresh :: proc(d: ^Doc) {
	textures_ensure(d)
	doc_refresh_comp(d)
	b := box_clip(d.tex_dirty, d.w, d.h)
	if !box_empty(b) {
		bw, bh := b.x1 - b.x0, b.y1 - b.y0
		if bw == d.w {
			rl.UpdateTextureRec(tex_canvas, {0, f32(b.y0), f32(bw), f32(bh)}, raw_data(d.comp[b.y0 * d.w:]))
		} else {
			sub := make([]Color, bw * bh, context.temp_allocator)
			for y in 0 ..< bh {
				copy(sub[y * bw:][:bw], d.comp[(b.y0 + y) * d.w + b.x0:][:bw])
			}
			rl.UpdateTextureRec(tex_canvas, {f32(b.x0), f32(b.y0), f32(bw), f32(bh)}, raw_data(sub))
		}
		d.tex_dirty = {}
		tex_mips_dirty = true
	}
	// smooth when zoomed out (mipmaps avoid shimmering), crisp pixels when zoomed in
	want: rl.TextureFilter = .POINT
	if d.zoom < 1 {
		want = .TRILINEAR
		if tex_mips_dirty {
			rl.GenTextureMipmaps(&tex_canvas)
			tex_mips_dirty = false
		}
	} else if d.zoom < 2 {
		want = .BILINEAR
	}
	if want != tex_filter {
		tex_filter = want
		rl.SetTextureFilter(tex_canvas, want)
	}
}

canvas_bg_color :: proc() -> Color {
	switch bg_mode {
	case 1:
		return Color{0, 0, 0, 255}
	case 2:
		return Color{255, 255, 255, 255}
	case 3:
		return Color{128, 128, 128, 255}
	}
	return Color{}
}

draw_canvas_bg :: proc(dst: rl.Rectangle) {
	if bg_mode == 0 {
		cell: f32 = 8
		rl.DrawTexturePro(tex_checker, {0, 0, dst.width / cell, dst.height / cell}, dst, {}, 0, rl.WHITE)
	} else {
		rl.DrawRectangleRec(dst, canvas_bg_color())
	}
}

draw_checker :: proc(r: Rect, cell: i32 = 4) {
	rl.DrawTexturePro(tex_checker, {0, 0, f32(r.w) / f32(cell), f32(r.h) / f32(cell)}, to_rl(r), {}, 0, rl.WHITE)
}

render_canvas :: proc(vp: Rect) {
	d := doc
	fill_rect(vp, C_VIEWPORT)
	clip_begin(vp)
	defer clip_end()
	render_refresh(d)

	z := d.zoom
	cw := f32(d.w) * z
	ch := f32(d.h) * z
	dst := rl.Rectangle{d.ox, d.oy, cw, ch}
	// drop shadow
	rl.DrawRectangleRec({dst.x + 4, dst.y + 4, dst.width, dst.height}, Color{0, 0, 0, 70})
	draw_canvas_bg(dst)
	rl.DrawTexturePro(tex_canvas, {0, 0, f32(d.w), f32(d.h)}, dst, {}, 0, rl.WHITE)

	x0 := i32(d.ox)
	y0 := i32(d.oy)
	x1 := i32(d.ox + cw)
	y1 := i32(d.oy + ch)

	// pixel grid at extreme zoom
	if show_pixel_grid && z >= 12 {
		gc := Color{128, 128, 140, 60}
		ix0 := max(int((f32(vp.x) - d.ox) / z), 0)
		ix1 := min(int((f32(vp.x + vp.w) - d.ox) / z) + 1, d.w)
		iy0 := max(int((f32(vp.y) - d.oy) / z), 0)
		iy1 := min(int((f32(vp.y + vp.h) - d.oy) / z) + 1, d.h)
		for i in ix0 + 1 ..< ix1 {
			vline(i32(d.ox + f32(i) * z), max(y0, vp.y), min(y1, vp.y + vp.h) - max(y0, vp.y), gc)
		}
		for i in iy0 + 1 ..< iy1 {
			hline(max(x0, vp.x), i32(d.oy + f32(i) * z), min(x1, vp.x + vp.w) - max(x0, vp.x), gc)
		}
	}
	// rule-of-thirds guide
	if show_thirds {
		gc := Color{255, 255, 255, 90}
		for i in 1 ..= 2 {
			vline(i32(d.ox + cw * f32(i) / 3), y0, y1 - y0, gc)
			hline(x0, i32(d.oy + ch * f32(i) / 3), x1 - x0, gc)
		}
	}
	outline_rect(Rect{x0 - 1, y0 - 1, x1 - x0 + 2, y1 - y0 + 2}, Color{10, 10, 14, 255})

	// selection outline (marching ants)
	doc_rebuild_edges(d)
	if len(d.sel_edges) > 0 {
		phase := f32(ui.time * 8)
		for e in d.sel_edges {
			sx := d.ox + f32(e.x) * z
			sy := d.oy + f32(e.y) * z
			ln := f32(e.n) * z
			if e.vert {
				if sx < f32(vp.x) - 1 || sx > f32(vp.x + vp.w) || sy > f32(vp.y + vp.h) || sy + ln < f32(vp.y) do continue
				ants_line(sx, sy, ln, true, phase)
			} else {
				if sy < f32(vp.y) - 1 || sy > f32(vp.y + vp.h) || sx > f32(vp.x + vp.w) || sx + ln < f32(vp.x) do continue
				ants_line(sx, sy, ln, false, phase)
			}
		}
	}

	// crop overlay
	if crop.active {
		b := crop_box()
		bx0, by0 := d.ox + f32(b.x0) * z, d.oy + f32(b.y0) * z
		bx1, by1 := d.ox + f32(b.x1) * z, d.oy + f32(b.y1) * z
		dark := Color{0, 0, 0, 150}
		rl.DrawRectangleRec({dst.x, dst.y, cw, by0 - dst.y}, dark)
		rl.DrawRectangleRec({dst.x, by1, cw, dst.y + ch - by1}, dark)
		rl.DrawRectangleRec({dst.x, by0, bx0 - dst.x, by1 - by0}, dark)
		rl.DrawRectangleRec({bx1, by0, dst.x + cw - bx1, by1 - by0}, dark)
		rl.DrawRectangleLinesEx({bx0, by0, bx1 - bx0, by1 - by0}, 1, rl.WHITE)
		for i in 1 ..= 2 {
			gc := Color{255, 255, 255, 80}
			rl.DrawLineV({bx0 + (bx1 - bx0) * f32(i) / 3, by0}, {bx0 + (bx1 - bx0) * f32(i) / 3, by1}, gc)
			rl.DrawLineV({bx0, by0 + (by1 - by0) * f32(i) / 3}, {bx1, by0 + (by1 - by0) * f32(i) / 3}, gc)
		}
	}

	// transform box
	if xform.active {
		cs := xform_corners()
		for i in 0 ..< 4 {
			a := canvas_to_screen(cs[i])
			b := canvas_to_screen(cs[(i + 1) % 4])
			rl.DrawLineV(a, b, Color{0, 0, 0, 200})
			rl.DrawLineV(a + 1, b + 1, Color{255, 255, 255, 220})
			m := (a + b) * 0.5
			handle_draw(m)
			handle_draw(a)
		}
	}

	// clone source marker
	if cur_tool == .Clone && clone_src_set {
		sp: Vec2
		if stroke.active && stroke.tool == .Clone {
			sp = canvas_to_screen(stroke.sm + stroke.clone_off)
		} else if !clone_realign {
			sp = canvas_to_screen(hover_pt + clone_off_saved)
		} else {
			sp = canvas_to_screen(clone_src_pt)
		}
		rl.DrawLineV(sp - {6, 0}, sp + {6, 0}, rl.WHITE)
		rl.DrawLineV(sp - {0, 6}, sp + {0, 6}, rl.WHITE)
		rl.DrawCircleLinesV(sp, 3, rl.BLACK)
	}

	if hover_valid && !drag.pan_active && ui.focus_id == 0 && ui.layer == ui.input_layer {
		render_cursor(d)
	}
}

ants_line :: proc(x, y, ln: f32, vert: bool, phase: f32) {
	// dashed black/white line, 4px dashes moving with time
	DASH :: 4
	start: f32 = 0
	for start < ln {
		k := math.floor((start + (vert ? y : x) + phase) / DASH)
		end := min((k + 1) * DASH - (vert ? y : x) - phase, ln)
		if end <= start {
			end = start + 1
		}
		c := int(k) % 2 == 0 ? rl.WHITE : rl.BLACK
		if vert {
			rl.DrawRectangleRec({x, y + start, 1, end - start}, c)
		} else {
			rl.DrawRectangleRec({x + start, y, end - start, 1}, c)
		}
		start = end
	}
}

handle_draw :: proc(p: Vec2) {
	rl.DrawRectangleRec({math.floor(p.x) - 3, math.floor(p.y) - 3, 7, 7}, rl.BLACK)
	rl.DrawRectangleRec({math.floor(p.x) - 2, math.floor(p.y) - 2, 5, 5}, rl.WHITE)
}

// Brush outline (ellipse in the brush's shape) or a small crosshair.
render_cursor :: proc(d: ^Doc) {
	t := eff_tool()
	mx := f32(rl.GetMouseX()) / f32(ui.scale)
	my := f32(rl.GetMouseY()) / f32(ui.scale)
	if !paint_tool(t) {
		return
	}
	b := &brushes[t]
	r := f32(b.size) / 2 * d.zoom
	if r < 3 {
		return
	}
	ang := f32(b.angle) * math.PI / 180
	if b.follow && stroke.active {
		ang += math.atan2(stroke.dir.y, stroke.dir.x)
	}
	ru := r * f32(clamp(b.roundness, 5, 100)) / 100
	n := clamp(int(r), 24, 96)
	ca, sa := math.cos(ang), math.sin(ang)
	prev: Vec2
	for i in 0 ..= n {
		th := f32(i) / f32(n) * math.TAU
		u, v := math.cos(th) * ru, math.sin(th) * r
		p := Vec2{mx + u * ca - v * sa, my + u * sa + v * ca}
		if i > 0 {
			rl.DrawLineV(prev, p, Color{0, 0, 0, 160})
			rl.DrawLineV(prev + 1, p + 1, Color{255, 255, 255, 200})
		}
		prev = p
	}
	rl.DrawRectangleRec({mx, my, 1, 1}, rl.WHITE)
}
