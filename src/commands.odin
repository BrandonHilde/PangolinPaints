package pangolin

import "core:fmt"

Cmd :: enum {
	None,
	// file
	New,
	Open,
	Save,
	Save_As,
	Place_Image,
	Export,
	Close_Doc,
	Exit,
	Swatches_Load,
	Swatches_Save,
	// edit
	Undo,
	Redo,
	Cut,
	Copy,
	Copy_Merged,
	Paste,
	Clear,
	Fill_Fg,
	Fill_Bg,
	Brush_Settings,
	Preferences,
	// image
	Image_Size,
	Canvas_Size,
	Crop_Sel,
	Trim,
	Rotate_CW,
	Rotate_CCW,
	Rotate_180,
	Rotate_Any,
	Flip_H,
	Flip_V,
	Flatten,
	Auto_Contrast,
	Curves,
	// layer
	Layer_New,
	Layer_Dup,
	Layer_Del,
	Layer_Up,
	Layer_Down,
	Layer_Merge,
	Layer_Props,
	Layer_Via_Copy,
	Layer_Via_Cut,
	Layer_Lock_Alpha,
	Mask_Add,
	Mask_From_Sel,
	Mask_Delete,
	Mask_Apply,
	Mask_Edit,
	Mask_Enable,
	// select
	Select_All,
	Deselect,
	Invert_Sel,
	Select_Alpha,
	Feather,
	Grow,
	Shrink,
	// view
	Zoom_In,
	Zoom_Out,
	Zoom_Fit,
	Zoom_1,
	Zoom_2,
	Toggle_Pixel_Grid,
	Toggle_Thirds,
	Toggle_Grid,
	Toggle_Snap,
	Grid_Settings,
	Toggle_Navigator,
	Toggle_Canvas_Mode,
	Toggle_Seamless,
	Cycle_Canvas_Bg,
	// help
	Help_Keys,
	About,
	// workspaces
	Ws_Manage,
	Ws_Import,
	Ws_Export,
	// misc
	Swap_Colors,
	Default_Colors,
	Brush_Smaller,
	Brush_Bigger,
	Opacity_10,
	Opacity_20,
	Opacity_30,
	Opacity_40,
	Opacity_50,
	Opacity_60,
	Opacity_70,
	Opacity_80,
	Opacity_90,
	Opacity_100,
	// tools (must stay in the same order as `Tool`)
	Tool_Brush,
	Tool_Oil,
	Tool_Smudge,
	Tool_Eraser,
	Tool_Blur,
	Tool_Dodge,
	Tool_Clone,
	Tool_Bucket,
	Tool_Gradient,
	Tool_Picker,
	Tool_Text,
	Tool_Select_Rect,
	Tool_Select_Ellipse,
	Tool_Lasso,
	Tool_Wand,
	Tool_Move,
	Tool_Transform,
	Tool_Crop,
	Tool_Hand,
	Tool_Zoom,
	// adjustments and filters (must stay in the same order as `Fx`)
	Fx_First,
	Fx_Last = Fx_First + len(Fx) - 1,
	// saved and built-in workspaces, in the order of `ws_entries`
	Ws_First,
	Ws_Last = Ws_First + WS_MAX - 1,
}

Shortcut :: struct {
	cmd:              Cmd,
	key:              KeyboardKey,
	ctrl, shift, alt: bool,
}

SHORTCUTS := [?]Shortcut {
	{.New, .N, true, false, false},
	{.Open, .O, true, false, false},
	{.Save, .S, true, false, false},
	{.Save_As, .S, true, true, false},
	{.Export, .E, true, true, false},
	{.Close_Doc, .W, true, false, false},
	{.Exit, .Q, true, false, false},
	{.Undo, .Z, true, false, false},
	{.Redo, .Y, true, false, false},
	{.Redo, .Z, true, true, false},
	{.Cut, .X, true, false, false},
	{.Copy, .C, true, false, false},
	{.Copy_Merged, .C, true, true, false},
	{.Paste, .V, true, false, false},
	{.Clear, .DELETE, false, false, false},
	{.Clear, .BACKSPACE, false, false, false},
	{.Fill_Fg, .BACKSPACE, false, false, true},
	{.Fill_Bg, .BACKSPACE, true, false, false},
	{.Brush_Settings, .F5, false, false, false},
	{.Image_Size, .I, true, false, true},
	{.Canvas_Size, .C, true, false, true},
	{.Auto_Contrast, .L, true, true, false},
	{.Curves, .M, true, false, false},
	{.Fx_First + Cmd(Fx.Levels), .L, true, false, false},
	{.Fx_First + Cmd(Fx.Hue_Saturation), .U, true, false, false},
	{.Fx_First + Cmd(Fx.Color_Balance), .B, true, false, false},
	{.Fx_First + Cmd(Fx.Desaturate), .U, true, true, false},
	{.Fx_First + Cmd(Fx.Invert), .I, true, false, false},
	{.Layer_New, .N, true, true, false},
	{.Layer_Via_Copy, .J, true, false, false},
	{.Layer_Via_Cut, .J, true, true, false},
	{.Layer_Merge, .E, true, false, false},
	{.Layer_Lock_Alpha, .SLASH, false, false, false},
	{.Mask_Edit, .BACKSLASH, false, false, false},
	{.Select_All, .A, true, false, false},
	{.Deselect, .D, true, false, false},
	{.Invert_Sel, .I, true, true, false},
	{.Feather, .F6, false, true, false},
	{.Zoom_In, .EQUAL, true, false, false},
	{.Zoom_In, .EQUAL, false, false, false},
	{.Zoom_In, .KP_ADD, false, false, false},
	{.Zoom_Out, .MINUS, true, false, false},
	{.Zoom_Out, .MINUS, false, false, false},
	{.Zoom_Out, .KP_SUBTRACT, false, false, false},
	{.Zoom_Fit, .ZERO, true, false, false},
	{.Zoom_1, .ONE, true, false, false},
	{.Zoom_2, .TWO, true, false, false},
	{.Toggle_Canvas_Mode, .TAB, false, false, false},
	{.Toggle_Pixel_Grid, .APOSTROPHE, true, true, false},
	{.Toggle_Thirds, .APOSTROPHE, true, false, false},
	{.Toggle_Grid, .SEMICOLON, true, false, false},
	{.Toggle_Snap, .SEMICOLON, true, true, false},
	{.Tool_Brush, .B, false, false, false},
	{.Tool_Oil, .N, false, false, false},
	{.Tool_Smudge, .R, false, false, false},
	{.Tool_Blur, .R, false, true, false},
	{.Tool_Eraser, .E, false, false, false},
	{.Tool_Dodge, .O, false, false, false},
	{.Tool_Clone, .S, false, false, false},
	{.Tool_Bucket, .G, false, false, false},
	{.Tool_Gradient, .G, false, true, false},
	{.Tool_Picker, .I, false, false, false},
	{.Tool_Text, .T, false, true, false},
	{.Tool_Select_Rect, .M, false, false, false},
	{.Tool_Select_Ellipse, .M, false, true, false},
	{.Tool_Lasso, .L, false, false, false},
	{.Tool_Wand, .W, false, false, false},
	{.Tool_Move, .V, false, false, false},
	{.Tool_Transform, .T, false, false, false},
	{.Tool_Transform, .T, true, false, false},
	{.Tool_Crop, .C, false, false, false},
	{.Tool_Hand, .H, false, false, false},
	{.Tool_Zoom, .Z, false, false, false},
	{.Swap_Colors, .X, false, false, false},
	{.Default_Colors, .D, false, false, false},
	{.Brush_Smaller, .LEFT_BRACKET, false, false, false},
	{.Brush_Bigger, .RIGHT_BRACKET, false, false, false},
	{.Opacity_10, .ONE, false, true, false},
	{.Opacity_20, .TWO, false, true, false},
	{.Opacity_30, .THREE, false, true, false},
	{.Opacity_40, .FOUR, false, true, false},
	{.Opacity_50, .FIVE, false, true, false},
	{.Opacity_60, .SIX, false, true, false},
	{.Opacity_70, .SEVEN, false, true, false},
	{.Opacity_80, .EIGHT, false, true, false},
	{.Opacity_90, .NINE, false, true, false},
	{.Opacity_100, .ZERO, false, true, false},
	{.Help_Keys, .F1, false, false, false},
}

key_name :: proc(k: KeyboardKey) -> string {
	#partial switch k {
	case .A ..= .Z:
		return fmt.tprintf("%c", rune(int(k)))
	case .ZERO ..= .NINE:
		return fmt.tprintf("%c", rune(int(k)))
	case .F1 ..= .F12:
		return fmt.tprintf("F%d", int(k) - int(KeyboardKey.F1) + 1)
	case .DELETE:
		return "Del"
	case .TAB:
		return "Tab"
	case .BACKSPACE:
		return "Backspace"
	case .ESCAPE:
		return "Esc"
	case .ENTER:
		return "Enter"
	case .EQUAL:
		return "+"
	case .KP_ADD:
		return "Num+"
	case .MINUS:
		return "-"
	case .KP_SUBTRACT:
		return "Num-"
	case .APOSTROPHE:
		return "'"
	case .SEMICOLON:
		return ";"
	case .LEFT_BRACKET:
		return "["
	case .RIGHT_BRACKET:
		return "]"
	case .SLASH:
		return "/"
	case .BACKSLASH:
		return "\\"
	}
	return "?"
}

shortcut_text_for :: proc(s: Shortcut) -> string {
	return fmt.tprintf("%s%s%s%s", s.ctrl ? "Ctrl+" : "", s.shift ? "Shift+" : "", s.alt ? "Alt+" : "", key_name(s.key))
}

shortcut_text :: proc(cmd: Cmd) -> string {
	for s in SHORTCUTS {
		if s.cmd == cmd {
			return shortcut_text_for(s)
		}
	}
	return ""
}

cmd_repeats :: proc(c: Cmd) -> bool {
	#partial switch c {
	case .Brush_Smaller, .Brush_Bigger, .Undo, .Redo, .Zoom_In, .Zoom_Out:
		return true
	}
	return false
}

shortcuts_update :: proc() {
	if ui.focus_id != 0 || dialog.kind != .None || popup.open || text_edit.active || text_end_time == ui.time {
		return
	}
	if tool_groups_key_capture() {
		return
	}
	// pending transform / crop: Enter applies, Esc cancels
	if xform.active || crop.active {
		if IsKeyPressed(.ENTER) || IsKeyPressed(.KP_ENTER) {
			if xform.active do xform_commit()
			if crop.active do crop_commit()
			return
		}
		if IsKeyPressed(.ESCAPE) {
			if xform.active do xform_cancel()
			crop.active = false
			return
		}
	} else if IsKeyPressed(.ESCAPE) && doc.sel != nil {
		run_cmd(.Deselect)
		return
	}
	if drag.active || stroke.active {
		return
	}
	if tool_groups_hotkeys() {
		return
	}
	for s in SHORTCUTS {
		if !(IsKeyPressed(s.key) || (cmd_repeats(s.cmd) && IsKeyPressedRepeat(s.key))) {
			continue
		}
		if s.ctrl != ui.ctrl || s.shift != ui.shift || s.alt != ui.alt {
			continue
		}
		run_cmd(s.cmd)
		return
	}
	// nudge with arrow keys using the move tool
	if cur_tool == .Move {
		dx, dy := 0, 0
		if key_hit(.LEFT) do dx = -1
		if key_hit(.RIGHT) do dx = 1
		if key_hit(.UP) do dy = -1
		if key_hit(.DOWN) do dy = 1
		if dx != 0 || dy != 0 {
			st := ui.shift ? 10 : 1
			move_nudge(dx * st, dy * st)
		}
	}
}

select_tool :: proc(t: Tool) {
	if t != cur_tool {
		tools_commit_pending()
	}
	cur_tool = t
	if t == .Transform {
		xform_begin()
	}
}

run_cmd :: proc(cmd: Cmd) {
	d := doc
	if cmd >= .Tool_Brush && cmd <= .Tool_Zoom {
		select_tool_in_group(Tool(int(cmd) - int(Cmd.Tool_Brush)))
		return
	}
	// commands below act on the document; finish pending interactions first
	#partial switch cmd {
	case .Zoom_In, .Zoom_Out, .Zoom_Fit, .Zoom_1, .Zoom_2, .Toggle_Pixel_Grid, .Toggle_Thirds, .Toggle_Grid, .Toggle_Snap, .Grid_Settings, .Toggle_Navigator, .Toggle_Canvas_Mode, .Toggle_Seamless, .Cycle_Canvas_Bg, .Swap_Colors, .Default_Colors, .Brush_Smaller, .Brush_Bigger, .Help_Keys, .About, .Brush_Settings, .None:
	case .Opacity_10 ..= .Opacity_100:
	case:
		tools_commit_pending()
	}
	if cmd >= .Fx_First && cmd <= .Fx_Last {
		fx_open(Fx(int(cmd) - int(Cmd.Fx_First)))
		return
	}
	if cmd >= .Ws_First && cmd <= .Ws_Last {
		workspace_apply_index(int(cmd) - int(Cmd.Ws_First))
		return
	}
	if cmd >= .Opacity_10 && cmd <= .Opacity_100 {
		t := paint_tool(cur_tool) ? cur_tool : Tool.Brush
		brushes[t].opacity = (int(cmd) - int(Cmd.Opacity_10) + 1) * 10
		set_statusf("Opacity %d%%", brushes[t].opacity)
		return
	}
	switch cmd {
	case .None, .Tool_Brush ..= .Tool_Zoom, .Fx_First ..= .Fx_Last, .Ws_First ..= .Ws_Last, .Opacity_10 ..= .Opacity_100:
	case .New:
		dialog_open(.New_Doc)
	case .Open:
		file_open_dialog()
	case .Save:
		file_save(d, false)
	case .Save_As:
		file_save(d, true)
	case .Place_Image:
		file_place_dialog()
	case .Export:
		dialog_open(.Export)
	case .Close_Doc:
		request_close(d)
	case .Exit:
		request_quit()
	case .Swatches_Load:
		file_swatches_load()
	case .Swatches_Save:
		file_swatches_save()
	case .Ws_Manage:
		dialog_open(.Workspaces)
	case .Ws_Import:
		workspace_import()
	case .Ws_Export:
		workspace_export()

	case .Undo:
		if !history_undo(d) {
			set_status("Nothing to undo")
		}
	case .Redo:
		if !history_redo(d) {
			set_status("Nothing to redo")
		}
	case .Cut:
		edit_copy(true, false)
	case .Copy:
		edit_copy(false, false)
	case .Copy_Merged:
		edit_copy(false, true)
	case .Paste:
		edit_paste()
	case .Clear:
		edit_clear()
	case .Fill_Fg:
		edit_fill(fg)
	case .Fill_Bg:
		edit_fill(bg)
	case .Brush_Settings:
		dialog_open(.Brush_Settings)
	case .Preferences:
		dialog_open(.Prefs)

	case .Image_Size:
		dialog_open(.Image_Size)
	case .Canvas_Size:
		dialog_open(.Canvas_Size)
	case .Crop_Sel:
		if d.sel == nil || !doc_crop(d, d.sel.bbox) {
			set_status("Make a selection first")
		}
	case .Trim:
		if b, ok := doc_content_bounds(d); !ok || !doc_crop(d, b) {
			set_status("Nothing to trim")
		}
	case .Rotate_CW:
		doc_rotate(d, 1)
	case .Rotate_CCW:
		doc_rotate(d, 3)
	case .Rotate_180:
		doc_rotate(d, 2)
	case .Rotate_Any:
		dialog_open(.Rotate)
	case .Flip_H:
		doc_flip(d, true)
	case .Flip_V:
		doc_flip(d, false)
	case .Flatten:
		if !doc_flatten(d) {
			set_status("Only one layer")
		}
	case .Auto_Contrast:
		edit_auto_contrast()
	case .Curves:
		dialog_open(.Curves)

	case .Layer_New:
		doc_add_layer(d)
	case .Layer_Dup:
		doc_dup_layer(d)
	case .Layer_Del:
		if !doc_delete_layer(d) {
			set_status("Cannot delete the only layer")
		}
	case .Layer_Up:
		doc_move_layer(d, 1)
	case .Layer_Down:
		doc_move_layer(d, -1)
	case .Layer_Merge:
		if !doc_merge_down(d) {
			set_status("No layer below to merge into")
		}
	case .Layer_Props:
		dialog_open(.Layer_Props)
	case .Layer_Via_Copy:
		edit_layer_via(false)
	case .Layer_Via_Cut:
		edit_layer_via(true)
	case .Layer_Lock_Alpha:
		l := &d.layers[d.active_layer]
		l.lock_alpha = !l.lock_alpha
		set_status(l.lock_alpha ? "Transparency locked" : "Transparency unlocked")
	case .Mask_Add:
		if !doc_add_mask(d, false) {
			set_status("Layer already has a mask")
		}
	case .Mask_From_Sel:
		if d.sel == nil {
			set_status("Make a selection first")
		} else if !doc_add_mask(d, true) {
			set_status("Layer already has a mask")
		}
	case .Mask_Delete:
		doc_delete_mask(d, false)
	case .Mask_Apply:
		doc_delete_mask(d, true)
	case .Mask_Edit:
		l := &d.layers[d.active_layer]
		if l.has_mask {
			d.edit_mask = !d.edit_mask
			set_status(d.edit_mask ? "Painting on the layer mask" : "Painting on the layer")
		} else {
			set_status("Layer has no mask")
		}
	case .Mask_Enable:
		l := &d.layers[d.active_layer]
		if l.has_mask {
			history_push(d)
			l.mask_on = !l.mask_on
			doc_touch_all(d)
		}

	case .Select_All:
		history_push(d)
		doc_sel_all(d)
	case .Deselect:
		if d.sel != nil {
			history_push(d)
			doc_sel_clear(d)
		}
	case .Invert_Sel:
		history_push(d)
		doc_sel_invert(d)
	case .Select_Alpha:
		history_push(d)
		doc_sel_from_alpha(d)
	case .Feather:
		dialog_open(.Feather)
	case .Grow:
		dialog_open(.Grow)
	case .Shrink:
		dialog_open(.Shrink)

	case .Zoom_In:
		zoom_center(d.zoom * 1.5)
	case .Zoom_Out:
		zoom_center(d.zoom / 1.5)
	case .Zoom_Fit:
		view_fit(d)
	case .Zoom_1:
		zoom_center(1)
	case .Zoom_2:
		zoom_center(2)
	case .Toggle_Pixel_Grid:
		show_pixel_grid = !show_pixel_grid
	case .Toggle_Thirds:
		show_thirds = !show_thirds
	case .Toggle_Grid:
		show_grid = !show_grid
		set_status(show_grid ? (snap_grid ? "Grid on, snapping" : "Grid on") : "Grid off")
	case .Toggle_Snap:
		snap_grid = !snap_grid
		if snap_grid do show_grid = true
		set_status(snap_grid ? "Snap to grid on" : "Snap to grid off")
	case .Grid_Settings:
		dialog_open(.Grid)
	case .Toggle_Navigator:
		show_navigator = !show_navigator
	case .Toggle_Canvas_Mode:
		canvas_mode = !canvas_mode
	case .Toggle_Seamless:
		seamless_mode = !seamless_mode
	case .Cycle_Canvas_Bg:
		bg_mode = (bg_mode + 1) % 4

	case .Help_Keys:
		dialog_open(.Shortcuts)
	case .About:
		dialog_open(.About)

	case .Swap_Colors:
		a, b := fg, bg
		set_fg(b)
		bg = a
	case .Default_Colors:
		set_fg(Color{0, 0, 0, 255})
		bg = Color{255, 255, 255, 255}
	case .Brush_Smaller:
		t := paint_tool(cur_tool) ? cur_tool : Tool.Brush
		b := &brushes[t]
		b.size = max(b.size - max(b.size / 8, 1), 1)
	case .Brush_Bigger:
		t := paint_tool(cur_tool) ? cur_tool : Tool.Brush
		b := &brushes[t]
		b.size = min(b.size + max(b.size / 8, 1), BRUSH_MAX)
	}
}

BRUSH_MAX :: 1000
