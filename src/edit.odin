package pangolin

// ---------------------------------------------------------------------------
// Clipboard and fills. Everything respects the (soft) selection.
// ---------------------------------------------------------------------------

edit_copy :: proc(cut, merged: bool) {
	d := doc
	b := doc_edit_box(d)
	if box_empty(b) {
		return
	}
	src: []Color
	if merged {
		doc_refresh_comp(d)
		src = d.comp
	} else {
		src = layer_flat(d, &d.layers[d.active_layer])
	}
	delete(clip.pix)
	bw, bh := b.x1 - b.x0, b.y1 - b.y0
	clip = Clip{bw, bh, b.x0, b.y0, make([]Color, bw * bh)}
	for y in b.y0 ..< b.y1 {
		for x in b.x0 ..< b.x1 {
			i := y * d.w + x
			p := src[i]
			p.a = u8(int(p.a) * int(sel_at(d, i)) / 255)
			clip.pix[(y - b.y0) * bw + x - b.x0] = p
		}
	}
	if cut {
		edit_clear()
		set_status("Cut")
	} else {
		set_status(merged ? "Copied (merged)" : "Copied")
	}
}

// Paste as a new layer at the copied position (centred if it no longer fits).
edit_paste :: proc() {
	d := doc
	if clip.pix == nil {
		set_status("Clipboard is empty")
		return
	}
	x0, y0 := clip.x, clip.y
	if x0 + clip.w > d.w || y0 + clip.h > d.h {
		x0, y0 = (d.w - clip.w) / 2, (d.h - clip.h) / 2
	}
	buf := make([]Color, d.w * d.h, context.temp_allocator)
	sel := make([]u8, d.w * d.h)
	for y in 0 ..< clip.h {
		ty := y0 + y
		if ty < 0 || ty >= d.h do continue
		for x in 0 ..< clip.w {
			tx := x0 + x
			if tx < 0 || tx >= d.w do continue
			p := clip.pix[y * clip.w + x]
			buf[ty * d.w + tx] = p
			sel[ty * d.w + tx] = p.a
		}
	}
	doc_add_layer_from(d, "Pasted", buf)
	doc_sel_set(d, sel)
	cur_tool = .Move
	set_status("Pasted as a new layer (move tool selected)")
}

edit_clear :: proc() {
	d := doc
	if !can_edit() {
		return
	}
	g, empty, _ := doc_target(d)
	b := doc_edit_box(d)
	bw := b.x1 - b.x0
	buf := make([]Color, bw * (b.y1 - b.y0), context.temp_allocator)
	tiles_read_box(g, b, buf, empty)
	history_push(d)
	for y in b.y0 ..< b.y1 {
		for x in b.x0 ..< b.x1 {
			s := sel_at(d, y * d.w + x)
			p := &buf[(y - b.y0) * bw + x - b.x0]
			if empty.a == 0 {
				p.a = u8(int(p.a) * (255 - int(s)) / 255)
			} else {
				// clearing a mask hides
				p^ = mix_px(p^, Color{0, 0, 0, 255}, f32(s) / 255)
			}
		}
	}
	tiles_write_box(g, b, buf, empty)
	doc_touch(d, b)
}

edit_fill :: proc(c: Color) {
	d := doc
	if !can_edit() {
		return
	}
	g, empty, is_mask := doc_target(d)
	col := c
	if is_mask {
		v := luma(c)
		col = Color{v, v, v, 255}
	}
	lock := !is_mask && d.layers[d.active_layer].lock_alpha
	b := doc_edit_box(d)
	bw := b.x1 - b.x0
	buf := make([]Color, bw * (b.y1 - b.y0), context.temp_allocator)
	tiles_read_box(g, b, buf, empty)
	history_push(d)
	for y in b.y0 ..< b.y1 {
		for x in b.x0 ..< b.x1 {
			a := f32(sel_at(d, y * d.w + x)) / 255
			p := &buf[(y - b.y0) * bw + x - b.x0]
			p^ = lock ? lock_mix(p^, col, a) : over_px(p^, col, a)
		}
	}
	tiles_write_box(g, b, buf, empty)
	doc_touch(d, b)
	recent_push(c)
}

// New layer from the selected pixels (Ctrl+J), optionally cutting them out.
edit_layer_via :: proc(cut: bool) {
	d := doc
	if d.sel == nil {
		doc_dup_layer(d)
		return
	}
	src := layer_flat(d, &d.layers[d.active_layer])
	buf := make([]Color, d.w * d.h, context.temp_allocator)
	for p, i in src {
		q := p
		q.a = u8(int(p.a) * int(d.sel.v[i]) / 255)
		buf[i] = q
	}
	if cut {
		if !can_edit() {
			return
		}
		history_push(d)
		for &p, i in src {
			p.a = u8(int(p.a) * (255 - int(d.sel.v[i])) / 255)
		}
		tiles_from_buf(&d.layers[d.active_layer].pix, d.w, d.h, src, {})
		// the snapshot above already covers the new layer too
		l := layer_make(cut ? "Cut layer" : "Layer copy", d.w, d.h)
		tiles_from_buf(&l.pix, d.w, d.h, buf, {})
		inject_at(&d.layers, d.active_layer + 1, l)
		d.active_layer += 1
		d.edit_mask = false
		doc_touch_all(d)
	} else {
		doc_add_layer_from(d, "Layer copy", buf)
	}
}

// Stretch each channel so the darkest/lightest 0.5% become black/white.
edit_auto_contrast :: proc() {
	if !live_begin() {
		return
	}
	d := doc
	hist: [256]int
	n := 0
	for p, i in live.orig {
		if p.a == 0 || sel_at(d, i) < 128 do continue
		hist[luma(p)] += 1
		n += 1
	}
	if n == 0 {
		live_cancel()
		return
	}
	cut := n / 200
	lo, hi := 0, 255
	acc := 0
	for v, i in hist {
		acc += v
		if acc > cut {
			lo = i
			break
		}
	}
	acc = 0
	#reverse for v, i in hist {
		acc += v
		if acc > cut {
			hi = i
			break
		}
	}
	if hi <= lo + 1 {
		live_cancel()
		set_status("Image already uses the full range")
		return
	}
	out := live_out()
	adj_levels(live.orig, out, lo, hi, 1, 0, 255, 0)
	live_store(out)
	live_finish()
	set_statusf("Auto contrast: %d..%d stretched to 0..255", lo, hi)
}

// ---------------------------------------------------------------------------
// Live preview for adjustments / filters: a snapshot of the target is filtered
// into a scratch buffer and blended back through the selection.
// ---------------------------------------------------------------------------

Live :: struct {
	active: bool,
	orig:   []Color, // target pixels before the dialog opened (w*h)
	out:    []Color,
	empty:  Color,
}

live: Live

live_begin :: proc() -> bool {
	d := doc
	if !can_edit() {
		return false
	}
	live_free()
	g, empty, _ := doc_target(d)
	history_push(d)
	live.active = true
	live.empty = empty
	live.orig = make([]Color, d.w * d.h)
	live.out = make([]Color, d.w * d.h)
	tiles_to_buf(g, d.w, d.h, live.orig, empty)
	return true
}

live_out :: proc() -> []Color {
	return live.out
}

// Write a filtered full-size buffer back, limited to and blended by the selection.
live_store :: proc(res: []Color) {
	d := doc
	g, empty, is_mask := doc_target(d)
	b := doc_edit_box(d)
	bw := b.x1 - b.x0
	buf := make([]Color, bw * (b.y1 - b.y0), context.temp_allocator)
	for y in b.y0 ..< b.y1 {
		for x in b.x0 ..< b.x1 {
			i := y * d.w + x
			s := sel_at(d, i)
			r := res[i]
			if is_mask {
				v := luma(r)
				r = Color{v, v, v, 255}
			}
			if s < 255 {
				r = mix_px(live.orig[i], r, f32(s) / 255)
			}
			buf[(y - b.y0) * bw + x - b.x0] = r
		}
	}
	tiles_write_box(g, b, buf, empty)
	doc_touch(d, b)
}

live_finish :: proc() {
	live_free()
	doc.thumb_dirty = true
}

live_cancel :: proc() {
	if live.active {
		history_revert(doc)
	}
	live_free()
}

live_free :: proc() {
	delete(live.orig)
	delete(live.out)
	live = {}
}
