package pangolin

import "core:fmt"
import "core:math"
import "core:strconv"
import "core:strings"

// ---------------------------------------------------------------------------
// Smart Select: a magic wand with curves and edge awareness.
//
// A pixel is in the area when its color is within the tolerance of the clicked color (the largest channel
// difference, as with the wand). Three curves shape that:
//   - Tolerance by hue and Tolerance by brightness: the tolerance for a pixel of that hue or brightness. The middle
//     line is the Tolerance setting itself, the top twice it, the bottom none. Grays have no hue, so the hue curve
//     fades out for them.
//   - Falloff: how strongly a pixel is selected by how different it is, from the clicked color (left) to the
//     tolerance (right). Full all the way is a hard edge, as the wand; a curve that drops makes a soft one.
//
// Edge bias looks at where the picture changes sharply (a Sobel edge map):
//   - Stop at edges: the area doesn't spread past an edge, even into similar colors on the other side. Edge pixels
//     join it, so it reaches the edge, but it doesn't go on from them.
//   - Snap to edges: the outline moves, within the snap distance, onto the strongest edge nearby. Pixels well inside
//     and well outside are kept as they are and flood the band between them in order of edge strength (a watershed),
//     so the two meet on the edge. A part thinner than the band keeps its middle, so it can't vanish.
//   - Stop and snap: both, one after the other.
// ---------------------------------------------------------------------------

Smart_Curve :: struct {
	pts: [MACRO_CURVE_MAX]Vec2,
	n:   int,
}

Smart_Curve_Kind :: enum {
	Hue,
	Light,
	Falloff,
}

SMART_CURVE_NAMES := [3]string{"Tolerance by hue", "Tolerance by brightness", "Falloff"}
SMART_CURVE_DEFAULTS := [Smart_Curve_Kind]string {
	.Hue     = "0,128 255,128",
	.Light   = "0,128 255,128",
	.Falloff = "0,255 160,255 255,0",
}

Smart_Edge_Mode :: enum {
	Stop,
	Snap,
	Both,
}

SMART_EDGE_NAMES := [3]string{"Stop at edges", "Snap to edges", "Stop and snap"}

Smart_Opts :: struct {
	tolerance:     int,
	contiguous:    bool,
	sample_merged: bool,
	antialias:     bool,
	curve_on:      [Smart_Curve_Kind]bool,
	curves:        [Smart_Curve_Kind]Smart_Curve, // n < 2: not set yet, the default
	edges:         bool,
	edge_mode:     Smart_Edge_Mode,
	edge_strength: int, // 1..100: how faint an edge still counts
	snap_px:       int, // how far the outline may move when snapping
}

SMART_DEFAULT :: Smart_Opts {
	tolerance     = 40,
	contiguous    = true,
	antialias     = true,
	curve_on      = {.Hue = false, .Light = false, .Falloff = true},
	edge_strength = 50,
	snap_px       = 4,
}

smart := SMART_DEFAULT
smart_preset: Name // the Smart Select preset picked last (presets.odin)

HELP_SMART_TOL :: "How different a color may be from the one clicked and still be selected, as the largest difference in red, green, blue or opacity. The hue and brightness curves raise or lower it for some colors."
HELP_SMART_CURVE :: "Pick which curve to shape. Tolerance by hue: more or less tolerance for some hues. Tolerance by brightness: more or less for dark or light tones. Falloff: how strongly a pixel is selected by how different it is, for a soft edge."
HELP_SMART_ON :: "Use this curve. Off, the curve keeps its shape but changes nothing."
HELP_SMART_EDGES :: "Take sharp changes in the picture into account: stop the area at them, move its outline onto them, or both."
HELP_SMART_EDGE_MODE :: "Stop at edges: don't spread past a sharp change, even into similar colors beyond it. Snap to edges: move the outline onto the strongest edge nearby. Stop and snap: both."
HELP_SMART_EDGE_STRENGTH :: "How faint a change still counts as an edge. Higher stops at, and snaps to, softer edges."
HELP_SMART_SNAP :: "How far, in canvas pixels, the outline may move to reach an edge when snapping."
HELP_SMART_CONTIGUOUS :: "Only select the connected area around the click. Off, every matching color in the picture is selected."
HELP_SMART_ALL_LAYERS :: "Look at all visible layers together, instead of the active layer alone."
HELP_SMART_SMOOTH :: "Soften the hard steps of the outline by a pixel, so fills and effects blend in."

// Sets a curve from its text ("x,y x,y ..."); false if the text isn't a curve.
smart_curve_set :: proc(c: ^Smart_Curve, text: string) -> bool {
	pts, ok := macro_curve_parse(text)
	if !ok do return false
	c.n = len(pts)
	for p, i in pts do c.pts[i] = p
	return true
}

// The points of curve `k` (its default until it is shaped).
smart_curve :: proc(k: Smart_Curve_Kind) -> []Vec2 {
	return smart_curve_of(&smart, k)
}

smart_curve_of :: proc(o: ^Smart_Opts, k: Smart_Curve_Kind) -> []Vec2 {
	c := &o.curves[k]
	if c.n < 2 do smart_curve_set(c, SMART_CURVE_DEFAULTS[k])
	return c.pts[:c.n]
}

// ---------------------------------------------------------------------------
// Presets: the settings as numbers, and the three curves as text ("x,y x,y;x,y ...;...", hue, brightness, falloff)
// ---------------------------------------------------------------------------

smart_preset_vals :: proc(o: ^Smart_Opts) -> (vals: []int, txt: string) {
	b2i :: proc(b: bool) -> int {return b ? 1 : 0}
	v := [?]int {
		o.tolerance, b2i(o.contiguous), b2i(o.sample_merged), b2i(o.antialias), b2i(o.edges), int(o.edge_mode),
		o.edge_strength, o.snap_px, b2i(o.curve_on[.Hue]), b2i(o.curve_on[.Light]), b2i(o.curve_on[.Falloff]),
	}
	vals = make([]int, len(v), context.temp_allocator)
	copy(vals, v[:])
	sb := strings.builder_make(context.temp_allocator)
	for k in Smart_Curve_Kind {
		if k != .Hue do strings.write_byte(&sb, ';')
		strings.write_string(&sb, macro_curve_text(smart_curve_of(o, k)))
	}
	return vals, strings.to_string(sb)
}

smart_preset_apply :: proc(o: ^Smart_Opts, vals: []int, txt: string) {
	at :: proc(v: []int, i: int, old: int) -> int {return i < len(v) ? v[i] : old}
	o.tolerance = clamp(at(vals, 0, o.tolerance), 0, 255)
	o.contiguous = at(vals, 1, int(o.contiguous)) != 0
	o.sample_merged = at(vals, 2, int(o.sample_merged)) != 0
	o.antialias = at(vals, 3, int(o.antialias)) != 0
	o.edges = at(vals, 4, int(o.edges)) != 0
	o.edge_mode = Smart_Edge_Mode(clamp(at(vals, 5, int(o.edge_mode)), 0, len(Smart_Edge_Mode) - 1))
	o.edge_strength = clamp(at(vals, 6, o.edge_strength), 1, 100)
	o.snap_px = clamp(at(vals, 7, o.snap_px), 1, 32)
	for k, i in Smart_Curve_Kind do o.curve_on[k] = at(vals, 8 + int(i), int(o.curve_on[k])) != 0
	for part, i in strings.split(txt, ";", context.temp_allocator) {
		if i < len(Smart_Curve_Kind) do smart_curve_set(&o.curves[Smart_Curve_Kind(i)], part)
	}
}

smart_builtins :: proc() -> []Preset_Builtin {
	out := make([dynamic]Preset_Builtin, context.temp_allocator)
	add :: proc(out: ^[dynamic]Preset_Builtin, name: string, o: Smart_Opts) {
		o := o
		v, t := smart_preset_vals(&o)
		append(out, Preset_Builtin{name = name, vals = v, text = t})
	}
	o := SMART_DEFAULT
	add(&out, "Default", o)
	o.curve_on[.Falloff], o.antialias = false, false
	add(&out, "Hard edge", o)
	o = SMART_DEFAULT
	o.edges, o.edge_mode = true, .Stop
	add(&out, "Stop at edges", o)
	o.edge_mode, o.snap_px = .Both, 6
	add(&out, "Snap to edges", o)
	return out[:]
}

// Settings saved without a preset name (before presets, or a first start) are "Default" if they match it.
smart_preset_guess :: proc() {
	if smart_preset.n > 0 do return
	sv, st := smart_preset_vals(&smart)
	b := smart_builtins()
	if preset_same({b[0].vals, b[0].text}, sv, st) do name_set(&smart_preset, b[0].name)
}

SMART_PRESET_TIP :: Tip{"Smart Select preset", "Ready-made or saved Smart Select settings, curves included. Picking one replaces them all. The ... menu saves your own."}

// ---------------------------------------------------------------------------
// The area
// ---------------------------------------------------------------------------

@(private = "file")
Smart_Ctx :: struct {
	target:                       Color,
	base:                         f32,
	hue_on, light_on, fall_on:    bool,
	hue_lut, light_lut, fall_lut: [256]f32,
}

@(private = "file")
smart_diff :: #force_inline proc(a, b: Color) -> int {
	return max(abs(int(a.r) - int(b.r)), abs(int(a.g) - int(b.g)), abs(int(a.b) - int(b.b)), abs(int(a.a) - int(b.a)))
}

// Whether color `c` is in the area, and how strongly it is selected.
@(private = "file")
smart_strength :: proc(k: ^Smart_Ctx, c: Color) -> (inside: bool, s: u8) {
	t := k.target
	if c.a == 0 && t.a == 0 do return true, 255
	diff := f32(smart_diff(c, t))
	tol := k.base
	if k.light_on do tol *= k.light_lut[luma(c)] / 128
	if k.hue_on {
		h, _, _ := ip_rgb_hsl(f32(c.r) / 255, f32(c.g) / 255, f32(c.b) / 255)
		m := k.hue_lut[clamp(int(h * 255 + 0.5), 0, 255)] / 128
		// grays have no hue: the curve fades out as the color does
		chroma := f32(int(max(c.r, c.g, c.b)) - int(min(c.r, c.g, c.b))) / 255
		tol *= 1 + (m - 1) * clamp(chroma * 4, 0, 1)
	}
	tol = min(tol, 255)
	if diff > tol do return false, 0
	if !k.fall_on do return true, 255
	x := tol > 0 ? diff / tol * 255 : 0
	return true, u8(clamp(k.fall_lut[clamp(int(x + 0.5), 0, 255)] + 0.5, 0, 255))
}

// How sharply the picture changes at each pixel, 0..255: a Sobel filter, the largest over the color channels and
// opacity. A hard step from 0 to 255 gives 255; a step of d gives about d.
smart_edge_map :: proc(pix: []Color, w, h: int) -> []u8 {
	e := make([]u8, w * h, context.temp_allocator)
	for y in 0 ..< h {
		r0, r1, r2 := max(y - 1, 0) * w, y * w, min(y + 1, h - 1) * w
		for x in 0 ..< w {
			x0, x2 := max(x - 1, 0), min(x + 1, w - 1)
			best := 0
			for ch in 0 ..< 4 {
				a, b, c := int(pix[r0 + x0][ch]), int(pix[r0 + x][ch]), int(pix[r0 + x2][ch])
				l, r := int(pix[r1 + x0][ch]), int(pix[r1 + x2][ch])
				f, g, i := int(pix[r2 + x0][ch]), int(pix[r2 + x][ch]), int(pix[r2 + x2][ch])
				gx := (c + 2 * r + i) - (a + 2 * l + f)
				gy := (f + 2 * g + i) - (a + 2 * b + c)
				best = max(best, abs(gx) + abs(gy))
			}
			e[r1 + x] = u8(min(best / 4, 255))
		}
	}
	return e
}

// The edge value from which Edge strength (1..100) counts a change as an edge.
smart_edge_limit :: proc(strength: int) -> int {
	s := 1 - f32(clamp(strength, 1, 100)) / 100
	return 4 + int(251 * s * s)
}

// The area like the one around (sx, sy), as a w*h mask (255: fully selected). The caller owns it.
smart_region :: proc(pix: []Color, w, h, sx, sy: int, o: ^Smart_Opts) -> []u8 {
	n := w * h
	mask := make([]u8, n)
	if sx < 0 || sy < 0 || sx >= w || sy >= h || len(pix) < n do return mask
	start := sy * w + sx

	k: Smart_Ctx
	k.base = f32(clamp(o.tolerance, 0, 255))
	k.hue_on, k.light_on, k.fall_on = o.curve_on[.Hue], o.curve_on[.Light], o.curve_on[.Falloff]
	if k.hue_on do k.hue_lut = macro_curve_lut(smart_curve(.Hue))
	if k.light_on do k.light_lut = macro_curve_lut(smart_curve(.Light))
	if k.fall_on do k.fall_lut = macro_curve_lut(smart_curve(.Falloff))
	// the clicked color, averaged with the pixels around it that are close to it: grain doesn't decide it, and a
	// one-pixel line stays its own color
	{
		center := pix[start]
		acc: [4]int
		cnt := 0
		for y in max(sy - 1, 0) ..= min(sy + 1, h - 1) {
			for x in max(sx - 1, 0) ..= min(sx + 1, w - 1) {
				c := pix[y * w + x]
				if smart_diff(c, center) * 2 > o.tolerance do continue
				acc += {int(c.r), int(c.g), int(c.b), int(c.a)}
				cnt += 1
			}
		}
		k.target = Color{u8(acc[0] / cnt), u8(acc[1] / cnt), u8(acc[2] / cnt), u8(acc[3] / cnt)}
	}

	edge: []u8
	if o.edges do edge = smart_edge_map(pix, w, h)
	stop := o.edges && o.edge_mode != .Snap
	limit := u8(smart_edge_limit(o.edge_strength))
	inside := make([]bool, n, context.temp_allocator)

	if !o.contiguous {
		for i in 0 ..< n {
			inside[i], mask[i] = smart_strength(&k, pix[i])
		}
	} else {
		seen := make([]bool, n, context.temp_allocator)
		stack := make([dynamic]int, context.temp_allocator)
		append(&stack, start)
		seen[start] = true
		for len(stack) > 0 {
			i := pop(&stack)
			ok, s := smart_strength(&k, pix[i])
			if i == start && !ok do ok, s = true, 255 // the clicked pixel is always in
			if !ok do continue
			inside[i], mask[i] = true, s
			// an edge joins the area, but the area doesn't spread on from it
			if stop && i != start && edge[i] >= limit do continue
			x, y := i % w, i / w
			nb: [4]int
			cnt := 0
			if seamless_mode {
				nb = {y * w + (x + 1) % w, y * w + (x + w - 1) % w, ((y + 1) % h) * w + x, ((y + h - 1) % h) * w + x}
				cnt = 4
			} else {
				if x + 1 < w {nb[cnt] = i + 1; cnt += 1}
				if x > 0 {nb[cnt] = i - 1; cnt += 1}
				if y + 1 < h {nb[cnt] = i + w; cnt += 1}
				if y > 0 {nb[cnt] = i - w; cnt += 1}
			}
			for j in nb[:cnt] {
				if !seen[j] {
					seen[j] = true
					append(&stack, j)
				}
			}
		}
	}

	if o.edges && o.edge_mode != .Stop do smart_snap(mask, inside, edge, w, h, clamp(o.snap_px, 1, 64))
	if o.antialias do smart_smooth(mask, w, h)
	return mask
}

// Moves the outline of `mask` onto the strongest edges within `r` pixels of it (see the top of the file).
@(private = "file")
smart_snap :: proc(mask: []u8, inside: []bool, edge: []u8, w, h, r: int) {
	n := w * h
	// steps (8-way) from the outline, on each side, up to r + 1; 0: farther
	dist := make([]u8, n, context.temp_allocator)
	q := make([dynamic]int, context.temp_allocator)
	for i in 0 ..< n {
		x, y := i % w, i / w
		in_ := inside[i]
		if x > 0 && inside[i - 1] != in_ || x < w - 1 && inside[i + 1] != in_ || y > 0 && inside[i - w] != in_ || y < h - 1 && inside[i + w] != in_ {
			dist[i] = 1
			append(&q, i)
		}
	}
	if len(q) == 0 do return
	for head := 0; head < len(q); head += 1 {
		i := q[head]
		if int(dist[i]) > r do continue
		x, y := i % w, i / w
		for dy in -1 ..= 1 {
			for dx in -1 ..= 1 {
				nx, ny := x + dx, y + dy
				if nx < 0 || ny < 0 || nx >= w || ny >= h do continue
				j := ny * w + nx
				if dist[j] != 0 || inside[j] != inside[i] do continue
				dist[j] = dist[i] + 1
				append(&q, j)
			}
		}
	}
	// what is sure stays: farther than r from the outline, or the middle of a part thinner than the band
	lab := make([]i16, n, context.temp_allocator) // -1: in the band, still to decide; 0: out; else its strength
	for i in 0 ..< n {
		d := int(dist[i])
		sure := d == 0 || d > r
		if !sure {
			sure = true
			x, y := i % w, i / w
			check: for dy in -1 ..= 1 {
				for dx in -1 ..= 1 {
					nx, ny := x + dx, y + dy
					if nx < 0 || ny < 0 || nx >= w || ny >= h do continue
					j := ny * w + nx
					if inside[j] == inside[i] && (dist[j] == 0 || int(dist[j]) > d) {
						sure = false
						break check
					}
				}
			}
		}
		lab[i] = !sure ? -1 : inside[i] ? i16(max(mask[i], 1)) : 0
	}
	// flood the band from the sure pixels, lowest edges first, so the two sides meet on the edges
	buckets: [256][dynamic]int
	for &b in buckets do b = make([dynamic]int, context.temp_allocator)
	queued := make([]bool, n, context.temp_allocator)
	nbrs :: proc(i, w, h: int) -> (nb: [4]int, cnt: int) {
		x, y := i % w, i / w
		if x + 1 < w {nb[cnt] = i + 1; cnt += 1}
		if x > 0 {nb[cnt] = i - 1; cnt += 1}
		if y + 1 < h {nb[cnt] = i + w; cnt += 1}
		if y > 0 {nb[cnt] = i - w; cnt += 1}
		return
	}
	for i in 0 ..< n {
		if lab[i] < 0 do continue
		nb, cnt := nbrs(i, w, h)
		for j in nb[:cnt] {
			if lab[j] < 0 && !queued[j] {
				queued[j] = true
				append(&buckets[edge[j]], j)
			}
		}
	}
	for level := 0; level < 256; {
		if len(buckets[level]) == 0 {
			level += 1
			continue
		}
		i := pop(&buckets[level])
		// take the side of the decided neighbour across the faintest edge
		nb, cnt := nbrs(i, w, h)
		best, best_e := -1, 256
		for j in nb[:cnt] {
			if lab[j] >= 0 && int(edge[j]) < best_e do best, best_e = j, int(edge[j])
		}
		if best < 0 do continue
		lab[i] = lab[best]
		for j in nb[:cnt] {
			if lab[j] < 0 && !queued[j] {
				queued[j] = true
				append(&buckets[max(int(edge[j]), level)], j)
			}
		}
	}
	for i in 0 ..< n {
		switch {
		case lab[i] == 0:
			mask[i] = 0
		case lab[i] > 0 && mask[i] == 0:
			mask[i] = u8(lab[i]) // newly in: as strongly as the side it joined
		}
	}
}

// Softens hard steps of the outline: a pixel next to a jump from in to out takes the average around it.
@(private = "file")
smart_smooth :: proc(mask: []u8, w, h: int) {
	src := make([]u8, len(mask), context.temp_allocator)
	copy(src, mask)
	for y in 0 ..< h {
		for x in 0 ..< w {
			i := y * w + x
			v := int(src[i])
			hard := x > 0 && abs(int(src[i - 1]) - v) > 127 || x < w - 1 && abs(int(src[i + 1]) - v) > 127 || y > 0 && abs(int(src[i - w]) - v) > 127 || y < h - 1 && abs(int(src[i + w]) - v) > 127
			if !hard do continue
			sum, cnt := 0, 0
			for yy in max(y - 1, 0) ..= min(y + 1, h - 1) {
				for xx in max(x - 1, 0) ..= min(x + 1, w - 1) {
					sum += int(src[yy * w + xx])
					cnt += 1
				}
			}
			mask[i] = u8(sum / cnt)
		}
	}
}

// ---------------------------------------------------------------------------
// Using it: a click selects, and changing the settings redoes the last click
// ---------------------------------------------------------------------------

Smart_Last :: struct {
	valid: bool,
	d:     ^Doc,
	w, h:  int,
	pt:    IVec,
	mode:  Sel_Mode,
	base:  []u8, // the selection before the click (owned), for Add, Subtract and Intersect
}

smart_last: Smart_Last

smart_forget :: proc() {
	delete(smart_last.base)
	smart_last = {}
}

// The painting `d` is closing: a click on it can't be redone.
smart_doc_closed :: proc(d: ^Doc) {
	if smart_last.d == d do smart_forget()
}

@(private = "file")
smart_source :: proc(d: ^Doc) -> []Color {
	if smart.sample_merged {
		doc_refresh_comp(d)
		return d.comp
	}
	return layer_flat(d, &d.layers[d.active_layer])
}

// A click with the tool at canvas point `p`: select the area there, combined with the selection by `mode`.
smart_click :: proc(p: Vec2, mode: Sel_Mode) {
	d := doc
	if d == nil || !pt_in_doc(p) do return
	smart_forget()
	smart_last = {valid = true, d = d, w = d.w, h = d.h, pt = ipt(p), mode = mode}
	if d.sel != nil && mode != .Replace {
		smart_last.base = make([]u8, len(d.sel.v))
		copy(smart_last.base, d.sel.v)
	}
	history_push(d)
	smart_apply()
}

// Selects the last click's area again, with the current settings. False if there is no click to redo.
smart_apply :: proc() -> bool {
	d := doc
	L := &smart_last
	if !L.valid || d == nil || L.d != d || L.w != d.w || L.h != d.h do return false
	shape := smart_region(smart_source(d), d.w, d.h, L.pt.x, L.pt.y, &smart)
	defer delete(shape)
	doc_sel_set(d, sel_combine(L.base, shape, L.mode))
	return true
}

// ---------------------------------------------------------------------------
// Settings window: docked by the canvas, which can still be clicked to select
// ---------------------------------------------------------------------------

@(private = "file")
Smart_Dlg :: struct {
	saved:   Smart_Opts, // to put back on Cancel
	saved_preset: Name,
	sel:     []u8, // the selection when the window opened (owned), for Cancel
	sel_w:   int,
	sel_h:   int,
	touched: bool, // the selection changed since then
	curve:   Smart_Curve_Kind,
	grab:    int, // the curve point being dragged, or -1
	dirty:   bool,
	last_t:  f64,
}

@(private = "file")
sdlg: Smart_Dlg

smart_settings_open :: proc() {
	sdlg.saved, sdlg.saved_preset = smart, smart_preset
	preset_naming_cancel()
	delete(sdlg.sel)
	sdlg.sel = nil
	sdlg.touched = false
	sdlg.grab = -1
	sdlg.dirty = false
	if d := doc; d != nil {
		sdlg.sel_w, sdlg.sel_h = d.w, d.h
		if d.sel != nil {
			sdlg.sel = make([]u8, len(d.sel.v))
			copy(sdlg.sel, d.sel.v)
		}
	}
	dialog_open(.Smart_Select)
}

SMART_GRAPH_H :: 120

dlg_smart_select :: proc() {
	LW :: 96
	c := dialog_frame("Smart Select", 330, 22 + 26 + 24 + 22 + SMART_GRAPH_H + 30 + 22 + 3 * 20 + 18 + 28, docked = true)
	box := Rect{c.x - 12, c.y - 26, c.w + 24, c.h + 34}
	changed := false
	y := c.y

	smart_preset_guess()
	sv, st := smart_preset_vals(&smart)
	tip_text(c.x, y + 3, "Preset", C_TEXT, SMART_PRESET_TIP)
	if v, ok := preset_row(Rect{c.x + LW, y, c.w - LW, 14}, "smart-select", smart_builtins(), &smart_preset, sv, st, SMART_PRESET_TIP); ok {
		smart_preset_apply(&smart, v.vals, v.text)
		changed = true
	}
	y += 22

	tol_tip := Tip{"Tolerance", HELP_SMART_TOL}
	tip_text(c.x, y + 3, "Tolerance", C_TEXT, tol_tip)
	if slider(Rect{c.x + LW, y, c.w - LW, 14}, &smart.tolerance, 0, 255, "", tol_tip) do changed = true
	y += 20
	if checkbox(c.x, y, "Contiguous", &smart.contiguous, {"Contiguous", HELP_SMART_CONTIGUOUS}) do changed = true
	if checkbox(c.x + 104, y, "All layers", &smart.sample_merged, {"All layers", HELP_SMART_ALL_LAYERS}) do changed = true
	if checkbox(c.x + 200, y, "Smooth edge", &smart.antialias, {"Smooth edge", HELP_SMART_SMOOTH}) do changed = true
	y += 24

	// the curves, one at a time
	k := sdlg.curve
	curve_tip := Tip{"Curve", HELP_SMART_CURVE}
	tip_text(c.x, y + 3, "Curve", C_TEXT, curve_tip)
	if nv, ch := combo(Rect{c.x + LW, y, 128, 14}, SMART_CURVE_NAMES[:], int(k), curve_tip); ch {
		sdlg.curve = Smart_Curve_Kind(nv)
		sdlg.grab = -1
		k = sdlg.curve
	}
	if checkbox(c.x + LW + 134, y + 1, "On", &smart.curve_on[k], {"On", HELP_SMART_ON}) do changed = true
	if button(Rect{c.x + c.w - 44, y, 44, 14}, "Reset", {"", "Put this curve back as it was at first."}) {
		smart_curve_set(&smart.curves[k], SMART_CURVE_DEFAULTS[k])
		changed = true
	}
	y += 22
	if smart_curve_edit(Rect{c.x, y, c.w, SMART_GRAPH_H}, k) do changed = true
	y += SMART_GRAPH_H + 2
	smart_axis(Rect{c.x, y, c.w, 6}, k)
	y += 28

	// edges
	hline(c.x, y - 4, c.w, C_RING_HI)
	if checkbox(c.x, y + 1, "Edge bias", &smart.edges, {"Edge bias", HELP_SMART_EDGES}) do changed = true
	mode_tip := Tip{"Edge bias", HELP_SMART_EDGE_MODE}
	if nv, ch := combo(Rect{c.x + LW, y, 150, 14}, SMART_EDGE_NAMES[:], int(smart.edge_mode), mode_tip); ch {
		smart.edge_mode = Smart_Edge_Mode(nv)
		changed = true
	}
	y += 22
	strength_tip := Tip{"Edge strength", HELP_SMART_EDGE_STRENGTH}
	tip_text(c.x, y + 3, "Edge strength", smart.edges ? C_TEXT : C_TEXT_DIM, strength_tip)
	if slider(Rect{c.x + LW, y, c.w - LW, 14}, &smart.edge_strength, 1, 100, "", strength_tip) do changed = true
	y += 20
	snap_tip := Tip{"Snap distance", HELP_SMART_SNAP}
	snapping := smart.edges && smart.edge_mode != .Stop
	tip_text(c.x, y + 3, "Snap distance", snapping ? C_TEXT : C_TEXT_DIM, snap_tip)
	if slider(Rect{c.x + LW, y, c.w - LW, 14}, &smart.snap_px, 1, 32, "", snap_tip, " px") do changed = true
	y += 20
	text(c.x, y + 3, "Click the canvas to select.  Shift: add   Alt: subtract", C_TEXT_DIM)

	// a click on the canvas beside the window selects there, as the tool does
	if !popup.open && in_rect(canvas_vp, ui.mx, ui.my) && !in_rect(box, ui.mx, ui.my) && ui.active_id == 0 {
		ui_tool_cursor(TOOL_ICONS[.Smart_Select])
		if ui.pressed[0] && doc != nil {
			smart_click(wrap_pt(screen_to_canvas(f32(ui.mx), f32(ui.my))), sel_mode_now())
			sdlg.touched = true
		}
	}
	// redo the last click with the new settings: at once, or now and then while a slider or a point is dragged
	if changed do sdlg.dirty = true
	if sdlg.dirty && (!ui.down[0] || ui.time - sdlg.last_t > 0.1) {
		sdlg.dirty = false
		sdlg.last_t = ui.time
		if smart_apply() do sdlg.touched = true
	}

	naming := preset_naming("smart-select", true)
	if button(Rect{c.x, c.y + c.h - 18, 104, 18}, "Save as Preset...", {"Save as Preset", "Keep these settings, curves included, as a Smart Select preset of your own, under a name you type above."}, !naming) {
		preset_save_begin("smart-select", sv, st, row = true)
	}
	ok, cancel := dialog_buttons(c, "Keep these settings (Enter).")
	if ok || cancel do preset_naming_cancel()
	if cancel {
		smart, smart_preset = sdlg.saved, sdlg.saved_preset
		if d := doc; sdlg.touched && d != nil && d.w == sdlg.sel_w && d.h == sdlg.sel_h {
			v := make([]u8, d.w * d.h)
			if sdlg.sel != nil do copy(v, sdlg.sel)
			doc_sel_set(d, v)
		}
		dialog_close()
	}
	if ok do dialog_close()
	if cancel || ok {
		delete(sdlg.sel)
		sdlg.sel = nil
	}
}

// What the curve's two directions mean, and what is under the pointer.
@(private = "file")
smart_curve_tip :: proc(k: Smart_Curve_Kind) -> Tip {
	switch k {
	case .Hue:
		return {"Tolerance by hue", "Hues go along the bottom, around the color wheel from red back to red. Higher on the curve gives that hue more tolerance: the middle line is the Tolerance setting, the top twice it, the bottom none. Grays are left to the Tolerance setting. Drag a point, click to add one, right-click to remove one."}
	case .Light:
		return {"Tolerance by brightness", "Tones go along the bottom, dark at the left. Higher on the curve gives that tone more tolerance: the middle line is the Tolerance setting, the top twice it, the bottom none. Drag a point, click to add one, right-click to remove one."}
	case .Falloff:
		return {"Falloff", "How different a pixel is goes along the bottom: the clicked color at the left, as different as the tolerance allows at the right. The height is how strongly it is selected. Flat at the top is a hard edge; a curve that drops makes a soft one. Drag a point, click to add one, right-click to remove one."}
	}
	return {}
}

// The curve editor. True when the curve changed.
@(private = "file")
smart_curve_edit :: proc(g: Rect, k: Smart_Curve_Kind) -> (changed: bool) {
	c := &smart.curves[k]
	smart_curve(k) // fills in the default
	on := smart.curve_on[k]
	fill_rect(g, C_PANEL_DK)
	px, py, pw, ph := f32(g.x) + 1, f32(g.y) + 1, f32(g.w) - 2, f32(g.h) - 2
	to_scr :: proc(p: Vec2, px, py, pw, ph: f32) -> Vec2 {
		return {px + p.x / 255 * pw, py + ph - p.y / 255 * ph}
	}
	grid := Color{60, 60, 72, 255}
	for i in 1 ..< 4 {
		vline(g.x + i32(f32(g.w) * f32(i) / 4), g.y, g.h, grid)
		hline(g.x, g.y + i32(f32(g.h) * f32(i) / 4), g.w, grid)
	}
	if k != .Falloff {
		// the Tolerance setting itself
		hline(g.x, g.y + g.h / 2, g.w, Color{110, 110, 126, 255})
	}

	// input
	mouse := Vec2{f32(ui.mx), f32(ui.my)}
	at := Vec2{clamp((mouse.x - px) / pw * 255, 0, 255), clamp((py + ph - mouse.y) / ph * 255, 0, 255)}
	hit := Rect{g.x - 4, g.y - 4, g.w + 8, g.h + 8}
	near := -1
	if ui_hover(hit) && !popup.open {
		tip_area(g, "smartcurve", smart_curve_tip(k))
		best := f32(7)
		for i in 0 ..< c.n {
			q := to_scr(c.pts[i], px, py, pw, ph)
			if dd := vlen(q - mouse); dd < best do near, best = i, dd
		}
		if ui.pressed[0] {
			if near < 0 && c.n < MACRO_CURVE_MAX {
				near = c.n
				for i in 0 ..< c.n {
					if c.pts[i].x > at.x {
						near = i
						break
					}
				}
				for j := c.n; j > near; j -= 1 do c.pts[j] = c.pts[j - 1]
				c.pts[near] = {math.round(at.x), math.round(at.y)}
				c.n += 1
				changed = true
			}
			sdlg.grab = near
			if near >= 0 do ui.active_id = make_id(g, "smartcurve")
		} else if ui.pressed[1] && near >= 0 && c.n > 2 {
			for j in near ..< c.n - 1 do c.pts[j] = c.pts[j + 1]
			c.n -= 1
			near = -1
			changed = true
		}
	}
	if sdlg.grab >= 0 {
		if !ui.down[0] {
			sdlg.grab = -1
		} else if i := sdlg.grab; i < c.n {
			lo: f32 = i > 0 ? c.pts[i - 1].x + 1 : 0
			hi: f32 = i < c.n - 1 ? c.pts[i + 1].x - 1 : 255
			np := Vec2{math.round(clamp(at.x, lo, hi)), math.round(at.y)}
			if np != c.pts[i] {
				c.pts[i] = np
				changed = true
			}
			near = i
		}
	}

	// the curve: filled under it, dimmed while it is off
	lut := macro_curve_lut(c.pts[:c.n])
	col := on ? C_ACCENT : C_TEXT_DIM
	steps := max(int(pw), 2)
	prev: Vec2
	for i in 0 ..= steps {
		t := f32(i) / f32(steps) * 255
		q := to_scr({t, lut[clamp(int(math.round(t)), 0, 255)]}, px, py, pw, ph)
		if i < steps do draw_rect(q.x, q.y, max(pw / f32(steps), 1), py + ph - q.y, with_alpha(col, on ? 40 : 20))
		if i > 0 do draw_thick_line(prev, q, 1.6, col)
		prev = q
	}
	for i in 0 ..< c.n {
		q := to_scr(c.pts[i], px, py, pw, ph)
		lit := i == near
		draw_frect({q.x - 4, q.y - 4, 8, 8}, lit ? C_ACCENT : BLACK)
		draw_frect({q.x - 3, q.y - 3, 6, 6}, lit ? WHITE : C_TEXT)
	}
	outline_rect(g, C_BORDER)

	// what the pointer is over, in words
	if ui_hover(hit) {
		v := lut[clamp(int(math.round(at.x)), 0, 255)]
		s: string
		switch k {
		case .Hue:
			s = fmt.tprintf("Hue %d deg: tolerance %d", int(at.x * 360 / 255 + 0.5), int(f32(smart.tolerance) * v / 128 + 0.5))
		case .Light:
			s = fmt.tprintf("Brightness %d%%: tolerance %d", int(at.x * 100 / 255 + 0.5), int(f32(smart.tolerance) * v / 128 + 0.5))
		case .Falloff:
			s = fmt.tprintf("%d%% of the tolerance: %d%% selected", int(at.x * 100 / 255 + 0.5), int(v * 100 / 255 + 0.5))
		}
		text(g.x + g.w - text_w(s) - 6, g.y + 4, s, C_TEXT)
	}
	return
}

// The strip under the graph: what goes along the bottom.
@(private = "file")
smart_axis :: proc(r: Rect, k: Smart_Curve_Kind) {
	for x in 0 ..< r.w {
		t := f32(x) / f32(max(r.w - 1, 1))
		col: Color
		switch k {
		case .Hue:
			cr, cg, cb := ip_hsl_rgb(t, 1, 0.5)
			col = {ip_u8(cr), ip_u8(cg), ip_u8(cb), 255}
		case .Light:
			v := u8(t * 255 + 0.5)
			col = {v, v, v, 255}
		case .Falloff:
			v := u8(230 - t * 170)
			col = {v, v, v, 255}
		}
		vline(r.x + x, r.y, r.h, col)
	}
	ly := r.y + r.h + 4
	left, right := "Red", "Red"
	switch k {
	case .Hue:
		for name, i in ([?]string{"Yellow", "Green", "Cyan", "Blue", "Magenta"}) {
			cx := r.x + i32(f32(r.w) * f32(i + 1) / 6)
			text(cx - text_w(name) / 2, ly, name, C_TEXT_DIM)
		}
	case .Light:
		left, right = "Dark", "Light"
	case .Falloff:
		left, right = "Same color", "At the tolerance"
	}
	text(r.x, ly, left, C_TEXT_DIM)
	if k != .Hue do text(r.x + r.w - text_w(right), ly, right, C_TEXT_DIM)
}

// ---------------------------------------------------------------------------
// Preferences
// ---------------------------------------------------------------------------

smart_prefs_write :: proc(sb: ^strings.Builder) {
	b2i :: proc(b: bool) -> int {
		return b ? 1 : 0
	}
	fmt.sbprintf(sb, "smart_tolerance=%d\n", smart.tolerance)
	fmt.sbprintf(sb, "smart_contiguous=%d\n", b2i(smart.contiguous))
	fmt.sbprintf(sb, "smart_all_layers=%d\n", b2i(smart.sample_merged))
	fmt.sbprintf(sb, "smart_smooth=%d\n", b2i(smart.antialias))
	fmt.sbprintf(sb, "smart_edges=%d\n", b2i(smart.edges))
	fmt.sbprintf(sb, "smart_edge_mode=%d\n", int(smart.edge_mode))
	fmt.sbprintf(sb, "smart_edge_strength=%d\n", smart.edge_strength)
	fmt.sbprintf(sb, "smart_snap=%d\n", smart.snap_px)
	for k in Smart_Curve_Kind {
		fmt.sbprintf(sb, "smart_curve_%v=%d:%s\n", k, b2i(smart.curve_on[k]), macro_curve_text(smart_curve(k)))
	}
	fmt.sbprintf(sb, "smart_preset=%s\n", name_str(&smart_preset))
}

// Reads one preferences line if it is a Smart Select setting.
smart_prefs_read :: proc(key, val: string) -> bool {
	if !strings.has_prefix(key, "smart_") do return false
	if key == "smart_preset" {
		name_set(&smart_preset, val) // the name only: the settings come from their own lines
		return true
	}
	for k in Smart_Curve_Kind {
		if key == fmt.tprintf("smart_curve_%v", k) {
			on, _, pts := strings.partition(val, ":")
			smart.curve_on[k] = on == "1"
			smart_curve_set(&smart.curves[k], pts)
			return true
		}
	}
	n, ok := strconv.parse_int(val)
	if !ok do return true
	switch key {
	case "smart_tolerance":
		smart.tolerance = clamp(n, 0, 255)
	case "smart_contiguous":
		smart.contiguous = n != 0
	case "smart_all_layers":
		smart.sample_merged = n != 0
	case "smart_smooth":
		smart.antialias = n != 0
	case "smart_edges":
		smart.edges = n != 0
	case "smart_edge_mode":
		smart.edge_mode = Smart_Edge_Mode(clamp(n, 0, len(Smart_Edge_Mode) - 1))
	case "smart_edge_strength":
		smart.edge_strength = clamp(n, 1, 100)
	case "smart_snap":
		smart.snap_px = clamp(n, 1, 32)
	}
	return true
}
