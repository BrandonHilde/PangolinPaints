package pangolin

import "core:fmt"
import "core:strings"

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

ui_scale_pref := 0 // 0 = auto

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
	case .None, .Message, .Shortcuts, .About, .Confirm, .Fx, .Brush_Settings, .Font, .Group_Rename:
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
		dialog.c = int(export_format)
	case .Prefs:
		dialog.a = ui_scale_pref
		dialog.b = bg_mode
	case .Curves:
		if !curves_open() {
			dialog.kind = .None
		}
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

// Draws the dim background and window frame; returns the content area.
// `docked` dialogs (live previews) leave the canvas undimmed and sit at its top right.
dialog_frame :: proc(title: string, w, h: i32, dim := true, docked := false) -> Rect {
	ui.layer = 2
	if dim && !docked {
		fill_rect(Rect{0, 0, i32(ui.w), i32(ui.h)}, Color{6, 7, 10, 130})
	}
	x := (i32(ui.w) - w) / 2
	y := (i32(ui.h) - h) / 2
	if docked {
		x = canvas_vp.x + canvas_vp.w - w - 12
		y = canvas_vp.y + 12
	}
	box := Rect{x, y, w, h}
	draw_shadow(f32(x), f32(y + 6), f32(w), f32(h), 7, 22, Color{0, 0, 0, 190})
	draw_rrect(f32(x), f32(y), f32(w), f32(h), 7, C_PANEL)
	// title bar: rounded on top only (the lower half is clipped away)
	clip_begin(Rect{x, y, w, 20})
	draw_rrect(f32(x), f32(y), f32(w), 40, 7, C_PANEL_DK)
	clip_end()
	hline(x, y + 20, w, C_BORDER)
	draw_rrect_outline(f32(x), f32(y), f32(w), f32(h), 7, C_RING_HI)
	text(x + 12, y + (20 - FONT_CAP) / 2, title, C_TEXT)
	return Rect{x + 12, y + 26, w - 24, h - 34}
}

// OK / Cancel row at the bottom of the content area.
dialog_buttons :: proc(c: Rect, ok_label := "OK", cancel_label := "Cancel") -> (ok, cancel: bool) {
	y := c.y + c.h - 18
	r := Rect{c.x + c.w - 64, y, 64, 18}
	if button_primary(r, ok_label) {
		ok = true
	}
	if cancel_label != "" {
		if button(Rect{r.x - 70, y, 64, 18}, cancel_label) {
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

row_int :: proc(c: Rect, y: i32, label: string, v: ^int, lo, hi: int, tip := "") -> bool {
	text(c.x, y + 3, label, C_TEXT)
	return field_int(Rect{c.x + 110, y, 72, 14}, v, lo, hi, tip)
}

row_slider :: proc(c: Rect, y: i32, label: string, v: ^int, lo, hi: int, suffix := "", tip := "", curve: f32 = 1) -> bool {
	text(c.x, y + 3, label, C_TEXT)
	return slider(Rect{c.x + 96, y, c.w - 96, 14}, v, lo, hi, "", tip, suffix, curve)
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
	text(c.x, y + 3, "Preset", C_TEXT)
	@(static) names: [len(SIZE_PRESETS)]string
	for p, i in SIZE_PRESETS do names[i] = p.name
	cur := -1
	for p, i in SIZE_PRESETS {
		if p.w == dialog.a && p.h == dialog.b do cur = i
	}
	if nv, ch := combo(Rect{c.x + 110, y, c.w - 110, 14}, names[:], cur); ch {
		dialog.a, dialog.b = SIZE_PRESETS[nv].w, SIZE_PRESETS[nv].h
	}
	y += 22
	row_int(c, y, "Width (px)", &dialog.a, 1, 16000)
	y += 20
	row_int(c, y, "Height (px)", &dialog.b, 1, 16000)
	if button(Rect{c.x + 190, y - 10, 50, 14}, "Swap", "Swap width and height") {
		dialog.a, dialog.b = dialog.b, dialog.a
	}
	y += 22
	text(c.x, y + 3, "Background", C_TEXT)
	if nv, ch := combo(Rect{c.x + 110, y, 120, 14}, NEW_BG_NAMES[:], dialog.c); ch {
		dialog.c = nv
	}
	sw := Rect{c.x + 236, y, 34, 14}
	bc := new_bg_color(dialog.c)
	draw_checker(sw, 4)
	fill_rect(sw, bc)
	outline_rect(sw, C_BORDER)
	y += 20
	mb := f32(dialog.a) * f32(dialog.b) * 4 / (1024 * 1024)
	text(c.x, y + 3, fmt.tprintf("%.1f MB per layer at full coverage", mb), C_TEXT_DIM)
	ok, cancel := dialog_buttons(c)
	if cancel {
		dialog_close()
	}
	if ok {
		new_w, new_h, new_bg = dialog.a, dialog.b, dialog.c
		d := doc_new_filled(dialog.a, dialog.b, fmt.tprintf("Painting %d", len(docs) + 1), bc)
		d.modified = false
		add_doc(d)
		dialog_close()
	}
}

dlg_image_size :: proc() {
	c := dialog_frame("Image Size", 280, 170)
	y := c.y
	if row_int(c, y, "Width (px)", &dialog.a, 1, 16000) && dialog.flag {
		dialog.b = max(int(f32(dialog.a) * dialog.ratio + 0.5), 1)
	}
	y += 20
	if row_int(c, y, "Height (px)", &dialog.b, 1, 16000) && dialog.flag {
		dialog.a = max(int(f32(dialog.b) / dialog.ratio + 0.5), 1)
	}
	y += 22
	checkbox(c.x, y, "Keep proportions", &dialog.flag)
	y += 18
	pcts := [?]int{25, 50, 75, 150, 200}
	for p, i in pcts {
		if button(Rect{c.x + i32(i) * 48, y, 46, 14}, fmt.tprintf("%d%%", p)) {
			dialog.a = max(doc.w * p / 100, 1)
			dialog.b = max(doc.h * p / 100, 1)
		}
	}
	y += 20
	text(c.x, y + 3, "Resample", C_TEXT)
	@(static) rs: Resample
	combo_enum(Rect{c.x + 110, y, 130, 14}, RESAMPLE_NAMES, &rs)
	ok, cancel := dialog_buttons(c)
	if cancel {
		dialog_close()
	}
	if ok {
		if dialog.a != doc.w || dialog.b != doc.h {
			doc_image_size(doc, dialog.a, dialog.b, rs)
		}
		dialog_close()
	}
}

dlg_canvas_size :: proc() {
	c := dialog_frame("Canvas Size", 260, 190)
	y := c.y
	row_int(c, y, "Width (px)", &dialog.a, 1, 16000)
	y += 20
	row_int(c, y, "Height (px)", &dialog.b, 1, 16000)
	y += 22
	text(c.x, y + 3, "Anchor", C_TEXT)
	for i in 0 ..< 9 {
		r := Rect{c.x + 110 + i32(i % 3) * 18, y + i32(i / 3) * 18, 16, 16}
		if icon_button(r, dialog.c == i ? .Check : .Minus, "", dialog.c == i) {
			dialog.c = i
		}
	}
	ok, cancel := dialog_buttons(c)
	if cancel {
		dialog_close()
	}
	if ok {
		col, row := dialog.c % 3, dialog.c / 3
		ox := (dialog.a - doc.w) * col / 2
		oy := (dialog.b - doc.h) * row / 2
		if dialog.a != doc.w || dialog.b != doc.h {
			doc_canvas_size(doc, dialog.a, dialog.b, ox, oy)
		}
		dialog_close()
	}
}

dlg_rotate :: proc() {
	c := dialog_frame("Rotate Image", 260, 100)
	y := c.y
	row_int(c, y, "Angle (deg, CW)", &dialog.a, -359, 359)
	y += 20
	text(c.x, y + 3, "The canvas grows to fit the rotated image.", C_TEXT_DIM)
	ok, cancel := dialog_buttons(c)
	if cancel {
		dialog_close()
	}
	if ok {
		if dialog.a % 360 != 0 {
			doc_rotate_any(doc, f32(dialog.a))
		}
		dialog_close()
	}
}

dlg_layer_props :: proc() {
	c := dialog_frame("Layer Properties", 280, 170)
	y := c.y
	text(c.x, y + 3, "Name", C_TEXT)
	text_field(Rect{c.x + 80, y, 170, 14}, &dialog.name)
	y += 20
	text(c.x, y + 3, "Opacity", C_TEXT)
	slider(Rect{c.x + 80, y, 170, 14}, &dialog.a, 0, 100, "", "", "%")
	y += 20
	text(c.x, y + 3, "Blend mode", C_TEXT)
	if nv, ch := combo(Rect{c.x + 80, y, 120, 14}, blend_names_slice(), dialog.b); ch {
		dialog.b = nv
	}
	y += 22
	checkbox(c.x, y, "Visible", &dialog.flag)
	checkbox(c.x + 70, y, "Locked", &dialog.flag2)
	la := dialog.c != 0
	if checkbox(c.x + 140, y, "Lock transparency", &la) {
		dialog.c = la ? 1 : 0
	}
	ok, cancel := dialog_buttons(c)
	if cancel {
		dialog_close()
	}
	if ok {
		history_push(doc)
		l := &doc.layers[doc.active_layer]
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

blend_names_slice :: proc() -> []string {
	@(static) names: [len(Blend)]string
	for n, i in BLEND_NAMES {
		names[int(i)] = n
	}
	return names[:]
}

dlg_export :: proc() {
	c := dialog_frame("Export Image", 300, 150)
	y := c.y
	text(c.x, y + 3, "Format", C_TEXT)
	@(static) names: [len(Export_Format)]string
	for n, i in EXPORT_FORMAT_NAMES do names[int(i)] = n
	if nv, ch := combo(Rect{c.x + 80, y, 180, 14}, names[:], dialog.c); ch {
		dialog.c = nv
	}
	y += 22
	if Export_Format(dialog.c) == .JPG {
		text(c.x, y + 3, "Quality", C_TEXT)
		slider(Rect{c.x + 80, y, 180, 14}, &dialog.a, 1, 100, "", "", "%")
		y += 20
	}
	text(c.x, y + 3, "Scale", C_TEXT)
	slider(Rect{c.x + 80, y, 180, 14}, &dialog.b, 10, 400, "", "", "%")
	y += 18
	text(c.x, y + 3, fmt.tprintf("Output %d x %d px, all visible layers merged", max(doc.w * dialog.b / 100, 1), max(doc.h * dialog.b / 100, 1)), C_TEXT_DIM)
	ok, cancel := dialog_buttons(c, "Export")
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
	row_slider(L, y, "Size", &b.size, 1, BRUSH_MAX, " px", "", 2.5)
	y += 18
	row_slider(L, y, "Opacity", &b.opacity, 1, 100, "%")
	y += 18
	row_slider(L, y, "Flow", &b.flow, 1, 100, "%", "How fast paint builds up within a stroke")
	y += 18
	row_slider(L, y, "Hardness", &b.hardness, 0, 100, "%")
	y += 18
	row_slider(L, y, "Spacing", &b.spacing, 1, 200, "%", "Distance between dabs, % of the size")
	y += 18
	row_slider(L, y, "Smoothing", &b.smoothing, 0, 100, "%", "Stabiliser: the stroke trails the mouse")
	y += 18
	row_slider(L, y, "Scatter", &b.scatter, 0, 100, "%")
	y += 18
	row_slider(L, y, "Size jitter", &b.size_jitter, 0, 100, "%")
	y += 18
	row_slider(L, y, "Paper grain", &b.grain, 0, 100, "%")
	y += 18
	row_slider(L, y, "Angle", &b.angle, 0, 359, " deg")
	y += 18
	row_slider(L, y, "Roundness", &b.roundness, 5, 100, "%")
	y += 20
	text(L.x, y + 3, "Tip", C_TEXT)
	combo_enum(Rect{L.x + 96, y, 90, 14}, TIP_NAMES, &b.tip)
	y += 18
	checkbox(L.x, y, "Rotate with stroke direction", &b.follow)

	y = R.y
	text(R.x, y + 3, "Pressure", C_TEXT)
	combo_enum(Rect{R.x + 96, y, R.w - 96, 14}, PRESSURE_NAMES, &b.pressure, "Pressure source (a pen on a graphics tablet replaces it with real pressure)")
	y += 18
	if b.pressure == .Taper {
		row_slider(R, y, "Taper length", &b.taper, 1, 100)
		y += 18
	}
	if b.pressure != .Off {
		checkbox(R.x, y, "affects size", &b.p_size)
		checkbox(R.x + 96, y, "affects opacity", &b.p_opacity)
		y += 16
	}
	checkbox(R.x, y, "Airbrush (builds up while held)", &b.airbrush)
	y += 20
	#partial switch t {
	case .Oil:
		text(R.x, y, "Wet paint", C_ACCENT)
		y += 14
		row_slider(R, y, "Paint load", &b.load, 0, 100, "%", "How long until the brush runs dry (100 = never)")
		y += 18
		row_slider(R, y, "Wetness", &b.wet, 0, 100, "%", "How much colour the brush picks up from the canvas")
		y += 18
		row_slider(R, y, "Bristles", &b.bristles, 0, 100, "%", "Strength of the bristle streaks")
		y += 18
	case .Smudge:
		row_slider(R, y, "Strength", &b.strength, 0, 100, "%")
		y += 18
		row_slider(R, y, "Bristles", &b.bristles, 0, 100, "%")
		y += 18
	case .Blur:
		row_slider(R, y, "Strength", &b.strength, 0, 100, "%")
		y += 18
		checkbox(R.x, y, "Sharpen instead of blur", &b.alt_mode)
		y += 18
	case .Dodge:
		row_slider(R, y, "Exposure", &b.strength, 0, 100, "%")
		y += 18
		checkbox(R.x, y, "Burn (darken) instead of dodge", &b.alt_mode)
		y += 18
		TONES := [?]string{"Shadows", "Midtones", "Highlights"}
		text(R.x, y + 3, "Range", C_TEXT)
		if nv, ch := combo(Rect{R.x + 96, y, 90, 14}, TONES[:], b.tone); ch {
			b.tone = nv
		}
		y += 18
	case .Clone:
		checkbox(R.x, y, "Sample all layers", &b.clone_merged)
		y += 16
		text(R.x, y, "Alt+click sets the source.", C_TEXT_DIM)
		y += 12
		text(R.x, y, "Shift+drag re-aligns to it.", C_TEXT_DIM)
		y += 18
	}
	// stroke preview
	pv := Rect{R.x, R.y + R.h - 86, R.w, 64}
	brush_preview(pv, t)
	ok, _ := dialog_buttons(c, "Close", "")
	if ok || IsKeyPressed(.F5) {
		dialog_close()
	}
}

UI_SCALE_NAMES := [?]string{"Auto", "1x", "2x", "3x", "4x"}
BG_MODE_NAMES := [?]string{"Checkerboard", "Black", "White", "Grey"}

dlg_prefs :: proc() {
	c := dialog_frame("Preferences", 290, 150)
	y := c.y
	text(c.x, y + 3, "UI scale", C_TEXT)
	if nv, ch := combo(Rect{c.x + 130, y, 100, 14}, UI_SCALE_NAMES[:], dialog.a); ch {
		dialog.a = nv
	}
	y += 20
	text(c.x, y + 3, "Transparency shown as", C_TEXT)
	if nv, ch := combo(Rect{c.x + 130, y, 100, 14}, BG_MODE_NAMES[:], dialog.b); ch {
		dialog.b = nv
	}
	y += 22
	checkbox(c.x, y, "Pixel grid at high zoom", &show_pixel_grid)
	y += 16
	checkbox(c.x, y, "Show navigator", &show_navigator)
	ok, cancel := dialog_buttons(c)
	if cancel {
		dialog_close()
	}
	if ok {
		ui_scale_pref = dialog.a
		bg_mode = dialog.b
		dialog_close()
	}
}

dlg_sel_modify :: proc() {
	title := dialog.kind == .Feather ? "Feather Selection" : dialog.kind == .Grow ? "Grow Selection" : "Shrink Selection"
	c := dialog_frame(title, 260, 80)
	row_int(c, c.y, "Radius (px)", &dialog.a, 1, 500)
	ok, cancel := dialog_buttons(c)
	if cancel {
		dialog_close()
	}
	if ok {
		d := doc
		v := make([]u8, d.w * d.h)
		copy(v, d.sel.v)
		#partial switch dialog.kind {
		case .Feather:
			mask_blur(v, d.w, d.h, f32(dialog.a))
		case .Grow:
			mask_grow(v, d.w, d.h, dialog.a)
		case .Shrink:
			mask_grow(v, d.w, d.h, -dialog.a)
		}
		history_push(d)
		doc_sel_set(d, v)
		dialog_close()
	}
}

dlg_confirm :: proc() {
	d := dialog.confirm_doc
	c := dialog_frame("Unsaved Changes", 300, 90)
	text(c.x, c.y + 2, fmt.tprintf("Save changes to \"%s\"?", name_str(&d.title)), C_TEXT)
	y := c.y + c.h - 16
	proceed := false
	if button(Rect{c.x, y, 70, 16}, "Save") {
		if file_save(d, false) {
			proceed = true
		} else {
			dialog_close()
			return
		}
	}
	if button(Rect{c.x + 76, y, 90, 16}, "Don't Save") {
		proceed = true
	}
	if button(Rect{c.x + 172, y, 70, 16}, "Cancel") || IsKeyPressed(.ESCAPE) {
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
	ok, _ := dialog_buttons(c, "OK", "")
	if ok {
		dialog_close()
	}
}

dlg_shortcuts :: proc() {
	c := dialog_frame("Keyboard Shortcuts", 660, 420)
	cols :: 3
	col_w := c.w / cols
	per_col := (len(SHORTCUTS) + 8 + cols - 1) / cols
	i := 0
	put :: proc(c: Rect, i: ^int, per_col: int, col_w: i32, keys, what: string) {
		col := i^ / per_col
		row := i^ % per_col
		x := c.x + i32(col) * col_w
		y := c.y + i32(row) * 10
		text(x, y, keys, C_ACCENT)
		text(x + 92, y, what, C_TEXT)
		i^ += 1
	}
	for s in SHORTCUTS {
		name := fmt.tprintf("%v", s.cmd)
		if s.cmd >= .Fx_First {
			name = FX_DEFS[Fx(int(s.cmd) - int(Cmd.Fx_First))].name
		}
		name, _ = strings.replace_all(name, "_", " ", context.temp_allocator)
		put(c, &i, per_col, col_w, shortcut_text_for(s), name)
	}
	put(c, &i, per_col, col_w, "Space (hold)", "Pan")
	put(c, &i, per_col, col_w, "Middle drag", "Pan")
	put(c, &i, per_col, col_w, "Alt (hold)", "Eyedropper")
	put(c, &i, per_col, col_w, "Shift+click", "Straight stroke")
	put(c, &i, per_col, col_w, "Wheel", "Zoom")
	put(c, &i, per_col, col_w, "Enter / Esc", "Apply / cancel")
	put(c, &i, per_col, col_w, "Arrows", "Nudge (Move)")
	put(c, &i, per_col, col_w, "Right drag", "Paint with BG")
	ok, _ := dialog_buttons(c, "Close", "")
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
	ok, _ := dialog_buttons(c, "Close", "")
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
