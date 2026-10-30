package pangolin

import "core:math"
import "core:slice"

// ---------------------------------------------------------------------------
// Vector layers: filled outlines (made by Layer > Convert Text to Path). The layer's pixels are a
// rendering of the outlines, so moving, transforming or resizing redraws them at full quality.
// Like text, painting or filtering the pixels turns the layer into an ordinary one.
// A Shape is shared between undo snapshots and never modified in place.
// ---------------------------------------------------------------------------

Path_Kind :: enum u8 {
	Move,
	Line,
	Quad, // control point c1
	Cubic, // control points c1, c2
}

Path_Cmd :: struct {
	kind:   Path_Kind,
	p:      Vec2, // end point
	c1, c2: Vec2,
}

// cmds[a:b], filled together in one colour with the non-zero winding rule.
Path_Item :: struct {
	color: Color,
	a, b:  int,
}

Shape :: struct {
	refs:  int,
	cmds:  []Path_Cmd,
	items: []Path_Item,
}

// Takes ownership of the slices.
shape_new :: proc(cmds: []Path_Cmd, items: []Path_Item) -> ^Shape {
	s := new(Shape)
	s.refs = 1
	s.cmds = cmds
	s.items = items
	return s
}

shape_share :: proc(s: ^Shape) -> ^Shape {
	if s != nil do s.refs += 1
	return s
}

shape_release :: proc(s: ^Shape) {
	if s == nil do return
	s.refs -= 1
	if s.refs <= 0 {
		delete(s.cmds)
		delete(s.items)
		free(s)
	}
}

// x' = a*x + b*y + e, y' = c*x + d*y + f
Affine :: struct {
	a, b, c, d, e, f: f32,
}

AFFINE_ID :: Affine{1, 0, 0, 1, 0, 0}

affine_apply :: #force_inline proc(m: Affine, p: Vec2) -> Vec2 {
	return Vec2{m.a * p.x + m.b * p.y + m.e, m.c * p.x + m.d * p.y + m.f}
}

shape_transformed :: proc(s: ^Shape, m: Affine) -> ^Shape {
	cmds := slice.clone(s.cmds)
	for &c in cmds {
		c.p = affine_apply(m, c.p)
		c.c1 = affine_apply(m, c.c1)
		c.c2 = affine_apply(m, c.c2)
	}
	return shape_new(cmds, slice.clone(s.items))
}

// Editing a text or vector layer's pixels directly makes it an ordinary layer.
layer_rasterize :: proc(l: ^Layer) {
	l.text.on = false
	shape_release(l.shape)
	l.shape = nil
}

// Polygon edges of a range of path commands, curves flattened to within `tol` pixels.
@(private = "file")
Edge :: struct {
	x0, y0, x1, y1: f32, // y0 < y1
	dir:            i8,
}

@(private = "file")
shape_edges :: proc(cmds: []Path_Cmd, tol: f32) -> [dynamic]Edge {
	edges := make([dynamic]Edge, context.temp_allocator)
	add :: proc(edges: ^[dynamic]Edge, a, b: Vec2) {
		if a.y == b.y do return
		if a.y < b.y {
			append(edges, Edge{a.x, a.y, b.x, b.y, 1})
		} else {
			append(edges, Edge{b.x, b.y, a.x, a.y, -1})
		}
	}
	start, cur: Vec2
	open := false
	for c in cmds {
		switch c.kind {
		case .Move:
			if open do add(&edges, cur, start)
			start, cur = c.p, c.p
			open = true
		case .Line:
			add(&edges, cur, c.p)
			cur = c.p
		case .Quad:
			dd := vlen(cur - c.c1 * 2 + c.p)
			n := clamp(int(math.ceil(math.sqrt(dd / (8 * tol)))), 1, 256)
			prev := cur
			for i in 1 ..= n {
				t := f32(i) / f32(n)
				u := 1 - t
				q := cur * (u * u) + c.c1 * (2 * u * t) + c.p * (t * t)
				add(&edges, prev, q)
				prev = q
			}
			cur = c.p
		case .Cubic:
			dd := max(vlen(cur - c.c1 * 2 + c.c2), vlen(c.c1 - c.c2 * 2 + c.p))
			n := clamp(int(math.ceil(math.sqrt(dd * 0.75 / tol))), 1, 256)
			prev := cur
			for i in 1 ..= n {
				t := f32(i) / f32(n)
				u := 1 - t
				q := cur * (u * u * u) + c.c1 * (3 * u * u * t) + c.c2 * (3 * u * t * t) + c.p * (t * t * t)
				add(&edges, prev, q)
				prev = q
			}
			cur = c.p
		}
	}
	if open do add(&edges, cur, start)
	return edges
}

@(private = "file")
add_span :: proc(row: []f32, a, b: f32, wgt: f32) {
	n := f32(len(row))
	a, b := clamp(a, 0, n), clamp(b, 0, n)
	if b <= a do return
	ia, ib := int(a), int(b)
	if ia == ib {
		row[ia] += (b - a) * wgt
		return
	}
	row[ia] += (f32(ia + 1) - a) * wgt
	for x in ia + 1 ..< ib do row[x] += wgt
	if ib < len(row) do row[ib] += (b - f32(ib)) * wgt
}

// Anti-aliased coverage (0..1) of the path in the bw x bh box at (ox, oy), non-zero winding.
shape_coverage :: proc(cmds: []Path_Cmd, ox, oy, bw, bh: int, out: []f32) {
	SUB :: 5
	edges := shape_edges(cmds, 0.1)
	slice.sort_by(edges[:], proc(a, b: Edge) -> bool {return a.y0 < b.y0})
	Cross :: struct {
		x:   f32,
		dir: i8,
	}
	active := make([dynamic]int, context.temp_allocator)
	xs := make([dynamic]Cross, context.temp_allocator)
	next := 0
	for y in 0 ..< bh {
		row := out[y * bw:][:bw]
		for s in 0 ..< SUB {
			sy := f32(oy + y) + (f32(s) + 0.5) / SUB
			for next < len(edges) && edges[next].y0 <= sy {
				append(&active, next)
				next += 1
			}
			clear(&xs)
			for i := 0; i < len(active); {
				e := edges[active[i]]
				if e.y1 <= sy {
					unordered_remove(&active, i)
					continue
				}
				if e.y0 <= sy {
					t := (sy - e.y0) / (e.y1 - e.y0)
					append(&xs, Cross{e.x0 + t * (e.x1 - e.x0) - f32(ox), e.dir})
				}
				i += 1
			}
			slice.sort_by(xs[:], proc(a, b: Cross) -> bool {return a.x < b.x})
			wind := 0
			for i in 0 ..< len(xs) - 1 {
				wind += int(xs[i].dir)
				if wind != 0 do add_span(row, xs[i].x, xs[i + 1].x, 1.0 / SUB)
			}
		}
		for &v in row do v = min(v, 1)
	}
}

// Bounding box of the outlines (control points included), in whole pixels.
shape_bounds :: proc(s: ^Shape) -> (b: Box, ok: bool) {
	lo := Vec2{max(f32), max(f32)}
	hi := Vec2{min(f32), min(f32)}
	for c in s.cmds {
		pts := [3]Vec2{c.p, c.c1, c.c2}
		n := c.kind == .Cubic ? 3 : (c.kind == .Quad ? 2 : 1)
		for p in pts[:n] {
			lo = {min(lo.x, p.x), min(lo.y, p.y)}
			hi = {max(hi.x, p.x), max(hi.y, p.y)}
		}
	}
	if len(s.cmds) == 0 do return
	return Box{int(math.floor(lo.x)) - 1, int(math.floor(lo.y)) - 1, int(math.ceil(hi.x)) + 1, int(math.ceil(hi.y)) + 1}, true
}

// Redraws a vector layer's pixels from its outlines.
shape_render_layer :: proc(d: ^Doc, li: int) {
	l := &d.layers[li]
	s := l.shape
	old, _ := tiles_bounds(&l.pix, d.w, d.h, {})
	tiles_destroy(&l.pix)
	l.pix = tiles_make(d.w, d.h)
	if s == nil do return
	bb, ok := shape_bounds(s)
	bb = box_clip(bb, d.w, d.h)
	if !ok || box_empty(bb) {
		doc_touch(d, old)
		return
	}
	bw, bh := bb.x1 - bb.x0, bb.y1 - bb.y0
	cov := make([]f32, bw * bh, context.temp_allocator)
	acc := make([][3]f32, bw * bh, context.temp_allocator)
	item := make([]f32, bw * bh, context.temp_allocator)
	for it in s.items {
		for &v in item do v = 0
		shape_coverage(s.cmds[it.a:it.b], bb.x0, bb.y0, bw, bh, item)
		col := [3]f32{f32(it.color.r), f32(it.color.g), f32(it.color.b)}
		ia := f32(it.color.a) / 255
		for c, i in item {
			if c <= 0 do continue
			a := c * ia
			acc[i] = col * a + acc[i] * (1 - a)
			cov[i] = a + cov[i] * (1 - a)
		}
	}
	for y in 0 ..< bh {
		for x in 0 ..< bw {
			c := cov[y * bw + x]
			if c <= 0 do continue
			a := u8(clamp(c * 255 + 0.5, 0, 255))
			if a == 0 do continue
			v := acc[y * bw + x] / c
			tiles_set(&l.pix, bb.x0 + x, bb.y0 + y, Color{u8(clamp(v.r + 0.5, 0, 255)), u8(clamp(v.g + 0.5, 0, 255)), u8(clamp(v.b + 0.5, 0, 255)), a}, {})
		}
	}
	doc_touch(d, box_union(old, bb))
}

// Layer > Convert Text to Path: the active text layer becomes a vector layer with the same look.
doc_text_to_path :: proc(d: ^Doc) -> bool {
	l := &d.layers[d.active_layer]
	if !l.text.on {
		set_status("Select a text layer first")
		return false
	}
	s := text_to_shape(&l.text)
	if s == nil {
		set_status("No text to convert")
		return false
	}
	history_push(d)
	l.text.on = false
	shape_release(l.shape)
	l.shape = s
	shape_render_layer(d, d.active_layer)
	d.thumb_dirty = true
	set_status("Text converted to a path: it can be moved, transformed and resized without losing detail")
	return true
}

doc_rasterize_layer :: proc(d: ^Doc) -> bool {
	l := &d.layers[d.active_layer]
	if !l.text.on && l.shape == nil do return false
	history_push(d)
	layer_rasterize(l)
	d.thumb_dirty = true
	return true
}

// Project files: commands then items.
write_shape :: proc(w: ^Writer, s: ^Shape) {
	w32(w, u32(len(s.cmds)))
	for c in s.cmds {
		w8(w, u8(c.kind))
		for v in ([6]f32{c.p.x, c.p.y, c.c1.x, c.c1.y, c.c2.x, c.c2.y}) do w32(w, transmute(u32)v)
	}
	w32(w, u32(len(s.items)))
	for it in s.items {
		wcol(w, it.color)
		w32(w, u32(it.a))
		w32(w, u32(it.b))
	}
}

read_shape :: proc(r: ^Reader) -> ^Shape {
	n := int(r32(r))
	if n < 0 || n > (len(r.d) - r.pos) / 25 {
		r.bad = true
		return nil
	}
	cmds := make([]Path_Cmd, n)
	for &c in cmds {
		c.kind = Path_Kind(min(r8(r), u8(len(Path_Kind) - 1)))
		v: [6]f32
		for &x in v do x = transmute(f32)r32(r)
		c.p, c.c1, c.c2 = {v[0], v[1]}, {v[2], v[3]}, {v[4], v[5]}
	}
	ni := int(r32(r))
	if r.bad || ni < 0 || ni > (len(r.d) - r.pos) / 12 {
		delete(cmds)
		r.bad = true
		return nil
	}
	items := make([]Path_Item, ni)
	for &it in items {
		it.color = rcol(r)
		it.a = clamp(int(r32(r)), 0, n)
		it.b = clamp(int(r32(r)), it.a, n)
	}
	return shape_new(cmds, items)
}

// Puts the active vector layer's outlines at `orig` moved by (dx, dy), and redraws it.
shape_move_to :: proc(d: ^Doc, orig: ^Shape, dx, dy: f32) {
	l := &d.layers[d.active_layer]
	ns := shape_transformed(orig, Affine{1, 0, 0, 1, dx, dy})
	shape_release(l.shape)
	l.shape = ns
	shape_render_layer(d, d.active_layer)
}
