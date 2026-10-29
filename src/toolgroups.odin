package pangolin

import "core:fmt"
import "core:strconv"
import "core:strings"

// User-editable tool groups shown in the left panel. A group's hotkey selects its first tool
// (or the one last used from it); pressing it again cycles through the group's tools.
// A group holding colours instead of tools is a colour group: its hotkey cycles the
// foreground colour and leaves the tool alone.

MAX_TOOL_GROUPS :: 12

Tool_Group :: struct {
	key:    KeyboardKey, // KEY_NULL: no hotkey
	tools:  [dynamic]Tool,
	colors: [dynamic]Color,
	blends: [dynamic]Blend, // blend-mode group: cycles the Brush tool's blend mode
	last:   Tool, // last tool picked from this group
	name:   Name, // empty: "Group" ("Pen" for the pen eraser group)
	pen_eraser: bool, // the pen's eraser end uses this group's last tool (at most one group)
	// this group's own brush settings, so a tool shared by two groups can differ between them;
	// the active group's live copy is the global `brushes`, swapped in by group_enter
	own_brushes: [Tool]Brush,
	own_preset:  [Tool]int,
	has_own:     bool, // own_brushes is filled in (otherwise it starts as a copy of the live brushes)
}

active_group := -1 // group whose brush settings are loaded in `brushes`, or -1

// Stores the live brushes in the active group.
group_save_brushes :: proc() {
	if active_group < 0 || active_group >= len(tool_groups) do return
	g := &tool_groups[active_group]
	g.own_brushes, g.own_preset, g.has_own = brushes, brush_preset_idx, true
}

// Makes `gi` the active group, loading its brush settings into the live brushes.
group_enter :: proc(gi: int) {
	if gi == active_group || gi < 0 || gi >= len(tool_groups) || tool_groups[gi].pen_eraser do return
	group_save_brushes()
	g := &tool_groups[gi]
	if g.has_own {
		brushes, brush_preset_idx = g.own_brushes, g.own_preset
	} else {
		g.own_brushes, g.own_preset, g.has_own = brushes, brush_preset_idx, true
	}
	active_group = gi
}

// Group the active tool belongs to: the active group if it holds the tool, else the first that does.
current_group :: proc() -> int {
	if active_group >= 0 && active_group < len(tool_groups) {
		g := &tool_groups[active_group]
		if !g.pen_eraser && tool_group_has(g, cur_tool) do return active_group
	}
	for &g, i in tool_groups {
		if !g.pen_eraser && tool_group_has(&g, cur_tool) do return i
	}
	return -1
}

// Picks `t` as a member of group `gi`; without a group, keeps the active group if it holds `t`.
select_tool_in_group :: proc(t: Tool, gi := -1) {
	if gi >= 0 {
		group_enter(gi)
	} else if active_group < 0 || active_group >= len(tool_groups) || !tool_group_has(&tool_groups[active_group], t) {
		for &g, i in tool_groups {
			if !g.pen_eraser && tool_group_has(&g, t) {
				group_enter(i)
				break
			}
		}
	}
	select_tool(t)
}

// Tool the pen's eraser end should use, if a tool group is assigned to it.
pen_eraser_group_tool :: proc() -> (Tool, bool) {
	for &g in tool_groups {
		if g.pen_eraser && len(g.tools) > 0 {
			return tool_group_has(&g, g.last) ? g.last : g.tools[0], true
		}
	}
	return {}, false
}

group_title :: proc(g: ^Tool_Group) -> string {
	if g.name.n > 0 {
		return name_str(&g.name)
	}
	return g.pen_eraser ? "Pen" : "Group"
}

// Group names go into the preferences and workspace files, whose fields are split on : and ;
group_clean_name :: proc(s: string) -> string {
	sb := strings.builder_make(context.temp_allocator)
	for r in strings.trim_space(s) {
		if r != ':' && r != ';' && r >= ' ' do strings.write_rune(&sb, r)
	}
	return strings.trim_space(strings.to_string(sb))
}

tool_groups_clear :: proc() {
	active_group = -1
	for &g in tool_groups {
		delete(g.tools)
		delete(g.colors)
		delete(g.blends)
	}
	clear(&tool_groups)
}

tool_groups: [dynamic]Tool_Group
group_key_wait := -1 // group waiting for a hotkey press, or -1

tool_groups_default :: proc() {
	tool_groups_clear()
	add :: proc(key: KeyboardKey, tools: ..Tool) {
		g := Tool_Group {
			key  = key,
			last = tools[0],
		}
		append(&g.tools, ..tools)
		append(&tool_groups, g)
	}
	add(.ONE, .Brush, .Oil, .Smudge, .Eraser, .Blur, .Dodge)
	add(.TWO, .Clone, .Bucket, .Gradient, .Picker, .Text)
	add(.THREE, .Select_Rect, .Select_Ellipse, .Lasso, .Wand)
	add(.FOUR, .Move, .Transform, .Crop)
	add(.FIVE, .Hand, .Zoom)
}

tool_group_activate :: proc(gi: int) {
	g := &tool_groups[gi]
	if len(g.colors) > 0 {
		next := 0
		for c, i in g.colors {
			if c.r == fg.r && c.g == fg.g && c.b == fg.b {
				next = (i + 1) % len(g.colors)
				break
			}
		}
		set_fg(g.colors[next])
		return
	}
	if len(g.blends) == 1 {
		// a lone effect toggles on and off
		brush_blend = brush_blend == g.blends[0] ? .Normal : g.blends[0]
		set_statusf("Brush blend: %s", brush_blend == .Normal ? "off" : BLEND_NAMES[brush_blend])
		return
	}
	if len(g.blends) > 0 {
		next := 0
		for b, i in g.blends {
			if b == brush_blend {
				next = (i + 1) % len(g.blends)
				break
			}
		}
		brush_blend = g.blends[next]
		set_statusf("Brush blend: %s", BLEND_NAMES[brush_blend])
		return
	}
	n := len(g.tools)
	if n == 0 {
		return
	}
	if g.pen_eraser {
		// only changes the pen's eraser end, never the active tool
		for t, i in g.tools {
			if t == g.last {
				g.last = g.tools[(i + 1) % n]
				break
			}
		}
		return
	}
	for t, i in g.tools {
		if t == cur_tool && current_group() == gi {
			g.last = g.tools[(i + 1) % n]
			select_tool_in_group(g.last, gi)
			return
		}
	}
	pick := g.tools[0]
	for t in g.tools {
		if t == g.last do pick = t
	}
	g.last = pick
	select_tool_in_group(pick, gi)
}

// Runs the hotkeys of all groups; returns true if one was handled.
tool_groups_hotkeys :: proc() -> bool {
	if ui.ctrl || ui.alt || ui.shift {
		return false
	}
	for &g, i in tool_groups {
		if g.key != .KEY_NULL && IsKeyPressed(g.key) {
			tool_group_activate(i)
			return true
		}
	}
	return false
}

// While a group is waiting for a hotkey, swallows the next key press. Returns true while waiting.
tool_groups_key_capture :: proc() -> bool {
	if group_key_wait < 0 {
		return false
	}
	if group_key_wait >= len(tool_groups) || IsKeyPressed(.ESCAPE) {
		group_key_wait = -1
		return true
	}
	assign :: proc(k: KeyboardKey) {
		for &o in tool_groups {
			if o.key == k do o.key = .KEY_NULL
		}
		tool_groups[group_key_wait].key = k
		group_key_wait = -1
	}
	if IsKeyPressed(.BACKSPACE) || IsKeyPressed(.DELETE) {
		assign(.KEY_NULL)
		return true
	}
	for i in 0 ..< 128 {
		if (i >= 48 && i <= 57) || (i >= 65 && i <= 90) {
			if IsKeyPressed(KeyboardKey(i)) {
				assign(KeyboardKey(i))
				return true
			}
		}
	}
	return true
}

blend_in :: proc(list: []Blend, b: Blend) -> bool {
	for x in list {
		if x == b do return true
	}
	return false
}

tool_group_has ::proc(g: ^Tool_Group, t: Tool) -> bool {
	for x in g.tools {
		if x == t do return true
	}
	return false
}

// Preferences: "groups=<key>:<tool>,<tool>:<hex>,<hex>;<key>:..." (tool = index into Tool).
tool_groups_serialize :: proc() -> string {
	sb := strings.builder_make(context.temp_allocator)
	for &g, i in tool_groups {
		fmt.sbprintf(&sb, "%s%d:", i > 0 ? ";" : "", int(g.key))
		for t, j in g.tools {
			fmt.sbprintf(&sb, "%s%d", j > 0 ? "," : "", int(t))
		}
		fmt.sbprintf(&sb, ":")
		for c, j in g.colors {
			fmt.sbprintf(&sb, "%s%s", j > 0 ? "," : "", color_hex(c))
		}
		fmt.sbprintf(&sb, ":")
		for b, j in g.blends {
			fmt.sbprintf(&sb, "%s%d", j > 0 ? "," : "", int(b))
		}
		fmt.sbprintf(&sb, ":%d:%s:", g.pen_eraser ? 1 : 0, name_str(&g.name))
		// own brush settings: tool/preset/<all brush fields>,...
		if g.has_own {
			first := true
			for t in g.tools {
				if !paint_tool(t) do continue
				fmt.sbprintf(&sb, "%s%d/%d", first ? "" : ",", int(t), g.own_preset[t])
				for x in brush_to_ints(g.own_brushes[t]) do fmt.sbprintf(&sb, "/%d", x)
				first = false
			}
		}
	}
	return strings.to_string(sb)
}

tool_groups_parse :: proc(s: string) {
	tool_groups_clear()
	for part in strings.split(s, ";", context.temp_allocator) {
		fields := strings.split(part, ":", context.temp_allocator)
		if len(fields) < 2 || len(tool_groups) >= MAX_TOOL_GROUPS {
			continue
		}
		k, _ := strconv.parse_int(fields[0])
		g: Tool_Group
		if (k >= 48 && k <= 57) || (k >= 65 && k <= 90) {
			g.key = KeyboardKey(k)
		}
		for ts in strings.split(fields[1], ",", context.temp_allocator) {
			ti, ok := strconv.parse_int(ts)
			if ok && ti >= 0 && ti < len(Tool) && !tool_group_has(&g, Tool(ti)) {
				append(&g.tools, Tool(ti))
			}
		}
		if len(fields) > 2 && len(g.tools) == 0 {
			for cs in strings.split(fields[2], ",", context.temp_allocator) {
				if c, ok := parse_hex(cs); ok {
					append(&g.colors, c)
				}
			}
		}
		if len(fields) > 3 && len(g.tools) == 0 && len(g.colors) == 0 {
			for bs in strings.split(fields[3], ",", context.temp_allocator) {
				bi, ok := strconv.parse_int(bs)
				if ok && bi >= 0 && bi < len(Blend) {
					append(&g.blends, Blend(bi))
				}
			}
		}
		if len(fields) > 4 && fields[4] == "1" do g.pen_eraser = true
		if len(fields) > 5 do name_set(&g.name, group_clean_name(fields[5]))
		if len(g.tools) > 0 do g.last = g.tools[0]
		if len(fields) > 6 && fields[6] != "" {
			// start from the live brushes so settings that are not saved keep their values
			g.own_brushes, g.own_preset = brushes, brush_preset_idx
			for e in strings.split(fields[6], ",", context.temp_allocator) {
				v := strings.split(e, "/", context.temp_allocator)
				if len(v) < 2 do continue
				ti, ok1 := strconv.parse_int(v[0])
				pi, ok2 := strconv.parse_int(v[1])
				if !(ok1 && ok2) || ti < 0 || ti >= len(Tool) || !paint_tool(Tool(ti)) do continue
				t := Tool(ti)
				vals := make([dynamic]int, context.temp_allocator)
				if len(v) == 4 {
					// first version of this field: tool/size/opacity/preset
					size, _ := strconv.parse_int(v[1])
					op, _ := strconv.parse_int(v[2])
					pi, _ = strconv.parse_int(v[3])
					append(&vals, size, op)
				} else {
					for s in v[2:] {
						n, _ := strconv.parse_int(s)
						append(&vals, n)
					}
				}
				g.own_brushes[t] = brush_from_ints(g.own_brushes[t], vals[:])
				if pi >= 0 && pi < len(presets) && presets[pi].tool == t do g.own_preset[t] = pi
			}
			g.has_own = true
		}
		append(&tool_groups, g)
	}
}

// ---------------------------------------------------------------------------
// Hotkey badge, canvas-mode bar and rename dialog
// ---------------------------------------------------------------------------

GROUPS_BAR_H :: 24

// Keyboard-key look for hotkey badges, so they read differently from the tool buttons.
keycap :: proc(r: Rect, label: string, lit, hover: bool) {
	fill := lit ? C_ACTIVE : (hover ? Color{78, 82, 96, 255} : Color{62, 65, 76, 255})
	face := Rect{r.x, r.y, r.w, r.h - 2}
	draw_rrect(f32(r.x), f32(r.y + 2), f32(r.w), f32(r.h - 2), RADIUS, C_BORDER) // the key's lower edge
	draw_rrect(f32(face.x), f32(face.y), f32(face.w), f32(face.h), RADIUS, fill)
	draw_rrect_outline(f32(face.x), f32(face.y), f32(face.w), f32(face.h), RADIUS, C_RING_HI)
	text_centered(face, label, label == "-" ? C_TEXT_OFF : (lit ? WHITE : C_TEXT))
}

keycap_w :: proc(label: string) -> i32 {
	return max(18, text_w(label) + 10)
}

// Shown in canvas mode in place of the side panels: every group as `[key] -> current tool`,
// with the group that holds the active tool highlighted.
panel_groups_bar :: proc(r: Rect) {
	ui.layer = 0
	fill_rect(r, C_PANEL_DK)
	hline(r.x, r.y, r.w, C_BORDER)
	ty := r.y + (r.h - FONT_CAP) / 2
	x := r.x + 10
	text(x, ty, "Groups:", C_TEXT_DIM)
	x += text_w("Groups:") + 10
	limit := r.x + r.w - 10
	if status_t > 0 {
		msg := name_str(&status_msg)
		limit -= text_w(msg) + 16
		text(r.x + r.w - 10 - text_w(msg), ty, msg, C_ACCENT)
	}
	ARROW :: "->"
	for &g, gi in tool_groups {
		shown: Tool
		active := false
		kind := 0 // 1 tool, 2 colour, 3 blend
		shown_color: Color
		shown_blend: Blend
		switch {
		case len(g.tools) > 0:
			kind = 1
			if g.pen_eraser {
				shown, _ = pen_eraser_group_tool()
				active = pen_eraser_active()
			} else if current_group() == gi {
				shown, active = cur_tool, true
			} else {
				shown = tool_group_has(&g, g.last) ? g.last : g.tools[0]
			}
		case len(g.colors) > 0:
			kind = 2
			shown_color = g.colors[0]
			for c in g.colors {
				if c.r == fg.r && c.g == fg.g && c.b == fg.b {
					shown_color, active = c, true
				}
			}
		case len(g.blends) > 0:
			kind = 3
			shown_blend = blend_in(g.blends[:], brush_blend) ? brush_blend : g.blends[0]
			active = shown_blend == brush_blend
		}
		if kind == 0 do continue

		title := group_title(&g)
		key := g.key == .KEY_NULL ? "" : key_name(g.key)
		// label: the hotkey as a keycap, or the group's name when it has none
		label_w := key == "" ? text_w(title) : keycap_w(key)
		target_w: i32 = kind == 3 ? text_w(BLEND_NAMES[shown_blend]) + 4 : 18
		cw := 8 + label_w + 6 + text_w(ARROW) + 6 + target_w + 8
		if x + cw > limit do break
		cell := Rect{x, r.y + 3, cw, r.h - 6}
		tip := key == "" ? title : fmt.tprintf("%s (%s)", title, key)
		clicked, held, hover := button_behavior(make_id(cell, "grpcell"), cell, tip)
		if active {
			draw_rrect(f32(cell.x), f32(cell.y), f32(cell.w), f32(cell.h), RADIUS, C_ACCENT_TINT)
			draw_rrect_outline(f32(cell.x), f32(cell.y), f32(cell.w), f32(cell.h), RADIUS, Color{246, 170, 104, 150})
		} else {
			draw_rrect(f32(cell.x), f32(cell.y), f32(cell.w), f32(cell.h), RADIUS, hover ? C_HOVER : C_PANEL)
			draw_rrect_outline(f32(cell.x), f32(cell.y), f32(cell.w), f32(cell.h), RADIUS, C_RING)
		}
		lx := cell.x + 8
		if key == "" {
			text(lx, ty, title, g.pen_eraser ? C_ACCENT : C_TEXT_DIM)
		} else {
			keycap(Rect{lx, cell.y + 2, label_w, cell.h - 4}, key, active, hover)
		}
		lx += label_w + 6
		text(lx, ty, ARROW, C_TEXT_DIM)
		lx += text_w(ARROW) + 6
		fgc := active ? C_ACCENT : C_TEXT
		switch kind {
		case 1:
			icon_centered(TOOL_ICONS[shown], Rect{lx, cell.y, 18, cell.h}, fgc)
		case 2:
			sw := Rect{lx + 1, cell.y + 4, 16, cell.h - 8}
			draw_rrect(f32(sw.x), f32(sw.y), f32(sw.w), f32(sw.h), 2, shown_color)
			draw_rrect_outline(f32(sw.x), f32(sw.y), f32(sw.w), f32(sw.h), 2, active ? WHITE : C_RING_HI)
		case 3:
			text(lx + 2, ty, BLEND_NAMES[shown_blend], fgc)
		}
		if clicked do tool_group_activate(gi)
		x += cw + 6
	}
}

dlg_group_rename :: proc() {
	c := dialog_frame("Rename Group", 280, 84)
	if dialog.a < 0 || dialog.a >= len(tool_groups) {
		dialog_close()
		return
	}
	text(c.x, c.y + 3, "Name", C_TEXT)
	text_field(Rect{c.x + 50, c.y, c.w - 50, 14}, &dialog.name, "Leave empty for the default name")
	ok, cancel := dialog_buttons(c)
	if cancel {
		dialog_close()
	}
	if ok {
		name_set(&tool_groups[dialog.a].name, group_clean_name(name_str(&dialog.name)))
		dialog_close()
	}
}

group_rename_open :: proc(gi: int) {
	dialog_open(.Group_Rename)
	dialog.a = gi
	dialog.name = tool_groups[gi].name
}
