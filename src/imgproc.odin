package pangolin

import "core:math"

// Image adjustments and filters used by the adjustment / filter dialogs.
//
// Conventions: `src` and `dst` are w*h row-major slices of NON-premultiplied colours.
// Per-pixel adjustments (adj_*) may run in place (dst == src). Spatial filters (filter_*)
// must not alias. Spatial filters premultiply by alpha while averaging so transparent
// pixels never bleed dark fringes, and clamp at image edges. Scratch memory comes from
// context.temp_allocator; nothing allocates per pixel.

// ---------------------------------------------------------------------------
// shared helpers
// ---------------------------------------------------------------------------

// Premultiplied working pixel: rgb = c*a (0..65025), alpha = a*255 (0..65025).
@(private = "file")
ip_P :: [4]u16

@(private = "file")
ip_u8 :: #force_inline proc(v: f32) -> u8 {
	return u8(clamp(v * 255 + 0.5, 0, 255))
}

@(private = "file")
ip_u8i :: #force_inline proc(v: f32) -> u8 {
	return u8(clamp(v + 0.5, 0, 255))
}

@(private = "file")
ip_ok :: proc(src, dst: []Color, w, h: int) -> bool {
	return w > 0 && h > 0 && len(src) >= w * h && len(dst) >= w * h
}

@(private = "file")
ip_copy :: proc(src, dst: []Color) {
	n := min(len(src), len(dst))
	if raw_data(src) != raw_data(dst) {
		copy(dst[:n], src[:n])
	}
}

// Rec.709 luma of 0..255 channels, integer weights summing to 256.
@(private = "file")
ip_luma :: #force_inline proc(c: Color) -> u32 {
	return (u32(c[0]) * 54 + u32(c[1]) * 183 + u32(c[2]) * 19) >> 8
}

@(private = "file")
ip_to_lin :: proc(v: f32) -> f32 {
	return v <= 0.04045 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4)
}

@(private = "file")
ip_to_srgb :: proc(v: f32) -> f32 {
	if v <= 0 do return 0
	return v <= 0.0031308 ? v * 12.92 : 1.055 * math.pow(v, 1 / 2.4) - 0.055
}

@(private = "file")
ip_rgb_hsl :: #force_inline proc(r, g, b: f32) -> (h, s, l: f32) {
	mx := max(r, g, b)
	mn := min(r, g, b)
	l = (mx + mn) * 0.5
	d := mx - mn
	if d <= 0 {
		return 0, 0, l
	}
	s = l > 0.5 ? d / (2 - mx - mn) : d / (mx + mn)
	if mx == r {
		h = (g - b) / d
		if g < b do h += 6
	} else if mx == g {
		h = (b - r) / d + 2
	} else {
		h = (r - g) / d + 4
	}
	h /= 6
	return
}

@(private = "file")
ip_hue_ch :: #force_inline proc(p, q, t: f32) -> f32 {
	t := t
	if t < 0 do t += 1
	if t > 1 do t -= 1
	if t < 1.0 / 6 do return p + (q - p) * 6 * t
	if t < 0.5 do return q
	if t < 2.0 / 3 do return p + (q - p) * (2.0 / 3 - t) * 6
	return p
}

@(private = "file")
ip_hsl_rgb :: #force_inline proc(h, s, l: f32) -> (r, g, b: f32) {
	if s <= 0 {
		return l, l, l
	}
	q := l < 0.5 ? l * (1 + s) : l + s - l * s
	p := 2 * l - q
	return ip_hue_ch(p, q, h + 1.0 / 3), ip_hue_ch(p, q, h), ip_hue_ch(p, q, h - 1.0 / 3)
}

@(private = "file")
ip_lut3 :: proc(src, dst: []Color, lr, lg, lb: ^[256]u8) {
	n := min(len(src), len(dst))
	for i in 0 ..< n {
		c := src[i]
		dst[i] = Color{lr^[c[0]], lg^[c[1]], lb^[c[2]], c[3]}
	}
}

@(private = "file")
ip_identity_lut :: proc() -> (l: [256]u8) {
	for i in 0 ..< 256 do l[i] = u8(i)
	return
}

@(private = "file")
ip_mix64 :: #force_inline proc(x: u64) -> u64 {
	z := x + 0x9E3779B97F4A7C15
	z = (z ~ (z >> 30)) * 0xBF58476D1CE4E5B9
	z = (z ~ (z >> 27)) * 0x94D049BB133111EB
	return z ~ (z >> 31)
}

@(private = "file")
ip_hash01 :: #force_inline proc(x: u64) -> f32 {
	return f32(ip_mix64(x) >> 40) / f32(1 << 24)
}

// Irwin-Hall(4) approximation of a unit gaussian from one 64-bit hash.
@(private = "file")
ip_gauss :: #force_inline proc(hv: u64) -> f32 {
	s := (hv & 0xffff) + ((hv >> 16) & 0xffff) + ((hv >> 32) & 0xffff) + (hv >> 48)
	return (f32(s) - 131070) / 37837.6
}

@(private = "file")
ip_smooth :: #force_inline proc(e0, e1, x: f32) -> f32 {
	t := clamp((x - e0) / (e1 - e0), 0, 1)
	return t * t * (3 - 2 * t)
}

@(private = "file")
ip_premul :: proc(src: []Color, n: int) -> []ip_P {
	buf := make([]ip_P, n, context.temp_allocator)
	for i in 0 ..< n {
		c := src[i]
		a := u16(c[3])
		buf[i] = ip_P{u16(c[0]) * a, u16(c[1]) * a, u16(c[2]) * a, a * 255}
	}
	return buf
}

@(private = "file")
ip_unpremul :: proc(buf: []ip_P, dst: []Color) {
	for p, i in buf {
		A := u32(p[3])
		if A == 0 {
			dst[i] = Color{0, 0, 0, 0}
			continue
		}
		hf := A / 2
		dst[i] = Color {
			u8(min((u32(p[0]) * 255 + hf) / A, 255)),
			u8(min((u32(p[1]) * 255 + hf) / A, 255)),
			u8(min((u32(p[2]) * 255 + hf) / A, 255)),
			u8((A + 127) / 255),
		}
	}
}

@(private = "file")
ip_w32 :: #force_inline proc(p: ip_P) -> [4]u32 {
	return {u32(p[0]), u32(p[1]), u32(p[2]), u32(p[3])}
}

@(private = "file")
ip_f :: #force_inline proc(p: ip_P) -> [4]f32 {
	return {f32(p[0]), f32(p[1]), f32(p[2]), f32(p[3])}
}

@(private = "file")
ip_r16 :: #force_inline proc(v: [4]f32) -> ip_P {
	return {
		u16(clamp(v[0] + 0.5, 0, 65025)),
		u16(clamp(v[1] + 0.5, 0, 65025)),
		u16(clamp(v[2] + 0.5, 0, 65025)),
		u16(clamp(v[3] + 0.5, 0, 65025)),
	}
}

// 1D box over [x-lo, x+hi] with clamped edges, in place (tmp is scratch of len(line)). O(n).
@(private = "file")
ip_line_box :: proc(line, tmp: []ip_P, lo, hi: int) {
	n := len(line)
	if n == 0 do return
	copy(tmp, line)
	inv := 1 / f32(lo + hi + 1)
	sum := ip_w32(tmp[0]) * u32(lo + 1)
	e := min(hi, n - 1)
	for k in 1 ..= e do sum += ip_w32(tmp[k])
	if hi > n - 1 do sum += ip_w32(tmp[n - 1]) * u32(hi - (n - 1))
	for x in 0 ..< n {
		line[x] = ip_P {
			u16(f32(sum[0]) * inv + 0.5),
			u16(f32(sum[1]) * inv + 0.5),
			u16(f32(sum[2]) * inv + 0.5),
			u16(f32(sum[3]) * inv + 0.5),
		}
		sum += ip_w32(tmp[min(x + hi + 1, n - 1)])
		sum -= ip_w32(tmp[max(x - lo, 0)])
	}
}

// 1D symmetric convolution (kernel length 2R+1) with clamped edges, in place.
@(private = "file")
ip_line_conv :: proc(line, tmp: []ip_P, kernel: []f32) {
	n := len(line)
	if n == 0 do return
	copy(tmp, line)
	R := len(kernel) / 2
	for x in 0 ..< n {
		acc: [4]f32
		for k in 0 ..< len(kernel) {
			acc += ip_f(tmp[clamp(x + k - R, 0, n - 1)]) * kernel[k]
		}
		line[x] = ip_r16(acc)
	}
}

@(private = "file")
ip_Op :: struct {
	kernel: []f32,
	nbox:   int,
	rad:    [3]int,
}

@(private = "file")
ip_line_op :: proc(line, tmp: []ip_P, op: ^ip_Op) {
	if op.kernel != nil do ip_line_conv(line, tmp, op.kernel)
	for k in 0 ..< op.nbox do ip_line_box(line, tmp, op.rad[k], op.rad[k])
}

// Runs `op` along every row then every column (columns processed in cache-friendly strips).
@(private = "file")
ip_sep_filter :: proc(buf: []ip_P, w, h: int, op: ^ip_Op) {
	tmp := make([]ip_P, max(w, h), context.temp_allocator)
	for y in 0 ..< h {
		ip_line_op(buf[y * w:(y + 1) * w], tmp[:w], op)
	}
	SW :: 16
	col := make([]ip_P, SW * h, context.temp_allocator)
	for x0 := 0; x0 < w; x0 += SW {
		sw := min(SW, w - x0)
		for y in 0 ..< h {
			row := buf[y * w + x0:]
			for c in 0 ..< sw do col[c * h + y] = row[c]
		}
		for c in 0 ..< sw do ip_line_op(col[c * h:(c + 1) * h], tmp[:h], op)
		for y in 0 ..< h {
			row := buf[y * w + x0:]
			for c in 0 ..< sw do row[c] = col[c * h + y]
		}
	}
}

// ---------------------------------------------------------------------------
// per-pixel adjustments (dst may alias src)
// ---------------------------------------------------------------------------

// GIMP-style brightness/contrast (-100..100): brightness scales toward black/white, contrast pivots on mid-grey.
adj_brightness_contrast :: proc(src, dst: []Color, brightness, contrast: int) {
	b := f32(clamp(brightness, -100, 100)) / 100
	c := f32(clamp(contrast, -100, 100)) / 100
	slant := math.tan((min(c, 0.995) + 1) * math.PI / 4)
	lut: [256]u8
	for i in 0 ..< 256 {
		v := f32(i) / 255
		if b < 0 {
			v *= 1 + b
		} else {
			v += (1 - v) * b
		}
		v = (v - 0.5) * slant + 0.5
		lut[i] = ip_u8(v)
	}
	ip_lut3(src, dst, &lut, &lut, &lut)
}

// Levels: input black/white points, gamma (0.1..10, >1 brightens), output range; channel 0 = RGB, 1 = R, 2 = G, 3 = B.
adj_levels :: proc(src, dst: []Color, in_lo, in_hi: int, gamma: f32, out_lo, out_hi: int, channel: int) {
	lo := f32(clamp(in_lo, 0, 255))
	hi := f32(clamp(in_hi, 0, 255))
	ig := 1 / clamp(gamma, 0.1, 10)
	olo := f32(clamp(out_lo, 0, 255))
	ohi := f32(clamp(out_hi, 0, 255))
	lut: [256]u8
	for i in 0 ..< 256 {
		v: f32
		if hi > lo {
			v = clamp((f32(i) - lo) / (hi - lo), 0, 1)
		} else {
			v = f32(i) >= lo ? 1 : 0
		}
		v = math.pow(v, ig)
		lut[i] = ip_u8i(olo + v * (ohi - olo))
	}
	id := ip_identity_lut()
	switch channel {
	case 1:
		ip_lut3(src, dst, &lut, &id, &id)
	case 2:
		ip_lut3(src, dst, &id, &lut, &id)
	case 3:
		ip_lut3(src, dst, &id, &id, &lut)
	case:
		ip_lut3(src, dst, &lut, &lut, &lut)
	}
}

// Builds a 256-entry curve LUT from control points (0..255 space, sorted by x) using monotone cubic (Fritsch-Carlson) interpolation, flat beyond the ends.
adj_curve_lut :: proc(points: []Vec2) -> [256]u8 {
	lut: [256]u8
	n0 := len(points)
	if n0 == 0 {
		return ip_identity_lut()
	}
	xs := make([]f32, n0, context.temp_allocator)
	ys := make([]f32, n0, context.temp_allocator)
	n := 0
	for p in points {
		if n > 0 && p.x <= xs[n - 1] do continue // skip unsorted / duplicate x
		xs[n] = p.x
		ys[n] = clamp(p.y, 0, 255)
		n += 1
	}
	if n == 1 {
		v := ip_u8i(ys[0])
		for i in 0 ..< 256 do lut[i] = v
		return lut
	}
	d := make([]f32, n, context.temp_allocator)
	m := make([]f32, n, context.temp_allocator)
	for k in 0 ..< n - 1 do d[k] = (ys[k + 1] - ys[k]) / (xs[k + 1] - xs[k])
	m[0] = d[0]
	m[n - 1] = d[n - 2]
	for k in 1 ..< n - 1 {
		m[k] = d[k - 1] * d[k] <= 0 ? 0 : (d[k - 1] + d[k]) * 0.5
	}
	for k in 0 ..< n - 1 {
		if d[k] == 0 {
			m[k] = 0
			m[k + 1] = 0
			continue
		}
		a := m[k] / d[k]
		b := m[k + 1] / d[k]
		s := a * a + b * b
		if s > 9 {
			t := 3 / math.sqrt(s)
			m[k] = t * a * d[k]
			m[k + 1] = t * b * d[k]
		}
	}
	seg := 0
	for i in 0 ..< 256 {
		x := f32(i)
		if x <= xs[0] {
			lut[i] = ip_u8i(ys[0])
			continue
		}
		if x >= xs[n - 1] {
			lut[i] = ip_u8i(ys[n - 1])
			continue
		}
		for seg < n - 2 && x > xs[seg + 1] do seg += 1
		hk := xs[seg + 1] - xs[seg]
		t := (x - xs[seg]) / hk
		t2 := t * t
		t3 := t2 * t
		v :=
			(2 * t3 - 3 * t2 + 1) * ys[seg] +
			(t3 - 2 * t2 + t) * hk * m[seg] +
			(-2 * t3 + 3 * t2) * ys[seg + 1] +
			(t3 - t2) * hk * m[seg + 1]
		lut[i] = ip_u8i(v)
	}
	return lut
}

// Applies per-channel LUTs (r, g, b) then the shared rgb LUT; any LUT may be nil.
adj_apply_luts :: proc(src, dst: []Color, rgb, r, g, b: ^[256]u8) {
	lr, lg, lb: [256]u8
	for i in 0 ..< 256 {
		vr := r != nil ? r^[i] : u8(i)
		vg := g != nil ? g^[i] : u8(i)
		vb := b != nil ? b^[i] : u8(i)
		if rgb != nil {
			vr, vg, vb = rgb^[vr], rgb^[vg], rgb^[vb]
		}
		lr[i], lg[i], lb[i] = vr, vg, vb
	}
	ip_lut3(src, dst, &lr, &lg, &lb)
}

// GIMP-style hue (-180..180) / saturation / lightness (-100..100) in HSL; colorize tints with `hue` at saturation (sat+100)/2 %.
adj_hue_sat_light :: proc(src, dst: []Color, hue, sat, light: int, colorize := false) {
	hs := f32(clamp(hue, -180, 180)) / 360
	ss := f32(clamp(sat, -100, 100)) / 100
	ls := f32(clamp(light, -100, 100)) / 100
	if !colorize && hs == 0 && ss == 0 && ls == 0 {
		ip_copy(src, dst)
		return
	}
	n := min(len(src), len(dst))
	ch := hs < 0 ? hs + 1 : hs
	cs := (ss + 1) * 0.5
	for i in 0 ..< n {
		c := src[i]
		r, g, b := f32(c[0]) / 255, f32(c[1]) / 255, f32(c[2]) / 255
		h, s, l: f32
		if colorize {
			h, s = ch, cs
			l = 0.2126 * r + 0.7152 * g + 0.0722 * b
		} else {
			h, s, l = ip_rgb_hsl(r, g, b)
			h += hs
			if h < 0 do h += 1
			if h >= 1 do h -= 1
			s = clamp(s * (1 + ss), 0, 1)
		}
		if ls < 0 {
			l *= 1 + ls
		} else {
			l += (1 - l) * ls
		}
		r, g, b = ip_hsl_rgb(h, s, l)
		dst[i] = Color{ip_u8(r), ip_u8(g), ip_u8(b), c[3]}
	}
}

// GIMP-style colour balance (-100..100 per axis) restricted to a tonal range (0 shadows, 1 midtones, 2 highlights), optionally preserving HSL lightness.
adj_color_balance :: proc(src, dst: []Color, cyan_red, magenta_green, yellow_blue: int, tone: int, preserve_lum := true) {
	cr := f32(clamp(cyan_red, -100, 100)) / 100
	mg := f32(clamp(magenta_green, -100, 100)) / 100
	yb := f32(clamp(yellow_blue, -100, 100)) / 100
	if cr == 0 && mg == 0 && yb == 0 {
		ip_copy(src, dst)
		return
	}
	// tonal mask per (max+min) sum, 0..510
	mask: [511]f32
	A :: 0.25
	B :: 0.333
	S :: 0.7
	for k in 0 ..< 511 {
		l := f32(k) / 510
		switch tone {
		case 0:
			mask[k] = clamp((l - B) / -A + 0.5, 0, 1) * S
		case 2:
			mask[k] = clamp((l + B - 1) / A + 0.5, 0, 1) * S
		case:
			mask[k] = clamp((l - B) / A + 0.5, 0, 1) * clamp((l + B - 1) / -A + 0.5, 0, 1) * S
		}
	}
	n := min(len(src), len(dst))
	for i in 0 ..< n {
		c := src[i]
		mx := max(c[0], c[1], c[2])
		mn := min(c[0], c[1], c[2])
		m := mask[int(mx) + int(mn)]
		r := clamp(f32(c[0]) / 255 + cr * m, 0, 1)
		g := clamp(f32(c[1]) / 255 + mg * m, 0, 1)
		b := clamp(f32(c[2]) / 255 + yb * m, 0, 1)
		if preserve_lum {
			h, s, _ := ip_rgb_hsl(r, g, b)
			r, g, b = ip_hsl_rgb(h, s, (f32(mx) + f32(mn)) / 510)
		}
		dst[i] = Color{ip_u8(r), ip_u8(g), ip_u8(b), c[3]}
	}
}

// Vibrance boosts muted colours more than saturated ones (and avoids clipping); saturation scales chroma uniformly. Both -100..100.
adj_vibrance :: proc(src, dst: []Color, vibrance, saturation: int) {
	v := f32(clamp(vibrance, -100, 100)) / 100
	ks := 1 + f32(clamp(saturation, -100, 100)) / 100
	if v == 0 && ks == 1 {
		ip_copy(src, dst)
		return
	}
	n := min(len(src), len(dst))
	for i in 0 ..< n {
		c := src[i]
		r, g, b := f32(c[0]) / 255, f32(c[1]) / 255, f32(c[2]) / 255
		mx := max(r, g, b)
		mn := min(r, g, b)
		y := 0.2126 * r + 0.7152 * g + 0.0722 * b
		kv := 1 + v * (1 - (mx - mn))
		if kv > 1 {
			// largest chroma scale that keeps every channel in gamut
			kmax := f32(1e9)
			if mx > y do kmax = min(kmax, (1 - y) / (mx - y))
			if mn < y do kmax = min(kmax, y / (y - mn))
			kv = max(1, min(kv, kmax))
		}
		k := kv * ks
		dst[i] = Color{ip_u8(y + (r - y) * k), ip_u8(y + (g - y) * k), ip_u8(y + (b - y) * k), c[3]}
	}
}

// Photographic exposure in linear light: stops (-5..5), additive offset (-0.5..0.5), then gamma (0.1..10, >1 brightens).
adj_exposure :: proc(src, dst: []Color, stops: f32, offset: f32, gamma: f32) {
	mul := math.pow(f32(2), clamp(stops, -5, 5))
	off := clamp(offset, -0.5, 0.5)
	ig := 1 / clamp(gamma, 0.1, 10)
	lut: [256]u8
	for i in 0 ..< 256 {
		l := ip_to_lin(f32(i) / 255) * mul + off
		l = math.pow(max(l, 0), ig)
		lut[i] = ip_u8(ip_to_srgb(l))
	}
	ip_lut3(src, dst, &lut, &lut, &lut)
}

// White balance in linear light: temperature (-100 cool .. 100 warm) and tint (-100 green .. 100 magenta), luminance-normalised.
adj_temperature :: proc(src, dst: []Color, temperature, tint: int) {
	t := f32(clamp(temperature, -100, 100)) / 100
	m := f32(clamp(tint, -100, 100)) / 100
	if t == 0 && m == 0 {
		ip_copy(src, dst)
		return
	}
	gr := math.pow(f32(2), 0.45 * t)
	gb := math.pow(f32(2), -0.45 * t)
	gg := math.pow(f32(2), -0.3 * m)
	y := 0.2126 * gr + 0.7152 * gg + 0.0722 * gb
	gr, gg, gb = gr / y, gg / y, gb / y
	lr, lg, lb: [256]u8
	for i in 0 ..< 256 {
		l := ip_to_lin(f32(i) / 255)
		lr[i] = ip_u8(ip_to_srgb(l * gr))
		lg[i] = ip_u8(ip_to_srgb(l * gg))
		lb[i] = ip_u8(ip_to_srgb(l * gb))
	}
	ip_lut3(src, dst, &lr, &lg, &lb)
}

// Reduces each channel to `levels` (2..64) evenly spaced values.
adj_posterize :: proc(src, dst: []Color, levels: int) {
	n := f32(clamp(levels, 2, 64) - 1)
	lut: [256]u8
	for i in 0 ..< 256 {
		lut[i] = ip_u8i(math.round(f32(i) * n / 255) * 255 / n)
	}
	ip_lut3(src, dst, &lut, &lut, &lut)
}

// Black/white by Rec.709 luminance: white when luma >= level (0..255).
adj_threshold :: proc(src, dst: []Color, level: int) {
	lv := clamp(level, 0, 255)
	n := min(len(src), len(dst))
	for i in 0 ..< n {
		c := src[i]
		y := (int(c[0]) * 2126 + int(c[1]) * 7152 + int(c[2]) * 722 + 5000) / 10000
		v: u8 = y >= lv ? 255 : 0
		dst[i] = Color{v, v, v, c[3]}
	}
}

// Inverts RGB.
adj_invert :: proc(src, dst: []Color) {
	n := min(len(src), len(dst))
	for i in 0 ..< n {
		c := src[i]
		dst[i] = Color{255 - c[0], 255 - c[1], 255 - c[2], c[3]}
	}
}

// Greyscale by perceptual Rec.709 luminance.
adj_desaturate :: proc(src, dst: []Color) {
	n := min(len(src), len(dst))
	for i in 0 ..< n {
		c := src[i]
		y := u8((int(c[0]) * 2126 + int(c[1]) * 7152 + int(c[2]) * 722 + 5000) / 10000)
		dst[i] = Color{y, y, y, c[3]}
	}
}

// Classic sepia tone matrix blended by amount (0..100).
adj_sepia :: proc(src, dst: []Color, amount: int) {
	t := f32(clamp(amount, 0, 100)) / 100
	if t == 0 {
		ip_copy(src, dst)
		return
	}
	n := min(len(src), len(dst))
	for i in 0 ..< n {
		c := src[i]
		r, g, b := f32(c[0]), f32(c[1]), f32(c[2])
		sr := 0.393 * r + 0.769 * g + 0.189 * b
		sg := 0.349 * r + 0.686 * g + 0.168 * b
		sb := 0.272 * r + 0.534 * g + 0.131 * b
		dst[i] = Color{ip_u8i(r + (sr - r) * t), ip_u8i(g + (sg - g) * t), ip_u8i(b + (sb - b) * t), c[3]}
	}
}

// ---------------------------------------------------------------------------
// spatial filters (dst must NOT alias src)
// ---------------------------------------------------------------------------

// Gaussian blur, radius = sigma in px (0..250); exact kernel below sigma 2, 3-pass box approximation above. Blurs alpha too.
filter_gaussian_blur :: proc(src, dst: []Color, w, h: int, radius: f32) {
	if !ip_ok(src, dst, w, h) do return
	n := w * h
	sigma := clamp(radius, 0, 250)
	if sigma < 0.05 {
		copy(dst[:n], src[:n])
		return
	}
	buf := ip_premul(src, n)
	op: ip_Op
	if sigma < 2 {
		R := int(math.ceil(sigma * 3))
		k := make([]f32, 2 * R + 1, context.temp_allocator)
		sum: f32
		for i in 0 ..< len(k) {
			x := f32(i - R)
			k[i] = math.exp(-x * x / (2 * sigma * sigma))
			sum += k[i]
		}
		for &v in k do v /= sum
		op.kernel = k
	} else {
		// Kovesi: box sizes whose 3-fold convolution matches sigma
		NB :: 3
		s2 := f64(sigma) * f64(sigma)
		wl := int(math.floor(math.sqrt(12 * s2 / NB + 1)))
		if wl % 2 == 0 do wl -= 1
		wu := wl + 2
		fwl := f64(wl)
		mi := int(math.round((12 * s2 - NB * fwl * fwl - 4 * NB * fwl - 3 * NB) / (-4 * fwl - 4)))
		op.nbox = NB
		for i in 0 ..< NB {
			op.rad[i] = ((i < mi ? wl : wu) - 1) / 2
		}
	}
	ip_sep_filter(buf, w, h, &op)
	ip_unpremul(buf, dst[:n])
}

// Square box blur of the given radius (window 2r+1), alpha-aware.
filter_box_blur :: proc(src, dst: []Color, w, h: int, radius: int) {
	if !ip_ok(src, dst, w, h) do return
	n := w * h
	r := clamp(radius, 0, 10000)
	if r == 0 {
		copy(dst[:n], src[:n])
		return
	}
	buf := ip_premul(src, n)
	op := ip_Op {
		nbox = 1,
		rad  = {r, 0, 0},
	}
	ip_sep_filter(buf, w, h, &op)
	ip_unpremul(buf, dst[:n])
}

// Linear motion blur of `distance` px total length along angle_deg (0 = horizontal, CCW); sliding box along pixel lines, O(pixels).
filter_motion_blur :: proc(src, dst: []Color, w, h: int, angle_deg: f32, distance: int) {
	if !ip_ok(src, dst, w, h) do return
	n := w * h
	th := angle_deg * math.PI / 180
	dx := math.cos(th)
	dy := -math.sin(th)
	horiz := abs(dx) >= abs(dy)
	steps := f32(clamp(distance, 0, 4000)) * (horiz ? abs(dx) : abs(dy))
	L := int(math.round(steps))
	if L <= 1 {
		copy(dst[:n], src[:n])
		return
	}
	buf := ip_premul(src, n)
	major := horiz ? w : h
	minor := horiz ? h : w
	slope := horiz ? dy / dx : dx / dy
	off := make([]int, major, context.temp_allocator)
	for t in 0 ..< major do off[t] = int(math.round(f32(t) * slope))
	omin := min(off[0], off[major - 1])
	omax := max(off[0], off[major - 1])
	line := make([]ip_P, major, context.temp_allocator)
	tmp := make([]ip_P, major, context.temp_allocator)
	idx := make([]int, major, context.temp_allocator)
	lo := (L - 1) / 2
	hi := L - 1 - lo
	// every pixel (t, s) lies on exactly one line k = s - off[t]
	for k in -omax ..< minor - omin {
		cnt := 0
		for t in 0 ..< major {
			s := k + off[t]
			if s < 0 || s >= minor do continue
			i := horiz ? s * w + t : t * w + s
			idx[cnt] = i
			line[cnt] = buf[i]
			cnt += 1
		}
		if cnt < 2 do continue
		ip_line_box(line[:cnt], tmp[:cnt], lo, hi)
		for j in 0 ..< cnt do buf[idx[j]] = line[j]
	}
	ip_unpremul(buf, dst[:n])
}

@(private = "file")
ip_zoom_pass :: proc(src, dst: []ip_P, w, h: int, cx, cy, s: f32, xi: []int, xf: []f32) {
	for x in 0 ..< w {
		qx := clamp(cx + (f32(x) - cx) * s, 0, f32(w - 1))
		x0 := min(int(qx), w - 1)
		xi[x] = x0
		xf[x] = qx - f32(x0)
	}
	for y in 0 ..< h {
		qy := clamp(cy + (f32(y) - cy) * s, 0, f32(h - 1))
		y0 := min(int(qy), h - 1)
		fy := qy - f32(y0)
		y1 := min(y0 + 1, h - 1)
		r0 := src[y0 * w:]
		r1 := src[y1 * w:]
		for x in 0 ..< w {
			x0 := xi[x]
			x1 := min(x0 + 1, w - 1)
			fx := xf[x]
			a := ip_f(r0[x0]) * (1 - fx) + ip_f(r0[x1]) * fx
			b := ip_f(r1[x0]) * (1 - fx) + ip_f(r1[x1]) * fx
			v := a * (1 - fy) + b * fy
			dst[y * w + x] = ip_r16((ip_f(src[y * w + x]) + v) * 0.5)
		}
	}
}

// Zoom blur toward (cx, cy) in pixels, amount 0..100; log-doubling passes so cost is O(pixels * log(blur length)).
filter_radial_blur :: proc(src, dst: []Color, w, h: int, cx, cy: f32, amount: int) {
	if !ip_ok(src, dst, w, h) do return
	n := w * h
	am := clamp(amount, 0, 100)
	smin := 1 - 0.6 * f32(am) / 100
	far: f32 = 0
	for p in ([4][2]f32{{0, 0}, {f32(w), 0}, {0, f32(h)}, {f32(w), f32(h)}}) {
		far = max(far, math.sqrt((p.x - cx) * (p.x - cx) + (p.y - cy) * (p.y - cy)))
	}
	D := far * (1 - smin)
	if am == 0 || D < 1 {
		copy(dst[:n], src[:n])
		return
	}
	passes := clamp(int(math.ceil(math.log2(D / 1.5))), 1, 12)
	lg := math.ln(smin)
	a := ip_premul(src, n)
	b := make([]ip_P, n, context.temp_allocator)
	xi := make([]int, w, context.temp_allocator)
	xf := make([]f32, w, context.temp_allocator)
	// pass i averages with the image scaled by smin^(1/2^i); together they form 2^passes evenly spaced taps
	for i in 1 ..= passes {
		s := math.exp(lg / f32(u32(1) << uint(i)))
		ip_zoom_pass(a, b, w, h, cx, cy, s, xi, xf)
		a, b = b, a
	}
	ip_unpremul(a, dst[:n])
}

// Unsharp mask: gaussian radius (sigma px), amount percent (0..500), threshold (0..255) on per-channel difference.
filter_unsharp_mask :: proc(src, dst: []Color, w, h: int, radius: f32, amount: int, threshold: int) {
	if !ip_ok(src, dst, w, h) do return
	n := w * h
	k := f32(clamp(amount, 0, 500)) / 100
	if k == 0 || radius < 0.05 {
		copy(dst[:n], src[:n])
		return
	}
	filter_gaussian_blur(src, dst, w, h, radius)
	th := clamp(threshold, 0, 255)
	for i in 0 ..< n {
		s := src[i]
		b := dst[i]
		o := s
		for c in 0 ..< 3 {
			d := int(s[c]) - int(b[c])
			if d != 0 && abs(d) >= th {
				o[c] = ip_u8i(f32(s[c]) + f32(d) * k)
			}
		}
		dst[i] = o
	}
}

// Adds deterministic gaussian-ish noise (amount 0..100 -> sigma up to ~90 levels); monochrome uses one value for all channels.
filter_add_noise :: proc(src, dst: []Color, w, h: int, amount: int, monochrome: bool, seed: u64) {
	if !ip_ok(src, dst, w, h) do return
	n := w * h
	sigma := f32(clamp(amount, 0, 100)) * 0.9
	if sigma == 0 {
		copy(dst[:n], src[:n])
		return
	}
	base := ip_mix64(seed) * 3
	for i in 0 ..< n {
		c := src[i]
		key := base + u64(i) * 3
		if monochrome {
			g := ip_gauss(ip_mix64(key)) * sigma
			dst[i] = Color{ip_u8i(f32(c[0]) + g), ip_u8i(f32(c[1]) + g), ip_u8i(f32(c[2]) + g), c[3]}
		} else {
			dst[i] = Color {
				ip_u8i(f32(c[0]) + ip_gauss(ip_mix64(key)) * sigma),
				ip_u8i(f32(c[1]) + ip_gauss(ip_mix64(key + 1)) * sigma),
				ip_u8i(f32(c[2]) + ip_gauss(ip_mix64(key + 2)) * sigma),
				c[3],
			}
		}
	}
}

@(private = "file")
ip_Med :: struct {
	hist:         [4][256]i32,
	med, lt:      [4]int,
	n_rgb, n_all: int,
}

@(private = "file")
ip_med_col :: #force_inline proc(st: ^ip_Med, src: []Color, w, x, y0, y1: int, $ADD: bool) {
	for yy in y0 ..= y1 {
		c := src[yy * w + x]
		d: i32 = ADD ? 1 : -1
		di := int(d)
		st.hist[3][c[3]] += d
		if int(c[3]) < st.med[3] do st.lt[3] += di
		st.n_all += di
		if c[3] != 0 {
			st.n_rgb += di
			for k in 0 ..< 3 {
				st.hist[k][c[k]] += d
				if int(c[k]) < st.med[k] do st.lt[k] += di
			}
		}
	}
}

@(private = "file")
ip_med_fix :: #force_inline proc(st: ^ip_Med) {
	for k in 0 ..< 4 {
		cnt := k == 3 ? st.n_all : st.n_rgb
		if cnt <= 0 do continue
		half := (cnt - 1) / 2
		m := st.med[k]
		lt := st.lt[k]
		for lt > half {
			m -= 1
			lt -= int(st.hist[k][m])
		}
		for lt + int(st.hist[k][m]) <= half {
			lt += int(st.hist[k][m])
			m += 1
		}
		st.med[k] = m
		st.lt[k] = lt
	}
}

// Per-channel median (radius 1..20, window clipped at edges) via Huang sliding histograms; RGB medians ignore fully transparent pixels.
filter_median :: proc(src, dst: []Color, w, h: int, radius: int) {
	if !ip_ok(src, dst, w, h) do return
	n := w * h
	r := clamp(radius, 0, 50)
	if r == 0 {
		copy(dst[:n], src[:n])
		return
	}
	st := new(ip_Med, context.temp_allocator)
	for y in 0 ..< h {
		y0 := max(0, y - r)
		y1 := min(h - 1, y + r)
		st^ = {}
		for x in 0 ..= min(r, w - 1) do ip_med_col(st, src, w, x, y0, y1, true)
		ip_med_fix(st)
		for x in 0 ..< w {
			i := y * w + x
			if st.n_rgb > 0 {
				dst[i] = Color{u8(st.med[0]), u8(st.med[1]), u8(st.med[2]), u8(st.med[3])}
			} else {
				c := src[i]
				dst[i] = Color{c[0], c[1], c[2], u8(st.med[3])}
			}
			if x - r >= 0 do ip_med_col(st, src, w, x - r, y0, y1, false)
			if x + r + 1 < w do ip_med_col(st, src, w, x + r + 1, y0, y1, true)
			ip_med_fix(st)
		}
	}
}

// Oil paint: each pixel takes the mean colour of the most common intensity bin (levels 4..64) in its (2r+1)^2 window (radius 1..15).
filter_oil_paint :: proc(src, dst: []Color, w, h: int, radius: int, levels: int) {
	if !ip_ok(src, dst, w, h) do return
	n := w * h
	r := clamp(radius, 0, 15)
	if r == 0 {
		copy(dst[:n], src[:n])
		return
	}
	L := clamp(levels, 4, 64)
	bins := make([]u8, n, context.temp_allocator)
	for i in 0 ..< n {
		c := src[i]
		bins[i] = u8((u32(c[0]) + u32(c[1]) + u32(c[2])) * u32(L) / 766)
	}
	cnt: [64]u32
	sum: [64][3]u32
	for y in 0 ..< h {
		y0 := max(0, y - r)
		y1 := min(h - 1, y + r)
		cnt = {}
		sum = {}
		for x in 0 ..= min(r, w - 1) {
			for yy in y0 ..= y1 {
				i := yy * w + x
				c := src[i]
				a := u32(c[3])
				b := bins[i]
				cnt[b] += a
				sum[b] += {u32(c[0]) * a, u32(c[1]) * a, u32(c[2]) * a}
			}
		}
		for x in 0 ..< w {
			best := 0
			bc := cnt[0]
			for k in 1 ..< L {
				if cnt[k] > bc {
					bc = cnt[k]
					best = k
				}
			}
			i := y * w + x
			if bc == 0 {
				dst[i] = src[i]
			} else {
				s := sum[best]
				hb := bc / 2
				dst[i] = Color{u8((s[0] + hb) / bc), u8((s[1] + hb) / bc), u8((s[2] + hb) / bc), src[i][3]}
			}
			if x - r >= 0 {
				for yy in y0 ..= y1 {
					j := yy * w + x - r
					c := src[j]
					a := u32(c[3])
					b := bins[j]
					cnt[b] -= a
					sum[b] -= {u32(c[0]) * a, u32(c[1]) * a, u32(c[2]) * a}
				}
			}
			if x + r + 1 < w {
				for yy in y0 ..= y1 {
					j := yy * w + x + r + 1
					c := src[j]
					a := u32(c[3])
					b := bins[j]
					cnt[b] += a
					sum[b] += {u32(c[0]) * a, u32(c[1]) * a, u32(c[2]) * a}
				}
			}
		}
	}
}

// Alpha-weighted moments for Kuwahara: weight, r, g, b, luma, luma^2.
@(private = "file")
ip_KV :: [6]i64

@(private = "file")
ip_kv :: #force_inline proc(c: Color) -> ip_KV {
	a := i64(c[3])
	l := i64(ip_luma(c))
	return {a, i64(c[0]) * a, i64(c[1]) * a, i64(c[2]) * a, l * a, l * l * a}
}

// Kuwahara painterly smoothing (radius 1..15): mean of the lowest-variance quadrant; rolling column sums + row prefix sums, cost independent of radius.
filter_kuwahara :: proc(src, dst: []Color, w, h: int, radius: int) {
	if !ip_ok(src, dst, w, h) do return
	n := w * h
	r := clamp(radius, 0, 100)
	if r == 0 {
		copy(dst[:n], src[:n])
		return
	}
	up := make([]ip_KV, w, context.temp_allocator) // column sums over rows [y-r, y]
	dn := make([]ip_KV, w, context.temp_allocator) // column sums over rows [y, y+r]
	pu := make([]ip_KV, w + 1, context.temp_allocator)
	pd := make([]ip_KV, w + 1, context.temp_allocator)
	for x in 0 ..< w do up[x] = ip_kv(src[x])
	for yy in 0 ..= min(r, h - 1) {
		for x in 0 ..< w do dn[x] += ip_kv(src[yy * w + x])
	}
	for y in 0 ..< h {
		if y > 0 {
			for x in 0 ..< w {
				up[x] += ip_kv(src[y * w + x])
				if y - r - 1 >= 0 do up[x] -= ip_kv(src[(y - r - 1) * w + x])
				dn[x] -= ip_kv(src[(y - 1) * w + x])
				if y + r < h do dn[x] += ip_kv(src[(y + r) * w + x])
			}
		}
		for x in 0 ..< w {
			pu[x + 1] = pu[x] + up[x]
			pd[x + 1] = pd[x] + dn[x]
		}
		for x in 0 ..< w {
			xl := max(0, x - r)
			xr := min(w, x + r + 1)
			q := [4]ip_KV{pu[x + 1] - pu[xl], pu[xr] - pu[x], pd[x + 1] - pd[xl], pd[xr] - pd[x]}
			best := -1
			bv := max(f64)
			for k in 0 ..< 4 {
				W := q[k][0]
				if W <= 0 do continue
				fw := f64(W)
				m := f64(q[k][4]) / fw
				v := f64(q[k][5]) / fw - m * m
				if v < bv {
					bv = v
					best = k
				}
			}
			i := y * w + x
			if best < 0 {
				dst[i] = src[i]
			} else {
				s := q[best]
				W := s[0]
				hw := W / 2
				dst[i] = Color{u8((s[1] + hw) / W), u8((s[2] + hw) / W), u8((s[3] + hw) / W), src[i][3]}
			}
		}
	}
}

// Emboss lit from angle_deg (0 = from the right, 90 = from above) with strength 1..10; keep_color adds the relief to the image instead of grey.
filter_emboss :: proc(src, dst: []Color, w, h: int, angle_deg: f32, strength: int, keep_color: bool) {
	if !ip_ok(src, dst, w, h) do return
	n := w * h
	hg := make([]i32, n, context.temp_allocator)
	for i in 0 ..< n {
		c := src[i]
		hg[i] = i32(ip_luma(c) * u32(c[3]) / 255) // premultiplied height so alpha edges emboss too
	}
	th := angle_deg * math.PI / 180
	lx := math.cos(th)
	ly := -math.sin(th)
	k := f32(clamp(strength, 1, 10)) * 0.1
	for y in 0 ..< h {
		rm := hg[max(y - 1, 0) * w:]
		r0 := hg[y * w:]
		rp := hg[min(y + 1, h - 1) * w:]
		for x in 0 ..< w {
			xm := max(x - 1, 0)
			xp := min(x + 1, w - 1)
			gx := (rm[xp] + 2 * r0[xp] + rp[xp]) - (rm[xm] + 2 * r0[xm] + rp[xm])
			gy := (rp[xm] + 2 * rp[x] + rp[xp]) - (rm[xm] + 2 * rm[x] + rm[xp])
			shade := -(f32(gx) * lx + f32(gy) * ly) * k
			c := src[y * w + x]
			if keep_color {
				dst[y * w + x] = Color{ip_u8i(f32(c[0]) + shade), ip_u8i(f32(c[1]) + shade), ip_u8i(f32(c[2]) + shade), c[3]}
			} else {
				g := ip_u8i(128 + shade)
				dst[y * w + x] = Color{g, g, g, c[3]}
			}
		}
	}
}

// Per-channel Sobel edge magnitude on premultiplied colour, inverted (dark lines on white) like Photoshop's Find Edges.
filter_find_edges :: proc(src, dst: []Color, w, h: int) {
	if !ip_ok(src, dst, w, h) do return
	n := w * h
	pm := make([][4]i32, n, context.temp_allocator)
	for i in 0 ..< n {
		c := src[i]
		a := i32(c[3])
		pm[i] = {(i32(c[0]) * a + 127) / 255, (i32(c[1]) * a + 127) / 255, (i32(c[2]) * a + 127) / 255, 0}
	}
	for y in 0 ..< h {
		rm := pm[max(y - 1, 0) * w:]
		r0 := pm[y * w:]
		rp := pm[min(y + 1, h - 1) * w:]
		for x in 0 ..< w {
			xm := max(x - 1, 0)
			xp := min(x + 1, w - 1)
			gx := (rm[xp] + 2 * r0[xp] + rp[xp]) - (rm[xm] + 2 * r0[xm] + rp[xm])
			gy := (rp[xm] + 2 * rp[x] + rp[xp]) - (rm[xm] + 2 * rm[x] + rm[xp])
			o: Color
			for c in 0 ..< 3 {
				m := math.sqrt(f32(gx[c] * gx[c] + gy[c] * gy[c])) * 0.5
				o[c] = ip_u8i(255 - m)
			}
			o[3] = src[y * w + x][3]
			dst[y * w + x] = o
		}
	}
}

// Mosaic: replaces each cell x cell block (2..256, grid anchored at 0,0) with its alpha-weighted average; alpha becomes the block average.
filter_pixelate :: proc(src, dst: []Color, w, h: int, cell: int) {
	if !ip_ok(src, dst, w, h) do return
	n := w * h
	cs := clamp(cell, 1, 4096)
	if cs <= 1 {
		copy(dst[:n], src[:n])
		return
	}
	ncx := (w + cs - 1) / cs
	sums := make([][4]u64, ncx, context.temp_allocator)
	cols := make([]Color, ncx, context.temp_allocator)
	for y0 := 0; y0 < h; y0 += cs {
		y1 := min(y0 + cs, h)
		for &s in sums do s = {}
		for y in y0 ..< y1 {
			row := src[y * w:]
			for cx in 0 ..< ncx {
				s: [4]u64
				for x in cx * cs ..< min(cx * cs + cs, w) {
					c := row[x]
					a := u64(c[3])
					s += {u64(c[0]) * a, u64(c[1]) * a, u64(c[2]) * a, a}
				}
				sums[cx] += s
			}
		}
		for cx in 0 ..< ncx {
			s := sums[cx]
			A := s[3]
			if A == 0 {
				cols[cx] = Color{0, 0, 0, 0}
				continue
			}
			cnt := u64((min(cx * cs + cs, w) - cx * cs) * (y1 - y0))
			cols[cx] = Color{u8((s[0] + A / 2) / A), u8((s[1] + A / 2) / A), u8((s[2] + A / 2) / A), u8((A + cnt / 2) / cnt)}
		}
		for y in y0 ..< y1 {
			row := dst[y * w:]
			for cx in 0 ..< ncx {
				c := cols[cx]
				for x in cx * cs ..< min(cx * cs + cs, w) do row[x] = c
			}
		}
	}
}

// Elliptical vignette: amount -100..100 (positive darkens, negative lightens edges), softness 0..100 widens the falloff.
filter_vignette :: proc(src, dst: []Color, w, h: int, amount: int, softness: int) {
	if !ip_ok(src, dst, w, h) do return
	n := w * h
	amt := f32(clamp(amount, -100, 100)) / 100
	if amt == 0 {
		copy(dst[:n], src[:n])
		return
	}
	s := f32(clamp(softness, 0, 100)) / 100
	e0 := 1 - 0.85 * s - 0.02
	e1 := 1 + 0.4 * s + 0.02
	ihw := 2 / f32(w)
	ihh := 2 / f32(h)
	for y in 0 ..< h {
		ny := (f32(y) + 0.5 - f32(h) * 0.5) * ihh
		for x in 0 ..< w {
			nx := (f32(x) + 0.5 - f32(w) * 0.5) * ihw
			m := ip_smooth(e0, e1, math.sqrt(nx * nx + ny * ny)) * amt
			c := src[y * w + x]
			o := c
			for k in 0 ..< 3 {
				v := f32(c[k])
				o[k] = m > 0 ? ip_u8i(v * (1 - m)) : ip_u8i(v + (255 - v) * -m)
			}
			dst[y * w + x] = o
		}
	}
}

// Woven plain-weave height at tile-local pixel (x, y); thread width T, N threads per tile (even, so the tile wraps).
@(private = "file")
ip_weave_h :: proc(x, y, T: int) -> f32 {
	fx := (f32(x) + 0.5) / f32(T)
	fy := (f32(y) + 0.5) / f32(T)
	ix := int(fx)
	iy := int(fy)
	u := fx - f32(ix)
	v := fy - f32(iy)
	tw := 0.8 + 0.4 * ip_hash01(u64(ix) * 2 + 7)
	tf := 0.8 + 0.4 * ip_hash01(u64(iy) * 2 + 1000003)
	// warp (vertical) is over where ix+iy is even, weft (horizontal) where odd
	along_w := 0.5 + 0.5 * math.sin(math.PI * (fy + f32(ix)))
	along_f := 0.5 - 0.5 * math.sin(math.PI * (fx + f32(iy)))
	hw := math.sin(math.PI * u) * (0.5 + 0.5 * along_w) * tw
	hf := math.sin(math.PI * v) * (0.5 + 0.5 * along_f) * tf
	fiber := ip_hash01(u64(x) * 7919 + u64(y) * 104729 + 17) * 0.08
	return max(hw, hf) + fiber
}

// Embosses a deterministic woven canvas texture (scale 1..8 sets thread size, strength 0..100), lit from the top-left.
filter_canvas_texture :: proc(src, dst: []Color, w, h: int, scale: int, strength: int) {
	if !ip_ok(src, dst, w, h) do return
	n := w * h
	k := f32(clamp(strength, 0, 100)) / 100 * 55
	if k == 0 {
		copy(dst[:n], src[:n])
		return
	}
	T := 2 + 2 * clamp(scale, 1, 8)
	NT :: 16
	S := T * NT
	hm := make([]f32, S * S, context.temp_allocator)
	for y in 0 ..< S {
		for x in 0 ..< S do hm[y * S + x] = ip_weave_h(x, y, T)
	}
	sh := make([]f32, S * S, context.temp_allocator)
	norm := f32(T) * 0.25
	for y in 0 ..< S {
		ym := (y + S - 1) % S
		yp := (y + 1) % S
		for x in 0 ..< S {
			xm := (x + S - 1) % S
			xp := (x + 1) % S
			slope := (hm[yp * S + xp] - hm[ym * S + xm]) * norm
			sh[y * S + x] = (clamp(slope, -1.5, 1.5) * 0.8 + (hm[y * S + x] - 0.6) * 0.35) * k
		}
	}
	for y in 0 ..< h {
		trow := sh[(y % S) * S:]
		for x in 0 ..< w {
			d := trow[x % S]
			c := src[y * w + x]
			dst[y * w + x] = Color{ip_u8i(f32(c[0]) + d), ip_u8i(f32(c[1]) + d), ip_u8i(f32(c[2]) + d), c[3]}
		}
	}
}
