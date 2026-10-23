package pangolin

import "core:fmt"
import "core:math"
import "core:strconv"
import "core:strings"
import rl "vendor:raylib"

FONT_SIZE :: 10

// Theme ----------------------------------------------------------------------
C_BG :: Color{30, 30, 36, 255}
C_PANEL :: Color{44, 44, 53, 255}
C_PANEL_DK :: Color{28, 28, 34, 255}
C_PANEL_LT :: Color{62, 62, 76, 255}
C_BORDER :: Color{16, 16, 20, 255}
C_HOVER :: Color{78, 78, 98, 255}
C_ACTIVE :: Color{150, 88, 58, 255}
C_ACCENT :: Color{240, 152, 96, 255}
C_SLIDER :: Color{112, 68, 48, 255}
C_TEXT :: Color{224, 224, 236, 255}
C_TEXT_DIM :: Color{138, 138, 156, 255}
C_VIEWPORT :: Color{58, 58, 68, 255}
C_DANGER :: Color{220, 90, 90, 255}

UI :: struct {
	w, h:                int, // logical window size
	scale:               i32,
	mx, my:              i32,
	pmx, pmy:            i32,
	down, pressed, released: [3]bool,
	wheel:               f32,
	wheel_h:             f32,
	active_id:           u32,
	focus_id:            u32,
	hover_id:            u32,
	hover_t:             f32,
	hover_seen:          bool,
	layer, input_layer:  int,
	chars:               [dynamic]rune,
	dt:                  f32,
	time:                f64,
	tip:                 string,
	cursor:              rl.MouseCursor,
	font:                rl.Font,
	icons:               rl.Texture2D,
	caret:               int,
	sel_all:             bool,
	edit:                Name,
	popup_result_id:     u32,
	popup_result_val:    int,
	last_click_t:        f64,
	last_click_id:       u32,
	dbl_click:           bool,
	ctrl, shift, alt:    bool,
	hide_cursor:         bool,
}

ui: UI

in_rect :: proc(r: Rect, x, y: i32) -> bool {
	return x >= r.x && y >= r.y && x < r.x + r.w && y < r.y + r.h
}

rect_inset :: proc(r: Rect, n: i32) -> Rect {
	return Rect{r.x + n, r.y + n, max(r.w - 2 * n, 0), max(r.h - 2 * n, 0)}
}

cut_left :: proc(r: ^Rect, w: i32) -> Rect {
	out := Rect{r.x, r.y, min(w, r.w), r.h}
	r.x += out.w
	r.w -= out.w
	return out
}

cut_right :: proc(r: ^Rect, w: i32) -> Rect {
	ww := min(w, r.w)
	out := Rect{r.x + r.w - ww, r.y, ww, r.h}
	r.w -= ww
	return out
}

cut_top :: proc(r: ^Rect, h: i32) -> Rect {
	out := Rect{r.x, r.y, r.w, min(h, r.h)}
	r.y += out.h
	r.h -= out.h
	return out
}

cut_bottom :: proc(r: ^Rect, h: i32) -> Rect {
	hh := min(h, r.h)
	out := Rect{r.x, r.y + r.h - hh, r.w, hh}
	r.h -= hh
	return out
}

to_rl :: proc(r: Rect) -> rl.Rectangle {
	return rl.Rectangle{f32(r.x), f32(r.y), f32(r.w), f32(r.h)}
}

// Drawing helpers --------------------------------------------------------------

fill_rect :: proc(r: Rect, c: Color) {
	rl.DrawRectangle(r.x, r.y, r.w, r.h, c)
}

outline_rect :: proc(r: Rect, c: Color) {
	rl.DrawRectangleLines(r.x, r.y, r.w, r.h, c)
}

hline :: proc(x, y, w: i32, c: Color) {
	rl.DrawRectangle(x, y, w, 1, c)
}

vline :: proc(x, y, h: i32, c: Color) {
	rl.DrawRectangle(x, y, 1, h, c)
}

text :: proc(x, y: i32, s: string, c: Color) {
	if len(s) == 0 {
		return
	}
	cs := strings.clone_to_cstring(s, context.temp_allocator)
	rl.DrawTextEx(ui.font, cs, {f32(x), f32(y)}, FONT_SIZE, 1, c)
}

text_w :: proc(s: string) -> i32 {
	if len(s) == 0 {
		return 0
	}
	cs := strings.clone_to_cstring(s, context.temp_allocator)
	return i32(rl.MeasureTextEx(ui.font, cs, FONT_SIZE, 1).x)
}

textf :: proc(x, y: i32, c: Color, format: string, args: ..any) {
	text(x, y, fmt.tprintf(format, ..args), c)
}

text_centered :: proc(r: Rect, s: string, c: Color) {
	tw := text_w(s)
	text(r.x + (r.w - tw) / 2, r.y + (r.h - 8) / 2, s, c)
}

text_clipped :: proc(r: Rect, s: string, c: Color) {
	clip_begin(r)
	text(r.x, r.y + (r.h - 8) / 2, s, c)
	clip_end()
}

clip_begin :: proc(r: Rect) {
	rl.BeginScissorMode(r.x, r.y, r.w, r.h)
}

clip_end :: proc() {
	rl.EndScissorMode()
}

icon :: proc(ic: Icon, x, y: i32, c: Color) {
	rl.DrawTextureRec(ui.icons, {f32(int(ic) * ICON_SIZE), 0, ICON_SIZE, ICON_SIZE}, {f32(x), f32(y)}, c)
}

icon_centered :: proc(ic: Icon, r: Rect, c: Color) {
	icon(ic, r.x + (r.w - ICON_SIZE) / 2, r.y + (r.h - ICON_SIZE) / 2, c)
}

// Small "+" / "-" badge in the top-right corner of a 12x12 icon.
icon_badge :: proc(x, y: i32, plus: bool, c: Color) {
	bx := x + 8
	by := y + 0
	rl.DrawRectangle(bx, by + 2, 5, 1, c)
	if plus {
		rl.DrawRectangle(bx + 2, by, 1, 5, c)
	}
}

// Frame / input ------------------------------------------------------------------

ui_begin_frame :: proc() {
	m := rl.GetMousePosition()
	ui.pmx, ui.pmy = ui.mx, ui.my
	ui.mx = i32(m.x) / ui.scale
	ui.my = i32(m.y) / ui.scale
	btns := [3]rl.MouseButton{.LEFT, .RIGHT, .MIDDLE}
	for b, i in btns {
		ui.down[i] = rl.IsMouseButtonDown(b)
		ui.pressed[i] = rl.IsMouseButtonPressed(b)
		ui.released[i] = rl.IsMouseButtonReleased(b)
	}
	wh := rl.GetMouseWheelMoveV()
	ui.wheel = wh.y
	ui.wheel_h = wh.x
	clear(&ui.chars)
	for {
		c := rl.GetCharPressed()
		if c == 0 {
			break
		}
		append(&ui.chars, c)
	}
	ui.dt = rl.GetFrameTime()
	ui.time = rl.GetTime()
	ui.cursor = .DEFAULT
	ui.hide_cursor = false
	ui.tip = ""
	ui.hover_seen = false
	ui.ctrl = rl.IsKeyDown(.LEFT_CONTROL) || rl.IsKeyDown(.RIGHT_CONTROL)
	ui.shift = rl.IsKeyDown(.LEFT_SHIFT) || rl.IsKeyDown(.RIGHT_SHIFT)
	ui.alt = rl.IsKeyDown(.LEFT_ALT) || rl.IsKeyDown(.RIGHT_ALT)
	ui.dbl_click = false
	if ui.pressed[0] {
		if ui.time - ui.last_click_t < 0.35 {
			ui.dbl_click = true
		}
		ui.last_click_t = ui.time
	}
	ui.layer = 0
}

ui_end_frame :: proc() {
	if ui.hover_seen {
		ui.hover_t += ui.dt
	} else {
		ui.hover_id = 0
		ui.hover_t = 0
	}
	if !ui.down[0] && !ui.down[1] {
		ui.active_id = 0
	}
	rl.SetMouseCursor(ui.cursor)
	@(static) hidden: bool
	if ui.hide_cursor != hidden {
		hidden = ui.hide_cursor
		if hidden {
			rl.HideCursor()
		} else {
			rl.ShowCursor()
		}
	}
}

make_id :: proc(r: Rect, s: string) -> u32 {
	h: u32 = 2166136261
	for i in 0 ..< len(s) {
		h = (h ~ u32(s[i])) * 16777619
	}
	h = (h ~ u32(r.x)) * 16777619
	h = (h ~ u32(r.y)) * 16777619
	h = (h ~ u32(ui.layer)) * 16777619
	return h | 1
}

ui_hover :: proc(r: Rect) -> bool {
	return ui.layer == ui.input_layer && in_rect(r, ui.mx, ui.my)
}

tooltip_hover :: proc(id: u32, tip: string) {
	ui.hover_seen = true
	if ui.hover_id != id {
		ui.hover_id = id
		ui.hover_t = 0
	} else if ui.hover_t > 0.45 && tip != "" {
		ui.tip = tip
	}
}

key_hit :: proc(k: rl.KeyboardKey) -> bool {
	return rl.IsKeyPressed(k) || rl.IsKeyPressedRepeat(k)
}

// Generic press/hold/click behaviour.
button_behavior :: proc(id: u32, r: Rect, tip: string) -> (clicked, held, hover: bool) {
	hover = ui_hover(r)
	if hover {
		tooltip_hover(id, tip)
		if ui.pressed[0] {
			ui.active_id = id
		}
	}
	if ui.active_id == id {
		held = ui.down[0]
		if ui.released[0] {
			if hover {
				clicked = true
			}
			ui.active_id = 0
		}
	}
	return
}

// Widgets ----------------------------------------------------------------------

button :: proc(r: Rect, label: string, tip := "", enabled := true, highlight := false) -> bool {
	id := make_id(r, label)
	clicked, held, hover := button_behavior(id, r, tip)
	if !enabled {
		clicked, held, hover = false, false, false
	}
	bg := C_PANEL_LT
	if highlight {
		bg = C_ACTIVE
	}
	if hover {
		bg = C_HOVER
	}
	if held {
		bg = C_ACTIVE
	}
	fill_rect(r, bg)
	outline_rect(r, C_BORDER)
	text_centered(r, label, enabled ? C_TEXT : C_TEXT_DIM)
	return clicked
}

icon_button :: proc(r: Rect, ic: Icon, tip := "", active := false, enabled := true) -> bool {
	id := make_id(r, tip)
	clicked, held, hover := button_behavior(id, r, tip)
	if !enabled {
		clicked, held, hover = false, false, false
	}
	bg := C_PANEL_LT
	if active {
		bg = C_ACTIVE
	}
	if hover {
		bg = active ? C_ACCENT : C_HOVER
	}
	if held {
		bg = C_ACTIVE
	}
	fill_rect(r, bg)
	outline_rect(r, C_BORDER)
	icon_centered(ic, r, enabled ? C_TEXT : C_TEXT_DIM)
	return clicked
}

// Icon button with a +/- badge (new layer, delete frame ...).
badge_button :: proc(r: Rect, ic: Icon, plus: bool, tip := "", enabled := true) -> bool {
	clicked := icon_button(r, ic, tip, false, enabled)
	x := r.x + (r.w - ICON_SIZE) / 2
	y := r.y + (r.h - ICON_SIZE) / 2
	icon_badge(x, y, plus, enabled ? C_ACCENT : C_TEXT_DIM)
	return clicked
}

toggle_button :: proc(r: Rect, ic: Icon, v: ^bool, tip := "") -> bool {
	if icon_button(r, ic, tip, v^) {
		v^ = !v^
		return true
	}
	return false
}

checkbox :: proc(x, y: i32, label: string, v: ^bool, tip := "") -> bool {
	r := Rect{x, y, 14 + text_w(label), 12}
	id := make_id(r, label)
	clicked, _, hover := button_behavior(id, r, tip)
	box := Rect{x, y + 1, 10, 10}
	fill_rect(box, C_PANEL_DK)
	outline_rect(box, hover ? C_ACCENT : C_BORDER)
	if v^ {
		icon(.Check, box.x - 1, box.y - 1, C_ACCENT)
	}
	text(x + 14, y + 1, label, C_TEXT)
	if clicked {
		v^ = !v^
		return true
	}
	return false
}

// Horizontal slider with value drawn inside. `suffix` is appended to the value
// ("%", "px"); `curve` > 1 gives finer control at the low end (brush sizes).
slider :: proc(r: Rect, v: ^int, lo, hi: int, label: string, tip := "", suffix := "", curve: f32 = 1, div := 1) -> bool {
	id := make_id(r, label)
	_, held, hover := button_behavior(id, r, tip)
	changed := false
	if held || (hover && ui.pressed[0]) {
		t := clamp(f32(ui.mx - r.x) / f32(max(r.w - 1, 1)), 0, 1)
		if curve != 1 {
			t = math.pow(t, curve)
		}
		nv := lo + int(t * f32(hi - lo) + 0.5)
		nv = clamp(nv, lo, hi)
		if nv != v^ {
			v^ = nv
			changed = true
		}
	}
	if hover && ui.wheel != 0 {
		step := 1
		if curve != 1 {
			step = max(v^ / 10, 1)
		}
		nv := clamp(v^ + (ui.wheel > 0 ? step : -step), lo, hi)
		if nv != v^ {
			v^ = nv
			changed = true
		}
	}
	fill_rect(r, C_PANEL_DK)
	frac := f32(v^ - lo) / f32(max(hi - lo, 1))
	if curve != 1 {
		frac = math.pow(clamp(frac, 0, 1), 1 / curve)
	}
	fill_rect(Rect{r.x, r.y, i32(f32(r.w) * frac), r.h}, hover || held ? C_ACTIVE : C_SLIDER)
	outline_rect(r, C_BORDER)
	vs := div > 1 ? fmt.tprintf("%.*f", div >= 100 ? 2 : 1, f32(v^) / f32(div)) : fmt.tprintf("%d", v^)
	s := label == "" ? fmt.tprintf("%s%s", vs, suffix) : fmt.tprintf("%s: %s%s", label, vs, suffix)
	text_centered(r, s, C_TEXT)
	return changed
}

// Editing core shared by text and numeric fields. Returns (submitted, blurred, cancelled).
edit_core :: proc(buf: ^Name, r: Rect, id: u32, ascii_only := true) -> (submitted, blurred, cancelled: bool) {
	// focus loss by clicking elsewhere
	hover := ui_hover(r)
	if ui.pressed[0] && !hover {
		ui.focus_id = 0
		return false, true, false
	}
	if ui.pressed[0] && hover {
		// place caret
		rel := ui.mx - r.x - 3
		best := 0
		for i in 0 ..= buf.n {
			if text_w(string(buf.b[:i])) <= rel {
				best = i
			}
		}
		ui.caret = best
		ui.sel_all = false
	}
	ui.caret = clamp(ui.caret, 0, buf.n)

	insert :: proc(buf: ^Name, s: string) {
		if ui.sel_all {
			buf.n = 0
			ui.caret = 0
			ui.sel_all = false
		}
		for i in 0 ..< len(s) {
			if buf.n >= len(buf.b) {
				break
			}
			ch := s[i]
			if ch < 32 || ch > 126 {
				continue
			}
			copy(buf.b[ui.caret + 1:buf.n + 1], buf.b[ui.caret:buf.n])
			buf.b[ui.caret] = ch
			buf.n += 1
			ui.caret += 1
		}
	}

	for ch in ui.chars {
		if ch >= 32 && ch < 127 {
			tmp := [1]u8{u8(ch)}
			insert(buf, string(tmp[:]))
		}
	}
	if ui.ctrl && rl.IsKeyPressed(.V) {
		cb := rl.GetClipboardText()
		if cb != nil {
			insert(buf, string(cb))
		}
	}
	if ui.ctrl && rl.IsKeyPressed(.C) {
		rl.SetClipboardText(strings.clone_to_cstring(name_str(buf), context.temp_allocator))
	}
	if ui.ctrl && rl.IsKeyPressed(.A) {
		ui.sel_all = true
	}
	if key_hit(.BACKSPACE) {
		if ui.sel_all {
			buf.n = 0
			ui.caret = 0
			ui.sel_all = false
		} else if ui.caret > 0 {
			copy(buf.b[ui.caret - 1:buf.n - 1], buf.b[ui.caret:buf.n])
			buf.n -= 1
			ui.caret -= 1
		}
	}
	if key_hit(.DELETE) {
		if ui.sel_all {
			buf.n = 0
			ui.caret = 0
			ui.sel_all = false
		} else if ui.caret < buf.n {
			copy(buf.b[ui.caret:buf.n - 1], buf.b[ui.caret + 1:buf.n])
			buf.n -= 1
		}
	}
	if key_hit(.LEFT) {
		ui.sel_all = false
		ui.caret = max(ui.caret - 1, 0)
	}
	if key_hit(.RIGHT) {
		ui.sel_all = false
		ui.caret = min(ui.caret + 1, buf.n)
	}
	if rl.IsKeyPressed(.HOME) {
		ui.sel_all = false
		ui.caret = 0
	}
	if rl.IsKeyPressed(.END) {
		ui.sel_all = false
		ui.caret = buf.n
	}
	if rl.IsKeyPressed(.ENTER) || rl.IsKeyPressed(.KP_ENTER) {
		ui.focus_id = 0
		submitted = true
	}
	if rl.IsKeyPressed(.ESCAPE) {
		ui.focus_id = 0
		cancelled = true
	}
	return
}

draw_edit_box :: proc(r: Rect, buf: ^Name, focused: bool) {
	fill_rect(r, C_PANEL_DK)
	outline_rect(r, focused ? C_ACCENT : C_BORDER)
	s := name_str(buf)
	clip_begin(rect_inset(r, 1))
	off: i32 = 0
	cw := text_w(string(buf.b[:clamp(ui.caret, 0, buf.n)]))
	if focused && cw > r.w - 8 {
		off = cw - (r.w - 8)
	}
	if focused && ui.sel_all && buf.n > 0 {
		fill_rect(Rect{r.x + 2 - off, r.y + 2, text_w(s) + 2, r.h - 4}, C_ACTIVE)
	}
	text(r.x + 3 - off, r.y + (r.h - 8) / 2, s, C_TEXT)
	if focused && !ui.sel_all && i32(ui.time * 2) % 2 == 0 {
		vline(r.x + 3 - off + cw, r.y + 3, r.h - 6, C_TEXT)
	}
	clip_end()
}

// Single-line text field. Returns (changed, submitted).
text_field :: proc(r: Rect, buf: ^Name, tip := "") -> (changed, submitted: bool) {
	id := make_id(r, "text")
	focused := ui.focus_id == id
	hover := ui_hover(r)
	if hover {
		ui.cursor = .IBEAM
		tooltip_hover(id, tip)
	}
	if focused {
		before := buf^
		sub, _, _ := edit_core(buf, r, id)
		submitted = sub
		changed = before.n != buf.n || before.b != buf.b
	} else if hover && ui.pressed[0] {
		ui.focus_id = id
		ui.sel_all = true
		ui.caret = buf.n
	}
	draw_edit_box(r, buf, ui.focus_id == id)
	return
}

// Numeric field: click to type, mouse wheel to nudge.
field_int :: proc(r: Rect, v: ^int, lo, hi: int, tip := "") -> bool {
	id := make_id(r, "int")
	focused := ui.focus_id == id
	hover := ui_hover(r)
	changed := false
	if hover {
		ui.cursor = .IBEAM
		tooltip_hover(id, tip)
	}
	if focused {
		before := ui.edit
		sub, blur, _ := edit_core(&ui.edit, r, id)
		typed := before.n != ui.edit.n || before.b != ui.edit.b
		if sub || blur || typed {
			n, ok := strconv.parse_int(name_str(&ui.edit))
			// While typing only accept values already inside the range, so that
			// e.g. typing "1" then "6" into a field with minimum 10 works.
			if ok && (sub || blur || (n >= lo && n <= hi)) {
				nv := clamp(n, lo, hi)
				if nv != v^ {
					v^ = nv
					changed = true
				}
			}
		}
		draw_edit_box(r, &ui.edit, ui.focus_id == id)
	} else {
		if hover && ui.pressed[0] {
			ui.focus_id = id
			name_set(&ui.edit, fmt.tprintf("%d", v^))
			ui.sel_all = true
			ui.caret = ui.edit.n
		}
		if hover && ui.wheel != 0 {
			nv := clamp(v^ + (ui.wheel > 0 ? 1 : -1), lo, hi)
			if nv != v^ {
				v^ = nv
				changed = true
			}
		}
		fill_rect(r, C_PANEL_DK)
		outline_rect(r, hover ? C_ACCENT : C_BORDER)
		s := fmt.tprintf("%d", v^)
		text(r.x + 3, r.y + (r.h - 8) / 2, s, C_TEXT)
	}
	return changed
}

label :: proc(x, y: i32, s: string, c := C_TEXT) {
	text(x, y, s, c)
}

// Popup menus / combos -----------------------------------------------------------

Popup_Item :: struct {
	label:   Name,
	value:   int,
	cmd:     Cmd,
	checked: bool,
	enabled: bool,
	sep:     bool,
}

Popup :: struct {
	open:      bool,
	owner:     u32,
	menu_idx:  int, // menubar index or -1
	anchor:    Rect,
	min_w:     i32,
	items:     [dynamic]Popup_Item,
	above:     bool,
	side:      bool, // open to the right of the anchor
}

popup: Popup

popup_begin :: proc(owner: u32, anchor: Rect, min_w: i32 = 0, menu_idx := -1) {
	popup.open = true
	popup.owner = owner
	popup.anchor = anchor
	popup.min_w = max(min_w, anchor.w)
	popup.menu_idx = menu_idx
	popup.above = false
	popup.side = false
	clear(&popup.items)
}

popup_item :: proc(label: string, value := 0, cmd := Cmd.None, checked := false, enabled := true) {
	it := Popup_Item {
		label   = make_name(label),
		value   = value,
		cmd     = cmd,
		checked = checked,
		enabled = enabled,
	}
	append(&popup.items, it)
}

popup_sep :: proc() {
	append(&popup.items, Popup_Item{sep = true})
}

popup_close :: proc() {
	popup.open = false
	clear(&popup.items)
}

POPUP_ITEM_H :: 14

popup_run :: proc() {
	if !popup.open {
		return
	}
	ui.layer = ui.input_layer
	w := popup.min_w
	h: i32 = 4
	for &it in popup.items {
		if it.sep {
			h += 5
			continue
		}
		iw := text_w(name_str(&it.label)) + 28
		if it.cmd != .None {
			sc := shortcut_text(it.cmd)
			if sc != "" {
				iw += text_w(sc) + 16
			}
		}
		w = max(w, iw)
		h += POPUP_ITEM_H
	}
	x := popup.anchor.x
	y := popup.anchor.y + popup.anchor.h
	if popup.side {
		x = popup.anchor.x + popup.anchor.w
		y = popup.anchor.y
	}
	if x + w > i32(ui.w) {
		x = i32(ui.w) - w
	}
	if y + h > i32(ui.h) {
		y = max(popup.anchor.y - h, 0)
		if popup.side {
			y = i32(ui.h) - h
		}
	}
	box := Rect{x, y, w, h}
	// shadow + frame
	fill_rect(Rect{box.x + 2, box.y + 2, box.w, box.h}, Color{0, 0, 0, 90})
	fill_rect(box, C_PANEL)
	outline_rect(box, C_BORDER)
	cy := box.y + 2
	for &it in popup.items {
		if it.sep {
			hline(box.x + 4, cy + 2, box.w - 8, C_PANEL_LT)
			cy += 5
			continue
		}
		ir := Rect{box.x + 2, cy, box.w - 4, POPUP_ITEM_H}
		hover := ui_hover(ir) && it.enabled
		if hover {
			fill_rect(ir, C_ACTIVE)
		}
		col := it.enabled ? C_TEXT : C_TEXT_DIM
		if it.checked {
			icon(.Check, ir.x + 1, ir.y + 1, col)
		}
		text(ir.x + 14, ir.y + 3, name_str(&it.label), col)
		if it.cmd != .None {
			sc := shortcut_text(it.cmd)
			if sc != "" {
				text(ir.x + ir.w - text_w(sc) - 6, ir.y + 3, sc, C_TEXT_DIM)
			}
		}
		if hover && ui.pressed[0] {
			cmd := it.cmd
			if cmd == .None {
				ui.popup_result_id = popup.owner
				ui.popup_result_val = it.value
			}
			popup_close()
			if cmd != .None {
				run_cmd(cmd)
			}
			return
		}
		cy += POPUP_ITEM_H
	}
	if (ui.pressed[0] || ui.pressed[1]) && !in_rect(box, ui.mx, ui.my) {
		// Clicking the menubar title is handled by the menubar itself.
		if !(popup.menu_idx >= 0 && in_rect(popup.anchor, ui.mx, ui.my)) {
			popup_close()
		}
	}
	if rl.IsKeyPressed(.ESCAPE) {
		popup_close()
	}
}

// Drop-down selector. Returns the newly picked index (one frame after the click).
combo :: proc(r: Rect, items: []string, cur: int, tip := "") -> (new_val: int, changed: bool) {
	id := make_id(r, "combo")
	clicked, held, hover := button_behavior(id, r, tip)
	bg := C_PANEL_LT
	if hover {
		bg = C_HOVER
	}
	if held {
		bg = C_ACTIVE
	}
	fill_rect(r, bg)
	outline_rect(r, C_BORDER)
	s := cur >= 0 && cur < len(items) ? items[cur] : ""
	text_clipped(Rect{r.x + 4, r.y, r.w - 18, r.h}, s, C_TEXT)
	icon(.Down, r.x + r.w - 14, r.y + (r.h - ICON_SIZE) / 2, C_TEXT_DIM)
	if ui.popup_result_id == id {
		new_val = ui.popup_result_val
		changed = true
		ui.popup_result_id = 0
	}
	if clicked {
		popup_begin(id, r, r.w)
		for it, i in items {
			popup_item(it, i, checked = i == cur)
		}
	}
	return
}

combo_enum :: proc(r: Rect, names: [$E]string, v: ^E, tip := "") -> bool {
	items: [len(E)]string
	for n, i in names {
		items[i] = n
	}
	nv, ch := combo(r, items[:], int(v^), tip)
	if ch {
		v^ = E(nv)
	}
	return ch
}

// Tooltip overlay --------------------------------------------------------------

tooltip_draw :: proc() {
	if ui.tip == "" || popup.open {
		return
	}
	tw := text_w(ui.tip)
	w := tw + 8
	h: i32 = 14
	x := ui.mx + 10
	y := ui.my + 14
	if x + w > i32(ui.w) {
		x = i32(ui.w) - w
	}
	if y + h > i32(ui.h) {
		y = ui.my - h - 4
	}
	fill_rect(Rect{x, y, w, h}, Color{20, 20, 26, 245})
	outline_rect(Rect{x, y, w, h}, C_ACCENT)
	text(x + 4, y + 3, ui.tip, C_TEXT)
}
