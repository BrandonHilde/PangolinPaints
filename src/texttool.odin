package pangolin

import "core:fmt"
import "core:strings"
import "core:unicode/utf8"

// ---------------------------------------------------------------------------
// Text tool: click the canvas to start a text layer, click existing text to edit it.
// Type on the canvas; Esc, Ctrl+Enter, or clicking elsewhere finishes. Every setting lives on the layer
// (and as defaults for the next one), so text stays editable and is saved with the project.
// ---------------------------------------------------------------------------

Text_Edit :: struct {
	active:  bool,
	d:       ^Doc,
	layer:   int,
	caret:   int, // byte index
	created: bool, // this session made the layer: an empty result removes it again
	want_x:  f32, // column kept while moving up / down
	vert:    bool, // the last key was Up or Down
	blink_t: f64,
}

text_edit: Text_Edit

// Settings for the next text layer.
text_defaults := Text_Info {
	size     = 48,
	color    = Color{20, 20, 24, 255},
	line_pct = 100,
}

text_hist_open: bool // one undo step covers a whole edit session / slider drag
text_end_time: f64 = -1 // frame on which a session ended, so the same key press is not handled twice

text_defaults_init :: proc() {
	if text_defaults.font.n == 0 {
		name_set(&text_defaults.font, DEFAULT_FONT)
	}
}

// The text layer being edited, if the session is still valid.
text_edit_layer :: proc() -> ^Layer {
	if !text_edit.active do return nil
	if text_edit.d != doc || text_edit.layer != doc.active_layer || text_edit.layer >= len(doc.layers) || !doc.layers[text_edit.layer].text.on {
		return nil
	}
	return &doc.layers[text_edit.layer]
}

text_editing :: proc() -> bool {
	return text_edit.active
}

text_end :: proc() {
	if !text_edit.active do return
	d := text_edit.d
	valid := text_edit_layer() != nil
	text_edit.active = false
	text_end_time = ui.time
	text_hist_open = false
	if !valid do return
	l := &d.layers[text_edit.layer]
	if l.text.n == 0 && text_edit.created {
		// nothing typed: take the whole new layer back
		history_revert(d)
		return
	}
	if name_str(&l.name) == "Text" && l.text.n > 0 {
		first := text_str(&l.text)
		if nl := strings.index_byte(first, '\n'); nl >= 0 do first = first[:nl]
		if len(first) > 28 do first = first[:28]
		name_set(&l.name, strings.trim_space(first))
	}
	d.thumb_dirty = true
}

// Call before changing the active text layer; groups consecutive changes into one undo step.
text_begin_change :: proc() {
	if !text_hist_open {
		history_push(doc)
		text_hist_open = true
	}
}

text_changed :: proc() {
	text_render_layer(doc, doc.active_layer)
}

@(private = "file")
text_target :: proc() -> ^Text_Info {
	l := &doc.layers[doc.active_layer]
	if l.text.on do return &l.text
	return &text_defaults
}

// Index of the topmost visible text layer whose block contains p.
text_layer_at :: proc(d: ^Doc, p: Vec2) -> int {
	for i := len(d.layers) - 1; i >= 0; i -= 1 {
		l := &d.layers[i]
		if !l.text.on || !l.visible do continue
		b := l.text.bx
		if box_empty(b) {
			b = Box{int(l.text.x) - 4, int(l.text.y) - 4, int(l.text.x) + 24, int(l.text.y) + l.text.size + 4}
		}
		if p.x >= f32(b.x0) && p.x < f32(b.x1) && p.y >= f32(b.y0) && p.y < f32(b.y1) do return i
	}
	return -1
}

text_click :: proc(p: Vec2) {
	d := doc
	text_defaults_init()
	// inside the block being edited: just move the caret
	if l := text_edit_layer(); l != nil {
		b := l.text.bx
		if p.x >= f32(b.x0) && p.x < f32(b.x1) && p.y >= f32(b.y0) && p.y < f32(b.y1) {
			text_edit.caret = text_hit_index(&l.text, p)
			text_edit.blink_t = ui.time
			return
		}
	}
	text_end()
	if li := text_layer_at(d, p); li >= 0 {
		if d.layers[li].locked {
			set_status("Layer is locked")
			return
		}
		tools_commit_pending()
		d.active_layer = li
		d.edit_mask = false
		history_push(d)
		text_hist_open = true
		text_edit = Text_Edit {
			active  = true,
			d       = d,
			layer   = li,
			caret   = text_hit_index(&d.layers[li].text, p),
			blink_t = ui.time,
		}
		return
	}
	history_push(d)
	text_hist_open = true
	l := layer_make("Text", d.w, d.h)
	l.text = text_defaults
	l.text.on = true
	l.text.n = 0
	l.text.x, l.text.y = p.x, p.y
	l.text.color = fg
	text_defaults.color = fg
	inject_at(&d.layers, d.active_layer + 1, l)
	d.active_layer += 1
	d.edit_mask = false
	doc_touch_all(d)
	text_edit = Text_Edit {
		active  = true,
		d       = d,
		layer   = d.active_layer,
		created = true,
		blink_t = ui.time,
	}
}

@(private = "file")
insert_text :: proc(l: ^Layer, s: string) {
	ti := &l.text
	for r in s {
		if r == '\r' do continue
		if r < 32 && r != '\n' do continue
		if r == 127 do continue
		enc, n := utf8.encode_rune(r)
		if ti.n + n > TEXT_MAX do break
		c := text_edit.caret
		copy(ti.buf[c + n:ti.n + n], ti.buf[c:ti.n])
		copy(ti.buf[c:c + n], enc[:n])
		ti.n += n
		text_edit.caret += n
	}
}

@(private = "file")
prev_rune_start :: proc(ti: ^Text_Info, i: int) -> int {
	j := i - 1
	for j > 0 && ti.buf[j] & 0xC0 == 0x80 do j -= 1
	return max(j, 0)
}

@(private = "file")
next_rune_end :: proc(ti: ^Text_Info, i: int) -> int {
	j := i + 1
	for j < ti.n && ti.buf[j] & 0xC0 == 0x80 do j += 1
	return min(j, ti.n)
}

// Keyboard handling while a text layer is being edited. Runs before the global shortcuts.
text_update :: proc() {
	if !text_edit.active do return
	l := text_edit_layer()
	if l == nil {
		text_end()
		return
	}
	if dialog.kind != .None || cur_tool != .Text {
		text_end()
		return
	}
	ti := &l.text
	changed := false
	typed := false
	if len(ui.chars) > 0 {
		b: strings.Builder
		strings.builder_init(&b, context.temp_allocator)
		for r in ui.chars do strings.write_rune(&b, r)
		insert_text(l, strings.to_string(b))
		changed = true
		typed = true
	}
	if ui.ctrl && IsKeyPressed(.V) {
		insert_text(l, gfx_clipboard_get())
		changed = true
		typed = true
	}
	key :: proc(k: KeyboardKey) -> bool {
		return IsKeyPressed(k) || IsKeyPressedRepeat(k)
	}
	if key(.ENTER) {
		if ui.ctrl {
			text_end()
			return
		}
		insert_text(l, "\n")
		changed = true
		typed = true
	}
	if key(.BACKSPACE) && text_edit.caret > 0 {
		s := prev_rune_start(ti, text_edit.caret)
		copy(ti.buf[s:], ti.buf[text_edit.caret:ti.n])
		ti.n -= text_edit.caret - s
		text_edit.caret = s
		changed = true
		typed = true
	}
	if key(.DELETE) && text_edit.caret < ti.n {
		e := next_rune_end(ti, text_edit.caret)
		copy(ti.buf[text_edit.caret:], ti.buf[e:ti.n])
		ti.n -= e - text_edit.caret
		changed = true
		typed = true
	}
	moved := false
	if changed || key(.LEFT) || key(.RIGHT) do text_edit.vert = false
	if key(.LEFT) {
		text_edit.caret = prev_rune_start(ti, text_edit.caret)
		moved = true
	}
	if key(.RIGHT) {
		text_edit.caret = next_rune_end(ti, text_edit.caret)
		moved = true
	}
	if key(.HOME) || key(.END) || key(.UP) || key(.DOWN) {
		L := text_layout(ti)
		li := 0
		for ln, i in L.lines {
			if text_edit.caret >= ln.a && text_edit.caret <= ln.b do li = i
		}
		if len(L.lines) > 0 {
			if key(.HOME) do text_edit.caret = L.lines[li].a
			if key(.END) do text_edit.caret = L.lines[li].b
			if key(.UP) || key(.DOWN) {
				cx, _, _ := text_caret_xy(ti, text_edit.caret)
				if !text_edit.vert do text_edit.want_x = cx
				nl := clamp(li + (key(.DOWN) ? 1 : -1), 0, len(L.lines) - 1)
				text_edit.caret = text_hit_index(ti, {text_edit.want_x, ti.y + (f32(nl) + 0.5) * L.lh})
				text_edit.vert = true
			}
		}
		moved = true
	}
	if IsKeyPressed(.ESCAPE) {
		text_end()
		return
	}
	if changed || moved {
		text_edit.blink_t = ui.time
	}
	if changed {
		text_render_layer(doc, doc.active_layer)
	}
	_ = typed
}

// Overlay: block outline and caret.
text_draw_overlay :: proc(d: ^Doc) {
	if cur_tool != .Text do return
	l := &d.layers[d.active_layer]
	if !l.text.on do return
	ti := &l.text
	b := text_bounds(ti)
	if !box_empty(l.text.bx) && ti.n > 0 do b = box_union(b, l.text.bx)
	a := canvas_to_screen({f32(b.x0), f32(b.y0)})
	z := canvas_to_screen({f32(b.x1), f32(b.y1)})
	editing := text_edit_layer() != nil
	col := editing ? C_ACCENT : Color{246, 170, 104, 120}
	draw_rect_outline({a.x, a.y, z.x - a.x, z.y - a.y}, col)
	if editing && i32((ui.time - text_edit.blink_t) * 2) % 2 == 0 {
		cx, cy, ch := text_caret_xy(ti, text_edit.caret)
		s0 := canvas_to_screen({cx, cy})
		s1 := canvas_to_screen({cx, cy + ch})
		draw_rect(s0.x, s0.y, hair() * 2, max(s1.y - s0.y, 4), C_ACCENT)
		draw_rect(s0.x - hair(), s0.y, hair() * 4, max(s1.y - s0.y, 4), Color{0, 0, 0, 90})
		draw_rect(s0.x, s0.y, hair() * 2, max(s1.y - s0.y, 4), C_ACCENT)
	}
}

// Options bar ----------------------------------------------------------------

text_font_pick_open :: proc() {
	fonts_ensure()
	dialog_open(.Font)
}

options_text :: proc(x: ^i32, y: i32) {
	text_defaults_init()
	l := &doc.layers[doc.active_layer]
	live := l.text.on
	ti := text_target()
	apply :: proc(live: bool) {
		if live do text_changed()
	}
	before := ti^
	// font
	fr := Rect{x^, y, 120, 14}
	if button(fr, name_str(&ti.font), "Font (click to choose)") {
		text_font_pick_open()
	}
	x^ += 125
	sz := ti.size
	if slider({x^, y, 92, 14}, &sz, 6, 600, "Size", "Text size in pixels", "px", 2) {
		if live do text_begin_change()
		ti.size = sz
		apply(live)
	}
	x^ += 97
	// colour chip: shows the text colour; click to take the foreground colour
	cr := Rect{x^, y, 24, 14}
	id := make_id(cr, "textcol")
	clicked, _, hover := button_behavior(id, cr, "Text colour (click to use the foreground colour)")
	draw_rrect(f32(cr.x), f32(cr.y), 24, 14, RADIUS, ti.color)
	draw_rrect_outline(f32(cr.x), f32(cr.y), 24, 14, RADIUS, hover ? WHITE : C_RING_HI)
	if clicked {
		if live do text_begin_change()
		ti.color = fg
		apply(live)
	}
	x^ += 30
	al := int(ti.align)
	AL := [?]string{"Left", "Center", "Right"}
	if nv, ch := combo({x^, y, 66, 14}, AL[:], al, "Alignment"); ch {
		if live do text_begin_change()
		ti.align = u8(nv)
		apply(live)
	}
	x^ += 71
	lp := ti.line_pct
	if slider({x^, y, 92, 14}, &lp, 50, 300, "Lines", "Line spacing", "%") {
		if live do text_begin_change()
		ti.line_pct = lp
		apply(live)
	}
	x^ += 97
	tr := ti.track
	if slider({x^, y, 88, 14}, &tr, -20, 100, "Spacing", "Letter spacing (1/100 of the size)", "") {
		if live do text_begin_change()
		ti.track = tr
		apply(live)
	}
	x^ += 93
	if live {
		// changes while no edit session is open each get their own undo step on the first touch
		if !ui.down[0] && !text_edit.active do text_hist_open = false
	}
	hint := "Click the canvas to type" if !live else "Esc or Ctrl+Enter: finish"
	text(x^ + 4, y + 3, hint, C_TEXT_DIM)
	// keep the defaults in step with what the user last chose
	if live && before != ti^ {
		text_defaults.font = ti.font
		text_defaults.size = ti.size
		text_defaults.align = ti.align
		text_defaults.line_pct = ti.line_pct
		text_defaults.track = ti.track
	}
}

// Font picker dialog ---------------------------------------------------------

font_filter: Name
font_scroll: i32

dlg_font :: proc() {
	fonts_ensure()
	c := dialog_frame("Choose Font", 320, 330)
	text(c.x, c.y + 3, "Search", C_TEXT)
	text_field({c.x + 50, c.y, c.w - 50, 14}, &font_filter)
	list := Rect{c.x, c.y + 22, c.w, c.h - 22 - 24}
	ctl_well(list)
	ROW :: 16
	flt := strings.to_lower(name_str(&font_filter), context.temp_allocator)
	idx := make([dynamic]int, context.temp_allocator)
	for f, i in ufonts {
		if flt == "" || strings.contains(strings.to_lower(f.name, context.temp_allocator), flt) {
			append(&idx, i)
		}
	}
	if ui_hover(list) && ui.wheel != 0 {
		font_scroll -= i32(ui.wheel) * ROW * 3
	}
	inner := rect_inset(list, 1)
	font_scroll = clamp(font_scroll, 0, max(i32(len(idx)) * ROW - inner.h, 0))
	cur := name_str(&text_target().font)
	clip_begin(inner)
	chosen := -1
	for k, row in idx {
		f := ufonts[k]
		ry := inner.y + i32(row) * ROW - font_scroll
		if ry + ROW < inner.y || ry > inner.y + inner.h do continue
		rr := Rect{inner.x, ry, inner.w, ROW}
		hover := ui_hover(rr) && ui_hover(list)
		if f.name == cur {
			fill_rect(rr, C_ACCENT_TINT)
		} else if hover {
			fill_rect(rr, Color{255, 255, 255, 14})
		}
		text(rr.x + 8, rr.y + (ROW - FONT_CAP) / 2, f.name, f.name == cur ? C_ACCENT : C_TEXT)
		if hover && ui.pressed[0] do chosen = k
	}
	clip_end()
	if len(idx) == 0 {
		text(list.x + 8, list.y + 8, "No matching fonts", C_TEXT_DIM)
	}
	if chosen >= 0 {
		ti := text_target()
		live := doc.layers[doc.active_layer].text.on
		if live do text_begin_change()
		name_set(&ti.font, ufonts[chosen].name)
		text_defaults.font = ti.font
		if live {
			text_changed()
			text_hist_open = false
		}
		dialog_close()
		return
	}
	cancel := button_primary({c.x + c.w - 64, c.y + c.h - 18, 64, 18}, "Close")
	if cancel || IsKeyPressed(.ESCAPE) do dialog_close()
}
