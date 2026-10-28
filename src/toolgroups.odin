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
}

tool_groups_clear :: proc() {
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
	for t, i in g.tools {
		if t == cur_tool {
			g.last = g.tools[(i + 1) % n]
			select_tool(g.last)
			return
		}
	}
	pick := g.tools[0]
	for t in g.tools {
		if t == g.last do pick = t
	}
	g.last = pick
	select_tool(pick)
}

// Runs the hotkeys of all groups; returns true if one was handled.
tool_groups_hotkeys :: proc() -> bool {
	if ui.ctrl || ui.alt || ui.shift {
		return false
	}
	for g, i in tool_groups {
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
	for g, i in tool_groups {
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
		if len(g.tools) > 0 do g.last = g.tools[0]
		append(&tool_groups, g)
	}
}
