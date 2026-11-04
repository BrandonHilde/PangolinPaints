package pangolin

import "core:fmt"

import oui "odinui:odinui"

// ---------------------------------------------------------------------------
// The timeline in the panel under the canvas: a bar of buttons, and a layers-by-frames grid drawn by hand.
// ---------------------------------------------------------------------------

// An icon button with a small + or - badge.
@(private = "file")
obadge_button :: proc(key: string, ic: Icon, plus: bool, tip: Tip, enabled := true) -> bool {
	n := oui.button_begin(uictx, key, {class = "icon-btn tl-btn", disabled = !enabled})
	oui.label(uictx, "icon", icon_text(ic), {class = "icon"})
	oui.label(uictx, "badge", icon_text(plus ? .Plus : .Minus), {class = "icon badge"})
	oui.end(uictx)
	oui_tip(n, tip)
	return n.clicked && enabled
}

timeline_bar_controls :: proc() {
	d := doc
	tb :: proc(key: string, ic: Icon, tip: Tip, enabled := true, lit := false) -> bool {
		c, _ := oui_icon_button(key, ic, tip, {class = "tl-btn", enabled = enabled, lit = lit})
		return c
	}
	if obadge_button("frame-new", .Frame, true, cmd_tip("New frame", .Frame_New)) do run_cmd(.Frame_New)
	if tb("frame-dup", .Copy, cmd_tip("Duplicate frame", .Frame_Dup)) do run_cmd(.Frame_Dup)
	if obadge_button("frame-vis", .Eye, true, cmd_tip("New frame from visible", .Frame_From_Visible)) do run_cmd(.Frame_From_Visible)
	if obadge_button("frame-del", .Frame, false, cmd_tip("Delete frame", .Frame_Del), len(d.frames) > 1) do run_cmd(.Frame_Del)
	oui.element_leaf(uictx, "gap1", "tl-gap")
	if tb("first", .First, cmd_tip("First frame", .Frame_First)) do run_cmd(.Frame_First)
	if tb("prev", .Left, cmd_tip("Previous frame", .Frame_Prev)) do run_cmd(.Frame_Prev)
	if tb("play", playing ? .Stop : .Play, cmd_tip(playing ? "Pause" : "Play", .Play), lit = playing) do run_cmd(.Play)
	if tb("next", .Right, cmd_tip("Next frame", .Frame_Next)) do run_cmd(.Frame_Next)
	if tb("last", .Last, cmd_tip("Last frame", .Frame_Last)) do run_cmd(.Frame_Last)
	oui.element_leaf(uictx, "gap2", "tl-gap")
	timeline_tag_controls()
	if obutton(fmt.tprintf("%d ms", d.frames[d.active_frame].duration), 58, {"Frame duration", "How long the current frame shows when the animation plays. Click to change it."}, key = "duration") {
		run_cmd(.Frame_Props)
	}
	oui.element_leaf(uictx, "gap3", "tl-gap")
	if tb("onion", .Onion, cmd_tip("Onion skin", .Toggle_Onion), lit = onion_on) do run_cmd(.Toggle_Onion)
	if onion_on {
		oslider("<", 32, &onion_before, 0, 5, {"Frames before", "How many earlier frames show over the canvas, tinted slightly red."}, key = "onion-before")
		oslider(">", 32, &onion_after, 0, 5, {"Frames after", "How many later frames show over the canvas, tinted slightly blue."}, key = "onion-after")
		oslider("", 42, &onion_alpha, 5, 100, {"Onion strength", "How strongly the neighbouring frames show. Frames further away fade."}, "%", key = "onion-alpha")
	}
}

tl_scroll_x, tl_scroll_y: i32
tl_drag := -1 // layer being dragged in the timeline, or -1
tl_drag_y0: i32
tl_drag_on: bool

TL_FRAME_W :: 20
TL_ROW_H :: 16
TL_HEAD_H :: 20

// A frame's right-click menu, on the timeline's cells and frame numbers.
@(private = "file")
frame_menu :: proc(id: u32) {
	popup_begin(id, Rect{ui.mx, ui.my, 1, 1}, 170)
	popup_item("New Frame", cmd = .Frame_New)
	popup_item("Duplicate Frame", cmd = .Frame_Dup)
	popup_item("New Frame from Visible", cmd = .Frame_From_Visible)
	popup_item("Delete Frame", cmd = .Frame_Del, enabled = len(doc.frames) > 1)
	popup_sep()
	popup_item("Move Frame Left", cmd = .Frame_Left, enabled = doc.active_frame > 0)
	popup_item("Move Frame Right", cmd = .Frame_Right, enabled = doc.active_frame < len(doc.frames) - 1)
	popup_sep()
	popup_item("Frame Properties...", cmd = .Frame_Props)
}

panel_timeline_grid :: proc(body: Rect) {
	d := doc
	// the names give way first, so the frames stay in view at a large UI scale
	hdr_w := min(150, body.w * 2 / 5)
	names := Rect{body.x, body.y + TL_HEAD_H, hdr_w, body.h - TL_HEAD_H}
	head := Rect{body.x + hdr_w, body.y, body.w - hdr_w, TL_HEAD_H}
	grid := Rect{body.x + hdr_w, body.y + TL_HEAD_H, body.w - hdr_w, body.h - TL_HEAD_H}

	nlayers := i32(len(d.layers))
	nframes := i32(len(d.frames))
	content_w := nframes * TL_FRAME_W + 20
	content_h := nlayers * TL_ROW_H

	if (ui_hover(grid) || ui_hover(names) || ui_hover(head)) && ui.wheel != 0 {
		if ui.shift {
			tl_scroll_x -= i32(ui.wheel) * TL_FRAME_W * 2
		} else {
			tl_scroll_y -= i32(ui.wheel) * TL_ROW_H
		}
	}
	tl_scroll_x = clamp(tl_scroll_x, 0, max(content_w - grid.w, 0))
	tl_scroll_y = clamp(tl_scroll_y, 0, max(content_h - grid.h, 0))
	// keep the current frame in view while playing or stepping
	af := i32(d.active_frame)
	if af * TL_FRAME_W < tl_scroll_x {
		tl_scroll_x = af * TL_FRAME_W
	} else if (af + 1) * TL_FRAME_W > tl_scroll_x + grid.w {
		tl_scroll_x = (af + 1) * TL_FRAME_W - grid.w
	}

	fill_rect(body, C_PANEL_DK)
	vline(body.x + hdr_w - 1, body.y, body.h, C_RING_HI)
	hline(body.x, body.y + TL_HEAD_H - 1, body.w, C_RING_HI)
	clip_begin(Rect{body.x, body.y, hdr_w, TL_HEAD_H})
	tip_text(body.x + 8, body.y + (TL_HEAD_H - FONT_CAP) / 2, "Layers", C_TEXT_DIM, {"Layers", "Each row is a layer, the top one in front. The columns on the right are the frames."})
	clip_end()

	// the frame numbers, and the tags under them
	clip_begin(head)
	for f in 0 ..< nframes {
		fx := head.x + f * TL_FRAME_W - tl_scroll_x
		if fx + TL_FRAME_W < head.x || fx > head.x + head.w do continue
		active := int(f) == d.active_frame
		if active do draw_rrect(f32(fx + 1), f32(head.y + 1), f32(TL_FRAME_W - 2), f32(TL_HEAD_H - 3), RADIUS, C_ACTIVE)
		s := fmt.tprintf("%d", f + 1)
		text(fx + (TL_FRAME_W - text_w(s)) / 2, head.y + 3, s, active ? WHITE : C_TEXT_DIM)
		vline(fx + TL_FRAME_W - 1, head.y, TL_HEAD_H, C_RING)
	}
	head_num := Rect{head.x, head.y, head.w, TL_HEAD_H - 6}
	tip_area(head_num, "scrub", {"Frames", "Click a number to go to that frame, or drag along them to scrub through the animation. Right-click for the frame's menu."})
	for &t, ti in d.tags {
		tx0 := head.x + i32(t.from) * TL_FRAME_W - tl_scroll_x
		tw := i32(t.to - t.from + 1) * TL_FRAME_W
		tr := Rect{tx0 + 1, head.y + TL_HEAD_H - 6, tw - 2, 4}
		draw_rrect(f32(tr.x), f32(tr.y), f32(tr.w), f32(tr.h), 2, t.color)
		if ti == play_tag do draw_rrect_outline(f32(tr.x - 1), f32(tr.y - 1), f32(tr.w + 2), f32(tr.h + 2), 2, WHITE)
		tip_area(tr, "tag", {name_str(&t.name), "This tag's range of frames. Click to play only these frames, again to play all."})
		if ui_hover(tr) && ui.pressed[0] {
			play_tag = play_tag == ti ? -1 : ti
		}
	}
	clip_end()
	hid := make_id(head_num, "scrub")
	if ui_hover(head_num) && ui.pressed[0] do ui.active_id = hid
	if ui.active_id == hid && ui.down[0] {
		stop_playback()
		set_frame(int((ui.mx - head.x + tl_scroll_x) / TL_FRAME_W))
	}
	if ui_hover(head_num) && ui.released[1] && !popup.open {
		f := int((ui.mx - head.x + tl_scroll_x) / TL_FRAME_W)
		if f < len(d.frames) {
			stop_playback()
			set_frame(f)
			frame_menu(make_id(head, "framemenu"))
		}
	}

	// layer rows
	clip_begin(names)
	for i in 0 ..< nlayers {
		li := int(nlayers - 1 - i)
		ry := names.y + i * TL_ROW_H - tl_scroll_y
		if ry + TL_ROW_H < names.y || ry > names.y + names.h do continue
		l := &d.layers[li]
		row := Rect{names.x, ry, names.w - 1, TL_ROW_H}
		if li == d.active_layer {
			fill_rect(row, C_ACCENT_TINT)
			fill_rect(Rect{row.x, row.y, 2, row.h}, C_ACCENT)
		} else if ui_hover(row) {
			fill_rect(row, Color{255, 255, 255, 12})
		}
		hline(row.x, ry + TL_ROW_H - 1, row.w, C_RING)
		eye := Rect{row.x + 5, ry + 2, 12, 12}
		lock := Rect{row.x + 20, ry + 2, 12, 12}
		icon(.Eye, eye.x, eye.y, l.visible ? C_TEXT : C_TEXT_OFF)
		icon(.Lock, lock.x, lock.y, l.locked ? C_ACCENT : C_TEXT_OFF)
		text_clipped(Rect{row.x + 38, ry, row.w - 40, TL_ROW_H}, name_str(&l.name), l.visible ? C_TEXT : C_TEXT_DIM)
		if ui_hover(names) {
			tip_area(row, "tl-row", {name_str(&l.name), "Click to work on this layer, double-click for its properties, right-click for its menu. Drag to move it."})
			tip_area(eye, "tl-eye", {"Visible", "Click to show or hide this layer on all frames."})
			tip_area(lock, "tl-lock", {"Locked", "Click to lock or unlock this layer. Tools can't change a locked layer."})
		}
		if ui_hover(row) && ui_hover(names) && ui.pressed[0] {
			switch {
			case in_rect(eye, ui.mx, ui.my):
				history_push(d)
				l.visible = !l.visible
				doc_touch_all(d)
			case in_rect(lock, ui.mx, ui.my):
				history_push(d)
				l.locked = !l.locked
			case:
				if d.active_layer != li do tools_commit_pending()
				d.active_layer = li
				d.edit_mask = false
				tl_drag, tl_drag_y0, tl_drag_on = li, ui.my, false
				if ui.dbl_click do dialog_open(.Layer_Props)
			}
		}
		// right-click: select the layer and open its menu (on release, so the press doesn't close it)
		if ui_hover(row) && ui_hover(names) && ui.released[1] && !popup.open {
			if d.active_layer != li do tools_commit_pending()
			d.active_layer = li
			d.edit_mask = false
			popup_begin(make_id(names, "tl-layermenu"), Rect{ui.mx, ui.my, 1, 1}, 150)
			popup_item("New Layer", cmd = .Layer_New)
			popup_item("Duplicate Layer", cmd = .Layer_Dup)
			popup_item("Delete Layer", cmd = .Layer_Del, enabled = len(d.layers) > 1)
			popup_item("Merge Down", cmd = .Layer_Merge, enabled = li > 0)
			popup_sep()
			popup_item("Properties...", cmd = .Layer_Props)
		}
	}
	// drag a row up or down to reorder; the line shows where it will land
	if tl_drag >= 0 && tl_drag < int(nlayers) {
		if !tl_drag_on && ui.down[0] && abs(ui.my - tl_drag_y0) > 4 do tl_drag_on = true
		if tl_drag_on {
			ri := clamp((ui.my - names.y + tl_scroll_y) / TL_ROW_H, 0, nlayers - 1)
			target := int(nlayers - 1 - ri)
			if target != tl_drag {
				ly := names.y + (target > tl_drag ? ri : ri + 1) * TL_ROW_H - tl_scroll_y
				fill_rect(Rect{names.x, ly - 1, names.w - 1, 2}, C_ACCENT)
				if ui.released[0] {
					history_push(d)
					for tl_drag < target {
						d.layers[tl_drag], d.layers[tl_drag + 1] = d.layers[tl_drag + 1], d.layers[tl_drag]
						tl_drag += 1
					}
					for tl_drag > target {
						d.layers[tl_drag], d.layers[tl_drag - 1] = d.layers[tl_drag - 1], d.layers[tl_drag]
						tl_drag -= 1
					}
					d.active_layer = target
					doc_touch_all(d)
				}
			}
		}
		if !ui.down[0] do tl_drag, tl_drag_on = -1, false
	} else {
		tl_drag, tl_drag_on = -1, false
	}
	clip_end()

	// cells
	clip_begin(grid)
	for i in 0 ..< nlayers {
		li := int(nlayers - 1 - i)
		ry := grid.y + i * TL_ROW_H - tl_scroll_y
		if ry + TL_ROW_H < grid.y || ry > grid.y + grid.h do continue
		l := &d.layers[li]
		spans := layer_spans(l)
		for f in 0 ..< nframes {
			fx := grid.x + f * TL_FRAME_W - tl_scroll_x
			if fx + TL_FRAME_W < grid.x || fx > grid.x + grid.w do continue
			cr := Rect{fx + 1, ry + 1, TL_FRAME_W - 2, TL_ROW_H - 2}
			active_cel := li == d.active_layer && int(f) == d.active_frame
			col := C_PANEL
			if int(f) == d.active_frame || li == d.active_layer do col = C_PANEL_LT
			if active_cel do col = C_ACTIVE
			draw_rrect(f32(cr.x), f32(cr.y), f32(cr.w), f32(cr.h), 2, col)
			// what is on the cel: a dot for pixels, a bar for a text or vector layer spanning the frames
			shows := !flat_hides(frame_flat_id(d, int(f)), l)
			pix, _ := frame_tiles(d, l, int(f))
			if shows && pix != nil && tiles_count(pix) > 0 {
				mark := active_cel ? WHITE : C_TEXT_DIM
				if spans {
					fill_rect(Rect{cr.x - 1, cr.y + cr.h / 2 - 1, cr.w + 2, 2}, mark)
				} else {
					draw_rrect(f32(cr.x + cr.w / 2 - 2), f32(cr.y + cr.h / 2 - 2), 4, 4, 2, mark)
				}
			}
			if ui_hover(grid) {
				desc := "A cel: this layer's picture in this frame. Click to work on it, double-click for the frame's duration, right-click for the frame's menu."
				if spans {
					desc = "A text or vector layer shows the same on every frame. Editing its pixels gives each frame its own copy."
				} else if frame_flat_id(d, int(f)) > 0 {
					desc = "A frame made from visible: it holds one flat image, and the text and vector layers from before it do not show on it."
				}
				tip_area(cr, "cel", {fmt.tprintf("Frame %d, %s", f + 1, name_str(&l.name)), desc})
			}
		}
	}
	clip_end()
	cell_at :: proc(grid: Rect, nframes: i32) -> (f, li: int, ok: bool) {
		fi := (ui.mx - grid.x + tl_scroll_x) / TL_FRAME_W
		ri := (ui.my - grid.y + tl_scroll_y) / TL_ROW_H
		li = len(doc.layers) - 1 - int(ri)
		return int(fi), li, fi < nframes && li >= 0
	}
	gid := make_id(grid, "cells")
	if ui_hover(grid) && ui.pressed[0] do ui.active_id = gid
	if ui.active_id == gid && ui.down[0] {
		f, li, ok := cell_at(grid, nframes)
		stop_playback()
		if ok do set_frame(f)
		if ui.pressed[0] && ok {
			if d.active_layer != li do tools_commit_pending()
			d.active_layer = li
			d.edit_mask = false
			if ui.dbl_click do dialog_open(.Frame_Props)
		}
	}
	if ui_hover(grid) && ui.released[1] && !popup.open {
		if f, li, ok := cell_at(grid, nframes); ok {
			stop_playback()
			set_frame(f)
			if d.active_layer != li do tools_commit_pending()
			d.active_layer = li
			d.edit_mask = false
			frame_menu(make_id(grid, "framemenu"))
		}
	}
}

dlg_frame_props :: proc() {
	c := dialog_frame("Frame Properties", 250, 110)
	y := c.y
	row_int(c, y, "Duration (ms)", &dialog.a, 10, 60000, "How long this frame shows when the animation plays, in thousandths of a second.")
	y += 22
	checkbox(c.x, y, "Apply to all frames", &dialog.flag, {"Apply to all frames", "Give every frame this duration, not just the current one."})
	ok, cancel := dialog_buttons(c, "Use this duration (Enter). You can undo it.")
	if cancel do dialog_close()
	if ok {
		history_push(doc)
		if dialog.flag {
			for &f in doc.frames do f.duration = dialog.a
		} else {
			doc.frames[doc.active_frame].duration = dialog.a
		}
		dialog_close()
	}
}
