package pangolin

import "core:fmt"
import "core:math"

MENU_H :: 24
OPT_H :: 30
TAB_H :: 26
STATUS_H :: 20
TOOLBAR_W :: 148
RIGHT_W :: 236

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
	groups_bar := Rect{0, H - GROUPS_BAR_H, W, GROUPS_BAR_H}
	if canvas_mode {
		body.h += STATUS_H - GROUPS_BAR_H
	}

	right, toolbar, tabs: Rect
	if !canvas_mode {
		right = cut_right(&body, RIGHT_W)
		toolbar = cut_left(&body, TOOLBAR_W)
		tabs = cut_top(&body, TAB_H)
	}
	viewport := body

	// keep the picture where it was on screen when the viewport changes size
	@(static) prev_mode := false
	@(static) prev_vp: Rect
	if canvas_mode != prev_mode && doc.view_init && prev_vp.w > 0 {
		doc.ox += f32(viewport.x + viewport.w / 2 - prev_vp.x - prev_vp.w / 2)
		doc.oy += f32(viewport.y + viewport.h / 2 - prev_vp.y - prev_vp.h / 2)
	}
	prev_mode, prev_vp = canvas_mode, viewport

	// canvas first so that panels can overdraw its borders
	canvas_update(viewport)
	render_canvas(viewport)

	if canvas_mode {
		panel_groups_bar(groups_bar)
	} else {
		panel_tabs(tabs)
		panel_toolbar(toolbar)
		panel_right(right)
		panel_status(status)
	}
	panel_options(optbar)
	panel_menubar(menubar)
}

// ---------------------------------------------------------------------------
// Menu bar
// ---------------------------------------------------------------------------

MENU_TITLES := [?]string{"File", "Edit", "Image", "Adjust", "Filter", "Layer", "Select", "View", "Workspaces", "Help"}

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
		item("Grid", cmd = .Toggle_Grid, checked = show_grid)
		item("Snap to Grid", cmd = .Toggle_Snap, checked = snap_grid)
		item("Grid Settings...", cmd = .Grid_Settings)
		item("Navigator", cmd = .Toggle_Navigator, checked = show_navigator)
		item("Canvas Mode", cmd = .Toggle_Canvas_Mode, checked = canvas_mode)
		item("Seamless Mode", cmd = .Toggle_Seamless, checked = seamless_mode)
		item("Cycle Transparency Display", cmd = .Cycle_Canvas_Bg)
		popup_sep()
		item("Preferences...", cmd = .Preferences)
	case 8:
		ws_refresh()
		for e, i in ws_entries {
			if i == len(WS_BUILTIN_NAMES) do popup_sep()
			item(e.name, cmd = Cmd(int(Cmd.Ws_First) + i), checked = e.name == ws_current)
		}
		popup_sep()
		item("Manage Workspaces...", cmd = .Ws_Manage)
		item("Import Workspace...", cmd = .Ws_Import)
		item("Export Workspace...", cmd = .Ws_Export)
	case 9:
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
	logo_draw(r.x + 7, r.y + (r.h - LOGO_SIZE) / 2, 1)
	x := r.x + 30
	for title, i in MENU_TITLES {
		w := text_w(title) + 18
		br := Rect{x, r.y, w, r.h - 1}
		id := make_id(br, title)
		hover := ui_hover(br)
		is_open := popup.open && popup.menu_idx == i
		if hover || is_open {
			pill := Rect{br.x + 1, br.y + 3, br.w - 2, br.h - 6}
			draw_rrect(f32(pill.x), f32(pill.y), f32(pill.w), f32(pill.h), RADIUS, is_open ? C_ACTIVE : C_HOVER)
		}
		text(br.x + 9, br.y + (br.h - FONT_CAP) / 2, title, hover || is_open ? WHITE : C_TEXT)
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
	tx := r.x + r.w - text_w(t) - 12
	text(tx, r.y + (r.h - 1 - FONT_CAP) / 2, t, C_TEXT_DIM)
	if icon_button(Rect{tx - 28, r.y + 3, 20, r.h - 7}, .Canvas_Mode, "Canvas mode (Tab)", canvas_mode) {
		run_cmd(.Toggle_Canvas_Mode)
	}
	if icon_button(Rect{tx - 52, r.y + 3, 20, r.h - 7}, .Seamless, "Seamless mode", seamless_mode) {
		run_cmd(.Toggle_Seamless)
	}
}

// ---------------------------------------------------------------------------
// Tabs
// ---------------------------------------------------------------------------

panel_tabs :: proc(r: Rect) {
	ui.layer = 0
	fill_rect(r, C_PANEL_DK)
	hline(r.x, r.y + r.h - 1, r.w, C_BORDER)
	x := r.x + 6
	close_idx := -1
	switch_idx := -1
	clip_begin(r)
	for d, i in docs {
		name := doc_display_name(d)
		w := text_w(name) + 40
		tr := Rect{x, r.y + 4, w, r.h - 4}
		if x + w > r.x + r.w - 28 {
			break
		}
		active := d == doc
		hover := ui_hover(tr)
		// rounded on top only: the lower corners run off the clip
		if active {
			draw_rrect(f32(tr.x), f32(tr.y), f32(tr.w), f32(tr.h + 6), 5, C_VIEWPORT)
			draw_rrect(f32(tr.x + 6), f32(tr.y), f32(tr.w - 12), 2, 1, C_ACCENT)
		} else if hover {
			draw_rrect(f32(tr.x), f32(tr.y + 2), f32(tr.w), f32(tr.h + 6), 5, C_PANEL)
		}
		text(tr.x + 10, tr.y + (tr.h - FONT_CAP) / 2, name, active ? C_TEXT : C_TEXT_DIM)
		cr := Rect{tr.x + tr.w - 18, tr.y + (tr.h - 12) / 2, 12, 12}
		chover := ui_hover(cr)
		if chover {
			draw_rrect(f32(cr.x), f32(cr.y), 12, 12, 3, C_HOVER)
		}
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
		x += w + 2
	}
	clip_end()
	if close_idx >= 0 {
		request_close(docs[close_idx])
	} else if switch_idx >= 0 {
		switch_doc(switch_idx)
	}
	if icon_button(Rect{r.x + r.w - 24, r.y + 5, 18, 17}, .Plus, "New painting") {
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
	.Text           = .Text,
	.Select_Rect    = .Sel_Rect,
	.Select_Ellipse = .Sel_Ellipse,
	.Lasso          = .Lasso,
	.Wand           = .Wand,
	.Move           = .Move,
	.Transform      = .Transform,
	.Crop           = .Crop,
	.Hand           = .Hand,
	.Zoom           = .Zoom,
	.Line           = .Line,
}

panel_toolbar :: proc(r: Rect) {
	ui.layer = 0
	fill_rect(r, C_PANEL)
	vline(r.x + r.w - 1, r.y, r.h, C_BORDER)
	t := eff_tool()
	y := r.y + 8
	BTN :: 24
	PITCH :: BTN + 2
	COLS :: 5
	gx := r.x + 10
	rem_g, rem_t := -1, -1
	cur_group := current_group()
	for &g, gi in tool_groups {
		// header band: the name on the left, the hotkey as a keycap on the right
		// (click the keycap for options; right-click the header for rename / remove)
		top := y
		y += 4
		title := group_title(&g)
		clip_begin(Rect{r.x + 4, top, r.w - 9, 28})
		draw_rrect(f32(r.x + 4), f32(top), f32(r.w - 9), 40, 5, C_PANEL_DK)
		clip_end()
		waiting := group_key_wait == gi
		label := waiting ? "..." : (g.key == .KEY_NULL ? "-" : key_name(g.key))
		kw := keycap_w(label)
		badge := Rect{r.x + r.w - 11 - kw, y + 1, kw, 18}
		clip_begin(Rect{r.x + 11, y, badge.x - r.x - 15, 20})
		text(r.x + 12, y + (20 - FONT_CAP) / 2, title, g.pen_eraser ? C_ACCENT : C_TEXT)
		clip_end()
		bid := make_id(badge, "grpbadge")
		clicked, _, badge_hover := button_behavior(bid, badge, "Group hotkey (click for options)")
		keycap(badge, label, waiting, badge_hover)
		if clicked {
			popup_begin(bid, badge, 120)
			popup_item("Assign hotkey...", 0)
			popup_item("Rename...", 3)
			popup_item(g.pen_eraser ? "Pen eraser: off" : "Use for pen eraser", 2)
			popup_item("Remove group", 1)
		}
		if ui.popup_result_id == bid {
			switch ui.popup_result_val {
			case 0:
				group_key_wait = gi
				set_statusf("Press a key for this tool group (Esc cancels, Backspace clears)")
			case 2:
				on := !g.pen_eraser
				for &o in tool_groups do o.pen_eraser = false
				g.pen_eraser = on
				set_statusf(on ? "The pen's eraser end now uses this group's current tool" : "Pen eraser group cleared")
			case 3:
				group_rename_open(gi)
			case:
				rem_g = gi
			}
			ui.popup_result_id = 0
		}
		// right-click anywhere on the header for a menu (opened on release,
		// since a popup opened on the press would be closed by that same click)
		hdr := Rect{r.x + 5, top, r.w - 11, 28}
		hid := make_id(hdr, "grphdr")
		if ui_hover(hdr) && ui.released[1] && !popup.open {
			popup_begin(hid, Rect{ui.mx, ui.my, 1, 1}, 110)
			popup_item("Rename...", 3)
			popup_item("Remove group", 1)
		}
		if ui.popup_result_id == hid {
			if ui.popup_result_val == 3 {
				group_rename_open(gi)
			} else {
				rem_g = gi
			}
			ui.popup_result_id = 0
		}
		is_colors := len(g.colors) > 0
		is_blends := len(g.blends) > 0
		is_tools := len(g.tools) > 0
		n := is_colors ? len(g.colors) : (is_blends ? len(g.blends) : len(g.tools))
		hline(r.x + 5, top + 28, r.w - 11, C_RING_HI)
		y = top + 34
		for tool, ti in g.tools {
			br := Rect{gx + i32(ti % COLS) * PITCH, y + i32(ti / COLS) * PITCH, BTN, BTN}
			// the pen-eraser group keeps its own selection, separate from the pen tip's tool
			if icon_button(br, TOOL_ICONS[tool], TOOL_NAMES[tool], g.pen_eraser ? g.last == tool : t == tool && cur_group == gi) {
				g.last = tool
				if !g.pen_eraser do select_tool_in_group(tool, gi)
			} else if ui_hover(br) && ui.pressed[1] && !popup.open {
				rem_g, rem_t = gi, ti
			}
		}
		for c, ci in g.colors {
			br := Rect{gx + i32(ci % COLS) * PITCH, y + i32(ci / COLS) * PITCH, BTN, BTN}
			clicked, _, hover := button_behavior(make_id(br, "grpcol"), br, color_hex(c))
			draw_rrect(f32(br.x), f32(br.y), f32(br.w), f32(br.h), RADIUS, c)
			same := c.r == fg.r && c.g == fg.g && c.b == fg.b
			linked := color_link_g == gi && color_link_i == ci
			draw_rrect_outline(f32(br.x), f32(br.y), f32(br.w), f32(br.h), RADIUS, linked ? C_ACCENT : (same ? WHITE : (hover ? C_RING_HI : C_RING)))
			if linked {
				draw_rrect_outline(f32(br.x - 1), f32(br.y - 1), f32(br.w + 2), f32(br.h + 2), RADIUS + 1, C_ACCENT)
			}
			if clicked {
				color_link_set(gi, ci)
			} else if hover && ui.pressed[1] && !popup.open {
				rem_g, rem_t = gi, ci
			}
		}
		// blend modes are listed one per row, the active one highlighted
		BROW :: 22
		for b, bi in g.blends {
			br := Rect{gx, y + i32(bi) * BROW, r.w - 20, 20}
			clicked, held, hover := button_behavior(make_id(br, "grpblend"), br, "Brush blend mode (right-click to remove)")
			fgc := ctl_state(br, hover, held, b == brush_blend, true)
			text(br.x + 8, br.y + (br.h - FONT_CAP) / 2, BLEND_NAMES[b], fgc)
			if clicked {
				brush_blend = b
			} else if hover && ui.pressed[1] && !popup.open {
				rem_g, rem_t = gi, bi
			}
		}
		pr := Rect{gx + i32(n % COLS) * PITCH, y + i32(n / COLS) * PITCH, BTN, BTN}
		if is_blends {
			pr = Rect{gx, y + i32(n) * BROW, BTN, BTN}
		}
		can_add := is_colors ? n < 48 : (is_blends ? n < len(Blend) : n < len(Tool))
		if can_add {
			pid := make_id(pr, "grpadd")
			tip := "Add a tool, colours or brush blend modes to this group (right-click an item to remove it)"
			if icon_button(pr, .Plus, tip) {
				popup_begin(pid, pr)
				popup_grid(5)
				any_section := false
				if !is_colors && !is_blends {
					for tool in Tool {
						if !tool_group_has(&g, tool) {
							popup_item_icon(TOOL_NAMES[tool], int(tool), TOOL_ICONS[tool])
						}
					}
					any_section = true
				}
				if !is_tools && !is_blends {
					if any_section do popup_sep()
					popup_item_swatch("Foreground colour", 100, fg)
					popup_item("All current swatches", 101)
					for p in Swatch_Preset {
						popup_item_palette(SWATCH_PRESET_NAMES[p], 200 + int(p), p)
					}
					any_section = true
				}
				if !is_tools && !is_colors {
					if any_section do popup_sep()
					for b in Blend {
						if !blend_in(g.blends[:], b) {
							popup_item_half(BLEND_NAMES[b], 300 + int(b))
						}
					}
				}
			}
			if ui.popup_result_id == pid {
				v := ui.popup_result_val
				switch {
				case v < 100:
					append(&g.tools, Tool(v))
				case v == 100:
					append(&g.colors, fg)
				case v == 101:
					append(&g.colors, ..swatches[:])
				case v >= 300:
					append(&g.blends, Blend(v - 300))
				case:
					append(&g.colors, ..swatch_preset_colors(Swatch_Preset(v - 200)))
				}
				ui.popup_result_id = 0
			}
		}
		if is_blends {
			y += i32(n) * BROW + PITCH + 4
		} else {
			y += i32(n / COLS + 1) * PITCH + 4
		}
		draw_rrect_outline(f32(r.x + 4), f32(top), f32(r.w - 9), f32(y - top), 5, C_RING_HI)
		y += 6
	}
	if rem_g >= 0 {
		color_link_clear() // indices shift
		if rem_t >= 0 {
			rg := &tool_groups[rem_g]
			if len(rg.colors) > 0 {
				ordered_remove(&rg.colors, rem_t)
			} else if len(rg.blends) > 0 {
				ordered_remove(&rg.blends, rem_t)
			} else {
				ordered_remove(&rg.tools, rem_t)
			}
		} else {
			group_save_brushes()
			active_group = -1 // indices shift
			delete(tool_groups[rem_g].tools)
			delete(tool_groups[rem_g].colors)
			delete(tool_groups[rem_g].blends)
			ordered_remove(&tool_groups, rem_g)
			group_key_wait = -1
		}
	}
	if len(tool_groups) < MAX_TOOL_GROUPS {
		if button(Rect{r.x + 6, y, r.w - 13, 18}, "+ New Group", "Add an empty tool group") {
			append(&tool_groups, Tool_Group{})
		}
	}
	y += 18
	// foreground / background chips below the groups
	cy := y + 20
	hline(r.x + 10, cy - 7, r.w - 21, C_RING_HI)
	bgr := Rect{r.x + 22, cy + 14, 24, 24}
	fgr := Rect{r.x + 9, cy, 24, 24}
	draw_rrect(f32(bgr.x), f32(bgr.y), 24, 24, 4, bg)
	draw_rrect_outline(f32(bgr.x), f32(bgr.y), 24, 24, 4, ui_hover(bgr) && !ui_hover(fgr) ? WHITE : C_RING_HI)
	draw_shadow(f32(fgr.x), f32(fgr.y + 1), 24, 24, 4, 5, Color{0, 0, 0, 140})
	draw_rrect(f32(fgr.x), f32(fgr.y), 24, 24, 4, fg)
	draw_rrect_outline(f32(fgr.x), f32(fgr.y), 24, 24, 4, WHITE)
	if ui_hover(bgr) && !ui_hover(fgr) {
		tooltip_hover(make_id(bgr, "bgchip"), "Background colour (click to swap)")
		if ui.pressed[0] {
			run_cmd(.Swap_Colors)
		}
	}
}

// ---------------------------------------------------------------------------
// Tool options bar
// ---------------------------------------------------------------------------

panel_options :: proc(r: Rect) {
	ui.layer = 0
	fill_rect(r, C_PANEL)
	hline(r.x, r.y + r.h - 1, r.w, C_BORDER)
	x := r.x + 8
	y := r.y + (r.h - 1 - 14) / 2
	t := eff_tool()
	if paint_tool(t) {
		options_brush(&x, y, t)
		if t == .Line do options_line(&x, y)
	} else {
		options_other(&x, y, t)
	}
	// right side: layer state
	l := &doc.layers[doc.active_layer]
	rx := r.x + r.w - 8
	rx -= 18
	if icon_button(Rect{rx, y, 18, 14}, .Lock_Alpha, "Lock layer transparency (/)", l.lock_alpha) {
		run_cmd(.Layer_Lock_Alpha)
	}
	if l.has_mask {
		rx -= 20
		if icon_button(Rect{rx, y, 18, 14}, .Mask, "Paint on the layer mask (\\)", doc.edit_mask) {
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
	slider_w(x, y, 84, &b.opacity, 1, 100, "Opacity", "Opacity (Shift+number keys)")
	#partial switch t {
	case .Brush, .Eraser, .Clone, .Line:
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
	case .Text:
		options_text(x, y)
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

// Section heading: a dim caption with a hairline running to the right edge (minus `reserve`).
section_header :: proc(x, y, w: i32, title: string, reserve: i32 = 0) {
	tw := text_w(title)
	text(x, y + 4, title, C_TEXT_DIM)
	hline(x + tw + 8, y + 8, w - tw - 8 - reserve, C_RING)
}

panel_right :: proc(r: Rect) {
	ui.layer = 0
	fill_rect(r, C_PANEL)
	vline(r.x, r.y, r.h, C_BORDER)
	area := Rect{r.x + 10, r.y + 6, r.w - 20, r.h - 10}
	x, y := area.x, area.y

	// --- colour picker ---------------------------------------------------
	if color_linked() != nil {
		section_header(x, y, area.w, "Color - editing toolbar colour")
	} else {
		section_header(x, y, area.w, "Color")
	}
	y += 20
	SV_H :: 100
	sv := Rect{x, y, area.w - 20, SV_H}
	hue := Rect{x + area.w - 12, y, 12, SV_H}
	draw_gradient(f32(sv.x), f32(sv.y), f32(sv.w), f32(sv.h), WHITE, hsv_to_rgb(fg_h, 1, 1), false)
	draw_gradient(f32(sv.x), f32(sv.y), f32(sv.w), f32(sv.h), Color{0, 0, 0, 0}, Color{0, 0, 0, 255})
	outline_rect(sv, C_RING_HI)
	if act, fx, fy := drag_area(sv, make_id(sv, "sv")); act {
		picker_set_fg_hsv(fg_h, fx, 1 - fy)
	}
	cx := sv.x + i32(fg_s * f32(sv.w - 1))
	cy := sv.y + i32((1 - fg_v) * f32(sv.h - 1))
	draw_circle_outline(f32(cx) + 0.5, f32(cy) + 0.5, 4, BLACK)
	draw_circle_outline(f32(cx) + 0.5, f32(cy) + 0.5, 5, WHITE)
	for i in 0 ..< 6 {
		seg_h := hue.h / 6
		c0 := hsv_to_rgb(f32(i) * 60, 1, 1)
		c1 := hsv_to_rgb(f32(i + 1) * 60, 1, 1)
		draw_gradient(f32(hue.x), f32(hue.y + i32(i) * seg_h), f32(hue.w), f32(seg_h + 1), c0, c1)
	}
	outline_rect(hue, C_RING_HI)
	if act, _, fy := drag_area(hue, make_id(hue, "hue")); act {
		picker_set_fg_hsv(fy * 359.9, fg_s, fg_v)
	}
	hy := hue.y + i32(fg_h / 360 * f32(hue.h - 1))
	draw_rrect(f32(hue.x - 3), f32(hy - 2), f32(hue.w + 6), 5, 2, WHITE)
	draw_rrect_outline(f32(hue.x - 3), f32(hy - 2), f32(hue.w + 6), 5, 2, Color{0, 0, 0, 160})
	y += SV_H + 8

	fgr := Rect{x, y, 30, 18}
	bgr := Rect{x + 34, y, 30, 18}
	draw_rrect(f32(fgr.x), f32(fgr.y), 30, 18, RADIUS, fg)
	draw_rrect_outline(f32(fgr.x), f32(fgr.y), 30, 18, RADIUS, C_RING_HI)
	draw_rrect(f32(bgr.x), f32(bgr.y), 30, 18, RADIUS, bg)
	draw_rrect_outline(f32(bgr.x), f32(bgr.y), 30, 18, RADIUS, C_RING_HI)
	if ui_hover(bgr) && ui.pressed[0] {
		run_cmd(.Swap_Colors)
	}
	if icon_button(Rect{x + 68, y, 18, 18}, .Swap, "Swap colors (X)") {
		run_cmd(.Swap_Colors)
	}
	hr := Rect{x + 92, y, 62, 18}
	hid := make_id(hr, "text")
	if ui.focus_id != hid {
		name_set(&hex_buf, color_hex(fg))
	}
	if ch, sub := text_field(hr, &hex_buf, "Hex colour (RRGGBB)"); ch || sub {
		if c, ok := parse_hex(name_str(&hex_buf)); ok {
			picker_set_fg(c)
		}
	}
	h, s, v := int(fg_h + 0.5), int(fg_s * 100 + 0.5), int(fg_v * 100 + 0.5)
	text(x + 160, y + 5, fmt.tprintf("%d %d %d", h, s, v), C_TEXT_DIM)
	y += 24
	rgb := [3]int{int(fg.r), int(fg.g), int(fg.b)}
	names := [3]string{"R", "G", "B"}
	for i in 0 ..< 3 {
		if slider(Rect{x, y + i32(i) * 17, area.w, 14}, &rgb[i], 0, 255, names[i]) {
			picker_set_fg(Color{u8(rgb[0]), u8(rgb[1]), u8(rgb[2]), 255})
		}
	}
	y += 56

	// --- swatches ----------------------------------------------------------
	text(x, y + 4, "Swatches", C_TEXT_DIM)
	bx := area.x + area.w - 18
	if icon_button(Rect{bx, y, 18, 16}, .Minus, "Remove selected swatch", false, len(swatches) > 1) {
		if swatch_sel >= 0 && swatch_sel < len(swatches) {
			ordered_remove(&swatches, swatch_sel)
			swatch_sel = clamp(swatch_sel, 0, len(swatches) - 1)
		}
	}
	bx -= 20
	if icon_button(Rect{bx, y, 18, 16}, .Plus, "Add foreground colour") {
		append(&swatches, fg)
		swatch_sel = len(swatches) - 1
	}
	bx -= 56
	if button(Rect{bx, y, 54, 16}, "Presets", "Load a swatch set") {
		popup_begin(SWATCH_PRESET_ID, Rect{bx, y, 54, 16}, 110)
		for p in Swatch_Preset {
			popup_item(SWATCH_PRESET_NAMES[p], int(p))
		}
	}
	if ui.popup_result_id == SWATCH_PRESET_ID {
		swatches_set_preset(Swatch_Preset(ui.popup_result_val))
		ui.popup_result_id = 0
	}
	y += 21
	cell: i32 = 14
	cols := max((area.w - 4) / cell, 1)
	rows := i32((len(swatches) + int(cols) - 1) / int(cols))
	rows = min(rows, 3)
	pal := Rect{x, y, area.w, max(rows, 1) * cell + 4}
	@(static) pal_scroll: i32
	all_rows := i32((len(swatches) + int(cols) - 1) / int(cols))
	if ui_hover(pal) && ui.wheel != 0 {
		pal_scroll -= i32(ui.wheel) * cell
	}
	pal_scroll = clamp(pal_scroll, 0, max(all_rows * cell + 4 - pal.h, 0))
	ctl_well(pal)
	clip_begin(rect_inset(pal, 1))
	for c, i in swatches {
		sr := Rect{pal.x + 2 + i32(i % int(cols)) * cell, pal.y + 2 + i32(i / int(cols)) * cell - pal_scroll, cell, cell}
		if sr.y + cell < pal.y || sr.y > pal.y + pal.h do continue
		draw_rrect(f32(sr.x), f32(sr.y), f32(sr.w - 2), f32(sr.h - 2), 2, c)
		if i == swatch_sel {
			draw_rrect_outline(f32(sr.x - 1), f32(sr.y - 1), f32(sr.w), f32(sr.h), 3, C_ACCENT)
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
	y += pal.h + 6
	// recently used colours
	text(x, y + 2, "Recent", C_TEXT_DIM)
	rx := x + 46
	for c in recent {
		if rx + 12 > area.x + area.w do break
		sr := Rect{rx, y, 12, 12}
		draw_rrect(f32(sr.x), f32(sr.y), 12, 12, 2, c)
		draw_rrect_outline(f32(sr.x), f32(sr.y), 12, 12, 2, C_RING_HI)
		if ui_hover(sr) {
			tooltip_hover(make_id(sr, "rc"), color_hex(c))
			if ui.pressed[0] do set_fg(c)
			if ui.pressed[1] do bg = c
		}
		rx += 14
	}
	y += 20

	// --- layers --------------------------------------------------------------
	section_header(x, y, area.w, "Layers")
	y += 20
	avail := area.y + area.h - y
	nav_h: i32 = 0
	if show_navigator && avail - 200 >= 70 {
		nav_h = min(avail - 200, 130)
	}
	lr := Rect{x, y, area.w, avail - (nav_h > 0 ? nav_h + 26 : 0)}
	panel_layers(lr)
	if nav_h > 0 {
		y = lr.y + lr.h + 6
		section_header(x, y, area.w, "Navigator")
		y += 20
		panel_navigator(Rect{x, y, area.w, area.y + area.h - y})
	}
}

// ---------------------------------------------------------------------------
// Layers panel
// ---------------------------------------------------------------------------

THUMB_W :: 36
THUMB_H :: 24

Thumb :: struct {
	tex:  Texture,
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
		t := tex_create(THUMB_W, THUMB_H, .Linear)
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
			tex_update(thumbs[li * 2 + k].tex, buf[:])
		}
	}
}

LAYER_ROW_H :: 32
layers_scroll: i32
layer_drag := -1 // layer being dragged in the list, or -1
layer_drag_y0: i32
layer_drag_on: bool

panel_layers :: proc(r: Rect) {
	d := doc
	l := &d.layers[d.active_layer]
	thumbs_refresh(d)
	x, y := r.x, r.y
	// active layer blend + opacity
	if nv, ch := combo(Rect{x, y, 92, 16}, blend_names_slice(), int(l.blend), "Blend mode"); ch {
		history_push(d)
		l.blend = Blend(nv)
		doc_touch_all(d)
	}
	op := int(l.opacity) * 100 / 255
	orr := Rect{x + 96, y, r.w - 96, 16}
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
	y += 22

	// buttons along the bottom
	by := r.y + r.h - 18
	list := Rect{x, y, r.w, by - y - 5}
	bx := x
	b :: proc(x: ^i32, y: i32) -> Rect {
		rc := Rect{x^, y, 26, 18}
		x^ += 28
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
	ctl_well(list)
	n := i32(len(d.layers))
	content := n * LAYER_ROW_H
	inner := rect_inset(list, 1)
	if ui_hover(list) && ui.wheel != 0 {
		layers_scroll -= i32(ui.wheel) * LAYER_ROW_H
	}
	layers_scroll = clamp(layers_scroll, 0, max(content - inner.h, 0))
	clip_begin(inner)
	for i in 0 ..< n {
		li := int(n - 1 - i)
		ry := inner.y + i * LAYER_ROW_H - layers_scroll
		if ry + LAYER_ROW_H < inner.y || ry > inner.y + inner.h do continue
		ly := &d.layers[li]
		row := Rect{inner.x, ry, inner.w, LAYER_ROW_H}
		active := li == d.active_layer
		if active {
			fill_rect(row, C_ACCENT_TINT)
			fill_rect(Rect{row.x, row.y, 2, row.h}, C_ACCENT)
		} else if ui_hover(row) && ui_hover(list) {
			fill_rect(row, Color{255, 255, 255, 12})
		}
		hline(row.x, ry + LAYER_ROW_H - 1, row.w, C_RING)
		eye := Rect{row.x + 5, ry + (LAYER_ROW_H - 12) / 2, 12, 12}
		icon(.Eye, eye.x, eye.y, ly.visible ? C_TEXT : C_TEXT_OFF)
		th := Rect{row.x + 22, ry + (LAYER_ROW_H - THUMB_H) / 2, THUMB_W, THUMB_H}
		draw_checker(th, 3)
		if li * 2 < len(thumbs) {
			draw_tex_at(thumbs[li * 2].tex, th.x, th.y)
		}
		outline_rect(rect_inset(th, -1), active && !d.edit_mask ? C_ACCENT : C_RING_HI)
		tx := th.x + THUMB_W + 6
		mr := Rect{tx, th.y, THUMB_W, THUMB_H}
		if ly.has_mask {
			if li * 2 + 1 < len(thumbs) {
				draw_tex_at(thumbs[li * 2 + 1].tex, mr.x, mr.y)
			}
			if !ly.mask_on {
				draw_line_i(mr.x, mr.y, mr.x + mr.w, mr.y + mr.h, C_DANGER)
			}
			outline_rect(rect_inset(mr, -1), active && d.edit_mask ? C_ACCENT : C_RING_HI)
			tx += THUMB_W + 6
		}
		name_r := Rect{tx, ry + 5, row.x + row.w - tx - 4, 10}
		text_clipped(name_r, name_str(&ly.name), ly.visible ? C_TEXT : C_TEXT_DIM)
		info := ""
		if ly.blend != .Normal do info = BLEND_NAMES[ly.blend]
		if ly.opacity < 255 do info = fmt.tprintf("%s %d%%", info, int(ly.opacity) * 100 / 255)
		text_clipped(Rect{tx, ry + 17, name_r.w - 28, 10}, info, C_TEXT_DIM)
		ix := row.x + row.w - 16
		if ly.text.on {
			icon(.Text, ix, ry + 17, C_TEXT_DIM)
			ix -= 13
		}
		if ly.locked {
			icon(.Lock, ix, ry + 17, C_ACCENT)
			ix -= 13
		}
		if ly.lock_alpha {
			icon(.Lock_Alpha, ix, ry + 17, C_ACCENT)
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
				layer_drag, layer_drag_y0, layer_drag_on = li, ui.my, false
				if ui.dbl_click {
					dialog_open(.Layer_Props)
				}
			}
		}
	}
	// drag a row up or down to reorder; the line shows where it will land
	if layer_drag >= 0 && layer_drag < int(n) {
		if !layer_drag_on && ui.down[0] && abs(ui.my - layer_drag_y0) > 4 {
			layer_drag_on = true
		}
		if layer_drag_on {
			ri := clamp((ui.my - inner.y + layers_scroll) / LAYER_ROW_H, 0, n - 1)
			target := int(n - 1 - ri)
			if target != layer_drag {
				ly := inner.y + (target > layer_drag ? ri : ri + 1) * LAYER_ROW_H - layers_scroll
				fill_rect(Rect{inner.x, ly - 1, inner.w, 2}, C_ACCENT)
				if ui.released[0] {
					history_push(d)
					for layer_drag < target {
						d.layers[layer_drag], d.layers[layer_drag + 1] = d.layers[layer_drag + 1], d.layers[layer_drag]
						layer_drag += 1
					}
					for layer_drag > target {
						d.layers[layer_drag], d.layers[layer_drag - 1] = d.layers[layer_drag - 1], d.layers[layer_drag]
						layer_drag -= 1
					}
					d.active_layer = target
					doc_touch_all(d)
				}
			}
		}
		if !ui.down[0] {
			layer_drag, layer_drag_on = -1, false
		}
	} else {
		layer_drag, layer_drag_on = -1, false
	}
	clip_end()
}

// ---------------------------------------------------------------------------
// Navigator: whole image with the visible area; click or drag to move the view
// ---------------------------------------------------------------------------

panel_navigator :: proc(r: Rect) {
	d := doc
	ctl_well(r)
	if !tex_valid(tex_canvas) || tex_doc != d {
		return
	}
	z := min(f32(r.w - 8) / f32(d.w), f32(r.h - 8) / f32(d.h))
	w, h := f32(d.w) * z, f32(d.h) * z
	dst := FRect{math.floor(f32(r.x) + (f32(r.w) - w) / 2), math.floor(f32(r.y) + (f32(r.h) - h) / 2), w, h}
	draw_canvas_bg(dst)
	draw_canvas_tex(d, dst)
	vp := canvas_vp
	vx := (f32(vp.x) - d.ox) / d.zoom
	vy := (f32(vp.y) - d.oy) / d.zoom
	vw := f32(vp.w) / d.zoom
	vh := f32(vp.h) / d.zoom
	vr := FRect{dst.x + vx * z, dst.y + vy * z, vw * z, vh * z}
	clip_begin(r)
	draw_rect_outline(vr, C_ACCENT)
	draw_rect_outline({vr.x + hair(), vr.y + hair(), vr.w - 2 * hair(), vr.h - 2 * hair()}, Color{0, 0, 0, 120})
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
preview_tex: Texture
preview_brush: Brush
preview_tool: Tool
preview_color: Color
preview_blend: Blend

brush_preview :: proc(r: Rect, t: Tool) {
	w, h := int(r.w), int(r.h)
	b := brushes[t]
	if preview_doc == nil || preview_doc.w != w || preview_doc.h != h || preview_brush != b || preview_tool != t || preview_color != fg || preview_blend != brush_blend {
		preview_brush, preview_tool, preview_color, preview_blend = b, t, fg, brush_blend
		if preview_doc != nil {
			doc_destroy(preview_doc)
		}
		if tex_valid(preview_tex) && (int(preview_tex.w) != w || int(preview_tex.h) != h) {
			tex_destroy(&preview_tex)
		}
		if !tex_valid(preview_tex) {
			preview_tex = tex_create(w, h, .Point)
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
		tex_update(preview_tex, pd.comp)
	}
	draw_checker(r, 4)
	draw_tex_at(preview_tex, r.x, r.y)
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
	ty := r.y + (r.h - FONT_CAP) / 2
	sep :: proc(x: i32, r: Rect) {
		vline(x, r.y + 5, r.h - 9, C_RING_HI)
	}
	if status_t > 0 {
		text(r.x + 10, ty, name_str(&status_msg), C_ACCENT)
	} else {
		label := TOOL_NAMES[cur_tool]
		if (cur_tool == .Brush || cur_tool == .Oil || cur_tool == .Text) && brush_blend != .Normal {
			label = fmt.tprintf("%s - %s", label, BLEND_NAMES[brush_blend])
		}
		text(r.x + 10, ty, label, C_TEXT_DIM)
	}
	x := r.x + 300
	sep(x - 12, r)
	if hover_valid && pt_in_doc(hover_pt) {
		q := ipt(hover_pt)
		doc_refresh_comp(d)
		c := d.comp[q.y * d.w + q.x]
		textf(x, ty, C_TEXT, "%d, %d", q.x, q.y)
		swr := Rect{x + 74, r.y + (r.h - 10) / 2, 10, 10}
		draw_rrect(f32(swr.x), f32(swr.y), 10, 10, 2, c)
		draw_rrect_outline(f32(swr.x), f32(swr.y), 10, 10, 2, C_RING_HI)
		text(x + 90, ty, color_hex(c), C_TEXT_DIM)
	}
	if d.sel != nil {
		b := d.sel.bbox
		sep(x + 148, r)
		textf(x + 160, ty, C_TEXT_DIM, "Sel %dx%d", b.x1 - b.x0, b.y1 - b.y0)
	}
	l := &d.layers[d.active_layer]
	target := d.edit_mask ? fmt.tprintf("%s (mask)", name_str(&l.name)) : name_str(&l.name)
	zoom := fmt.tprintf("%d%%", int(d.zoom * 100 + 0.5))
	size := fmt.tprintf("%d x %d", d.w, d.h)
	rx := r.x + r.w - 10
	rx -= text_w(zoom)
	text(rx, ty, zoom, C_TEXT)
	rx -= 14
	sep(rx + 6, r)
	rx -= text_w(size)
	text(rx, ty, size, C_TEXT_DIM)
	rx -= 14
	sep(rx + 6, r)
	rx -= text_w(target)
	text(rx, ty, target, C_TEXT_DIM)
}
