package pangolin

import "core:fmt"
import "core:math"
import "core:os"
import "core:strconv"
import "core:strings"
import rl "vendor:raylib"

choose_scale :: proc() -> i32 {
	if ui_scale_pref > 0 {
		return i32(ui_scale_pref)
	}
	mh := rl.GetMonitorHeight(rl.GetCurrentMonitor())
	switch {
	case mh >= 2000:
		return 3
	case mh >= 1350:
		return 2
	}
	return 1
}

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

main :: proc() {
	shot_path := ""
	demo := false
	dlg_arg := -1
	menu_arg := -1
	open_args := make([dynamic]string)
	args := os.args
	for i := 1; i < len(args); i += 1 {
		a := args[i]
		switch {
		case a == "--shot" && i + 1 < len(args):
			shot_path = args[i + 1]
			i += 1
		case a == "--demo":
			demo = true
		case a == "--dialog" && i + 1 < len(args):
			dlg_arg, _ = strconv.parse_int(args[i + 1])
			i += 1
		case a == "--menu" && i + 1 < len(args):
			menu_arg, _ = strconv.parse_int(args[i + 1])
			i += 1
		case a == "--brush-sheet" && i + 1 < len(args):
			rl.SetTraceLogLevel(.WARNING)
			os.exit(brush_sheet(args[i + 1]))
		case a == "--bench":
			rl.SetTraceLogLevel(.WARNING)
			os.exit(bench())
		case a == "--selftest":
			rl.SetTraceLogLevel(.WARNING)
			os.exit(selftest())
		case:
			append(&open_args, a)
		}
	}

	rl.SetTraceLogLevel(.WARNING)
	rl.SetConfigFlags({.WINDOW_RESIZABLE, .VSYNC_HINT})
	rl.InitWindow(1280, 800, APP_NAME)
	defer rl.CloseWindow()
	rl.SetExitKey(.KEY_NULL)
	rl.SetWindowMinSize(900, 560)
	mon := rl.GetCurrentMonitor()
	mw, mh := rl.GetMonitorWidth(mon), rl.GetMonitorHeight(mon)
	if mw > 0 && mh > 0 && shot_path == "" {
		ww, wh := mw * 85 / 100, mh * 85 / 100
		rl.SetWindowSize(ww, wh)
		rl.SetWindowPosition((mw - ww) / 2, max((mh - wh) / 2, 30))
	}

	brush_init()
	swatches_set_preset(.Oil_Paints)
	set_fg(fg)
	prefs_load()
	ui.font = rl.GetFontDefault()
	ui.icons = icons_build_atlas()
	render_init()
	brand_init()

	if demo {
		demo_setup()
	} else {
		d := doc_new_filled(new_w, new_h, "Untitled", new_bg_color(new_bg))
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
		}
	}
	rt: rl.RenderTexture2D
	rt_w, rt_h: i32
	frame_no := 0
	last_title: string

	for !want_quit {
		if rl.WindowShouldClose() {
			request_quit()
		}
		free_all(context.temp_allocator)

		sw, sh := rl.GetScreenWidth(), rl.GetScreenHeight()
		ui.scale = choose_scale()
		// never let the logical resolution drop below what the layout needs
		for ui.scale > 1 && (sw / ui.scale < 900 || sh / ui.scale < 560) {
			ui.scale -= 1
		}
		lw, lh := max(sw / ui.scale, 1), max(sh / ui.scale, 1)
		ui.w, ui.h = int(lw), int(lh)
		if rt.id == 0 || rt_w != lw || rt_h != lh {
			if rt.id != 0 {
				rl.UnloadRenderTexture(rt)
			}
			rt = rl.LoadRenderTexture(lw, lh)
			rl.SetTextureFilter(rt.texture, .POINT)
			rt_w, rt_h = lw, lh
		}

		ui_begin_frame()
		ui.input_layer = (dialog.kind != .None ? 2 : 0) + (popup.open ? 1 : 0)

		if rl.IsFileDropped() {
			files := rl.LoadDroppedFiles()
			for i in 0 ..< int(files.count) {
				p := string(files.paths[i])
				// Shift while dropping places images as layers in the open painting
				if ui.shift && lower_ext(p) != ".ppnt" && lower_ext(p) != ".gpl" {
					place_image(p)
				} else {
					open_path(p)
				}
			}
			rl.UnloadDroppedFiles(files)
		}

		shortcuts_update()
		if status_t > 0 {
			status_t -= ui.dt
		}
		if menu_arg >= 0 && frame_no == 3 {
			popup_begin(1, Rect{4 + i32(menu_arg) * 44, 0, 40, 15}, 0, menu_arg)
			menu_build(menu_arg)
		}
		rl.BeginTextureMode(rt)
		rl.ClearBackground(C_BG)
		main_ui()
		dialogs_run()
		popup_run()
		tooltip_draw()
		rl.EndTextureMode()

		rl.BeginDrawing()
		rl.ClearBackground(rl.BLACK)
		rl.DrawTexturePro(rt.texture, {0, 0, f32(lw), -f32(lh)}, {0, 0, f32(lw * ui.scale), f32(lh * ui.scale)}, {}, 0, rl.WHITE)
		rl.EndDrawing()
		ui_end_frame()

		title := fmt.tprintf("%s - %s", doc_display_name(doc), APP_NAME)
		if title != last_title {
			rl.SetWindowTitle(strings.clone_to_cstring(title, context.temp_allocator))
			delete(last_title)
			last_title = strings.clone(title)
		}

		frame_no += 1
		if shot_path != "" {
			if frame_no == 8 {
				rl.TakeScreenshot(strings.clone_to_cstring(shot_path, context.temp_allocator))
			}
			if frame_no == 12 {
				break
			}
		}
	}
	if shot_path == "" {
		prefs_save()
	}
}

_ :: math
