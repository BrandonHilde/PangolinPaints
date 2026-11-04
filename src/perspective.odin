package pangolin

import "core:math"

// ---------------------------------------------------------------------------
// Perspective guides: a horizon and 1, 2 or 3 vanishing points, with guide lines fanning out from
// each point across the canvas. While snapping is on, brush strokes and lines run along a guide:
// once a stroke has moved a few pixels it picks the guide through its start that best matches the
// way it set off, and keeps to it until released. The parallel lines count as guides too
// (1-point: level with and upright to the horizon; 2-point: upright). The points are kept as
// fractions of the canvas, may lie well outside it, and are dragged by their handles (or the
// horizon, which carries the points on it) while the guide's settings are in the options bar.
// ---------------------------------------------------------------------------

PERSP_MAX :: 3
PERSP_FAMILIES :: 3 // guide sets a stroke can follow, whatever the number of points
PERSP_PICK_PX :: 6 // screen distance a stroke moves before it picks its guide
PERSP_LIMIT :: 20 // points stay within this many canvas sizes

persp_on := false
persp_points := 2 // vanishing points, 1..3
persp_lines := 16 // guide lines drawn from each point
persp_snap := true
persp_vp := [PERSP_MAX]Vec2{{-0.25, 0.4}, {1.25, 0.4}, {0.5, 1.8}}

persp_lock := -1 // guide set the stroke in progress keeps to, or -1 until it picks one
persp_grab := -1 // handle being dragged: a point, or PERSP_MAX for the horizon
persp_hover := -1
persp_grab_at: Vec2 // horizon: where the pointer was last frame; point: its offset from the pointer

PERSP_COLORS := [PERSP_MAX]Color{{246, 170, 104, 255}, {110, 170, 255, 255}, {130, 210, 140, 255}}

persp_snapping :: proc() -> bool {
	return persp_on && persp_snap
}

persp_point :: proc(d: ^Doc, i: int) -> Vec2 {
	return Vec2{persp_vp[i].x * f32(d.w), persp_vp[i].y * f32(d.h)}
}

// Unit direction along the horizon: through the first two points, or level for one point.
persp_horizon_dir :: proc(d: ^Doc) -> Vec2 {
	if persp_points >= 2 {
		v := persp_point(d, 1) - persp_point(d, 0)
		if l := vlen(v); l > 0.001 do return v / l
	}
	return {1, 0}
}

// Direction of guide set k through `from`; false when `from` sits on its vanishing point.
persp_family_dir :: proc(d: ^Doc, k: int, from: Vec2) -> (Vec2, bool) {
	n := clamp(persp_points, 1, PERSP_MAX)
	if k < n {
		v := persp_point(d, k) - from
		l := vlen(v)
		if l < 0.5 do return {}, false
		return v / l, true
	}
	h := persp_horizon_dir(d)
	if k == 1 do return h, true // 1-point: level with the horizon
	return Vec2{-h.y, h.x}, true // upright to it
}

// Pulls `p` onto the guide through `from` closest in direction to from -> p. With `lock`, the
// guide is picked once the pointer has moved a few screen pixels (until then `from` is returned)
// and then kept.
persp_project :: proc(d: ^Doc, from, p: Vec2, lock: ^int = nil) -> Vec2 {
	if !persp_snapping() do return p
	v := p - from
	l := vlen(v)
	k := lock != nil ? lock^ : -1
	if k < 0 {
		if lock != nil && l * d.zoom < PERSP_PICK_PX do return from
		if l < 0.001 do return p
		best: f32 = -1
		for f in 0 ..< PERSP_FAMILIES {
			dir, ok := persp_family_dir(d, f, from)
			if !ok do continue
			if c := abs(v.x * dir.x + v.y * dir.y) / l; c > best {
				best, k = c, f
			}
		}
		if k < 0 do return p
		if lock != nil do lock^ = k
	}
	dir, ok := persp_family_dir(d, k, from)
	if !ok do return p
	return from + dir * (v.x * dir.x + v.y * dir.y)
}

// Where the guide a stroke keeps to starts: the press, or for a polygon the point placed before.
persp_from :: proc() -> Vec2 {
	if drag.tool == .Line && line_active() && !line_tool.started {
		return line_tool.pts[len(line_tool.pts) - 1]
	}
	return drag.start
}

// Default places for n points, with the horizon at height y (a fraction of the canvas).
persp_layout :: proc(n: int, y: f32) {
	switch n {
	case 1:
		persp_vp[0] = {0.5, y}
	case:
		persp_vp[0], persp_vp[1] = {-0.25, y}, {1.25, y}
		persp_vp[2] = {0.5, y < 0.5 ? 1.8 : -0.8} // looking down from a high horizon, up from a low one
	}
}

// Height of the horizon (as a fraction of the canvas) under the canvas centre.
persp_horizon_y :: proc(d: ^Doc) -> f32 {
	o, h := persp_point(d, 0), persp_horizon_dir(d)
	if abs(h.x) < 0.01 do return persp_vp[0].y
	y := o.y + h.y * (f32(d.w) / 2 - o.x) / h.x
	return clamp(y / f32(max(d.h, 1)), -1, 2)
}

persp_editing :: proc() -> bool {
	return persp_on && options_switch_on && options_switch == .Perspective
}

// Screen position of point i's handle: on the point, or held at the edge of the view while the
// point is out of sight (so it can still be grabbed without zooming out).
persp_handle :: proc(d: ^Doc, i: int) -> (sp: Vec2, off_view: bool) {
	sp = canvas_to_screen(persp_point(d, i))
	r := canvas_vp
	c := Vec2{clamp(sp.x, f32(r.x) + 12, f32(r.x + r.w) - 12), clamp(sp.y, f32(r.y) + 12, f32(r.y + r.h) - 12)}
	return c, c != sp
}

// Handle under canvas point p: a point, PERSP_MAX for the horizon, or -1.
@(private = "file")
persp_hit :: proc(d: ^Doc, p: Vec2) -> int {
	n := clamp(persp_points, 1, PERSP_MAX)
	for i in 0 ..< n {
		if sp, _ := persp_handle(d, i); vlen(sp - canvas_to_screen(p)) <= 8 do return i
	}
	v, h := p - persp_point(d, 0), persp_horizon_dir(d)
	if abs(v.x * h.y - v.y * h.x) * d.zoom <= 4 do return PERSP_MAX
	return -1
}

// Dragging the points and the horizon while the settings are shown. Returns true while it owns the
// mouse (or the pointer is on a handle), so the tool doesn't act on that press.
persp_input :: proc(d: ^Doc, p: Vec2, over: bool) -> bool {
	persp_hover = -1
	if persp_grab < 0 {
		if !persp_editing() || !over do return false
		persp_hover = persp_hit(d, p)
		if persp_hover < 0 do return false
		if ui.pressed[0] {
			persp_grab = persp_hover
			persp_grab_at = persp_grab < PERSP_MAX ? persp_point(d, persp_grab) - p : p
		}
	}
	ui.cursor = .RESIZE_ALL
	if persp_grab < 0 do return true
	frac :: proc(d: ^Doc, q: Vec2) -> Vec2 {
		v := Vec2{q.x / f32(max(d.w, 1)), q.y / f32(max(d.h, 1))}
		return {clamp(v.x, -PERSP_LIMIT, PERSP_LIMIT + 1), clamp(v.y, -PERSP_LIMIT, PERSP_LIMIT + 1)}
	}
	if persp_grab < PERSP_MAX {
		persp_vp[persp_grab] = frac(d, snap_pt(p + persp_grab_at))
	} else {
		// the horizon moves square to itself, carrying the points on it
		h := persp_horizon_dir(d)
		nrm := Vec2{-h.y, h.x}
		mv := nrm * ((p.x - persp_grab_at.x) * nrm.x + (p.y - persp_grab_at.y) * nrm.y)
		persp_grab_at = p
		for i in 0 ..< min(persp_points, 2) {
			persp_vp[i] = frac(d, persp_point(d, i) + mv)
		}
	}
	if !ui.down[0] do persp_grab = -1
	return true
}

// Angles spanning the canvas as seen from o: all the way round from inside it.
@(private = "file")
persp_fan :: proc(d: ^Doc, o: Vec2) -> (lo, hi: f32) {
	if o.x >= 0 && o.y >= 0 && o.x <= f32(d.w) && o.y <= f32(d.h) {
		return 0, math.TAU
	}
	cv := Vec2{f32(d.w) / 2, f32(d.h) / 2} - o
	base := math.atan2(cv.y, cv.x)
	lo, hi = max(f32), min(f32)
	for q in ([4]Vec2{{0, 0}, {f32(d.w), 0}, {0, f32(d.h)}, {f32(d.w), f32(d.h)}}) {
		v := q - o
		a := math.atan2(v.y, v.x) - base
		if a > math.PI do a -= math.TAU
		if a < -math.PI do a += math.TAU
		lo, hi = min(lo, a), max(hi, a)
	}
	return base + lo, base + hi
}

// Guide fans, the horizon, the guide a stroke is following, and the point handles.
render_persp :: proc(d: ^Doc, vp: Rect) {
	if !persp_on {
		return
	}
	n := clamp(persp_points, 1, PERSP_MAX)
	reach := f32(d.w + d.h) * 2
	for i in 0 ..< n do reach = max(reach, vlen(persp_point(d, i)) * 2 + f32(d.w + d.h))
	// the fans stay on the canvas; the horizon and handles may be out beside it
	clip_begin(Rect{i32(d.ox), i32(d.oy), i32(f32(d.w) * d.zoom) + 1, i32(f32(d.h) * d.zoom) + 1})
	for i in 0 ..< n {
		o := persp_point(d, i)
		c := with_alpha(PERSP_COLORS[i], 90)
		lo, hi := persp_fan(d, o)
		k := max(persp_lines, 1)
		for j in 0 ..< k {
			a := lo + (hi - lo) * (f32(j) + 0.5) / f32(k)
			draw_line(canvas_to_screen(o), canvas_to_screen(o + Vec2{math.cos(a), math.sin(a)} * reach), c)
		}
	}
	if drag.active && persp_lock >= 0 && paint_tool(drag.tool) && persp_snapping() {
		from := persp_from()
		if dir, ok := persp_family_dir(d, persp_lock, from); ok {
			a, b := canvas_to_screen(from - dir * reach), canvas_to_screen(from + dir * reach)
			c := persp_lock < n ? PERSP_COLORS[persp_lock] : WHITE
			draw_line(a + 1, b + 1, Color{0, 0, 0, 120})
			draw_line(a, b, with_alpha(c, 220))
		}
	}
	clip_end()
	o, h := persp_point(d, 0), persp_horizon_dir(d)
	lit := persp_hover == PERSP_MAX || persp_grab == PERSP_MAX
	a, b := canvas_to_screen(o - h * reach), canvas_to_screen(o + h * reach)
	draw_line(a + 1, b + 1, Color{0, 0, 0, 110})
	draw_line(a, b, lit ? WHITE : Color{235, 235, 245, 170})
	for i in 0 ..< n {
		sp, off_view := persp_handle(d, i)
		on := persp_hover == i || persp_grab == i
		draw_circle_outline(sp.x, sp.y, 7, BLACK)
		draw_circle_outline(sp.x, sp.y, 6, on ? WHITE : PERSP_COLORS[i])
		draw_frect({sp.x - 1, sp.y - 1, 3, 3}, PERSP_COLORS[i])
		if off_view {
			// a tick pointing at the point out of sight
			dir := vnorm(canvas_to_screen(persp_point(d, i)) - sp)
			draw_line(sp + dir * 7, sp + dir * 12, Color{0, 0, 0, 200})
			draw_line(sp + dir * 7 + 1, sp + dir * 12 + 1, PERSP_COLORS[i])
		}
	}
}

options_persp :: proc() {
	oicon("icon", .Perspective, "switch-icon", cmd_tip("Perspective", .Toggle_Perspective))
	otext("title", "Perspective", "switch-title", cmd_tip("Perspective", .Toggle_Perspective))
	n, y := persp_points, persp_horizon_y(doc)
	oslider("Points", 84, &persp_points, 1, PERSP_MAX, {"Vanishing points", "How many points the guides fan out from: 1 looks straight on, 2 looks at a corner, 3 also looks up or down. Drag the points on the canvas to place them."})
	if persp_points != n do persp_layout(persp_points, y)
	oslider("Lines", 84, &persp_lines, 2, 64, {"Guide lines", "How many guide lines are drawn from each vanishing point. This only changes what you see: strokes can follow a guide through any point."})
	ocheck("Snap", &persp_snap, {"Snap to guides", "Brush strokes and lines follow the guide closest to the way they set off, and keep to it until released."})
	if obutton("Reset", 46, {"Reset points", "Put the vanishing points and the horizon back in their default places."}) do persp_layout(persp_points, 0.4)
	if obutton("Perspective Off", 100, cmd_tip("Perspective", .Toggle_Perspective)) do run_cmd(.Toggle_Perspective)
}
