package pangolin

import "core:fmt"
import "core:math"
import "core:os"
import "core:strconv"
import "core:strings"

// Paints a small sample so the UI can be inspected without user input (--demo).
demo_setup :: proc() {
	d := doc_new_filled(1200, 900, "demo", Color{240, 234, 220, 255})
	d.modified = false
	add_doc(d)
	// sky gradient on the background
	cur_tool = .Gradient
	drag.active = true
	drag.tool = .Gradient
	history_push(d)
	g, empty, _ := doc_target(d)
	drag.orig = make([]Color, d.w * d.h)
	tiles_to_buf(g, d.w, d.h, drag.orig, empty)
	set_fg(Color{70, 120, 190, 255})
	bg = Color{250, 214, 160, 255}
	gradient_render({600, 0}, {600, 620})
	delete(drag.orig)
	drag = {}
	// oil strokes on a new layer
	doc_add_layer(d)
	name_set(&d.layers[1].name, "Hills")
	stroke_line :: proc(t: Tool, col: Color, pts: []Vec2) {
		if !stroke_begin(t, pts[0], col) do return
		for i in 1 ..< len(pts) {
			a, b := pts[i - 1], pts[i]
			for k in 1 ..= 12 {
				stroke_move(a + (b - a) * (f32(k) / 12))
			}
		}
		stroke_end()
	}
	brushes[.Oil].size = 70
	for i in 0 ..< 7 {
		y := f32(560 + i * 40)
		col := Color{u8(60 + i * 12), u8(110 + i * 8), u8(60 + i * 3), 255}
		pts := [?]Vec2{{-40, y}, {300, y - 60 + f32(i * 5)}, {700, y + 10}, {1240, y - 40}}
		stroke_line(.Oil, col, pts[:])
	}
	// a sun with the soft brush
	brushes[.Brush].size = 160
	brushes[.Brush].hardness = 30
	doc_add_layer(d)
	name_set(&d.layers[2].name, "Sun")
	sun := [?]Vec2{{860, 210}, {861, 211}}
	stroke_line(.Brush, Color{255, 236, 170, 255}, sun[:])
	d.layers[2].blend = .Screen
	// smudge some clouds
	brushes[.Brush].size = 50
	brushes[.Brush].hardness = 10
	d.active_layer = 0
	for i in 0 ..< 3 {
		y := f32(140 + i * 70)
		cl := [?]Vec2{{120, y}, {300, y - 20}, {480, y + 10}}
		stroke_line(.Brush, Color{250, 250, 255, 255}, cl[:])
	}
	brushes[.Smudge].size = 60
	for i in 0 ..< 3 {
		y := f32(140 + i * 70)
		sm := [?]Vec2{{140, y + 10}, {420, y - 5}, {520, y + 20}}
		stroke_line(.Smudge, fg, sm[:])
	}
	d.active_layer = 1
	m := sel_ellipse(d.w, d.h, {700, 380}, {1020, 600})
	doc_sel_set(d, m)
	set_fg(Color{150, 70, 40, 255})
	cur_tool = .Oil
	d.modified = false
}

// Adds frames to the demo painting: copies with the sun moved along, each on its own cel (--demo-frames).
demo_frames :: proc(n: int) {
	d := doc
	sel := d.sel // the demo's selection would keep the strokes out
	d.sel = nil
	defer d.sel = sel
	for i in 1 ..< n {
		doc_add_frame(d, true)
		d.frames[i].duration = 120
		d.active_layer = 2
		tiles_fill(&d.layers[2].pix, Color{}, {})
		sun := [?]Vec2{{860 - f32(i) * 90, 210 + f32(i) * 20}, {861 - f32(i) * 90, 211 + f32(i) * 20}}
		brushes[.Brush].size = 160
		brushes[.Brush].hardness = 30
		if stroke_begin(.Brush, sun[0], Color{255, 236, 170, 255}) {
			for k in 1 ..= 12 do stroke_move(sun[0] + (sun[1] - sun[0]) * (f32(k) / 12))
			stroke_end()
		}
	}
	t: Tag
	name_set(&t.name, "Sunset")
	t.from, t.to, t.color = 1, n - 1, Color{240, 150, 80, 255}
	append(&d.tags, t)
	d.active_layer = 1
	set_frame(0)
	doc_refresh_comp(d)
	d.modified = false
}

main :: proc() {
	shot_path := ""
	win_w, win_h := 0, 0
	shot_frame := 8
	demo := false
	demo_frame_n := 0
	dlg_arg := -1
	menu_arg := -1
	Script_Click :: struct {
		frame: int,
		pos:   Vec2,
	}
	clicks := make([dynamic]Script_Click)
	hover: Script_Click // moves the pointer without clicking, for checking tooltips with --shot
	Script_Drag :: struct {
		frame:    int,
		from, to: Vec2,
	}
	drags := make([dynamic]Script_Drag)
	files_arg := ""
	open_args := make([dynamic]string)
	args := os.args
	for i := 1; i < len(args); i += 1 {
		a := args[i]
		switch {
		case a == "--shot" && i + 1 < len(args):
			shot_path = args[i + 1]
			i += 1
		case a == "--scale" && i + 1 < len(args):
			if v, ok := strconv.parse_int(args[i + 1]); ok do ui_scale_arg = ui_scale_parse(v)
			i += 1
		case a == "--size" && i + 1 < len(args):
			wh := strings.split(args[i + 1], "x", context.temp_allocator)
			if len(wh) == 2 {
				win_w, _ = strconv.parse_int(wh[0])
				win_h, _ = strconv.parse_int(wh[1])
			}
			i += 1
		case a == "--crop" && i + 1 < len(args):
			v := strings.split(args[i + 1], ",", context.temp_allocator)
			if len(v) == 4 {
				for k in 0 ..< 4 {
					gfx.shot_rect[k], _ = strconv.parse_int(v[k])
				}
				gfx.shot_crop = true
			}
			i += 1
		case a == "--shot-frame" && i + 1 < len(args):
			shot_frame, _ = strconv.parse_int(args[i + 1])
			i += 1
		case a == "--demo":
			demo = true
		case a == "--demo-frames" && i + 1 < len(args):
			demo = true
			demo_frame_n, _ = strconv.parse_int(args[i + 1])
			i += 1
		case a == "--dialog" && i + 1 < len(args):
			dlg_arg, _ = strconv.parse_int(args[i + 1])
			i += 1
		case a == "--clicks" && i + 1 < len(args):
			// "frame:x,y;frame:x,y": left clicks in window pixels, for checking the interface with --shot
			for part in strings.split(args[i + 1], ";", context.temp_allocator) {
				fp := strings.split(part, ":", context.temp_allocator)
				if len(fp) != 2 do continue
				xy := strings.split(fp[1], ",", context.temp_allocator)
				if len(xy) != 2 do continue
				f, _ := strconv.parse_int(fp[0])
				x, _ := strconv.parse_f32(xy[0])
				y, _ := strconv.parse_f32(xy[1])
				append(&clicks, Script_Click{f, {x, y}})
			}
			i += 1
		case a == "--drag" && i + 1 < len(args):
			// "frame:x0,y0,x1,y1;...": press at the first point on that frame, move to the second over the
			// next few frames and release there, for checking drags with --shot
			for part in strings.split(args[i + 1], ";", context.temp_allocator) {
				fp := strings.split(part, ":", context.temp_allocator)
				if len(fp) != 2 do continue
				xy := strings.split(fp[1], ",", context.temp_allocator)
				if len(xy) != 4 do continue
				v: [4]f32
				for s, k in xy do v[k], _ = strconv.parse_f32(s)
				f, _ := strconv.parse_int(fp[0])
				append(&drags, Script_Drag{f, {v[0], v[1]}, {v[2], v[3]}})
			}
			i += 1
		case a == "--files" && i + 1 < len(args):
			files_arg = args[i + 1] // the system's folder picker can't be scripted
			i += 1
		case a == "--hover" && i + 1 < len(args):
			// "frame:x,y": from that frame on, the pointer rests there
			fp := strings.split(args[i + 1], ":", context.temp_allocator)
			if len(fp) == 2 {
				xy := strings.split(fp[1], ",", context.temp_allocator)
				if len(xy) == 2 {
					hover.frame, _ = strconv.parse_int(fp[0])
					hover.pos.x, _ = strconv.parse_f32(xy[0])
					hover.pos.y, _ = strconv.parse_f32(xy[1])
				}
			}
			i += 1
		case a == "--menu" && i + 1 < len(args):
			menu_arg, _ = strconv.parse_int(args[i + 1])
			i += 1
		case a == "--brush-sheet" && i + 1 < len(args):
			os.exit(brush_sheet(args[i + 1]))
		case a == "--icon-sheet" && i + 1 < len(args):
			os.exit(icon_sheet(args[i + 1]))
		case a == "--convert" && i + 2 < len(args):
			os.exit(convert_file(args[i + 1], args[i + 2]))
		case a == "--bench":
			os.exit(bench())
		case a == "--selftest":
			os.exit(selftest())
		case:
			append(&open_args, a)
		}
	}

	if !gfx_init(APP_NAME, shot_path != "", win_w, win_h) {
		fmt.eprintln("could not start SDL:", gfx_error())
		os.exit(1)
	}
	defer gfx_shutdown()
	pen_init()

	brush_init()
	swatches_set_preset(.Oil_Paints)
	set_fg(fg)
	tool_groups_default()
	prefs_load()
	macros_refresh()
	render_init()
	brand_init()
	oui_init()
	panels_init()

	if demo {
		demo_setup()
		if demo_frame_n > 1 {
			demo_frames(demo_frame_n)
			bottom_mode_set(.Animation)
		}
	} else {
		d := doc_new_painting(new_w, new_h, "Untitled", new_bg_color(new_bg))
		d.modified = false
		add_doc(d)
	}
	for p in open_args {
		open_path(p)
	}
	if dlg_arg >= 0 {
		k := Dialog_Kind(clamp(dlg_arg, 0, len(Dialog_Kind) - 1))
		#partial switch k {
		case .Fx:
			fx_open(.Hue_Saturation)
		case:
			dialog_open(k)
			dialog.confirm_doc = doc // the Confirm window needs a painting to ask about
		}
	}
	if files_arg != "" {
		files_set_dir(files_arg)
		bottom_mode_set(.Files)
	}
	frame_no := 0
	last_title: string

	for !want_quit {
		free_all(context.temp_allocator)
		gfx_poll()
		for c in clicks {
			switch frame_no {
			case c.frame - 2 ..< c.frame:
				gfx.mouse = c.pos
			case c.frame:
				gfx.mouse = c.pos
				gfx.m_pressed[0], gfx.m_down[0] = true, true
			case c.frame + 1:
				gfx.mouse = c.pos
				gfx.m_released[0], gfx.m_down[0] = true, false
			}
		}
		for d in drags {
			DRAG_STEPS :: 6
			switch f := frame_no - d.frame; {
			case f >= -2 && f < 0:
				gfx.mouse = d.from
			case f == 0:
				gfx.mouse = d.from
				gfx.m_pressed[0], gfx.m_down[0] = true, true
			case f > 0 && f <= DRAG_STEPS:
				gfx.mouse = d.from + (d.to - d.from) * f32(f) / DRAG_STEPS
			case f == DRAG_STEPS + 1:
				gfx.mouse = d.to
				gfx.m_released[0], gfx.m_down[0] = true, false
			}
		}
		if hover.frame > 0 && frame_no >= hover.frame do gfx.mouse = hover.pos
		if gfx.quit {
			gfx.quit = false
			request_quit()
		}

		sw, sh := int(gfx.pw), int(gfx.ph)
		scale := f32(ui_scale_wanted()) / 100
		if ui.scale > 0 && scale != ui.scale {
			views_rescale(ui.scale / scale)
		}
		ui.scale = scale
		gfx_set_scale(ui.scale)
		ui.w, ui.h = max(int(f32(sw) / ui.scale), 1), max(int(f32(sh) / ui.scale), 1)

		ui_begin_frame()
		ui.input_layer = (dialog.kind != .None ? 2 : 0) + (popup.open ? 1 : 0)

		for p in gfx.dropped {
			// Shift while dropping places images as layers in the open painting
			if ui.shift && lower_ext(p) != ".ppnt" && lower_ext(p) != ".gpl" {
				place_image(p)
			} else {
				open_path(p)
			}
		}

		text_update()
		shortcuts_update()
		// never more than one frame at a time: the first time round, frames take a while to prepare,
		// and each should still get its turn so the next round can run at full speed
		if playing && dialog.kind == .None && !text_edit.active {
			playback_update(min(ui.dt, f32(max(doc.frames[doc.active_frame].duration, 10)) / 1000))
		}
		if status_t > 0 {
			status_t -= ui.dt
		}
		if menu_arg >= 0 && frame_no == 3 {
			menu_request = menu_arg
		}
		gfx_begin(C_BG)
		oui_begin_frame()
		main_ui()
		oui_end_frame()
		oui_render()
		files_drag_run()
		dialogs_run()
		dialog_frame_end()
		popup_run()
		tooltip_draw()
		if shot_path != "" && frame_no == shot_frame {
			gfx.screenshot = shot_path
		}
		gfx_present()
		ui_end_frame()

		title := fmt.tprintf("%s - %s", doc_display_name(doc), APP_NAME)
		if title != last_title {
			gfx_set_title(title)
			delete(last_title)
			last_title = strings.clone(title)
		}

		frame_no += 1
		if shot_path != "" && frame_no == shot_frame + 4 {
			break
		}
	}
	if shot_path == "" {
		prefs_save()
	}
}

_ :: math
