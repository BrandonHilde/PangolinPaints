package pangolin

import "core:fmt"
import "core:math"

import oui "odinui:odinui"

SWATCH_PRESET_ID :: u32(0x5A7C4E51)
PRESET_ID :: u32(0xB2A5E7E1)

// ---------------------------------------------------------------------------
// Top-level layout: the theme places the areas (#menubar, #body, #toolbar, #viewport ...) and
// each panel draws into the box it gets.
// ---------------------------------------------------------------------------

panels_init :: proc() {
	oui_slot_register("logo", proc(r: Rect, _: int) {
		logo_draw(r.x, r.y + (r.h - LOGO_SIZE) / 2, 1)
		tip_area(r, "logo", {"Pangolin Paints", "A painting and image editor. Help > About has the details."})
	})
	oui_slot_register("color_chips", proc(r: Rect, _: int) {panel_color_chips(r)})
	oui_slot_register("color_picker", proc(r: Rect, _: int) {panel_color_picker(r)})
	oui_slot_register("hex_field", proc(r: Rect, _: int) {panel_hex_field(r)})
	oui_slot_register("swatches", proc(r: Rect, _: int) {panel_swatches(r)})
	oui_slot_register("recent", proc(r: Rect, _: int) {panel_recent(r)})
	oui_slot_register("layer_list", proc(r: Rect, _: int) {panel_layer_list(r)})
	oui_slot_register("navigator", proc(r: Rect, _: int) {panel_navigator(r)})
	oui_slot_register("cursor_info", proc(r: Rect, _: int) {panel_cursor_info(r)})
	oui_slot_register("groups_bar", proc(r: Rect, _: int) {panel_groups_bar(r)})
	oui_slot_register("macro_editor", proc(r: Rect, _: int) {macro_editor_ui(r)})
	oui_slot_register("viewport", proc(r: Rect, _: int) {panel_viewport(r)})
	oui_slot_register("timeline_grid", proc(r: Rect, _: int) {panel_timeline_grid(r)})
	oui_slot_register("files_grid", proc(r: Rect, _: int) {panel_files_grid(r)})
}

main_ui :: proc() {
	oui.element(uictx, "window", "screen", {id = "window"})
	defer oui.end(uictx)
	panel_menubar()
	if macro_editor_on() {
		// the node editor takes the place of everything below the menus
		oui_slot("viewport", "macro_editor")
		return
	}
	panel_options()
	if canvas_mode {
		oui_slot("viewport", "viewport")
		oui_slot("groups-bar", "groups_bar")
		return
	}
	oui.element(uictx, "body", "row", {id = "body"})
	panel_toolbar()
	oui.element(uictx, "center", "column", {id = "center"})
	panel_tabs()
	oui_slot("viewport", "viewport")
	panel_timeline()
	oui.end(uictx)
	panel_right()
	oui.end(uictx)
	panel_status()
}

panel_viewport :: proc(viewport: Rect) {
	// keep the picture where it was on screen when the viewport changes size
	@(static) prev_mode := false
	@(static) prev_vp: Rect
	if canvas_mode != prev_mode && doc.view_init && prev_vp.w > 0 {
		doc.ox += f32(viewport.x + viewport.w / 2 - prev_vp.x - prev_vp.w / 2)
		doc.oy += f32(viewport.y + viewport.h / 2 - prev_vp.y - prev_vp.h / 2)
	}
	prev_mode, prev_vp = canvas_mode, viewport
	canvas_update(viewport)
	render_canvas(viewport)
}

// ---------------------------------------------------------------------------
// Menu bar
// ---------------------------------------------------------------------------

MENU_TITLES := [?]string{"File", "Edit", "Image", "Adjust", "Filter", "Layer", "Frame", "Select", "View", "Workspaces", "Macros", "Help"}

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
		item("Import as Layer...", cmd = .Place_Image)
		item("Export...", cmd = .Export)
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
		item("Delete", cmd = .Clear)
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
		item("Convert Text to Path", cmd = .Layer_Text_To_Path, enabled = l.text.on)
		item("Rasterize Layer", cmd = .Layer_Rasterize, enabled = l.text.on || l.shape != nil)
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
		item("New Frame", cmd = .Frame_New)
		item("Duplicate Frame", cmd = .Frame_Dup)
		item("New Frame from Visible", cmd = .Frame_From_Visible)
		item("Delete Frame", cmd = .Frame_Del, enabled = len(d.frames) > 1)
		popup_sep()
		item("Move Frame Left", cmd = .Frame_Left, enabled = d.active_frame > 0)
		item("Move Frame Right", cmd = .Frame_Right, enabled = d.active_frame < len(d.frames) - 1)
		popup_sep()
		item("Previous Frame", cmd = .Frame_Prev, enabled = len(d.frames) > 1)
		item("Next Frame", cmd = .Frame_Next, enabled = len(d.frames) > 1)
		item("First Frame", cmd = .Frame_First, enabled = len(d.frames) > 1)
		item("Last Frame", cmd = .Frame_Last, enabled = len(d.frames) > 1)
		item(playing ? "Pause" : "Play", cmd = .Play, enabled = len(d.frames) > 1)
		popup_sep()
		item("Frame Properties...", cmd = .Frame_Props)
		item("Tags...", cmd = .Tags)
		item("Onion Skin", cmd = .Toggle_Onion, checked = onion_on)
	case 7:
		item("Select All", cmd = .Select_All)
		item("Deselect", cmd = .Deselect)
		item("Invert Selection", cmd = .Invert_Sel)
		item("Select Layer Opacity", cmd = .Select_Alpha)
		popup_sep()
		item("Feather...", cmd = .Feather, enabled = d.sel != nil)
		item("Grow...", cmd = .Grow, enabled = d.sel != nil)
		item("Shrink...", cmd = .Shrink, enabled = d.sel != nil)
	case 8:
		item("Zoom In", cmd = .Zoom_In)
		item("Zoom Out", cmd = .Zoom_Out)
		item("Fit to Window", cmd = .Zoom_Fit)
		item("100%", cmd = .Zoom_1)
		item("200%", cmd = .Zoom_2)
		popup_sep()
		item("Pixel Grid", cmd = .Toggle_Pixel_Grid, checked = show_pixel_grid)
		item("Rule of Thirds", cmd = .Toggle_Thirds, checked = show_thirds)
		item("Grid", cmd = .Toggle_Grid, checked = show_grid)
		item("Snap to Grid", cmd = .Toggle_Snap, checked = snap_grid)
		item("Grid Settings...", cmd = .Grid_Settings)
		item("Mirror Painting", cmd = .Toggle_Mirror, checked = mirror_on)
		item("Perspective Guides", cmd = .Toggle_Perspective, checked = persp_on)
		item("Navigator", cmd = .Toggle_Navigator, checked = show_navigator)
		item("Canvas Mode", cmd = .Toggle_Canvas_Mode, checked = canvas_mode)
		item("Tiled Mode", cmd = .Toggle_Seamless, checked = seamless_mode)
		item("Cycle Transparency Display", cmd = .Cycle_Canvas_Bg)
		popup_sep()
		item("UI Scale...", cmd = .UI_Scale)
		item("Timeline", cmd = .Toggle_Timeline, checked = bottom_mode == .Animation)
		item("File Browser", cmd = .Toggle_Files, checked = bottom_mode == .Files)
	case 9:
		ws_refresh()
		for e, i in ws_entries {
			if i == len(WS_BUILTIN_NAMES) do popup_sep()
			item(e.name, cmd = Cmd(int(Cmd.Ws_First) + i), checked = e.name == ws_current)
		}
		popup_sep()
		item("Manage Workspaces...", cmd = .Ws_Manage)
		item("Import Workspace...", cmd = .Ws_Import)
		item("Export Workspace...", cmd = .Ws_Export)
	case 10:
		for m, i in macro_lib {
			if i >= MACRO_MENU_MAX do break
			item(m.name, cmd = Cmd(int(Cmd.Macro_First) + i))
		}
		if len(macro_lib) > 0 do popup_sep()
		item("Node Editor", cmd = .Macro_Editor, checked = macro_editor_on())
		item(macro_recording() ? "Stop Recording" : "Record Macro", cmd = .Macro_Record, checked = macro_recording())
		item("Manage Macros...", cmd = .Macros)
		item("Import Macro...", cmd = .Macro_Import)
	case 11:
		item("Keyboard Shortcuts", cmd = .Help_Keys)
		item("About", cmd = .About)
	}
}

menu_request := -1 // a menu to open (--menu)

panel_menubar :: proc() {
	bar := oui.element(uictx, "menubar", "menubar", {id = "menubar"})
	defer oui.end(uictx)
	oui_slot("logo", "logo")
	menu_open := popup.open && popup.menu_idx >= 0
	for title, i in MENU_TITLES {
		is_open := menu_open && popup.menu_idx == i
		n := oui.button_begin(uictx, title, {class = is_open ? "menu-title open" : "menu-title"})
		oui.label(uictx, "t", title)
		oui.end(uictx)
		oui_tip(n, menu_title_tip(title))
		// menus drop from the bottom of the bar
		r := oui_rect(n)
		br := oui_rect(bar)
		anchor := Rect{r.x, br.y, r.w, br.h - 1}
		id := make_id(anchor, title)
		if n.pressed || menu_request == i {
			menu_request = -1
			popup_begin(id, anchor, 0, i)
			menu_build(i)
		} else if menu_open && ui.input_layer < 2 && in_rect(br.h > 30 ? r : anchor, ui.mx, ui.my) {
			// while a menu is open the bar takes no clicks: moving along it switches menus,
			// clicking the open one's title closes it. A bar with wrapped rows has titles above each other.
			if ui.pressed[0] && is_open {
				popup_close()
			} else if !is_open {
				popup_begin(id, anchor, 0, i)
				menu_build(i)
			}
		}
	}
	oui.element_leaf(uictx, "spacer", "spacer")
	if macro_recording() && obutton("Stop Recording", 0, {"Recording a macro", "The commands you use are being recorded as a macro. Click to stop and save it."}, true, true, id = "rec-stop") {
		run_cmd(.Macro_Record)
	}
	if c, _ := oui_icon_button("canvas-mode", .Canvas_Mode, cmd_tip("Canvas Mode", .Toggle_Canvas_Mode), {lit = canvas_mode, enabled = true}); c {
		run_cmd(.Toggle_Canvas_Mode)
	}
	// a very large UI scale needs the row more: the tab shows the name too
	if ui.w >= 480 do oui_tip(oui.label(uictx, "doc", doc_display_name(doc), {id = "doc-name"}), {"Current painting", doc_status(doc)})
}

// ---------------------------------------------------------------------------
// Tabs
// ---------------------------------------------------------------------------

panel_tabs :: proc() {
	tabs_rect = oui_rect(oui.element(uictx, "tabs", "tabbar", {id = "tabs"}))
	defer oui.end(uictx)
	close_idx := -1
	switch_idx := -1
	for d, i in docs {
		active := d == doc
		t := oui.button_begin(uictx, fmt.tprintf("tab%x", uintptr(d)), {class = active ? "tab active" : "tab"})
		oui_tip(t, {"", fmt.tprintf("%s Click to switch to it, middle-click to close it.", doc_status(d))})
		if active do oui.element_leaf(uictx, "accent", "tab-accent")
		oui.label(uictx, "name", doc_display_name(d))
		if c, _ := oui_icon_button("close", .Close, {"Close painting", "Close this painting. If it has unsaved changes you are asked first."}, {class = "tab-close", enabled = true}); c {
			close_idx = i
		}
		oui.end(uictx)
		if t.pressed do switch_idx = i // a press on the tab itself, not its close button
		if t.hovered && ui.pressed[2] do close_idx = i
	}
	if c, _ := oui_icon_button("new", .Plus, cmd_tip("New painting", .New), {id = "new-tab", enabled = true}); c {
		run_cmd(.New)
	}
	if close_idx >= 0 {
		request_close(docs[close_idx])
	} else if switch_idx >= 0 {
		switch_doc(switch_idx)
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
	.Grid           = .Grid,
	.Mirror         = .Sym_X,
	.Perspective    = .Perspective,
	.Seamless       = .Seamless,
}

GROUP_RENAME_TIP :: "Choose the name shown at the top of this group."
GROUP_REMOVE_TIP :: "Remove this group from the toolbar. Its tools stay available from the other groups' + buttons."

panel_toolbar :: proc() {
	oui.element(uictx, "toolbar", "toolbar", {id = "toolbar"})
	defer oui.end(uictx)
	t := eff_tool()
	rem_g, rem_t := -1, -1
	cur_group := current_group()
	for &g, gi in tool_groups {
		oui.element(uictx, fmt.tprintf("g%d", gi), "tool-group", {class = g.pen_eraser ? "eraser" : ""})
		// header: the name on the left, the hotkey as a keycap on the right
		// (click the keycap for options; right-click the header for rename / remove)
		hdr := oui.element(uictx, "head", "group-head")
		oui_tip(hdr, {group_title(&g), "A tool group: tools, switches, colors, blend modes or macros kept together. Right-click to rename or remove it."})
		oui.label(uictx, "title", group_title(&g), {class = "group-title"})
		waiting := group_key_wait == gi
		label := waiting ? "..." : (g.key == .KEY_NULL ? "-" : key_name(g.key))
		kc := oui.button_begin(uictx, "key", {class = label == "-" ? "keycap none" : "keycap", checked = waiting})
		oui.label(uictx, "t", label)
		oui.end(uictx)
		oui_tip(kc, {"Group hotkey", len(g.macros) > 0 ? "Press this key to run the group's selected macro; the next press runs the macro after it. Click to change the key, rename or remove the group." : "Press this key to pick the group's last tool, and again to step through what it holds. Click to change the key, rename or remove the group, or use it for the pen's eraser end."})
		oui.end(uictx)
		bid := make_id({}, fmt.tprintf("grpbadge%d", gi))
		if kc.clicked {
			popup_begin(bid, oui_rect(kc), 120)
			popup_item("Assign hotkey...", 0, tip = "Press a letter or number key next to make it this group's hotkey. Backspace clears it, Esc cancels.")
			popup_item("Rename...", 3, tip = GROUP_RENAME_TIP)
			popup_item(g.pen_eraser ? "Pen eraser: off" : "Use for pen eraser", 2, tip = "The eraser end of a tablet pen uses this group's last tool, instead of erasing. Only one group can do this.")
			popup_item("Remove group", 1, tip = GROUP_REMOVE_TIP)
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
		hid := make_id({}, fmt.tprintf("grphdr%d", gi))
		if hdr.hovered && ui.released[1] && !popup.open {
			popup_begin(hid, Rect{ui.mx, ui.my, 1, 1}, 110)
			popup_item("Rename...", 3, tip = GROUP_RENAME_TIP)
			popup_item("Remove group", 1, tip = GROUP_REMOVE_TIP)
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
		is_macros := len(g.macros) > 0
		n := is_colors ? len(g.colors) : (is_blends ? len(g.blends) : (is_macros ? len(g.macros) : len(g.tools)))
		oui.element(uictx, "items", "group-items", {class = is_blends || is_macros ? "blends" : ""})
		for tool, ti in g.tools {
			// the pen-eraser group keeps its own selection, separate from the pen tip's tool
			lit := g.pen_eraser ? g.last == tool : t == tool && cur_group == gi
			if tool_is_toggle(tool) do lit = tool_toggle_on(tool)
			clicked, bn := oui_icon_button(fmt.tprintf("t%d", int(tool)), TOOL_ICONS[tool], tool_tip(tool), {class = "tool", lit = lit, enabled = true, icon_lg = true})
			if clicked {
				if tool_is_toggle(tool) {
					tool_toggle(tool)
				} else {
					g.last = tool
					if !g.pen_eraser do select_tool_in_group(tool, gi)
				}
			} else if bn.hovered && ui.pressed[1] && !popup.open {
				rem_g, rem_t = gi, ti
			}
		}
		for c, ci in g.colors {
			same := c.r == fg.r && c.g == fg.g && c.b == fg.b
			linked := color_link_g == gi && color_link_i == ci
			class := linked ? "color-chip linked" : (same ? "color-chip same" : "color-chip")
			cn := oui.button_begin(uictx, fmt.tprintf("c%d", ci), {class = class, style = fmt.tprintf("background:#%02x%02x%02x", c.r, c.g, c.b)})
			oui.end(uictx)
			oui_tip(cn, {fmt.tprintf("#%s", color_hex(c)), "Click to paint with this color, and to change it with the color picker. Right-click to remove it. The group's hotkey steps through its colors."})
			if cn.clicked {
				color_link_set(gi, ci)
			} else if cn.hovered && ui.pressed[1] && !popup.open {
				rem_g, rem_t = gi, ci
			}
		}
		// blend modes are listed one per row, the active one highlighted
		for b, bi in g.blends {
			if obutton(BLEND_NAMES[b], 0, {"", fmt.tprintf("The Brush tool's blend mode. %s Right-click to remove it.", BLEND_HELP[b])}, true, b == brush_blend, key = fmt.tprintf("b%d", bi), class = "blend-row") {
				brush_blend = b
			}
			if bn := oui.find_node(uictx.build_parent, fmt.tprintf("b%d", bi)); bn != nil && bn.hovered && ui.pressed[1] && !popup.open {
				rem_g, rem_t = gi, bi
			}
		}
		// macros are listed one per row too: the one the hotkey runs next is highlighted
		for &mn, mi in g.macros {
			name := name_str(&mn)
			found := macro_find(name) != nil
			tip := found ? fmt.tprintf("Click to make this the macro the group's hotkey runs next. Right-click to remove it from the group.") : "There is no macro with this name any more. Right-click to remove it from the group."
			if obutton(name, 0, {name, tip}, found, mi == g.next_macro, key = fmt.tprintf("m%d", mi), class = "blend-row") {
				g.next_macro = mi
			}
			if bn := oui.find_node(uictx.build_parent, fmt.tprintf("m%d", mi)); bn != nil && bn.hovered && ui.pressed[1] && !popup.open {
				rem_g, rem_t = gi, mi
			}
		}
		macros_left := 0
		for m in macro_lib do if !group_has_macro(&g, m.name) do macros_left += 1
		can_add := is_colors ? n < 48 : (is_blends ? n < len(Blend) : (is_macros ? macros_left > 0 : n < len(Tool)))
		if can_add {
			tip := Tip{"Add to group", "Add a tool, a switch, colors, brush blend modes or macros to this group. A group holds one of those kinds. Right-click an item to remove it."}
			pid := make_id({}, fmt.tprintf("grpadd%d", gi))
			add_clicked, add_node := oui_icon_button("add", .Plus, tip, {class = "tool quiet", enabled = true, icon_lg = true})
			if add_clicked {
				popup_begin(pid, oui_rect(add_node))
				popup_grid(5)
				any_section := false
				if !is_colors && !is_blends && !is_macros {
					for tool in Tool {
						if !tool_group_has(&g, tool) {
							popup_item_icon(TOOL_NAMES[tool], int(tool), TOOL_ICONS[tool], TOOL_HELP[tool])
						}
					}
					any_section = true
				}
				if !is_tools && !is_blends && !is_macros {
					if any_section do popup_sep()
					popup_item_swatch("Foreground color", 100, fg)
					popup_item("All current swatches", 101, tip = "Add every color in the Swatches panel to this group.")
					for p in Swatch_Preset {
						popup_item_palette(SWATCH_PRESET_NAMES[p], 200 + int(p), swatch_preset_colors(p), SWATCH_PRESET_HELP[p])
					}
					any_section = true
				}
				if !is_tools && !is_colors && !is_macros {
					if any_section do popup_sep()
					for b in Blend {
						if !blend_in(g.blends[:], b) {
							popup_item_half(BLEND_NAMES[b], 300 + int(b))
						}
					}
					any_section = true
				}
				if !is_tools && !is_colors && !is_blends && macros_left > 0 {
					if any_section do popup_sep()
					for m, mi in macro_lib {
						if !group_has_macro(&g, m.name) {
							popup_item_half(m.name, 1000 + mi)
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
				case v >= 1000:
					if v - 1000 < len(macro_lib) {
						mn: Name
						name_set(&mn, macro_lib[v - 1000].name)
						append(&g.macros, mn)
					}
				case v >= 300:
					append(&g.blends, Blend(v - 300))
				case:
					append(&g.colors, ..swatch_preset_colors(Swatch_Preset(v - 200)))
				}
				ui.popup_result_id = 0
			}
		}
		oui.end(uictx) // items
		oui.end(uictx) // group
	}
	if rem_g >= 0 {
		color_link_clear() // indices shift
		if rem_t >= 0 {
			rg := &tool_groups[rem_g]
			if len(rg.colors) > 0 {
				ordered_remove(&rg.colors, rem_t)
			} else if len(rg.blends) > 0 {
				ordered_remove(&rg.blends, rem_t)
			} else if len(rg.macros) > 0 {
				ordered_remove(&rg.macros, rem_t)
				if rg.next_macro >= len(rg.macros) do rg.next_macro = 0
			} else {
				ordered_remove(&rg.tools, rem_t)
			}
		} else {
			group_save_brushes()
			active_group = -1 // indices shift
			tool_group_free(&tool_groups[rem_g])
			ordered_remove(&tool_groups, rem_g)
			group_key_wait = -1
		}
	}
	if len(tool_groups) < MAX_TOOL_GROUPS {
		if obutton("+ New Group", 0, {"", "Add an empty tool group, then use its + button to fill it with tools, colors, blend modes or macros."}, id = "new-group") {
			append(&tool_groups, Tool_Group{})
		}
	}
	oui.separator(uictx, "chips-sep")
	oui_slot("color-chips", "color_chips")
}

// Foreground / background chips below the tool groups.
panel_color_chips :: proc(r: Rect) {
	bgr := Rect{r.x + 13, r.y + 14, 24, 24}
	fgr := Rect{r.x, r.y, 24, 24}
	draw_rrect(f32(bgr.x), f32(bgr.y), 24, 24, 4, bg)
	draw_rrect_outline(f32(bgr.x), f32(bgr.y), 24, 24, 4, ui_hover(bgr) && !ui_hover(fgr) ? WHITE : C_RING_HI)
	draw_shadow(f32(fgr.x), f32(fgr.y + 1), 24, 24, 4, 5, Color{0, 0, 0, 140})
	draw_rrect(f32(fgr.x), f32(fgr.y), 24, 24, 4, fg)
	draw_rrect_outline(f32(fgr.x), f32(fgr.y), 24, 24, 4, WHITE)
	tip_area(fgr, "fgchip", {"Foreground color", "The color you paint with. Change it with the color panel, or hold Alt and click the canvas."})
	if ui_hover(bgr) && !ui_hover(fgr) {
		tooltip_hover(make_id(bgr, "bgchip"), {fmt.tprintf("Background color (%s)", shortcut_text(.Swap_Colors)), "Right-drag paints with this color. Click to swap it with the foreground color."})
		if ui.pressed[0] {
			run_cmd(.Swap_Colors)
		}
	}
}

// ---------------------------------------------------------------------------
// Tool options bar
// ---------------------------------------------------------------------------

panel_options :: proc() {
	oui.element(uictx, "options", "optionsbar", {id = "options"})
	defer oui.end(uictx)
	t := eff_tool()
	if options_switch_on && options_switch == .Grid && show_grid {
		options_grid()
	} else if options_switch_on && options_switch == .Mirror && mirror_on {
		options_mirror()
	} else if options_switch_on && options_switch == .Perspective && persp_on {
		options_persp()
	} else if options_switch_on && options_switch == .Seamless && seamless_mode {
		options_seamless()
	} else if paint_tool(t) {
		options_brush(t)
		if t == .Line do options_line()
	} else {
		options_other(t)
	}
	// right side: layer state
	oui.element_leaf(uictx, "spacer", "spacer")
	l := &doc.layers[doc.active_layer]
	if l.has_mask {
		if c, _ := oui_icon_button("mask", .Mask, cmd_tip("Edit Mask", .Mask_Edit), {lit = doc.edit_mask, enabled = true}); c {
			run_cmd(.Mask_Edit)
		}
	}
	if c, _ := oui_icon_button("lock-alpha", .Lock_Alpha, cmd_tip("Lock Transparency", .Layer_Lock_Alpha), {lit = l.lock_alpha, enabled = true}); c {
		run_cmd(.Layer_Lock_Alpha)
	}
}

options_brush :: proc(t: Tool) {
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
		if nv, ch := ocombo("preset", 96, names[:], cur, {"Brush preset", "A ready-made brush for this tool. Picking one replaces all this tool's settings."}); ch {
			pi := idx[nv]
			brush_preset_idx[t] = pi
			brushes[t] = presets[pi].b
		}
	}
	oslider("Size", 92, &b.size, 1, BRUSH_MAX, {"Brush size ([ and ])", HELP_SIZE}, "px", 2.5)
	oslider("Opacity", 84, &b.opacity, 1, 100, {"Opacity (Shift+number keys)", HELP_OPACITY}, "%")
	#partial switch t {
	case .Brush, .Eraser, .Clone, .Line:
		oslider("Flow", 70, &b.flow, 1, 100, {"Flow", HELP_FLOW}, "%")
		oslider("Hard", 76, &b.hardness, 0, 100, {"Hardness", HELP_HARDNESS}, "%")
		if t == .Clone do ocheck("All layers", &b.clone_merged, {"Sample all layers", HELP_CLONE_ALL})
	case .Oil:
		oslider("Load", 70, &b.load, 0, 100, {"Paint load", HELP_LOAD}, "%")
		oslider("Wet", 66, &b.wet, 0, 100, {"Wetness", HELP_WET}, "%")
		oslider("Bristle", 76, &b.bristles, 0, 100, {"Bristles", HELP_BRISTLES}, "%")
		oslider("Hard", 70, &b.hardness, 0, 100, {"Hardness", HELP_HARDNESS}, "%")
	case .Smudge:
		oslider("Strength", 84, &b.strength, 0, 100, {"Strength", HELP_SMUDGE}, "%")
		oslider("Hard", 70, &b.hardness, 0, 100, {"Hardness", HELP_HARDNESS}, "%")
	case .Blur:
		oslider("Strength", 84, &b.strength, 0, 100, {"Strength", HELP_BLUR}, "%")
		oui.element(uictx, "mode", "button-group")
		if obutton("Blur", 46, {"", "The brush softens what is under it."}, true, !b.alt_mode) do b.alt_mode = false
		if obutton("Sharpen", 52, {"", "The brush crisps up what is under it."}, true, b.alt_mode) do b.alt_mode = true
		oui.end(uictx)
	case .Dodge:
		oslider("Exposure", 84, &b.strength, 0, 100, {"Exposure", HELP_EXPOSURE}, "%")
		oui.element(uictx, "mode", "button-group")
		if obutton("Dodge", 46, {"", "The brush lightens what is under it."}, true, !b.alt_mode) do b.alt_mode = false
		if obutton("Burn", 40, {"", "The brush darkens what is under it."}, true, b.alt_mode) do b.alt_mode = true
		oui.end(uictx)
		TONES := [?]string{"Shadows", "Midtones", "Highlights"}
		if nv, ch := ocombo("tone", 74, TONES[:], b.tone, {"Tonal range", HELP_TONES}); ch do b.tone = nv
	}
	oslider("Smooth", 84, &b.smoothing, 0, 100, {"Smoothing", HELP_SMOOTHING}, "%")
	if obutton("More...", 58, cmd_tip("Brush Settings", .Brush_Settings)) {
		run_cmd(.Brush_Settings)
	}
}

options_other :: proc(t: Tool) {
	sel_modes :: proc() {
		labels := [?]string{"New", "Add", "Sub", "And"}
		tips := [?]string{
			"Each new selection replaces the last one.",
			"Each new selection adds to the last one. Holding Shift does this for one selection.",
			"Each new selection cuts away from the last one. Holding Alt does this for one selection.",
			"Keep only where each new selection overlaps the last one. Holding Shift and Alt does this for one selection.",
		}
		oui.element(uictx, "sel-mode", "button-group")
		for l, i in labels {
			if obutton(l, 28, {l, tips[i]}, true, int(topts.sel_mode) == i) {
				topts.sel_mode = Sel_Mode(i)
			}
		}
		oui.end(uictx)
	}
	#partial switch t {
	case .Bucket:
		oslider("Tolerance", 100, &topts.tolerance, 0, 255, {"Tolerance", HELP_TOLERANCE})
		oslider("Opacity", 90, &topts.fill_opacity, 1, 100, {"Fill opacity", HELP_FILL_OPACITY}, "%")
		ocheck("Contiguous", &topts.contiguous, {"Contiguous", HELP_CONTIGUOUS})
		ocheck("All layers", &topts.sample_merged, {"All layers", HELP_ALL_LAYERS})
		ocheck("Smooth edge", &topts.antialias, {"Smooth edge", HELP_SMOOTH_EDGE})
	case .Gradient:
		ocombo_enum("shape", 80, GRAD_NAMES, &topts.grad_kind, {"Gradient shape", "Linear runs straight along the drag, Radial spreads in a circle, Reflected runs both ways from the start, Diamond spreads as a square on its corner."})
		oslider("Opacity", 90, &topts.fill_opacity, 1, 100, {"Fill opacity", HELP_FILL_OPACITY}, "%")
		ocheck("To transparent", &topts.grad_to_clear, {"To transparent", "Fade from the foreground color to nothing, rather than to the background color."})
		ocheck("Reverse", &topts.grad_reverse, {"Reverse", "Swap the two ends of the gradient."})
		ohint("Drag across the canvas")
	case .Picker:
		SIZES := [?]string{"Point", "3 x 3 average", "5 x 5 average", "11 x 11 average"}
		VALS := [?]int{1, 3, 5, 11}
		cur := 0
		for v, i in VALS do if v == topts.pick_size do cur = i
		if nv, ch := ocombo("sample", 100, SIZES[:], cur, {"Sample size", "Read a single pixel, or the average of a square around it, which ignores grain and fine detail."}); ch do topts.pick_size = VALS[nv]
		ohint("Click: foreground   Right click: background   (Alt with any brush)")
	case .Select_Rect, .Select_Ellipse, .Lasso:
		sel_modes()
		oslider("Feather", 90, &topts.feather, 0, 200, {"Feather", "How soft the edge of a new selection is, as a radius in canvas pixels."}, "px")
		ohint("Shift: add   Alt: subtract   Drag inside a selection to move it")
	case .Wand:
		sel_modes()
		oslider("Tolerance", 100, &topts.tolerance, 0, 255, {"Tolerance", HELP_TOLERANCE})
		ocheck("Contiguous", &topts.contiguous, {"Contiguous", HELP_CONTIGUOUS})
		ocheck("All layers", &topts.sample_merged, {"All layers", HELP_ALL_LAYERS})
		ocheck("Smooth edge", &topts.antialias, {"Smooth edge", HELP_SMOOTH_EDGE})
	case .Text:
		options_text()
	case .Move:
		ohint("Drag to move the selection (or the whole layer). Alt: copy. Arrows nudge, Shift x10.")
	case .Transform:
		if xform.active {
			if obutton("Apply", 50, {"Apply (Enter)", "Keep the transformed result."}) do xform_commit()
			if obutton("Cancel", 50, {"Cancel (Esc)", "Put everything back as it was."}) do xform_cancel()
		}
		ohint("Corners: scale (Shift: free)   Edges: stretch   Outside: rotate   Inside: move")
	case .Crop:
		if crop.active {
			if obutton("Crop", 50, {"Crop (Enter)", "Cut the canvas down to the marked area."}) do crop_commit()
			if obutton("Cancel", 50, {"Cancel (Esc)", "Remove the marked area and leave the canvas as it is."}) do crop.active = false
		}
		ohint("Drag the area to keep (Shift: square). Enter or double click crops.")
	case .Hand:
		ohint("Drag to pan. Space or middle mouse works with any tool.")
	case .Zoom:
		ohint("Click to zoom in, right click to zoom out. The mouse wheel works anywhere.")
	}
}

// ---------------------------------------------------------------------------
// Right panel: color, swatches, layers, navigator
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

// Section heading: a dim caption with a hairline running to the right edge.
osection :: proc(key, title, desc: string) {
	oui_tip(oui.element(uictx, key, "section-head"), {title, desc})
	oui.label(uictx, "t", title)
	oui.element_leaf(uictx, "line", "section-line")
	oui.end(uictx)
}

swatch_area_w: i32 = 216 // width of the swatch grid last frame, for its height

panel_right :: proc() {
	d := doc
	oui.element(uictx, "right", "sidepanel", {id = "right"})
	defer oui.end(uictx)

	// --- colour picker ---------------------------------------------------
	osection("color-head", color_linked() != nil ? "Color - editing toolbar color" : "Color", color_linked() != nil ? "Your changes here also change the toolbar color you picked, until you choose another color." : "The foreground color, the one you paint with.")
	oui_slot("picker", "color_picker")
	oui.element(uictx, "color-row", "row", {id = "color-row"})
	oui_tip(oui.element_leaf(uictx, "fg", "color-chip", {id = "fg-chip", style = fmt.tprintf("background:#%02x%02x%02x", fg.r, fg.g, fg.b)}), {"Foreground color", "The color you paint with. The sliders and fields here change it."})
	if oswatch_button("bg", bg, {"Background color", "Right-drag paints with this color. Click to swap it with the foreground color."}) do run_cmd(.Swap_Colors)
	if c, _ := oui_icon_button("swap", .Swap, cmd_tip("Swap colors", .Swap_Colors), {id = "swap-colors", enabled = true}); c {
		run_cmd(.Swap_Colors)
	}
	oui_slot("hex", "hex_field")
	h, s, v := int(fg_h + 0.5), int(fg_s * 100 + 0.5), int(fg_v * 100 + 0.5)
	otext("hsv", fmt.tprintf("%d %d %d", h, s, v), "dim", {"Hue, saturation, value", "The foreground color as hue in degrees, then saturation and value in percent."})
	oui.end(uictx)
	rgb := [3]int{int(fg.r), int(fg.g), int(fg.b)}
	names := [3]string{"R", "G", "B"}
	classes := [3]string{"wide ch-r", "wide ch-g", "wide ch-b"}
	tips := [3]Tip {
		{"Red", "The amount of red in the foreground color, from 0 to 255."},
		{"Green", "The amount of green in the foreground color, from 0 to 255."},
		{"Blue", "The amount of blue in the foreground color, from 0 to 255."},
	}
	for i in 0 ..< 3 {
		if oslider(names[i], 0, &rgb[i], 0, 255, tips[i], class = classes[i]) {
			picker_set_fg(Color{u8(rgb[0]), u8(rgb[1]), u8(rgb[2]), 255})
		}
	}

	// --- swatches ----------------------------------------------------------
	oui.element(uictx, "swatch-head", "row", {id = "swatch-head"})
	otext("t", "Swatches", "dim", {"Swatches", "Colors kept ready to use, shared by all paintings. File > Load Swatches reads a palette from a file."})
	oui.element_leaf(uictx, "spacer", "spacer")
	if obutton("Presets", 54, {"", "Replace the swatches with one of the ready-made sets."}) {
		r := oui_rect(oui_last)
		popup_begin(SWATCH_PRESET_ID, r, 110)
		for p in Swatch_Preset {
			popup_item(SWATCH_PRESET_NAMES[p], int(p), tip = SWATCH_PRESET_HELP[p])
		}
	}
	if c, _ := oui_icon_button("add", .Plus, {"Add swatch", "Add the foreground color to the swatches."}, {enabled = true}); c {
		append(&swatches, fg)
		swatch_sel = len(swatches) - 1
	}
	if c, _ := oui_icon_button("remove", .Minus, {"Remove swatch", "Remove the swatch with the outline. Click a swatch to select it."}, {enabled = len(swatches) > 1}); c {
		if swatch_sel >= 0 && swatch_sel < len(swatches) {
			ordered_remove(&swatches, swatch_sel)
			swatch_sel = clamp(swatch_sel, 0, len(swatches) - 1)
		}
	}
	oui.end(uictx)
	if ui.popup_result_id == SWATCH_PRESET_ID {
		swatches_set_preset(Swatch_Preset(ui.popup_result_val))
		ui.popup_result_id = 0
	}
	// up to three rows of swatches, scrolled with the wheel
	cell: i32 = 14
	cols := max((swatch_area_w - 4) / cell, 1)
	rows := clamp(i32((len(swatches) + int(cols) - 1) / int(cols)), 1, 3)
	oui_slot("swatches", "swatches", style = fmt.tprintf("height:%dpx", rows * cell + 4))
	oui.element(uictx, "recent-row", "row", {id = "recent-row"})
	otext("t", "Recent", "dim", {"Recent colors", "The colors you have painted with lately, newest first."})
	oui_slot("recent", "recent")
	oui.end(uictx)

	// --- layers --------------------------------------------------------------
	osection("layers-head", "Layers", "The stack of layers in this painting, topmost first. Tools change the active layer.")
	l := &d.layers[d.active_layer]
	thumbs_refresh(d)
	oui.element(uictx, "layer-props", "row", {id = "layer-props"})
	if nv, ch := ocombo("blend", 92, blend_names_slice(), int(l.blend), {"Blend mode", BLEND_TIP}); ch {
		history_push(d)
		l.blend = Blend(nv)
		doc_touch_all(d)
	}
	op := int(l.opacity) * 100 / 255
	// one undo step per drag or wheel gesture, taken before the first change
	@(static) op_pushed: bool
	if on := oui.find_node(uictx.build_parent, "s:Opacity"); on != nil && on.hovered && (ui.pressed[0] || ui.wheel != 0) && !op_pushed {
		history_push(d)
		op_pushed = true
	}
	if oslider("Opacity", 0, &op, 0, 100, {"Layer opacity", "How solid the active layer is: 100 covers what is below, 0 hides it."}, "%", class = "wide") {
		l.opacity = u8(op * 255 / 100)
		doc_touch_all(d)
	}
	if op_pushed && !ui.down[0] && ui.wheel == 0 {
		op_pushed = false
	}
	oui.end(uictx)
	oui_slot("layer-list", "layer_list")
	oui.element(uictx, "layer-buttons", "row", {id = "layer-buttons"})
	lb :: proc(key: string, ic: Icon, tip: Tip, enabled := true, lit := false) -> bool {
		c, _ := oui_icon_button(key, ic, tip, {class = "layer-btn", enabled = enabled, lit = lit})
		return c
	}
	{
		n := oui.button_begin(uictx, "new", {class = "icon-btn layer-btn"})
		oui.label(uictx, "icon", icon_text(.Layer), {class = "icon"})
		oui.label(uictx, "badge", icon_text(.Plus), {class = "icon badge"})
		oui.end(uictx)
		oui_tip(n, cmd_tip("New layer", .Layer_New))
		if n.clicked do run_cmd(.Layer_New)
	}
	if lb("dup", .Copy, cmd_tip("Duplicate layer", .Layer_Dup)) do run_cmd(.Layer_Dup)
	if lb("del", .Trash, cmd_tip("Delete layer", .Layer_Del), len(d.layers) > 1) do run_cmd(.Layer_Del)
	if lb("up", .Up, cmd_tip("Move layer up", .Layer_Up), d.active_layer < len(d.layers) - 1) do run_cmd(.Layer_Up)
	if lb("down", .Down, cmd_tip("Move layer down", .Layer_Down), d.active_layer > 0) do run_cmd(.Layer_Down)
	if lb("merge", .Merge, cmd_tip("Merge down", .Layer_Merge), d.active_layer > 0) do run_cmd(.Layer_Merge)
	if l.has_mask {
		if lb("mask", .Mask, cmd_tip("Delete mask", .Mask_Delete), lit = true) do run_cmd(.Mask_Delete)
	} else {
		if lb("mask", .Mask, d.sel != nil ? cmd_tip("Add mask from selection", .Mask_From_Sel) : cmd_tip("Add layer mask", .Mask_Add)) {
			run_cmd(d.sel != nil ? .Mask_From_Sel : .Mask_Add)
		}
	}
	oui.end(uictx)
	if show_navigator {
		osection("nav-head", "Navigator", "The whole canvas, with a box around what the view shows.")
		oui_slot("navigator", "navigator")
	}
}

// Saturation / value field and hue strip.
panel_color_picker :: proc(r: Rect) {
	sv := Rect{r.x, r.y, r.w - 20, r.h}
	hue := Rect{r.x + r.w - 12, r.y, 12, r.h}
	draw_gradient(f32(sv.x), f32(sv.y), f32(sv.w), f32(sv.h), WHITE, hsv_to_rgb(fg_h, 1, 1), false)
	draw_gradient(f32(sv.x), f32(sv.y), f32(sv.w), f32(sv.h), Color{0, 0, 0, 0}, Color{0, 0, 0, 255})
	outline_rect(sv, C_RING_HI)
	tip_area(sv, "sv", {"Saturation and value", "Drag to set the foreground color: left to right from gray to full color, top to bottom from bright to dark."})
	tip_area(hue, "hue", {"Hue", "Drag up or down to choose the hue of the foreground color."})
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
	clip_begin(rect_inset(r, -4))
	draw_rrect(f32(hue.x - 3), f32(hy - 2), f32(hue.w + 6), 5, 2, WHITE)
	draw_rrect_outline(f32(hue.x - 3), f32(hy - 2), f32(hue.w + 6), 5, 2, Color{0, 0, 0, 160})
	clip_end()
}

panel_hex_field :: proc(hr: Rect) {
	hid := make_id(hr, "text")
	if ui.focus_id != hid {
		name_set(&hex_buf, color_hex(fg))
	}
	if ch, sub := text_field(hr, &hex_buf, {"Hex color", "The foreground color as a hex code, RRGGBB. Type or paste one here."}); ch || sub {
		if c, ok := parse_hex(name_str(&hex_buf)); ok {
			picker_set_fg(c)
		}
	}
}

panel_swatches :: proc(pal: Rect) {
	swatch_area_w = pal.w
	cell: i32 = 14
	cols := max((pal.w - 4) / cell, 1)
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
			tooltip_hover(make_id(sr, "sw"), {fmt.tprintf("#%s", color_hex(c)), "Click to make this the foreground color, right-click for the background color."})
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
}

// Recently used colours.
panel_recent :: proc(r: Rect) {
	rx := r.x
	for c in recent {
		if rx + 12 > r.x + r.w do break
		sr := Rect{rx, r.y + (r.h - 12) / 2, 12, 12}
		draw_rrect(f32(sr.x), f32(sr.y), 12, 12, 2, c)
		draw_rrect_outline(f32(sr.x), f32(sr.y), 12, 12, 2, C_RING_HI)
		if ui_hover(sr) {
			tooltip_hover(make_id(sr, "rc"), {fmt.tprintf("#%s", color_hex(c)), "Click to make this the foreground color, right-click for the background color."})
			if ui.pressed[0] do set_fg(c)
			if ui.pressed[1] do bg = c
		}
		rx += 14
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
	if (stroke.active || drag.active || playing) && ui.time - thumbs_t < 0.3 {
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

// Layer rows: visibility, thumbnails, name and state; click to select, drag to reorder,
// right-click for the layer menu.
panel_layer_list :: proc(list: Rect) {
	d := doc
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
		// the row's own tip comes first: what lies inside it asks later and wins
		in_list := ui_hover(list)
		if in_list do tip_area(row, "layer-row", {name_str(&ly.name), "Click to make this the active layer. Drag to change its place in the stack, double-click for its properties, right-click for more."})
		if in_list do tip_area(rect_inset(eye, -3), "layer-eye", {"Visible", "Click to show or hide this layer."})
		icon(.Eye, eye.x, eye.y, ly.visible ? C_TEXT : C_TEXT_OFF)
		th := Rect{row.x + 22, ry + (LAYER_ROW_H - THUMB_H) / 2, THUMB_W, THUMB_H}
		draw_checker(th, 3)
		if li * 2 < len(thumbs) {
			draw_tex_at(thumbs[li * 2].tex, th.x, th.y)
		}
		outline_rect(rect_inset(th, -1), active && !d.edit_mask ? C_ACCENT : C_RING_HI)
		if in_list do tip_area(th, "layer-thumb", {name_str(&ly.name), "Click to paint on this layer's pixels. An outline shows it is what tools change. Drag to change its place in the stack."})
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
			if in_list do tip_area(mr, "layer-mask", {"Layer mask", "Click to paint on the mask: black hides, white reveals. Shift-click turns the mask's effect on or off, which a red line shows."})
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
			if in_list do tip_area({ix, ry + 17, 12, 12}, "layer-text", {"Text layer", "This layer's text can still be edited. Click it with the Text tool."})
			ix -= 13
		}
		if ly.shape != nil {
			icon(.Curve, ix, ry + 17, C_TEXT_DIM)
			if in_list do tip_area({ix, ry + 17, 12, 12}, "layer-vector", {"Vector layer", "This layer is made of outlines, which stay sharp when it is moved or resized."})
			ix -= 13
		}
		if ly.locked {
			icon(.Lock, ix, ry + 17, C_ACCENT)
			if in_list do tip_area({ix, ry + 17, 12, 12}, "layer-locked", {"Locked", "This layer can't be changed. Unlock it in its properties."})
			ix -= 13
		}
		if ly.lock_alpha {
			icon(.Lock_Alpha, ix, ry + 17, C_ACCENT)
			if in_list do tip_area({ix, ry + 17, 12, 12}, "layer-alpha", cmd_tip("Transparency locked", .Layer_Lock_Alpha))
		}
		// right-click: select the layer and open its menu (on release, so the press doesn't close it)
		if ui_hover(row) && ui_hover(list) && ui.released[1] && !popup.open {
			if d.active_layer != li do tools_commit_pending()
			d.active_layer = li
			d.edit_mask = false
			popup_begin(make_id(list, "layermenu"), Rect{ui.mx, ui.my, 1, 1}, 150)
			popup_item("Convert Text to Path", cmd = .Layer_Text_To_Path, enabled = ly.text.on)
			popup_item("Rasterize Layer", cmd = .Layer_Rasterize, enabled = ly.text.on || ly.shape != nil)
			popup_sep()
			popup_item("Duplicate Layer", cmd = .Layer_Dup)
			popup_item("Delete Layer", cmd = .Layer_Del, enabled = len(d.layers) > 1)
			popup_item("Merge Down", cmd = .Layer_Merge, enabled = li > 0)
			popup_sep()
			popup_item("Properties...", cmd = .Layer_Props)
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
	if !d.comp_lazy && (!tex_valid(tex_canvas) || tex_doc != d) {
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
	tip_area(r, "navigator", {"Navigator", "Click or drag to move the view to that part of the canvas."})
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

panel_status :: proc() {
	d := doc
	oui.element(uictx, "status", "statusbar", {id = "status"})
	defer oui.end(uictx)
	if status_t > 0 {
		oui_tip(oui.label(uictx, "tool", name_str(&status_msg), {id = "status-tool", class = "message"}), {"Messages", "Messages from the program appear here, such as why an action could not be done."})
	} else {
		label := tool_title(cur_tool)
		if (cur_tool == .Brush || cur_tool == .Oil || cur_tool == .Text) && brush_blend != .Normal {
			label = fmt.tprintf("%s - %s", label, BLEND_NAMES[brush_blend])
		}
		oui_tip(oui.label(uictx, "tool", fmt.tprintf("%s:  %s", label, TOOL_HINT[cur_tool]), {id = "status-tool"}), tool_tip(cur_tool))
	}
	oui.separator(uictx, "sep0")
	// the readout under the pointer changes every frame, so it is drawn by hand
	oui_slot("cursor-info", "cursor_info")
	if d.sel != nil {
		b := d.sel.bbox
		oui.separator(uictx, "sep1")
		oui_tip(oui.label(uictx, "sel", fmt.tprintf("Sel %dx%d", b.x1 - b.x0, b.y1 - b.y0)), {"Selection", "The width and height of the box around the selection, in pixels. Ctrl+D clears it."})
	}
	oui.element_leaf(uictx, "spacer", "spacer")
	l := &d.layers[d.active_layer]
	oui_tip(oui.label(uictx, "target", d.edit_mask ? fmt.tprintf("%s (mask)", name_str(&l.name)) : name_str(&l.name)), {"Active layer", "The layer tools change. It says (mask) when you are painting on its mask."})
	oui.separator(uictx, "sep2")
	if len(d.frames) > 1 {
		oui_tip(oui.label(uictx, "frame", fmt.tprintf("Frame %d / %d", d.active_frame + 1, len(d.frames))), {"Current frame", "The frame you are working on. View > Timeline shows them all, and , and . step through them."})
		oui.separator(uictx, "sep-frame")
	}
	oui_tip(oui.label(uictx, "size", fmt.tprintf("%d x %d", d.w, d.h)), {"Canvas size", "Width by height in pixels. Change it with Image > Image Size or Canvas Size."})
	oui.separator(uictx, "sep3")
	oui_tip(oui.label(uictx, "zoom", fmt.tprintf("%d%%", int(d.zoom * 100 + 0.5)), {class = "strong"}), {"Zoom", "Use the mouse wheel to zoom, Ctrl+0 to fit the canvas and Ctrl+1 for 100%."})
}

// Pixel position and colour under the pointer, in the status bar.
panel_cursor_info :: proc(r: Rect) {
	d := doc
	tip_area(r, "cursor-info", {"Under the pointer", "The position on the canvas in pixels, from the top left corner, and the color you see there."})
	if !hover_valid || !pt_in_doc(hover_pt) do return
	ty := r.y + (r.h - FONT_CAP) / 2
	q := ipt(hover_pt)
	textf(r.x, ty, C_TEXT, "%d, %d", q.x, q.y)
	if d.comp_lazy do return // the composite is only made once frames stop changing
	doc_refresh_comp(d)
	c := d.comp[q.y * d.w + q.x]
	swr := Rect{r.x + 74, r.y + (r.h - 10) / 2, 10, 10}
	draw_rrect(f32(swr.x), f32(swr.y), 10, 10, 2, c)
	draw_rrect_outline(f32(swr.x), f32(swr.y), 10, 10, 2, C_RING_HI)
	text(r.x + 90, ty, color_hex(c), C_TEXT_DIM)
}
