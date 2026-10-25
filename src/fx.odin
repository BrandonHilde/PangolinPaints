package pangolin

import "core:fmt"

// ---------------------------------------------------------------------------
// Adjustments (Adjust menu) and filters (Filter menu), applied to the active
// layer or mask through the selection, with a live preview.
// ---------------------------------------------------------------------------

Fx :: enum {
	// adjustments
	Brightness_Contrast,
	Levels,
	Hue_Saturation,
	Color_Balance,
	Vibrance,
	Exposure,
	Temperature,
	Posterize,
	Threshold,
	Sepia,
	Invert,
	Desaturate,
	// filters
	Gaussian_Blur,
	Box_Blur,
	Motion_Blur,
	Radial_Blur,
	Unsharp_Mask,
	Add_Noise,
	Median,
	Oil_Paint,
	Kuwahara,
	Emboss,
	Find_Edges,
	Pixelate,
	Vignette,
	Canvas_Texture,
}

FX_FIRST_FILTER :: Fx.Gaussian_Blur

Fx_Param :: struct {
	name:    string,
	lo, hi:  int,
	def:     int,
	suffix:  string,
	div:     int, // display value / div (e.g. gamma 100 = 1.00)
}

Fx_Def :: struct {
	name:    string,
	params:  []Fx_Param,
	flag:    string, // optional checkbox
	flag_def: bool,
	choice:  []string, // optional combo (channel / tonal range)
	heavy:   bool, // preview only after the slider is released
}

FX_DEFS := [Fx]Fx_Def {
	.Brightness_Contrast = {name = "Brightness / Contrast", params = {{"Brightness", -100, 100, 0, "", 1}, {"Contrast", -100, 100, 0, "", 1}}},
	.Levels = {name = "Levels", params = {{"Input black", 0, 254, 0, "", 1}, {"Input white", 1, 255, 255, "", 1}, {"Gamma", 10, 500, 100, "", 100}, {"Output black", 0, 255, 0, "", 1}, {"Output white", 0, 255, 255, "", 1}}, choice = {"RGB", "Red", "Green", "Blue"}},
	.Hue_Saturation = {name = "Hue / Saturation", params = {{"Hue", -180, 180, 0, "", 1}, {"Saturation", -100, 100, 0, "", 1}, {"Lightness", -100, 100, 0, "", 1}}, flag = "Colorize"},
	.Color_Balance = {name = "Color Balance", params = {{"Cyan / Red", -100, 100, 0, "", 1}, {"Magenta / Green", -100, 100, 0, "", 1}, {"Yellow / Blue", -100, 100, 0, "", 1}}, choice = {"Shadows", "Midtones", "Highlights"}, flag = "Preserve luminosity", flag_def = true},
	.Vibrance = {name = "Vibrance", params = {{"Vibrance", -100, 100, 0, "", 1}, {"Saturation", -100, 100, 0, "", 1}}},
	.Exposure = {name = "Exposure", params = {{"Exposure", -500, 500, 0, " stops", 100}, {"Offset", -50, 50, 0, "", 100}, {"Gamma", 10, 500, 100, "", 100}}},
	.Temperature = {name = "Temperature / Tint", params = {{"Temperature", -100, 100, 0, "", 1}, {"Tint", -100, 100, 0, "", 1}}},
	.Posterize = {name = "Posterize", params = {{"Levels", 2, 64, 6, "", 1}}},
	.Threshold = {name = "Threshold", params = {{"Level", 0, 255, 128, "", 1}}},
	.Sepia = {name = "Sepia", params = {{"Amount", 0, 100, 80, "%", 1}}},
	.Invert = {name = "Invert"},
	.Desaturate = {name = "Desaturate"},
	.Gaussian_Blur = {name = "Gaussian Blur", params = {{"Radius", 1, 2500, 30, " px", 10}}},
	.Box_Blur = {name = "Box Blur", params = {{"Radius", 1, 200, 4, " px", 1}}},
	.Motion_Blur = {name = "Motion Blur", params = {{"Angle", -180, 180, 0, " deg", 1}, {"Distance", 1, 500, 20, " px", 1}}},
	.Radial_Blur = {name = "Radial (Zoom) Blur", params = {{"Amount", 0, 100, 20, "", 1}, {"Centre X", 0, 100, 50, "%", 1}, {"Centre Y", 0, 100, 50, "%", 1}}, heavy = true},
	.Unsharp_Mask = {name = "Unsharp Mask", params = {{"Amount", 0, 500, 100, "%", 1}, {"Radius", 1, 1000, 15, " px", 10}, {"Threshold", 0, 255, 0, "", 1}}},
	.Add_Noise = {name = "Add Noise", params = {{"Amount", 0, 100, 10, "%", 1}}, flag = "Monochromatic", flag_def = true},
	.Median = {name = "Median (Despeckle)", params = {{"Radius", 1, 20, 2, " px", 1}}, heavy = true},
	.Oil_Paint = {name = "Oil Paint", params = {{"Brush radius", 1, 15, 4, " px", 1}, {"Detail levels", 4, 64, 20, "", 1}}, heavy = true},
	.Kuwahara = {name = "Painterly (Kuwahara)", params = {{"Radius", 1, 15, 4, " px", 1}}, heavy = true},
	.Emboss = {name = "Emboss", params = {{"Light angle", -180, 180, 135, " deg", 1}, {"Height", 1, 10, 3, "", 1}}, flag = "Keep colour", flag_def = true},
	.Find_Edges = {name = "Find Edges"},
	.Pixelate = {name = "Pixelate", params = {{"Cell size", 2, 256, 8, " px", 1}}},
	.Vignette = {name = "Vignette", params = {{"Amount", -100, 100, 40, "", 1}, {"Softness", 0, 100, 50, "", 1}}},
	.Canvas_Texture = {name = "Canvas Texture", params = {{"Weave size", 1, 8, 3, "", 1}, {"Strength", 0, 100, 35, "%", 1}}},
}

Fx_State :: struct {
	fx:        Fx,
	v:         [6]int,
	flag:      bool,
	choice:    int,
	preview:   bool,
	dirty:     bool,
	seed:      u64,
}

fxs: Fx_State

fx_run :: proc(fx: Fx, st: ^Fx_State, src, dst: []Color, w, h: int) {
	v := st.v
	switch fx {
	case .Brightness_Contrast:
		adj_brightness_contrast(src, dst, v[0], v[1])
	case .Levels:
		adj_levels(src, dst, v[0], max(v[1], v[0] + 1), f32(v[2]) / 100, v[3], v[4], st.choice)
	case .Hue_Saturation:
		adj_hue_sat_light(src, dst, v[0], v[1], v[2], st.flag)
	case .Color_Balance:
		adj_color_balance(src, dst, v[0], v[1], v[2], st.choice, st.flag)
	case .Vibrance:
		adj_vibrance(src, dst, v[0], v[1])
	case .Exposure:
		adj_exposure(src, dst, f32(v[0]) / 100, f32(v[1]) / 100, f32(v[2]) / 100)
	case .Temperature:
		adj_temperature(src, dst, v[0], v[1])
	case .Posterize:
		adj_posterize(src, dst, v[0])
	case .Threshold:
		adj_threshold(src, dst, v[0])
	case .Sepia:
		adj_sepia(src, dst, v[0])
	case .Invert:
		adj_invert(src, dst)
	case .Desaturate:
		adj_desaturate(src, dst)
	case .Gaussian_Blur:
		filter_gaussian_blur(src, dst, w, h, f32(v[0]) / 10)
	case .Box_Blur:
		filter_box_blur(src, dst, w, h, v[0])
	case .Motion_Blur:
		filter_motion_blur(src, dst, w, h, f32(v[0]), v[1])
	case .Radial_Blur:
		filter_radial_blur(src, dst, w, h, f32(w) * f32(v[1]) / 100, f32(h) * f32(v[2]) / 100, v[0])
	case .Unsharp_Mask:
		filter_unsharp_mask(src, dst, w, h, f32(v[1]) / 10, v[0], v[2])
	case .Add_Noise:
		filter_add_noise(src, dst, w, h, v[0], st.flag, st.seed)
	case .Median:
		filter_median(src, dst, w, h, v[0])
	case .Oil_Paint:
		filter_oil_paint(src, dst, w, h, v[0], v[1])
	case .Kuwahara:
		filter_kuwahara(src, dst, w, h, v[0])
	case .Emboss:
		filter_emboss(src, dst, w, h, f32(v[0]), v[1], st.flag)
	case .Find_Edges:
		filter_find_edges(src, dst, w, h)
	case .Pixelate:
		filter_pixelate(src, dst, w, h, v[0])
	case .Vignette:
		filter_vignette(src, dst, w, h, v[0], v[1])
	case .Canvas_Texture:
		filter_canvas_texture(src, dst, w, h, v[0], v[1])
	}
}

// Last-used settings per effect, so reopening a dialog remembers them.
fx_saved: [Fx]Fx_State
fx_saved_ok: [Fx]bool
fx_last: Fx = .Gaussian_Blur

fx_open :: proc(fx: Fx) {
	def := &FX_DEFS[fx]
	if !live_begin() {
		return
	}
	fxs = Fx_State {
		fx      = fx,
		flag    = def.flag_def,
		choice  = fx == .Color_Balance ? 1 : 0,
		preview = true,
		dirty   = true,
		seed    = u64(ui.time * 1000) + 1,
	}
	for p, i in def.params {
		fxs.v[i] = p.def
	}
	if fx_saved_ok[fx] {
		fxs.v, fxs.flag, fxs.choice = fx_saved[fx].v, fx_saved[fx].flag, fx_saved[fx].choice
	}
	if fx >= FX_FIRST_FILTER {
		fx_last = fx
	}
	// effects without settings apply straight away
	if len(def.params) == 0 && def.flag == "" {
		fx_apply_now()
		live_finish()
		set_status(def.name)
		return
	}
	dialog_open(.Fx)
}

fx_apply_now :: proc() {
	d := doc
	out := live_out()
	fx_run(fxs.fx, &fxs, live.orig, out, d.w, d.h)
	live_store(out)
}

dlg_fx :: proc() {
	def := &FX_DEFS[fxs.fx]
	rows := i32(len(def.params))
	extra: i32 = 0
	if def.choice != nil do extra += 20
	if def.flag != "" do extra += 18
	c := dialog_frame(def.name, 300, 64 + rows * 20 + extra + 18, docked = true)
	y := c.y
	if def.choice != nil {
		text(c.x, y + 3, fxs.fx == .Levels ? "Channel" : "Tones", C_TEXT)
		if nv, ch := combo(Rect{c.x + 100, y, 120, 14}, def.choice, fxs.choice); ch {
			fxs.choice = nv
			fxs.dirty = true
		}
		y += 20
	}
	held := false
	for &p, i in def.params {
		text(c.x, y + 3, p.name, C_TEXT)
		r := Rect{c.x + 100, y, c.w - 100, 14}
		if slider(r, &fxs.v[i], p.lo, p.hi, "", "", p.suffix, 1, p.div) {
			fxs.dirty = true
		}
		if ui.active_id == make_id(r, "") && ui.down[0] {
			held = true
		}
		y += 20
	}
	if def.flag != "" {
		if checkbox(c.x, y, def.flag, &fxs.flag) {
			fxs.dirty = true
		}
		y += 18
	}
	if checkbox(c.x, y, "Preview", &fxs.preview) {
		fxs.dirty = true
	}
	if def.heavy && held {
		text(c.x + 70, y + 1, "(preview on release)", C_TEXT_DIM)
	}
	if fxs.dirty && !(def.heavy && held) {
		fxs.dirty = false
		if fxs.preview {
			fx_apply_now()
		} else {
			live_store(live.orig)
		}
	}
	if button(Rect{c.x, c.y + c.h - 16, 60, 16}, "Reset", "Back to the default settings") {
		for p, i in def.params do fxs.v[i] = p.def
		fxs.flag = def.flag_def
		fxs.dirty = true
	}
	ok, cancel := dialog_buttons(c)
	if cancel {
		live_cancel()
		dialog_close()
	}
	if ok {
		if !fxs.preview || fxs.dirty {
			fx_apply_now()
		}
		fx_saved[fxs.fx] = fxs
		fx_saved_ok[fxs.fx] = true
		live_finish()
		dialog_close()
		set_status(def.name)
	}
}

// ---------------------------------------------------------------------------
// Curves dialog: drag points on the curve, click to add, right click to remove.
// ---------------------------------------------------------------------------

Curves_State :: struct {
	pts:     [4][dynamic]Vec2, // RGB, R, G, B
	channel: int,
	grab:    int,
	dirty:   bool,
}

curves: Curves_State

curves_open :: proc() -> bool {
	if !live_begin() {
		return false
	}
	for &p in curves.pts {
		clear(&p)
		append(&p, Vec2{0, 0}, Vec2{255, 255})
	}
	curves.channel = 0
	curves.grab = -1
	curves.dirty = true
	return true
}

curves_apply :: proc() {
	luts: [4][256]u8
	for i in 0 ..< 4 {
		luts[i] = adj_curve_lut(curves.pts[i][:])
	}
	out := live_out()
	adj_apply_luts(live.orig, out, &luts[0], &luts[1], &luts[2], &luts[3])
	live_store(out)
}

dlg_curves :: proc() {
	c := dialog_frame("Curves", 300, 352, docked = true)
	CH := [?]string{"RGB", "Red", "Green", "Blue"}
	text(c.x, c.y + 3, "Channel", C_TEXT)
	if nv, ch := combo(Rect{c.x + 60, c.y, 90, 14}, CH[:], curves.channel); ch {
		curves.channel = nv
		curves.grab = -1
	}
	g := Rect{c.x + (c.w - 256) / 2, c.y + 22, 256, 256}
	fill_rect(g, C_PANEL_DK)
	// histogram of the original
	hist: [256]int
	for p in live.orig {
		if p.a == 0 do continue
		v: u8
		switch curves.channel {
		case 1:
			v = p.r
		case 2:
			v = p.g
		case 3:
			v = p.b
		case:
			v = luma(p)
		}
		hist[v] += 1
	}
	hmax := 1
	for v in hist do hmax = max(hmax, v)
	for v, i in hist {
		hh := i32(f32(v) / f32(hmax) * 240)
		vline(g.x + i32(i), g.y + g.h - hh, hh, Color{70, 70, 84, 255})
	}
	for i in 1 ..< 4 {
		vline(g.x + i32(i) * 64, g.y, g.h, Color{60, 60, 72, 255})
		hline(g.x, g.y + i32(i) * 64, g.w, Color{60, 60, 72, 255})
	}
	draw_line_i(g.x, g.y + g.h, g.x + g.w, g.y, Color{90, 90, 104, 255})
	pts := &curves.pts[curves.channel]
	to_scr :: proc(g: Rect, p: Vec2) -> Vec2 {
		return Vec2{f32(g.x) + p.x, f32(g.y + g.h) - p.y}
	}
	// mouse
	mp := Vec2{f32(ui.mx - g.x), f32(g.y + g.h - ui.my)}
	if ui_hover(g) && ui.pressed[0] {
		best, bd := -1, f32(8)
		for p, i in pts {
			if d := vlen(p - mp); d < bd {
				best, bd = i, d
			}
		}
		if best < 0 {
			// insert in x order
			np := Vec2{clamp(mp.x, 0, 255), clamp(mp.y, 0, 255)}
			at := len(pts)
			for p, i in pts {
				if p.x > np.x {
					at = i
					break
				}
			}
			inject_at(pts, at, np)
			best = at
		}
		curves.grab = best
		curves.dirty = true
	}
	if ui_hover(g) && ui.pressed[1] && len(pts) > 2 {
		for p, i in pts {
			if vlen(p - mp) < 8 {
				ordered_remove(pts, i)
				curves.dirty = true
				break
			}
		}
	}
	if curves.grab >= 0 && curves.grab < len(pts) && ui.down[0] {
		i := curves.grab
		lo: f32 = i > 0 ? pts[i - 1].x + 1 : 0
		hi: f32 = i < len(pts) - 1 ? pts[i + 1].x - 1 : 255
		pts[i] = Vec2{clamp(mp.x, lo, hi), clamp(mp.y, 0, 255)}
		curves.dirty = true
	}
	if !ui.down[0] {
		curves.grab = -1
	}
	lut := adj_curve_lut(pts[:])
	CC := [?]Color{C_TEXT, {230, 90, 90, 255}, {90, 200, 110, 255}, {100, 150, 255, 255}}
	for x in 1 ..< 256 {
		a := to_scr(g, Vec2{f32(x - 1), f32(lut[x - 1])})
		b := to_scr(g, Vec2{f32(x), f32(lut[x])})
		draw_line(a, b, CC[curves.channel])
	}
	for p in pts {
		s := to_scr(g, p)
		draw_frect({s.x - 3, s.y - 3, 6, 6}, BLACK)
		draw_frect({s.x - 2, s.y - 2, 4, 4}, WHITE)
	}
	outline_rect(g, C_BORDER)
	text(c.x, g.y + g.h + 6, "Click: add point   Drag: shape   Right click: remove", C_TEXT_DIM)
	if curves.dirty && curves.grab < 0 || curves.dirty && ui.time - curves_last_t > 0.08 {
		curves.dirty = false
		curves_last_t = ui.time
		curves_apply()
	}
	if button(Rect{c.x, c.y + c.h - 16, 60, 16}, "Reset") {
		clear(pts)
		append(pts, Vec2{0, 0}, Vec2{255, 255})
		curves.dirty = true
	}
	ok, cancel := dialog_buttons(c)
	if cancel {
		live_cancel()
		dialog_close()
	}
	if ok {
		curves_apply()
		live_finish()
		dialog_close()
		set_status("Curves")
	}
}

curves_last_t: f64

_ :: fmt
