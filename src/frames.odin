package pangolin

import "core:math"

// ---------------------------------------------------------------------------
// Frames. Layer.pix and Layer.mask always hold the current frame's tiles, so brush, filter and
// selection code never needs to know about frames; set_frame swaps them. The other frames' tiles
// wait in Layer.cels:
//   - a nil cel, or a cel past the end of the list, is an empty one: layers made anywhere need no
//     setting up, and the slot of the current frame is always nil
//   - cels are never changed in place, and undo snapshots share them by reference. A snapshot then
//     costs one pointer per cel, not a walk over every tile of every frame
// Text and vector layers span all frames: their cels stay empty and set_frame leaves their tiles
// where they are. A frame with `flat` set does not show the ones made before it (see doc_frame_from_visible);
// text typed on that frame afterwards belongs to it, so it does show.
// ---------------------------------------------------------------------------

FRAME_DEFAULT_MS :: 100

layer_spans :: proc(l: ^Layer) -> bool {
	return l.text.on || l.shape != nil
}

frame_flat_id :: proc(d: ^Doc, f: int) -> int {
	return f >= 0 && f < len(d.frames) ? d.frames[f].flat : 0
}

flat_hides :: proc(flat: int, l: ^Layer) -> bool {
	return flat > 0 && layer_spans(l) && l.span_id < flat
}

// Larger than every span_id and Frame.flat so far: what a new flat frame or text layer takes.
span_next_id :: proc(d: ^Doc) -> int {
	m := 0
	for &l in d.layers do m = max(m, l.span_id)
	for fr in d.frames do m = max(m, fr.flat)
	return m + 1
}

cel_release :: proc(c: ^Cel) {
	if c == nil do return
	c.refs -= 1
	if c.refs <= 0 {
		tiles_destroy(&c.pix)
		tiles_destroy(&c.mask)
		free(c)
	}
}

layer_cels_fit :: proc(l: ^Layer, n: int) {
	if len(l.cels) < n do resize(&l.cels, n)
}

// A cel holding what the layer has now, sharing its tiles; nil if that is nothing.
@(private = "file")
cel_share_current :: proc(l: ^Layer) -> ^Cel {
	if tiles_count(&l.pix) == 0 && (!l.has_mask || tiles_count(&l.mask) == 0) do return nil
	c := new(Cel)
	c.refs = 1
	c.pix = tiles_share(&l.pix)
	if l.has_mask do c.mask = tiles_share(&l.mask)
	return c
}

// Moves the working tiles to frame `nf`, with no history and no redraw: the caller sees to those.
frame_switch :: proc(d: ^Doc, nf: int) {
	of := d.active_frame
	if nf == of do return
	for &l in d.layers {
		if layer_spans(&l) do continue
		layer_cels_fit(&l, max(len(d.frames), of + 1, nf + 1))
		// put the old frame away; an empty cel stays nil, and takes no memory
		if tiles_count(&l.pix) == 0 && (!l.has_mask || tiles_count(&l.mask) == 0) {
			tiles_destroy(&l.pix)
			if l.has_mask do tiles_destroy(&l.mask)
		} else {
			c := new(Cel)
			c.refs = 1
			c.pix = l.pix
			if l.has_mask do c.mask = l.mask
			l.cels[of] = c
		}
		l.pix, l.mask = {}, {}
		// take the new one out: moved if nothing else holds it, shared if a snapshot does
		if c := l.cels[nf]; c != nil {
			if c.refs == 1 {
				l.pix, l.mask = c.pix, c.mask
				free(c)
			} else {
				l.pix = tiles_share(&c.pix)
				if l.has_mask do l.mask = tiles_share(&c.mask)
				c.refs -= 1
			}
			l.cels[nf] = nil
		}
		if len(l.pix.t) == 0 do l.pix = tiles_make(d.w, d.h)
		if l.has_mask && len(l.mask.t) == 0 do l.mask = tiles_make(d.w, d.h)
	}
	d.active_frame = nf
}

// What a layer shows on frame `f`, without moving anything. Nil pointers mean an empty cel.
frame_tiles :: proc(d: ^Doc, l: ^Layer, f: int) -> (pix, mask: ^Tiles) {
	if f == d.active_frame || layer_spans(l) do return &l.pix, &l.mask
	if f < len(l.cels) && l.cels[f] != nil do return &l.cels[f].pix, &l.cels[f].mask
	return nil, nil
}

// Composite of any frame into `out` (a w*h buffer). Reads only: safe for frames other than the current one.
frame_composite :: proc(d: ^Doc, f: int, out: []Color) {
	flat := frame_flat_id(d, f)
	if f == d.active_frame {
		fx_update(d, true) // the current frame's effects, if any are out of date (an export right after a change)
		composite_box_fast(d, d.layers[:], doc_box(d), out, flat)
		return
	}
	tmp := make([]Layer, len(d.layers), context.temp_allocator)
	for &l, i in d.layers {
		tmp[i] = l // shallow: nothing here outlives this call
		pix, mask := frame_tiles(d, &l, f)
		tmp[i].pix = pix != nil ? pix^ : Tiles{}
		tmp[i].mask = mask != nil ? mask^ : Tiles{}
	}
	composite_box_fast(d, fx_apply(d, tmp, f, true), doc_box(d), out, flat) // with this frame's effects
}

// A text or vector layer is about to become ordinary pixels: every frame keeps showing what it
// showed, as its own cel. Each frame can then be painted on separately.
layer_fan_out :: proc(d: ^Doc, l: ^Layer) {
	shared: ^Cel
	for f in 0 ..< len(d.frames) {
		if f == d.active_frame || flat_hides(d.frames[f].flat, l) do continue
		if shared == nil {
			shared = new(Cel)
			shared.pix = tiles_share(&l.pix)
			if l.has_mask do shared.mask = tiles_share(&l.mask)
		}
		layer_cels_fit(l, len(d.frames))
		cel_release(l.cels[f])
		l.cels[f] = shared
		shared.refs += 1
	}
	if flat_hides(frame_flat_id(d, d.active_frame), l) {
		tiles_destroy(&l.pix)
		l.pix = tiles_make(d.w, d.h)
		if l.has_mask {
			tiles_destroy(&l.mask)
			l.mask = tiles_make(d.w, d.h)
		}
	}
}

// Shows frame `f`. The canvas draws it from the frame cache until something needs the composite
// itself, so stepping through the frames of a large painting stays quick.
set_frame :: proc(f: int) {
	d := doc
	nf := clamp(f, 0, len(d.frames) - 1)
	if nf == d.active_frame do return
	tools_commit_pending()
	frame_switch(d, nf)
	d.comp_dirty = doc_box(d)
	d.thumb_dirty = true
	d.comp_lazy = true
	d.frame_t = ui.time
}

@(private = "file")
tags_on_insert :: proc(d: ^Doc, pos: int) {
	for &t in d.tags {
		if t.from >= pos do t.from += 1
		if t.to >= pos do t.to += 1
	}
}

@(private = "file")
tags_on_delete :: proc(d: ^Doc, pos: int) {
	i := 0
	for i < len(d.tags) {
		t := &d.tags[i]
		if t.from > pos do t.from -= 1
		if t.to >= pos do t.to -= 1
		if t.to < t.from || t.to < 0 {
			ordered_remove(&d.tags, i)
			continue
		}
		t.from = max(t.from, 0)
		i += 1
	}
	if play_tag >= len(d.tags) do play_tag = -1
}

// Room for a new frame right after the current one, and moves there.
@(private = "file")
frame_insert_after_current :: proc(d: ^Doc, frame: Frame, cel_of: proc(l: ^Layer) -> ^Cel) {
	pos := d.active_frame + 1
	for &l in d.layers {
		if layer_spans(&l) do continue
		layer_cels_fit(&l, len(d.frames))
		inject_at(&l.cels, pos, cel_of != nil ? cel_of(&l) : nil)
	}
	inject_at(&d.frames, pos, frame)
	tags_on_insert(d, pos)
	frame_switch(d, pos)
}

doc_add_frame :: proc(d: ^Doc, duplicate: bool) {
	history_push(d)
	src := d.frames[d.active_frame]
	if duplicate {
		frame_insert_after_current(d, src, cel_share_current)
	} else {
		frame_insert_after_current(d, Frame{duration = src.duration}, nil)
	}
	doc_touch_all(d)
}

doc_delete_frame :: proc(d: ^Doc) -> bool {
	if len(d.frames) <= 1 do return false
	history_push(d)
	pos := d.active_frame
	next := pos + 1 < len(d.frames) ? pos + 1 : pos - 1
	frame_switch(d, next)
	for &l in d.layers {
		if layer_spans(&l) do continue
		layer_cels_fit(&l, len(d.frames))
		cel_release(l.cels[pos])
		ordered_remove(&l.cels, pos)
	}
	ordered_remove(&d.frames, pos)
	tags_on_delete(d, pos)
	d.active_frame = next > pos ? next - 1 : next
	doc_touch_all(d)
	return true
}

doc_move_frame :: proc(d: ^Doc, dir: int) -> bool {
	a := d.active_frame
	b := a + dir
	if b < 0 || b >= len(d.frames) do return false
	history_push(d)
	for &l in d.layers {
		if layer_spans(&l) do continue
		layer_cels_fit(&l, len(d.frames))
		l.cels[a], l.cels[b] = l.cels[b], l.cels[a]
	}
	d.frames[a], d.frames[b] = d.frames[b], d.frames[a]
	d.active_frame = b
	doc_touch_all(d)
	return true
}

// A new frame after the current one, holding one flattened image of everything visible now. It
// must look the same as the frame it came from, whatever the layers' blend modes or masks: the
// pixels go on a plain layer (Normal, 100%, visible), every other layer's cel stays empty, and
// the frame's flat id keeps the text and vector layers, which span all frames, from drawing on it.
doc_frame_from_visible :: proc(d: ^Doc) {
	history_push(d)
	flat_pix := doc_flat(d, context.temp_allocator)
	frame_insert_after_current(d, Frame{duration = d.frames[d.active_frame].duration, flat = span_next_id(d)}, nil)
	plain :: proc(l: ^Layer) -> bool {
		// any mask is reveal-all on the new frame, so it changes nothing
		return !layer_spans(l) && l.visible && !l.locked && l.opacity == 255 && l.blend == .Normal
	}
	target := -1
	if plain(&d.layers[d.active_layer]) {
		target = d.active_layer
	} else {
		#reverse for &l, i in d.layers {
			if plain(&l) {
				target = i
				break
			}
		}
	}
	if target < 0 {
		append(&d.layers, layer_make("Visible", d.w, d.h))
		target = len(d.layers) - 1
	}
	tiles_from_buf(&d.layers[target].pix, d.w, d.h, flat_pix, {})
	d.active_layer = target
	d.edit_mask = false
	doc_touch_all(d)
}

// Runs `op` once per frame with that frame's tiles in place, then comes back to the frame it started on.
doc_each_frame :: proc(d: ^Doc, data: rawptr, op: proc(d: ^Doc, f: int, data: rawptr)) {
	saved := d.active_frame
	for f in 0 ..< len(d.frames) {
		frame_switch(d, f)
		op(d, f, data)
	}
	frame_switch(d, saved)
}

// ---------------------------------------------------------------------------
// Frame cache. Compositing a 12 MP painting takes far longer than a frame of animation should, so
// composited frames are kept as textures at the size the view needs (the same box-filtered levels
// as the canvas's mips), the least recently used going first when they pass a memory limit. An
// edit drops the frame it touched; anything that can change every frame drops them all.
// ---------------------------------------------------------------------------

FRAME_CACHE_CAP :: 512 * 1024 * 1024 // bytes of texture

@(private = "file")
Frame_Cached :: struct {
	d:        ^Doc,
	frame, k: int,
	tex:      Texture,
	used:     u64,
}

@(private = "file")
frame_cache: [dynamic]Frame_Cached
@(private = "file")
frame_cache_bytes: int
@(private = "file")
frame_cache_tick: u64
@(private = "file")
frame_cache_buf: []Color // composites are made here, to save allocating 48 MB for each

@(private = "file")
level_bytes :: proc(d: ^Doc, k: int) -> int {
	n := 1 << uint(k)
	return ((d.w + n - 1) >> uint(k)) * ((d.h + n - 1) >> uint(k)) * 4
}

// The level of detail for the current view. During playback it also keeps every frame in the
// range inside the memory limit: a loop larger than the cache would recomposite all the time.
frame_cache_level :: proc(d: ^Doc) -> int {
	k := 0
	for k < MAX_MIP && d.zoom * f32(int(1) << uint(k + 1)) <= 1 do k += 1
	if playing {
		lo, hi, _ := play_range()
		for k < MAX_MIP && (hi - lo + 1) * level_bytes(d, k) > FRAME_CACHE_CAP do k += 1
	}
	return k
}

@(private = "file")
frame_cache_remove :: proc(i: int) {
	e := &frame_cache[i]
	frame_cache_bytes -= int(e.tex.w) * int(e.tex.h) * 4
	tex_destroy(&e.tex)
	unordered_remove(&frame_cache, i)
}

// Forgets frame `f` of a document, or every frame if `f` is -1.
frame_cache_drop :: proc(d: ^Doc, f := -1) {
	if !d.fc_used do return
	#reverse for &e, i in frame_cache {
		if e.d == d && (f < 0 || e.frame == f) do frame_cache_remove(i)
	}
	if f < 0 do d.fc_used = false
}

// Box-filtered copy of a w*h image at 1/2^k, weighting colors by alpha.
shrink_level :: proc(src: []Color, w, h, k: int, dst: []Color) {
	n := 1 << uint(k)
	mw, mh := (w + n - 1) >> uint(k), (h + n - 1) >> uint(k)
	for my in 0 ..< mh {
		sy0, sy1 := my << uint(k), min((my + 1) << uint(k), h)
		for mx in 0 ..< mw {
			sx0, sx1 := mx << uint(k), min((mx + 1) << uint(k), w)
			ar, ag, ab, aa: u32
			for sy in sy0 ..< sy1 {
				row := src[sy * w:]
				for sx in sx0 ..< sx1 {
					p := row[sx]
					a := u32(p.a)
					ar += u32(p.r) * a
					ag += u32(p.g) * a
					ab += u32(p.b) * a
					aa += a
				}
			}
			c: Color
			if aa > 0 {
				cnt := u32((sx1 - sx0) * (sy1 - sy0))
				c = {u8(ar / aa), u8(ag / aa), u8(ab / aa), u8(aa / cnt)}
			}
			dst[my * mw + mx] = c
		}
	}
}

// Frame `f` as a texture at level `k`, made now if it is not cached.
frame_cache_tex :: proc(d: ^Doc, f, k: int) -> Texture {
	frame_cache_tick += 1
	for &e in frame_cache {
		if e.d == d && e.frame == f && e.k == k {
			e.used = frame_cache_tick
			return e.tex
		}
	}
	need := level_bytes(d, k)
	for frame_cache_bytes + need > FRAME_CACHE_CAP && len(frame_cache) > 0 {
		oldest := 0
		for &e, i in frame_cache {
			if e.used < frame_cache[oldest].used do oldest = i
		}
		frame_cache_remove(oldest)
	}
	if len(frame_cache_buf) != d.w * d.h {
		delete(frame_cache_buf)
		frame_cache_buf = make([]Color, d.w * d.h)
	}
	frame_composite(d, f, frame_cache_buf)
	n := 1 << uint(k)
	mw, mh := (d.w + n - 1) >> uint(k), (d.h + n - 1) >> uint(k)
	tex: Texture
	if k == 0 {
		tex = tex_from_pixels(frame_cache_buf, mw, mh, .Linear)
	} else {
		small := make([]Color, mw * mh, context.temp_allocator)
		shrink_level(frame_cache_buf, d.w, d.h, k, small)
		tex = tex_from_pixels(small, mw, mh, .Linear)
	}
	append(&frame_cache, Frame_Cached{d, f, k, tex, frame_cache_tick})
	frame_cache_bytes += need
	d.fc_used = true
	return tex
}

// The part of a level's texture that holds the canvas: its last row and column can be partly empty.
frame_cache_src :: proc(d: ^Doc, k: int) -> FRect {
	n := f32(int(1) << uint(k))
	return {0, 0, f32(d.w) / n, f32(d.h) / n}
}

// Draws the current frame from the cache in place of the composite.
frame_cache_draw :: proc(d: ^Doc, dst: FRect) {
	k := frame_cache_level(d)
	t := frame_cache_tex(d, d.active_frame, k)
	z := d.zoom * f32(int(1) << uint(k))
	tex_set_filter(t, z < 2 ? .Linear : .Point)
	draw_tex(t, frame_cache_src(d, k), dst)
}

// ---------------------------------------------------------------------------
// Onion skin: the neighbouring frames over the current one, slightly red before it and blue after.
// Over rather than under: a painting's opaque background would hide them. The tints stay gentle because
// what the frames have in common is covered too, and should not change color.
// ---------------------------------------------------------------------------

onion_on: bool
onion_before := 1
onion_after := 1
onion_alpha := 30 // %

onion_draw :: proc(d: ^Doc, dst: FRect) {
	if !onion_on || playing || len(d.frames) < 2 do return
	k := frame_cache_level(d)
	src := frame_cache_src(d, k)
	layer :: proc(d: ^Doc, f, k: int, src, dst: FRect, tint: Color, distance: int) {
		t := frame_cache_tex(d, f, k)
		a := f32(clamp(onion_alpha, 0, 100)) * 255 / 100 / math.pow(f32(1.6), f32(distance - 1)) // further away, fainter
		c := tint
		c.a = u8(a)
		draw_tex(t, src, dst, c)
	}
	for i := onion_before; i >= 1; i -= 1 {
		if f := d.active_frame - i; f >= 0 do layer(d, f, k, src, dst, Color{255, 215, 215, 255}, i)
	}
	for i := onion_after; i >= 1; i -= 1 {
		if f := d.active_frame + i; f < len(d.frames) do layer(d, f, k, src, dst, Color{215, 225, 255, 255}, i)
	}
}
