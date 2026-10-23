package pangolin

import "core:fmt"
import "core:math"
import rl "vendor:raylib"

MENU_H :: 16
OPT_H :: 22
TAB_H :: 16
STATUS_H :: 14
TOOLBAR_W :: 54
RIGHT_W :: 220

SWATCH_PRESET_ID :: u32(0x5A7C4E51)
PRESET_ID :: u32(0xB2A5E7E1)

// ---------------------------------------------------------------------------
// Top-level layout
// ---------------------------------------------------------------------------

main_ui :: proc() {
	W, H := i32(ui.w), i32(ui.h)
	fill_rect(Rect{0, 0, W, H}, C_BG)

	menubar := Rect{0, 0, W, MENU_H}
	optbar := Rect{0, MENU_H, W, OPT_H}
	status := Rect{0, H - STATUS_H, W, STATUS_H}
	body := Rect{0, MENU_H + OPT_H, W, H - MENU_H - OPT_H - STATUS_H}

	right := cut_right(&body, RIGHT_W)
	toolbar := cut_left(&body, TOOLBAR_W)
	tabs := cut_top(&body, TAB_H)
	viewport := body

	// canvas first so that panels can overdraw its borders
	canvas_update(viewport)
	render_canvas(viewport)

	panel_tabs(tabs)
	panel_toolbar(toolbar)
	panel_options(optbar)
	panel_right(right)
	panel_status(status)
	panel_menubar(menubar)
}

// ---------------------------------------------------------------------------
// Menu bar
// ---------------------------------------------------------------------------

MENU_TITLES := [?]string{"File", "Edit", "Image", "Adjust", "Filter", "Layer", "Select", "View", "Help"}

fx_item :: proc(fx: Fx) {
	name := FX_DEFS[fx].name
	def := &FX_DEFS[fx]
	label := len(def.params) > 0 || def.flag != "" ? fmt.tprintf("%s...", name) : name
	popup_item(label, cmd = Cmd(int(Cmd.Fx_First) + int(fx)))
}

menu_build :: proc(idx: int) {
	item :: popup_item
	d := doc
	l := &d.layers[d.active_layer]
	switch idx {
	case 0:
		item("New...", cmd = .New)
		item("Open...", cmd = .Open)
		popup_sep()
		item("Save", cmd = .Save)
		item("Save As...", cmd = .Save_As)
		popup_sep()
		item("Place Image as Layer...", cmd = .Place_Image)
		item("Export Image...", cmd = .Export)
		popup_sep()
		item("Load Swatches...", cmd = .Swatches_Load)
		item("Save Swatches...", cmd = .Swatches_Save)
		popup_sep()
		item("Close", cmd = .Close_Doc)
		item("Exit", cmd = .Exit)
	case 1:
		item("Undo", cmd = .Undo, enabled = len(d.undo) > 0)
		item("Redo", cmd = .Redo, enabled = len(d.redo) > 0)
		popup_sep()
		item("Cut", cmd = .Cut)
		item("Copy", cmd = .Copy)
		item("Copy Merged", cmd = .Copy_Merged)
		item("Paste as Layer", cmd = .Paste, enabled = clip.pix != nil)
		item("Clear", cmd = .Clear)
		popup_sep()
		item("Fill with Foreground", cmd = .Fill_Fg)
		item("Fill with Background", cmd = .Fill_Bg)
		popup_sep()
		item("Brush Settings...", cmd = .Brush_Settings)
		item("Preferences...", cmd = .Preferences)
	case 2:
		item("Image Size...", cmd = .Image_Size)
		item("Canvas Size...", cmd = .Canvas_Size)
		item("Crop to Selection", cmd = .Crop_Sel)
		item("Trim Transparent Edges", cmd = .Trim)
		popup_sep()
		item("Rotate 90 CW", cmd = .Rotate_CW)
		item("Rotate 90 CCW", cmd = .Rotate_CCW)
		item("Rotate 180", cmd = .Rotate_180)
		item("Rotate by Angle...", cmd = .Rotate_Any)
		item("Flip Horizontal", cmd = .Flip_H)
		item("Flip Vertical", cmd = .Flip_V)
		popup_sep()
		item("Flatten Image", cmd = .Flatten)
	case 3:
		item("Auto Contrast", cmd = .Auto_Contrast)
		fx_item(.Brightness_Contrast)
		fx_item(.Levels)
		item("Curves...", cmd = .Curves)
		fx_item(.Exposure)
		popup_sep()
		fx_item(.Hue_Saturation)
		fx_item(.Vibrance)
		fx_item(.Color_Balance)
		fx_item(.Temperature)
		popup_sep()
		fx_item(.Desaturate)
		fx_item(.Sepia)
		fx_item(.Invert)
		fx_item(.Posterize)
		fx_item(.Threshold)
	case 4:
		item(fmt.tprintf("Repeat %s", FX_DEFS[fx_last].name), cmd = Cmd(int(Cmd.Fx_First) + int(fx_last)))
		popup_sep()
		fx_item(.Gaussian_Blur)
		fx_item(.Box_Blur)
		fx_item(.Motion_Blur)
		fx_item(.Radial_Blur)
		fx_item(.Unsharp_Mask)
		popup_sep()
		fx_item(.Oil_Paint)
		fx_item(.Kuwahara)
		fx_item(.Canvas_Texture)
		fx_item(.Emboss)
		fx_item(.Find_Edges)
		popup_sep()
		fx_item(.Add_Noise)
		fx_item(.Median)
		fx_item(.Pixelate)
		fx_item(.Vignette)
	case 5:
		item("New Layer", cmd = .Layer_New)
		item("Duplicate Layer", cmd = .Layer_Dup)
		item("Delete Layer", cmd = .Layer_Del)
		item("Layer via Copy", cmd = .Layer_Via_Copy)
		item("Layer via Cut", cmd = .Layer_Via_Cut)
		popup_sep()
		item("Move Up", cmd = .Layer_Up)
		item("Move Down", cmd = .Layer_Down)
		item("Merge Down", cmd = .Layer_Merge)
		popup_sep()
		item("Lock Transparency", cmd = .Layer_Lock_Alpha, checked = l.lock_alpha)
		item("Properties...", cmd = .Layer_Props)
		popup_sep()
		item("Add Mask (Reveal All)", cmd = .Mask_Add, enabled = !l.has_mask)
		item("Add Mask from Selection", cmd = .Mask_From_Sel, enabled = !l.has_mask && d.sel != nil)
		item("Edit Mask", cmd = .Mask_Edit, checked = d.edit_mask, enabled = l.has_mask)
		item("Enable Mask", cmd = .Mask_Enable, checked = l.mask_on, enabled = l.has_mask)
		item("Apply Mask", cmd = .Mask_Apply, enabled = l.has_mask)
		item("Delete Mask", cmd = .Mask_Delete, enabled = l.has_mask)
	case 6:
		item("Select All", cmd = .Select_All)
		item("Deselect", cmd = .Deselect)
		item("Invert Selection", cmd = .Invert_Sel)
		item("Select Layer Opacity", cmd = .Select_Alpha)
		popup_sep()
		item("Feather...", cmd = .Feather, enabled = d.sel != nil)
		item("Grow...", cmd = .Grow, enabled = d.sel != nil)
		item("Shrink...", cmd = .Shrink, enabled = d.sel != nil)
	case 7:
		item("Zoom In", cmd = .Zoom_In)
		item("Zoom Out", cmd = .Zoom_Out)
		item("Fit on Screen", cmd = .Zoom_Fit)
		item("100%", cmd = .Zoom_1)
		item("200%", cmd = .Zoom_2)
		popup_sep()
		item("Pixel Grid", cmd = .Toggle_Pixel_Grid, checked = show_pixel_grid)
		item("Rule of Thirds", cmd = .Toggle_Thirds, checked = show_thirds)
		item("Navigator", cmd = .Toggle_Navigator, checked = show_navigator)
		item("Cycle Transparency Display", cmd = .Cycle_Canvas_Bg)
		popup_sep()
		item("Preferences...", cmd = .Preferences)
	case 8:
		item("Keyboard Shortcuts", cmd = .Help_Keys)
		item("About", cmd = .About)
	}
}

panel_menubar :: proc(r: Rect) {
	// The menubar stays interactive while a menu is open, but not under dialogs.
	if ui.input_layer < 2 {
		ui.layer = ui.input_layer
	} else {
		ui.layer = -1
	}
	fill_rect(r, C_PANEL_DK)
	hline(r.x, r.y + r.h - 1, r.w, C_BORDER)
	x := r.x + 4
	for title, i in MENU_TITLES {
		w := text_w(title) + 14
		br := Rect{x, r.y, w, r.h - 1}
		id := make_id(br, title)
		hover := ui_hover(br)
		is_open := popup.open && popup.menu_idx == i
		if hover || is_open {
			fill_rect(br, is_open ? C_ACTIVE : C_HOVER)
		}
		text(br.x + 7, br.y + 4, title, C_TEXT)
		if hover {
			if ui.pressed[0] {
				if is_open {
					popup_close()
				} else {
					popup_begin(id, br, 0, i)
					menu_build(i)
				}
			} else if popup.open && popup.menu_idx >= 0 && popup.menu_idx != i {
				popup_begin(id, br, 0, i)
				menu_build(i)
			}
		}
		x += w
	}
	t := doc_display_name(doc)
	text(r.x + r.w - text_w(t) - 8, r.y + 4, t, C_TEXT_DIM)
}

// ---------------------------------------------------------------------------
// Tabs
// ---------------------------------------------------------------------------

panel_tabs :: proc(r: Rect) {
	ui.layer = 0
	fill_rect(r, C_PANEL_DK)
	hline(r.x, r.y + r.h - 1, r.w, C_BORDER)
	x := r.x + 2
	close_idx := -1
	switch_idx := -1
	for d, i in docs {
		name := doc_display_name(d)
		w := text_w(name) + 34
		tr := Rect{x, r.y + 1, w, r.h - 1}
		if x + w > r.x + r.w - 20 {
			break
		}
		active := d == doc
		hover := ui_hover(tr)
		fill_rect(tr, active ? C_PANEL : (hover ? C_HOVER : C_PANEL_DK))
		if active {
			hline(tr.x, tr.y, tr.w, C_ACCENT)
		}
		text(tr.x + 6, tr.y + 4, name, active ? C_TEXT : C_TEXT_DIM)
		cr := Rect{tr.x + tr.w - 16, tr.y + 2, 12, 12}
		chover := ui_hover(cr)
		icon(.Close, cr.x, cr.y, chover ? C_DANGER : C_TEXT_DIM)
		if ui.pressed[0] && hover {
			if chover {
				close_idx = i
			} else {
				switch_idx = i
			}
		}
		if ui.pressed[2] && hover {
			close_idx = i
		}
		x += w + 1
	}
	if close_idx >= 0 {
		request_close(docs[close_idx])
	} else if switch_idx >= 0 {
		switch_doc(switch_idx)
	}
	if icon_button(Rect{r.x + r.w - 18, r.y + 2, 16, 13}, .Plus, "New painting") {
		run_cmd(.New)
	}
}

// ---------------------------------------------------------------------------
// Toolbar
// ---------------------------------------------------------------------------

TOOL_ICONS := [Tool]Icon {
	.Brush          = .Brush,
	.Oil            = .Oil,
	.Smudge         = .Smudge,
	.Eraser         = .Eraser,
	.Blur           = .Blur,
	.Dodge          = .Dodge,
	.Clone          = .Clone,
	.Bucket         = .Bucket,
	.Gradient       = .Gradient,
	.Picker         = .Picker,
	.Select_Rect    = .Sel_Rect,
	.Select_Ellipse = .Sel_Ellipse,
	.Lasso          = .Lasso,
	.Wand           = .Wand,
	.Move           = .Move,
	.Transform      = .Transform,
	.Crop           = .Crop,
	.Hand           = .Hand,
	.Zoom           = .Zoom,
}

panel_toolbar :: proc(r: Rect) {
	ui.layer = 0
	fill_rect(r, C_PANEL)
	vline(r.x + r.w - 1, r.y, r.h, C_BORDER)
	t := eff_tool()
	y := r.y + 4
	i: i32 = 0
	for tool in Tool {
		// small gaps between groups: painting, fill, selection, transform, view
		if tool == .Bucket || tool == .Select_Rect || tool == .Move || tool == .Hand {
			if i % 2 == 1 do i += 1
			y += 4
		}
		br := Rect{r.x + 3 + (i % 2) * 25, y + (i / 2) * 25, 24, 24}
		if icon_button(br, TOOL_ICONS[tool], TOOL_NAMES[tool], t == tool) {
			select_tool(tool)
		}
		i += 1
	}
	// fg / bg chips at the bottom of the toolbar
	cy := y + ((i + 1) / 2) * 25 + 8
	bgr := Rect{r.x + 18, cy + 12, 22, 22}
	fgr := Rect{r.x + 6, cy, 22, 22}
	fill_rect(bgr, bg)
	outline_rect(bgr, C_BORDER)
	fill_rect(fgr, fg)
	outline_rect(fgr, rl.WHITE)
	outline_rect(rect_inset(fgr, -1), C_BORDER)
	if ui_hover(bgr) && !ui_hover(fgr) && ui.pressed[0] {
		run_cmd(.Swap_Colors)
	}
}

// ---------------------------------------------------------------------------
// Tool options bar
// ---------------------------------------------------------------------------

panel_options :: proc(r: Rect) {
	ui.layer = 0
	fill_rect(r, C_PANEL)
	hline(r.x, r.y + r.h - 1, r.w, C_BORDER)
	x := r.x + 6
	y := r.y + 4
	t := eff_tool()
	if paint_tool(t) {
		options_brush(&x, y, t)
	} else {
		options_other(&x, y, t)
	}
	// right side: layer state
	l := &doc.layers[doc.active_layer]
	rx := r.x + r.w - 6
	rx -= 16
	if icon_button(Rect{rx, y, 16, 14}, .Lock_Alpha, "Lock layer transparency (/)", l.lock_alpha) {
		run_cmd(.Layer_Lock_Alpha)
	}
	if l.has_mask {
		rx -= 17
		if icon_button(Rect{rx, y, 16, 14}, .Mask, "Paint on the layer mask (\\)", doc.edit_mask) {
			run_cmd(.Mask_Edit)
		}
	}
}

slider_w :: proc(x: ^i32, y: i32, w: i32, v: ^int, lo, hi: int, label, tip: string, suffix := "%", curve: f32 = 1) {
	slider(Rect{x^, y, w, 14}, v, lo, hi, label, tip, suffix, curve)
	x^ += w + 5
}

options_brush :: proc(x: ^i32, y: i32, t: Tool) {
	b := &brushes[t]
	// presets for this tool
	names := make([dynamic]string, context.temp_allocator)
	idx := make([dynamic]int, context.temp_allocator)
	cur := -1
	for p, i in presets {
		if p.tool == t {
			if i == brush_preset_idx[t] do cur = len(names)
			append(&names, p.name)
			append(&idx, i)
		}
	}
	if len(names) > 0 {
		if nv, ch := combo(Rect{x^, y, 96, 14}, names[:], cur, "Brush preset"); ch {
			pi := idx[nv]
			brush_preset_idx[t] = pi
			brushes[t] = presets[pi].b
		}
		x^ += 101
	}
	slider_w(x, y, 92, &b.size, 1, BRUSH_MAX, "Size", "Brush size ([ and ])", "px", 2.5)
	slider_w(x, y, 84, &b.opacity, 1, 100, "Opacity", "Opacity (number keys)")
	#partial switch t {
	case .Brush, .Eraser, .Clone:
		slider_w(x, y, 70, &b.flow, 1, 100, "Flow", "How fast paint builds up")
		slider_w(x, y, 76, &b.hardness, 0, 100, "Hard", "Hardness")
		if t == .Clone {
			checkbox(x^, y + 1, "All layers", &b.clone_merged, "Sample all visible layers")
			x^ += 70
		}
	case .Oil:
		slider_w(x, y, 70, &b.load, 0, 100, "Load", "Paint on the brush (100 = never runs dry)")
		slider_w(x, y, 66, &b.wet, 0, 100, "Wet", "How much the brush mixes with paint on the canvas")
		slider_w(x, y, 76, &b.bristles, 0, 100, "Bristle", "Bristle streaks")
		slider_w(x, y, 70, &b.hardness, 0, 100, "Hard", "Hardness")
	case .Smudge:
		slider_w(x, y, 84, &b.strength, 0, 100, "Strength", "How far colour is dragged")
		slider_w(x, y, 70, &b.hardness, 0, 100, "Hard", "Hardness")
	case .Blur:
		slider_w(x, y, 84, &b.strength, 0, 100, "Strength", "")
		if button(Rect{x^, y, 46, 14}, "Blur", "", true, !b.alt_mode) do b.alt_mode = false
		if button(Rect{x^ + 48, y, 52, 14}, "Sharpen", "", true, b.alt_mode) do b.alt_mode = true
		x^ += 106
	case .Dodge:
		slider_w(x, y, 84, &b.strength, 0, 100, "Exposure", "")
		if button(Rect{x^, y, 46, 14}, "Dodge", "Lighten", true, !b.alt_mode) do b.alt_mode = false
		if button(Rect{x^ + 48, y, 40, 14}, "Burn", "Darken", true, b.alt_mode) do b.alt_mode = true
		x^ += 94
		TONES := [?]string{"Shadows", "Midtones", "Highlights"}
		if nv, ch := combo(Rect{x^, y, 74, 14}, TONES[:], b.tone, "Tonal range"); ch do b.tone = nv
		x^ += 80
	}
	slider_w(x, y, 84, &b.smoothing, 0, 100, "Smooth", "Stroke stabiliser")
	if button(Rect{x^, y, 58, 14}, "More...", "All brush settings (F5)") {
		run_cmd(.Brush_Settings)
	}
	x^ += 64
}

options_other :: proc(x: ^i32, y: i32, t: Tool) {
	hint :: proc(x: ^i32, y: i32, s: string) {
		text(x^, y + 3, s, C_TEXT_DIM)
		x^ += text_w(s) + 10
	}
	sel_modes :: proc(x: ^i32, y: i32) {
		labels := [?]string{"New", "Add", "Sub", "And"}
		for l, i in labels {
			if button(Rect{x^ + i32(i) * 30, y, 28, 14}, l, "", true, int(topts.sel_mode) == i) {
				topts.sel_mode = Sel_Mode(i)
			}
		}
		x^ += 126
	}
	#partial switch t {
	case .Bucket:
		slider_w(x, y, 100, &topts.tolerance, 0, 255, "Tolerance", "", "")
		slider_w(x, y, 90, &topts.fill_opacity, 1, 100, "Opacity", "")
		checkbox(x^, y + 1, "Contiguous", &topts.contiguous)
		x^ += 78
		checkbox(x^, y + 1, "All layers", &topts.sample_merged, "Find the fill area from all visible layers")
		x^ += 72
		checkbox(x^, y + 1, "Smooth edge", &topts.antialias)
		x^ += 84
	case .Gradient:
		combo_enum(Rect{x^, y, 80, 14}, GRAD_NAMES, &topts.grad_kind, "Gradient shape")
		x^ += 86
		slider_w(x, y, 90, &topts.fill_opacity, 1, 100, "Opacity", "")
		checkbox(x^, y + 1, "To transparent", &topts.grad_to_clear, "Foreground to transparent instead of foreground to background")
		x^ += 98
		checkbox(x^, y + 1, "Reverse", &topts.grad_reverse)
		x^ += 62
		hint(x, y, "Drag across the canvas")
	case .Picker:
		SIZES := [?]string{"Point", "3 x 3 average", "5 x 5 average", "11 x 11 average"}
		VALS := [?]int{1, 3, 5, 11}
		cur := 0
		for v, i in VALS do if v == topts.pick_size do cur = i
		if nv, ch := combo(Rect{x^, y, 100, 14}, SIZES[:], cur, "Sample size"); ch do topts.pick_size = VALS[nv]
		x^ += 106
		hint(x, y, "Click: foreground   Right click: background   (Alt with any brush)")
	case .Select_Rect, .Select_Ellipse, .Lasso:
		sel_modes(x, y)
		slider_w(x, y, 90, &topts.feather, 0, 200, "Feather", "Soft edge radius", "px")
		hint(x, y, "Shift: add   Alt: subtract   Drag inside a selection to move it")
	case .Wand:
		sel_modes(x, y)
		slider_w(x, y, 100, &topts.tolerance, 0, 255, "Tolerance", "", "")
		checkbox(x^, y + 1, "Contiguous", &topts.contiguous)
		x^ += 78
		checkbox(x^, y + 1, "All layers", &topts.sample_merged)
		x^ += 72
		checkbox(x^, y + 1, "Smooth edge", &topts.antialias)
		x^ += 84
	case .Move:
		hint(x, y, "Drag to move the selection (or the whole layer). Alt: copy. Arrows nudge, Shift x10.")
	case .Transform:
		if xform.active {
			if button(Rect{x^, y, 50, 14}, "Apply", "Enter") do xform_commit()
			if button(Rect{x^ + 54, y, 50, 14}, "Cancel", "Esc") do xform_cancel()
			x^ += 112
		}
		hint(x, y, "Corners: scale (Shift: free)   Edges: stretch   Outside: rotate   Inside: move")
	case .Crop:
		if crop.active {
			if button(Rect{x^, y, 50, 14}, "Crop", "Enter") do crop_commit()
			if button(Rect{x^ + 54, y, 50, 14}, "Cancel", "Esc") do crop.active = false
			x^ += 112
		}
		hint(x, y, "Drag the area to keep (Shift: square). Enter or double click crops.")
	case .Hand:
		hint(x, y, "Drag to pan. Space or middle mouse works with any tool.")
	case .Zoom:
		hint(x, y, "Click to zoom in, right click to zoom out. The mouse wheel works anywhere.")
	}
}

// ---------------------------------------------------------------------------
// Right panel: colour, swatches, layers, navigator
// ---------------------------------------------------------------------------

drag_area :: proc(r: Rect, id: u32) -> (active: bool, fx, fy: f32) {
	if ui_hover(r) && ui.pressed[0] {
		ui.active_id = id
	}
	if ui.active_id == id && ui.down[0] {
		fx = clamp(f32(ui.mx - r.x) / f32(max(r.w - 1, 1)), 0, 1)
		fy = clamp(f32(ui.my - r.y) / f32(max(r.h - 1, 1)), 0, 1)
		active = true
	}
	return
}

hex_buf: Name

panel_right :: proc(r: Rect) {
	ui.layer = 0
	fill_rect(r, C_PANEL)
	vline(r.x, r.y, r.h, C_BORDER)
	area := rect_inset(r, 6)
	x, y := area.x, area.y

	// --- colour picker ---------------------------------------------------
	sv := Rect{x, y, area.w - 18, 92}
	hue := Rect{x + area.w - 12, y, 12, 92}
	rl.DrawRectangleGradientH(sv.x, sv.y, sv.w, sv.h, rl.WHITE, hsv_to_rgb(fg_h, 1, 1))
	rl.DrawRectangleGradientV(sv.x, sv.y, sv.w, sv.h, Color{0, 0, 0, 0}, Color{0, 0, 0, 255})
	outline_rect(sv, C_BORDER)
	if act, fx, fy := drag_area(sv, make_id(sv, "sv")); act {
		set_fg_hsv(fg_h, fx, 1 - fy)
	}
	cx := sv.x + i32(fg_s * f32(sv.w - 1))
	cy := sv.y + i32((1 - fg_v) * f32(sv.h - 1))
	rl.DrawCircleLines(cx, cy, 3, rl.BLACK)
	rl.DrawCircleLines(cx, cy, 4, rl.WHITE)
	for i in 0 ..< 6 {
		seg_h := hue.h / 6
		c0 := hsv_to_rgb(f32(i) * 60, 1, 1)
		c1 := hsv_to_rgb(f32(i + 1) * 60, 1, 1)
		rl.DrawRectangleGradientV(hue.x, hue.y + i32(i) * seg_h, hue.w, seg_h + 1, c0, c1)
	}
	outline_rect(hue, C_BORDER)
	if act, _, fy := drag_area(hue, make_id(hue, "hue")); act {
		set_fg_hsv(fy * 359.9, fg_s, fg_v)
	}
	hy := hue.y + i32(fg_h / 360 * f32(hue.h - 1))
	hline(hue.x - 2, hy, hue.w + 4, rl.WHITE)
	hline(hue.x - 2, hy + 1, hue.w + 4, rl.BLACK)
	y += 96

	fgr := Rect{x, y, 30, 16}
	bgr := Rect{x + 34, y, 30, 16}
	fill_rect(fgr, fg)
	outline_rect(fgr, C_BORDER)
	fill_rect(bgr, bg)
	outline_rect(bgr, C_BORDER)
	if ui_hover(bgr) && ui.pressed[0] {
		run_cmd(.Swap_Colors)
	}
	if icon_button(Rect{x + 68, y, 16, 16}, .Swap, "Swap colors (X)") {
		run_cmd(.Swap_Colors)
	}
	hr := Rect{x + 90, y, 58, 16}
	hid := make_id(hr, "text")
	if ui.focus_id != hid {
		name_set(&hex_buf, color_hex(fg))
	}
	if ch, sub := text_field(hr, &hex_buf, "Hex colour (RRGGBB)"); ch || sub {
		if c, ok := parse_hex(name_str(&hex_buf)); ok {
			set_fg(c)
		}
	}
	h, s, v := int(fg_h + 0.5), int(fg_s * 100 + 0.5), int(fg_v * 100 + 0.5)
	text(x + 152, y + 4, fmt.tprintf("%d %d %d", h, s, v), C_TEXT_DIM)
	y += 20
	rgb := [3]int{int(fg.r), int(fg.g), int(fg.b)}
	names := [3]string{"R", "G", "B"}
	for i in 0 ..< 3 {
		if slider(Rect{x, y + i32(i) * 15, area.w, 13}, &rgb[i], 0, 255, names[i]) {
			set_fg(Color{u8(rgb[0]), u8(rgb[1]), u8(rgb[2]), 255})
		}
	}
	y += 48

	// --- swatches ----------------------------------------------------------
	hline(r.x + 1, y, r.w - 1, C_BORDER)
	y += 4
	text(x, y + 3, "Swatches", C_TEXT_DIM)
	bx := area.x + area.w - 16
	if icon_button(Rect{bx, y, 16, 14}, .Minus, "Remove selected swatch", false, len(swatches) > 1) {
		if swatch_sel >= 0 && swatch_sel < len(swatches) {
			ordered_remove(&swatches, swatch_sel)
			swatch_sel = clamp(swatch_sel, 0, len(swatches) - 1)
		}
	}
	bx -= 17
	if icon_button(Rect{bx, y, 16, 14}, .Plus, "Add foreground colour") {
		append(&swatches, fg)
		swatch_sel = len(swatches) - 1
	}
	bx -= 52
	if button(Rect{bx, y, 50, 14}, "Presets", "Load a swatch set") {
		popup_begin(SWATCH_PRESET_ID, Rect{bx, y, 50, 14}, 110)
		for p in Swatch_Preset {
			popup_item(SWATCH_PRESET_NAMES[p], int(p))
		}
	}
	if ui.popup_result_id == SWATCH_PRESET_ID {
		swatches_set_preset(Swatch_Preset(ui.popup_result_val))
		ui.popup_result_id = 0
	}
	y += 17
	cell: i32 = 13
	cols := max(area.w / cell, 1)
	rows := i32((len(swatches) + int(cols) - 1) / int(cols))
	rows = min(rows, 3)
	pal := Rect{x, y, area.w, max(rows, 1) * cell}
	@(static) pal_scroll: i32
	all_rows := i32((len(swatches) + int(cols) - 1) / int(cols))
	if ui_hover(pal) && ui.wheel != 0 {
		pal_scroll -= i32(ui.wheel) * cell
	}
	pal_scroll = clamp(pal_scroll, 0, max(all_rows * cell - pal.h, 0))
	fill_rect(pal, C_PANEL_DK)
	clip_begin(pal)
	for c, i in swatches {
		sr := Rect{pal.x + i32(i % int(cols)) * cell, pal.y + i32(i / int(cols)) * cell - pal_scroll, cell, cell}
		if sr.y + cell < pal.y || sr.y > pal.y + pal.h do continue
		fill_rect(Rect{sr.x, sr.y, sr.w - 1, sr.h - 1}, c)
		if i == swatch_sel {
			outline_rect(Rect{sr.x, sr.y, sr.w - 1, sr.h - 1}, C_ACCENT)
		}
		if ui_hover(sr) && ui_hover(pal) {
			tooltip_hover(make_id(sr, "sw"), color_hex(c))
			if ui.pressed[0] {
				set_fg(c)
				swatch_sel = i
			} else if ui.pressed[1] {
				bg = c
				swatch_sel = i
			}
		}
	}
	clip_end()
	y += pal.h + 3
	// recently used colours
	text(x, y + 1, "Recent", C_TEXT_DIM)
	rx := x + 38
	for c in recent {
		if rx + 11 > area.x + area.w do break
		sr := Rect{rx, y, 10, 10}
		fill_rect(sr, c)
		outline_rect(sr, C_BORDER)
		if ui_hover(sr) {
			tooltip_hover(make_id(sr, "rc"), color_hex(c))
			if ui.pressed[0] do set_fg(c)
			if ui.pressed[1] do bg = c
		}
		rx += 11
	}
	y += 14

	// --- layers --------------------------------------------------------------
	hline(r.x + 1, y, r.w - 1, C_BORDER)
	y += 4
	nav_h: i32 = show_navigator ? 104 : 0
	lr := Rect{x, y, area.w, area.y + area.h - y - nav_h}
	panel_layers(lr)
	if show_navigator {
		y = lr.y + lr.h + 4
		hline(r.x + 1, y - 2, r.w - 1, C_BORDER)
		panel_navigator(Rect{x, y, area.w, area.y + area.h - y})
	}
}

// ---------------------------------------------------------------------------
// Layers panel
// ---------------------------------------------------------------------------

THUMB_W :: 36
THUMB_H :: 24

Thumb :: struct {
	tex:  rl.Texture2D,
	used: bool,
}

thumbs: [dynamic]Thumb // 2 per layer: pixels, mask
thumbs_doc: ^Doc
thumbs_t: f64

thumbs_refresh :: proc(d: ^Doc) {
	if !(d.thumb_dirty || thumbs_doc != d || len(thumbs) < len(d.layers) * 2) {
		return
	}
	if (stroke.active || drag.active) && ui.time - thumbs_t < 0.3 {
		return
	}
	thumbs_t = ui.time
	d.thumb_dirty = false
	thumbs_doc = d
	for len(thumbs) < len(d.layers) * 2 {
		img := rl.GenImageColor(THUMB_W, THUMB_H, rl.BLANK)
		t := rl.LoadTextureFromImage(img)
		rl.UnloadImage(img)
		rl.SetTextureFilter(t, .BILINEAR)
		append(&thumbs, Thumb{tex = t})
	}
	buf: [THUMB_W * THUMB_H]Color
	for &l, li in d.layers {
		for k in 0 ..< 2 {
			if k == 1 && !l.has_mask do continue
			g := k == 0 ? &l.pix : &l.mask
			empty := k == 0 ? Color{} : MASK_EMPTY
			// fit the image into the thumbnail, letterboxed
			sc := min(f32(THUMB_W) / f32(d.w), f32(THUMB_H) / f32(d.h))
			tw, th := f32(d.w) * sc, f32(d.h) * sc
			ox, oy := (f32(THUMB_W) - tw) / 2, (f32(THUMB_H) - th) / 2
			for ty in 0 ..< THUMB_H {
				for tx in 0 ..< THUMB_W {
					fx := (f32(tx) + 0.5 - ox) / sc
					fy := (f32(ty) + 0.5 - oy) / sc
					c := Color{}
					if fx >= 0 && fy >= 0 && fx < f32(d.w) && fy < f32(d.h) {
						// 2x2 samples for a little smoothing
						acc: [4]f32
						for s in 0 ..< 4 {
							sx := clamp(int(fx + (f32(s % 2) - 0.5) / sc * 0.5), 0, d.w - 1)
							sy := clamp(int(fy + (f32(s / 2) - 0.5) / sc * 0.5), 0, d.h - 1)
							p := tiles_get(g, sx, sy, empty)
							a := f32(p.a)
							acc += [4]f32{f32(p.r) * a, f32(p.g) * a, f32(p.b) * a, a}
						}
						if acc[3] > 0 {
							c = Color{u8(acc[0] / acc[3]), u8(acc[1] / acc[3]), u8(acc[2] / acc[3]), u8(acc[3] / 4)}
						}
					}
					buf[ty * THUMB_W + tx] = c
				}
			}
			rl.UpdateTexture(thumbs[li * 2 + k].tex, &buf[0])
		}
	}
}

LAYER_ROW_H :: 28
layers_scroll: i32

panel_layers :: proc(r: Rect) {
	d := doc
	l := &d.layers[d.active_layer]
	thumbs_refresh(d)
	x, y := r.x, r.y
	// active layer blend + opacity
	if nv, ch := combo(Rect{x, y, 86, 14}, blend_names_slice(), int(l.blend), "Blend mode"); ch {
		history_push(d)
		l.blend = Blend(nv)
		doc_touch_all(d)
	}
	op := int(l.opacity) * 100 / 255
	orr := Rect{x + 90, y, r.w - 90, 14}
	@(static) op_pushed: bool
	if ui_hover(orr) && (ui.pressed[0] || ui.wheel != 0) && !op_pushed {
		history_push(d)
		op_pushed = true
	}
	if slider(orr, &op, 0, 100, "Opacity", "Layer opacity", "%") {
		l.opacity = u8(op * 255 / 100)
		doc_touch_all(d)
	}
	if op_pushed && !ui.down[0] && ui.wheel == 0 {
		op_pushed = false
	}
	y += 18

	// buttons along the bottom
	by := r.y + r.h - 16
	list := Rect{x, y, r.w, by - y - 3}
	bx := x
	b :: proc(x: ^i32, y: i32) -> Rect {
		rc := Rect{x^, y, 22, 16}
		x^ += 23
		return rc
	}
	if badge_button(b(&bx, by), .Layer, true, "New layer (Ctrl+Shift+N)") do run_cmd(.Layer_New)
	if icon_button(b(&bx, by), .Copy, "Duplicate layer") do run_cmd(.Layer_Dup)
	if icon_button(b(&bx, by), .Trash, "Delete layer", false, len(d.layers) > 1) do run_cmd(.Layer_Del)
	if icon_button(b(&bx, by), .Up, "Move layer up", false, d.active_layer < len(d.layers) - 1) do run_cmd(.Layer_Up)
	if icon_button(b(&bx, by), .Down, "Move layer down", false, d.active_layer > 0) do run_cmd(.Layer_Down)
	if icon_button(b(&bx, by), .Merge, "Merge down (Ctrl+E)", false, d.active_layer > 0) do run_cmd(.Layer_Merge)
	if l.has_mask {
		if icon_button(b(&bx, by), .Mask, "Delete mask", true) do run_cmd(.Mask_Delete)
	} else {
		if icon_button(b(&bx, by), .Mask, d.sel != nil ? "Add mask from selection" : "Add layer mask") {
			run_cmd(d.sel != nil ? .Mask_From_Sel : .Mask_Add)
		}
	}

	// list, top layer first
	fill_rect(list, C_PANEL_DK)
	n := i32(len(d.layers))
	content := n * LAYER_ROW_H
	if ui_hover(list) && ui.wheel != 0 {
		layers_scroll -= i32(ui.wheel) * LAYER_ROW_H
	}
	layers_scroll = clamp(layers_scroll, 0, max(content - list.h, 0))
	clip_begin(list)
	for i in 0 ..< n {
		li := int(n - 1 - i)
		ry := list.y + i * LAYER_ROW_H - layers_scroll
		if ry + LAYER_ROW_H < list.y || ry > list.y + list.h do continue
		ly := &d.layers[li]
		row := Rect{list.x, ry, list.w, LAYER_ROW_H}
		active := li == d.active_layer
		if active {
			fill_rect(row, C_ACTIVE)
		} else if ui_hover(row) && ui_hover(list) {
			fill_rect(row, C_PANEL_LT)
		}
		hline(row.x, ry + LAYER_ROW_H - 1, row.w, C_BORDER)
		eye := Rect{row.x + 2, ry + 8, 12, 12}
		icon(.Eye, eye.x, eye.y, ly.visible ? C_TEXT : Color{80, 80, 96, 255})
		th := Rect{row.x + 17, ry + 2, THUMB_W, THUMB_H}
		draw_checker(th, 3)
		if li * 2 < len(thumbs) {
			rl.DrawTexture(thumbs[li * 2].tex, th.x, th.y, rl.WHITE)
		}
		outline_rect(rect_inset(th, -1), active && !d.edit_mask ? rl.WHITE : C_BORDER)
		tx := th.x + THUMB_W + 4
		mr := Rect{tx, ry + 2, THUMB_W, THUMB_H}
		if ly.has_mask {
			if li * 2 + 1 < len(thumbs) {
				rl.DrawTexture(thumbs[li * 2 + 1].tex, mr.x, mr.y, rl.WHITE)
			}
			if !ly.mask_on {
				rl.DrawLine(mr.x, mr.y, mr.x + mr.w, mr.y + mr.h, C_DANGER)
			}
			outline_rect(rect_inset(mr, -1), active && d.edit_mask ? rl.WHITE : C_BORDER)
			tx += THUMB_W + 4
		}
		name_r := Rect{tx, ry + 3, row.x + row.w - tx - 2, 10}
		text_clipped(name_r, name_str(&ly.name), ly.visible ? C_TEXT : C_TEXT_DIM)
		info := ""
		if ly.blend != .Normal do info = BLEND_NAMES[ly.blend]
		if ly.opacity < 255 do info = fmt.tprintf("%s %d%%", info, int(ly.opacity) * 100 / 255)
		text_clipped(Rect{tx, ry + 15, name_r.w - 28, 10}, info, C_TEXT_DIM)
		ix := row.x + row.w - 14
		if ly.locked {
			icon(.Lock, ix, ry + 14, C_ACCENT)
			ix -= 13
		}
		if ly.lock_alpha {
			icon(.Lock_Alpha, ix, ry + 14, C_ACCENT)
		}
		if ui_hover(row) && ui_hover(list) && ui.pressed[0] {
			switch {
			case in_rect(eye, ui.mx, ui.my):
				history_push(d)
				ly.visible = !ly.visible
				doc_touch_all(d)
			case ly.has_mask && in_rect(mr, ui.mx, ui.my):
				d.active_layer = li
				d.edit_mask = true
				if ui.shift {
					history_push(d)
					ly.mask_on = !ly.mask_on
					doc_touch_all(d)
				}
			case:
				if d.active_layer != li do tools_commit_pending()
				d.active_layer = li
				d.edit_mask = false
				if ui.dbl_click {
					dialog_open(.Layer_Props)
				}
			}
		}
	}
	clip_end()
	outline_rect(list, C_BORDER)
}

// ---------------------------------------------------------------------------
// Navigator: whole image with the visible area; click or drag to move the view
// ---------------------------------------------------------------------------

panel_navigator :: proc(r: Rect) {
	d := doc
	fill_rect(r, C_PANEL_DK)
	outline_rect(r, C_BORDER)
	if tex_canvas.id == 0 || tex_doc != d {
		return
	}
	z := min(f32(r.w - 6) / f32(d.w), f32(r.h - 6) / f32(d.h))
	w, h := f32(d.w) * z, f32(d.h) * z
	dst := rl.Rectangle{math.floor(f32(r.x) + (f32(r.w) - w) / 2), math.floor(f32(r.y) + (f32(r.h) - h) / 2), w, h}
	draw_canvas_bg(dst)
	rl.DrawTexturePro(tex_canvas, {0, 0, f32(d.w), f32(d.h)}, dst, {}, 0, rl.WHITE)
	vp := canvas_vp
	vx := (f32(vp.x) - d.ox) / d.zoom
	vy := (f32(vp.y) - d.oy) / d.zoom
	vw := f32(vp.w) / d.zoom
	vh := f32(vp.h) / d.zoom
	vr := rl.Rectangle{dst.x + vx * z, dst.y + vy * z, vw * z, vh * z}
	clip_begin(r)
	rl.DrawRectangleLinesEx(vr, 1, C_ACCENT)
	clip_end()
	if act, fx, fy := drag_area(r, make_id(r, "nav")); act {
		// centre the view on the clicked point
		px := (f32(r.x) + fx * f32(r.w - 1) - dst.x) / z
		py := (f32(r.y) + fy * f32(r.h - 1) - dst.y) / z
		d.ox = f32(vp.x) + f32(vp.w) / 2 - px * d.zoom
		d.oy = f32(vp.y) + f32(vp.h) / 2 - py * d.zoom
	}
}

// ---------------------------------------------------------------------------
// Brush preview (Brush Settings dialog): paints a sample stroke off-screen.
// ---------------------------------------------------------------------------

preview_doc: ^Doc
preview_tex: rl.Texture2D
preview_brush: Brush
preview_tool: Tool
preview_color: Color

brush_preview :: proc(r: Rect, t: Tool) {
	w, h := int(r.w), int(r.h)
	b := brushes[t]
	if preview_doc == nil || preview_doc.w != w || preview_doc.h != h || preview_brush != b || preview_tool != t || preview_color != fg {
		preview_brush, preview_tool, preview_color = b, t, fg
		if preview_doc != nil {
			doc_destroy(preview_doc)
		}
		if preview_tex.id != 0 && (int(preview_tex.width) != w || int(preview_tex.height) != h) {
			rl.UnloadTexture(preview_tex)
			preview_tex = {}
		}
		if preview_tex.id == 0 {
			img := rl.GenImageColor(i32(w), i32(h), rl.BLANK)
			preview_tex = rl.LoadTextureFromImage(img)
			rl.UnloadImage(img)
		}
		pd := doc_new_filled(w, h, "preview", Color{250, 248, 242, 255})
		// a few vertical colour bands so blending tools have something to work on
		if t == .Smudge || t == .Blur || t == .Oil || t == .Dodge || t == .Clone || t == .Eraser {
			bands := [?]Color{{200, 60, 50, 255}, {240, 200, 60, 255}, {60, 110, 190, 255}, {40, 40, 40, 255}}
			for y in 0 ..< h {
				for x in 0 ..< w {
					tiles_set(&pd.layers[0].pix, x, y, bands[(x * len(bands)) / w], {})
				}
			}
		}
		preview_doc = pd
		// run a sample stroke with the real engine on the preview document
		saved_doc := doc
		saved_brush := brushes[t]
		saved_stroke_mask, saved_mw, saved_mh := stroke_mask, stroke_mask_w, stroke_mask_h
		saved_src, saved_src_set, saved_off, saved_realign := clone_src_pt, clone_src_set, clone_off_saved, clone_realign
		stroke_mask, stroke_mask_w, stroke_mask_h = nil, 0, 0
		doc = pd
		pb := &brushes[t]
		pb.size = min(pb.size, h * 2 / 3)
		pb.smoothing = 0
		if t == .Clone {
			clone_src_pt = Vec2{f32(w) * 0.1, f32(h) * 0.5}
			clone_src_set, clone_realign = true, true
		}
		col := t == .Dodge ? fg : fg
		steps := 60
		for i in 0 ..= steps {
			u := f32(i) / f32(steps)
			p := Vec2{f32(w) * (0.08 + 0.84 * u), f32(h) * (0.5 + 0.28 * math.sin(u * math.TAU))}
			if t == .Clone {
				p.x = f32(w) * (0.3 + 0.6 * u)
			}
			if i == 0 {
				if !stroke_begin(t, p, col) do break
			} else {
				stroke_move(p)
			}
		}
		stroke_end()
		delete(stroke_mask)
		stroke_mask, stroke_mask_w, stroke_mask_h = saved_stroke_mask, saved_mw, saved_mh
		clone_src_pt, clone_src_set, clone_off_saved, clone_realign = saved_src, saved_src_set, saved_off, saved_realign
		brushes[t] = saved_brush
		doc = saved_doc
		doc_refresh_comp(pd)
		rl.UpdateTexture(preview_tex, raw_data(pd.comp))
	}
	draw_checker(r, 4)
	rl.DrawTexture(preview_tex, r.x, r.y, rl.WHITE)
	outline_rect(r, C_BORDER)
}

// ---------------------------------------------------------------------------
// Status bar
// ---------------------------------------------------------------------------

panel_status :: proc(r: Rect) {
	ui.layer = 0
	d := doc
	fill_rect(r, C_PANEL_DK)
	hline(r.x, r.y, r.w, C_BORDER)
	ty := r.y + 3
	if status_t > 0 {
		text(r.x + 6, ty, name_str(&status_msg), C_ACCENT)
	} else {
		text(r.x + 6, ty, TOOL_NAMES[cur_tool], C_TEXT_DIM)
	}
	x := r.x + 280
	if hover_valid && pt_in_doc(hover_pt) {
		q := ipt(hover_pt)
		doc_refresh_comp(d)
		c := d.comp[q.y * d.w + q.x]
		textf(x, ty, C_TEXT, "%d, %d", q.x, q.y)
		swr := Rect{x + 64, r.y + 3, 8, 8}
		fill_rect(swr, c)
		outline_rect(swr, C_BORDER)
		text(x + 76, ty, color_hex(c), C_TEXT_DIM)
	}
	if d.sel != nil {
		b := d.sel.bbox
		textf(x + 130, ty, C_TEXT_DIM, "Sel %dx%d", b.x1 - b.x0, b.y1 - b.y0)
	}
	l := &d.layers[d.active_layer]
	target := d.edit_mask ? fmt.tprintf("%s (mask)", name_str(&l.name)) : name_str(&l.name)
	info := fmt.tprintf("%s   %dx%d   %d%%", target, d.w, d.h, int(d.zoom * 100 + 0.5))
	text(r.x + r.w - text_w(info) - 8, ty, info, C_TEXT_DIM)
}
