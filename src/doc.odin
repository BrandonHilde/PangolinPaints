package pangolin

import "core:fmt"
import "core:math"
import "core:os"
import "core:thread"

MAX_UNDO :: 100

// ---------------------------------------------------------------------------
// Layers
// ---------------------------------------------------------------------------

layer_make :: proc(name: string, w, h: int) -> Layer {
	l: Layer
	name_set(&l.name, name)
	l.visible = true
	l.opacity = 255
	l.pix = tiles_make(w, h)
	return l
}

layer_destroy :: proc(l: ^Layer) {
	tiles_destroy(&l.pix)
	shape_release(l.shape)
	l.shape = nil
	if l.has_mask {
		tiles_destroy(&l.mask)
	}
	for c in l.cels do cel_release(c)
	delete(l.cels)
	l.cels = nil
}

// Copy of a layer sharing all tiles.
layer_share :: proc(l: ^Layer) -> Layer {
	n := l^
	n.pix = tiles_share(&l.pix)
	n.shape = shape_share(l.shape)
	if l.has_mask {
		n.mask = tiles_share(&l.mask)
	}
	n.cels = nil
	if len(l.cels) > 0 {
		n.cels = make([dynamic]^Cel, len(l.cels))
		for c, i in l.cels {
			if c != nil do c.refs += 1
			n.cels[i] = c
		}
	}
	return n
}

// ---------------------------------------------------------------------------
// Selection masks (shared, immutable)
// ---------------------------------------------------------------------------

mask_new :: proc(w, h: int) -> ^Mask {
	m := new(Mask)
	m.refs = 1
	m.v = make([]u8, w * h)
	return m
}

mask_release :: proc(m: ^Mask) {
	if m == nil {
		return
	}
	m.refs -= 1
	if m.refs <= 0 {
		delete(m.v)
		free(m)
	}
}

mask_share :: proc(m: ^Mask) -> ^Mask {
	if m != nil {
		m.refs += 1
	}
	return m
}

// Recompute the bounding box; returns false when nothing is selected.
mask_update_bbox :: proc(m: ^Mask, w, h: int) -> bool {
	b := Box{w, h, 0, 0}
	for y in 0 ..< h {
		row := m.v[y * w:][:w]
		first := -1
		for v, x in row {
			if v != 0 {
				first = x
				break
			}
		}
		if first < 0 {
			continue
		}
		last := first
		#reverse for v, x in row {
			if v != 0 {
				last = x
				break
			}
		}
		b.x0 = min(b.x0, first)
		b.x1 = max(b.x1, last + 1)
		b.y0 = min(b.y0, y)
		b.y1 = max(b.y1, y + 1)
	}
	m.bbox = b
	return !box_empty(b)
}

// ---------------------------------------------------------------------------
// State snapshots / history
// ---------------------------------------------------------------------------

state_clone :: proc(s: ^State) -> State {
	r: State
	r.w, r.h = s.w, s.h
	r.layers = make([dynamic]Layer, 0, len(s.layers))
	for &l in s.layers {
		append(&r.layers, layer_share(&l))
	}
	r.sel = mask_share(s.sel)
	r.frames = make([dynamic]Frame, len(s.frames))
	copy(r.frames[:], s.frames[:])
	r.tags = make([dynamic]Tag, len(s.tags))
	copy(r.tags[:], s.tags[:])
	r.active_frame = s.active_frame
	return r
}

state_destroy :: proc(s: ^State) {
	for &l in s.layers {
		layer_destroy(&l)
	}
	delete(s.layers)
	mask_release(s.sel)
	delete(s.frames)
	delete(s.tags)
	s^ = {}
}

doc_new :: proc(w, h: int, title := "Painting") -> ^Doc {
	d := new(Doc)
	d.w, d.h = w, h
	append(&d.layers, layer_make("Background", w, h))
	layers_give_ids(d)
	append(&d.frames, Frame{duration = FRAME_DEFAULT_MS})
	d.zoom = 1
	name_set(&d.title, title)
	d.comp = make([]Color, w * h)
	doc_dirty_all(d)
	return d
}

doc_destroy :: proc(d: ^Doc) {
	state_destroy(&d.s)
	for &s in d.undo {
		state_destroy(&s)
	}
	for &s in d.redo {
		state_destroy(&s)
	}
	delete(d.undo)
	delete(d.redo)
	delete(d.comp)
	delete(d.sel_edges)
	chan_free(d)
	fx_cache_free(d)
	if d.path != "" {
		delete(d.path)
	}
	free(d)
}

doc_box :: proc(d: ^Doc) -> Box {
	return Box{0, 0, d.w, d.h}
}

// Mark a region as changed (composite + texture + thumbnails).
doc_dirty :: proc(d: ^Doc, b: Box) {
	cb := box_clip(b, d.w, d.h)
	if box_empty(cb) {
		return
	}
	d.comp_dirty = box_union(d.comp_dirty, cb)
	d.thumb_dirty = true
	d.comp_lazy = false
	if len(d.fx_cache) > 0 && len(d.layers) > 0 {
		fx_mark_stale(d, d.layers[clamp(d.active_layer, 0, len(d.layers) - 1)].uid)
		if stroke.active do fx_paint_through(d, cb) // painting shows as it goes down, without running the effects
	}
	if d.fc_used {
		// a text or vector layer shows on every frame
		l := &d.layers[clamp(d.active_layer, 0, len(d.layers) - 1)]
		frame_cache_drop(d, layer_spans(l) ? -1 : d.active_frame)
	}
}

doc_dirty_all :: proc(d: ^Doc) {
	doc_dirty(d, doc_box(d))
	fx_mark_stale(d)
	d.sel_dirty = true
	frame_cache_drop(d)
}

// Call after anything that changed pixels.
doc_touch :: proc(d: ^Doc, b: Box) {
	doc_dirty(d, b)
	d.modified = true
}

doc_touch_all :: proc(d: ^Doc) {
	doc_dirty_all(d)
	d.modified = true
}

doc_clamp :: proc(d: ^Doc) {
	d.active_layer = clamp(d.active_layer, 0, len(d.layers) - 1)
	if !d.layers[d.active_layer].has_mask {
		d.edit_mask = false
	}
	if len(d.comp) != d.w * d.h {
		delete(d.comp)
		d.comp = make([]Color, d.w * d.h)
	}
	doc_dirty_all(d)
}

history_push :: proc(d: ^Doc) {
	stop_playback() // every edit comes through here
	if d.history_hold > 0 {
		d.modified = true
		return
	}
	append(&d.undo, state_clone(&d.s))
	for len(d.undo) > MAX_UNDO {
		state_destroy(&d.undo[0])
		ordered_remove(&d.undo, 0)
	}
	for &s in d.redo {
		state_destroy(&s)
	}
	clear(&d.redo)
	d.modified = true
}

// Drop the most recent undo entry (used when an action turned out to change nothing).
history_discard :: proc(d: ^Doc) {
	if d.history_hold == 0 && len(d.undo) > 0 {
		s := pop(&d.undo)
		state_destroy(&s)
	}
}

// Restore the most recent snapshot without keeping a redo entry (cancelled previews).
history_revert :: proc(d: ^Doc) {
	if d.history_hold > 0 || len(d.undo) == 0 {
		return
	}
	state_destroy(&d.s)
	d.s = pop(&d.undo)
	doc_clamp(d)
}

history_undo :: proc(d: ^Doc) -> bool {
	if len(d.undo) == 0 {
		return false
	}
	append(&d.redo, d.s)
	d.s = pop(&d.undo)
	d.modified = true
	doc_clamp(d)
	return true
}

history_redo :: proc(d: ^Doc) -> bool {
	if len(d.redo) == 0 {
		return false
	}
	append(&d.undo, d.s)
	d.s = pop(&d.redo)
	d.modified = true
	doc_clamp(d)
	return true
}

// The grid that painting tools write to: the active layer, its mask, or one of its color channels
// (painted like a mask: grey values, see channels.odin).
doc_target :: proc(d: ^Doc) -> (g: ^Tiles, empty: Color, is_mask: bool) {
	l := &d.layers[d.active_layer]
	if d.edit_mask && l.has_mask {
		return &l.mask, MASK_EMPTY, true
	}
	if cg, ok := chan_target(d); ok {
		return cg, CHAN_EMPTY, true
	}
	return &l.pix, Color{}, false
}

can_edit :: proc() -> bool {
	l := &doc.layers[doc.active_layer]
	if l.is_group {
		set_status("This is a group: pick a layer in it to change pixels")
		return false
	}
	if l.locked {
		set_status("Layer is locked")
		return false
	}
	if !l.visible {
		set_status("Layer is hidden")
		return false
	}
	layer_rasterize(doc, l) // editing the pixels directly rasterises a text or vector layer
	return true
}

// ---------------------------------------------------------------------------
// Blending (non-premultiplied RGBA, W3C compositing formulas)
// ---------------------------------------------------------------------------

@(private = "file")
lum3 :: #force_inline proc(c: [3]f32) -> f32 {
	return 0.3 * c[0] + 0.59 * c[1] + 0.11 * c[2]
}

@(private = "file")
clip_color :: proc(c: [3]f32) -> [3]f32 {
	l := lum3(c)
	n := min(c[0], c[1], c[2])
	x := max(c[0], c[1], c[2])
	r := c
	if n < 0 {
		for i in 0 ..< 3 do r[i] = l + (r[i] - l) * l / max(l - n, 1e-6)
	}
	if x > 1 {
		for i in 0 ..< 3 do r[i] = l + (r[i] - l) * (1 - l) / max(x - l, 1e-6)
	}
	return r
}

@(private = "file")
set_lum :: proc(c: [3]f32, l: f32) -> [3]f32 {
	d := l - lum3(c)
	return clip_color({c[0] + d, c[1] + d, c[2] + d})
}

@(private = "file")
sat3 :: proc(c: [3]f32) -> f32 {
	return max(c[0], c[1], c[2]) - min(c[0], c[1], c[2])
}

@(private = "file")
set_sat :: proc(c: [3]f32, s: f32) -> [3]f32 {
	mx := max(c[0], c[1], c[2])
	mn := min(c[0], c[1], c[2])
	r: [3]f32
	if mx > mn {
		for i in 0 ..< 3 {
			r[i] = (c[i] - mn) * s / (mx - mn)
		}
	}
	return r
}

blend_channel :: proc(mode: Blend, d, s: f32) -> f32 {
	#partial switch mode {
	case .Normal:
		return s
	case .Multiply:
		return d * s
	case .Screen:
		return d + s - d * s
	case .Overlay:
		return d < 0.5 ? 2 * d * s : 1 - 2 * (1 - d) * (1 - s)
	case .Hard_Light:
		return s < 0.5 ? 2 * d * s : 1 - 2 * (1 - d) * (1 - s)
	case .Soft_Light:
		if s <= 0.5 {
			return d - (1 - 2 * s) * d * (1 - d)
		}
		dd := d <= 0.25 ? ((16 * d - 12) * d + 4) * d : math.sqrt(d)
		return d + (2 * s - 1) * (dd - d)
	case .Darken:
		return min(d, s)
	case .Lighten:
		return max(d, s)
	case .Color_Dodge:
		if d == 0 do return 0
		if s >= 1 do return 1
		return min(1, d / (1 - s))
	case .Color_Burn:
		if d >= 1 do return 1
		if s <= 0 do return 0
		return 1 - min(1, (1 - d) / s)
	case .Add:
		return min(d + s, 1)
	case .Subtract:
		return max(d - s, 0)
	case .Difference:
		return abs(d - s)
	}
	return s
}

blend_rgb :: proc(mode: Blend, d, s: [3]f32) -> [3]f32 {
	#partial switch mode {
	case .Hue:
		return set_lum(set_sat(s, sat3(d)), lum3(d))
	case .Saturation:
		return set_lum(set_sat(d, sat3(s)), lum3(d))
	case .Color:
		return set_lum(s, lum3(d))
	case .Luminosity:
		return set_lum(d, lum3(s))
	}
	return {blend_channel(mode, d[0], s[0]), blend_channel(mode, d[1], s[1]), blend_channel(mode, d[2], s[2])}
}

// Blend src over dst with the given opacity (0..1).
blend_px :: proc(dst, src: Color, opacity: f32, mode: Blend) -> Color {
	if src.a == 0 || opacity <= 0 {
		return dst
	}
	sa := f32(src.a) / 255 * opacity
	if mode == .Erase {
		// only the source's coverage matters: it removes that much of what is below
		return Color{dst.r, dst.g, dst.b, u8(f32(dst.a) * (1 - sa) + 0.5)}
	}
	if dst.a == 0 {
		return Color{src.r, src.g, src.b, u8(sa * 255 + 0.5)}
	}
	if mode == .Normal {
		if sa >= 0.999 {
			return Color{src.r, src.g, src.b, 255}
		}
		return over_px(dst, src, sa)
	}
	da := f32(dst.a) / 255
	ra := sa + da * (1 - sa)
	s := [3]f32{f32(src.r) / 255, f32(src.g) / 255, f32(src.b) / 255}
	dc := [3]f32{f32(dst.r) / 255, f32(dst.g) / 255, f32(dst.b) / 255}
	b := blend_rgb(mode, dc, s)
	out: Color
	for i in 0 ..< 3 {
		c := ((1 - sa) * da * dc[i] + sa * ((1 - da) * s[i] + da * b[i])) / ra
		out[i] = u8(clamp(c, 0, 1) * 255 + 0.5)
	}
	out.a = u8(clamp(ra, 0, 1) * 255 + 0.5)
	return out
}

// Normal "over" with source alpha `sa` (0..1) replacing src.a.
over_px :: #force_inline proc(dst, src: Color, sa: f32) -> Color {
	if sa <= 0 {
		return dst
	}
	da := f32(dst.a) / 255
	ra := sa + da * (1 - sa)
	if ra <= 0 {
		return {}
	}
	k := da * (1 - sa)
	return Color {
		u8((f32(src.r) * sa + f32(dst.r) * k) / ra + 0.5),
		u8((f32(src.g) * sa + f32(dst.g) * k) / ra + 0.5),
		u8((f32(src.b) * sa + f32(dst.b) * k) / ra + 0.5),
		u8(ra * 255 + 0.5),
	}
}

// Linear interpolation of non-premultiplied colours, weighting colour by alpha.
mix_px :: proc(a, b: Color, t: f32) -> Color {
	if t <= 0 do return a
	if t >= 1 do return b
	aa := f32(a.a) * (1 - t)
	ba := f32(b.a) * t
	ra := aa + ba
	if ra <= 0 {
		return Color{}
	}
	return Color {
		u8((f32(a.r) * aa + f32(b.r) * ba) / ra + 0.5),
		u8((f32(a.g) * aa + f32(b.g) * ba) / ra + 0.5),
		u8((f32(a.b) * aa + f32(b.b) * ba) / ra + 0.5),
		u8(ra + 0.5),
	}
}

// ---------------------------------------------------------------------------
// Compositing
// ---------------------------------------------------------------------------

// Composite all visible layers inside box `b` into `out` (full w*h buffer).
// `flat`: the frame's Frame.flat, which can hide text and vector layers. A layer with no tiles (an empty cel) is skipped.
// Which layers are in which group, for compositing a list with groups: `kids[g]` are group g's layers and `top` the
// rest, each bottom first.
Comp_Tree :: struct {
	top:  [dynamic]int,
	kids: [][dynamic]int,
}

comp_tree :: proc(layers: []Layer, allocator := context.temp_allocator) -> Comp_Tree {
	t := Comp_Tree {
		top  = make([dynamic]int, allocator),
		kids = make([][dynamic]int, len(layers), allocator),
	}
	at := make(map[int]int, len(layers), allocator)
	for &l, i in layers do if l.uid != 0 do at[l.uid] = i
	for &l, i in layers {
		p, ok := at[l.parent]
		if l.parent != 0 && ok && layers[p].is_group && p != i {
			if t.kids[p] == nil do t.kids[p] = make([dynamic]int, allocator)
			append(&t.kids[p], i)
		} else {
			append(&t.top, i)
		}
	}
	return t
}

composite_box :: proc(d: ^Doc, layers_in: []Layer, b: Box, out: []Color, flat := 0, tree: ^Comp_Tree = nil, fx_done := false) {
	w := d.w
	layers := fx_done ? layers_in : fx_layers(d, layers_in) // live layer effects
	for y in b.y0 ..< b.y1 {
		for x in b.x0 ..< b.x1 {
			out[y * w + x] = {}
		}
	}
	t := tree
	local: Comp_Tree
	if t == nil && layers_have_groups(layers) {
		local = comp_tree(layers)
		t = &local
	}
	for ty in b.y0 / TILE ..= (b.y1 - 1) / TILE {
		for tx in b.x0 / TILE ..= (b.x1 - 1) / TILE {
			x0, x1 := max(b.x0, tx * TILE), min(b.x1, (tx + 1) * TILE)
			y0, y1 := max(b.y0, ty * TILE), min(b.y1, (ty + 1) * TILE)
			if t == nil {
				for &l in layers do comp_layer_tile(&l, tx, ty, x0, y0, x1, y1, out, w, 0, 0, 1, flat)
			} else {
				comp_items(layers, t, t.top[:], tx, ty, x0, y0, x1, y1, out, w, 0, 0, 1, flat)
			}
		}
	}
}

// Layers `items` (and the groups among them, with their contents) onto `dst`, within one tile. `dst` holds pixel
// (x, y) at (y - oy) * dw + (x - ox); `op_mul` is the opacity of the pass-through groups they are in.
@(private = "file")
comp_items :: proc(layers: []Layer, t: ^Comp_Tree, items: []int, tx, ty, x0, y0, x1, y1: int, dst: []Color, dw, ox, oy: int, op_mul: f32, flat: int) {
	for i in items {
		l := &layers[i]
		if !l.is_group || l.fx_shown {
			// (a group with effects shows their result, in place of its layers)
			comp_layer_tile(l, tx, ty, x0, y0, x1, y1, dst, dw, ox, oy, op_mul, flat)
			continue
		}
		if !l.visible || l.opacity == 0 || len(t.kids[i]) == 0 do continue
		gop := op_mul * f32(l.opacity) / 255
		if l.pass_through {
			comp_items(layers, t, t.kids[i][:], tx, ty, x0, y0, x1, y1, dst, dw, ox, oy, gop, flat)
			continue
		}
		// combined on their own first, then blended by the group's mode and opacity
		buf: [TILE * TILE]Color
		bw := x1 - x0
		comp_items(layers, t, t.kids[i][:], tx, ty, x0, y0, x1, y1, buf[:], bw, x0, y0, 1, flat)
		for y in y0 ..< y1 {
			for x in x0 ..< x1 {
				s := buf[(y - y0) * bw + x - x0]
				if s.a == 0 do continue
				di := (y - oy) * dw + x - ox
				dst[di] = blend_px(dst[di], s, gop, l.blend)
			}
		}
	}
}

// One layer's pixels in tile (tx, ty), within x0..x1, y0..y1, onto `dst` (laid out as for comp_items).
@(private = "file")
comp_layer_tile :: proc(l: ^Layer, tx, ty, x0, y0, x1, y1: int, dst: []Color, dw, ox, oy: int, op_mul: f32, flat: int) {
	if !l.visible || l.opacity == 0 || len(l.pix.t) == 0 || flat_hides(flat, l) {
		return
	}
	ti := ty * l.pix.tw + tx
	t := l.pix.t[ti]
	if t == nil {
		return
	}
	mt: ^Tile = nil
	use_mask := l.has_mask && l.mask_on && len(l.mask.t) > 0
	if use_mask {
		mt = l.mask.t[ti]
	}
	op := f32(l.opacity) / 255 * op_mul
	fast := l.blend == .Normal && l.opacity == 255 && op_mul >= 1 && mt == nil
	for y in y0 ..< y1 {
		trow := (y - ty * TILE) * TILE - tx * TILE
		orow := (y - oy) * dw - ox
		for x in x0 ..< x1 {
			s := t.pix[trow + x]
			if s.a == 0 {
				continue
			}
			if fast {
				if s.a == 255 {
					dst[orow + x] = s
				} else {
					dst[orow + x] = over_px(dst[orow + x], s, f32(s.a) / 255)
				}
				continue
			}
			o := op
			if mt != nil {
				o *= f32(mt.pix[trow + x].r) / 255
			}
			dst[orow + x] = blend_px(dst[orow + x], s, o, l.blend)
		}
	}
}

// composite_box on several threads when the area is large. They only read tiles (no refcounts) and each
// writes its own rows of `out`.
composite_box_fast :: proc(d: ^Doc, layers_in: []Layer, b: Box, out: []Color, flat := 0) {
	Band :: struct {
		d:      ^Doc,
		layers: []Layer,
		b:      Box,
		out:    []Color,
		flat:   int,
		tree:   ^Comp_Tree,
	}
	MAX_BANDS :: 8
	n := clamp(os.get_processor_core_count(), 1, MAX_BANDS)
	if n < 2 || (b.x1 - b.x0) * (b.y1 - b.y0) < 1 << 20 {
		composite_box(d, layers_in, b, out, flat)
		return
	}
	layers := fx_layers(d, layers_in) // once, here: the threads only read
	// the groups are worked out here, once: the threads only read them
	tree: ^Comp_Tree
	local: Comp_Tree
	if layers_have_groups(layers) {
		local = comp_tree(layers)
		tree = &local
	}
	bands: [MAX_BANDS]Band
	threads: [MAX_BANDS]^thread.Thread
	for i in 0 ..< n {
		rows := b.y1 - b.y0
		bands[i] = {d, layers, Box{b.x0, b.y0 + rows * i / n, b.x1, b.y0 + rows * (i + 1) / n}, out, flat, tree}
		if i == 0 do continue // this thread does the first band itself
		t := thread.create(proc(t: ^thread.Thread) {
			band := (^Band)(t.data)
			composite_box(band.d, band.layers, band.b, band.out, band.flat, band.tree, true)
		})
		t.data = &bands[i]
		thread.start(t)
		threads[i] = t
	}
	composite_box(d, layers, bands[0].b, out, flat, tree, true)
	for t in threads[1:n] {
		thread.join(t)
		thread.destroy(t)
	}
}

doc_refresh_comp :: proc(d: ^Doc) {
	if len(d.comp) != d.w * d.h {
		delete(d.comp)
		d.comp = make([]Color, d.w * d.h)
		d.comp_dirty = doc_box(d)
	}
	d.comp_lazy = false
	chan_sync(d) // a channel painted since: into its layer first
	b := box_clip(d.comp_dirty, d.w, d.h)
	if box_empty(b) {
		return
	}
	if chan_showing_raw(d) {
		chan_fill_raw(d, b, d.comp)
	} else {
		composite_box_fast(d, d.layers[:], b, d.comp, frame_flat_id(d, d.active_frame))
	}
	d.comp_dirty = {}
	d.tex_dirty = box_union(d.tex_dirty, b)
}

// Full composite into a new buffer (export, copy merged, sample merged).
doc_flat :: proc(d: ^Doc, allocator := context.allocator) -> []Color {
	out := make([]Color, d.w * d.h, allocator)
	composite_box(d, d.layers[:], doc_box(d), out, frame_flat_id(d, d.active_frame))
	return out
}

// Flattened pixels of one layer (mask applied) as a w*h buffer.
layer_flat :: proc(d: ^Doc, l: ^Layer, allocator := context.temp_allocator) -> []Color {
	out := make([]Color, d.w * d.h, allocator)
	if l.is_group {
		// a group: what it shows, its contents combined by its opacity and mode
		for &x, k in d.layers {
			if &x != l do continue
			s := layer_span_start(d.layers[:], k)
			composite_box(d, d.layers[s:k + 1], doc_box(d), out, frame_flat_id(d, d.active_frame))
			break
		}
		return out
	}
	tiles_to_buf(&l.pix, d.w, d.h, out, {})
	return out
}

// Layer pixels with its mask multiplied into alpha (for merging).
layer_masked :: proc(d: ^Doc, l: ^Layer, allocator := context.temp_allocator) -> []Color {
	out := layer_flat(d, l, allocator)
	if l.has_mask && l.mask_on {
		m := make([]Color, d.w * d.h, context.temp_allocator)
		tiles_to_buf(&l.mask, d.w, d.h, m, MASK_EMPTY)
		for &p, i in out {
			p.a = u8(int(p.a) * int(m[i].r) / 255)
		}
	}
	return out
}

// ---------------------------------------------------------------------------
// Layer commands
// ---------------------------------------------------------------------------

doc_add_layer :: proc(d: ^Doc) {
	history_push(d)
	l := layer_make(fmt.tprintf("Layer %d", len(d.layers)), d.w, d.h)
	layer_insert_above(d, l, d.active_layer)
	d.edit_mask = false
	doc_touch_all(d)
}

// Insert a layer built from a w*h buffer above the active one.
doc_add_layer_from :: proc(d: ^Doc, name: string, pix: []Color) {
	history_push(d)
	l := layer_make(name, d.w, d.h)
	tiles_from_buf(&l.pix, d.w, d.h, pix, {})
	layer_insert_above(d, l, d.active_layer)
	d.edit_mask = false
	doc_touch_all(d)
}

// Deletes the active layer; a group goes with everything in it. False if no layer would be left.
doc_delete_layer :: proc(d: ^Doc) -> bool {
	g := d.active_layer
	s := layer_span_start(d.layers[:], g)
	if g - s + 1 >= len(d.layers) {
		return false
	}
	history_push(d)
	layers_remove_run(d, s, g)
	d.edit_mask = false
	doc_touch_all(d)
	return true
}

// Copies the active layer (a group with everything in it) just above it.
doc_dup_layer :: proc(d: ^Doc) {
	history_push(d)
	doc_dup_run(d)
	doc_touch_all(d)
}

doc_merge_down :: proc(d: ^Doc) -> bool {
	i := d.active_layer
	if d.layers[i].is_group do return doc_merge_group(d)
	if layer_merge_target(d) != i - 1 {
		return false
	}
	history_push(d)
	// both become plain per-frame pixels first
	layer_rasterize(d, &d.layers[i])
	layer_rasterize(d, &d.layers[i - 1])
	doc_each_frame(d, &i, proc(d: ^Doc, f: int, data: rawptr) {
		i := (^int)(data)^
		up := &d.layers[i]
		lo := &d.layers[i - 1]
		if tiles_count(&up.pix) == 0 && !(lo.has_mask && lo.mask_on) do return
		op := f32(up.opacity) / 255
		src := layer_masked(d, up)
		dst := layer_masked(d, lo)
		for p in 0 ..< len(dst) {
			dst[p] = blend_px(dst[p], src[p], op, up.blend)
		}
		tiles_from_buf(&lo.pix, d.w, d.h, dst, {})
	})
	lo := &d.layers[i - 1]
	if lo.has_mask do layer_mask_remove(lo) // it is in the pixels now, on every frame
	layer_destroy(&d.layers[i])
	ordered_remove(&d.layers, i)
	d.active_layer = i - 1
	d.edit_mask = false
	doc_touch_all(d)
	return true
}

doc_flatten :: proc(d: ^Doc) -> bool {
	if len(d.layers) <= 1 && !d.layers[0].has_mask && !layer_spans(&d.layers[0]) && len(d.frames) <= 1 {
		return false
	}
	history_push(d)
	buf := make([]Color, d.w * d.h)
	defer delete(buf)
	nl := layer_make("Background", d.w, d.h)
	layer_cels_fit(&nl, len(d.frames))
	for f in 0 ..< len(d.frames) {
		frame_composite(d, f, buf)
		if f == d.active_frame {
			tiles_from_buf(&nl.pix, d.w, d.h, buf, {})
			continue
		}
		g := tiles_make(d.w, d.h)
		tiles_from_buf(&g, d.w, d.h, buf, {})
		if tiles_count(&g) == 0 {
			tiles_destroy(&g)
			continue
		}
		c := new(Cel)
		c.refs = 1
		c.pix = g
		nl.cels[f] = c
	}
	for &l in d.layers {
		layer_destroy(&l)
	}
	clear(&d.layers)
	append(&d.layers, nl)
	for &fr in d.frames do fr.flat = 0
	d.active_layer = 0
	d.edit_mask = false
	doc_touch_all(d)
	return true
}

// Add a white (reveal-all) mask, or one built from the selection.
doc_add_mask :: proc(d: ^Doc, from_sel: bool) -> bool {
	l := &d.layers[d.active_layer]
	if l.has_mask {
		return false
	}
	history_push(d)
	l.mask = tiles_make(d.w, d.h)
	l.has_mask = true
	l.mask_on = true
	if from_sel && d.sel != nil {
		buf := make([]Color, d.w * d.h, context.temp_allocator)
		for v, i in d.sel.v {
			buf[i] = Color{v, v, v, 255}
		}
		tiles_from_buf(&l.mask, d.w, d.h, buf, MASK_EMPTY)
		// the same mask on every frame
		if !layer_spans(l) && len(d.frames) > 1 {
			m := Mask_Share{d.active_layer, tiles_share(&l.mask)}
			defer tiles_destroy(&m.tiles)
			doc_each_frame(d, &m, proc(d: ^Doc, f: int, data: rawptr) {
				m := (^Mask_Share)(data)
				l := &d.layers[m.layer]
				tiles_destroy(&l.mask)
				l.mask = tiles_share(&m.tiles)
			})
		}
	}
	d.edit_mask = true
	doc_touch_all(d)
	return true
}

@(private = "file")
Mask_Share :: struct {
	layer: int,
	tiles: Tiles,
}

doc_delete_mask :: proc(d: ^Doc, apply: bool) -> bool {
	l := &d.layers[d.active_layer]
	if !l.has_mask {
		return false
	}
	history_push(d)
	if apply {
		layer_rasterize(d, l)
		li := d.active_layer
		doc_each_frame(d, &li, proc(d: ^Doc, f: int, data: rawptr) {
			l := &d.layers[(^int)(data)^]
			on := l.mask_on
			l.mask_on = true
			px := layer_masked(d, l)
			l.mask_on = on
			tiles_from_buf(&l.pix, d.w, d.h, px, {})
		})
	}
	layer_mask_remove(l)
	d.edit_mask = false
	doc_touch_all(d)
	return true
}

// Removes a layer's mask on every frame. A cel a snapshot also holds is replaced, not changed.
@(private = "file")
layer_mask_remove :: proc(l: ^Layer) {
	tiles_destroy(&l.mask)
	l.has_mask = false
	l.mask_on = false
	for &c in l.cels {
		if c == nil || len(c.mask.t) == 0 do continue
		n := new(Cel)
		n.refs = 1
		n.pix = tiles_share(&c.pix)
		cel_release(c)
		c = n
	}
}

// ---------------------------------------------------------------------------
// Image-wide transforms. Every layer and mask is processed as a flat buffer.
// ---------------------------------------------------------------------------

// Apply `f` to every pixel grid in the document, producing new nw x nh grids.
// Vector layers instead have their outlines moved by `m` (old canvas -> new) and are redrawn.
@(private = "file")
doc_remap :: proc(d: ^Doc, nw, nh: int, f: proc(src: []Color, sw, sh: int, dst: []Color, dw, dh: int, ctx: rawptr, empty: Color), ctx: rawptr, m: Affine) {
	src := make([]Color, d.w * d.h)
	defer delete(src)
	dst := make([]Color, nw * nh)
	defer delete(dst)
	// text becomes pixels; vector layers keep their outlines, moved once
	for &l in d.layers {
		if l.text.on {
			layer_rasterize(d, &l)
		}
		if l.shape != nil {
			ns := shape_transformed(l.shape, m)
			shape_release(l.shape)
			l.shape = ns
		}
	}
	saved := d.active_frame
	for fi in 0 ..< len(d.frames) {
		frame_switch(d, fi) // (an empty cel comes back at the old size)
		for &l in d.layers {
			if layer_spans(&l) && fi > 0 do continue // their tiles are not per frame
			if tiles_count(&l.pix) > 0 {
				tiles_to_buf(&l.pix, d.w, d.h, src, {})
				f(src, d.w, d.h, dst, nw, nh, ctx, {})
				tiles_destroy(&l.pix)
				l.pix = tiles_make(nw, nh)
				tiles_from_buf(&l.pix, nw, nh, dst, {})
			} else {
				tiles_destroy(&l.pix)
				l.pix = tiles_make(nw, nh)
			}
			if l.has_mask {
				if tiles_count(&l.mask) > 0 {
					tiles_to_buf(&l.mask, d.w, d.h, src, MASK_EMPTY)
					f(src, d.w, d.h, dst, nw, nh, ctx, MASK_EMPTY)
					tiles_destroy(&l.mask)
					l.mask = tiles_make(nw, nh)
					tiles_from_buf(&l.mask, nw, nh, dst, MASK_EMPTY)
				} else {
					tiles_destroy(&l.mask)
					l.mask = tiles_make(nw, nh)
				}
			}
		}
	}
	mask_release(d.sel)
	d.sel = nil
	d.w, d.h = nw, nh
	frame_switch(d, saved) // every cel has the new size now
	for &l, i in d.layers {
		if l.shape != nil do shape_render_layer(d, i)
	}
	doc_clamp(d)
	d.view_init = false
	d.modified = true
}

Resize_Ctx :: struct {
	ox, oy: int,
	fill:   Color, // used for the bottom layer's new area
	filter: Resample,
}

// Resize canvas; old content is placed at (ox, oy) in the new canvas.
doc_canvas_size :: proc(d: ^Doc, nw, nh, ox, oy: int) {
	history_push(d)
	ctx := Resize_Ctx{ox = ox, oy = oy}
	doc_remap(d, nw, nh, proc(src: []Color, sw, sh: int, dst: []Color, dw, dh: int, ctx: rawptr, empty: Color) {
		c := (^Resize_Ctx)(ctx)
		for &p in dst do p = empty
		for y in 0 ..< sh {
			ny := y + c.oy
			if ny < 0 || ny >= dh do continue
			for x in 0 ..< sw {
				nx := x + c.ox
				if nx < 0 || nx >= dw do continue
				dst[ny * dw + nx] = src[y * sw + x]
			}
		}
	}, &ctx, Affine{1, 0, 0, 1, f32(ox), f32(oy)})
}

Resample :: enum {
	Bicubic,
	Bilinear,
	Nearest,
}

RESAMPLE_NAMES := [Resample]string {
	.Bicubic  = "Bicubic (smooth)",
	.Bilinear = "Bilinear",
	.Nearest  = "Nearest neighbour",
}

// Short names for macro files.
RESAMPLE_KEYS := [Resample]string {
	.Bicubic  = "bicubic",
	.Bilinear = "bilinear",
	.Nearest  = "nearest",
}

doc_image_size :: proc(d: ^Doc, nw, nh: int, filter: Resample) {
	history_push(d)
	ctx := Resize_Ctx{filter = filter}
	doc_remap(d, nw, nh, proc(src: []Color, sw, sh: int, dst: []Color, dw, dh: int, ctx: rawptr, empty: Color) {
		c := (^Resize_Ctx)(ctx)
		resample(src, sw, sh, dst, dw, dh, c.filter)
	}, &ctx, Affine{f32(nw) / f32(d.w), 0, 0, f32(nh) / f32(d.h), 0, 0})
}

// quarter: 1 = 90 CW, 2 = 180, 3 = 90 CCW
doc_rotate :: proc(d: ^Doc, quarter: int) {
	history_push(d)
	nw, nh := d.w, d.h
	if quarter % 2 == 1 {
		nw, nh = d.h, d.w
	}
	q := quarter
	sw, sh := f32(d.w), f32(d.h)
	m: Affine
	switch q {
	case 1:
		m = {0, -1, 1, 0, sh, 0}
	case 2:
		m = {-1, 0, 0, -1, sw, sh}
	case:
		m = {0, 1, -1, 0, 0, sw}
	}
	doc_remap(d, nw, nh, proc(src: []Color, sw, sh: int, dst: []Color, dw, dh: int, ctx: rawptr, empty: Color) {
		q := (^int)(ctx)^
		for y in 0 ..< sh {
			for x in 0 ..< sw {
				nx, ny: int
				switch q {
				case 1:
					nx, ny = sh - 1 - y, x
				case 2:
					nx, ny = sw - 1 - x, sh - 1 - y
				case:
					nx, ny = y, sw - 1 - x
				}
				dst[ny * dw + nx] = src[y * sw + x]
			}
		}
	}, &q, m)
}

doc_flip :: proc(d: ^Doc, horiz: bool) {
	history_push(d)
	h := horiz
	m := horiz ? Affine{-1, 0, 0, 1, f32(d.w), 0} : Affine{1, 0, 0, -1, 0, f32(d.h)}
	doc_remap(d, d.w, d.h, proc(src: []Color, sw, sh: int, dst: []Color, dw, dh: int, ctx: rawptr, empty: Color) {
		horiz := (^bool)(ctx)^
		for y in 0 ..< sh {
			for x in 0 ..< sw {
				if horiz {
					dst[y * dw + (sw - 1 - x)] = src[y * sw + x]
				} else {
					dst[(sh - 1 - y) * dw + x] = src[y * sw + x]
				}
			}
		}
	}, &h, m)
}

Rotate_Ctx :: struct {
	angle: f32,
	ox, oy: f32,
}

// Rotate by an arbitrary angle (degrees, clockwise), enlarging the canvas to fit.
doc_rotate_any :: proc(d: ^Doc, deg: f32) {
	a := deg * math.PI / 180
	ca, sa := math.cos(a), math.sin(a)
	fw, fh := f32(d.w), f32(d.h)
	nw := int(math.ceil(abs(fw * ca) + abs(fh * sa) - 0.01))
	nh := int(math.ceil(abs(fw * sa) + abs(fh * ca) - 0.01))
	nw, nh = clamp(nw, 1, 16384), clamp(nh, 1, 16384)
	history_push(d)
	ctx := Rotate_Ctx{a, 0, 0}
	// forward rotation about the centres: the inverse of the sampling below
	scx, scy := fw / 2, fh / 2
	dcx, dcy := f32(nw) / 2, f32(nh) / 2
	m := Affine{ca, -sa, sa, ca, dcx - ca * scx + sa * scy, dcy - sa * scx - ca * scy}
	doc_remap(d, nw, nh, proc(src: []Color, sw, sh: int, dst: []Color, dw, dh: int, ctx: rawptr, empty: Color) {
		c := (^Rotate_Ctx)(ctx)
		ca, sa := math.cos(c.angle), math.sin(c.angle)
		scx, scy := f32(sw) / 2, f32(sh) / 2
		dcx, dcy := f32(dw) / 2, f32(dh) / 2
		for y in 0 ..< dh {
			for x in 0 ..< dw {
				dx := f32(x) + 0.5 - dcx
				dy := f32(y) + 0.5 - dcy
				// inverse rotation
				sx := dx * ca + dy * sa + scx
				sy := -dx * sa + dy * ca + scy
				dst[y * dw + x] = sample_bilinear(src, sw, sh, sx - 0.5, sy - 0.5, empty)
			}
		}
	}, &ctx, m)
}

doc_crop :: proc(d: ^Doc, b: Box) -> bool {
	cb := box_clip(b, d.w, d.h)
	if box_empty(cb) || (cb.x0 == 0 && cb.y0 == 0 && cb.x1 == d.w && cb.y1 == d.h) {
		return false
	}
	doc_canvas_size(d, cb.x1 - cb.x0, cb.y1 - cb.y0, -cb.x0, -cb.y0)
	return true
}

// Bounding box of visible content across all layers.
doc_content_bounds :: proc(d: ^Doc) -> (b: Box, ok: bool) {
	for &l in d.layers {
		if lb, lok := tiles_bounds(&l.pix, d.w, d.h, {}); lok {
			b = box_union(b, lb)
			ok = true
		}
		for c in l.cels {
			if c == nil do continue
			if lb, lok := tiles_bounds(&c.pix, d.w, d.h, {}); lok {
				b = box_union(b, lb)
				ok = true
			}
		}
	}
	return
}

// ---------------------------------------------------------------------------
// Resampling
// ---------------------------------------------------------------------------

// Bilinear sample at continuous pixel coordinates (pixel centres at integers).
sample_bilinear :: proc(src: []Color, w, h: int, x, y: f32, empty: Color) -> Color {
	if x < -1 || y < -1 || x > f32(w) || y > f32(h) {
		return empty
	}
	x0 := int(math.floor(x))
	y0 := int(math.floor(y))
	fx := x - f32(x0)
	fy := y - f32(y0)
	get :: #force_inline proc(src: []Color, w, h, x, y: int, empty: Color) -> Color {
		if x < 0 || y < 0 || x >= w || y >= h {
			return empty
		}
		return src[y * w + x]
	}
	acc: [4]f32
	ws := [4]f32{(1 - fx) * (1 - fy), fx * (1 - fy), (1 - fx) * fy, fx * fy}
	ps := [4]Color{get(src, w, h, x0, y0, empty), get(src, w, h, x0 + 1, y0, empty), get(src, w, h, x0, y0 + 1, empty), get(src, w, h, x0 + 1, y0 + 1, empty)}
	for p, i in ps {
		a := f32(p.a) * ws[i]
		acc[0] += f32(p.r) * a
		acc[1] += f32(p.g) * a
		acc[2] += f32(p.b) * a
		acc[3] += a
	}
	if acc[3] <= 0.001 {
		return Color{}
	}
	return Color{u8(clamp(acc[0] / acc[3], 0, 255) + 0.5), u8(clamp(acc[1] / acc[3], 0, 255) + 0.5), u8(clamp(acc[2] / acc[3], 0, 255) + 0.5), u8(clamp(acc[3], 0, 255) + 0.5)}
}

@(private = "file")
cubic_w :: proc(x: f32) -> f32 {
	// Catmull-Rom (a = -0.5)
	ax := abs(x)
	if ax < 1 {
		return 1.5 * ax * ax * ax - 2.5 * ax * ax + 1
	}
	if ax < 2 {
		return -0.5 * ax * ax * ax + 2.5 * ax * ax - 4 * ax + 2
	}
	return 0
}

// Separable resize. Downscaling area-averages (box filter scaled to the ratio) so
// photos shrink without aliasing; upscaling uses the chosen kernel.
resample :: proc(src: []Color, sw, sh: int, dst: []Color, dw, dh: int, filter: Resample) {
	if filter == .Nearest {
		for y in 0 ..< dh {
			sy := min(y * sh / dh, sh - 1)
			for x in 0 ..< dw {
				dst[y * dw + x] = src[sy * sw + min(x * sw / dw, sw - 1)]
			}
		}
		return
	}
	// horizontal pass into premultiplied floats, then vertical
	tmp := make([][4]f32, dw * sh)
	defer delete(tmp)
	Tap :: struct {
		i: int,
		w: f32,
	}
	taps_for :: proc(n_src, n_dst: int, filter: Resample) -> (taps: [][]Tap) {
		taps = make([][]Tap, n_dst, context.temp_allocator)
		scale := f32(n_src) / f32(n_dst)
		support: f32 = filter == .Bicubic ? 2 : 1
		fs := max(scale, 1)
		for o in 0 ..< n_dst {
			c := (f32(o) + 0.5) * scale - 0.5
			lo := int(math.floor(c - support * fs))
			hi := int(math.ceil(c + support * fs))
			list := make([dynamic]Tap, context.temp_allocator)
			sum: f32
			for i in lo ..= hi {
				t := (f32(i) - c) / fs
				wv: f32
				if filter == .Bicubic {
					wv = cubic_w(t)
				} else {
					wv = max(1 - abs(t), 0)
				}
				if wv == 0 do continue
				append(&list, Tap{clamp(i, 0, n_src - 1), wv})
				sum += wv
			}
			if sum != 0 {
				for &tp in list do tp.w /= sum
			}
			taps[o] = list[:]
		}
		return
	}
	hx := taps_for(sw, dw, filter)
	vy := taps_for(sh, dh, filter)
	for y in 0 ..< sh {
		for x in 0 ..< dw {
			acc: [4]f32
			for tp in hx[x] {
				p := src[y * sw + tp.i]
				a := f32(p.a)
				acc += [4]f32{f32(p.r) * a, f32(p.g) * a, f32(p.b) * a, a} * tp.w
			}
			tmp[y * dw + x] = acc
		}
	}
	for y in 0 ..< dh {
		for x in 0 ..< dw {
			acc: [4]f32
			for tp in vy[y] {
				acc += tmp[tp.i * dw + x] * tp.w
			}
			a := clamp(acc[3], 0, 255)
			if a < 0.5 {
				dst[y * dw + x] = {}
				continue
			}
			dst[y * dw + x] = Color{u8(clamp(acc[0] / acc[3], 0, 255) + 0.5), u8(clamp(acc[1] / acc[3], 0, 255) + 0.5), u8(clamp(acc[2] / acc[3], 0, 255) + 0.5), u8(a + 0.5)}
		}
	}
}

// ---------------------------------------------------------------------------
// Colour helpers
// ---------------------------------------------------------------------------

color_hex :: proc(c: Color) -> string {
	return fmt.tprintf("%02X%02X%02X", c.r, c.g, c.b)
}

// Returns false if the string is not valid hex (RGB or RRGGBB, optional #).
parse_hex :: proc(s: string) -> (c: Color, ok: bool) {
	t := s
	if len(t) > 0 && t[0] == '#' {
		t = t[1:]
	}
	hexv :: proc(ch: u8) -> (v: u8, ok: bool) {
		switch ch {
		case '0' ..= '9':
			return ch - '0', true
		case 'a' ..= 'f':
			return ch - 'a' + 10, true
		case 'A' ..= 'F':
			return ch - 'A' + 10, true
		}
		return 0, false
	}
	vals: [6]u8
	n := len(t)
	if n != 3 && n != 6 {
		return
	}
	for i in 0 ..< n {
		v, vok := hexv(t[i])
		if !vok {
			return
		}
		vals[i] = v
	}
	if n == 3 {
		c = Color{vals[0] * 17, vals[1] * 17, vals[2] * 17, 255}
	} else {
		c = Color{vals[0] << 4 | vals[1], vals[2] << 4 | vals[3], vals[4] << 4 | vals[5], 255}
	}
	ok = true
	return
}

clamp_u8 :: proc(v: f32) -> u8 {
	return u8(clamp(v, 0, 255) + 0.5)
}

hexc :: proc(v: u32) -> Color {
	return Color{u8(v >> 16), u8(v >> 8), u8(v), 255}
}

luma :: proc(c: Color) -> u8 {
	return u8((int(c.r) * 2126 + int(c.g) * 7152 + int(c.b) * 722) / 10000)
}

rgb_to_hsv :: proc(c: Color) -> (h, s, v: f32) {
	r, g, b := f32(c.r) / 255, f32(c.g) / 255, f32(c.b) / 255
	mx := max(r, max(g, b))
	mn := min(r, min(g, b))
	d := mx - mn
	v = mx
	s = mx == 0 ? 0 : d / mx
	if d == 0 {
		h = 0
	} else if mx == r {
		h = math.mod((g - b) / d, 6)
	} else if mx == g {
		h = (b - r) / d + 2
	} else {
		h = (r - g) / d + 4
	}
	h *= 60
	if h < 0 {
		h += 360
	}
	return
}

hsv_to_rgb :: proc(h, s, v: f32, a: u8 = 255) -> Color {
	hh := math.mod(h, 360)
	if hh < 0 {
		hh += 360
	}
	c := v * s
	x := c * (1 - abs(math.mod(hh / 60, 2) - 1))
	m := v - c
	r, g, b: f32
	switch int(hh / 60) {
	case 0:
		r, g, b = c, x, 0
	case 1:
		r, g, b = x, c, 0
	case 2:
		r, g, b = 0, c, x
	case 3:
		r, g, b = 0, x, c
	case 4:
		r, g, b = x, 0, c
	case:
		r, g, b = c, 0, x
	}
	return Color{u8((r + m) * 255 + 0.5), u8((g + m) * 255 + 0.5), u8((b + m) * 255 + 0.5), a}
}
