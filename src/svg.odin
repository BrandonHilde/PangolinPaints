package pangolin

import "core:math"
import "core:strconv"
import "core:strings"

// ---------------------------------------------------------------------------
// A small SVG rasterizer for the UI icons (assets/icons) and the logo (assets/logo.svg).
// It reads what those files use: <svg viewBox>, <g>, <path>, <circle>, <ellipse>, <rect> (rx),
// <line>, <polyline> and <polygon>; fill, stroke, stroke-width, opacity, fill-opacity,
// stroke-opacity, fill-rule, transform and the same properties inside style="...".
// currentColor is white, so icons can be tinted when drawn. Strokes always get round caps and
// joins. Coverage comes from each pixel's distance to the outline, which stays crisp at icon sizes.
// ---------------------------------------------------------------------------

@(private = "file")
Svg_Style :: struct {
	fill, stroke:         Color,
	has_fill, has_stroke: bool,
	width:                f32,
	opacity:              f32,
	fill_op, stroke_op:   f32,
	evenodd:              bool,
	xf:                   Affine,
}

@(private = "file")
Svg_Poly :: struct {
	pts:    [dynamic]Vec2,
	closed: bool,
}

// Renders `src` into a w*h image (straight alpha). The viewBox is scaled to fit.
svg_render :: proc(src: string, w, h: int, allocator := context.allocator) -> []Color {
	acc := make([][4]f32, w * h, context.temp_allocator) // premultiplied
	stack := make([dynamic]Svg_Style, context.temp_allocator)
	append(&stack, Svg_Style{fill = WHITE, has_fill = true, stroke = WHITE, width = 1, opacity = 1, fill_op = 1, stroke_op = 1, xf = AFFINE_ID})

	s := src
	for {
		lt := strings.index_byte(s, '<')
		if lt < 0 do break
		s = s[lt + 1:]
		if strings.has_prefix(s, "!--") {
			end := strings.index(s, "-->")
			if end < 0 do break
			s = s[end + 3:]
			continue
		}
		gt := strings.index_byte(s, '>')
		if gt < 0 do break
		tag := s[:gt]
		s = s[gt + 1:]
		if len(tag) == 0 || tag[0] == '?' || tag[0] == '!' do continue
		if tag[0] == '/' {
			name := strings.trim_space(tag[1:])
			if (name == "g" || name == "svg") && len(stack) > 1 do pop(&stack)
			continue
		}
		self_closing := strings.has_suffix(tag, "/")
		if self_closing do tag = tag[:len(tag) - 1]
		name_end := 0
		for name_end < len(tag) && !is_space(tag[name_end]) do name_end += 1
		name := tag[:name_end]
		attrs := svg_attrs(tag[name_end:])

		st := stack[len(stack) - 1]
		if name == "svg" {
			// map the viewBox onto the output, keeping its aspect ratio
			if vb, ok := attrs["viewBox"]; ok {
				v: [4]f32
				nums := vb
				for k in 0 ..< 4 do v[k], _ = svg_number(&nums)
				if v[2] > 0 && v[3] > 0 {
					sc := min(f32(w) / v[2], f32(h) / v[3])
					ox := (f32(w) - v[2] * sc) / 2 - v[0] * sc
					oy := (f32(h) - v[3] * sc) / 2 - v[1] * sc
					st.xf = Affine{sc, 0, 0, sc, ox, oy}
				}
			}
		}
		svg_apply_style(&st, attrs)
		switch name {
		case "svg", "g":
			if !self_closing do append(&stack, st)
		case "path", "circle", "ellipse", "rect", "line", "polyline", "polygon":
			polys := svg_shape(name, attrs, st.xf)
			svg_draw(acc, w, h, polys[:], st)
		}
	}

	out := make([]Color, w * h, allocator)
	for p, i in acc {
		a := clamp(p[3], 0, 1)
		if a <= 0 do continue
		out[i] = Color{u8(clamp(p[0] / a, 0, 1) * 255 + 0.5), u8(clamp(p[1] / a, 0, 1) * 255 + 0.5), u8(clamp(p[2] / a, 0, 1) * 255 + 0.5), u8(a * 255 + 0.5)}
	}
	return out
}

@(private = "file")
is_space :: #force_inline proc(c: u8) -> bool {
	return c == ' ' || c == '\t' || c == '\n' || c == '\r'
}

@(private = "file")
svg_attrs :: proc(s: string) -> map[string]string {
	m := make(map[string]string, 8, context.temp_allocator)
	i := 0
	for i < len(s) {
		for i < len(s) && is_space(s[i]) do i += 1
		k0 := i
		for i < len(s) && s[i] != '=' && !is_space(s[i]) do i += 1
		key := s[k0:i]
		for i < len(s) && (is_space(s[i]) || s[i] == '=') do i += 1
		if i >= len(s) || (s[i] != '"' && s[i] != '\'') do break
		q := s[i]
		i += 1
		v0 := i
		for i < len(s) && s[i] != q do i += 1
		m[key] = s[v0:min(i, len(s))]
		i += 1
	}
	// properties in style="a:b; c:d" behave like attributes
	if style, ok := m["style"]; ok {
		for decl in strings.split(style, ";", context.temp_allocator) {
			kv := strings.split_n(decl, ":", 2, context.temp_allocator)
			if len(kv) == 2 do m[strings.trim_space(kv[0])] = strings.trim_space(kv[1])
		}
	}
	return m
}

@(private = "file")
svg_color :: proc(v: string) -> (Color, bool) {
	switch v {
	case "none", "transparent":
		return {}, false
	case "currentColor", "white":
		return WHITE, true
	case "black":
		return BLACK, true
	}
	if len(v) == 4 && v[0] == '#' {
		// #rgb
		long := [7]u8{'#', v[1], v[1], v[2], v[2], v[3], v[3]}
		if c, ok := parse_hex(string(long[:])); ok do return c, true
	}
	if c, ok := parse_hex(v); ok do return c, true
	return WHITE, true
}

@(private = "file")
svg_apply_style :: proc(st: ^Svg_Style, attrs: map[string]string) {
	f32_attr :: proc(attrs: map[string]string, key: string, v: ^f32) {
		if s, ok := attrs[key]; ok {
			if n, ok2 := strconv.parse_f32(strings.trim_suffix(strings.trim_space(s), "px")); ok2 do v^ = n
		}
	}
	if v, ok := attrs["fill"]; ok do st.fill, st.has_fill = svg_color(v)
	if v, ok := attrs["stroke"]; ok do st.stroke, st.has_stroke = svg_color(v)
	if v, ok := attrs["fill-rule"]; ok do st.evenodd = v == "evenodd"
	f32_attr(attrs, "stroke-width", &st.width)
	f32_attr(attrs, "fill-opacity", &st.fill_op)
	f32_attr(attrs, "stroke-opacity", &st.stroke_op)
	op: f32 = 1
	f32_attr(attrs, "opacity", &op)
	st.opacity *= op
	if v, ok := attrs["transform"]; ok do st.xf = affine_mul(st.xf, svg_transform(v))
}

// m then n: points go through n first.
@(private = "file")
affine_mul :: proc(m, n: Affine) -> Affine {
	return Affine {
		a = m.a * n.a + m.b * n.c,
		b = m.a * n.b + m.b * n.d,
		c = m.c * n.a + m.d * n.c,
		d = m.c * n.b + m.d * n.d,
		e = m.a * n.e + m.b * n.f + m.e,
		f = m.c * n.e + m.d * n.f + m.f,
	}
}

@(private = "file")
svg_transform :: proc(v: string) -> Affine {
	m := AFFINE_ID
	s := v
	for {
		open := strings.index_byte(s, '(')
		close := strings.index_byte(s, ')')
		if open < 0 || close < open do break
		fn := strings.trim_space(s[:open])
		args := s[open + 1:close]
		s = s[close + 1:]
		a: [6]f32
		n := 0
		for n < 6 {
			x, ok := svg_number(&args)
			if !ok do break
			a[n] = x
			n += 1
		}
		t := AFFINE_ID
		switch fn {
		case "translate":
			t.e, t.f = a[0], a[1]
		case "scale":
			t.a, t.d = a[0], n > 1 ? a[1] : a[0]
		case "rotate":
			r := a[0] * math.PI / 180
			cs, sn := math.cos(r), math.sin(r)
			t = Affine{cs, -sn, sn, cs, 0, 0}
			if n == 3 {
				// about (cx, cy)
				t = affine_mul(affine_mul(Affine{1, 0, 0, 1, a[1], a[2]}, t), Affine{1, 0, 0, 1, -a[1], -a[2]})
			}
		case "matrix":
			t = Affine{a[0], a[2], a[1], a[3], a[4], a[5]}
		}
		m = affine_mul(m, t)
	}
	return m
}

// Reads the next number from `s` (separators: spaces, commas; "1.5.5" is two numbers).
@(private = "file")
svg_number :: proc(s: ^string) -> (f32, bool) {
	i := 0
	t := s^
	for i < len(t) && (is_space(t[i]) || t[i] == ',') do i += 1
	start := i
	if i < len(t) && (t[i] == '-' || t[i] == '+') do i += 1
	dot := false
	digits := false
	for i < len(t) {
		c := t[i]
		if c >= '0' && c <= '9' {
			digits = true
		} else if c == '.' && !dot {
			dot = true
		} else {
			break
		}
		i += 1
	}
	if digits && i < len(t) && (t[i] == 'e' || t[i] == 'E') {
		j := i + 1
		if j < len(t) && (t[j] == '-' || t[j] == '+') do j += 1
		if j < len(t) && t[j] >= '0' && t[j] <= '9' {
			i = j
			for i < len(t) && t[i] >= '0' && t[i] <= '9' do i += 1
		}
	}
	if !digits {
		return 0, false
	}
	v, _ := strconv.parse_f32(t[start:i])
	s^ = t[i:]
	return v, true
}

// Arc flags may be written without separators ("a2 2 0 011 1").
@(private = "file")
svg_flag :: proc(s: ^string) -> bool {
	t := s^
	i := 0
	for i < len(t) && (is_space(t[i]) || t[i] == ',') do i += 1
	if i >= len(t) do return false
	s^ = t[i + 1:]
	return t[i] == '1'
}

@(private = "file")
attr_f :: proc(attrs: map[string]string, key: string) -> f32 {
	if s, ok := attrs[key]; ok {
		t := s
		v, _ := svg_number(&t)
		return v
	}
	return 0
}

// Turns an element into polylines in output pixels.
@(private = "file")
svg_shape :: proc(name: string, attrs: map[string]string, xf: Affine) -> [dynamic]Svg_Poly {
	polys := make([dynamic]Svg_Poly, context.temp_allocator)
	// curve flattening: a step every ~1.5 output pixels
	scale := math.sqrt(abs(xf.a * xf.d - xf.b * xf.c))
	start_poly :: proc(polys: ^[dynamic]Svg_Poly, p: Vec2) -> ^Svg_Poly {
		append(polys, Svg_Poly{pts = make([dynamic]Vec2, context.temp_allocator)})
		q := &polys[len(polys) - 1]
		append(&q.pts, p)
		return q
	}
	put :: proc(q: ^Svg_Poly, xf: Affine, p: Vec2) {
		append(&q.pts, affine_apply(xf, p))
	}
	ellipse :: proc(polys: ^[dynamic]Svg_Poly, xf: Affine, scale, cx, cy, rx, ry: f32) {
		if rx <= 0 || ry <= 0 do return
		n := clamp(int(math.TAU * max(rx, ry) * scale / 1.5), 12, 160)
		q := start_poly(polys, affine_apply(xf, {cx + rx, cy}))
		for k in 1 ..< n {
			a := f32(k) / f32(n) * math.TAU
			put(q, xf, {cx + rx * math.cos(a), cy + ry * math.sin(a)})
		}
		q.closed = true
	}
	switch name {
	case "circle":
		r := attr_f(attrs, "r")
		ellipse(&polys, xf, scale, attr_f(attrs, "cx"), attr_f(attrs, "cy"), r, r)
	case "ellipse":
		ellipse(&polys, xf, scale, attr_f(attrs, "cx"), attr_f(attrs, "cy"), attr_f(attrs, "rx"), attr_f(attrs, "ry"))
	case "line":
		q := start_poly(&polys, affine_apply(xf, {attr_f(attrs, "x1"), attr_f(attrs, "y1")}))
		put(q, xf, {attr_f(attrs, "x2"), attr_f(attrs, "y2")})
	case "polyline", "polygon":
		s := attrs["points"]
		x, okx := svg_number(&s)
		y, oky := svg_number(&s)
		if !okx || !oky do break
		q := start_poly(&polys, affine_apply(xf, {x, y}))
		for {
			x, okx = svg_number(&s)
			y, oky = svg_number(&s)
			if !okx || !oky do break
			put(q, xf, {x, y})
		}
		q.closed = name == "polygon"
	case "rect":
		x, y := attr_f(attrs, "x"), attr_f(attrs, "y")
		w, h := attr_f(attrs, "width"), attr_f(attrs, "height")
		_, has_rx := attrs["rx"]
		_, has_ry := attrs["ry"]
		rx, ry := attr_f(attrs, "rx"), attr_f(attrs, "ry")
		if !has_ry do ry = rx
		if !has_rx do rx = ry
		rx, ry = min(rx, w / 2), min(ry, h / 2)
		if rx <= 0 || ry <= 0 {
			q := start_poly(&polys, affine_apply(xf, {x, y}))
			put(q, xf, {x + w, y})
			put(q, xf, {x + w, y + h})
			put(q, xf, {x, y + h})
			q.closed = true
			break
		}
		// rounded: quarter ellipses at the corners
		q := start_poly(&polys, affine_apply(xf, {x + rx, y}))
		n := clamp(int(max(rx, ry) * scale / 1.2), 3, 32)
		corners := [4][4]f32{{x + w - rx, y + ry, -90, 0}, {x + w - rx, y + h - ry, 0, 90}, {x + rx, y + h - ry, 90, 180}, {x + rx, y + ry, 180, 270}}
		for c in corners {
			for k in 0 ..= n {
				a := (c[2] + (c[3] - c[2]) * f32(k) / f32(n)) * math.PI / 180
				put(q, xf, {c[0] + rx * math.cos(a), c[1] + ry * math.sin(a)})
			}
		}
		q.closed = true
	case "path":
		svg_path(&polys, attrs["d"], xf, scale)
	}
	return polys
}

@(private = "file")
svg_path :: proc(polys: ^[dynamic]Svg_Poly, d: string, xf: Affine, scale: f32) {
	s := d
	cmd: u8 = 0
	p, start, ctrl: Vec2 // current point, subpath start, last control point (for S / T)
	last_curve: u8 = 0
	q: ^Svg_Poly
	begin :: proc(polys: ^[dynamic]Svg_Poly, xf: Affine, p: Vec2) -> ^Svg_Poly {
		append(polys, Svg_Poly{pts = make([dynamic]Vec2, context.temp_allocator)})
		r := &polys[len(polys) - 1]
		append(&r.pts, affine_apply(xf, p))
		return r
	}
	steps :: proc(scale: f32, pts: ..Vec2) -> int {
		l: f32
		for i in 1 ..< len(pts) do l += math.sqrt((pts[i].x - pts[i - 1].x) * (pts[i].x - pts[i - 1].x) + (pts[i].y - pts[i - 1].y) * (pts[i].y - pts[i - 1].y))
		return clamp(int(l * scale / 1.5), 2, 64)
	}
	for {
		// next command letter, or an implicit repeat of the last one
		t := s
		i := 0
		for i < len(t) && (is_space(t[i]) || t[i] == ',') do i += 1
		if i >= len(t) do break
		c := t[i]
		if (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') {
			cmd = c
			s = t[i + 1:]
		} else if cmd == 0 {
			break
		} else if cmd == 'M' {
			cmd = 'L'
		} else if cmd == 'm' {
			cmd = 'l'
		}
		rel := cmd >= 'a'
		base := rel ? p : Vec2{}
		up := cmd >= 'a' ? cmd - 32 : cmd
		ok := true
		num :: proc(s: ^string, ok: ^bool) -> f32 {
			v, good := svg_number(s)
			if !good do ok^ = false
			return v
		}
		if q == nil && up != 'M' {
			q = begin(polys, xf, p)
		}
		switch up {
		case 'M':
			x := num(&s, &ok)
			y := num(&s, &ok)
			if !ok do return
			p = base + {x, y}
			start = p
			q = begin(polys, xf, p)
		case 'L':
			x := num(&s, &ok)
			y := num(&s, &ok)
			if !ok do return
			p = base + {x, y}
			append(&q.pts, affine_apply(xf, p))
		case 'H':
			x := num(&s, &ok)
			if !ok do return
			p.x = (rel ? p.x : 0) + x
			append(&q.pts, affine_apply(xf, p))
		case 'V':
			y := num(&s, &ok)
			if !ok do return
			p.y = (rel ? p.y : 0) + y
			append(&q.pts, affine_apply(xf, p))
		case 'C', 'S':
			c1: Vec2
			if up == 'C' {
				c1 = base + {num(&s, &ok), num(&s, &ok)}
			} else {
				c1 = last_curve == 'C' ? 2 * p - ctrl : p
			}
			c2 := base + Vec2{num(&s, &ok), num(&s, &ok)}
			e := base + Vec2{num(&s, &ok), num(&s, &ok)}
			if !ok do return
			n := steps(scale, p, c1, c2, e)
			for k in 1 ..= n {
				u := f32(k) / f32(n)
				v := 1 - u
				pt := v * v * v * p + 3 * v * v * u * c1 + 3 * v * u * u * c2 + u * u * u * e
				append(&q.pts, affine_apply(xf, pt))
			}
			ctrl, p = c2, e
		case 'Q', 'T':
			c1: Vec2
			if up == 'Q' {
				c1 = base + {num(&s, &ok), num(&s, &ok)}
			} else {
				c1 = last_curve == 'Q' ? 2 * p - ctrl : p
			}
			e := base + Vec2{num(&s, &ok), num(&s, &ok)}
			if !ok do return
			n := steps(scale, p, c1, e)
			for k in 1 ..= n {
				u := f32(k) / f32(n)
				v := 1 - u
				append(&q.pts, affine_apply(xf, v * v * p + 2 * v * u * c1 + u * u * e))
			}
			ctrl, p = c1, e
		case 'A':
			rx := abs(num(&s, &ok))
			ry := abs(num(&s, &ok))
			rot := num(&s, &ok)
			large := svg_flag(&s)
			sweep := svg_flag(&s)
			e := base + Vec2{num(&s, &ok), num(&s, &ok)}
			if !ok do return
			svg_arc(q, xf, scale, p, e, rx, ry, rot, large, sweep)
			p = e
		case 'Z':
			q.closed = true
			p = start
			q = nil // a command after Z without M starts a new subpath at the start point
		case:
			return
		}
		last_curve = up == 'S' ? 'C' : (up == 'T' ? 'Q' : up)
	}
}

// SVG endpoint arc -> centre parametrisation (SVG spec, appendix F.6).
@(private = "file")
svg_arc :: proc(q: ^Svg_Poly, xf: Affine, scale: f32, p0, p1: Vec2, rx_in, ry_in, rot_deg: f32, large, sweep: bool) {
	rx, ry := rx_in, ry_in
	if rx == 0 || ry == 0 || p0 == p1 {
		append(&q.pts, affine_apply(xf, p1))
		return
	}
	phi := rot_deg * math.PI / 180
	cp, sp := math.cos(phi), math.sin(phi)
	dx, dy := (p0.x - p1.x) / 2, (p0.y - p1.y) / 2
	x1 := cp * dx + sp * dy
	y1 := -sp * dx + cp * dy
	lam := (x1 * x1) / (rx * rx) + (y1 * y1) / (ry * ry)
	if lam > 1 {
		k := math.sqrt(lam)
		rx, ry = rx * k, ry * k
	}
	num := rx * rx * ry * ry - rx * rx * y1 * y1 - ry * ry * x1 * x1
	den := rx * rx * y1 * y1 + ry * ry * x1 * x1
	co := math.sqrt(max(num / den, 0))
	if large == sweep do co = -co
	cxp := co * rx * y1 / ry
	cyp := -co * ry * x1 / rx
	cx := cp * cxp - sp * cyp + (p0.x + p1.x) / 2
	cy := sp * cxp + cp * cyp + (p0.y + p1.y) / 2
	ang :: proc(ux, uy, vx, vy: f32) -> f32 {
		return math.atan2(ux * vy - uy * vx, ux * vx + uy * vy)
	}
	t1 := ang(1, 0, (x1 - cxp) / rx, (y1 - cyp) / ry)
	dt := ang((x1 - cxp) / rx, (y1 - cyp) / ry, (-x1 - cxp) / rx, (-y1 - cyp) / ry)
	if !sweep && dt > 0 do dt -= math.TAU
	if sweep && dt < 0 do dt += math.TAU
	n := clamp(int(abs(dt) * max(rx, ry) * scale / 1.5), 2, 96)
	for k in 1 ..= n {
		a := t1 + dt * f32(k) / f32(n)
		x := rx * math.cos(a)
		y := ry * math.sin(a)
		append(&q.pts, affine_apply(xf, {cp * x - sp * y + cx, sp * x + cp * y + cy}))
	}
}

// Squared distance from p to segment ab.
@(private = "file")
seg_dist2 :: #force_inline proc(p, a, b: Vec2) -> f32 {
	ab := b - a
	ap := p - a
	l2 := ab.x * ab.x + ab.y * ab.y
	t: f32 = 0
	if l2 > 0 do t = clamp((ap.x * ab.x + ap.y * ab.y) / l2, 0, 1)
	d := ap - ab * t
	return d.x * d.x + d.y * d.y
}

@(private = "file")
svg_draw :: proc(acc: [][4]f32, w, h: int, polys: []Svg_Poly, st: Svg_Style) {
	if len(polys) == 0 do return
	scale := math.sqrt(abs(st.xf.a * st.xf.d - st.xf.b * st.xf.c))
	hw := st.width * scale / 2
	// bounds of everything, padded by the stroke
	lo := Vec2{max(f32), max(f32)}
	hi := Vec2{min(f32), min(f32)}
	for &q in polys {
		for pt in q.pts {
			lo = {min(lo.x, pt.x), min(lo.y, pt.y)}
			hi = {max(hi.x, pt.x), max(hi.y, pt.y)}
		}
	}
	pad := (st.has_stroke ? hw : 0) + 1
	x0, y0 := max(int(lo.x - pad), 0), max(int(lo.y - pad), 0)
	x1, y1 := min(int(hi.x + pad) + 1, w), min(int(hi.y + pad) + 1, h)
	if x0 >= x1 || y0 >= y1 do return

	blend :: #force_inline proc(dst: ^[4]f32, c: Color, a: f32) {
		if a <= 0 do return
		k := 1 - a
		dst^ = {f32(c.r) / 255 * a + dst[0] * k, f32(c.g) / 255 * a + dst[1] * k, f32(c.b) / 255 * a + dst[2] * k, a + dst[3] * k}
	}

	for y in y0 ..< y1 {
		for x in x0 ..< x1 {
			pt := Vec2{f32(x) + 0.5, f32(y) + 0.5}
			if st.has_fill {
				// winding number at the pixel centre and the distance to the nearest edge
				wind := 0
				d2 := max(f32)
				for &q in polys {
					n := len(q.pts)
					if n < 2 do continue
					for i in 0 ..< n {
						a := q.pts[i]
						b := q.pts[(i + 1) % n]
						if a.y <= pt.y {
							if b.y > pt.y && (b.x - a.x) * (pt.y - a.y) - (pt.x - a.x) * (b.y - a.y) > 0 do wind += 1
						} else if b.y <= pt.y && (b.x - a.x) * (pt.y - a.y) - (pt.x - a.x) * (b.y - a.y) < 0 {
							wind -= 1
						}
						d2 = min(d2, seg_dist2(pt, a, b))
					}
				}
				inside := st.evenodd ? wind % 2 != 0 : wind != 0
				d := math.sqrt(d2)
				cov := inside ? min(0.5 + d, 1) : max(0.5 - d, 0)
				blend(&acc[y * w + x], st.fill, cov * st.opacity * st.fill_op)
			}
			if st.has_stroke && hw > 0 {
				d2 := max(f32)
				for &q in polys {
					n := len(q.pts)
					if n < 2 do continue // a lone moveto draws nothing; dots are written "l0 0"
					segs := q.closed ? n : n - 1
					for i in 0 ..< segs {
						d2 = min(d2, seg_dist2(pt, q.pts[i], q.pts[(i + 1) % n]))
					}
				}
				d := math.sqrt(d2)
				cov: f32
				if hw >= 0.5 {
					cov = clamp(hw + 0.5 - d, 0, 1)
				} else {
					// hairlines: keep a pixel's worth of footprint, fade by width
					cov = clamp(1 - d, 0, 1) * hw * 2
				}
				blend(&acc[y * w + x], st.stroke, cov * st.opacity * st.stroke_op)
			}
		}
	}
}
