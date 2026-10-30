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
	fmt.sbprintf(&sb, "grid=%d\n", b2i(show_grid))
	fmt.sbprintf(&sb, "grid_snap=%d\n", b2i(snap_grid))
	fmt.sbprintf(&sb, "grid_w=%d\n", grid_w)
	fmt.sbprintf(&sb, "grid_h=%d\n", grid_h)
	fmt.sbprintf(&sb, "grid_opacity=%d\n", grid_opacity)
	fmt.sbprintf(&sb, "grid_angle=%d\n", grid_angle)
	fmt.sbprintf(&sb, "mirror=%d\n", b2i(mirror_on))
	fmt.sbprintf(&sb, "mirror_count=%d\n", mirror_count)
	fmt.sbprintf(&sb, "mirror_angle=%d\n", mirror_angle)
	fmt.sbprintf(&sb, "mirror_cx=%d\n", int(mirror_cx * 10000))
	fmt.sbprintf(&sb, "mirror_cy=%d\n", int(mirror_cy * 10000))
	fmt.sbprintf(&sb, "new_w=%d\n", new_w)
	fmt.sbprintf(&sb, "new_h=%d\n", new_h)
	fmt.sbprintf(&sb, "new_bg=%d\n", new_bg)
	fmt.sbprintf(&sb, "jpg_quality=%d\n", export_quality)
	fmt.sbprintf(&sb, "fg=%d\n", int(fg.r) << 16 | int(fg.g) << 8 | int(fg.b))
	fmt.sbprintf(&sb, "bg=%d\n", int(bg.r) << 16 | int(bg.g) << 8 | int(bg.b))
	workspace_write(&sb)
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
		if workspace_apply_line(key, sval) {
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
		case "grid":
			show_grid = val != 0
		case "grid_snap":
			snap_grid = val != 0
		case "grid_w":
			grid_w = clamp(val, 1, 4096)
		case "grid_h":
			grid_h = clamp(val, 1, 4096)
		case "grid_opacity":
			grid_opacity = clamp(val, 5, 100)
		case "grid_angle":
			grid_angle = clamp(val, -90, 90)
		case "mirror":
			mirror_on = val != 0
		case "mirror_count":
			mirror_count = clamp(val, 1, MIRROR_MAX)
		case "mirror_angle":
			mirror_angle = clamp(val, 0, 179)
		case "mirror_cx":
			mirror_cx = clamp(f32(val) / 10000, 0, 1)
		case "mirror_cy":
			mirror_cy = clamp(f32(val) / 10000, 0, 1)
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
		}
	}
}
