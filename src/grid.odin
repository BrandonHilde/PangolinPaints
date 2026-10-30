package pangolin

import "core:math"

// ---------------------------------------------------------------------------
// Grid: an overlay of grid_w x grid_h cells anchored at the canvas origin, optionally rotated by
// grid_angle about the canvas centre (at 0 the lines fall on multiples of the cell size). While it is shown and
// snapping is on, the pointer position every tool sees is pulled to the nearest grid
// intersection (or canvas edge), so strokes, shapes, selections, moves and text all land on it.
// ---------------------------------------------------------------------------

show_grid := false
snap_grid := true
grid_w := 64
grid_h := 64
grid_opacity := 35 // %
grid_angle := 0 // degrees, -90..90

grid_snapping :: proc() -> bool {
	return show_grid && snap_grid
}

// View tools and the eyedropper keep the raw pointer. Snapping only applies once a tool is
// pressed: hovering (and hit-testing handles) always uses the real pointer position.
tool_snaps :: proc(t: Tool) -> bool {
	#partial switch t {
	case .Hand, .Zoom, .Picker, .Text:
		// text clicks hit-test existing text; a new block's position is snapped in text_click
		return false
	}
	return true
}

@(private = "file")
snap_axis :: proc(v: f32, cell: int, size: int) -> f32 {
	// seamless mode repeats the canvas, so snap within the copy the point falls on
	n := f32(size)
	base: f32 = 0
	if seamless_mode {
		base = math.floor(v / n) * n
	}
	l := v - base
	g := f32(max(cell, 1))
	s := math.round(l / g) * g
	// the canvas edges count as grid lines too, when the size isn't a multiple of the cell
	if abs(l - n) < abs(l - s) {
		s = n
	}
	return base + s
}

snap_pt :: proc(p: Vec2) -> Vec2 {
	if !grid_snapping() {
		return p
	}
	if grid_angle == 0 {
		return Vec2{snap_axis(p.x, grid_w, doc.w), snap_axis(p.y, grid_h, doc.h)}
	}
	// rotated: snap in the grid's own frame
	c, ca, sa := grid_frame(doc)
	v := p - c
	u := Vec2{v.x * ca + v.y * sa, -v.x * sa + v.y * ca} + c
	gw, gh := f32(max(grid_w, 1)), f32(max(grid_h, 1))
	u = Vec2{math.round(u.x / gw) * gw, math.round(u.y / gh) * gh} - c
	return c + Vec2{u.x * ca - u.y * sa, u.x * sa + u.y * ca}
}

// Centre and rotation of the grid.
grid_frame :: proc(d: ^Doc) -> (c: Vec2, ca, sa: f32) {
	a := f32(grid_angle) * math.PI / 180
	return Vec2{f32(d.w) / 2, f32(d.h) / 2}, math.cos(a), math.sin(a)
}

// Grid lines over the canvas (and its seamless copies); hidden once cells get too small to read.
render_grid :: proc(d: ^Doc, vp: Rect) {
	if !show_grid {
		return
	}
	z := d.zoom
	if f32(grid_w) * z < 4 || f32(grid_h) * z < 4 {
		return
	}
	gc := Color{140, 150, 170, u8(clamp(grid_opacity, 0, 100) * 255 / 100)}
	cw, ch := f32(d.w) * z, f32(d.h) * z
	span := seamless_mode ? 1 : 0
	for ty in -span ..= span {
		for tx in -span ..= span {
			ox, oy := d.ox + f32(tx) * cw, d.oy + f32(ty) * ch
			x0, y0 := max(ox, f32(vp.x)), max(oy, f32(vp.y))
			x1, y1 := min(ox + cw, f32(vp.x + vp.w)), min(oy + ch, f32(vp.y + vp.h))
			if x1 <= x0 || y1 <= y0 do continue
			if grid_angle != 0 {
				render_grid_rotated(d, Vec2{f32(tx * d.w), f32(ty * d.h)}, Rect{i32(x0), i32(y0), i32(x1 - x0) + 1, i32(y1 - y0) + 1}, gc)
				continue
			}
			for i := max(int((x0 - ox) / (f32(grid_w) * z)), 1); ; i += 1 {
				x := ox + f32(i * grid_w) * z
				if x >= x1 || i * grid_w >= d.w do break
				vline(i32(x), i32(y0), i32(y1 - y0), gc)
			}
			for i := max(int((y0 - oy) / (f32(grid_h) * z)), 1); ; i += 1 {
				y := oy + f32(i * grid_h) * z
				if y >= y1 || i * grid_h >= d.h do break
				hline(i32(x0), i32(y), i32(x1 - x0), gc)
			}
		}
	}
}

// One canvas copy's rotated grid lines (copy offset `off` in canvas pixels), clipped to `clip`.
@(private = "file")
render_grid_rotated :: proc(d: ^Doc, off: Vec2, clip: Rect, gc: Color) {
	c, ca, sa := grid_frame(d)
	to_grid :: proc(p, c: Vec2, ca, sa: f32) -> Vec2 {
		v := p - c
		return Vec2{v.x * ca + v.y * sa, -v.x * sa + v.y * ca} + c
	}
	// the canvas corners in grid space bound the lines needed
	lo := Vec2{max(f32), max(f32)}
	hi := Vec2{min(f32), min(f32)}
	for q in ([4]Vec2{{0, 0}, {f32(d.w), 0}, {0, f32(d.h)}, {f32(d.w), f32(d.h)}}) {
		u := to_grid(q, c, ca, sa)
		lo = {min(lo.x, u.x), min(lo.y, u.y)}
		hi = {max(hi.x, u.x), max(hi.y, u.y)}
	}
	gw, gh := f32(max(grid_w, 1)), f32(max(grid_h, 1))
	clip_begin(clip)
	defer clip_end()
	line :: proc(a, b, off: Vec2, c: Vec2, ca, sa: f32, gc: Color) {
		from_grid :: proc(u, c: Vec2, ca, sa: f32) -> Vec2 {
			v := u - c
			return c + Vec2{v.x * ca - v.y * sa, v.x * sa + v.y * ca}
		}
		pa := canvas_to_screen(from_grid(a, c, ca, sa) + off)
		pb := canvas_to_screen(from_grid(b, c, ca, sa) + off)
		draw_line(pa, pb, gc)
	}
	for k := math.ceil(lo.x / gw); k * gw <= hi.x; k += 1 {
		line({k * gw, lo.y}, {k * gw, hi.y}, off, c, ca, sa, gc)
	}
	for k := math.ceil(lo.y / gh); k * gh <= hi.y; k += 1 {
		line({lo.x, k * gh}, {hi.x, k * gh}, off, c, ca, sa, gc)
	}
}

// Small cross on the snapped point, so it is clear where a click will land.
render_snap_marker :: proc(p: Vec2) {
	sp := canvas_to_screen(p)
	sp = {math.floor(sp.x) + 0.5, math.floor(sp.y) + 0.5}
	draw_line(sp - {5, 0}, sp + {6, 0}, Color{0, 0, 0, 180})
	draw_line(sp - {0, 5}, sp + {0, 6}, Color{0, 0, 0, 180})
	draw_line(sp - {4, -1}, sp + {5, 1}, C_ACCENT)
	draw_line(sp - {-1, 4}, sp + {1, 5}, C_ACCENT)
}

dlg_grid :: proc() {
	c := dialog_frame("Grid", 280, 170)
	y := c.y
	row_int(c, y, "Cell width (px)", &dialog.a, 1, 4096)
	y += 20
	row_int(c, y, "Cell height (px)", &dialog.b, 1, 4096)
	y += 22
	row_slider(c, y, "Line opacity", &dialog.c, 5, 100, "%")
	y += 20
	row_slider(c, y, "Angle", &dialog.d, -90, 90, "deg")
	y += 20
	checkbox(c.x, y, "Show grid", &dialog.flag)
	checkbox(c.x + 110, y, "Snap to grid", &dialog.flag2, "Every tool snaps to the grid while it is shown")
	ok, cancel := dialog_buttons(c)
	if cancel {
		dialog_close()
	}
	if ok {
		grid_w, grid_h, grid_opacity, grid_angle = dialog.a, dialog.b, dialog.c, dialog.d
		show_grid, snap_grid = dialog.flag, dialog.flag2
		dialog_close()
	}
}
