package pangolin

import "core:fmt"
import "core:strconv"
import "core:strings"
import "core:os"

// Tiny key=value preferences file stored next to the executable.

prefs_path :: proc() -> string {
	return fmt.tprintf("%spaints.cfg", gfx_app_dir())
}

prefs_save :: proc() {
	sb := strings.builder_make(context.temp_allocator)
	b2i :: proc(b: bool) -> int {
		return b ? 1 : 0
	}
	fmt.sbprintf(&sb, "ui_scale=%d\n", ui_scale_pref)
	fmt.sbprintf(&sb, "bg_mode=%d\n", bg_mode)
	fmt.sbprintf(&sb, "pixel_grid=%d\n", b2i(show_pixel_grid))
	fmt.sbprintf(&sb, "navigator=%d\n", b2i(show_navigator))
	fmt.sbprintf(&sb, "new_w=%d\n", new_w)
	fmt.sbprintf(&sb, "new_h=%d\n", new_h)
	fmt.sbprintf(&sb, "new_bg=%d\n", new_bg)
	fmt.sbprintf(&sb, "jpg_quality=%d\n", export_quality)
	fmt.sbprintf(&sb, "fg=%d\n", int(fg.r) << 16 | int(fg.g) << 8 | int(fg.b))
	fmt.sbprintf(&sb, "bg=%d\n", int(bg.r) << 16 | int(bg.g) << 8 | int(bg.b))
	for t in Tool {
		if !paint_tool(t) do continue
		b := &brushes[t]
		fmt.sbprintf(&sb, "size_%d=%d\nopacity_%d=%d\npreset_%d=%d\n", int(t), b.size, int(t), b.opacity, int(t), brush_preset_idx[t])
	}
	fmt.sbprintf(&sb, "groups=%s\n", tool_groups_serialize())
	fmt.sbprintf(&sb, "swatches=")
	for c, i in swatches {
		fmt.sbprintf(&sb, "%s%s", i > 0 ? "," : "", color_hex(c))
	}
	fmt.sbprintf(&sb, "\n")
	write_file(prefs_path(), transmute([]u8)strings.to_string(sb))
}

prefs_load :: proc() {
	path := prefs_path()
	if !os.exists(path) {
		return
	}
	data, ok := read_file(path)
	if !ok {
		return
	}
	defer delete(data)
	text := string(data)
	for line in strings.split_lines_iterator(&text) {
		eq := strings.index_byte(line, '=')
		if eq < 0 {
			continue
		}
		key := strings.trim_space(line[:eq])
		sval := strings.trim_space(line[eq + 1:])
		if key == "groups" {
			tool_groups_parse(sval)
			continue
		}
		if key == "swatches" {
			list := make([dynamic]Color, context.temp_allocator)
			for part in strings.split(sval, ",", context.temp_allocator) {
				if c, cok := parse_hex(part); cok {
					append(&list, c)
				}
			}
			if len(list) > 0 {
				clear(&swatches)
				append(&swatches, ..list[:])
			}
			continue
		}
		val, vok := strconv.parse_int(sval)
		if !vok {
			continue
		}
		switch key {
		case "ui_scale":
			ui_scale_pref = clamp(val, 0, 4)
		case "bg_mode":
			bg_mode = clamp(val, 0, 3)
		case "pixel_grid":
			show_pixel_grid = val != 0
		case "navigator":
			show_navigator = val != 0
		case "new_w":
			new_w = clamp(val, 1, 16000)
		case "new_h":
			new_h = clamp(val, 1, 16000)
		case "new_bg":
			new_bg = clamp(val, 0, len(NEW_BG_NAMES) - 1)
		case "jpg_quality":
			export_quality = clamp(val, 1, 100)
		case "fg":
			set_fg(Color{u8(val >> 16), u8(val >> 8), u8(val), 255})
		case "bg":
			bg = Color{u8(val >> 16), u8(val >> 8), u8(val), 255}
		case:
			// per-tool brush settings: preset first so size/opacity can override it
			for prefix in ([?]string{"preset_", "size_", "opacity_"}) {
				if !strings.has_prefix(key, prefix) do continue
				ti, tok := strconv.parse_int(key[len(prefix):])
				if !tok || ti < 0 || ti >= len(Tool) || !paint_tool(Tool(ti)) do continue
				t := Tool(ti)
				switch prefix {
				case "preset_":
					if val >= 0 && val < len(presets) && presets[val].tool == t {
						brush_preset_idx[t] = val
						brushes[t] = presets[val].b
					}
				case "size_":
					brushes[t].size = clamp(val, 1, BRUSH_MAX)
				case "opacity_":
					brushes[t].opacity = clamp(val, 1, 100)
				}
			}
		}
	}
}
