package pangolin

import "core:fmt"

Dialog_Kind :: enum {
	None,
	New_Doc,
	Image_Size,
	Canvas_Size,
	Rotate,
	Layer_Props,
	Export,
	Brush_Settings,
	Prefs,
	Fx,
	Curves,
	Feather,
	Grow,
	Shrink,
	Confirm,
	Message,
	Shortcuts,
	About,
	Font,
	Workspaces,
	Group_Rename,
	Macros,
	Grid,
	UI_Scale,
	Frame_Props,
	Tags,
}

Dialog :: struct {
	kind:         Dialog_Kind,
	a, b, c, d:   int,
	flag, flag2:  bool,
	ratio:        f32,
	name:         Name,
	msg_title:    Name,
	msg_text:     Name,
	confirm_doc:  ^Doc,
	confirm_quit: bool,
}

dialog: Dialog

DIALOG_W_DEFAULT :: 260

dialog_open :: proc(k: Dialog_Kind) {
	if dialog.kind == .Fx || dialog.kind == .Curves {
		live_cancel()
	}
	dialog = Dialog {
		kind      = k,
		msg_title = dialog.msg_title,
		msg_text  = dialog.msg_text,
	}
	switch k {
	case .None, .Message, .Shortcuts, .About, .Confirm, .Fx, .Brush_Settings, .Font, .Group_Rename, .UI_Scale, .Tags:
	case .Macros:
		macros_refresh()
		dialog.b = -1 // fill in the name field
	case .Frame_Props:
		dialog.a = doc.frames[doc.active_frame].duration
	case .Workspaces:
		ws_refresh()
		for e, i in ws_entries {
			if e.name == ws_current do dialog.a = i
		}
	case .New_Doc:
		dialog.a, dialog.b = new_w, new_h
		dialog.c = new_bg
	case .Image_Size:
		dialog.a, dialog.b = doc.w, doc.h
		dialog.c = 100
		dialog.flag = true
		dialog.ratio = f32(doc.h) / f32(doc.w)
	case .Canvas_Size:
		dialog.a, dialog.b = doc.w, doc.h
		dialog.c = 4
	case .Rotate:
		dialog.a = 0
	case .Layer_Props:
		l := &doc.layers[doc.active_layer]
		dialog.name = l.name
		dialog.a = int(l.opacity) * 100 / 255
		dialog.b = int(l.blend)
		dialog.flag = l.visible
		dialog.flag2 = l.locked
		dialog.c = l.lock_alpha ? 1 : 0
	case .Export:
		dialog.a = export_quality
		dialog.b = 100
		// (the animated formats are only on offer with more than one frame)
		dialog.c = len(doc.frames) > 1 || int(export_format) < EXPORT_STILL_FORMATS ? int(export_format) : 0
	case .Prefs:
		dialog.b = bg_mode
	case .Curves:
		if !curves_open() {
			dialog.kind = .None
		}
	case .Grid:
		dialog.a, dialog.b, dialog.c, dialog.d = grid_w, grid_h, grid_opacity, grid_angle
		dialog.flag, dialog.flag2 = show_grid, snap_grid
	case .Feather:
		dialog.a = 10
	case .Grow, .Shrink:
		dialog.a = 5
	}
	if (k == .Feather || k == .Grow || k == .Shrink) && doc.sel == nil {
		dialog.kind = .None
		set_status("Make a selection first")
	}
}

dialog_close :: proc() {
	dialog.kind = .None
}

// OK / Cancel row at the bottom of the content area.
dialog_buttons :: proc(c: Rect, ok_tip: string, ok_label := "OK", cancel_label := "Cancel") -> (ok, cancel: bool) {
	y := c.y + c.h - 18
	r := Rect{c.x + c.w - 64, y, 64, 18}
	if button_primary(r, ok_label, {ok_label, ok_tip}) {
		ok = true
	}
	if cancel_label != "" {
		if button(Rect{r.x - 70, y, 64, 18}, cancel_label, {cancel_label, "Close this window without changing anything (Esc)."}) {
			cancel = true
		}
	}
	if ui.focus_id == 0 && !popup.open {
		if IsKeyPressed(.ENTER) || IsKeyPressed(.KP_ENTER) {
			ok = true
		}
		if IsKeyPressed(.ESCAPE) && cancel_label != "" {
			cancel = true
		}
	}
	return
}

row_int :: proc(c: Rect, y: i32, label: string, v: ^int, lo, hi: int, desc: string) -> bool {
	tip_text(c.x, y + 3, label, C_TEXT, {label, desc})
	return field_int(Rect{c.x + 110, y, 72, 14}, v, lo, hi, {label, desc})
}

row_slider :: proc(c: Rect, y: i32, label: string, v: ^int, lo, hi: int, suffix: string, desc: string, curve: f32 = 1) -> bool {
	tip_text(c.x, y + 3, label, C_TEXT, {label, desc})
	return slider(Rect{c.x + 96, y, c.w - 96, 14}, v, lo, hi, "", {label, desc}, suffix, curve)
}

dialogs_run :: proc() {
	switch dialog.kind {
	case .None:
	case .New_Doc:
		dlg_new()
	case .Image_Size:
		dlg_image_size()
	case .Canvas_Size:
		dlg_canvas_size()
	case .Rotate:
		dlg_rotate()
	case .Layer_Props:
		dlg_layer_props()
	case .Export:
		dlg_export()
	case .Brush_Settings:
		dlg_brush_settings()
	case .Prefs:
		dlg_prefs()
	case .Grid:
		dlg_grid()
	case .UI_Scale:
		dlg_ui_scale()
	case .Frame_Props:
		dlg_frame_props()
	case .Tags:
		dlg_tags()
	case .Fx:
		dlg_fx()
	case .Curves:
		dlg_curves()
	case .Feather, .Grow, .Shrink:
		dlg_sel_modify()
	case .Confirm:
		dlg_confirm()
	case .Message:
		dlg_message()
	case .Shortcuts:
		dlg_shortcuts()
	case .About:
		dlg_about()
	case .Font:
		dlg_font()
	case .Workspaces:
		dlg_workspaces()
	case .Group_Rename:
		dlg_group_rename()
	case .Macros:
		dlg_macros()
	}
}

// ---------------------------------------------------------------------------

Size_Preset :: struct {
	name: string,
	w, h: int,
}

SIZE_PRESETS := [?]Size_Preset {
	{"Sketch 1600 x 1200", 1600, 1200},
	{"HD 1920 x 1080", 1920, 1080},
	{"4K 3840 x 2160", 3840, 2160},
	{"Square 2048 x 2048", 2048, 2048},
	{"Portrait 1080 x 1350", 1080, 1350},
	{"A4 300 dpi 2480 x 3508", 2480, 3508},
	{"Letter 300 dpi 2550 x 3300", 2550, 3300},
	{"Canvas 16x20in 150 dpi", 2400, 3000},
	{"Small 800 x 600", 800, 600},
}

NEW_BG_NAMES := [?]string{"White", "Primed canvas", "Toned ground", "Mid grey", "Black", "Transparent", "Foreground", "Background"}

new_w, new_h, new_bg := 1600, 1200, 0

new_bg_color :: proc(i: int) -> Color {
	switch i {
	case 0:
		return Color{255, 255, 255, 255}
	case 1:
		return Color{240, 234, 220, 255}
	case 2:
		return Color{176, 136, 98, 255} // burnt sienna imprimatura
	case 3:
		return Color{128, 128, 128, 255}
	case 4:
		return Color{0, 0, 0, 255}
	case 5:
		return Color{}
	case 6:
		return fg
	case 7:
		return bg
	}
	return Color{255, 255, 255, 255}
}

dlg_new :: proc() {
	c := dialog_frame("New Painting", 300, 186)
	y := c.y
	PRESET_TIP :: "Fill in the width and height with a common size."
	tip_text(c.x, y + 3, "Preset", C_TEXT, {"Size preset", PRESET_TIP})
	@(static) names: [len(SIZE_PRESETS)]string
	for p, i in SIZE_PRESETS do names[i] = p.name
	cur := -1
	for p, i in SIZE_PRESETS {
		if p.w == dialog.a && p.h == dialog.b do cur = i
	}
	if nv, ch := combo(Rect{c.x + 110, y, c.w - 110, 14}, names[:], cur, {"Size preset", PRESET_TIP}); ch {
		dialog.a, dialog.b = SIZE_PRESETS[nv].w, SIZE_PRESETS[nv].h
	}
	y += 22
	row_int(c, y, "Width (px)", &dialog.a, 1, 16000, "The width of the new canvas. Click to type, or use the mouse wheel.")
	y += 20
	row_int(c, y, "Height (px)", &dialog.b, 1, 16000, "The height of the new canvas. Click to type, or use the mouse wheel.")
	if button(Rect{c.x + 190, y - 10, 50, 14}, "Swap", {"", "Swap the width and height, to turn a landscape canvas into a portrait one."}) {
		dialog.a, dialog.b = dialog.b, dialog.a
	}
	y += 22
	BG_TIP :: "What the bottom layer starts as. A clear layer to paint on is added above it, unless the background is Transparent."
	tip_text(c.x, y + 3, "Background", C_TEXT, {"Background", BG_TIP})
	if nv, ch := combo(Rect{c.x + 110, y, 120, 14}, NEW_BG_NAMES[:], dialog.c, {"Background", BG_TIP}); ch {
		dialog.c = nv
	}
	sw := Rect{c.x + 236, y, 34, 14}
	bc := new_bg_color(dialog.c)
	draw_checker(sw, 4)
	fill_rect(sw, bc)
	outline_rect(sw, C_BORDER)
	tip_area(sw, "new-bg-swatch", {"Background color", BG_TIP})
	y += 20
	mb := f32(dialog.a) * f32(dialog.b) * 4 / (1024 * 1024)
	tip_text(c.x, y + 3, fmt.tprintf("%.1f MB per layer at full coverage", mb), C_TEXT_DIM, {"Memory use", "The most memory one layer can take at this size. Empty parts of a layer take almost none."})
	ok, cancel := dialog_buttons(c, "Create the painting in a new tab (Enter).")
	if cancel {
		dialog_close()
	}
	if ok {
		new_w, new_h, new_bg = dialog.a, dialog.b, dialog.c
		d := doc_new_painting(dialog.a, dialog.b, fmt.tprintf("Painting %d", len(docs) + 1), bc)
		d.modified = false
		add_doc(d)
		dialog_close()
	}
}

dlg_image_size :: proc() {
	c := dialog_frame("Image Size", 280, 170)
	y := c.y
	if row_int(c, y, "Width (px)", &dialog.a, 1, 16000, "The new width. All layers are scaled to it.") && dialog.flag {
		dialog.b = max(int(f32(dialog.a) * dialog.ratio + 0.5), 1)
	}
	y += 20
	if row_int(c, y, "Height (px)", &dialog.b, 1, 16000, "The new height. All layers are scaled to it.") && dialog.flag {
		dialog.a = max(int(f32(dialog.b) / dialog.ratio + 0.5), 1)
	}
	y += 22
	checkbox(c.x, y, "Keep proportions", &dialog.flag, {"Keep proportions", "Changing the width also changes the height to match, and the other way around."})
	y += 18
	pcts := [?]int{25, 50, 75, 150, 200}
	for p, i in pcts {
		if button(Rect{c.x + i32(i) * 48, y, 46, 14}, fmt.tprintf("%d%%", p), {"", "Fill in this percent of the current size."}) {
			dialog.a = max(doc.w * p / 100, 1)
			dialog.b = max(doc.h * p / 100, 1)
		}
	}
	y += 20
	RESAMPLE_TIP :: "How new pixels are worked out. Bicubic is smoothest, Bilinear softer, and Nearest keeps hard pixel edges."
	tip_text(c.x, y + 3, "Resample", C_TEXT, {"Resample", RESAMPLE_TIP})
	@(static) rs: Resample
	combo_enum(Rect{c.x + 110, y, 130, 14}, RESAMPLE_NAMES, &rs, {"Resample", RESAMPLE_TIP})
	ok, cancel := dialog_buttons(c, "Scale the painting to this size (Enter).")
	if cancel {
		dialog_close()
	}
	if ok {
		if dialog.a != doc.w || dialog.b != doc.h {
			doc_image_size(doc, dialog.a, dialog.b, rs)
			macro_record("image.Size", "width", fmt.tprint(dialog.a), "height", fmt.tprint(dialog.b), "resample", RESAMPLE_KEYS[rs])
		}
		dialog_close()
	}
}

dlg_canvas_size :: proc() {
	c := dialog_frame("Canvas Size", 260, 190)
	y := c.y
	row_int(c, y, "Width (px)", &dialog.a, 1, 16000, "The new canvas width. The painting is not scaled.")
	y += 20
	row_int(c, y, "Height (px)", &dialog.b, 1, 16000, "The new canvas height. The painting is not scaled.")
	y += 22
	ANCHOR_TIP :: "Where the painting sits in the new canvas. Space is added, or cut away, on the other sides."
	tip_text(c.x, y + 3, "Anchor", C_TEXT, {"Anchor", ANCHOR_TIP})
	for i in 0 ..< 9 {
		r := Rect{c.x + 110 + i32(i % 3) * 18, y + i32(i / 3) * 18, 16, 16}
		if icon_button(r, dialog.c == i ? .Check : .Minus, {ANCHOR_NAMES[i], ANCHOR_TIP}, dialog.c == i) {
			dialog.c = i
		}
	}
	ok, cancel := dialog_buttons(c, "Change the canvas to this size (Enter).")
	if cancel {
		dialog_close()
	}
	if ok {
		if dialog.a != doc.w || dialog.b != doc.h {
			doc_canvas_size_anchored(doc, dialog.a, dialog.b, dialog.c)
			macro_record("image.Canvas_Size", "width", fmt.tprint(dialog.a), "height", fmt.tprint(dialog.b), "anchor", ANCHOR_KEYS[dialog.c])
		}
		dialog_close()
	}
}

dlg_rotate :: proc() {
	c := dialog_frame("Rotate Image", 260, 100)
	y := c.y
	row_int(c, y, "Angle (deg, CW)", &dialog.a, -359, 359, "How far to turn the painting, clockwise. Negative angles turn it counter-clockwise.")
	y += 20
	text(c.x, y + 3, "The canvas grows to fit the rotated image.", C_TEXT_DIM)
	ok, cancel := dialog_buttons(c, "Rotate the painting (Enter).")
	if cancel {
		dialog_close()
	}
	if ok {
		if dialog.a % 360 != 0 {
			doc_rotate_any(doc, f32(dialog.a))
			macro_record("image.Rotate", "angle", fmt.tprint(dialog.a))
		}
		dialog_close()
	}
}

dlg_layer_props :: proc() {
	c := dialog_frame("Layer Properties", 280, 170)
	y := c.y
	NAME_TIP :: "The layer's name in the layer list."
	OPACITY_TIP :: "How solid the whole layer is: 100 covers what is below, 0 hides it."
	tip_text(c.x, y + 3, "Name", C_TEXT, {"Layer name", NAME_TIP})
	text_field(Rect{c.x + 80, y, 170, 14}, &dialog.name, {"Layer name", NAME_TIP})
	y += 20
	tip_text(c.x, y + 3, "Opacity", C_TEXT, {"Layer opacity", OPACITY_TIP})
	slider(Rect{c.x + 80, y, 170, 14}, &dialog.a, 0, 100, "", {"Layer opacity", OPACITY_TIP}, "%")
	y += 20
	tip_text(c.x, y + 3, "Blend mode", C_TEXT, {"Blend mode", BLEND_TIP})
	if nv, ch := combo(Rect{c.x + 80, y, 120, 14}, blend_names_slice(), dialog.b, {"Blend mode", BLEND_TIP}); ch {
		dialog.b = nv
	}
	y += 22
	checkbox(c.x, y, "Visible", &dialog.flag, {"Visible", "Show the layer. A hidden layer can't be painted on and isn't exported."})
	checkbox(c.x + 70, y, "Locked", &dialog.flag2, {"Locked", "Protect the layer from painting and other changes."})
	la := dialog.c != 0
	if checkbox(c.x + 140, y, "Lock transparency", &la, {"Lock transparency", cmd_help(.Layer_Lock_Alpha)}) {
		dialog.c = la ? 1 : 0
	}
	ok, cancel := dialog_buttons(c, "Use these layer settings (Enter).")
	if cancel {
		dialog_close()
	}
	if ok {
		history_push(doc)
		l := &doc.layers[doc.active_layer]
		layer_props_record(l)
		l.name = dialog.name
		l.opacity = u8(dialog.a * 255 / 100)
		l.blend = Blend(dialog.b)
		l.visible = dialog.flag
		l.locked = dialog.flag2
		l.lock_alpha = dialog.c != 0
		doc_touch_all(doc)
		dialog_close()
	}
}

BLEND_TIP :: "How the layer mixes with the layers below it, such as Multiply to darken or Screen to lighten. The wheel steps through the modes."

blend_names_slice :: proc() -> []string {
	@(static) names: [len(Blend)]string
	for n, i in BLEND_NAMES {
		names[int(i)] = n
	}
	return names[:]
}

dlg_export :: proc() {
	c := dialog_frame("Export", 300, 150)
	y := c.y
	FORMAT_TIP :: "The kind of image file to save. PNG and TIFF keep transparency and every detail, JPG makes smaller files of photos. With several frames, a PNG sequence saves one file per frame and a GIF plays as an animation; these use the timeline's playback range."
	tip_text(c.x, y + 3, "Format", C_TEXT, {"Format", FORMAT_TIP})
	@(static) names: [len(Export_Format)]string
	for n, i in EXPORT_FORMAT_NAMES do names[int(i)] = n
	if nv, ch := combo(Rect{c.x + 80, y, 180, 14}, names[:len(doc.frames) > 1 ? len(names) : EXPORT_STILL_FORMATS], dialog.c, {"Format", FORMAT_TIP}); ch {
		dialog.c = nv
	}
	y += 22
	if Export_Format(dialog.c) == .JPG {
		QUALITY_TIP :: "Higher keeps more detail and makes a larger file. JPG only."
		tip_text(c.x, y + 3, "Quality", C_TEXT, {"JPG quality", QUALITY_TIP})
		slider(Rect{c.x + 80, y, 180, 14}, &dialog.a, 1, 100, "", {"JPG quality", QUALITY_TIP}, "%")
		y += 20
	}
	SCALE_TIP :: "The size of the exported image, in percent of the canvas. The painting itself is not changed."
	tip_text(c.x, y + 3, "Scale", C_TEXT, {"Scale", SCALE_TIP})
	slider(Rect{c.x + 80, y, 180, 14}, &dialog.b, 10, 400, "", {"Scale", SCALE_TIP}, "%")
	y += 18
	output := fmt.tprintf("Output %d x %d px, all visible layers merged", max(doc.w * dialog.b / 100, 1), max(doc.h * dialog.b / 100, 1))
	if Export_Format(dialog.c) == .PNG_Sequence || Export_Format(dialog.c) == .GIF {
		lo, hi, _ := play_range()
		output = fmt.tprintf("Output %d x %d px, %d frames", max(doc.w * dialog.b / 100, 1), max(doc.h * dialog.b / 100, 1), hi - lo + 1)
	}
	tip_text(c.x, y + 3, output, C_TEXT_DIM, {"Output", "The size of the image file. All visible layers are combined into it."})
	ok, cancel := dialog_buttons(c, "Choose where to save the image (Enter).", "Export")
	if cancel {
		dialog_close()
	}
	if ok {
		export_format = Export_Format(dialog.c)
		export_quality = dialog.a
		scale := dialog.b
		dialog_close()
		export_run(export_format, export_quality, scale)
	}
}

dlg_brush_settings :: proc() {
	t := paint_tool(cur_tool) ? cur_tool : Tool.Brush
	b := &brushes[t]
	c := dialog_frame(fmt.tprintf("Brush Settings - %s", TOOL_NAMES[t]), 440, 300, false)
	col_w := (c.w - 16) / 2
	L := Rect{c.x, c.y, col_w, c.h}
	R := Rect{c.x + col_w + 16, c.y, col_w, c.h}
	y := L.y
	row_slider(L, y, "Size", &b.size, 1, BRUSH_MAX, " px", HELP_SIZE, 2.5)
	y += 18
	row_slider(L, y, "Opacity", &b.opacity, 1, 100, "%", HELP_OPACITY)
	y += 18
	row_slider(L, y, "Flow", &b.flow, 1, 100, "%", HELP_FLOW)
	y += 18
	row_slider(L, y, "Hardness", &b.hardness, 0, 100, "%", HELP_HARDNESS)
	y += 18
	row_slider(L, y, "Spacing", &b.spacing, 1, 200, "%", HELP_SPACING)
	y += 18
	row_slider(L, y, "Smoothing", &b.smoothing, 0, 100, "%", HELP_SMOOTHING)
	y += 18
	row_slider(L, y, "Scatter", &b.scatter, 0, 100, "%", HELP_SCATTER)
	y += 18
	row_slider(L, y, "Size jitter", &b.size_jitter, 0, 100, "%", HELP_SIZE_JITTER)
	y += 18
	row_slider(L, y, "Paper grain", &b.grain, 0, 100, "%", HELP_GRAIN)
	y += 18
	row_slider(L, y, "Angle", &b.angle, 0, 359, " deg", HELP_ANGLE)
	y += 18
	row_slider(L, y, "Roundness", &b.roundness, 5, 100, "%", HELP_ROUNDNESS)
	y += 20
	tip_text(L.x, y + 3, "Tip", C_TEXT, {"Brush tip", HELP_TIP})
	combo_enum(Rect{L.x + 96, y, 90, 14}, TIP_NAMES, &b.tip, {"Brush tip", HELP_TIP})
	y += 18
	checkbox(L.x, y, "Rotate with stroke direction", &b.follow, {"Rotate with stroke direction", HELP_FOLLOW})

	y = R.y
	tip_text(R.x, y + 3, "Pressure", C_TEXT, {"Pressure", HELP_PRESSURE})
	combo_enum(Rect{R.x + 96, y, R.w - 96, 14}, PRESSURE_NAMES, &b.pressure, {"Pressure", HELP_PRESSURE})
	y += 18
	if b.pressure == .Taper {
		row_slider(R, y, "Taper length", &b.taper, 1, 100, "", HELP_TAPER)
		y += 18
	}
	if b.pressure != .Off {
		checkbox(R.x, y, "affects size", &b.p_size, {"Pressure affects size", HELP_P_SIZE})
		checkbox(R.x + 96, y, "affects opacity", &b.p_opacity, {"Pressure affects opacity", HELP_P_OPACITY})
		y += 16
	}
	checkbox(R.x, y, "Airbrush (builds up while held)", &b.airbrush, {"Airbrush", HELP_AIRBRUSH})
	y += 20
	#partial switch t {
	case .Oil:
		text(R.x, y, "Wet paint", C_ACCENT)
		y += 14
		row_slider(R, y, "Paint load", &b.load, 0, 100, "%", HELP_LOAD)
		y += 18
		row_slider(R, y, "Wetness", &b.wet, 0, 100, "%", HELP_WET)
		y += 18
		row_slider(R, y, "Bristles", &b.bristles, 0, 100, "%", HELP_BRISTLES)
		y += 18
	case .Smudge:
		row_slider(R, y, "Strength", &b.strength, 0, 100, "%", HELP_SMUDGE)
		y += 18
		row_slider(R, y, "Bristles", &b.bristles, 0, 100, "%", HELP_BRISTLES)
		y += 18
	case .Blur:
		row_slider(R, y, "Strength", &b.strength, 0, 100, "%", HELP_BLUR)
		y += 18
		checkbox(R.x, y, "Sharpen instead of blur", &b.alt_mode, {"Sharpen", "Crisp up the pixels under the brush instead of softening them."})
		y += 18
	case .Dodge:
		row_slider(R, y, "Exposure", &b.strength, 0, 100, "%", HELP_EXPOSURE)
		y += 18
		checkbox(R.x, y, "Burn (darken) instead of dodge", &b.alt_mode, {"Burn", "Darken what is under the brush instead of lightening it."})
		y += 18
		TONES := [?]string{"Shadows", "Midtones", "Highlights"}
		tip_text(R.x, y + 3, "Range", C_TEXT, {"Tonal range", HELP_TONES})
		if nv, ch := combo(Rect{R.x + 96, y, 90, 14}, TONES[:], b.tone, {"Tonal range", HELP_TONES}); ch {
			b.tone = nv
		}
		y += 18
	case .Clone:
		checkbox(R.x, y, "Sample all layers", &b.clone_merged, {"Sample all layers", HELP_CLONE_ALL})
		y += 16
		text(R.x, y, "Alt+click sets the source.", C_TEXT_DIM)
		y += 12
		text(R.x, y, "Shift+drag re-aligns to it.", C_TEXT_DIM)
		y += 18
	}
	// stroke preview
	pv := Rect{R.x, R.y + R.h - 86, R.w, 64}
	brush_preview(pv, t)
	tip_area(pv, "brush-preview", {"Preview", "A sample stroke with these settings, in the foreground color."})
	ok, _ := dialog_buttons(c, "Close this window (Enter, or F5 again). The settings are already applied.", "Close", "")
	if ok || IsKeyPressed(.F5) {
		dialog_close()
	}
}

BG_MODE_NAMES := [?]string{"Checkerboard", "Black", "White", "Grey"}

dlg_prefs :: proc() {
	c := dialog_frame("Preferences", 290, 112)
	y := c.y
	BG_TIP :: "What shows through where a painting is transparent. It is only a display: your painting and exports are not affected."
	tip_text(c.x, y + 3, "Transparency shown as", C_TEXT, {"Transparency", BG_TIP})
	if nv, ch := combo(Rect{c.x + 130, y, 100, 14}, BG_MODE_NAMES[:], dialog.b, {"Transparency", BG_TIP}); ch {
		dialog.b = nv
	}
	y += 22
	checkbox(c.x, y, "Pixel grid at high zoom", &show_pixel_grid, {"Pixel grid", cmd_help(.Toggle_Pixel_Grid)})
	y += 16
	checkbox(c.x, y, "Show navigator", &show_navigator, {"Navigator", cmd_help(.Toggle_Navigator)})
	ok, cancel := dialog_buttons(c, "Use these preferences (Enter).")
	if cancel {
		dialog_close()
	}
	if ok {
		bg_mode = dialog.b
		dialog_close()
	}
}

dlg_sel_modify :: proc() {
	title := dialog.kind == .Feather ? "Feather Selection" : dialog.kind == .Grow ? "Grow Selection" : "Shrink Selection"
	c := dialog_frame(title, 260, 80)
	row_int(c, c.y, "Radius (px)", &dialog.a, 1, 500, dialog.kind == .Feather ? "How wide the soft edge of the selection is, in canvas pixels." : dialog.kind == .Grow ? "How far the edge of the selection moves outward, in canvas pixels." : "How far the edge of the selection moves inward, in canvas pixels.")
	ok, cancel := dialog_buttons(c, "Change the selection (Enter).")
	if cancel {
		dialog_close()
	}
	if ok {
		op: Sel_Op = dialog.kind == .Feather ? .Feather : dialog.kind == .Grow ? .Grow : .Shrink
		if doc_sel_modify(doc, op, dialog.a) {
			macro_record(SEL_OP_NODES[op], "px", fmt.tprint(dialog.a))
		}
		dialog_close()
	}
}

dlg_confirm :: proc() {
	d := dialog.confirm_doc
	c := dialog_frame("Unsaved Changes", 300, 90)
	text(c.x, c.y + 2, fmt.tprintf("Save changes to \"%s\"?", name_str(&d.title)), C_TEXT)
	y := c.y + c.h - 16
	proceed := false
	if button(Rect{c.x, y, 70, 16}, "Save", {"", "Save the painting first, then close it."}) {
		if file_save(d, false) {
			proceed = true
		} else {
			dialog_close()
			return
		}
	}
	if button(Rect{c.x + 76, y, 90, 16}, "Don't Save", {"", "Close the painting and lose the changes since it was last saved."}) {
		proceed = true
	}
	if button(Rect{c.x + 172, y, 70, 16}, "Cancel", {"", "Go back to the painting (Esc)."}) || IsKeyPressed(.ESCAPE) {
		dialog_close()
		return
	}
	if proceed {
		quit := dialog.confirm_quit
		dialog_close()
		if quit {
			d.modified = false
			request_quit()
		} else {
			close_doc(d)
		}
	}
}

dlg_message :: proc() {
	c := dialog_frame(name_str(&dialog.msg_title), 340, 100)
	text(c.x, c.y + 4, name_str(&dialog.msg_text), C_TEXT)
	ok, _ := dialog_buttons(c, "Close this message (Enter).", "OK", "")
	if ok {
		dialog_close()
	}
}

ANCHOR_NAMES := [9]string{"Top left", "Top", "Top right", "Left", "Center", "Right", "Bottom left", "Bottom", "Bottom right"}
ANCHOR_KEYS := [9]string{"top-left", "top", "top-right", "left", "center", "right", "bottom-left", "bottom", "bottom-right"}

// Changes the canvas size, keeping the painting at anchor `a` (0..8: top left, top, top right, ... bottom right).
doc_canvas_size_anchored :: proc(d: ^Doc, w, h, a: int) {
	col, row := a % 3, a / 3
	doc_canvas_size(d, w, h, (w - d.w) * col / 2, (h - d.h) * row / 2)
}

// Records what the Layer Properties window changes on `l`, one node per setting.
layer_props_record :: proc(l: ^Layer) {
	if !macro_recording() do return
	if name_str(&dialog.name) != name_str(&l.name) do macro_record("layer.Rename", "name", name_str(&dialog.name))
	if dialog.a != int(l.opacity) * 100 / 255 do macro_record("layer.Opacity", "opacity", fmt.tprint(dialog.a))
	if Blend(dialog.b) != l.blend do macro_record("layer.Blend", "blend", BLEND_NAMES[Blend(dialog.b)])
	if dialog.flag != l.visible do macro_record("layer.Visible", "visible", dialog.flag ? "1" : "0")
	if dialog.flag2 != l.locked do macro_record("layer.Lock", "locked", dialog.flag2 ? "1" : "0")
	if (dialog.c != 0) != l.lock_alpha do macro_record("cmd.Layer_Lock_Alpha")
}

// A command's name as the menus and tooltips say it, for the shortcuts window.
shortcut_name :: proc(c: Cmd) -> string {
	if c >= .Tool_Brush && c <= .Tool_Seamless do return TOOL_NAMES[Tool(int(c) - int(Cmd.Tool_Brush))]
	if c >= .Fx_First && c <= .Fx_Last do return FX_DEFS[Fx(int(c) - int(Cmd.Fx_First))].name
	if c >= .Opacity_10 && c <= .Opacity_100 do return fmt.tprintf("Opacity %d%%", (int(c) - int(Cmd.Opacity_10) + 1) * 10)
	#partial switch c {
	case .Clear:              return "Delete"
	case .Save_As:            return "Save As"
	case .Export:             return "Export"
	case .Close_Doc:          return "Close"
	case .Copy_Merged:        return "Copy Merged"
	case .Paste:              return "Paste as Layer"
	case .Fill_Fg:            return "Fill with Foreground"
	case .Fill_Bg:            return "Fill with Background"
	case .Brush_Settings:     return "Brush Settings"
	case .Image_Size:         return "Image Size"
	case .Canvas_Size:        return "Canvas Size"
	case .Auto_Contrast:      return "Auto Contrast"
	case .Layer_New:          return "New Layer"
	case .Layer_Via_Copy:     return "Layer via Copy"
	case .Layer_Via_Cut:      return "Layer via Cut"
	case .Layer_Merge:        return "Merge Down"
	case .Layer_Lock_Alpha:   return "Lock Transparency"
	case .Frame_New:          return "New Frame"
	case .Frame_Prev:         return "Previous Frame"
	case .Frame_Next:         return "Next Frame"
	case .Frame_First:        return "First Frame"
	case .Frame_Last:         return "Last Frame"
	case .Play:               return "Play / Pause"
	case .Toggle_Onion:       return "Onion Skin"
	case .Mask_Edit:          return "Edit Mask"
	case .Select_All:         return "Select All"
	case .Invert_Sel:         return "Invert Selection"
	case .Zoom_In:            return "Zoom In"
	case .Zoom_Out:           return "Zoom Out"
	case .Zoom_Fit:           return "Fit to Window"
	case .Zoom_1:             return "Zoom 100%"
	case .Zoom_2:             return "Zoom 200%"
	case .Toggle_Canvas_Mode: return "Canvas Mode"
	case .Toggle_Pixel_Grid:  return "Pixel Grid"
	case .Toggle_Thirds:      return "Rule of Thirds"
	case .Toggle_Grid:        return "Grid"
	case .Toggle_Snap:        return "Snap to Grid"
	case .Swap_Colors:        return "Swap Colors"
	case .Default_Colors:     return "Default Colors"
	case .Brush_Smaller:      return "Smaller Brush"
	case .Brush_Bigger:       return "Bigger Brush"
	case .Help_Keys:          return "Keyboard Shortcuts"
	case .Macro_Editor:       return "Node Editor"
	case .Macro_Record:       return "Record Macro"
	case .Macros:             return "Manage Macros"
	case .Macro_Import:       return "Import Macro"
	}
	return fmt.tprintf("%v", c)
}

dlg_shortcuts :: proc() {
	c := dialog_frame("Keyboard Shortcuts", 660, 420)
	cols :: 3
	col_w := c.w / cols
	per_col := (len(SHORTCUTS) + 8 + cols - 1) / cols
	i := 0
	put :: proc(c: Rect, i: ^int, per_col: int, col_w: i32, keys, what, desc: string) {
		col := i^ / per_col
		row := i^ % per_col
		x := c.x + i32(col) * col_w
		y := c.y + i32(row) * 10
		text(x, y, keys, C_ACCENT)
		tip_text(x + 92, y, what, C_TEXT, {"", desc})
		i^ += 1
	}
	for s in SHORTCUTS {
		put(c, &i, per_col, col_w, shortcut_text_for(s), shortcut_name(s.cmd), cmd_help(s.cmd))
	}
	put(c, &i, per_col, col_w, "Space (hold)", "Pan", "Drag to scroll the view with any tool.")
	put(c, &i, per_col, col_w, "Middle drag", "Pan", "Scroll the view with any tool.")
	put(c, &i, per_col, col_w, "Alt (hold)", "Eyedropper", "With most tools, click to take a color from the canvas.")
	put(c, &i, per_col, col_w, "Shift+click", "Straight stroke", "Paint a straight line from the end of the last stroke.")
	put(c, &i, per_col, col_w, "Wheel", "Zoom", "Zoom on the pointer. Shift scrolls sideways, Ctrl up and down.")
	put(c, &i, per_col, col_w, "Enter / Esc", "Apply / cancel", "Finish or cancel a transform, a crop or a line.")
	put(c, &i, per_col, col_w, "Arrows", "Nudge (Move)", "With the Move tool, move by one pixel, or 10 with Shift.")
	put(c, &i, per_col, col_w, "Right drag", "Paint with BG", "Paint with the background color.")
	ok, _ := dialog_buttons(c, "Close this window (Enter or Esc).", "Close", "")
	if ok || IsKeyPressed(.ESCAPE) {
		dialog_close()
	}
}

dlg_about :: proc() {
	c := dialog_frame("About", 360, 160)
	logo_draw(c.x + 4, c.y + 6, 4)
	tx := c.x + 80
	text(tx, c.y + 6, APP_NAME, C_ACCENT)
	text(tx, c.y + 20, APP_TAGLINE, C_TEXT_DIM)
	text(tx, c.y + 38, "Natural brushes, wet oil paint, smudge and blend,", C_TEXT)
	text(tx, c.y + 50, "layers with masks, adjustments and filters.", C_TEXT)
	text(tx, c.y + 62, "A sibling of Pangolin Pixels.", C_TEXT)
	text(tx, c.y + 80, "Written in Odin with SDL3.", C_TEXT_DIM)
	ok, _ := dialog_buttons(c, "Close this window (Enter).", "Close", "")
	if ok {
		dialog_close()
	}
}

// Closing / quitting ------------------------------------------------------------

request_close :: proc(d: ^Doc) {
	if d.modified {
		dialog_open(.Confirm)
		dialog.confirm_doc = d
		dialog.confirm_quit = false
	} else {
		close_doc(d)
	}
}

request_quit :: proc() {
	for d, i in docs {
		if d.modified {
			switch_doc(i)
			dialog_open(.Confirm)
			dialog.confirm_doc = d
			dialog.confirm_quit = true
			return
		}
	}
	want_quit = true
}
