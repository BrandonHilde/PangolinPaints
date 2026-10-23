package pangolin

// ---------------------------------------------------------------------------
// Tile grids (see types.odin). `empty` is the colour a nil tile stands for:
// transparent for layer pixels, white for layer masks.
// ---------------------------------------------------------------------------

MASK_EMPTY :: Color{255, 255, 255, 255}

tile_new :: proc(fill: Color) -> ^Tile {
	t := new(Tile)
	t.refs = 1
	if fill != {} {
		for &p in t.pix {
			p = fill
		}
	}
	return t
}

tile_release :: proc(t: ^Tile) {
	if t == nil {
		return
	}
	t.refs -= 1
	if t.refs <= 0 {
		free(t)
	}
}

tiles_make :: proc(w, h: int) -> Tiles {
	tw := (w + TILE - 1) / TILE
	th := (h + TILE - 1) / TILE
	return Tiles{tw, th, make([]^Tile, tw * th)}
}

tiles_destroy :: proc(g: ^Tiles) {
	for t in g.t {
		tile_release(t)
	}
	delete(g.t)
	g^ = {}
}

// A new grid sharing every tile with `g` (for undo snapshots).
tiles_share :: proc(g: ^Tiles) -> Tiles {
	r := Tiles{g.tw, g.th, make([]^Tile, len(g.t))}
	for t, i in g.t {
		if t != nil {
			t.refs += 1
		}
		r.t[i] = t
	}
	return r
}

// Replace the contents of `dst` with tiles shared from `src` (same dimensions).
tiles_assign :: proc(dst, src: ^Tiles) {
	for t, i in src.t {
		if t != nil {
			t.refs += 1
		}
		tile_release(dst.t[i])
		dst.t[i] = t
	}
}

tiles_get :: #force_inline proc(g: ^Tiles, x, y: int, empty: Color) -> Color {
	t := g.t[(y / TILE) * g.tw + x / TILE]
	if t == nil {
		return empty
	}
	return t.pix[(y % TILE) * TILE + x % TILE]
}

// Returns a tile that may be written, creating or un-sharing it first.
tiles_write :: proc(g: ^Tiles, tx, ty: int, empty: Color) -> ^Tile {
	i := ty * g.tw + tx
	t := g.t[i]
	if t == nil {
		t = tile_new(empty)
		g.t[i] = t
	} else if t.refs > 1 {
		n := new(Tile)
		n.refs = 1
		n.pix = t.pix
		t.refs -= 1
		g.t[i] = n
		t = n
	}
	return t
}

tiles_set :: proc(g: ^Tiles, x, y: int, c, empty: Color) {
	t := tiles_write(g, x / TILE, y / TILE, empty)
	t.pix[(y % TILE) * TILE + x % TILE] = c
}

// Copy a region of the grid into `out` (row-major, box width).
tiles_read_box :: proc(g: ^Tiles, b: Box, out: []Color, empty: Color) {
	bw := b.x1 - b.x0
	for y in b.y0 ..< b.y1 {
		row := out[(y - b.y0) * bw:]
		ty := y / TILE
		x := b.x0
		for x < b.x1 {
			tx := x / TILE
			end := min((tx + 1) * TILE, b.x1)
			t := g.t[ty * g.tw + tx]
			if t == nil {
				for xx in x ..< end {
					row[xx - b.x0] = empty
				}
			} else {
				base := (y % TILE) * TILE
				copy(row[x - b.x0:end - b.x0], t.pix[base + x % TILE:base + x % TILE + (end - x)])
			}
			x = end
		}
	}
}

// Write a region from `src` (row-major, box width). Tiles that end up entirely `empty`
// are dropped so documents stay sparse.
tiles_write_box :: proc(g: ^Tiles, b: Box, src: []Color, empty: Color) {
	bw := b.x1 - b.x0
	for ty in b.y0 / TILE ..= (b.y1 - 1) / TILE {
		for tx in b.x0 / TILE ..= (b.x1 - 1) / TILE {
			x0, x1 := max(b.x0, tx * TILE), min(b.x1, (tx + 1) * TILE)
			y0, y1 := max(b.y0, ty * TILE), min(b.y1, (ty + 1) * TILE)
			if x1 <= x0 || y1 <= y0 {
				continue
			}
			// skip writing all-empty data into an empty tile
			cur := g.t[ty * g.tw + tx]
			if cur == nil {
				all_empty := true
				scan: for y in y0 ..< y1 {
					for x in x0 ..< x1 {
						if src[(y - b.y0) * bw + x - b.x0] != empty {
							all_empty = false
							break scan
						}
					}
				}
				if all_empty {
					continue
				}
			}
			t := tiles_write(g, tx, ty, empty)
			for y in y0 ..< y1 {
				copy(t.pix[(y % TILE) * TILE + x0 % TILE:][:x1 - x0], src[(y - b.y0) * bw + x0 - b.x0:][:x1 - x0])
			}
		}
	}
	tiles_compact_box(g, b, empty)
}

tiles_to_buf :: proc(g: ^Tiles, w, h: int, out: []Color, empty: Color) {
	tiles_read_box(g, Box{0, 0, w, h}, out, empty)
}

tiles_from_buf :: proc(g: ^Tiles, w, h: int, src: []Color, empty: Color) {
	tiles_write_box(g, Box{0, 0, w, h}, src, empty)
}

tile_is_empty :: proc(t: ^Tile, empty: Color) -> bool {
	for p in t.pix {
		if p != empty {
			// transparent pixels with leftover colour still count as empty
			if empty.a == 0 && p.a == 0 {
				continue
			}
			return false
		}
	}
	return true
}

// Release tiles inside the box that hold nothing but `empty`.
tiles_compact_box :: proc(g: ^Tiles, b: Box, empty: Color) {
	if box_empty(b) {
		return
	}
	for ty in max(b.y0, 0) / TILE ..= min((b.y1 - 1) / TILE, g.th - 1) {
		for tx in max(b.x0, 0) / TILE ..= min((b.x1 - 1) / TILE, g.tw - 1) {
			i := ty * g.tw + tx
			if t := g.t[i]; t != nil && tile_is_empty(t, empty) {
				tile_release(t)
				g.t[i] = nil
			}
		}
	}
}

// Bounding box of pixels that differ from `empty` (alpha > 0 for layers).
tiles_bounds :: proc(g: ^Tiles, w, h: int, empty: Color) -> (b: Box, ok: bool) {
	b = Box{w, h, 0, 0}
	for ty in 0 ..< g.th {
		for tx in 0 ..< g.tw {
			t := g.t[ty * g.tw + tx]
			if t == nil {
				continue
			}
			for yy in 0 ..< TILE {
				y := ty * TILE + yy
				if y >= h do break
				for xx in 0 ..< TILE {
					x := tx * TILE + xx
					if x >= w do break
					p := t.pix[yy * TILE + xx]
					used := empty.a == 0 ? p.a != 0 : p != empty
					if used {
						b.x0 = min(b.x0, x)
						b.y0 = min(b.y0, y)
						b.x1 = max(b.x1, x + 1)
						b.y1 = max(b.y1, y + 1)
					}
				}
			}
		}
	}
	ok = !box_empty(b)
	return
}

tiles_count :: proc(g: ^Tiles) -> int {
	n := 0
	for t in g.t {
		if t != nil do n += 1
	}
	return n
}

// Fill the whole grid with one colour.
tiles_fill :: proc(g: ^Tiles, c, empty: Color) {
	for &t in g.t {
		tile_release(t)
		t = nil
		if c != empty && !(empty.a == 0 && c.a == 0) {
			t = tile_new(c)
		}
	}
}
