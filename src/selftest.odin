package pangolin

import "core:fmt"
import "core:math"
import "core:os"
import "core:strings"
import "core:time"

// Headless tests: `PangolinPaints --selftest`. Returns the number of failures.

@(private = "file")
fails: int

@(private = "file")
check :: proc(cond: bool, what: string, loc := #caller_location) {
	if !cond {
		fails += 1
		fmt.printf("FAIL %s (line %d)\n", what, loc.line)
	}
}

@(private = "file")
px :: proc(d: ^Doc, l, x, y: int) -> Color {
	return tiles_get(&d.layers[l].pix, x, y, {})
}

@(private = "file")
paint_line :: proc(t: Tool, col: Color, a, b: Vec2, steps := 40) {
	if !stroke_begin(t, a, col) do return
	for i in 1 ..= steps {
		stroke_move(a + (b - a) * (f32(i) / f32(steps)))
	}
	// let the stabiliser catch up
	for _ in 0 ..< 30 {
		stroke_move(b)
	}
	stroke_end()
}

@(private = "file")
fresh :: proc(w, h: int, fill: Color) -> ^Doc {
	d := doc_new_filled(w, h, "test", fill)
	append(&docs, d)
	doc = d
	return d
}

selftest :: proc() -> int {
	brush_init()
	fails = 0
	red := Color{220, 30, 30, 255}
	blue := Color{30, 60, 220, 255}
	white := Color{255, 255, 255, 255}

	// --- UI scale -----------------------------------------------------------
	{
		check(ui_scale_auto(1366, 768) == 100, "auto scale on a small laptop")
		check(ui_scale_auto(1920, 1080) == 150, "a 1080p display gets 150%")
		check(ui_scale_auto(2560, 1440) == 200 && ui_scale_auto(3840, 2160) == 300, "larger displays get more")
		check(ui_scale_auto(15360, 8640) == UI_SCALE_MAX, "auto stops at the end of the slider")
		check(ui_scale_auto(1080, 1920) == 100, "auto scale on a portrait monitor goes by its width")
		check(ui_scale_auto(1920, 1080, 2) == 200, "the system's display scale is a lower limit")
		ui_scale_arg, ui_scale_pref = 350, 125
		check(ui_scale_wanted() == 350, "--scale beats the saved scale")
		ui_scale_arg = 0
		check(ui_scale_wanted() == 125, "a chosen scale beats auto, whatever the window")
		ui_scale_pref = 0
		check(ui_scale_parse(0) == 0, "stored auto")
		check(ui_scale_parse(2) == 200, "stored multiple from older versions")
		check(ui_scale_parse(125) == 125, "stored percent")
		check(ui_scale_parse(9000) == UI_SCALE_MAX, "stored scale clamped")
	}

	// --- commands and shortcuts ------------------------------------------------------
	{
		has :: proc(c: Cmd, key: KeyboardKey, ctrl, shift: bool) -> bool {
			for s in SHORTCUTS do if s.cmd == c && s.key == key && s.ctrl == ctrl && s.shift == shift && !s.alt do return true
			return false
		}
		check(has(.Tool_Line, .L, false, false), "L picks the line tool")
		check(has(.Tool_Lasso, .Q, false, false), "Q picks the lasso")
		check(has(.Tool_Text, .T, false, false), "T picks the text tool")
		check(has(.Tool_Transform, .T, false, true) && has(.Tool_Transform, .T, true, false), "Shift+T and Ctrl+T pick free transform")
		for a, i in SHORTCUTS {
			for b in SHORTCUTS[i + 1:] {
				check(a.key != b.key || a.ctrl != b.ctrl || a.shift != b.shift || a.alt != b.alt, fmt.tprintf("%s is bound to one command", shortcut_text_for(a)))
			}
		}
		// every command says what it does, except for the ones that are not commands
		for c in Cmd.None ..= Cmd.Tool_Seamless {
			if c == .None do continue
			check(cmd_help(c) != "", fmt.tprintf("%v has tooltip text", c))
		}
		for fx in Fx {
			def := &FX_DEFS[fx]
			check(def.help != "", fmt.tprintf("%s says what it does", def.name))
			for p in def.params do check(p.help != "", fmt.tprintf("%s: %s has tooltip text", def.name, p.name))
			if def.flag != "" do check(def.flag_help != "", fmt.tprintf("%s: its checkbox has tooltip text", def.name))
			if def.choice != nil do check(def.choice_help != "", fmt.tprintf("%s: its combo has tooltip text", def.name))
		}
		for t in Tool {
			check(TOOL_HELP[t] != "", fmt.tprintf("%v has tooltip text", t))
			check(tool_is_toggle(t) || TOOL_HINT[t] != "", fmt.tprintf("%v has a status bar hint", t))
			check(fmt.tprintf("%v", Cmd(int(Cmd.Tool_Brush) + int(t))) == fmt.tprintf("Tool_%v", t), fmt.tprintf("the command for %v picks it", t))
		}
		tool_groups_default()
		WANT := [?]string{"Paint", "Draw", "Select", "Transform", "View"}
		check(len(tool_groups) == len(WANT), "five default tool groups")
		for &g, i in tool_groups do check(group_title(&g) == WANT[i], fmt.tprintf("default group %d is %s", i, WANT[i]))
	}

	// --- frames ---------------------------------------------------------------------------
	{
		same_look :: proc(a, b: []Color) -> bool {
			if len(a) != len(b) do return false
			for p, i in a {
				q := b[i]
				if p.a == 0 && q.a == 0 do continue // the color of a fully clear pixel shows nowhere
				if abs(int(p.r) - int(q.r)) > 1 || abs(int(p.g) - int(q.g)) > 1 || abs(int(p.b) - int(q.b)) > 1 || abs(int(p.a) - int(q.a)) > 1 do return false
			}
			return true
		}
		frame_flat :: proc(d: ^Doc, f: int) -> []Color {
			out := make([]Color, d.w * d.h, context.temp_allocator)
			frame_composite(d, f, out)
			return out
		}
		b := &brushes[.Brush]
		b^ = brush_default(.Brush)
		b.size, b.hardness, b.opacity, b.flow = 12, 100, 100, 100

		d := fresh(200, 120, {})
		check(len(d.frames) == 1 && d.active_frame == 0, "a new painting has one frame")
		paint_line(.Brush, red, {20, 60}, {100, 60})
		doc_add_frame(d, false)
		check(len(d.frames) == 2 && d.active_frame == 1, "a new frame comes after the current one, and is shown")
		check(px(d, 0, 60, 60).a == 0, "a new frame's cels are empty")
		paint_line(.Brush, blue, {60, 20}, {60, 100})
		set_frame(0)
		check(px(d, 0, 60, 60) == red && px(d, 0, 60, 30).a == 0, "frame 1 keeps its own pixels")
		check(frame_flat(d, 1)[30 * d.w + 60] == blue, "a frame other than the current one can be composited")
		set_frame(1)
		check(px(d, 0, 60, 30) == blue && px(d, 0, 30, 60).a == 0, "frame 2 keeps its own pixels")

		// undo snapshots cover all frames, and bring back the frame they were taken on
		undo_n := len(d.undo)
		paint_line(.Brush, red, {150, 20}, {150, 100})
		set_frame(0)
		history_undo(d)
		check(d.active_frame == 1 && px(d, 0, 150, 60).a == 0 && px(d, 0, 60, 30) == blue, "undo goes back to the frame it changes")
		check(frame_flat(d, 0)[60 * d.w + 60] == red, "undo leaves the other frames alone")
		history_redo(d)
		set_frame(1)
		check(px(d, 0, 150, 60) == red, "redo brings the stroke back")
		_ = undo_n

		// a duplicate shares its tiles until it is painted on
		set_frame(0)
		src_tile := d.layers[0].pix.t[60 / TILE * d.layers[0].pix.tw + 60 / TILE]
		refs_before := src_tile.refs
		doc_add_frame(d, true)
		check(d.active_frame == 1 && len(d.frames) == 3, "a duplicate comes after the current frame")
		dup_tile := d.layers[0].pix.t[60 / TILE * d.layers[0].pix.tw + 60 / TILE]
		check(dup_tile == src_tile && src_tile.refs > refs_before, "a duplicate frame shares its tiles")
		paint_line(.Brush, blue, {30, 60}, {90, 60})
		check(px(d, 0, 60, 60) == blue && frame_flat(d, 0)[60 * d.w + 60] == red, "painting on a duplicate leaves its source alone")
		check(frame_flat(d, 2)[30 * d.w + 60] == blue, "the frame after the duplicate moved along")

		// move and delete, with a tag following the frames
		name: Tag
		name.from, name.to = 1, 2
		append(&d.tags, name)
		doc_move_frame(d, 1)
		check(d.active_frame == 2 && px(d, 0, 60, 60) == blue && frame_flat(d, 1)[30 * d.w + 60] == blue, "moving a frame moves its cels")
		doc_delete_frame(d)
		check(len(d.frames) == 2 && d.active_frame == 1 && d.tags[0].to == 1, "deleting a frame fixes the tags")
		history_undo(d)
		check(len(d.frames) == 3 && d.active_frame == 2 && d.tags[0].to == 2 && px(d, 0, 60, 60) == blue, "undo brings a deleted frame back")
		for len(d.frames) > 1 do doc_delete_frame(d)
		check(!doc_delete_frame(d), "the last frame can't be deleted")
		clear(&d.tags)

		// everything that works on whole layers works on every frame
		d = fresh(200, 120, {})
		paint_line(.Brush, red, {20, 60}, {100, 60})
		doc_add_layer(d)
		paint_line(.Brush, blue, {20, 30}, {100, 30})
		doc_add_frame(d, false)
		paint_line(.Brush, blue, {20, 90}, {100, 90})
		d.active_layer = 0
		paint_line(.Brush, red, {20, 40}, {100, 40})
		f0, f1 := frame_flat(d, 0), frame_flat(d, 1)
		d.active_layer = 1
		doc_merge_down(d)
		check(len(d.layers) == 1 && same_look(frame_flat(d, 0), f0) && same_look(frame_flat(d, 1), f1), "merge down merges on every frame")
		history_undo(d)
		check(len(d.layers) == 2 && same_look(frame_flat(d, 0), f0), "undo brings the merged layer back on every frame")
		doc_flatten(d)
		check(len(d.layers) == 1 && same_look(frame_flat(d, 0), f0) && same_look(frame_flat(d, 1), f1), "flatten keeps every frame's look")
		history_undo(d)
		doc_flip(d, true)
		check(frame_flat(d, 0)[60 * d.w + (d.w - 1 - 60)] == red, "a flip reaches the other frames")
		history_undo(d)
		doc_canvas_size(d, 300, 200, 50, 40)
		check(d.w == 300 && frame_flat(d, 0)[100 * d.w + 110] == red, "a canvas size change reaches the other frames")
		check(frame_flat(d, 1)[130 * d.w + 110] == blue, "and the current one")
		history_undo(d)
		check(d.w == 200 && same_look(frame_flat(d, 0), f0) && same_look(frame_flat(d, 1), f1), "undo restores every frame's size")
		if bx, ok := doc_content_bounds(d); ok {
			check(bx.y0 < 30 - 3, "trim looks at every frame")
		}
		d.active_layer = 0
		set_frame(1)
		doc_add_mask(d, false)
		tiles_fill(&d.layers[0].mask, Color{0, 0, 0, 255}, MASK_EMPTY)
		doc_touch_all(d)
		check(frame_flat(d, 0)[60 * d.w + 60] == red, "a mask painted on one frame leaves the others")
		doc_delete_mask(d, true)
		check(!d.layers[0].has_mask && frame_flat(d, 0)[60 * d.w + 60] == red, "applying a mask keeps the other frames' pixels")

		// a text layer spans the frames until it is painted on
		d = fresh(200, 120, white)
		tl := layer_make("Words", d.w, d.h)
		tiles_fill(&tl.pix, Color{0, 200, 0, 255}, {})
		tl.opacity = 128
		tl.text.on = true
		append(&d.layers, tl)
		d.active_layer = 0
		doc_add_frame(d, false)
		check(frame_flat(d, 1)[10] != white, "a text layer shows on a new frame")
		d.active_layer = 1
		can_edit()
		check(!d.layers[1].text.on && tiles_count(&d.layers[1].pix) > 0, "painting on a text layer makes it pixels")
		check(frame_flat(d, 0)[10] != white && frame_flat(d, 1)[10].g == 200, "both frames keep showing it")
		set_frame(0)
		check(tiles_count(&d.layers[1].pix) > 0, "as their own copies")

		// new frame from visible: the same look from one plain image, whatever the layers do
		d = fresh(200, 120, Color{200, 180, 150, 255})
		paint_line(.Brush, red, {20, 60}, {180, 60})
		doc_add_layer(d)
		paint_line(.Brush, blue, {60, 20}, {60, 100})
		d.layers[1].blend = .Multiply
		d.layers[1].opacity = 180
		d.active_layer = 1
		doc_add_mask(d, false)
		for x in 0 ..< 200 do tiles_set(&d.layers[1].mask, x, 50, Color{90, 90, 90, 255}, MASK_EMPTY)
		d.edit_mask = false
		tv := layer_make("Words", d.w, d.h)
		for x in 10 ..< 150 do tiles_set(&tv.pix, x, 80, Color{0, 200, 0, 200}, {})
		tv.text.on = true
		tv.blend = .Screen
		append(&d.layers, tv)
		hidden := layer_make("Hidden", d.w, d.h)
		tiles_fill(&hidden.pix, Color{9, 9, 9, 255}, {})
		hidden.visible = false
		append(&d.layers, hidden)
		d.active_layer = 3
		source := frame_flat(d, 0)
		undo_before := len(d.undo)
		doc_frame_from_visible(d)
		check(len(d.frames) == 2 && d.active_frame == 1, "from visible adds a frame after the current one")
		check(same_look(frame_flat(d, 1), source), "from visible looks just like its source")
		check(same_look(doc_flat(d, context.temp_allocator), source), "and so does the composite of the current frame")
		check(d.frames[1].flat > 0 && d.frames[0].flat == 0, "only the new frame is flat")
		tgt := &d.layers[d.active_layer]
		check(tgt.blend == .Normal && tgt.opacity == 255 && tgt.visible && !layer_spans(tgt), "its image is on a plain layer")
		painted := 0
		for &l in d.layers {
			if !layer_spans(&l) && tiles_count(&l.pix) > 0 do painted += 1
		}
		check(painted == 1, "every other layer's cel is empty on that frame")
		check(same_look(frame_flat(d, 0), source), "the source frame is unchanged")
		history_undo(d)
		check(len(d.frames) == 1 && len(d.undo) == undo_before && same_look(frame_flat(d, 0), source), "from visible can be undone")
		history_redo(d)
		check(len(d.frames) == 2 && same_look(frame_flat(d, 1), source), "and redone")
		// text typed on that frame afterwards is the frame's own: it shows
		typed := layer_make("Typed", d.w, d.h)
		tiles_fill(&typed.pix, Color{9, 200, 9, 255}, {})
		typed.text.on = true
		typed.span_id = span_next_id(d)
		append(&d.layers, typed)
		doc_touch_all(d)
		check(frame_flat(d, 1)[10].g == 200, "a text layer made on a flat frame shows on it")
		layer_destroy(&d.layers[len(d.layers) - 1])
		pop(&d.layers)
		doc_touch_all(d)
		// no plain layer to use: it makes one
		for &l in d.layers do l.blend = .Multiply
		set_frame(0)
		pre := frame_flat(d, 0)
		n_layers := len(d.layers)
		doc_frame_from_visible(d)
		check(len(d.layers) == n_layers + 1 && same_look(frame_flat(d, d.active_frame), pre), "with no plain layer, it adds one")
		for &l in d.layers do l.blend = .Normal
		history_undo(d)
		for &l in d.layers do l.blend = .Normal
		doc_touch_all(d)

		// .ppnt version 5: everything comes back, and shared tiles stay shared
		set_frame(1)
		d.frames[1].duration = 250
		tg: Tag
		name_set(&tg.name, "Walk")
		tg.from, tg.to, tg.dir, tg.color = 0, 1, .Ping_Pong, Color{1, 2, 3, 255}
		append(&d.tags, tg)
		doc_add_frame(d, true)
		saved := [3][]Color{frame_flat(d, 0), frame_flat(d, 1), frame_flat(d, 2)}
		data := project_encode(d)
		nd, ok := project_decode(data)
		check(ok, "a project with frames loads")
		if ok {
			check(len(nd.frames) == 3 && nd.active_frame == d.active_frame && nd.frames[1].duration == 250, "frames round trip")
			check(nd.frames[1].flat > 0 && nd.frames[2].flat > 0 && nd.frames[0].flat == 0, "the flat flag round trips")
			check(len(nd.tags) == 1 && name_str(&nd.tags[0].name) == "Walk" && nd.tags[0].to == 1 && nd.tags[0].dir == .Ping_Pong, "tags round trip")
			for f in 0 ..< 3 do check(same_look(frame_flat(nd, f), saved[f]), fmt.tprintf("frame %d looks the same after loading", f + 1))
			lp := nd.layers[0].pix
			shared_tiles := false
			for t in lp.t do if t != nil && t.refs > 1 do shared_tiles = true
			// the duplicate is the current frame; its cel on frame 2 holds the same tiles
			for &l in nd.layers {
				for t in l.pix.t do if t != nil && t.refs > 1 do shared_tiles = true
			}
			check(shared_tiles, "tiles frames share stay shared after loading")
			doc_destroy(nd)
		}
		// older files: one frame
		old := Writer{}
		old.b = make([dynamic]u8, context.temp_allocator)
		append(&old.b, 'P', 'P', 'N', 'T')
		w8(&old, 4)
		w32(&old, 64)
		w32(&old, 64)
		w32(&old, 0)
		w32(&old, 1)
		wstr(&old, "Old")
		w8(&old, LF_VISIBLE)
		w8(&old, 255)
		w8(&old, 0)
		w32(&old, 0)
		od, ook := project_decode(old.b[:])
		check(ook && len(od.frames) == 1 && od.active_frame == 0 && len(od.tags) == 0, "a version 4 project loads as one frame")
		if ook do doc_destroy(od)

		// GIF export honors the playback range
		d = fresh(32, 32, red)
		doc_add_frame(d, false)
		paint_line(.Brush, blue, {0, 16}, {31, 16})
		doc_add_frame(d, true)
		gif_all := export_gif_bytes(d, 100)
		check(len(gif_all) > 6 && string(gif_all[:6]) == "GIF89a", "a GIF comes out")
		gp, gw, gh, gok := decode_image(gif_all, ".gif")
		check(gok && gw == 32 && gh == 32, "and reads back")
		if gok do delete(gp)
		tg2: Tag
		tg2.from, tg2.to = 1, 1
		append(&d.tags, tg2)
		play_tag = 0
		lo, hi, _ := play_range()
		check(lo == 1 && hi == 1, "a tag limits the playback range")
		one := export_gif_bytes(d, 100)
		check(len(one) < len(gif_all), "and what a GIF holds")
		check(export_png_sequence(d, "selftest_seq.png", 100) == 1, "and a PNG sequence")
		sp, sw, sh, sok := load_image_pixels("selftest_seq_001.png")
		check(sok && sw == 32 && sh == 32, "whose files read back")
		if sok do delete(sp)
		os.remove("selftest_seq_001.png")
		play_tag = -1
	}

	// --- file browser ---------------------------------------------------------------------
	{
		for name in ([?]string{"a.png", "b.JPG", "c.jpeg", "d.webp", "e.bmp", "f.tga", "g.gif", "h.qoi", "i.tif", "j.tiff", "k.psd", "l.psb", "m.kra", "n.ppnt"}) {
			check(files_listed(name), fmt.tprintf("the file browser lists %s", name))
		}
		check(!files_listed("o.txt") && !files_listed("p.gpl"), "and not other files")
		// webp reaches the shared decoder: a small lossless image
		WEBP := [?]u8{'R', 'I', 'F', 'F', 0x1a, 0, 0, 0, 'W', 'E', 'B', 'P', 'V', 'P', '8', 'L', 0x0d, 0, 0, 0, 0x2f, 0, 0, 0, 0x10, 0x07, 0x10, 0x11, 0x11, 0x88, 0x88, 0xfe, 0x07, 0}
		wp, ww, wh, wok := decode_image(WEBP[:], ".webp")
		check(wok && ww == 1 && wh == 1, "WebP files open")
		if wok do delete(wp)
		// a project's preview, made the way the thumbnail thread makes it
		d := fresh(32, 32, red)
		doc_add_frame(d, false)
		preview_path := "selftest_preview.ppnt"
		if write_file(preview_path, project_encode(d)) {
			pv, pw, ph, pok := files_preview(preview_path)
			check(pok && pw == 32 && ph == 32, "a project has a preview")
			if pok do delete(pv)
			os.remove(preview_path)
		}
		// a drop lands at the point, at the image's own size
		ix, iy := image_place(10, 10, IVec{16, 16})
		check(ix == 11 && iy == 11, "a dropped image is centered on the pointer")
		ix, iy = image_place(10, 10, IVec{-500, 500})
		check(ix == -9 && iy == 31, "and always keeps a pixel on the canvas")
	}

	// --- tiles --------------------------------------------------------------
	{
		g := tiles_make(150, 70)
		buf := make([]Color, 150 * 70, context.temp_allocator)
		for &p, i in buf do p = Color{u8(i), u8(i >> 8), 7, 255}
		tiles_from_buf(&g, 150, 70, buf, {})
		out := make([]Color, 150 * 70, context.temp_allocator)
		tiles_to_buf(&g, 150, 70, out, {})
		same := true
		for p, i in out do if p != buf[i] do same = false
		check(same, "tiles round trip")
		sh := tiles_share(&g)
		tiles_set(&g, 5, 5, red, {})
		check(tiles_get(&sh, 5, 5, {}) == buf[5 * 150 + 5], "copy-on-write keeps the snapshot")
		check(tiles_get(&g, 5, 5, {}) == red, "copy-on-write writes the copy")
		check(g.t[0] != sh.t[0] && g.t[1] == sh.t[1], "only the touched tile is cloned")
		tiles_destroy(&sh)
		clr := make([]Color, 150 * 70, context.temp_allocator)
		tiles_from_buf(&g, 150, 70, clr, {})
		check(tiles_count(&g) == 0, "empty tiles are released")
		tiles_destroy(&g)
	}

	// --- brush, undo/redo -------------------------------------------------------
	{
		d := fresh(200, 120, white)
		b := &brushes[.Brush]
		b^ = brush_default(.Brush)
		b.size, b.hardness, b.opacity, b.flow = 12, 100, 100, 100
		paint_line(.Brush, red, {20, 60}, {180, 60})
		check(px(d, 0, 100, 60) == red, "hard brush paints solid color")
		check(px(d, 0, 100, 20) == white, "brush leaves other pixels alone")
		check(len(d.undo) == 1, "one undo step per stroke")
		history_undo(d)
		check(px(d, 0, 100, 60) == white, "undo restores the stroke area")
		history_redo(d)
		check(px(d, 0, 100, 60) == red, "redo repaints")

		// opacity caps a stroke, even where dabs overlap
		b.opacity = 50
		paint_line(.Brush, blue, {20, 30}, {180, 30})
		c := px(d, 0, 100, 30)
		check(abs(int(c.r) - 142) <= 3 && abs(int(c.g) - 157) <= 3, fmt.tprintf("50%% opacity stroke mixes halfway (got %v)", c))
		b.opacity = 100

		// soft brush: centre stronger than the edge
		b.hardness = 0
		b.size = 30
		paint_line(.Brush, blue, {100, 95}, {101, 95}, 2)
		cc, ce := px(d, 0, 100, 95), px(d, 0, 100, 108)
		check(cc.r < ce.r && cc.r < 120 && ce.r > 150, fmt.tprintf("soft brush falls off (%v / %v)", cc, ce))

		// selection limits painting
		b.hardness = 100
		b.size = 40
		doc_sel_set(d, sel_rect(d.w, d.h, {0, 0}, {100, 120}))
		paint_line(.Brush, blue, {60, 10}, {140, 10})
		check(px(d, 0, 80, 10) == blue && px(d, 0, 120, 10) == white, "selection masks the brush")
		doc_sel_clear(d)

		// eraser
		layer := 0
		paint_line(.Eraser, white, {20, 60}, {180, 60})
		check(px(d, layer, 100, 60).a == 0, "eraser clears alpha")

		// lock transparency: painting keeps alpha
		d.layers[0].lock_alpha = true
		paint_line(.Brush, blue, {20, 60}, {180, 60})
		check(px(d, 0, 100, 60).a == 0, "lock transparency protects clear pixels")
		d.layers[0].lock_alpha = false
	}

	// --- oil and smudge ------------------------------------------------------------
	{
		d := fresh(200, 100, white)
		// left half red, right half blue
		for y in 0 ..< 100 {
			for x in 0 ..< 200 {
				tiles_set(&d.layers[0].pix, x, y, x < 100 ? red : blue, {})
			}
		}
		s := &brushes[.Smudge]
		s^ = brush_default(.Smudge)
		s.size, s.strength = 30, 90
		paint_line(.Smudge, white, {60, 50}, {150, 50})
		c := px(d, 0, 120, 50)
		check(c.r > 60 && c.b < 210, fmt.tprintf("smudge drags red into blue (got %v)", c))

		o := &brushes[.Oil]
		o^ = brush_default(.Oil)
		o.size, o.load, o.wet, o.bristles, o.tip = 30, 100, 0, 0, .Round
		paint_line(.Oil, Color{240, 220, 40, 255}, {20, 20}, {180, 20})
		y := px(d, 0, 100, 20)
		check(y.r > 200 && y.g > 180, fmt.tprintf("dry loaded oil covers (got %v)", y))
		o.wet, o.load = 90, 10
		paint_line(.Oil, Color{240, 220, 40, 255}, {20, 80}, {180, 80})
		m := px(d, 0, 170, 80)
		check(m.b > 60, fmt.tprintf("wet oil picks up canvas color (got %v)", m))
	}

	// --- layers, blend modes, masks -------------------------------------------------
	{
		d := fresh(64, 64, Color{100, 100, 100, 255})
		doc_add_layer(d)
		tiles_fill(&d.layers[1].pix, Color{200, 200, 200, 255}, {})
		d.layers[1].blend = .Multiply
		doc_dirty_all(d)
		doc_refresh_comp(d)
		check(abs(int(d.comp[0].r) - 78) <= 1, fmt.tprintf("multiply blend (got %v)", d.comp[0]))
		d.layers[1].blend = .Normal
		doc_add_mask(d, false)
		check(d.edit_mask, "new mask is selected for editing")
		b := &brushes[.Brush]
		b.size, b.hardness, b.opacity, b.flow = 20, 100, 100, 100
		paint_line(.Brush, Color{0, 0, 0, 255}, {0, 10}, {63, 10})
		doc_dirty_all(d)
		doc_refresh_comp(d)
		check(d.comp[10 * 64 + 30].r == 100, "black on the mask hides the layer")
		check(d.comp[50 * 64 + 30].r == 200, "white mask shows the layer")
		check(px(d, 1, 30, 10).r == 200, "mask painting leaves pixels untouched")
		doc_merge_down(d)
		check(len(d.layers) == 1 && px(d, 0, 30, 10).r == 100 && px(d, 0, 30, 50).r == 200, "merge down applies the mask")
	}

	// --- transforms -------------------------------------------------------------
	{
		d := fresh(100, 50, white)
		tiles_set(&d.layers[0].pix, 0, 0, red, {})
		doc_rotate(d, 1)
		check(d.w == 50 && d.h == 100 && px(d, 0, 49, 0) == red, "rotate 90 CW")
		doc_image_size(d, 25, 50, .Bicubic)
		check(d.w == 25 && d.h == 50, "image size")
		doc_canvas_size(d, 40, 60, 5, 5)
		check(d.w == 40 && d.h == 60 && px(d, 0, 0, 0).a == 0 && px(d, 0, 10, 10) == white, "canvas size adds transparent margin")
		doc_crop(d, Box{5, 5, 30, 55})
		check(d.w == 25 && d.h == 50, "crop")
		doc_rotate_any(d, 45)
		check(d.w > 40 && d.h > 40, "free rotate enlarges canvas")
		check(len(d.undo) == 5, "each transform is one undo step")
	}

	// --- adjustments through the live preview path -----------------------------------
	{
		d := fresh(64, 32, Color{100, 150, 200, 255})
		doc_sel_set(d, sel_rect(d.w, d.h, {0, 0}, {32, 32}))
		fx_open(.Invert)
		check(px(d, 0, 10, 10) == Color{155, 105, 55, 255}, "invert inside selection")
		check(px(d, 0, 50, 10) == Color{100, 150, 200, 255}, "invert leaves outside alone")
		history_undo(d)
		check(px(d, 0, 10, 10) == Color{100, 150, 200, 255}, "adjustment undo")
		doc_sel_clear(d)
		live_begin()
		fxs.fx = .Gaussian_Blur
		fxs.v[0] = 30
		fx_apply_now()
		live_cancel()
		check(px(d, 0, 10, 10) == Color{100, 150, 200, 255} && len(d.undo) == 0, "cancelled preview restores pixels")
	}

	// --- project file round trip --------------------------------------------------
	{
		d := fresh(130, 70, Color{10, 20, 30, 255})
		doc_add_layer(d)
		tiles_set(&d.layers[1].pix, 129, 69, red, {})
		d.layers[1].opacity = 128
		d.layers[1].blend = .Screen
		doc_add_mask(d, false)
		tiles_set(&d.layers[1].mask, 3, 3, Color{50, 50, 50, 255}, MASK_EMPTY)
		data := project_encode(d)
		nd, ok := project_decode(data)
		check(ok, "project decodes")
		if ok {
			check(nd.w == 130 && nd.h == 70 && len(nd.layers) == 2, "project size and layers")
			check(tiles_get(&nd.layers[1].pix, 129, 69, {}) == red, "project pixels")
			check(tiles_get(&nd.layers[0].pix, 64, 64, {}) == Color{10, 20, 30, 255}, "project background")
			check(nd.layers[1].opacity == 128 && nd.layers[1].blend == .Screen, "project layer settings")
			check(nd.layers[1].has_mask && tiles_get(&nd.layers[1].mask, 3, 3, MASK_EMPTY).r == 50 && tiles_get(&nd.layers[1].mask, 60, 3, MASK_EMPTY).r == 255, "project mask")
			doc_destroy(nd)
		}
		_, bad := project_decode(data[:len(data) / 2])
		check(!bad, "truncated project is rejected")
	}

	// --- text layers ----------------------------------------------------------------
	{
		d := fresh(300, 120, Color{255, 255, 255, 255})
		doc = d
		l := layer_make("Text", 300, 120)
		l.text = Text_Info{on = true, size = 40, color = Color{200, 30, 30, 255}, line_pct = 100, x = 10, y = 10}
		name_set(&l.text.font, DEFAULT_FONT)
		msg := "Hello\nWorld"
		copy(l.text.buf[:], msg)
		l.text.n = len(msg)
		append(&d.layers, l)
		text_render_layer(d, 1)
		tl := &d.layers[1]
		check(!box_empty(tl.text.bx), "text renders a block")
		inked := 0
		for y in tl.text.bx.y0 ..< tl.text.bx.y1 {
			for x in tl.text.bx.x0 ..< tl.text.bx.x1 {
				if tiles_get(&tl.pix, x, y, {}).a > 0 do inked += 1
			}
		}
		check(inked > 200, fmt.tprintf("text paints pixels (%d)", inked))
		check(tl.text.bx.y1 - tl.text.bx.y0 > 70, "two lines are taller than one")
		cx, cy, _ := text_caret_xy(&tl.text, 6)
		check(cx == tl.text.x && cy > tl.text.y + 30, "caret on the second line")
		data := project_encode(d)
		nd, ok := project_decode(data)
		check(ok, "text project decodes")
		if ok {
			nt := &nd.layers[1].text
			check(nt.on && text_str(nt) == msg && nt.size == 40 && nt.color == Color{200, 30, 30, 255}, "text settings survive saving")
			check(tiles_get(&nd.layers[1].pix, tl.text.bx.x0 + 20, tl.text.bx.y0 + 25, {}) == tiles_get(&tl.pix, tl.text.bx.x0 + 20, tl.text.bx.y0 + 25, {}), "text pixels survive saving")
			doc_destroy(nd)
		}
		doc = nil
	}

	// --- image codecs -----------------------------------------------------------
	{
		w, h := 97, 61
		pix := make([]Color, w * h, context.temp_allocator)
		for y in 0 ..< h {
			for x in 0 ..< w {
				pix[y * w + x] = Color{u8(x * 255 / w), u8(y * 255 / h), 128, 255}
			}
		}
		jpg := export_encode(pix, w, h, .JPG, 95)
		back, bw, bh, ok := jpeg_decode(jpg)
		check(ok && bw == w && bh == h, "jpeg round trip size")
		if ok {
			err := 0
			for p, i in back {
				err += abs(int(p.r) - int(pix[i].r)) + abs(int(p.g) - int(pix[i].g)) + abs(int(p.b) - int(pix[i].b))
			}
			check(f32(err) / f32(w * h * 3) < 2.5, "jpeg quality")
			delete(back)
		}
		png := export_encode(pix, w, h, .PNG, 0)
		pb, pw, ph, pok := decode_image(png, ".png")
		check(pok && pw == w && ph == h && pb[500] == pix[500], "png round trip")
		if pok do delete(pb)
		for f in ([?]Export_Format{.BMP, .TGA, .QOI}) {
			check(len(export_encode(pix, w, h, f, 0)) > 0, fmt.tprintf("%v export", f))
		}		// alpha that varies, so the predictor and the alpha channel both get exercised
		tp := make([]Color, w * h, context.temp_allocator)
		for &c, i in tp do c = Color{pix[i].r, pix[i].g, pix[i].b, u8(i * 7)}
		tif := export_encode(tp, w, h, .TIFF, 0)
		tb, tw, th, tok := decode_image(tif, ".tif")
		same := tok && tw == w && th == h
		if same {
			for c, i in tb do if c != tp[i] {same = false; break}
		}
		check(same, "tiff round trip")
		if tok do delete(tb)
	}

	// --- erase blend mode ------------------------------------------------------------
	{
		d := fresh(64, 64, white)
		doc_add_layer(d)
		tiles_fill(&d.layers[1].pix, red, {})
		doc_add_layer(d)
		tiles_set(&d.layers[2].pix, 10, 10, blue, {})
		tiles_set(&d.layers[2].pix, 11, 10, Color{0, 0, 0, 128}, {})
		d.layers[2].blend = .Erase
		doc_dirty_all(d)
		doc_refresh_comp(d)
		check(d.comp[10 * 64 + 10].a == 0 && d.comp[10 * 64 + 20] == red, "erase layer cuts through the layers below")
		check(abs(int(d.comp[10 * 64 + 11].a) - 127) <= 1, "erase strength follows the eraser layer's alpha")
		doc_merge_down(d)
		check(px(d, 1, 10, 10).a == 0 && px(d, 1, 20, 10) == red, "merging an erase layer erases the layer below")
	}

	// --- grid snapping --------------------------------------------------------------
	{
		d := fresh(95, 60, white)
		show_grid, snap_grid, grid_w, grid_h = true, true, 10, 20
		check(snap_pt({13, 7}) == Vec2{10, 0} && snap_pt({16, 11}) == Vec2{20, 20}, "points snap to grid intersections")
		check(snap_pt({93.5, 59}) == Vec2{95, 60}, "canvas edges snap like grid lines")
		snap_grid = false
		check(snap_pt({13, 7}) == Vec2{13, 7}, "no snapping when snap is off")
		snap_grid, show_grid = true, false
		check(snap_pt({13, 7}) == Vec2{13, 7}, "no snapping while the grid is hidden")
		show_grid = true
		// a freehand stroke snapped point by point paints along the grid lines
		paint_line(.Brush, red, snap_pt({12, 31}), snap_pt({48, 38}))
		check(px(d, 0, 30, 40) == red && px(d, 0, 30, 25) == white, "snapped stroke follows the grid line")
		// rotated 45 degrees about the centre: snapped points sit on the rotated lattice
		grid_w, grid_h, grid_angle = 10, 10, 45
		q := snap_pt({60, 33})
		c, ca, sa := grid_frame(d)
		u := Vec2{(q - c).x * ca + (q - c).y * sa, -(q - c).x * sa + (q - c).y * ca} + c
		frac :: proc(v: f32) -> f32 {return abs(v / 10 - math.round(v / 10))}
		check(frac(u.x) < 0.01 && frac(u.y) < 0.01 && vlen(q - Vec2{60, 33}) < 8, "rotated grid snapping")
		show_grid, grid_w, grid_h, grid_angle = false, 64, 64, 0
	}

	// --- shift-stepped sliders ---------------------------------------------------------
	{
		check(slider_chunk(37, 0, 359, " deg", 1) == 35 && slider_chunk(-12, -90, 90, "deg", 1) == -10, "angles snap to 5 degrees")
		check(slider_chunk(37, 0, 359, " deg", 1, 1) == 40 && slider_chunk(35, 0, 359, " deg", 1, -1) == 30, "shift+wheel steps 5 degrees")
		check(slider_chunk(47, 1, 100, "%", 1) == 45 && slider_chunk(1, 1, 100, "%", 1, 1) == 5, "percentages step by 5")
		check(slider_chunk(130, 0, 255, "", 1) == 130 && slider_chunk(134, 0, 255, "", 1) == 130, "0..255 steps by 10")
		check(slider_chunk(37, 1, 1000, "px", 2.5) == 40 && slider_chunk(140, 1, 1000, "px", 2.5) == 150, "sizes stair-step")
		check(slider_chunk(40, 1, 1000, "px", 2.5, 1) == 50 && slider_chunk(40, 1, 1000, "px", 2.5, -1) == 30, "sizes step to the next stair")
		check(slider_chunk(7, 1, 16, "", 1) == 7, "short ranges keep single steps")
	}

	// --- switches share the options bar ---------------------------------------------------
	{
		fresh(32, 32, white)
		show_grid, mirror_on = false, false
		tool_toggle(.Grid)
		check(show_grid && options_switch_on && options_switch == .Grid, "clicking Grid turns it on and shows its settings")
		select_tool(.Brush)
		check(show_grid && !options_switch_on, "picking a tool brings its settings back")
		tool_toggle(.Grid)
		check(show_grid && options_switch_on, "clicking Grid while it is on shows its settings")
		tool_toggle(.Grid)
		check(!show_grid && !options_switch_on, "clicking Grid again turns it off")
		tool_toggle(.Mirror)
		tool_toggle(.Mirror)
		check(!mirror_on && !options_switch_on, "Mirror switches the same way")
		tool_toggle(.Seamless)
		check(seamless_mode && options_switch_on && options_switch == .Seamless, "Tiled Mode is a switch too")
		run_cmd(.Tool_Seamless)
		check(!seamless_mode && !options_switch_on, "its command turns it off again")

		// a group of switches: its hotkey cycles Grid -> Mirror -> off
		append(&tool_groups, Tool_Group{last = .Grid})
		gi := len(tool_groups) - 1
		append(&tool_groups[gi].tools, Tool.Grid, Tool.Mirror)
		tool_group_activate(gi)
		check(show_grid && !mirror_on && options_switch == .Grid, "switch group hotkey turns on its first switch")
		tool_group_activate(gi)
		check(!show_grid && mirror_on && options_switch_on && options_switch == .Mirror, "pressing again moves on to the next switch")
		tool_group_activate(gi)
		check(!show_grid && !mirror_on, "after the last switch, the group turns off")
		tool_group_activate(gi)
		select_tool(.Brush)
		tool_group_activate(gi)
		check(!show_grid && !mirror_on, "pressed while using a tool, the hotkey turns the switch off")
		tool_group_activate(gi)
		check(show_grid && options_switch_on, "and the next press turns it back on")
		delete(tool_groups[gi].tools)
		pop(&tool_groups)
		show_grid, mirror_on = false, false
		options_show_tool()
	}

	// --- mirror painting ---------------------------------------------------------------
	{
		d := fresh(200, 100, white)
		mirror_on, mirror_count, mirror_angle, mirror_cx, mirror_cy = true, 1, 90, 0.5, 0.5
		paint_line(.Brush, red, {20, 30}, {60, 30})
		check(px(d, 0, 40, 30) == red && px(d, 0, 159, 30) == red && px(d, 0, 100, 30) == white, "one mirror paints the reflection")
		check(len(d.undo) == 1, "a mirrored stroke is one undo step")
		history_undo(d)
		// four mirrors: 8 copies around the centre
		mirror_count, mirror_angle = 4, 0
		paint_line(.Brush, red, {130, 50}, {140, 50}, 4)
		check(px(d, 0, 65, 50) == red && px(d, 0, 100, 15) == red && px(d, 0, 100, 85) == red, "four mirrors paint around the centre")
		history_undo(d)
		// wet oil: each copy keeps its own paint
		mirror_count, mirror_angle = 1, 90
		paint_line(.Oil, blue, {20, 60}, {60, 60})
		c0, c1 := px(d, 0, 40, 60), px(d, 0, 159, 60)
		check(c0.b > 150 && c1.b > 150, fmt.tprintf("mirrored oil paints both sides (%v / %v)", c0, c1))
		history_undo(d)
		// a filled polygon is filled on both sides
		set_fg(red)
		line_outline, line_fill = false, true
		append(&line_tool.pts, Vec2{10, 10}, Vec2{40, 10}, Vec2{25, 40})
		line_finish(true)
		check(px(d, 0, 25, 20) == red && px(d, 0, 174, 20) == red, "mirrored polygon fill")
		line_outline, line_fill = true, false
		mirror_on, mirror_count, mirror_angle = false, 1, 90
	}

	// --- perspective guides --------------------------------------------------------------
	{
		d := fresh(200, 100, white)
		d.zoom = 1
		saved := persp_vp
		persp_on, persp_snap, persp_points = true, true, 2
		persp_vp[0], persp_vp[1] = {-0.5, 0.5}, {1.5, 0.5} // (-100, 50) and (300, 50)
		on_line :: proc(a, b, q: Vec2) -> bool {
			u, v := b - a, q - a
			return abs(u.x * v.y - u.y * v.x) / max(vlen(u), 0.001) < 0.01
		}
		from := Vec2{100, 80}
		q := persp_project(d, from, {150, 73})
		check(on_line(from, persp_point(d, 1), q) && q.x > 140, "a stroke heading for a point follows its guide")
		q = persp_project(d, from, {102, 40})
		check(abs(q.x - 100) < 0.01 && abs(q.y - 40) < 0.1, "2-point: upright strokes stay upright")
		lock := -1
		q = persp_project(d, from, from + {2, 0}, &lock)
		check(q == from && lock == -1, "a stroke waits a few pixels before picking its guide")
		persp_project(d, from, from + {-40, -2}, &lock)
		q = persp_project(d, from, from + {0, -50}, &lock)
		check(lock == 0 && on_line(from, persp_point(d, 0), q), "a stroke keeps to the guide it picked")
		persp_snap = false
		check(persp_project(d, from, {102, 40}) == Vec2{102, 40}, "no snapping when snap is off")
		persp_snap, persp_points = true, 1
		persp_vp[0] = {0.5, 0.4}
		q = persp_project(d, {150, 80}, {190, 81})
		check(abs(q.y - 80) < 0.01, "1-point: level strokes stay level")
		q = persp_project(d, {150, 80}, {128, 66})
		check(on_line({150, 80}, {100, 40}, q), "1-point: strokes towards the point follow it")
		persp_points = 2
		persp_layout(2, 0.3)
		check(abs(persp_horizon_y(d) - 0.3) < 0.001 && persp_vp[0].x < 0 && persp_vp[1].x > 1, "default 2-point layout keeps the horizon height")
		persp_on = false
		tool_toggle(.Perspective)
		check(persp_on && persp_editing(), "clicking Perspective turns it on and shows its settings")
		tool_toggle(.Perspective)
		check(!persp_on && !options_switch_on, "clicking it again turns it off")
		persp_vp, persp_points, persp_snap = saved, 2, true
	}

	// --- line / polygon tool ---------------------------------------------------------
	{
		d := fresh(100, 100, white)
		set_fg(red)
		line_outline, line_fill = true, false
		append(&line_tool.pts, Vec2{10, 10}, Vec2{90, 10}, Vec2{90, 90})
		line_finish(false)
		check(!line_active() && len(d.undo) == 1, "a finished polyline is one undo step")
		check(px(d, 0, 50, 10) == red && px(d, 0, 90, 50) == red && px(d, 0, 50, 50) == white, "polyline paints straight segments")
		history_undo(d)
		line_fill = true
		append(&line_tool.pts, Vec2{20, 20}, Vec2{80, 20}, Vec2{80, 80}, Vec2{20, 80})
		line_finish(true)
		check(len(d.undo) == 1 && px(d, 0, 50, 50) == red && px(d, 0, 20, 50) == red && px(d, 0, 5, 50) == white, "closed polygon is filled and outlined in one step")
		history_undo(d)
		line_outline = false
		append(&line_tool.pts, Vec2{20, 20}, Vec2{80, 20}, Vec2{50, 80})
		line_finish(true)
		check(len(d.undo) == 1 && px(d, 0, 50, 40) == red && px(d, 0, 50, 19) == white, "fill without outline")
		line_outline, line_fill = true, false
	}

	// --- text character colors -------------------------------------------------------
	{
		d := fresh(400, 120, white)
		text_defaults_init()
		l := layer_make("Text", d.w, d.h)
		l.text = text_defaults
		l.text.on = true
		l.text.size = 40
		l.text.x, l.text.y = 10, 10
		text_color_all(&l.text, blue)
		append(&d.layers, l)
		d.active_layer = 1
		ti := &d.layers[1].text
		s := "MMMM MMMM"
		text_insert_bytes(ti, 0, transmute([]u8)s, 0)
		text_color_range(ti, 5, 9, red)
		check(ti.npal == 1 && text_char_color(ti, 0) == blue && text_char_color(ti, 6) == red, "color a range of text")
		text_render_layer(d, 1)
		count :: proc(d: ^Doc, x0, x1: int, c: Color) -> int {
			n := 0
			for y in 0 ..< d.h do for x in x0 ..< x1 {
				p := tiles_get(&d.layers[1].pix, x, y, {})
				if p.a == 255 && p.r == c.r && p.g == c.g && p.b == c.b do n += 1
			}
			return n
		}
		mx, _, _ := text_caret_xy(ti, 5) // where the red part starts
		mid := int(mx) - 1
		check(count(d, 0, mid, blue) > 100 && count(d, 0, mid, red) == 0 && count(d, mid, d.w, red) > 100 && count(d, mid, d.w, blue) == 0, "colored text renders in its colors")
		// inserting and deleting keeps each character's color
		text_insert_bytes(ti, 0, transmute([]u8)string("x"), 0)
		text_delete_range(ti, 0, 1)
		check(text_char_color(ti, 5) == red && text_char_color(ti, 4) == blue, "colors move with the text")
		text_delete_range(ti, 5, 9)
		check(ti.npal == 0, "unused text colors are dropped")
		text_color_range(ti, 0, 2, red)
		data := project_encode(d)
		nd, ok := project_decode(data)
		check(ok && nd.layers[1].text.npal == 1 && text_char_color(&nd.layers[1].text, 1) == red && text_char_color(&nd.layers[1].text, 3) == blue, "text colors are saved in projects")
		if ok do doc_destroy(nd)
	}

	// --- text to path ---------------------------------------------------------------
	{
		d := fresh(300, 120, white)
		text_defaults_init()
		mk :: proc(d: ^Doc, size: int, x, y: f32) -> int {
			l := layer_make("Text", d.w, d.h)
			l.text = text_defaults
			l.text.on = true
			l.text.size = size
			l.text.x, l.text.y = x, y
			text_color_all(&l.text, Color{30, 60, 220, 255})
			s := "Path"
			text_insert_bytes(&l.text, 0, transmute([]u8)s, 0)
			append(&d.layers, l)
			text_render_layer(d, len(d.layers) - 1)
			return len(d.layers) - 1
		}
		alpha_sum :: proc(d: ^Doc, li: int) -> (sum: int, partial: int) {
			for y in 0 ..< d.h do for x in 0 ..< d.w {
				a := int(tiles_get(&d.layers[li].pix, x, y, {}).a)
				sum += a
				if a > 0 && a < 255 do partial += 1
			}
			return
		}
		li := mk(d, 50, 20, 20)
		d.active_layer = li
		text_sum, _ := alpha_sum(d, li)
		check(doc_text_to_path(d) && d.layers[li].shape != nil && !d.layers[li].text.on, "text converts to a vector layer")
		path_sum, _ := alpha_sum(d, li)
		check(abs(path_sum - text_sum) * 100 < text_sum * 3, fmt.tprintf("the path looks like the text (%d vs %d)", path_sum, text_sum))
		// doubling the image redraws the outlines: ink scales by 4 and edges stay one pixel wide
		_, partial1 := alpha_sum(d, li)
		doc_image_size(d, 600, 240, .Bicubic)
		big_sum, partial2 := alpha_sum(d, li)
		check(d.layers[li].shape != nil && abs(big_sum - path_sum * 4) * 100 < path_sum * 4 * 3, "image size scales vector layers")
		check(partial2 < partial1 * 3, fmt.tprintf("scaled outlines stay sharp (%d edge pixels, was %d)", partial2, partial1))
		data := project_encode(d)
		nd, ok := project_decode(data)
		check(ok && nd.layers[li].shape != nil && len(nd.layers[li].shape.cmds) == len(d.layers[li].shape.cmds), "vector layers are saved in projects")
		if ok do doc_destroy(nd)
		history_undo(d)
		history_undo(d)
		check(d.w == 300 && d.layers[li].text.on && d.layers[li].shape == nil, "undo brings the text layer back")
		history_redo(d)
		// free transform at 2x scales the outlines, not the pixels
		before, _ := shape_bounds(d.layers[li].shape)
		check(xform_begin() && d.layers[li].shape != nil, "free transform keeps a vector layer")
		xform.sx, xform.sy = 2, 2
		xform_commit()
		after, _ := shape_bounds(d.layers[li].shape)
		check(d.layers[li].shape != nil && abs((after.x1 - after.x0) - 2 * (before.x1 - before.x0)) <= 4, "free transform scales vector outlines")
		history_undo(d)
		check(can_edit() && d.layers[li].shape == nil, "painting rasterises a vector layer")
	}

	// --- defaults ------------------------------------------------------------------
	{
		check(brush_default(.Brush).pressure == .Pen && brush_default(.Eraser).pressure == .Pen, "pen pressure is on by default")
		old := brush_to_ints(brush_default(.Brush))
		old[13] = int(Pressure.Off)
		check(brush_from_ints(brush_default(.Brush), old[:25]).pressure == .Pen, "old saved brushes get pen pressure")
		check(brush_from_ints(brush_default(.Brush), old[:]).pressure == .Off, "pressure turned off by the user stays off")
		d := doc_new_painting(40, 30, "two", white)
		check(len(d.layers) == 2 && d.active_layer == 1 && px(d, 1, 5, 5).a == 0 && px(d, 0, 5, 5) == white, "new painting has a clear layer over the background")
		doc_destroy(d)
	}

	// --- selections -----------------------------------------------------------------
	{
		d := fresh(80, 80, white)
		e := sel_ellipse(80, 80, {10, 10}, {70, 70})
		check(e[40 * 80 + 40] == 255 && e[0] == 0, "ellipse selection")
		edge := e[40 * 80 + 10]
		check(edge > 0 && edge < 255, "ellipse selection is anti-aliased")
		doc_sel_set(d, e)
		check(d.sel != nil && d.sel.bbox.x0 >= 9 && d.sel.bbox.x1 <= 71, "selection bounds")
		v := make([]u8, 80 * 80)
		copy(v, d.sel.v)
		mask_grow(v, 80, 80, 5)
		check(v[40 * 80 + 6] == 255, "grow selection")
		mask_grow(v, 80, 80, -10)
		check(v[40 * 80 + 12] == 0, "shrink selection")
		delete(v)
		poly := [?]Vec2{{10, 10}, {70, 10}, {40, 70}}
		pm := sel_polygon(80, 80, poly[:])
		check(pm[30 * 80 + 40] == 255 && pm[60 * 80 + 10] == 0, "lasso polygon")
		delete(pm)
	}

	// --- macros ---------------------------------------------------------------------
	{
		// every command is a node, is stood in for by a node with settings, or is left out on purpose
		for c in Cmd.None ..= Cmd.Tool_Seamless {
			if c == .None do continue
			_, covered := macro_cmd_id(c)
			for x in MACRO_CMD_NODES {
				if x.cmd != c do continue
				covered = true
				check(macro_def_find(x.id) != nil, fmt.tprintf("%s is a node", x.id))
			}
			for x in MACRO_CMD_EXCLUDED do if x == c do covered = true
			if c >= .Opacity_10 && c <= .Opacity_100 do covered = macro_def_find("brush.Opacity") != nil // one node with the opacity as its setting
			check(covered, fmt.tprintf("%v is a macro node, or left out on purpose", c))
		}
		ids := make(map[string]bool, context.temp_allocator)
		for &def in macro_catalogue() {
			check(!(def.id in ids), fmt.tprintf("one node is called %s", def.id))
			ids[def.id] = true
			check(def.name != "" && def.help != "" && def.category != "", fmt.tprintf("%s has a name, a category and tooltip text", def.id))
			for &st, i in def.settings {
				check(st.key != "" && st.name != "" && st.help != "", fmt.tprintf("%s: %s has a key, a name and tooltip text", def.id, st.name))
				for o in def.settings[i + 1:] do check(o.key != st.key, fmt.tprintf("%s: one setting is called %s", def.id, st.key))
				back, ok := macro_value_parse(&st, macro_value_text(&st, st.def))
				check(ok && back.num == st.def.num && back.col == st.def.col, fmt.tprintf("%s: the default of %s reads back", def.id, st.key))
			}
		}
		check(len(macro_def_find("fx.Gaussian_Blur").settings) == 1 && len(macro_def_find("fx.Levels").settings) == 6, "effect nodes take the settings of their windows")

		// setting values
		grow := macro_def_find("sel.Grow")
		v, ok := macro_value_parse(&grow.settings[0], "9999")
		check(ok && v.num == 500, "numbers are kept in range")
		v, ok = macro_value_parse(&grow.settings[0], "lots")
		check(!ok && v.num == 5, "text that is not a number gives the default")
		v, ok = macro_value_parse(&macro_def_find("file.Export").settings[0], "JPG")
		check(ok && Export_Format(int(v.num)) == .JPG, "choices are stored by name")
		v, ok = macro_value_parse(&macro_def_find("edit.Fill").settings[0], "#ff000080")
		check(ok && v.col == Color{255, 0, 0, 128}, "colors with alpha")

		// the file format
		m := macro_new("Round trip")
		a := macro_add_node(m, "sel.Grow", 200, 0)
		macro_set_arg(m, a, "px", "4")
		b := macro_add_node(m, "file.Export", 400, -50.5)
		macro_set_arg(m, b, "path", `{dir}/my "best" = pic.{ext}`)
		macro_link(m, macro_start(m), a.id)
		macro_link(m, a.id, b.id)
		t1 := strings.clone(macro_to_text(m), context.temp_allocator)
		m2, ok2 := macro_from_text(t1)
		check(ok2 && macro_to_text(m2) == t1, "a macro file reads back as it was written")
		pv, _ := macro_arg(macro_node(m2, b.id), "path")
		check(pv == `{dir}/my "best" = pic.{ext}`, "values with spaces, quotes and = survive the file")
		macro_free(m)
		macro_free(m2)
		_, bad_ok := macro_from_text("not a macro")
		check(!bad_ok, "other files are not read as macros")

		// running: one undo step
		d := fresh(40, 30, white)
		undo0 := len(d.undo)
		m = macro_new("Fill box")
		n1 := macro_add_node(m, "sel.Rect", 200, 0)
		for kv in ([?][2]string{{"x", "10"}, {"y", "5"}, {"w", "10"}, {"h", "10"}, {"units", "pixels"}}) do macro_set_arg(m, n1, kv[0], kv[1])
		n2 := macro_add_node(m, "edit.Fill", 400, 0)
		macro_set_arg(m, n2, "color", "#dc1e1e")
		n3 := macro_add_node(m, "cmd.Deselect", 600, 0)
		macro_link(m, macro_start(m), n1.id)
		macro_link(m, n1.id, n2.id)
		macro_link(m, n2.id, n3.id)
		rok, rmsg, _ := macro_run(m)
		check(rok, fmt.tprintf("a macro runs (%s)", rmsg))
		check(px(d, 0, 12, 7) == red && px(d, 0, 2, 2) == white && d.sel == nil, "the macro selected a box, filled it and deselected")
		check(len(d.undo) == undo0 + 1 && d.history_hold == 0, "a macro is one undo step")
		history_undo(d)
		check(px(d, 0, 12, 7) == white, "one undo takes the whole macro back")
		history_redo(d)
		check(px(d, 0, 12, 7) == red, "redo brings it back")

		// a failing step puts everything back and says where it stopped
		undo1 := len(d.undo)
		bad := macro_new("Fails")
		f1 := macro_add_node(bad, "edit.Fill", 200, 0)
		macro_set_arg(bad, f1, "color", "#1e3cdc")
		f2 := macro_add_node(bad, "sel.Grow", 400, 0)
		macro_link(bad, macro_start(bad), f1.id)
		macro_link(bad, f1.id, f2.id)
		fok, fmsg, fat := macro_run(bad)
		check(!fok && fat == f2.id && strings.contains(fmsg, "no selection"), "a failing step stops the macro and names the step")
		check(px(d, 0, 2, 2) == white && len(d.undo) == undo1 && d.history_hold == 0, "a failed macro leaves the painting as it was")

		// macros that can't run don't touch the painting
		unk := macro_new("Unknown")
		u := macro_add_node(unk, "cmd.Nonsense", 200, 0)
		macro_link(unk, macro_start(unk), u.id)
		uok, umsg, _ := macro_run(unk)
		check(!uok && strings.contains(umsg, "cmd.Nonsense") && len(d.undo) == undo1, "a node this version doesn't know stops the macro before it starts")
		loop := macro_new("Loop")
		l1 := macro_add_node(loop, "cmd.Select_All", 200, 0)
		l2 := macro_add_node(loop, "cmd.Deselect", 400, 0)
		macro_link(loop, macro_start(loop), l1.id)
		macro_link(loop, l1.id, l2.id)
		macro_link(loop, l2.id, l1.id)
		lchain, lok, _ := macro_chain(loop)
		check(lok && len(lchain) == 0 && macro_prev(loop, l1.id) == l2.id, "a node takes one Document wire in: wiring into it replaces the old one, so the wire can't loop")

		// value wires: value nodes feed settings, and are worked out once per run
		vm := macro_new("Values")
		vn := macro_add_node(vm, "value.Number", 0, 100)
		macro_set_arg(vm, vn, "value", "3")
		vmath := macro_add_node(vm, "value.Math", 0, 200)
		macro_set_arg(vm, vmath, "op", "multiply")
		macro_set_arg(vm, vmath, "b", "4")
		macro_wire(vm, vn.id, vmath.id, "a")
		grow2 := macro_add_node(vm, "sel.Grow", 200, 0)
		macro_wire(vm, vmath.id, grow2.id, "px")
		rnd := macro_add_node(vm, "value.Random", 0, 300)
		macro_set_arg(vm, rnd, "min", "5")
		macro_set_arg(vm, rnd, "max", "7")
		run := macro_run_state(vm)
		gv, gok, _ := macro_node_values(&run, macro_node(vm, grow2.id), macro_def_find("sel.Grow"))
		check(gok && gv[0].num == 12, "a setting takes the value wired into it (3 x 4)")
		r1, _, _ := macro_eval(&run, rnd.id)
		r2, _, _ := macro_eval(&run, rnd.id)
		check(r1.num == r2.num && r1.num >= 5 && r1.num <= 7 && r1.num == math.floor(r1.num), "a value node gives one result per run, in its range")
		macro_wire(vm, vmath.id, vn.id, "value")
		macro_wire(vm, vn.id, vmath.id, "a")
		run2 := macro_run_state(vm)
		_, cok, cmsg := macro_eval(&run2, vmath.id)
		check(!cok && strings.contains(cmsg, "loop"), "values wired round in a loop are refused")
		macro_unwire(vm, vn.id, "value")
		wt := strings.clone(macro_to_text(vm), context.temp_allocator)
		vm2, _ := macro_from_text(wt)
		check(len(vm2.wires) == 2 && macro_wire_from(vm2, grow2.id, "px") == vmath.id, "value wires are saved in the file")
		check(macro_can_feed(.Number, .Choice) && macro_can_feed(.Number, .Bool) && !macro_can_feed(.Color, .Number) && !macro_can_feed(.Text, .Number), "which values can feed which settings")
		iv := macro_new("Info")
		info := macro_add_node(iv, "value.Info", 0, 100)
		macro_set_arg(iv, info, "what", "height")
		run3 := macro_run_state(iv)
		ih, _, _ := macro_eval(&run3, info.id)
		check(ih.num == f64(doc.h), "Document Info reads the open painting")
		vchain, _, vcmsg := macro_chain(vm)
		check(len(vchain) == 0 && vcmsg == "", "value nodes are not steps")
		macro_link(vm, macro_start(vm), vn.id)
		_, vbad, vbmsg := macro_chain(vm)
		check(!vbad && strings.contains(vbmsg, "Document wire"), "a value node on the Document wire is refused")
		for x in ([?]^Macro{vm, vm2, iv}) do macro_free(x)

		// effects take their settings from the node
		inv := macro_new("Invert")
		i1 := macro_add_node(inv, "fx.Invert", 200, 0)
		macro_link(inv, macro_start(inv), i1.id)
		before := px(d, 0, 2, 2)
		iok, _, _ := macro_run(inv)
		after := px(d, 0, 2, 2)
		check(iok && after.r == 255 - before.r && after.b == 255 - before.b, "an effect node applies its effect")

		// recording keeps the commands used, not view changes or a running macro's own steps
		macro_record_start()
		run_cmd(.Select_All)
		run_cmd(.Toggle_Onion)
		run_cmd(.Toggle_Onion)
		macro_run(inv)
		rec := macro_record_stop()
		rchain, rcok, _ := macro_chain(rec)
		check(rec != nil && rcok && len(rchain) == 1 && rchain[0].kind == "cmd.Select_All", "recording keeps only the commands that are steps")
		macro_free(rec)
		macro_record_start()
		check(macro_record_stop() == nil, "a recording with no steps makes no macro")

		// macro groups: the hotkey runs the selected macro, then selects the next
		fg0 := fg
		ma := macro_new("Mark A")
		x := macro_add_node(ma, "color.Foreground", 200, 0)
		macro_set_arg(ma, x, "color", "#010203")
		macro_link(ma, macro_start(ma), x.id)
		mb := macro_new("Mark B")
		y := macro_add_node(mb, "color.Foreground", 200, 0)
		macro_set_arg(mb, y, "color", "#040506")
		macro_link(mb, macro_start(mb), y.id)
		append(&macro_lib, ma, mb)
		tool_groups_default()
		grp: Tool_Group
		for nm in ([2]string{"Mark A", "Mark B"}) {
			n: Name
			name_set(&n, nm)
			append(&grp.macros, n)
		}
		append(&tool_groups, grp)
		gi := len(tool_groups) - 1
		tool_group_activate(gi)
		check(fg == Color{1, 2, 3, 255} && tool_groups[gi].next_macro == 1, "a macro group's hotkey runs the selected macro and selects the next")
		tool_group_activate(gi)
		check(fg == Color{4, 5, 6, 255} && tool_groups[gi].next_macro == 0, "pressing it again runs the next macro, then starts over")
		tool_groups[gi].next_macro = 1
		saved := strings.clone(tool_groups_serialize(), context.temp_allocator)
		tool_groups_parse(saved)
		lg := &tool_groups[len(tool_groups) - 1]
		check(len(lg.macros) == 2 && name_str(&lg.macros[1]) == "Mark B" && lg.next_macro == 1, "macro groups are saved with the preferences")
		name_set(&lg.macros[1], "Missing")
		tool_group_activate(len(tool_groups) - 1)
		check(lg.next_macro == 1, "a macro that can't run stays selected")
		tool_groups_parse("49:0,1:::0:Paint:")
		check(len(tool_groups) == 1 && len(tool_groups[0].tools) == 2 && len(tool_groups[0].macros) == 0, "group preferences from before macros still load")
		tool_groups_default()
		set_fg(fg0)
		macros_clear()
		for mm in ([?]^Macro{m, bad, unk, loop, inv}) do macro_free(mm)

		// export paths
		d.path = strings.clone("C:/art/pic.ppnt")
		ep, epok, _ := macro_export_path(d, "{dir}/{name}_{frame}.{ext}", "png")
		check(epok && ep == "C:/art/pic_001.png", "export path templates")
		ep, epok, _ = macro_export_path(d, "out/{name}", "jpg")
		check(epok && ep == "C:/art/out/pic.jpg", "a relative export path goes next to the painting and gets its extension")
		check(export_path_template(d, "C:/art/pic.png") == "{dir}/{name}.png" && export_path_template(d, "D:/x/thing.png") == "D:/x/thing.png", "a recorded export works on other paintings")
		delete(d.path)
		d.path = ""
		_, epok, _ = macro_export_path(d, "{dir}/x.png", "png")
		check(!epok, "an unsaved painting has no {dir}")
		ep, epok, _ = macro_export_path(d, "C:/out/pic.png", "jpg")
		check(epok && ep == "C:/out/pic.jpg", "an export gets its format's extension")
		sv := macro_new("Save")
		s1 := macro_add_node(sv, "file.Save", 200, 0)
		macro_link(sv, macro_start(sv), s1.id)
		sok, smsg, _ := macro_run(sv)
		check(!sok && strings.contains(smsg, "never been saved"), "Save on a painting with no file and no file set says so")
		macro_free(sv)

		// the node search: names, then choices picked in advance
		hits := macro_search("soft light")
		check(len(hits) > 0 && hits[0].def.id == "layer.Blend" && hits[0].def.settings[hits[0].setting].choices[hits[0].choice] == "Soft Light", "typing a blend mode finds Layer Blend Mode with it picked")
		hits = macro_search("png")
		check(len(hits) > 0 && hits[0].def.id == "file.Export" && hits[0].def.settings[hits[0].setting].choices[hits[0].choice] == "png", "typing a format finds Export set to it")
		hits = macro_search("gaussian")
		check(len(hits) > 0 && hits[0].def.id == "fx.Gaussian_Blur" && hits[0].setting < 0, "typing a node's name finds the node first")
		hits = macro_search("")
		check(len(hits) == len(macro_shared_defs()) - 1 + len(macro_catalogue()), "with nothing typed, every node but Start is offered")
		check(len(macro_search("zzzz")) == 0, "nothing matches nonsense")
	}

	check(icons_ok(), "the app icon is there at every size")

	if fails == 0 {
		fmt.println("selftest: all passed")
	} else {
		fmt.printf("selftest: %d failure(s)\n", fails)
	}
	return fails
}

// Opens any supported file and exports it flattened (`--convert in out.png`), listing its layers;
// a headless check of the file readers.
convert_file :: proc(src, dst: string) -> int {
	brush_init()
	d, err := doc_load(src)
	if err != "" {
		fmt.eprintln(err)
		return 1
	}
	fmt.printf("%s: %dx%d, %d layer(s)\n", path_basename(src), d.w, d.h, len(d.layers))
	for &l, i in d.layers {
		fmt.printf("  %d %q opacity %d %v%s%s%s\n", i, name_str(&l.name), l.opacity, l.blend, l.visible ? "" : " hidden", l.has_mask ? " mask" : "", l.text.on ? " text" : (l.shape != nil ? " vector" : ""))
	}
	f := Export_Format.PNG
	for e, k in EXPORT_EXT {
		if int(k) < EXPORT_STILL_FORMATS && lower_ext(dst) == fmt.tprintf(".%s", e) do f = k
	}
	data := lower_ext(dst) == ".ppnt" ? project_encode(d) : export_encode(doc_flat(d, context.temp_allocator), d.w, d.h, f, 90)
	if data == nil || !write_file(dst, data) {
		fmt.eprintln("cannot write", dst)
		return 1
	}
	return 0
}

// Paints one sample stroke per brush preset onto a sheet (`--brush-sheet out.png`),
// for eyeballing brush quality at 100%.
brush_sheet :: proc(path: string) -> int {
	brush_init()
	row_h := 90
	w, h := 900, row_h * len(presets)
	d := doc_new_filled(w, h, "sheet", Color{244, 240, 230, 255})
	append(&docs, d)
	doc = d
	bands := [?]Color{{196, 58, 46, 255}, {236, 196, 60, 255}, {52, 100, 180, 255}, {30, 30, 34, 255}}
	cols := [?]Color{{30, 30, 34, 255}, {178, 52, 40, 255}, {40, 92, 170, 255}, {60, 130, 70, 255}}
	for p, i in presets {
		y0 := i * row_h
		// blending tools get color bands to work on
		if p.tool != .Brush && p.tool != .Oil {
			for y in y0 + 8 ..< y0 + row_h - 8 {
				for x in 160 ..< w {
					tiles_set(&d.layers[0].pix, x, y, bands[((x - 160) * len(bands)) / (w - 160)], {})
				}
			}
		} else {
			// a half-dark stripe to show coverage and mixing
			for y in y0 + 8 ..< y0 + row_h - 8 {
				for x in 520 ..< w {
					tiles_set(&d.layers[0].pix, x, y, Color{70, 60, 110, 255}, {})
				}
			}
		}
		brushes[p.tool] = p.b
		brushes[p.tool].size = min(p.b.size, row_h - 30)
		if p.tool == .Clone {
			clone_src_pt = Vec2{170, f32(y0 + row_h / 2)}
			clone_src_set, clone_realign = true, true
		}
		pts := 120
		for k in 0 ..= pts {
			u := f32(k) / f32(pts)
			pt := Vec2{170 + u * f32(w - 200), f32(y0 + row_h / 2) + 22 * f32(math.sin(u * 9))}
			if p.tool == .Clone do pt.x = 320 + u * f32(w - 360)
			if k == 0 {
				stroke_begin(p.tool, pt, cols[i % len(cols)])
			} else {
				stroke_move(pt)
			}
		}
		stroke_end()
	}
	doc_dirty_all(d)
	doc_refresh_comp(d)
	// labels are rasterised straight into the image
	cp := make([]Color, w * h)
	defer delete(cp)
	copy(cp, d.comp)
	for p, i in presets {
		image_draw_text(cp, w, h, 8, i * row_h + row_h / 2 - 5, fmt.tprintf("%v: %s", p.tool, p.name), 14, BLACK)
	}
	return write_file(path, encode_png(cp, w, h)) ? 0 : 1
}

// Every icon at the sizes the UI draws it (1x, 2x and 3x) plus a large proof, and the logo (`--icon-sheet`).
icon_sheet :: proc(path: string) -> int {
	SIZES :: [?]int{12, 16, 24, 32, 36, 48, 96}
	COL :: 300
	PER_ROW :: 4
	row_h := 0
	for s in SIZES do row_h = max(row_h, s)
	row_h += 34
	rows := (len(Icon) + PER_ROW - 1) / PER_ROW
	w := PER_ROW * COL + 20
	logo_h := 280
	h := rows * row_h + logo_h + 20
	pix := make([]Color, w * h)
	defer delete(pix)
	for &p in pix do p = C_PANEL
	put :: proc(pix: []Color, w, h: int, src: []Color, sw, sh, x, y: int, tint: Color) {
		for yy in 0 ..< sh {
			for xx in 0 ..< sw {
				s := src[yy * sw + xx]
				px, py := x + xx, y + yy
				if s.a == 0 || px < 0 || py < 0 || px >= w || py >= h do continue
				d := &pix[py * w + px]
				k := f32(s.a) / 255 * f32(tint.a) / 255
				for ch in 0 ..< 3 {
					d[ch] = u8(f32(d[ch]) * (1 - k) + f32(s[ch]) * f32(tint[ch]) / 255 * k + 0.5)
				}
			}
		}
	}
	for ic in Icon {
		i := int(ic)
		ox := 10 + (i % PER_ROW) * COL
		oy := 10 + (i / PER_ROW) * row_h
		x := ox
		for s, k in SIZES {
			icon_px := svg_render(ICON_SVG[ic], s, s, context.temp_allocator)
			put(pix, w, h, icon_px, s, s, x, oy + 16 + (row_h - 34 - s) / 2, k == 1 ? C_ACCENT : C_TEXT)
			x += s + 4
		}
		image_draw_text(pix, w, h, ox, oy, fmt.tprintf("%v", ic), 14, C_TEXT_DIM)
	}
	ly := 10 + rows * row_h
	x := 10
	for s in ([?]int{16, 32, 48, 64, 128, 256}) {
		lp := logo_pixels_at(i32(s))
		put(pix, w, h, lp, s, s, x, ly, WHITE)
		x += s + 12
	}
	return write_file(path, encode_png(pix, w, h)) ? 0 : 1
}

// Rough timings for big canvases (`--bench`).
bench :: proc() -> int {
	brush_init()
	d := doc_new_filled(4000, 3000, "bench", Color{240, 234, 220, 255})
	append(&docs, d)
	doc = d
	run :: proc(name: string, t: Tool, size: int, n: int) {
		brushes[t].size = size
		t0 := now_s()
		if !stroke_begin(t, {200, 1500}, Color{120, 60, 30, 255}) do return
		for i in 1 ..= n {
			stroke_move(Vec2{200 + f32(i) * 3000 / f32(n), 1500 + 600 * f32(math.sin(f32(i) * 0.05))})
			doc_refresh_comp(doc)
		}
		stroke_end()
		dt := now_s() - t0
		fmt.printf("%s (%d px): %.2f ms/frame\n", name, size, dt * 1000 / f64(n))
	}
	// 120 frames covering 3000 px: ~25 px of mouse travel per frame
	run("Brush hard", .Brush, 40, 120)
	run("Brush soft", .Brush, 300, 120)
	run("Oil", .Oil, 80, 120)
	run("Oil big", .Oil, 250, 120)
	run("Smudge", .Smudge, 150, 120)
	t0 := now_s()
	doc_dirty_all(d)
	doc_refresh_comp(d)
	fmt.printf("full composite 12 MP: %.1f ms\n", (now_s() - t0) * 1000)
	t0 = now_s()
	data := project_encode(d)
	fmt.printf("save project: %.1f ms, %d KB\n", (now_s() - t0) * 1000, len(data) / 1024)
	return bench_animation(d)
}

// 12 frames of the 12 MP painting above, as an animation over a background usually is: every frame a
// copy of the last with a new stroke, over the opaque background and a full Multiply layer.
@(private = "file")
bench_animation :: proc(d: ^Doc) -> int {
	FRAMES :: 12
	doc_add_layer(d)
	tiles_fill(&d.layers[d.active_layer].pix, Color{200, 180, 150, 128}, {})
	d.layers[d.active_layer].blend = .Multiply
	doc_add_layer(d)
	t0 := now_s()
	for i in 0 ..< FRAMES {
		if i > 0 do doc_add_frame(d, true)
		paint_line(.Brush, Color{u8(40 + i * 15), 90, 200, 255}, {f32(200 + i * 250), 300}, {f32(600 + i * 250), 2700}, 60)
	}
	fmt.printf("make %d frames with a stroke each: %.1f ms\n", FRAMES, (now_s() - t0) * 1000)
	t0 = now_s()
	for _ in 0 ..< 100 {
		history_push(d)
		history_discard(d)
	}
	fmt.printf("undo snapshot of 12 frames: %.3f ms\n", (now_s() - t0) * 1000 / 100)
	t0 = now_s()
	for i in 0 ..< 120 do frame_switch(d, i % FRAMES)
	fmt.printf("swap frames: %.3f ms\n", (now_s() - t0) * 1000 / 120)
	buf := make([]Color, d.w * d.h)
	defer delete(buf)
	t0 = now_s()
	for f in 0 ..< FRAMES do frame_composite(d, f, buf)
	t1 := now_s()
	fmt.printf("composite one frame: %.1f ms\n", (t1 - t0) * 1000 / FRAMES)
	small := make([]Color, (d.w / 4 + 1) * (d.h / 4 + 1))
	defer delete(small)
	t0 = now_s()
	shrink_level(buf, d.w, d.h, 2, small)
	fmt.printf("shrink to a quarter: %.1f ms\n", (now_s() - t0) * 1000)

	if !gfx_init(APP_NAME, true, 1600, 1000) do return 1
	defer gfx_shutdown()
	gfx_set_scale(1)
	ui.scale = 1
	draw_frame :: proc(d: ^Doc, f, k: int, tex: Texture) {
		gfx_poll()
		gfx_begin(C_BG)
		dst := FRect{0, 0, f32(d.w) * d.zoom, f32(d.h) * d.zoom}
		draw_tex(tex, frame_cache_src(d, k), dst)
		gfx_present()
	}
	d.zoom = 0.25 // a 12 MP painting fit to a 1000 px high window
	k := frame_cache_level(d)
	// what playback would cost without the cache: the whole composite, uploaded every frame
	tc := tex_create(d.w, d.h, .Linear)
	defer tex_destroy(&tc)
	t0 = now_s()
	for f in 0 ..< FRAMES {
		frame_composite(d, f, buf)
		tex_update(tc, buf)
		gfx_poll()
		gfx_begin(C_BG)
		draw_tex(tc, {0, 0, f32(d.w), f32(d.h)}, {0, 0, f32(d.w) * d.zoom, f32(d.h) * d.zoom})
		gfx_present()
	}
	fmt.printf("playback frame, no cache: %.1f ms\n", (now_s() - t0) * 1000 / FRAMES)
	for pass in 0 ..< 3 {
		t0 = now_s()
		for f in 0 ..< FRAMES {
			frame_switch(d, f)
			draw_frame(d, f, k, frame_cache_tex(d, f, k))
		}
		fmt.printf("playback frame, cache pass %d: %.1f ms\n", pass + 1, (now_s() - t0) * 1000 / FRAMES)
	}
	return 0
}

now_s :: proc() -> f64 {
	return f64(time.now()._nsec) / 1e9
}
