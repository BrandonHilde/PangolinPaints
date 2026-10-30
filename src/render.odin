package pangolin

import "core:math"

tex_canvas: Texture
tex_checker: Texture
tex_w, tex_h: int
tex_doc: ^Doc // document whose pixels are in tex_canvas

render_init :: proc() {
	a := Color{204, 204, 212, 255}
	b := Color{150, 150, 162, 255}
	pix := [4]Color{a, b, b, a}
	tex_checker = tex_from_pixels(pix[:], 2, 2, .Point)
}

textures_ensure :: proc(d: ^Doc) {
	if tex_valid(tex_canvas) && tex_w == d.w && tex_h == d.h && tex_doc == d {
		return
	}
	if !tex_valid(tex_canvas) || tex_w != d.w || tex_h != d.h {
		tex_destroy(&tex_canvas)
		tex_canvas = tex_create(d.w, d.h, .Point)
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
		tex_update_rect(tex_canvas, b.x0, b.y0, bw, bh, raw_data(d.comp[b.y0 * d.w + b.x0:]), d.w)
		d.tex_dirty = {}
		for &m in mips {
			m.dirty = box_union(m.dirty, b)
		}
	}
}

// Zoomed-out views sample a box-filtered half/quarter/... resolution copy of the canvas, so thin strokes
// do not shimmer while panning (what mipmaps did on the GPU). Each level is built lazily and only
// re-averaged where the canvas changed.
MAX_MIP :: 7

Mip :: struct {
	tex:   Texture,
	w, h:  int,
	doc:   ^Doc,
	dirty: Box,
}

mips: [MAX_MIP + 1]Mip

mip_request :: proc(d: ^Doc, k: int) -> Texture {
	m := &mips[k]
	n := 1 << uint(k)
	mw, mh := (d.w + n - 1) >> uint(k), (d.h + n - 1) >> uint(k)
	if !tex_valid(m.tex) || m.w != mw || m.h != mh || m.doc != d {
		tex_destroy(&m.tex)
		m.tex = tex_create(mw, mh, .Linear)
		m.w, m.h, m.doc = mw, mh, d
		m.dirty = doc_box(d)
	}
	b := box_clip(m.dirty, d.w, d.h)
	if !box_empty(b) {
		x0, y0 := b.x0 >> uint(k), b.y0 >> uint(k)
		x1, y1 := min((b.x1 + n - 1) >> uint(k), mw), min((b.y1 + n - 1) >> uint(k), mh)
		bw, bh := x1 - x0, y1 - y0
		buf := make([]Color, bw * bh, context.temp_allocator)
		for my in y0 ..< y1 {
			sy0, sy1 := my << uint(k), min((my + 1) << uint(k), d.h)
			for mx in x0 ..< x1 {
				sx0, sx1 := mx << uint(k), min((mx + 1) << uint(k), d.w)
				ar, ag, ab, aa: u32
				for sy in sy0 ..< sy1 {
					row := d.comp[sy * d.w:]
					for sx in sx0 ..< sx1 {
						p := row[sx]
						a := u32(p.a)
						ar += u32(p.r) * a
						ag += u32(p.g) * a
						ab += u32(p.b) * a
						aa += a
					}
				}
				cnt := u32((sx1 - sx0) * (sy1 - sy0))
				c: Color
				if aa > 0 {
					c = {u8(ar / aa), u8(ag / aa), u8(ab / aa), u8(aa / cnt)}
				}
				buf[(my - y0) * bw + (mx - x0)] = c
			}
		}
		tex_update_rect(m.tex, x0, y0, bw, bh, raw_data(buf), bw)
	}
	m.dirty = {}
	return m.tex
}

// Draws the canvas pixels into `dst`, picking a sampling strategy from the on-screen scale.
draw_canvas_tex :: proc(d: ^Doc, dst: FRect) {
	z := dst.w / f32(d.w)
	k := 0
	for k < MAX_MIP && z * f32(int(1) << uint(k + 1)) <= 1 {
		k += 1
	}
	if k > 0 {
		t := mip_request(d, k)
		n := f32(int(1) << uint(k))
		draw_tex(t, {0, 0, f32(d.w) / n, f32(d.h) / n}, dst)
		return
	}
	tex_set_filter(tex_canvas, z < 2 ? .Linear : .Point)
	draw_tex(tex_canvas, {0, 0, f32(d.w), f32(d.h)}, dst)
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

draw_canvas_bg :: proc(dst: FRect) {
	if bg_mode == 0 {
		draw_tex_tiled(tex_checker, dst, 16)
	} else {
		draw_frect(dst, canvas_bg_color())
	}
}

draw_checker :: proc(r: Rect, cell: i32 = 4) {
	draw_tex_tiled(tex_checker, FRect{f32(r.x), f32(r.y), f32(r.w), f32(r.h)}, f32(cell) * 2)
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
	dst := FRect{d.ox, d.oy, cw, ch}
	// drop shadow
	draw_shadow(dst.x, dst.y + 3, dst.w, dst.h, 0, 14, Color{0, 0, 0, 150})
	draw_canvas_bg(dst)
	draw_canvas_tex(d, dst)
	if seamless_mode {
		// the surrounding 8 copies, so the image can be judged as a repeating texture
		for ty in -1 ..= 1 {
			for tx in -1 ..= 1 {
				if tx == 0 && ty == 0 do continue
				t := FRect{d.ox + f32(tx) * cw, d.oy + f32(ty) * ch, cw, ch}
				if t.x >= f32(vp.x + vp.w) || t.y >= f32(vp.y + vp.h) || t.x + cw <= f32(vp.x) || t.y + ch <= f32(vp.y) do continue
				draw_canvas_bg(t)
				draw_canvas_tex(d, t)
			}
		}
	}

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
	render_grid(d, vp)
	outline_rect(Rect{x0 - 1, y0 - 1, x1 - x0 + 2, y1 - y0 + 2}, Color{10, 10, 14, 255})

	// selection outline (marching ants)
	doc_rebuild_edges(d)
	if len(d.sel_edges) > 0 {
		phase := f32(ui.time * 8)
		span := seamless_mode ? 1 : 0
		for ty in -span ..= span {
			for tx in -span ..= span {
				for e in d.sel_edges {
					sx := d.ox + f32(tx) * cw + f32(e.x) * z
					sy := d.oy + f32(ty) * ch + f32(e.y) * z
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
		}
	}

	// crop overlay
	if crop.active {
		b := crop_box()
		bx0, by0 := d.ox + f32(b.x0) * z, d.oy + f32(b.y0) * z
		bx1, by1 := d.ox + f32(b.x1) * z, d.oy + f32(b.y1) * z
		dark := Color{0, 0, 0, 150}
		draw_frect({dst.x, dst.y, cw, by0 - dst.y}, dark)
		draw_frect({dst.x, by1, cw, dst.y + ch - by1}, dark)
		draw_frect({dst.x, by0, bx0 - dst.x, by1 - by0}, dark)
		draw_frect({bx1, by0, dst.x + cw - bx1, by1 - by0}, dark)
		draw_rect_outline({bx0, by0, bx1 - bx0, by1 - by0}, WHITE)
		for i in 1 ..= 2 {
			gc := Color{255, 255, 255, 80}
			draw_line({bx0 + (bx1 - bx0) * f32(i) / 3, by0}, {bx0 + (bx1 - bx0) * f32(i) / 3, by1}, gc)
			draw_line({bx0, by0 + (by1 - by0) * f32(i) / 3}, {bx1, by0 + (by1 - by0) * f32(i) / 3}, gc)
		}
	}

	// transform box
	if xform.active {
		cs := xform_corners()
		for i in 0 ..< 4 {
			a := canvas_to_screen(cs[i])
			b := canvas_to_screen(cs[(i + 1) % 4])
			draw_line(a, b, Color{0, 0, 0, 200})
			draw_line(a + 1, b + 1, Color{255, 255, 255, 220})
			m := (a + b) * 0.5
			handle_draw(m)
			handle_draw(a)
		}
	}

	text_draw_overlay(d)
	render_line_preview(d)

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
		draw_line(sp - {6, 0}, sp + {6, 0}, WHITE)
		draw_line(sp - {0, 6}, sp + {0, 6}, WHITE)
		draw_circle_outline(sp.x, sp.y, 3, BLACK)
	}

	if hover_valid && !drag.pan_active && ui.focus_id == 0 && ui.layer == ui.input_layer {
		render_cursor(d)
		if grid_snapping() && tool_snaps(eff_tool()) {
			render_snap_marker(hover_pt)
		}
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
		c := int(k) % 2 == 0 ? WHITE : BLACK
		if vert {
			draw_frect({x, y + start, 1, end - start}, c)
		} else {
			draw_frect({x + start, y, end - start, 1}, c)
		}
		start = end
	}
}

handle_draw :: proc(p: Vec2) {
	draw_frect({math.floor(p.x) - 3, math.floor(p.y) - 3, 7, 7}, BLACK)
	draw_frect({math.floor(p.x) - 2, math.floor(p.y) - 2, 5, 5}, WHITE)
}

// Brush outline (ellipse in the brush's shape), drawn thicker for small brushes.
render_cursor :: proc(d: ^Doc) {
	t := eff_tool()
	mx := ui.ptr.x / f32(ui.scale)
	my := ui.ptr.y / f32(ui.scale)
	if !paint_tool(t) {
		return
	}
	if grid_snapping() {
		// the ring sits where the dab will land
		sp := canvas_to_screen(hover_pt)
		mx, my = sp.x, sp.y
	}
	b := &brushes[t]
	r := f32(b.size) / 2 * d.zoom
	// same outline as every other size; a small brush just gets a thicker line so it stays visible
	bold := r < 3
	r = max(r, 1.5)
	ang := f32(b.angle) * math.PI / 180
	if b.follow && stroke.active {
		ang += math.atan2(stroke.dir.y, stroke.dir.x)
	}
	ru := r * f32(clamp(b.roundness, 5, 100)) / 100
	n := clamp(int(r), 24, 96)
	ca, sa := math.cos(ang), math.sin(ang)
	pts := make([]Vec2, n + 1, context.temp_allocator)
	for i in 0 ..= n {
		th := f32(i) / f32(n) * math.TAU
		u, v := math.cos(th) * ru, math.sin(th) * r
		pts[i] = Vec2{mx + u * ca - v * sa, my + u * sa + v * ca}
	}
	// Every copy is offset symmetrically around the pointer, so the ring stays centred on it.
	// All dark copies go down first, then all white ones, so neighbouring segments don't overpaint.
	// Bold: a 2px white line (offsets 0..1) inside a dark halo (-1..2); -0.5 recentres the 4x4 block.
	for pass in 0 ..< 2 {
		for i in 1 ..= n {
			a, b := pts[i - 1], pts[i]
			if bold {
				for dy in -1 ..= 2 {
					for dx in -1 ..= 2 {
						white := dx >= 0 && dx <= 1 && dy >= 0 && dy <= 1
						if white != (pass == 1) do continue
						o := Vec2{f32(dx) - 0.5, f32(dy) - 0.5}
						draw_line(a + o, b + o, white ? WHITE : Color{0, 0, 0, 200})
					}
				}
			} else if pass == 0 {
				draw_line(a - 0.5, b - 0.5, Color{0, 0, 0, 160})
			} else {
				draw_line(a + 0.5, b + 0.5, Color{255, 255, 255, 200})
			}
		}
	}
	draw_frect({mx - 0.5, my - 0.5, 1, 1}, WHITE)
}
