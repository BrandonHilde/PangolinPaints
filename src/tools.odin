package pangolin

import "core:math"
import "core:slice"

canvas_vp: Rect

hover_pt: Vec2 // canvas position under the mouse (continuous)
hover_valid: bool // mouse is over the canvas viewport

Grad_Kind :: enum u8 {
	Linear,
	Radial,
	Reflected,
	Diamond,
}

GRAD_NAMES := [Grad_Kind]string {
	.Linear    = "Linear",
	.Radial    = "Radial",
	.Reflected = "Reflected",
	.Diamond   = "Diamond",
}

// Options for the non-brush tools.
Tool_Opts :: struct {
	tolerance:     int,
	contiguous:    bool,
	sample_merged: bool,
	antialias:     bool,
	fill_opacity:  int,
	grad_kind:     Grad_Kind,
	grad_to_clear: bool, // foreground to transparent instead of foreground to background
	grad_reverse:  bool,
	pick_size:     int, // eyedropper average: 1, 3, 5, 11
	sel_mode:      Sel_Mode,
	feather:       int,
}

topts := Tool_Opts {
	tolerance    = 32,
	contiguous   = true,
	antialias    = true,
	fill_opacity = 100,
	pick_size    = 1,
}

Drag :: struct {
	active:     bool,
	btn:        int,
	tool:       Tool,
	start:      Vec2,
	cur:        Vec2,
	sel_base:   []u8,
	sel_moving: bool,
	sel_mode:   Sel_Mode,
	lasso:      [dynamic]Vec2,
	orig:       []Color, // flat copy of the target (gradient / move)
	orig_sel:   ^Mask,
	moved:      bool,
	text_move:  bool, // the Move tool is dragging a text layer by its position
	text_start: Vec2,
	shape0:     ^Shape, // the Move tool is dragging a vector layer: its outlines before the move
	pan_active: bool,
}

drag: Drag

last_stroke_end: Vec2
have_last_stroke: bool

// Tool in effect right now, considering temporary overrides (Space = hand, Alt = picker).
eff_tool :: proc() -> Tool {
	if drag.active {
		return drag.tool
	}
	if IsKeyDown(.SPACE) && ui.focus_id == 0 && dialog.kind == .None && !text_edit.active {
		return .Hand
	}
	if pen_eraser_active() {
		if t, ok := pen_eraser_group_tool(); ok {
			return t
		}
	}
	if pen_eraser_active() && (cur_tool == .Brush || cur_tool == .Oil) {
		return .Eraser // the eraser end of the pen
	}
	if ui.alt && (paint_tool(cur_tool) || cur_tool == .Bucket || cur_tool == .Gradient) && cur_tool != .Clone && cur_tool != .Eraser {
		return .Picker
	}
	return cur_tool
}

screen_to_canvas :: proc(sx, sy: f32) -> Vec2 {
	return Vec2{(sx - doc.ox) / doc.zoom, (sy - doc.oy) / doc.zoom}
}

canvas_to_screen :: proc(p: Vec2) -> Vec2 {
	return Vec2{doc.ox + p.x * doc.zoom, doc.oy + p.y * doc.zoom}
}

pt_in_doc :: proc(p: Vec2) -> bool {
	return p.x >= 0 && p.y >= 0 && p.x < f32(doc.w) && p.y < f32(doc.h)
}

// Seamless mode: a point on any of the surrounding tiles is the same point on the canvas.
wrap_pt :: proc(p: Vec2) -> Vec2 {
	if !seamless_mode {
		return p
	}
	w, h := f32(doc.w), f32(doc.h)
	return Vec2{p.x - math.floor(p.x / w) * w, p.y - math.floor(p.y / h) * h}
}

wrap_i :: #force_inline proc(v, n: int) -> int {
	return ((v % n) + n) % n
}

ipt :: proc(p: Vec2) -> IVec {
	return IVec{int(math.floor(p.x)), int(math.floor(p.y))}
}

// Average colour around p from the composite (or the active layer).
sample_color :: proc(p: Vec2, merged: bool) -> (c: Color, ok: bool) {
	d := doc
	q := ipt(wrap_pt(p))
	if q.x < 0 || q.y < 0 || q.x >= d.w || q.y >= d.h {
		return
	}
	doc_refresh_comp(d)
	r := topts.pick_size / 2
	acc: [4]f32
	n: f32
	g, empty, _ := doc_target(d)
	for y in max(q.y - r, 0) ..= min(q.y + r, d.h - 1) {
		for x in max(q.x - r, 0) ..= min(q.x + r, d.w - 1) {
			px := merged ? d.comp[y * d.w + x] : tiles_get(g, x, y, empty)
			a := f32(px.a)
			acc += [4]f32{f32(px.r) * a, f32(px.g) * a, f32(px.b) * a, a}
			n += 1
		}
	}
	if acc[3] <= 0 {
		return Color{0, 0, 0, 0}, true
	}
	return Color{u8(acc[0] / acc[3] + 0.5), u8(acc[1] / acc[3] + 0.5), u8(acc[2] / acc[3] + 0.5), 255}, true
}

pick_color :: proc(p: Vec2, btn: int) {
	c, ok := sample_color(p, true)
	if !ok || c.a == 0 {
		return
	}
	if btn == 0 {
		set_fg(c)
	} else {
		bg = c
	}
}

sel_mode_now :: proc() -> Sel_Mode {
	if ui.shift && ui.alt {
		return .Intersect
	}
	if ui.shift {
		return .Add
	}
	if ui.alt {
		return .Subtract
	}
	return topts.sel_mode
}

begin_drag :: proc(btn: int, p: Vec2) {
	t := eff_tool()
	d := doc
	drag.active = true
	drag.btn = btn
	drag.tool = t
	drag.start, drag.cur = p, p
	drag.sel_moving = false
	drag.moved = false
	main_col := btn == 0 ? fg : bg
	p := p
	if t == .Bucket || t == .Wand || t == .Text {
		// point tools act on the canvas copy of whatever tile was clicked
		p = wrap_pt(p)
	}
	switch t {
	case .Brush, .Oil, .Smudge, .Eraser, .Blur, .Dodge, .Clone:
		if t == .Clone && ui.alt {
			clone_src_pt = p
			clone_src_set = true
			clone_realign = true
			set_status("Clone source set")
			drag.active = false
			return
		}
		if ui.shift && have_last_stroke {
			// straight line from the end of the previous stroke
			if stroke_begin(t, last_stroke_end, main_col) {
				append(&stroke.pts, p)
				stroke_flush(true)
				stroke_end()
				last_stroke_end = p
			}
			drag.active = false
			return
		}
		if !stroke_begin(t, p, main_col) {
			drag.active = false
		}
	case .Line:
		line_mouse_down(btn, p)
	case .Bucket:
		drag.active = false
		if pt_in_doc(p) && can_edit() {
			bucket_fill(p, main_col)
		}
	case .Gradient:
		if !can_edit() {
			drag.active = false
			return
		}
		history_push(d)
		g, empty, _ := doc_target(d)
		drag.orig = make([]Color, d.w * d.h)
		tiles_to_buf(g, d.w, d.h, drag.orig, empty)
	case .Text:
		drag.active = false
		if pt_in_doc(p) || text_edit.active {
			text_click(p)
			// dragging inside the text being edited selects
			drag.active = text_edit_layer() != nil && !ui.dbl_click
		}
	case .Picker:
		pick_color(p, btn)
	case .Select_Rect, .Select_Ellipse, .Lasso:
		drag.sel_mode = sel_mode_now()
		drag.sel_base = d.sel != nil ? slice.clone(d.sel.v) : nil
		history_push(d)
		wp := wrap_pt(p)
		q := ipt(wp)
		if drag.sel_mode == .Replace && d.sel != nil && pt_in_doc(wp) && d.sel.v[q.y * d.w + q.x] >= 128 {
			drag.sel_moving = true
		}
		clear(&drag.lasso)
		append(&drag.lasso, p)
	case .Wand:
		drag.active = false
		if !pt_in_doc(p) {
			return
		}
		q := ipt(p)
		src: []Color
		if topts.sample_merged {
			doc_refresh_comp(d)
			src = d.comp
		} else {
			src = layer_flat(d, &d.layers[d.active_layer])
		}
		shape := region_select(src, d.w, d.h, q.x, q.y, topts.tolerance, topts.contiguous, topts.antialias)
		mode := sel_mode_now()
		nm := sel_combine(d.sel != nil ? d.sel.v : nil, shape, mode)
		delete(shape)
		history_push(d)
		doc_sel_set(d, nm)
	case .Move:
		if tl := &d.layers[d.active_layer]; tl.text.on && d.sel == nil && !tl.locked && tl.visible {
			// text layers move by their position, so they stay editable
			history_push(d)
			drag.text_move = true
			drag.text_start = {tl.text.x, tl.text.y}
			return
		}
		if tl := &d.layers[d.active_layer]; tl.shape != nil && d.sel == nil && !d.edit_mask && !tl.locked && tl.visible {
			// vector layers move their outlines
			history_push(d)
			drag.shape0 = shape_share(tl.shape)
			return
		}
		if !can_edit() {
			drag.active = false
			return
		}
		history_push(d)
		g, empty, _ := doc_target(d)
		drag.orig = make([]Color, d.w * d.h)
		tiles_to_buf(g, d.w, d.h, drag.orig, empty)
		drag.orig_sel = mask_share(d.sel)
	case .Transform:
		drag.active = false
		xform_mouse_down(p)
		if xform.grab != .None {
			drag.active = true
		}
	case .Crop:
		crop_mouse_down(p)
	case .Hand:
		drag.active = false
	case .Zoom:
		drag.active = false
		zoom_at(d.zoom * (btn == 0 ? 2 : 0.5), f32(ui.mx), f32(ui.my))
	}
}

update_drag :: proc(p: Vec2) {
	d := doc
	drag.cur = p
	if p != drag.start {
		drag.moved = true
	}
	switch drag.tool {
	case .Brush, .Oil, .Smudge, .Eraser, .Blur, .Dodge, .Clone:
		stroke_move(p)
	case .Gradient:
		gradient_render(drag.start, p)
	case .Picker:
		pick_color(p, drag.btn)
	case .Select_Rect, .Select_Ellipse, .Lasso:
		w, h := d.w, d.h
		if drag.sel_moving {
			dx := int(math.round(p.x - drag.start.x))
			dy := int(math.round(p.y - drag.start.y))
			nm := make([]u8, w * h)
			for y in 0 ..< h {
				sy := y - dy
				if seamless_mode do sy = wrap_i(sy, h)
				if sy < 0 || sy >= h do continue
				for x in 0 ..< w {
					sx := x - dx
					if seamless_mode do sx = wrap_i(sx, w)
					if sx < 0 || sx >= w do continue
					nm[y * w + x] = drag.sel_base[sy * w + sx]
				}
			}
			doc_sel_set(d, nm)
			return
		}
		a, b := drag.start, p
		if drag.tool != .Lasso && ui.shift && drag.sel_mode != .Add {
			// square / circle
			dx, dy := b.x - a.x, b.y - a.y
			m := max(abs(dx), abs(dy))
			b = Vec2{a.x + math.sign(dx) * m, a.y + math.sign(dy) * m}
		}
		if drag.tool != .Lasso && ui.ctrl {
			a = drag.start * 2 - b
		}
		// snap rectangle corners to whole pixels for crisp edges
		if drag.tool == .Lasso {
			lp := drag.lasso[len(drag.lasso) - 1]
			if vlen(p - lp) * d.zoom >= 2 {
				append(&drag.lasso, p)
			}
		}
		// seamless: the shape is also drawn on the 8 neighbouring tiles, so it wraps round the edges
		shape: []u8
		span := seamless_mode ? 1 : 0
		for oy in -span ..= span {
			for ox in -span ..= span {
				off := Vec2{f32(ox * w), f32(oy * h)}
				s: []u8
				#partial switch drag.tool {
				case .Select_Rect:
					s = sel_rect(w, h, Vec2{math.round(a.x), math.round(a.y)} + off, Vec2{math.round(b.x), math.round(b.y)} + off)
				case .Select_Ellipse:
					s = sel_ellipse(w, h, a + off, b + off)
				case .Lasso:
					pts := make([]Vec2, len(drag.lasso), context.temp_allocator)
					for lp, i in drag.lasso do pts[i] = lp + off
					s = sel_polygon(w, h, pts)
				}
				if shape == nil {
					shape = s
				} else {
					for v, i in s do shape[i] = max(shape[i], v)
					delete(s)
				}
			}
		}
		if topts.feather > 0 {
			mask_blur(shape, w, h, f32(topts.feather))
		}
		nm := sel_combine(drag.sel_base, shape, drag.sel_mode)
		delete(shape)
		doc_sel_set(d, nm)
	case .Move:
		if drag.text_move {
			tl := &d.layers[d.active_layer]
			tl.text.x = drag.text_start.x + math.round(p.x - drag.start.x)
			tl.text.y = drag.text_start.y + math.round(p.y - drag.start.y)
			text_render_layer(d, d.active_layer)
			return
		}
		if drag.shape0 != nil {
			shape_move_to(d, drag.shape0, math.round(p.x - drag.start.x), math.round(p.y - drag.start.y))
			return
		}
		move_render(int(math.round(p.x - drag.start.x)), int(math.round(p.y - drag.start.y)))
	case .Transform:
		xform_mouse_drag(p)
	case .Crop:
		crop_mouse_drag(p)
	case .Text:
		if drag.moved do text_drag(p)
	case .Bucket, .Wand, .Hand, .Zoom, .Line:
	}
}

end_drag :: proc() {
	d := doc
	switch drag.tool {
	case .Brush, .Oil, .Smudge, .Eraser, .Blur, .Dodge, .Clone:
		stroke_end()
		last_stroke_end = drag.cur
		have_last_stroke = true
	case .Gradient:
		if !drag.moved {
			history_revert(d)
		}
		delete(drag.orig)
		drag.orig = nil
		d.thumb_dirty = true
	case .Select_Rect, .Select_Ellipse, .Lasso:
		if !drag.moved && drag.sel_mode == .Replace && !drag.sel_moving {
			doc_sel_clear(d)
		}
		cur := d.sel != nil ? d.sel.v : nil
		if slice.equal(drag.sel_base, cur) {
			history_discard(d)
		}
		if drag.sel_base != nil {
			delete(drag.sel_base)
			drag.sel_base = nil
		}
	case .Move:
		if drag.text_move {
			if !drag.moved {
				history_discard(d)
			}
			drag.text_move = false
			d.thumb_dirty = true
			break
		}
		if drag.shape0 != nil {
			if !drag.moved {
				history_discard(d)
			}
			shape_release(drag.shape0)
			drag.shape0 = nil
			d.thumb_dirty = true
			break
		}
		if !drag.moved {
			history_discard(d)
		}
		delete(drag.orig)
		drag.orig = nil
		mask_release(drag.orig_sel)
		drag.orig_sel = nil
		d.thumb_dirty = true
	case .Transform:
		xform.grab = .None
	case .Crop:
		crop_mouse_up()
	case .Line:
		line_mouse_up(drag.cur)
	case .Picker, .Text, .Bucket, .Wand, .Hand, .Zoom:
	}
	drag.active = false
}

// Called every frame with the viewport rectangle. Handles pan, zoom and tool input.
canvas_update :: proc(vp: Rect) {
	canvas_vp = vp
	d := doc
	if !d.view_init {
		view_fit(d)
	}
	over := ui.layer == ui.input_layer && in_rect(vp, ui.mx, ui.my)
	mx := ui.ptr.x / f32(ui.scale)
	my := ui.ptr.y / f32(ui.scale)
	p := screen_to_canvas(mx, my)
	if tool_snaps(drag.active ? drag.tool : eff_tool()) {
		p = snap_pt(p)
	}
	hover_pt = p
	hover_valid = over

	if over && ui.wheel != 0 && ui.focus_id == 0 && !drag.active {
		if ui.shift {
			d.ox += ui.wheel * 30
		} else if ui.ctrl {
			d.oy += ui.wheel * 30
		} else {
			zoom_at(d.zoom * math.pow(f32(1.25), ui.wheel), mx, my)
		}
	}
	if over && ui.wheel_h != 0 {
		d.ox += ui.wheel_h * 30
	}

	t := eff_tool()
	if !drag.pan_active && over && !drag.active && (ui.pressed[2] || (t == .Hand && ui.pressed[0])) {
		drag.pan_active = true
	}
	if drag.pan_active {
		d.ox += gfx.mouse_delta.x / f32(ui.scale)
		d.oy += gfx.mouse_delta.y / f32(ui.scale)
		ui.cursor = .RESIZE_ALL
		if !ui.down[2] && !(t == .Hand && ui.down[0]) {
			drag.pan_active = false
		}
		return
	}

	// paint tools show the brush outline only (a small brush still gets a minimum-size ring)
	if paint_tool(t) && (over || drag.active) && ui.focus_id == 0 {
		ui.hide_cursor = true
	}

	if over && !drag.active {
		switch t {
		case .Hand:
			ui.cursor = .RESIZE_ALL
		case .Zoom:
			ui.cursor = .POINTING_HAND
		case .Brush, .Oil, .Smudge, .Eraser, .Blur, .Dodge, .Clone, .Line:
			// the brush outline is drawn instead (see render_cursor)
			ui.cursor = .DEFAULT
		case .Transform:
			ui.cursor = xform_cursor(p)
		case .Move:
			ui.cursor = .RESIZE_ALL
		case .Text:
			ui.cursor = .IBEAM
		case .Bucket, .Gradient, .Picker, .Select_Rect, .Select_Ellipse, .Lasso, .Wand, .Crop:
			ui.cursor = .CROSSHAIR
		}
		if ui.pressed[0] || ui.pressed[1] {
			begin_drag(ui.pressed[0] ? 0 : 1, p)
		}
	} else if drag.active {
		btn_down := ui.down[drag.btn]
		update_drag(p)
		if !btn_down || ui.released[drag.btn] {
			end_drag()
		}
	}
}

// ---------------------------------------------------------------------------
// View
// ---------------------------------------------------------------------------

ZOOM_MIN :: 0.02
ZOOM_MAX :: 64

// Zoom keeping the canvas point under (sx, sy) fixed.
zoom_at :: proc(nz: f32, sx, sy: f32) {
	z := clamp(nz, ZOOM_MIN, ZOOM_MAX)
	// settle on round numbers near 100% steps
	for s in ([?]f32{0.25, 0.5, 1, 2, 4, 8, 16}) {
		if abs(z - s) / s < 0.06 {
			z = s
		}
	}
	cx := (sx - doc.ox) / doc.zoom
	cy := (sy - doc.oy) / doc.zoom
	doc.zoom = z
	doc.ox = sx - cx * z
	doc.oy = sy - cy * z
}

zoom_center :: proc(nz: f32) {
	vp := canvas_vp
	zoom_at(nz, f32(vp.x) + f32(vp.w) / 2, f32(vp.y) + f32(vp.h) / 2)
}

view_fit :: proc(d: ^Doc) {
	vp := canvas_vp
	if vp.w <= 0 || vp.h <= 0 {
		return
	}
	zx := f32(vp.w - 40) / f32(d.w)
	zy := f32(vp.h - 40) / f32(d.h)
	z := clamp(min(zx, zy), ZOOM_MIN, ZOOM_MAX)
	if z > 1 {
		z = f32(int(z))
	}
	d.zoom = z
	d.ox = math.floor(f32(vp.x) + (f32(vp.w) - f32(d.w) * z) / 2)
	d.oy = math.floor(f32(vp.y) + (f32(vp.h) - f32(d.h) * z) / 2)
	d.view_init = true
}

// ---------------------------------------------------------------------------
// Paint bucket
// ---------------------------------------------------------------------------

bucket_fill :: proc(p: Vec2, col: Color) {
	d := doc
	q := ipt(p)
	g, empty, is_mask := doc_target(d)
	cur := make([]Color, d.w * d.h, context.temp_allocator)
	tiles_to_buf(g, d.w, d.h, cur, empty)
	src := cur
	if topts.sample_merged {
		doc_refresh_comp(d)
		src = d.comp
	}
	region := region_select(src, d.w, d.h, q.x, q.y, topts.tolerance, topts.contiguous, topts.antialias)
	defer delete(region)
	c := col
	if is_mask {
		v := luma(col)
		c = Color{v, v, v, 255}
	}
	lock := !is_mask && d.layers[d.active_layer].lock_alpha
	op := f32(topts.fill_opacity) / 100
	history_push(d)
	changed := false
	for i in 0 ..< len(cur) {
		if region[i] == 0 do continue
		a := f32(region[i]) / 255 * op * f32(sel_at(d, i)) / 255
		if a <= 0 do continue
		cur[i] = lock ? lock_mix(cur[i], c, a) : over_px(cur[i], c, a)
		changed = true
	}
	if !changed {
		history_discard(d)
		return
	}
	tiles_from_buf(g, d.w, d.h, cur, empty)
	doc_touch_all(d)
}

// ---------------------------------------------------------------------------
// Gradient
// ---------------------------------------------------------------------------

gradient_render :: proc(a, b: Vec2) {
	d := doc
	g, empty, is_mask := doc_target(d)
	c0, c1 := fg, bg
	if topts.grad_to_clear {
		c1 = Color{fg.r, fg.g, fg.b, 0}
	}
	if is_mask {
		v0, v1 := luma(c0), luma(c1)
		c0 = Color{v0, v0, v0, 255}
		c1 = Color{v1, v1, v1, topts.grad_to_clear ? 0 : 255}
	}
	if topts.grad_reverse {
		c0, c1 = c1, c0
	}
	lock := !is_mask && d.layers[d.active_layer].lock_alpha
	op := f32(topts.fill_opacity) / 100
	dir := b - a
	ln := max(vlen(dir), 0.5)
	n := dir / ln
	box := doc_edit_box(d)
	bw := box.x1 - box.x0
	out := make([]Color, bw * (box.y1 - box.y0), context.temp_allocator)
	seed: u64 = 77
	for y in box.y0 ..< box.y1 {
		for x in box.x0 ..< box.x1 {
			i := y * d.w + x
			o := drag.orig[i]
			sa := f32(sel_at(d, i)) / 255 * op
			if sa <= 0 {
				out[(y - box.y0) * bw + x - box.x0] = o
				continue
			}
			v := Vec2{f32(x) + 0.5, f32(y) + 0.5} - a
			t: f32
			switch topts.grad_kind {
			case .Linear:
				t = (v.x * n.x + v.y * n.y) / ln
			case .Radial:
				t = vlen(v) / ln
			case .Reflected:
				t = abs(v.x * n.x + v.y * n.y) / ln
			case .Diamond:
				t = (abs(v.x * n.x + v.y * n.y) + abs(-v.x * n.y + v.y * n.x)) / ln
			}
			// a little noise hides 8-bit banding
			t = clamp(t + (rand_f(&seed) - 0.5) / 255, 0, 1)
			gc := mix_px(c0, c1, t)
			res := lock ? lock_mix(o, gc, sa * f32(gc.a) / 255) : over_px(o, gc, sa * f32(gc.a) / 255)
			out[(y - box.y0) * bw + x - box.x0] = res
		}
	}
	tiles_write_box(g, box, out, empty)
	doc_touch(d, box)
}

// ---------------------------------------------------------------------------
// Move tool: drags the selected pixels (or the whole layer)
// ---------------------------------------------------------------------------

move_render :: proc(dx, dy: int) {
	d := doc
	g, empty, _ := doc_target(d)
	w, h := d.w, d.h
	out := make([]Color, w * h, context.temp_allocator)
	sel := drag.orig_sel
	copy_mode := ui.alt
	if sel == nil {
		for &p in out do p = empty
		for y in 0 ..< h {
			sy := y - dy
			if seamless_mode do sy = wrap_i(sy, h)
			if sy < 0 || sy >= h do continue
			for x in 0 ..< w {
				sx := x - dx
				if seamless_mode do sx = wrap_i(sx, w)
				if sx < 0 || sx >= w do continue
				out[y * w + x] = drag.orig[sy * w + sx]
			}
		}
		tiles_from_buf(g, w, h, out, empty)
		doc_touch_all(d)
		return
	}
	// cut the selection out, then lay the moved pixels on top
	for i in 0 ..< w * h {
		o := drag.orig[i]
		s := sel.v[i]
		if s != 0 && !copy_mode {
			if empty.a == 0 {
				o.a = u8(int(o.a) * (255 - int(s)) / 255)
			} else {
				o = mix_px(o, empty, f32(s) / 255)
			}
		}
		out[i] = o
	}
	b := sel.bbox
	for y in b.y0 ..< b.y1 {
		ny := y + dy
		if seamless_mode do ny = wrap_i(ny, h)
		if ny < 0 || ny >= h do continue
		for x in b.x0 ..< b.x1 {
			nx := x + dx
			if seamless_mode do nx = wrap_i(nx, w)
			if nx < 0 || nx >= w do continue
			s := sel.v[y * w + x]
			if s == 0 do continue
			src := drag.orig[y * w + x]
			out[ny * w + nx] = over_px(out[ny * w + nx], src, f32(src.a) / 255 * f32(s) / 255)
		}
	}
	affected := box_union(b, Box{b.x0 + dx, b.y0 + dy, b.x1 + dx, b.y1 + dy})
	affected = box_union(affected, d.sel != nil ? d.sel.bbox : Box{})
	if seamless_mode {
		affected = doc_box(d) // moved pixels can reappear on the opposite side
	}
	affected = box_clip(affected, w, h)
	if !box_empty(affected) {
		sub := make([]Color, (affected.x1 - affected.x0) * (affected.y1 - affected.y0), context.temp_allocator)
		aw := affected.x1 - affected.x0
		for y in affected.y0 ..< affected.y1 {
			copy(sub[(y - affected.y0) * aw:][:aw], out[y * w + affected.x0:][:aw])
		}
		tiles_write_box(g, affected, sub, empty)
		doc_touch(d, affected)
	}
	// the selection travels with the pixels
	nm := make([]u8, w * h)
	for y in 0 ..< h {
		sy := y - dy
		if seamless_mode do sy = wrap_i(sy, h)
		if sy < 0 || sy >= h do continue
		for x in 0 ..< w {
			sx := x - dx
			if seamless_mode do sx = wrap_i(sx, w)
			if sx < 0 || sx >= w do continue
			nm[y * w + x] = sel.v[sy * w + sx]
		}
	}
	doc_sel_set(d, nm)
}

move_nudge :: proc(dx, dy: int) {
	d := doc
	if l := &d.layers[d.active_layer]; l.shape != nil && d.sel == nil && !d.edit_mask && !l.locked && l.visible {
		history_push(d)
		s := shape_share(l.shape)
		shape_move_to(d, s, f32(dx), f32(dy))
		shape_release(s)
		d.thumb_dirty = true
		return
	}
	if !can_edit() {
		return
	}
	history_push(d)
	g, empty, _ := doc_target(d)
	drag.orig = make([]Color, d.w * d.h)
	tiles_to_buf(g, d.w, d.h, drag.orig, empty)
	drag.orig_sel = mask_share(d.sel)
	move_render(dx, dy)
	delete(drag.orig)
	drag.orig = nil
	mask_release(drag.orig_sel)
	drag.orig_sel = nil
	d.thumb_dirty = true
}

// ---------------------------------------------------------------------------
// Free transform: scale / rotate / move the selection or the whole layer.
// Drag a corner to scale (Shift: free aspect), an edge to stretch, outside the box
// to rotate (Shift: 15 degree steps), inside to move. Enter applies, Esc cancels.
// ---------------------------------------------------------------------------

Xform_Grab :: enum {
	None,
	Move,
	Rotate,
	Corner, // index in `handle`
	Edge,
}

Xform :: struct {
	active:   bool,
	src:      []Color, // floating pixels (bw x bh)
	sw, sh:   int,
	base:     []Color, // target with the floating pixels removed (w*h)
	empty:    Color,
	// transform: floating image centre at (cx, cy), scaled then rotated
	cx, cy:   f32,
	sx, sy:   f32,
	angle:    f32,
	grab:     Xform_Grab,
	handle:   int,
	g_start:  Vec2,
	g_cx, g_cy, g_sx, g_sy, g_angle: f32,
	last_box: Box,
	// vector layers: the outlines are transformed instead of the pixels
	shape0:   ^Shape,
	c0x, c0y: f32, // centre of the box at the start
}

xform: Xform

xform_begin :: proc() -> bool {
	d := doc
	if xform.active {
		return true
	}
	l := &d.layers[d.active_layer]
	vector := l.shape != nil && d.sel == nil && !d.edit_mask
	if vector {
		if l.locked || !l.visible {
			set_status(l.locked ? "Layer is locked" : "Layer is hidden")
			return false
		}
	} else if !can_edit() {
		return false
	}
	g, empty, _ := doc_target(d)
	full := make([]Color, d.w * d.h)
	defer delete(full)
	tiles_to_buf(g, d.w, d.h, full, empty)
	b: Box
	ok: bool
	if d.sel != nil {
		b, ok = d.sel.bbox, true
	} else {
		b, ok = tiles_bounds(g, d.w, d.h, empty)
	}
	if !ok {
		set_status("Nothing to transform")
		return false
	}
	history_push(d)
	xf := &xform
	xf.active = true
	xf.empty = empty
	xf.sw, xf.sh = b.x1 - b.x0, b.y1 - b.y0
	xf.src = make([]Color, xf.sw * xf.sh)
	xf.base = make([]Color, d.w * d.h)
	copy(xf.base, full)
	for y in b.y0 ..< b.y1 {
		for x in b.x0 ..< b.x1 {
			i := y * d.w + x
			s := sel_at(d, i)
			p := full[i]
			if empty.a != 0 {
				// masks: the floating part carries its coverage in alpha
				p = Color{p.r, p.g, p.b, s}
			} else {
				p.a = u8(int(p.a) * int(s) / 255)
			}
			xf.src[(y - b.y0) * xf.sw + x - b.x0] = p
			if s != 0 {
				if empty.a == 0 {
					xf.base[i].a = u8(int(full[i].a) * (255 - int(s)) / 255)
				} else {
					xf.base[i] = mix_px(full[i], empty, f32(s) / 255)
				}
			}
		}
	}
	xf.cx = f32(b.x0) + f32(xf.sw) / 2
	xf.cy = f32(b.y0) + f32(xf.sh) / 2
	xf.c0x, xf.c0y = xf.cx, xf.cy
	if vector {
		xf.shape0 = shape_share(l.shape)
	}
	xf.sx, xf.sy, xf.angle = 1, 1, 0
	xf.grab = .None
	xf.last_box = b
	doc_sel_clear(d)
	return true
}

// Corners of the transformed box in canvas space: tl, tr, br, bl.
xform_corners :: proc() -> [4]Vec2 {
	xf := &xform
	hw, hh := f32(xf.sw) / 2 * xf.sx, f32(xf.sh) / 2 * xf.sy
	ca, sa := math.cos(xf.angle), math.sin(xf.angle)
	loc := [4]Vec2{{-hw, -hh}, {hw, -hh}, {hw, hh}, {-hw, hh}}
	out: [4]Vec2
	for p, i in loc {
		out[i] = Vec2{xf.cx + p.x * ca - p.y * sa, xf.cy + p.x * sa + p.y * ca}
	}
	return out
}

// Canvas point -> floating image local coordinates (unscaled pixels from its top-left).
xform_to_local :: proc(p: Vec2) -> Vec2 {
	xf := &xform
	ca, sa := math.cos(xf.angle), math.sin(xf.angle)
	dx, dy := p.x - xf.cx, p.y - xf.cy
	u := (dx * ca + dy * sa) / xf.sx
	v := (-dx * sa + dy * ca) / xf.sy
	return Vec2{u + f32(xf.sw) / 2, v + f32(xf.sh) / 2}
}

xform_render :: proc() {
	d := doc
	xf := &xform
	if xf.shape0 != nil {
		// scale, then rotate, about the box centre, then move it to (cx, cy)
		ca, sa := math.cos(xf.angle), math.sin(xf.angle)
		m := Affine{ca * xf.sx, -sa * xf.sy, sa * xf.sx, ca * xf.sy, 0, 0}
		m.e = xf.cx - m.a * xf.c0x - m.b * xf.c0y
		m.f = xf.cy - m.c * xf.c0x - m.d * xf.c0y
		l := &d.layers[d.active_layer]
		ns := shape_transformed(xf.shape0, m)
		shape_release(l.shape)
		l.shape = ns
		shape_render_layer(d, d.active_layer)
		return
	}
	g, empty, _ := doc_target(d)
	cs := xform_corners()
	b := Box{d.w, d.h, 0, 0}
	for c in cs {
		b.x0 = min(b.x0, int(math.floor(c.x)) - 1)
		b.y0 = min(b.y0, int(math.floor(c.y)) - 1)
		b.x1 = max(b.x1, int(math.ceil(c.x)) + 1)
		b.y1 = max(b.y1, int(math.ceil(c.y)) + 1)
	}
	b = box_clip(b, d.w, d.h)
	redo := box_clip(box_union(b, xf.last_box), d.w, d.h)
	xf.last_box = b
	if box_empty(redo) {
		return
	}
	rw := redo.x1 - redo.x0
	out := make([]Color, rw * (redo.y1 - redo.y0), context.temp_allocator)
	for y in redo.y0 ..< redo.y1 {
		for x in redo.x0 ..< redo.x1 {
			o := xf.base[y * d.w + x]
			if x >= b.x0 && x < b.x1 && y >= b.y0 && y < b.y1 {
				l := xform_to_local(Vec2{f32(x) + 0.5, f32(y) + 0.5})
				s := sample_bilinear(xf.src, xf.sw, xf.sh, l.x - 0.5, l.y - 0.5, Color{})
				if s.a != 0 {
					if empty.a != 0 {
						o = mix_px(o, Color{s.r, s.g, s.b, 255}, f32(s.a) / 255)
					} else {
						o = over_px(o, s, f32(s.a) / 255)
					}
				}
			}
			out[(y - redo.y0) * rw + x - redo.x0] = o
		}
	}
	tiles_write_box(g, redo, out, empty)
	doc_touch(d, redo)
}

xform_commit :: proc() {
	if !xform.active {
		return
	}
	xform_render()
	xform_free()
	doc.thumb_dirty = true
	set_status("Transform applied")
}

xform_cancel :: proc() {
	if !xform.active {
		return
	}
	xform_free()
	history_revert(doc)
	set_status("Transform cancelled")
}

xform_free :: proc() {
	delete(xform.src)
	delete(xform.base)
	shape_release(xform.shape0)
	xform = {}
}

// Hit test in screen space so handles stay grabbable at any zoom.
xform_hit :: proc(p: Vec2) -> (grab: Xform_Grab, handle: int) {
	cs := xform_corners()
	sp := canvas_to_screen(p)
	for c, i in cs {
		if vlen(canvas_to_screen(c) - sp) <= 6 {
			return .Corner, i
		}
	}
	for i in 0 ..< 4 {
		m := (cs[i] + cs[(i + 1) % 4]) * 0.5
		if vlen(canvas_to_screen(m) - sp) <= 6 {
			return .Edge, i
		}
	}
	l := xform_to_local(p)
	if l.x >= 0 && l.y >= 0 && l.x <= f32(xform.sw) && l.y <= f32(xform.sh) {
		return .Move, 0
	}
	return .Rotate, 0
}

xform_cursor :: proc(p: Vec2) -> MouseCursor {
	if !xform.active {
		return .RESIZE_ALL
	}
	g, _ := xform_hit(p)
	switch g {
	case .Corner, .Edge:
		return .RESIZE_NESW
	case .Move:
		return .RESIZE_ALL
	case .Rotate, .None:
		return .POINTING_HAND
	}
	return .DEFAULT
}

xform_mouse_down :: proc(p: Vec2) {
	if !xform.active {
		if !xform_begin() {
			return
		}
	}
	if ui.dbl_click {
		xform_commit()
		return
	}
	xf := &xform
	xf.grab, xf.handle = xform_hit(p)
	xf.g_start = p
	xf.g_cx, xf.g_cy, xf.g_sx, xf.g_sy, xf.g_angle = xf.cx, xf.cy, xf.sx, xf.sy, xf.angle
}

xform_mouse_drag :: proc(p: Vec2) {
	xf := &xform
	if !xf.active {
		return
	}
	switch xf.grab {
	case .None:
		return
	case .Move:
		xf.cx = xf.g_cx + p.x - xf.g_start.x
		xf.cy = xf.g_cy + p.y - xf.g_start.y
	case .Rotate:
		a0 := math.atan2(xf.g_start.y - xf.g_cy, xf.g_start.x - xf.g_cx)
		a1 := math.atan2(p.y - xf.g_cy, p.x - xf.g_cx)
		xf.angle = xf.g_angle + a1 - a0
		if ui.shift {
			step := f32(math.PI / 12)
			xf.angle = math.round(xf.angle / step) * step
		}
	case .Corner, .Edge:
		// scale about the opposite side, measured in the box's rotated frame
		ca, sa := math.cos(xf.g_angle), math.sin(xf.g_angle)
		hw, hh := f32(xf.sw) / 2, f32(xf.sh) / 2
		sgn := [4]Vec2{{-1, -1}, {1, -1}, {1, 1}, {-1, 1}}
		esg := [4]Vec2{{0, -1}, {1, 0}, {0, 1}, {-1, 0}}
		hs := xf.grab == .Corner ? sgn[xf.handle] : esg[xf.handle]
		// anchor = opposite point in local (scaled) space
		anchor := Vec2{-hs.x * hw * xf.g_sx, -hs.y * hh * xf.g_sy}
		an_w := Vec2{xf.g_cx + anchor.x * ca - anchor.y * sa, xf.g_cy + anchor.x * sa + anchor.y * ca}
		dv := p - an_w
		lu := dv.x * ca + dv.y * sa
		lv := -dv.x * sa + dv.y * ca
		nsx, nsy := xf.g_sx, xf.g_sy
		if hs.x != 0 do nsx = lu * hs.x / (2 * hw)
		if hs.y != 0 do nsy = lv * hs.y / (2 * hh)
		if xf.grab == .Corner && !ui.shift {
			// keep proportions
			k := max(abs(nsx / xf.g_sx), abs(nsy / xf.g_sy))
			nsx = math.sign(nsx) * k * abs(xf.g_sx)
			nsy = math.sign(nsy) * k * abs(xf.g_sy)
		}
		if abs(nsx) < 0.01 do nsx = 0.01
		if abs(nsy) < 0.01 do nsy = 0.01
		xf.sx, xf.sy = nsx, nsy
		// new centre = anchor + half size towards the handle
		half := Vec2{hs.x * hw * nsx, hs.y * hh * nsy}
		xf.cx = an_w.x + half.x * ca - half.y * sa
		xf.cy = an_w.y + half.x * sa + half.y * ca
	}
	xform_render()
}

// ---------------------------------------------------------------------------
// Crop tool: drag a rectangle, Enter (or double click) crops, Esc cancels.
// ---------------------------------------------------------------------------

Crop :: struct {
	active: bool,
	a, b:   Vec2,
}

crop: Crop

crop_box :: proc() -> Box {
	x0 := int(math.round(min(crop.a.x, crop.b.x)))
	y0 := int(math.round(min(crop.a.y, crop.b.y)))
	x1 := int(math.round(max(crop.a.x, crop.b.x)))
	y1 := int(math.round(max(crop.a.y, crop.b.y)))
	return box_clip(Box{x0, y0, x1, y1}, doc.w, doc.h)
}

crop_mouse_down :: proc(p: Vec2) {
	if crop.active && ui.dbl_click {
		crop_commit()
		drag.active = false
		return
	}
	crop.active = true
	crop.a, crop.b = p, p
}

crop_mouse_drag :: proc(p: Vec2) {
	crop.b = p
	if ui.shift {
		dx, dy := p.x - crop.a.x, p.y - crop.a.y
		m := max(abs(dx), abs(dy))
		crop.b = Vec2{crop.a.x + math.sign(dx) * m, crop.a.y + math.sign(dy) * m}
	}
}

crop_mouse_up :: proc() {
	if box_empty(crop_box()) {
		crop.active = false
	}
}

crop_commit :: proc() {
	if !crop.active {
		return
	}
	b := crop_box()
	crop.active = false
	if doc_crop(doc, b) {
		set_statusf("Cropped to %dx%d", doc.w, doc.h)
	}
}

// Finish any pending tool interaction (switching tools, running commands).
tools_commit_pending :: proc() {
	text_end()
	if !drag.active do line_finish(false)
	if drag.active {
		end_drag()
	}
	xform_commit()
	crop.active = false
}
