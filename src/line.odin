package pangolin

import "core:math"

// ---------------------------------------------------------------------------
// Line / polygon tool. Drag for a single line; or click to place points one by one, then
// double click, right click or Enter to finish, or click the first point to close the shape.
// Shift keeps each segment at 15 degree steps, Backspace removes the last point, Esc cancels.
// The outline is painted with the tool's own brush settings; closed shapes can also be filled.
// ---------------------------------------------------------------------------

Line_Tool :: struct {
	pts:     [dynamic]Vec2, // placed points; empty when no line is in progress
	started: bool, // the current press placed the first point
}

line_tool: Line_Tool
line_outline := true
line_fill := false

LINE_CLOSE_PX :: 8 // screen distance from the first point that closes the shape

line_active :: proc() -> bool {
	return len(line_tool.pts) > 0
}

// Shift: the segment from the previous point snaps to 15 degree steps.
line_constrain :: proc(p: Vec2) -> Vec2 {
	n := len(line_tool.pts)
	if !ui.shift || n == 0 {
		return p
	}
	a := line_tool.pts[n - 1]
	v := p - a
	step := f32(math.PI / 12)
	ang := math.round(math.atan2(v.y, v.x) / step) * step
	return a + Vec2{math.cos(ang), math.sin(ang)} * vlen(v)
}

line_near_start :: proc(p: Vec2) -> bool {
	return len(line_tool.pts) >= 3 && vlen(p - line_tool.pts[0]) * doc.zoom <= LINE_CLOSE_PX
}

line_cancel :: proc() {
	clear(&line_tool.pts)
}

line_undo_point :: proc() {
	if len(line_tool.pts) > 0 {
		pop(&line_tool.pts)
	}
}

line_mouse_down :: proc(btn: int, p: Vec2) {
	line_tool.started = false
	// a double click finishes only on the point just placed, so quick clicks elsewhere still add points
	dbl := ui.dbl_click && line_active() && vlen(p - line_tool.pts[len(line_tool.pts) - 1]) * doc.zoom <= 6
	if line_active() && (btn == 1 || dbl) {
		line_finish(false)
		drag.active = false
		return
	}
	if !line_active() {
		append(&line_tool.pts, p)
		line_tool.started = true
	}
}

line_mouse_up :: proc(p: Vec2) {
	q := line_constrain(p)
	if line_tool.started {
		// dragged out a single line: done
		if vlen(q - line_tool.pts[0]) * doc.zoom > 3 {
			append(&line_tool.pts, q)
			line_finish(false)
		}
		return
	}
	if line_near_start(p) {
		line_finish(true)
		return
	}
	if vlen(q - line_tool.pts[len(line_tool.pts) - 1]) > 0.01 {
		append(&line_tool.pts, q)
	}
}

// Paints the line in progress (closed: back to the first point) and clears it.
line_finish :: proc(closed: bool) {
	defer line_cancel()
	pts := line_tool.pts[:]
	if len(pts) < 2 || !can_edit() {
		return
	}
	d := doc
	col := fg
	filled := false
	if closed && line_fill && len(pts) >= 3 {
		history_push(d)
		line_fill_polygon(d, pts, col)
		filled = true
	}
	if !line_outline && filled {
		return
	}
	n := len(d.undo)
	if !stroke_begin(.Line, pts[0], col) {
		return
	}
	if stroke.b.pressure == .Pen {
		stroke.b.pressure = .Off // the pen isn't drawing this; taper still applies
	}
	for p in pts[1:] {
		append(&stroke.pts, p)
		stroke_flush(true)
	}
	if closed {
		append(&stroke.pts, pts[0])
		stroke_flush(true)
	}
	stroke_end()
	if filled && len(d.undo) > n {
		history_discard(d) // the fill and its outline are one undo step
	}
}

// Fills the polygon with `col` on the active layer (or mask), anti-aliased, through the selection.
line_fill_polygon :: proc(d: ^Doc, pts: []Vec2, col: Color) {
	w, h := d.w, d.h
	cov: []u8
	defer delete(cov)
	span := seamless_mode ? 1 : 0
	for oy in -span ..= span {
		for ox in -span ..= span {
			off := Vec2{f32(ox * w), f32(oy * h)}
			shifted := make([]Vec2, len(pts), context.temp_allocator)
			for p, i in pts do shifted[i] = p + off
			s := sel_polygon(w, h, shifted)
			if cov == nil {
				cov = s
			} else {
				for v, i in s do cov[i] = max(cov[i], v)
				delete(s)
			}
		}
	}
	g, empty, is_mask := doc_target(d)
	c := col
	if is_mask {
		v := luma(col)
		c = Color{v, v, v, 255}
	}
	lock := !is_mask && d.layers[d.active_layer].lock_alpha
	op := f32(brushes[.Line].opacity) / 100
	cur := make([]Color, w * h, context.temp_allocator)
	tiles_to_buf(g, w, h, cur, empty)
	for i in 0 ..< w * h {
		if cov[i] == 0 do continue
		a := f32(cov[i]) / 255 * op * f32(sel_at(d, i)) / 255
		if a <= 0 do continue
		cur[i] = lock ? lock_mix(cur[i], c, a) : over_px(cur[i], c, a)
	}
	tiles_from_buf(g, w, h, cur, empty)
	doc_touch_all(d)
}

// The placed points and the segment to the pointer, drawn over the canvas.
render_line_preview :: proc(d: ^Doc) {
	if !line_active() || cur_tool != .Line {
		return
	}
	pts := line_tool.pts[:]
	tip := line_constrain(hover_pt)
	closing := line_near_start(hover_pt)
	if closing {
		tip = pts[0]
	}
	seg :: proc(a, b: Vec2) {
		sa, sb := canvas_to_screen(a), canvas_to_screen(b)
		draw_line(sa + 1, sb + 1, Color{0, 0, 0, 170})
		draw_line(sa, sb, Color{255, 255, 255, 230})
	}
	for i in 1 ..< len(pts) {
		seg(pts[i - 1], pts[i])
	}
	if drag.active || hover_valid {
		seg(pts[len(pts) - 1], tip)
	}
	for p, i in pts {
		sp := canvas_to_screen(p)
		if i == 0 && closing {
			draw_circle_outline(sp.x, sp.y, 6, C_ACCENT)
		}
		handle_draw(sp)
	}
}

options_line :: proc(x: ^i32, y: i32) {
	checkbox(x^, y + 1, "Outline", &line_outline, "Paint the line with the brush settings")
	x^ += 64
	checkbox(x^, y + 1, "Fill closed", &line_fill, "Fill shapes closed by clicking the first point with the foreground colour")
	x^ += 80
	text(x^, y + 3, line_active() ? "Double click / Enter: finish   Click first point: close   Esc: cancel" : "Drag: line   Click: polygon points (Shift: 15 degrees)", C_TEXT_DIM)
}
