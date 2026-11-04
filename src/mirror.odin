package pangolin

import "core:math"

// ---------------------------------------------------------------------------
// Mirror painting: `mirror_count` mirror lines through the centre, evenly spaced and starting at
// `mirror_angle`, give 2 x count copies of every brush dab and line (the dihedral symmetry: one
// mirror is a plain left/right reflection, six make a snowflake). The centre is kept as a fraction
// of the canvas so it stays put across documents and resizes; Move Center places it with a click.
// ---------------------------------------------------------------------------

MIRROR_MAX :: 16
MIRROR_COPIES :: MIRROR_MAX * 2

mirror_on := false
mirror_count := 1
mirror_angle := 90 // degrees from horizontal: 90 is a vertical line (left / right mirror)
mirror_cx, mirror_cy: f32 = 0.5, 0.5
mirror_placing := false // Move Center: the next press on the canvas places the centre
mirror_drag := false

mirror_center :: proc(d: ^Doc) -> Vec2 {
	return Vec2{mirror_cx * f32(d.w), mirror_cy * f32(d.h)}
}

// The symmetry's transforms (identity first): rotations by multiples of 360/count, then the
// reflections across each mirror line.
mirror_transforms :: proc(d: ^Doc) -> (ms: [MIRROR_COPIES]Affine, n: int) {
	c := mirror_center(d)
	k := clamp(mirror_count, 1, MIRROR_MAX)
	about :: proc(m: Affine, c: Vec2) -> Affine {
		r := m
		r.e = c.x - m.a * c.x - m.b * c.y
		r.f = c.y - m.c * c.x - m.d * c.y
		return r
	}
	for i in 0 ..< k {
		a := f32(i) * math.TAU / f32(k)
		ms[n] = about(Affine{math.cos(a), -math.sin(a), math.sin(a), math.cos(a), 0, 0}, c)
		n += 1
	}
	for i in 0 ..< k {
		t := 2 * (f32(mirror_angle) * math.PI / 180 + f32(i) * math.PI / f32(k))
		ms[n] = about(Affine{math.cos(t), math.sin(t), math.sin(t), -math.cos(t), 0, 0}, c)
		n += 1
	}
	return
}

// Mirror lines through the centre, and the centre itself.
render_mirror :: proc(d: ^Doc, vp: Rect) {
	if !mirror_on {
		return
	}
	c := mirror_center(d)
	reach := f32(d.w + d.h) * 2
	// the lines stay on the canvas (render_canvas has already clipped to the viewport)
	clip_begin(Rect{i32(d.ox), i32(d.oy), i32(f32(d.w) * d.zoom) + 1, i32(f32(d.h) * d.zoom) + 1})
	k := clamp(mirror_count, 1, MIRROR_MAX)
	for i in 0 ..< k {
		t := f32(mirror_angle) * math.PI / 180 + f32(i) * math.PI / f32(k)
		dir := Vec2{math.cos(t), math.sin(t)} * reach
		a, b := canvas_to_screen(c - dir), canvas_to_screen(c + dir)
		draw_line(a + 1, b + 1, Color{0, 0, 0, 90})
		draw_line(a, b, Color{C_ACCENT.r, C_ACCENT.g, C_ACCENT.b, 150})
	}
	clip_end()
	sp := canvas_to_screen(c)
	draw_circle_outline(sp.x, sp.y, 6, BLACK)
	draw_circle_outline(sp.x, sp.y, 5, mirror_placing ? WHITE : C_ACCENT)
	draw_frect({sp.x - 1, sp.y - 1, 3, 3}, C_ACCENT)
}

// Move Center: press (and drag) on the canvas to put the centre there. Returns true while it
// owns the mouse, so the tool doesn't act on that press.
mirror_center_input :: proc(p: Vec2, over: bool) -> bool {
	if !mirror_placing && !mirror_drag {
		return false
	}
	ui.cursor = .CROSSHAIR
	if !mirror_drag && over && ui.pressed[0] {
		mirror_drag = true
	}
	if mirror_drag {
		q := snap_pt(p)
		mirror_cx = clamp(q.x / f32(max(doc.w, 1)), 0, 1)
		mirror_cy = clamp(q.y / f32(max(doc.h, 1)), 0, 1)
		if !ui.down[0] {
			mirror_drag = false
			mirror_placing = false
			set_status("Mirror center placed")
		}
		return true
	}
	return over && (ui.pressed[0] || ui.pressed[1])
}

// Toggle items that can sit in tool groups ---------------------------------------------

tool_is_toggle :: proc(t: Tool) -> bool {
	return t == .Grid || t == .Mirror || t == .Perspective || t == .Seamless
}

tool_toggle_on :: proc(t: Tool) -> bool {
	#partial switch t {
	case .Grid:
		return show_grid
	case .Mirror:
		return mirror_on
	case .Perspective:
		return persp_on
	case .Seamless:
		return seamless_mode
	}
	return false
}

// The options bar shows the last thing picked: a tool, or one of these switches.
options_switch: Tool // .Grid, .Mirror, .Perspective or .Seamless while its settings are shown
options_switch_on: bool

options_show_tool :: proc() {
	options_switch_on = false
}

// Clicking a switch: off -> on (showing its settings); on but not shown -> show its settings;
// on and shown -> off (the tool's settings come back).
tool_toggle :: proc(t: Tool) {
	if tool_toggle_on(t) && !(options_switch_on && options_switch == t) {
		options_switch, options_switch_on = t, true
		return
	}
	switch_set(t, !tool_toggle_on(t))
}

// Turns a switch on or off, if it isn't already.
switch_set :: proc(t: Tool, on: bool) {
	if tool_toggle_on(t) == on do return
	#partial switch t {
	case .Grid:
		run_cmd(.Toggle_Grid)
	case .Mirror:
		run_cmd(.Toggle_Mirror)
	case .Perspective:
		run_cmd(.Toggle_Perspective)
	case .Seamless:
		run_cmd(.Toggle_Seamless)
	}
}

// Keeps the options bar in step with a switch turned on or off from anywhere (menu, shortcut, bar).
switch_changed :: proc(t: Tool) {
	if tool_toggle_on(t) {
		options_switch, options_switch_on = t, true
	} else if options_switch == t {
		options_switch_on = false
	}
}

options_grid :: proc() {
	oicon("icon", .Grid, "switch-icon", cmd_tip("Grid", .Toggle_Grid))
	otext("title", "Grid", "switch-title", cmd_tip("Grid", .Toggle_Grid))
	oslider("W", 84, &grid_w, 1, 1024, {"Cell width", "How wide each grid cell is, in canvas pixels. Shift moves along round sizes."}, "px", 2)
	oslider("H", 84, &grid_h, 1, 1024, {"Cell height", "How tall each grid cell is, in canvas pixels. Shift moves along round sizes."}, "px", 2)
	oslider("Angle", 92, &grid_angle, -90, 90, {"Grid angle", "Turn the grid about the center of the canvas. Snapping follows the turned lines. Shift moves by 5 degrees."}, "deg")
	ocheck("Snap", &snap_grid, cmd_tip("Snap to Grid", .Toggle_Snap))
	if obutton("Grid Off", 66, cmd_tip("Grid", .Toggle_Grid)) do run_cmd(.Toggle_Grid)
}

options_mirror :: proc() {
	oicon("icon", .Sym_X, "switch-icon", cmd_tip("Mirror", .Toggle_Mirror))
	otext("title", "Mirror", "switch-title", cmd_tip("Mirror", .Toggle_Mirror))
	oslider("Mirrors", 90, &mirror_count, 1, MIRROR_MAX, {"Mirror lines", "How many mirror lines run through the center. Each stroke is painted twice per line: 1 mirrors left and right, 6 makes a snowflake."})
	oslider("Angle", 92, &mirror_angle, 0, 179, {"Mirror angle", "The angle of the first mirror line: 90 is upright, for a left and right mirror. Shift moves by 5 degrees."}, "deg")
	if obutton("Move Center", 84, {"Move Center", "After clicking this, click or drag on the canvas to place the center the mirror lines run through. Esc cancels."}, true, mirror_placing) {
		mirror_placing = !mirror_placing
		if mirror_placing do set_status("Click or drag on the canvas to place the mirror center (Esc cancels)")
	}
	if obutton("Reset", 46, {"Reset center", "Put the mirror center back in the middle of the canvas."}) {
		mirror_cx, mirror_cy = 0.5, 0.5
	}
	if obutton("Mirror Off", 72, cmd_tip("Mirror", .Toggle_Mirror)) do run_cmd(.Toggle_Mirror)
}

// Tiled Mode has nothing to adjust: its settings are the reminder of what it does, and the way out.
options_seamless :: proc() {
	oicon("icon", .Seamless, "switch-icon", cmd_tip("Tiled Mode", .Toggle_Seamless))
	otext("title", "Tiled Mode", "switch-title", cmd_tip("Tiled Mode", .Toggle_Seamless))
	ohint("Strokes wrap across the canvas edges, for textures that repeat.")
	if obutton("Tiled Off", 66, cmd_tip("Tiled Mode", .Toggle_Seamless)) do run_cmd(.Toggle_Seamless)
}
