package pangolin

import "core:fmt"
import "core:math"
import "core:strings"
import "core:time"

// Headless tests: `PangolinPaints --selftest`. Returns the number of failures.

@(private = "file")
fails: int

@(private = "file")
check :: proc(cond: bool, what: string, loc := #caller_location) {
	if !cond {
		fails += 1
		fmt.printf("FAIL %s (line %d)\n", what, loc.line)
	}
}

@(private = "file")
px :: proc(d: ^Doc, l, x, y: int) -> Color {
	return tiles_get(&d.layers[l].pix, x, y, {})
}

@(private = "file")
paint_line :: proc(t: Tool, col: Color, a, b: Vec2, steps := 40) {
	if !stroke_begin(t, a, col) do return
	for i in 1 ..= steps {
		stroke_move(a + (b - a) * (f32(i) / f32(steps)))
	}
	// let the stabiliser catch up
	for _ in 0 ..< 30 {
		stroke_move(b)
	}
	stroke_end()
}

@(private = "file")
fresh :: proc(w, h: int, fill: Color) -> ^Doc {
	d := doc_new_filled(w, h, "test", fill)
	append(&docs, d)
	doc = d
	return d
}

selftest :: proc() -> int {
	brush_init()
	fails = 0
	red := Color{220, 30, 30, 255}
	blue := Color{30, 60, 220, 255}
	white := Color{255, 255, 255, 255}

	// --- tiles --------------------------------------------------------------
	{
		g := tiles_make(150, 70)
		buf := make([]Color, 150 * 70, context.temp_allocator)
		for &p, i in buf do p = Color{u8(i), u8(i >> 8), 7, 255}
		tiles_from_buf(&g, 150, 70, buf, {})
		out := make([]Color, 150 * 70, context.temp_allocator)
		tiles_to_buf(&g, 150, 70, out, {})
		same := true
		for p, i in out do if p != buf[i] do same = false
		check(same, "tiles round trip")
		sh := tiles_share(&g)
		tiles_set(&g, 5, 5, red, {})
		check(tiles_get(&sh, 5, 5, {}) == buf[5 * 150 + 5], "copy-on-write keeps the snapshot")
		check(tiles_get(&g, 5, 5, {}) == red, "copy-on-write writes the copy")
		check(g.t[0] != sh.t[0] && g.t[1] == sh.t[1], "only the touched tile is cloned")
		tiles_destroy(&sh)
		clr := make([]Color, 150 * 70, context.temp_allocator)
		tiles_from_buf(&g, 150, 70, clr, {})
		check(tiles_count(&g) == 0, "empty tiles are released")
		tiles_destroy(&g)
	}

	// --- brush, undo/redo -------------------------------------------------------
	{
		d := fresh(200, 120, white)
		b := &brushes[.Brush]
		b^ = brush_default(.Brush)
		b.size, b.hardness, b.opacity, b.flow = 12, 100, 100, 100
		paint_line(.Brush, red, {20, 60}, {180, 60})
		check(px(d, 0, 100, 60) == red, "hard brush paints solid colour")
		check(px(d, 0, 100, 20) == white, "brush leaves other pixels alone")
		check(len(d.undo) == 1, "one undo step per stroke")
		history_undo(d)
		check(px(d, 0, 100, 60) == white, "undo restores the stroke area")
		history_redo(d)
		check(px(d, 0, 100, 60) == red, "redo repaints")

		// opacity caps a stroke, even where dabs overlap
		b.opacity = 50
		paint_line(.Brush, blue, {20, 30}, {180, 30})
		c := px(d, 0, 100, 30)
		check(abs(int(c.r) - 142) <= 3 && abs(int(c.g) - 157) <= 3, fmt.tprintf("50%% opacity stroke mixes halfway (got %v)", c))
		b.opacity = 100

		// soft brush: centre stronger than the edge
		b.hardness = 0
		b.size = 30
		paint_line(.Brush, blue, {100, 95}, {101, 95}, 2)
		cc, ce := px(d, 0, 100, 95), px(d, 0, 100, 108)
		check(cc.r < ce.r && cc.r < 120 && ce.r > 150, fmt.tprintf("soft brush falls off (%v / %v)", cc, ce))

		// selection limits painting
		b.hardness = 100
		b.size = 40
		doc_sel_set(d, sel_rect(d.w, d.h, {0, 0}, {100, 120}))
		paint_line(.Brush, blue, {60, 10}, {140, 10})
		check(px(d, 0, 80, 10) == blue && px(d, 0, 120, 10) == white, "selection masks the brush")
		doc_sel_clear(d)

		// eraser
		layer := 0
		paint_line(.Eraser, white, {20, 60}, {180, 60})
		check(px(d, layer, 100, 60).a == 0, "eraser clears alpha")

		// lock transparency: painting keeps alpha
		d.layers[0].lock_alpha = true
		paint_line(.Brush, blue, {20, 60}, {180, 60})
		check(px(d, 0, 100, 60).a == 0, "lock transparency protects clear pixels")
		d.layers[0].lock_alpha = false
	}

	// --- oil and smudge ------------------------------------------------------------
	{
		d := fresh(200, 100, white)
		// left half red, right half blue
		for y in 0 ..< 100 {
			for x in 0 ..< 200 {
				tiles_set(&d.layers[0].pix, x, y, x < 100 ? red : blue, {})
			}
		}
		s := &brushes[.Smudge]
		s^ = brush_default(.Smudge)
		s.size, s.strength = 30, 90
		paint_line(.Smudge, white, {60, 50}, {150, 50})
		c := px(d, 0, 120, 50)
		check(c.r > 60 && c.b < 210, fmt.tprintf("smudge drags red into blue (got %v)", c))

		o := &brushes[.Oil]
		o^ = brush_default(.Oil)
		o.size, o.load, o.wet, o.bristles, o.tip = 30, 100, 0, 0, .Round
		paint_line(.Oil, Color{240, 220, 40, 255}, {20, 20}, {180, 20})
		y := px(d, 0, 100, 20)
		check(y.r > 200 && y.g > 180, fmt.tprintf("dry loaded oil covers (got %v)", y))
		o.wet, o.load = 90, 10
		paint_line(.Oil, Color{240, 220, 40, 255}, {20, 80}, {180, 80})
		m := px(d, 0, 170, 80)
		check(m.b > 60, fmt.tprintf("wet oil picks up canvas colour (got %v)", m))
	}

	// --- layers, blend modes, masks -------------------------------------------------
	{
		d := fresh(64, 64, Color{100, 100, 100, 255})
		doc_add_layer(d)
		tiles_fill(&d.layers[1].pix, Color{200, 200, 200, 255}, {})
		d.layers[1].blend = .Multiply
		doc_dirty_all(d)
		doc_refresh_comp(d)
		check(abs(int(d.comp[0].r) - 78) <= 1, fmt.tprintf("multiply blend (got %v)", d.comp[0]))
		d.layers[1].blend = .Normal
		doc_add_mask(d, false)
		check(d.edit_mask, "new mask is selected for editing")
		b := &brushes[.Brush]
		b.size, b.hardness, b.opacity, b.flow = 20, 100, 100, 100
		paint_line(.Brush, Color{0, 0, 0, 255}, {0, 10}, {63, 10})
		doc_dirty_all(d)
		doc_refresh_comp(d)
		check(d.comp[10 * 64 + 30].r == 100, "black on the mask hides the layer")
		check(d.comp[50 * 64 + 30].r == 200, "white mask shows the layer")
		check(px(d, 1, 30, 10).r == 200, "mask painting leaves pixels untouched")
		doc_merge_down(d)
		check(len(d.layers) == 1 && px(d, 0, 30, 10).r == 100 && px(d, 0, 30, 50).r == 200, "merge down applies the mask")
	}

	// --- transforms -------------------------------------------------------------
	{
		d := fresh(100, 50, white)
		tiles_set(&d.layers[0].pix, 0, 0, red, {})
		doc_rotate(d, 1)
		check(d.w == 50 && d.h == 100 && px(d, 0, 49, 0) == red, "rotate 90 CW")
		doc_image_size(d, 25, 50, .Bicubic)
		check(d.w == 25 && d.h == 50, "image size")
		doc_canvas_size(d, 40, 60, 5, 5)
		check(d.w == 40 && d.h == 60 && px(d, 0, 0, 0).a == 0 && px(d, 0, 10, 10) == white, "canvas size adds transparent margin")
		doc_crop(d, Box{5, 5, 30, 55})
		check(d.w == 25 && d.h == 50, "crop")
		doc_rotate_any(d, 45)
		check(d.w > 40 && d.h > 40, "free rotate enlarges canvas")
		check(len(d.undo) == 5, "each transform is one undo step")
	}

	// --- adjustments through the live preview path -----------------------------------
	{
		d := fresh(64, 32, Color{100, 150, 200, 255})
		doc_sel_set(d, sel_rect(d.w, d.h, {0, 0}, {32, 32}))
		fx_open(.Invert)
		check(px(d, 0, 10, 10) == Color{155, 105, 55, 255}, "invert inside selection")
		check(px(d, 0, 50, 10) == Color{100, 150, 200, 255}, "invert leaves outside alone")
		history_undo(d)
		check(px(d, 0, 10, 10) == Color{100, 150, 200, 255}, "adjustment undo")
		doc_sel_clear(d)
		live_begin()
		fxs.fx = .Gaussian_Blur
		fxs.v[0] = 30
		fx_apply_now()
		live_cancel()
		check(px(d, 0, 10, 10) == Color{100, 150, 200, 255} && len(d.undo) == 0, "cancelled preview restores pixels")
	}

	// --- project file round trip --------------------------------------------------
	{
		d := fresh(130, 70, Color{10, 20, 30, 255})
		doc_add_layer(d)
		tiles_set(&d.layers[1].pix, 129, 69, red, {})
		d.layers[1].opacity = 128
		d.layers[1].blend = .Screen
		doc_add_mask(d, false)
		tiles_set(&d.layers[1].mask, 3, 3, Color{50, 50, 50, 255}, MASK_EMPTY)
		data := project_encode(d)
		nd, ok := project_decode(data)
		check(ok, "project decodes")
		if ok {
			check(nd.w == 130 && nd.h == 70 && len(nd.layers) == 2, "project size and layers")
			check(tiles_get(&nd.layers[1].pix, 129, 69, {}) == red, "project pixels")
			check(tiles_get(&nd.layers[0].pix, 64, 64, {}) == Color{10, 20, 30, 255}, "project background")
			check(nd.layers[1].opacity == 128 && nd.layers[1].blend == .Screen, "project layer settings")
			check(nd.layers[1].has_mask && tiles_get(&nd.layers[1].mask, 3, 3, MASK_EMPTY).r == 50 && tiles_get(&nd.layers[1].mask, 60, 3, MASK_EMPTY).r == 255, "project mask")
			doc_destroy(nd)
		}
		_, bad := project_decode(data[:len(data) / 2])
		check(!bad, "truncated project is rejected")
	}

	// --- text layers ----------------------------------------------------------------
	{
		d := fresh(300, 120, Color{255, 255, 255, 255})
		doc = d
		l := layer_make("Text", 300, 120)
		l.text = Text_Info{on = true, size = 40, color = Color{200, 30, 30, 255}, line_pct = 100, x = 10, y = 10}
		name_set(&l.text.font, DEFAULT_FONT)
		msg := "Hello\nWorld"
		copy(l.text.buf[:], msg)
		l.text.n = len(msg)
		append(&d.layers, l)
		text_render_layer(d, 1)
		tl := &d.layers[1]
		check(!box_empty(tl.text.bx), "text renders a block")
		inked := 0
		for y in tl.text.bx.y0 ..< tl.text.bx.y1 {
			for x in tl.text.bx.x0 ..< tl.text.bx.x1 {
				if tiles_get(&tl.pix, x, y, {}).a > 0 do inked += 1
			}
		}
		check(inked > 200, fmt.tprintf("text paints pixels (%d)", inked))
		check(tl.text.bx.y1 - tl.text.bx.y0 > 70, "two lines are taller than one")
		cx, cy, _ := text_caret_xy(&tl.text, 6)
		check(cx == tl.text.x && cy > tl.text.y + 30, "caret on the second line")
		data := project_encode(d)
		nd, ok := project_decode(data)
		check(ok, "text project decodes")
		if ok {
			nt := &nd.layers[1].text
			check(nt.on && text_str(nt) == msg && nt.size == 40 && nt.color == Color{200, 30, 30, 255}, "text settings survive saving")
			check(tiles_get(&nd.layers[1].pix, tl.text.bx.x0 + 20, tl.text.bx.y0 + 25, {}) == tiles_get(&tl.pix, tl.text.bx.x0 + 20, tl.text.bx.y0 + 25, {}), "text pixels survive saving")
			doc_destroy(nd)
		}
		doc = nil
	}

	// --- image codecs -----------------------------------------------------------
	{
		w, h := 97, 61
		pix := make([]Color, w * h, context.temp_allocator)
		for y in 0 ..< h {
			for x in 0 ..< w {
				pix[y * w + x] = Color{u8(x * 255 / w), u8(y * 255 / h), 128, 255}
			}
		}
		jpg := export_encode(pix, w, h, .JPG, 95)
		back, bw, bh, ok := jpeg_decode(jpg)
		check(ok && bw == w && bh == h, "jpeg round trip size")
		if ok {
			err := 0
			for p, i in back {
				err += abs(int(p.r) - int(pix[i].r)) + abs(int(p.g) - int(pix[i].g)) + abs(int(p.b) - int(pix[i].b))
			}
			check(f32(err) / f32(w * h * 3) < 2.5, "jpeg quality")
			delete(back)
		}
		png := export_encode(pix, w, h, .PNG, 0)
		pb, pw, ph, pok := decode_image(png, ".png")
		check(pok && pw == w && ph == h && pb[500] == pix[500], "png round trip")
		if pok do delete(pb)
		for f in ([?]Export_Format{.BMP, .TGA, .QOI}) {
			check(len(export_encode(pix, w, h, f, 0)) > 0, fmt.tprintf("%v export", f))
		}		// alpha that varies, so the predictor and the alpha channel both get exercised
		tp := make([]Color, w * h, context.temp_allocator)
		for &c, i in tp do c = Color{pix[i].r, pix[i].g, pix[i].b, u8(i * 7)}
		tif := export_encode(tp, w, h, .TIFF, 0)
		tb, tw, th, tok := decode_image(tif, ".tif")
		same := tok && tw == w && th == h
		if same {
			for c, i in tb do if c != tp[i] {same = false; break}
		}
		check(same, "tiff round trip")
		if tok do delete(tb)
	}

	// --- grid snapping --------------------------------------------------------------
	{
		d := fresh(95, 60, white)
		show_grid, snap_grid, grid_w, grid_h = true, true, 10, 20
		check(snap_pt({13, 7}) == Vec2{10, 0} && snap_pt({16, 11}) == Vec2{20, 20}, "points snap to grid intersections")
		check(snap_pt({93.5, 59}) == Vec2{95, 60}, "canvas edges snap like grid lines")
		snap_grid = false
		check(snap_pt({13, 7}) == Vec2{13, 7}, "no snapping when snap is off")
		snap_grid, show_grid = true, false
		check(snap_pt({13, 7}) == Vec2{13, 7}, "no snapping while the grid is hidden")
		show_grid = true
		// a freehand stroke snapped point by point paints along the grid lines
		paint_line(.Brush, red, snap_pt({12, 31}), snap_pt({48, 38}))
		check(px(d, 0, 30, 40) == red && px(d, 0, 30, 25) == white, "snapped stroke follows the grid line")
		show_grid, grid_w, grid_h = false, 64, 64
	}

	// --- defaults ------------------------------------------------------------------
	{
		check(brush_default(.Brush).pressure == .Pen && brush_default(.Eraser).pressure == .Pen, "pen pressure is on by default")
		old := brush_to_ints(brush_default(.Brush))
		old[13] = int(Pressure.Off)
		check(brush_from_ints(brush_default(.Brush), old[:25]).pressure == .Pen, "old saved brushes get pen pressure")
		check(brush_from_ints(brush_default(.Brush), old[:]).pressure == .Off, "pressure turned off by the user stays off")
		d := doc_new_painting(40, 30, "two", white)
		check(len(d.layers) == 2 && d.active_layer == 1 && px(d, 1, 5, 5).a == 0 && px(d, 0, 5, 5) == white, "new painting has a clear layer over the background")
		doc_destroy(d)
	}

	// --- selections -----------------------------------------------------------------
	{
		d := fresh(80, 80, white)
		e := sel_ellipse(80, 80, {10, 10}, {70, 70})
		check(e[40 * 80 + 40] == 255 && e[0] == 0, "ellipse selection")
		edge := e[40 * 80 + 10]
		check(edge > 0 && edge < 255, "ellipse selection is anti-aliased")
		doc_sel_set(d, e)
		check(d.sel != nil && d.sel.bbox.x0 >= 9 && d.sel.bbox.x1 <= 71, "selection bounds")
		v := make([]u8, 80 * 80)
		copy(v, d.sel.v)
		mask_grow(v, 80, 80, 5)
		check(v[40 * 80 + 6] == 255, "grow selection")
		mask_grow(v, 80, 80, -10)
		check(v[40 * 80 + 12] == 0, "shrink selection")
		delete(v)
		poly := [?]Vec2{{10, 10}, {70, 10}, {40, 70}}
		pm := sel_polygon(80, 80, poly[:])
		check(pm[30 * 80 + 40] == 255 && pm[60 * 80 + 10] == 0, "lasso polygon")
		delete(pm)
	}

	if fails == 0 {
		fmt.println("selftest: all passed")
	} else {
		fmt.printf("selftest: %d failure(s)\n", fails)
	}
	return fails
}

// Opens any supported file and exports it flattened (`--convert in out.png`), listing its layers;
// a headless check of the file readers.
convert_file :: proc(src, dst: string) -> int {
	brush_init()
	d, err := doc_load(src)
	if err != "" {
		fmt.eprintln(err)
		return 1
	}
	fmt.printf("%s: %dx%d, %d layer(s)\n", path_basename(src), d.w, d.h, len(d.layers))
	for &l, i in d.layers {
		fmt.printf("  %d %q opacity %d %v%s%s%s\n", i, name_str(&l.name), l.opacity, l.blend, l.visible ? "" : " hidden", l.has_mask ? " mask" : "", l.text.on ? " text" : "")
	}
	f := Export_Format.PNG
	for e, k in EXPORT_EXT {
		if lower_ext(dst) == fmt.tprintf(".%s", e) do f = k
	}
	data := export_encode(doc_flat(d, context.temp_allocator), d.w, d.h, f, 90)
	if data == nil || !write_file(dst, data) {
		fmt.eprintln("cannot write", dst)
		return 1
	}
	return 0
}

// Paints one sample stroke per brush preset onto a sheet (`--brush-sheet out.png`),
// for eyeballing brush quality at 100%.
brush_sheet :: proc(path: string) -> int {
	brush_init()
	row_h := 90
	w, h := 900, row_h * len(presets)
	d := doc_new_filled(w, h, "sheet", Color{244, 240, 230, 255})
	append(&docs, d)
	doc = d
	bands := [?]Color{{196, 58, 46, 255}, {236, 196, 60, 255}, {52, 100, 180, 255}, {30, 30, 34, 255}}
	cols := [?]Color{{30, 30, 34, 255}, {178, 52, 40, 255}, {40, 92, 170, 255}, {60, 130, 70, 255}}
	for p, i in presets {
		y0 := i * row_h
		// blending tools get colour bands to work on
		if p.tool != .Brush && p.tool != .Oil {
			for y in y0 + 8 ..< y0 + row_h - 8 {
				for x in 160 ..< w {
					tiles_set(&d.layers[0].pix, x, y, bands[((x - 160) * len(bands)) / (w - 160)], {})
				}
			}
		} else {
			// a half-dark stripe to show coverage and mixing
			for y in y0 + 8 ..< y0 + row_h - 8 {
				for x in 520 ..< w {
					tiles_set(&d.layers[0].pix, x, y, Color{70, 60, 110, 255}, {})
				}
			}
		}
		brushes[p.tool] = p.b
		brushes[p.tool].size = min(p.b.size, row_h - 30)
		if p.tool == .Clone {
			clone_src_pt = Vec2{170, f32(y0 + row_h / 2)}
			clone_src_set, clone_realign = true, true
		}
		pts := 120
		for k in 0 ..= pts {
			u := f32(k) / f32(pts)
			pt := Vec2{170 + u * f32(w - 200), f32(y0 + row_h / 2) + 22 * f32(math.sin(u * 9))}
			if p.tool == .Clone do pt.x = 320 + u * f32(w - 360)
			if k == 0 {
				stroke_begin(p.tool, pt, cols[i % len(cols)])
			} else {
				stroke_move(pt)
			}
		}
		stroke_end()
	}
	doc_dirty_all(d)
	doc_refresh_comp(d)
	// labels are rasterised straight into the image
	cp := make([]Color, w * h)
	defer delete(cp)
	copy(cp, d.comp)
	for p, i in presets {
		image_draw_text(cp, w, h, 8, i * row_h + row_h / 2 - 5, fmt.tprintf("%v: %s", p.tool, p.name), 14, BLACK)
	}
	return write_file(path, encode_png(cp, w, h)) ? 0 : 1
}

// Rough timings for big canvases (`--bench`).
bench :: proc() -> int {
	brush_init()
	d := doc_new_filled(4000, 3000, "bench", Color{240, 234, 220, 255})
	append(&docs, d)
	doc = d
	run :: proc(name: string, t: Tool, size: int, n: int) {
		brushes[t].size = size
		t0 := now_s()
		if !stroke_begin(t, {200, 1500}, Color{120, 60, 30, 255}) do return
		for i in 1 ..= n {
			stroke_move(Vec2{200 + f32(i) * 3000 / f32(n), 1500 + 600 * f32(math.sin(f32(i) * 0.05))})
			doc_refresh_comp(doc)
		}
		stroke_end()
		dt := now_s() - t0
		fmt.printf("%s (%d px): %.2f ms/frame\n", name, size, dt * 1000 / f64(n))
	}
	// 120 frames covering 3000 px: ~25 px of mouse travel per frame
	run("Brush hard", .Brush, 40, 120)
	run("Brush soft", .Brush, 300, 120)
	run("Oil", .Oil, 80, 120)
	run("Oil big", .Oil, 250, 120)
	run("Smudge", .Smudge, 150, 120)
	t0 := now_s()
	doc_dirty_all(d)
	doc_refresh_comp(d)
	fmt.printf("full composite 12 MP: %.1f ms\n", (now_s() - t0) * 1000)
	t0 = now_s()
	data := project_encode(d)
	fmt.printf("save project: %.1f ms, %d KB\n", (now_s() - t0) * 1000, len(data) / 1024)
	return 0
}

now_s :: proc() -> f64 {
	return f64(time.now()._nsec) / 1e9
}
