package pangolin

import "core:fmt"

import oui "odinui:odinui"

// ---------------------------------------------------------------------------
// Color channels. Right-click a layer > Expose Color Channels lists its red, green, blue and alpha channels
// under the layers; click one to paint on it.
//
// The channel being painted is a grey grid (`Doc.chan_grid`, the value in .r like a layer mask), so every tool
// that can paint a mask can paint a channel: doc_target hands it out with is_mask set. chan_sync keeps it and
// the layer in step a tile at a time. Both grids are shadowed by shared references (`chan_shadow`,
// `chan_pix_shadow`): a tile that is written is un-shared first (tiles_write), so a tile whose pointer no
// longer matches its shadow is one that changed. A changed channel tile goes into the layer; a changed layer
// tile (undo, a frame switch, a command that works on every layer) is read back into the channel.
//
// Raw view (`Doc.chan_raw`) shows the channel being painted in grey on the canvas; Image view shows the
// picture as usual.
// ---------------------------------------------------------------------------

CHAN_EMPTY :: Color{0, 0, 0, 255} // a nil channel tile: the 0 a transparent pixel has in every channel
CHANNEL_NAMES := [4]string{"Red", "Green", "Blue", "Alpha"}
CHANNEL_COLORS := [4]Color{{236, 96, 86, 255}, {108, 196, 116, 255}, {96, 150, 236, 255}, {200, 200, 200, 255}}

chan_exposed :: proc(d: ^Doc, uid: int) -> bool {
	for u in d.chan_exposed do if u == uid do return true
	return false
}

// Lists or hides the active layer's channels.
chan_toggle_expose :: proc(d: ^Doc) {
	l := &d.layers[d.active_layer]
	if l.is_group {
		set_status("A group has no pixels of its own: pick a layer in it")
		return
	}
	layers_give_ids(d)
	for u, i in d.chan_exposed {
		if u == l.uid {
			ordered_remove(&d.chan_exposed, i)
			if d.chan_uid == u do chan_end(d)
			set_statusf("%s's color channels are hidden", name_str(&l.name))
			return
		}
	}
	append(&d.chan_exposed, l.uid)
	d.thumb_dirty = true
	set_statusf("%s's color channels are listed under the layers: click one to paint on it", name_str(&l.name))
}

// Paint on channel c (0..3 = red, green, blue, alpha) of layer li.
chan_select :: proc(d: ^Doc, li, c: int) {
	if d.active_layer != li do tools_commit_pending()
	d.active_layer = li
	d.edit_mask = false
	l := &d.layers[li]
	if d.chan_uid != l.uid || d.edit_chan != c + 1 do chan_drop(d)
	d.chan_uid = l.uid
	d.edit_chan = c + 1
	chan_sync(d)
	if d.chan_raw do d.comp_dirty = doc_box(d)
	set_statusf("Painting on the %s channel of %s", CHANNEL_NAMES[c], name_str(&l.name))
}

// Back to painting the layer itself.
chan_end :: proc(d: ^Doc) {
	was := d.edit_chan != 0
	d.edit_chan = 0
	d.chan_uid = 0
	chan_drop(d)
	if was && d.chan_raw do d.comp_dirty = doc_box(d)
}

chan_set_raw :: proc(d: ^Doc, raw: bool) {
	if d.chan_raw == raw do return
	d.chan_raw = raw
	d.comp_dirty = doc_box(d)
	d.tex_dirty = doc_box(d)
}

// The channel grid, when a channel is being painted (with the layer's latest pixels in it).
chan_target :: proc(d: ^Doc) -> (^Tiles, bool) {
	if d.edit_chan == 0 do return nil, false
	chan_sync(d)
	if d.chan_c == 0 do return nil, false
	return &d.chan_grid, true
}

// The canvas shows the channel in grey.
chan_showing_raw :: proc(d: ^Doc) -> bool {
	return d.chan_raw && d.edit_chan != 0 && d.chan_c != 0
}

@(private = "file")
chan_drop :: proc(d: ^Doc) {
	tiles_destroy(&d.chan_grid)
	tiles_destroy(&d.chan_shadow)
	tiles_destroy(&d.chan_pix_shadow)
	d.chan_c = 0
}

// Frees what a document's channels hold (on closing it).
chan_free :: proc(d: ^Doc) {
	chan_drop(d)
	delete(d.chan_exposed)
	d.chan_exposed = nil
}

@(private = "file")
share_into :: proc(g: ^Tiles, i: int, t: ^Tile) {
	if t != nil do t.refs += 1
	tile_release(g.t[i])
	g.t[i] = t
}

@(private = "file")
tile_box :: proc(g: ^Tiles, i: int) -> Box {
	tx, ty := i % g.tw, i / g.tw
	return Box{tx * TILE, ty * TILE, (tx + 1) * TILE, (ty + 1) * TILE}
}

// Channel c of a layer tile, as a grey tile (nil for a nil layer tile: all 0).
@(private = "file")
chan_tile_from :: proc(p: ^Tile, c: int) -> ^Tile {
	if p == nil do return nil
	t := new(Tile)
	t.refs = 1
	for px, k in p.pix {
		v := px[c]
		t.pix[k] = Color{v, v, v, 255}
	}
	return t
}

// Brings the channel grid and the layer into step. Called before each composite and whenever a tool asks
// for its target.
chan_sync :: proc(d: ^Doc) {
	if d.edit_chan == 0 do return
	if len(d.layers) == 0 || d.edit_mask {
		chan_end(d)
		return
	}
	l := &d.layers[clamp(d.active_layer, 0, len(d.layers) - 1)]
	// another layer was picked, or this one can't be painted any more
	if l.uid != d.chan_uid || l.is_group || !chan_exposed(d, l.uid) {
		chan_end(d)
		return
	}
	c := d.edit_chan - 1
	n := len(l.pix.t)
	if d.chan_c != d.edit_chan || len(d.chan_grid.t) != n || d.chan_grid.tw != l.pix.tw {
		// (re)build: the channel just picked, or the image changed size
		chan_drop(d)
		d.chan_grid = Tiles{l.pix.tw, l.pix.th, make([]^Tile, n)}
		d.chan_shadow = Tiles{l.pix.tw, l.pix.th, make([]^Tile, n)}
		d.chan_pix_shadow = Tiles{l.pix.tw, l.pix.th, make([]^Tile, n)}
		for i in 0 ..< n {
			d.chan_grid.t[i] = chan_tile_from(l.pix.t[i], c)
			share_into(&d.chan_shadow, i, d.chan_grid.t[i])
			share_into(&d.chan_pix_shadow, i, l.pix.t[i])
		}
		d.chan_c = d.edit_chan
		if d.chan_raw do d.comp_dirty = doc_box(d)
		return
	}
	raw := d.chan_raw
	for i in 0 ..< n {
		p := l.pix.t[i]
		g := d.chan_grid.t[i]
		if p != d.chan_pix_shadow.t[i] {
			// the layer changed some other way: read the channel from it again
			nt := chan_tile_from(p, c)
			tile_release(g)
			d.chan_grid.t[i] = nt
			share_into(&d.chan_shadow, i, nt)
			share_into(&d.chan_pix_shadow, i, p)
			if raw do d.comp_dirty = box_union(d.comp_dirty, box_clip(tile_box(&l.pix, i), d.w, d.h))
		} else if g != d.chan_shadow.t[i] {
			// painted: put the channel's values into the layer
			if g == nil && p == nil {
				share_into(&d.chan_shadow, i, nil)
				continue
			}
			tx, ty := i % l.pix.tw, i / l.pix.tw
			pt := tiles_write(&l.pix, tx, ty, Color{})
			if g == nil {
				for &px in pt.pix do px[c] = 0
			} else {
				for &px, k in pt.pix do px[c] = g.pix[k].r
			}
			share_into(&d.chan_shadow, i, g)
			share_into(&d.chan_pix_shadow, i, pt)
			b := box_clip(tile_box(&l.pix, i), d.w, d.h)
			d.comp_dirty = box_union(d.comp_dirty, b)
			d.thumb_dirty = true
			d.modified = true
		}
	}
}

// Raw view: the channel being painted, in grey, in place of the composite.
chan_fill_raw :: proc(d: ^Doc, b: Box, out: []Color) {
	for y in b.y0 ..< b.y1 {
		for x in b.x0 ..< b.x1 {
			out[y * d.w + x] = tiles_get(&d.chan_grid, x, y, CHAN_EMPTY)
		}
	}
}

// What the status bar and target label call the channel being painted.
chan_label :: proc(d: ^Doc) -> string {
	if d.edit_chan == 0 do return ""
	return fmt.tprintf("%s channel", CHANNEL_NAMES[d.edit_chan - 1])
}

// ---------------------------------------------------------------------------
// The Channels section under the layers
// ---------------------------------------------------------------------------

CHAN_HEAD_H :: 18 // a layer's name above its channels
CHAN_ROW_H :: 28
CHAN_LIST_MAX_H :: CHAN_HEAD_H + 4 * CHAN_ROW_H + 8 // taller lists scroll

@(private = "file")
chan_thumbs: map[int]Thumb // uid * 4 + channel
@(private = "file")
chan_thumbs_t := -1.0
@(private = "file")
chan_thumbs_doc: ^Doc
@(private = "file")
chan_list_scroll: i32

panel_channels :: proc(d: ^Doc) {
	if len(d.chan_exposed) == 0 do return
	// layers that went away take their entries with them
	for i := len(d.chan_exposed) - 1; i >= 0; i -= 1 {
		li := layer_find_uid(d.layers[:], d.chan_exposed[i])
		if li < 0 || d.layers[li].is_group do ordered_remove(&d.chan_exposed, i)
	}
	if len(d.chan_exposed) == 0 do return
	osection("chan-head", "Channels", "The color channels of the layers you exposed (right-click a layer > Expose Color Channels). Click one to paint on it alone.")
	oui.element(uictx, "chan-view", "row", {id = "chan-view"})
	otext("t", "View", "dim", {"Channel view", cmd_help(.Channels_Raw)})
	oui.element_leaf(uictx, "spacer", "spacer")
	if obutton("Raw", 0, {"Raw", "Show the channel you are painting in grey: white is 255, black 0."}, true, d.chan_raw, key = "raw") {
		if !d.chan_raw do run_cmd(.Channels_Raw)
	}
	if obutton("Image", 0, {"Image", "Show the picture as usual while you paint a channel."}, true, !d.chan_raw, key = "image") {
		if d.chan_raw do run_cmd(.Channels_Raw)
	}
	oui.end(uictx)
	h := i32(len(d.chan_exposed)) * (CHAN_HEAD_H + 4 * CHAN_ROW_H) + 2
	oui_slot("chan-list", "chan_list", style = fmt.tprintf("height:%dpx", min(h, CHAN_LIST_MAX_H)))
}

@(private = "file")
chan_thumbs_refresh :: proc(d: ^Doc) {
	if thumbs_t == chan_thumbs_t && chan_thumbs_doc == d {
		// only the newly exposed are missing
		missing := false
		for u in d.chan_exposed do if (u * 4) not_in chan_thumbs do missing = true
		if !missing do return
	}
	chan_thumbs_t = thumbs_t
	chan_thumbs_doc = d
	buf: [THUMB_W * THUMB_H]Color
	sc := min(f32(THUMB_W) / f32(d.w), f32(THUMB_H) / f32(d.h))
	tw, th := f32(d.w) * sc, f32(d.h) * sc
	ox, oy := (f32(THUMB_W) - tw) / 2, (f32(THUMB_H) - th) / 2
	for u in d.chan_exposed {
		li := layer_find_uid(d.layers[:], u)
		if li < 0 do continue
		l := &d.layers[li]
		for c in 0 ..< 4 {
			for ty in 0 ..< THUMB_H {
				for tx in 0 ..< THUMB_W {
					fx := (f32(tx) + 0.5 - ox) / sc
					fy := (f32(ty) + 0.5 - oy) / sc
					px := Color{}
					if fx >= 0 && fy >= 0 && fx < f32(d.w) && fy < f32(d.h) {
						acc: f32
						for s in 0 ..< 4 {
							sx := clamp(int(fx + (f32(s % 2) - 0.5) / sc * 0.5), 0, d.w - 1)
							sy := clamp(int(fy + (f32(s / 2) - 0.5) / sc * 0.5), 0, d.h - 1)
							acc += f32(tiles_get(&l.pix, sx, sy, Color{})[c])
						}
						v := u8(acc / 4)
						px = Color{v, v, v, 255}
					}
					buf[ty * THUMB_W + tx] = px
				}
			}
			key := u * 4 + c
			t, ok := chan_thumbs[key]
			if !ok {
				t = Thumb{tex = tex_create(THUMB_W, THUMB_H, .Linear)}
				chan_thumbs[key] = t
			}
			tex_update(t.tex, buf[:])
		}
	}
}

panel_chan_list :: proc(list: Rect) {
	d := doc
	ctl_well(list)
	chan_thumbs_refresh(d)
	inner := rect_inset(list, 1)
	content := i32(len(d.chan_exposed)) * (CHAN_HEAD_H + 4 * CHAN_ROW_H)
	in_list := ui_hover(list)
	if in_list && content > inner.h do side_list_wheel = true
	if in_list && ui.wheel != 0 do chan_list_scroll -= i32(ui.wheel) * CHAN_ROW_H
	chan_list_scroll = clamp(chan_list_scroll, 0, max(content - inner.h, 0))
	clip_begin(inner)
	defer clip_end()
	y := inner.y - chan_list_scroll
	hide := -1
	for u, k in d.chan_exposed {
		li := layer_find_uid(d.layers[:], u)
		if li < 0 do continue
		l := &d.layers[li]
		// the layer's name, and a button to hide its channels again
		head := Rect{inner.x, y, inner.w, CHAN_HEAD_H}
		text_clipped(Rect{head.x + 6, y + 4, head.w - 28, 10}, name_str(&l.name), C_TEXT_DIM)
		xr := Rect{head.x + head.w - 16, y + 3, 12, 12}
		hot := in_list && ui_hover(rect_inset(xr, -2))
		icon(.Close, xr.x, xr.y, hot ? C_TEXT : C_TEXT_OFF)
		if in_list do tip_area(rect_inset(xr, -2), "chan-hide", {"Hide channels", "Take this layer's channels out of the list. The layer keeps its pixels."})
		if hot && ui.pressed[0] do hide = k
		y += CHAN_HEAD_H
		for c in 0 ..< 4 {
			row := Rect{inner.x, y, inner.w, CHAN_ROW_H}
			active := d.active_layer == li && d.edit_chan == c + 1 && !d.edit_mask
			if active {
				fill_rect(row, C_ACCENT_TINT)
				fill_rect(Rect{row.x, row.y, 2, row.h}, C_ACCENT)
			} else if in_list && ui_hover(row) {
				fill_rect(row, Color{255, 255, 255, 12})
			}
			hline(row.x, y + CHAN_ROW_H - 1, row.w, C_RING)
			dot := Rect{row.x + 8, y + (CHAN_ROW_H - 6) / 2, 6, 6}
			fill_rect(dot, CHANNEL_COLORS[c])
			th := Rect{row.x + 22, y + (CHAN_ROW_H - THUMB_H) / 2, THUMB_W, THUMB_H}
			fill_rect(th, BLACK)
			if t, ok := chan_thumbs[u * 4 + c]; ok do draw_tex_at(t.tex, th.x, th.y)
			outline_rect(rect_inset(th, -1), active ? C_ACCENT : C_RING_HI)
			text_clipped(Rect{th.x + THUMB_W + 8, y + (CHAN_ROW_H - 10) / 2, row.x + row.w - th.x - THUMB_W - 12, 10}, CHANNEL_NAMES[c], active ? C_TEXT : C_TEXT_DIM)
			if in_list {
				tip_area(row, "chan-row", {fmt.tprintf("%s channel", CHANNEL_NAMES[c]), c == 3 ? "Click to paint on this layer's transparency alone: white is solid, black is clear. The eraser makes pixels clear. Click the layer itself to paint on all of it again." : fmt.tprintf("Click to paint on this layer's %s alone: brushes put the brightness of their color into it. Click the layer itself to paint on all of it again.", CHANNEL_NAMES[c])})
				if ui_hover(row) && ui.pressed[0] && hide < 0 do chan_select(d, li, c)
			}
			y += CHAN_ROW_H
		}
	}
	if hide >= 0 {
		u := d.chan_exposed[hide]
		ordered_remove(&d.chan_exposed, hide)
		if d.chan_uid == u do chan_end(d)
	}
}
