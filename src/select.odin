package pangolin

import "core:math"

// ---------------------------------------------------------------------------
// Selection shapes. All return a new w*h coverage buffer (0..255), anti-aliased.
// ---------------------------------------------------------------------------

sel_rect :: proc(w, h: int, a, b: Vec2) -> []u8 {
	m := make([]u8, w * h)
	x0, x1 := min(a.x, b.x), max(a.x, b.x)
	y0, y1 := min(a.y, b.y), max(a.y, b.y)
	ix0, ix1 := clamp(int(math.floor(x0)), 0, w), clamp(int(math.ceil(x1)), 0, w)
	iy0, iy1 := clamp(int(math.floor(y0)), 0, h), clamp(int(math.ceil(y1)), 0, h)
	for y in iy0 ..< iy1 {
		cy := clamp(min(f32(y + 1), y1) - max(f32(y), y0), 0, 1)
		for x in ix0 ..< ix1 {
			cx := clamp(min(f32(x + 1), x1) - max(f32(x), x0), 0, 1)
			m[y * w + x] = u8(cx * cy * 255 + 0.5)
		}
	}
	return m
}

sel_ellipse :: proc(w, h: int, a, b: Vec2) -> []u8 {
	m := make([]u8, w * h)
	x0, x1 := min(a.x, b.x), max(a.x, b.x)
	y0, y1 := min(a.y, b.y), max(a.y, b.y)
	rx, ry := (x1 - x0) / 2, (y1 - y0) / 2
	if rx < 0.25 || ry < 0.25 {
		return m
	}
	cx, cy := (x0 + x1) / 2, (y0 + y1) / 2
	ix0, ix1 := clamp(int(math.floor(x0)), 0, w), clamp(int(math.ceil(x1)), 0, w)
	iy0, iy1 := clamp(int(math.floor(y0)), 0, h), clamp(int(math.ceil(y1)), 0, h)
	// signed distance approximation scaled to pixels gives a 1px soft edge
	rmin := min(rx, ry)
	for y in iy0 ..< iy1 {
		dy := (f32(y) + 0.5 - cy) / ry
		for x in ix0 ..< ix1 {
			dx := (f32(x) + 0.5 - cx) / rx
			d := (math.sqrt(dx * dx + dy * dy) - 1) * rmin
			c := clamp(0.5 - d, 0, 1)
			m[y * w + x] = u8(c * 255 + 0.5)
		}
	}
	return m
}

// Polygon fill with 4x vertical supersampling and exact horizontal coverage.
sel_polygon :: proc(w, h: int, pts: []Vec2) -> []u8 {
	m := make([]u8, w * h)
	if len(pts) < 3 {
		return m
	}
	miny, maxy := pts[0].y, pts[0].y
	for p in pts {
		miny = min(miny, p.y)
		maxy = max(maxy, p.y)
	}
	y0 := clamp(int(math.floor(miny)), 0, h)
	y1 := clamp(int(math.ceil(maxy)), 0, h)
	SUB :: 4
	acc := make([]f32, w, context.temp_allocator)
	xs := make([dynamic]f32, context.temp_allocator)
	for y in y0 ..< y1 {
		for &v in acc do v = 0
		for s in 0 ..< SUB {
			sy := f32(y) + (f32(s) + 0.5) / SUB
			clear(&xs)
			n := len(pts)
			for i in 0 ..< n {
				a := pts[i]
				b := pts[(i + 1) % n]
				if (a.y <= sy && b.y > sy) || (b.y <= sy && a.y > sy) {
					t := (sy - a.y) / (b.y - a.y)
					append(&xs, a.x + t * (b.x - a.x))
				}
			}
			// insertion sort (few crossings per line)
			for i in 1 ..< len(xs) {
				j := i
				for j > 0 && xs[j - 1] > xs[j] {
					xs[j - 1], xs[j] = xs[j], xs[j - 1]
					j -= 1
				}
			}
			for i := 0; i + 1 < len(xs); i += 2 {
				a := clamp(xs[i], 0, f32(w))
				b := clamp(xs[i + 1], 0, f32(w))
				if b <= a do continue
				ia, ib := int(a), int(b)
				if ia == ib {
					if ia < w do acc[ia] += b - a
					continue
				}
				acc[ia] += f32(ia + 1) - a
				for x in ia + 1 ..< ib {
					acc[x] += 1
				}
				if ib < w do acc[ib] += b - f32(ib)
			}
		}
		for x in 0 ..< w {
			m[y * w + x] = u8(clamp(acc[x] / SUB, 0, 1) * 255 + 0.5)
		}
	}
	return m
}

// ---------------------------------------------------------------------------
// Region selection (flood fill / magic wand). Distance is the max channel difference.
// ---------------------------------------------------------------------------

color_match :: #force_inline proc(a, b: Color, tol: int) -> bool {
	if a.a == 0 && b.a == 0 {
		return true
	}
	return(
		abs(int(a.r) - int(b.r)) <= tol &&
		abs(int(a.g) - int(b.g)) <= tol &&
		abs(int(a.b) - int(b.b)) <= tol &&
		abs(int(a.a) - int(b.a)) <= tol \
	)
}

// Returns a w*h mask (255 = in region). Edge pixels get partial coverage when
// `antialias` is set so fills blend into soft edges instead of leaving gaps.
region_select :: proc(pix: []Color, w, h, sx, sy, tol: int, contiguous, antialias: bool) -> []u8 {
	mask := make([]u8, w * h)
	if sx < 0 || sy < 0 || sx >= w || sy >= h {
		return mask
	}
	target := pix[sy * w + sx]
	if !contiguous {
		for i in 0 ..< w * h {
			if color_match(pix[i], target, tol) {
				mask[i] = 255
			}
		}
	} else {
		stack := make([dynamic]int, context.temp_allocator)
		append(&stack, sy * w + sx)
		for len(stack) > 0 {
			i := pop(&stack)
			if mask[i] != 0 || !color_match(pix[i], target, tol) {
				continue
			}
			x := i % w
			y := i / w
			l := x
			for l > 0 {
				j := y * w + l - 1
				if mask[j] != 0 || !color_match(pix[j], target, tol) do break
				l -= 1
			}
			r := x
			for r < w - 1 {
				j := y * w + r + 1
				if mask[j] != 0 || !color_match(pix[j], target, tol) do break
				r += 1
			}
			for xx in l ..= r {
				mask[y * w + xx] = 255
			}
			for yy in ([2]int{y - 1, y + 1}) {
				if yy < 0 || yy >= h do continue
				for xx in l ..= r {
					j := yy * w + xx
					if mask[j] == 0 && color_match(pix[j], target, tol) {
						append(&stack, j)
					}
				}
			}
		}
	}
	if antialias {
		// border pixels just outside the region get coverage by colour similarity
		out := make([]u8, w * h)
		copy(out, mask)
		soft := max(tol, 16) * 3
		for y in 0 ..< h {
			for x in 0 ..< w {
				i := y * w + x
				if mask[i] != 0 do continue
				near := (x > 0 && mask[i - 1] != 0) || (x < w - 1 && mask[i + 1] != 0) || (y > 0 && mask[i - w] != 0) || (y < h - 1 && mask[i + w] != 0)
				if !near do continue
				p := pix[i]
				dist := max(abs(int(p.r) - int(target.r)), abs(int(p.g) - int(target.g)), abs(int(p.b) - int(target.b)), abs(int(p.a) - int(target.a)))
				if dist < soft {
					out[i] = u8(255 * (soft - dist) / soft)
				}
			}
		}
		delete(mask)
		return out
	}
	return mask
}

// Combine an existing selection (may be nil = nothing) with a new shape.
sel_combine :: proc(base: []u8, shape: []u8, mode: Sel_Mode) -> []u8 {
	out := make([]u8, len(shape))
	switch mode {
	case .Replace:
		copy(out, shape)
	case .Add:
		for i in 0 ..< len(out) {
			b := base != nil ? base[i] : 0
			out[i] = max(b, shape[i])
		}
	case .Subtract:
		if base != nil {
			for i in 0 ..< len(out) {
				out[i] = u8(int(base[i]) * (255 - int(shape[i])) / 255)
			}
		}
	case .Intersect:
		if base != nil {
			for i in 0 ..< len(out) {
				out[i] = min(base[i], shape[i])
			}
		}
	}
	return out
}

// Install a new selection buffer (takes ownership). Empty masks clear the selection.
doc_sel_set :: proc(d: ^Doc, v: []u8) {
	mask_release(d.sel)
	d.sel = nil
	m := new(Mask)
	m.refs = 1
	m.v = v
	if mask_update_bbox(m, d.w, d.h) {
		d.sel = m
	} else {
		delete(m.v)
		free(m)
	}
	d.sel_dirty = true
}

doc_sel_clear :: proc(d: ^Doc) {
	mask_release(d.sel)
	d.sel = nil
	d.sel_dirty = true
}

doc_sel_all :: proc(d: ^Doc) {
	v := make([]u8, d.w * d.h)
	for &x in v do x = 255
	doc_sel_set(d, v)
}

doc_sel_invert :: proc(d: ^Doc) {
	v := make([]u8, d.w * d.h)
	for &x, i in v {
		x = d.sel == nil ? 255 : 255 - d.sel.v[i]
	}
	doc_sel_set(d, v)
}

// Coverage of pixel i by the selection (255 when nothing is selected).
sel_at :: #force_inline proc(d: ^Doc, i: int) -> u8 {
	if d.sel == nil {
		return 255
	}
	return d.sel.v[i]
}

// Region affected by edits: the selection bounds, or the whole image.
doc_edit_box :: proc(d: ^Doc) -> Box {
	if d.sel != nil {
		return d.sel.bbox
	}
	return doc_box(d)
}

// ---------------------------------------------------------------------------
// Selection modifiers
// ---------------------------------------------------------------------------

// 3-pass box blur of a u8 mask (approximates a gaussian of the given radius).
mask_blur :: proc(v: []u8, w, h: int, radius: f32) {
	if radius <= 0 {
		return
	}
	r := max(int(radius * 0.58 + 0.5), 1) // three box passes ~ gaussian sigma
	tmp := make([]f32, w * h, context.temp_allocator)
	buf := make([]f32, w * h, context.temp_allocator)
	for x, i in v do buf[i] = f32(x)
	for _ in 0 ..< 3 {
		box_pass(buf, tmp, w, h, r, true)
		box_pass(tmp, buf, w, h, r, false)
	}
	for &x, i in v do x = u8(clamp(buf[i], 0, 255) + 0.5)

	box_pass :: proc(src, dst: []f32, w, h, r: int, horiz: bool) {
		n, lines := w, h
		if !horiz do n, lines = h, w
		inv := 1 / f32(2 * r + 1)
		for l in 0 ..< lines {
			at :: #force_inline proc(src: []f32, w, l, i, n: int, horiz: bool) -> f32 {
				ii := clamp(i, 0, n - 1)
				return horiz ? src[l * w + ii] : src[ii * w + l]
			}
			sum: f32
			for i in -r ..= r do sum += at(src, w, l, i, n, horiz)
			for i in 0 ..< n {
				if horiz {
					dst[l * w + i] = sum * inv
				} else {
					dst[i * w + l] = sum * inv
				}
				sum += at(src, w, l, i + r + 1, n, horiz) - at(src, w, l, i - r, n, horiz)
			}
		}
	}
}

// Grow (r > 0) or shrink (r < 0) with a separable square max/min filter.
mask_grow :: proc(v: []u8, w, h: int, r: int) {
	if r == 0 {
		return
	}
	grow := r > 0
	rr := abs(r)
	tmp := make([]u8, w * h, context.temp_allocator)
	// van Herk / Gil-Werman: block prefix and suffix extrema, O(n) for any radius
	pass :: proc(src, dst: []u8, w, h, r: int, horiz, grow: bool) {
		n, lines := w, h
		if !horiz do n, lines = h, w
		k := 2 * r + 1
		m := n + 2 * r
		line := make([]u8, m, context.temp_allocator)
		g := make([]u8, m, context.temp_allocator)
		hh := make([]u8, m, context.temp_allocator)
		pad: u8 = grow ? 0 : 255
		pick :: #force_inline proc(a, b: u8, grow: bool) -> u8 {
			return grow ? max(a, b) : min(a, b)
		}
		for l in 0 ..< lines {
			for i in 0 ..< m {
				j := i - r
				if j < 0 || j >= n {
					line[i] = pad
				} else {
					line[i] = horiz ? src[l * w + j] : src[j * w + l]
				}
			}
			for i in 0 ..< m {
				g[i] = i % k == 0 ? line[i] : pick(g[i - 1], line[i], grow)
			}
			#reverse for _, i in hh {
				hh[i] = (i == m - 1 || (i + 1) % k == 0) ? line[i] : pick(hh[i + 1], line[i], grow)
			}
			for i in 0 ..< n {
				// window [i, i + 2r] in padded coordinates
				v := pick(hh[i], g[i + 2 * r], grow)
				if horiz {
					dst[l * w + i] = v
				} else {
					dst[i * w + l] = v
				}
			}
		}
	}
	pass(v, tmp, w, h, rr, true, grow)
	pass(tmp, v, w, h, rr, false, grow)
}

// Selection from layer transparency.
doc_sel_from_alpha :: proc(d: ^Doc) {
	l := &d.layers[d.active_layer]
	px := layer_flat(d, l)
	v := make([]u8, d.w * d.h)
	for p, i in px do v[i] = p.a
	doc_sel_set(d, v)
}

// ---------------------------------------------------------------------------
// Marching ants: outline of the 50% coverage boundary, merged into runs.
// ---------------------------------------------------------------------------

doc_rebuild_edges :: proc(d: ^Doc) {
	if !d.sel_dirty {
		return
	}
	d.sel_dirty = false
	clear(&d.sel_edges)
	if d.sel == nil {
		return
	}
	w, h := d.w, d.h
	v := d.sel.v
	b := d.sel.bbox
	at :: #force_inline proc(v: []u8, w, h, x, y: int) -> bool {
		if x < 0 || y < 0 || x >= w || y >= h {
			return false
		}
		return v[y * w + x] >= 128
	}
	// horizontal runs
	for y in b.y0 ..= b.y1 {
		run := -1
		for x in b.x0 ..= b.x1 {
			edge := x < b.x1 && at(v, w, h, x, y) != at(v, w, h, x, y - 1)
			if edge && run < 0 {
				run = x
			} else if !edge && run >= 0 {
				append(&d.sel_edges, Sel_Edge{i32(run), i32(y), i32(x - run), false})
				run = -1
			}
		}
	}
	// vertical runs
	for x in b.x0 ..= b.x1 {
		run := -1
		for y in b.y0 ..= b.y1 {
			edge := y < b.y1 && at(v, w, h, x, y) != at(v, w, h, x - 1, y)
			if edge && run < 0 {
				run = y
			} else if !edge && run >= 0 {
				append(&d.sel_edges, Sel_Edge{i32(x), i32(run), i32(y - run), true})
				run = -1
			}
		}
	}
}
