package pangolin

import "core:math"

// ---------------------------------------------------------------------------
// Brush settings
// ---------------------------------------------------------------------------

Tip :: enum u8 {
	Round, // soft/hard ellipse
	Bristle, // streaky, follows the stroke direction
	Chalk, // grain eats into the dab
	Flat, // squared-off tip, for calligraphy and knives
}

TIP_NAMES := [Tip]string {
	.Round   = "Round",
	.Bristle = "Bristle",
	.Chalk   = "Chalk",
	.Flat    = "Flat",
}

Pressure :: enum u8 {
	Off,
	Taper, // thin start and end, like a pen lifted off the paper
	Speed, // faster strokes are thinner
	Pen, // real pressure from a graphics tablet (used automatically when a pen is in use)
}

PRESSURE_NAMES := [Pressure]string {
	.Off   = "Off",
	.Taper = "Taper ends",
	.Speed = "Stroke speed",
	.Pen   = "Pen pressure",
}

Brush :: struct {
	size:        int, // diameter in canvas pixels
	opacity:     int, // 1..100, cap for one stroke
	flow:        int, // 1..100, per-dab build-up
	hardness:    int, // 0..100
	spacing:     int, // 1..200 % of the diameter
	smoothing:   int, // 0..100 stabiliser
	scatter:     int, // 0..100 % of the diameter
	size_jitter: int, // 0..100
	grain:       int, // 0..100 paper texture
	angle:       int, // 0..359
	roundness:   int, // 5..100
	tip:         Tip,
	follow:      bool, // tip rotates with the stroke direction
	pressure:    Pressure,
	taper:       int, // taper length in % of the brush size x 10
	p_size:      bool, // pressure changes size
	p_opacity:   bool, // pressure changes opacity
	airbrush:    bool, // keep spraying while the mouse is still
	// wet media (oil)
	load:        int, // 0..100 paint on the brush (100 = never runs out)
	wet:         int, // 0..100 how much canvas colour the brush picks up
	bristles:    int, // 0..100 strength of the bristle streaks
	// smudge / blur / dodge
	strength:    int, // 0..100
	alt_mode:    bool, // blur: sharpen instead; dodge: burn instead
	tone:        int, // dodge/burn range: 0 shadows, 1 midtones, 2 highlights
	clone_merged: bool, // clone: sample all layers
}

brush_default :: proc(t: Tool) -> Brush {
	b := Brush {
		size      = 24,
		opacity   = 100,
		flow      = 100,
		hardness  = 80,
		spacing   = 8,
		roundness = 100,
		pressure  = .Pen, // a pen's pressure is always used; the mouse paints at full pressure anyway
		taper     = 30,
		p_size    = true,
		load      = 70,
		wet       = 30,
		bristles  = 50,
		strength  = 50,
		tone      = 1,
	}
	#partial switch t {
	case .Oil:
		b.size = 36
		b.hardness = 75
		b.spacing = 4
		b.tip = .Bristle
		b.follow = true
	case .Smudge:
		b.size = 40
		b.hardness = 30
		b.spacing = 4
		b.strength = 60
	case .Eraser:
		b.size = 40
		b.hardness = 60
	case .Blur:
		b.size = 50
		b.hardness = 0
		b.spacing = 10
	case .Dodge:
		b.size = 80
		b.hardness = 0
		b.strength = 25
	case .Clone:
		b.size = 60
		b.hardness = 40
	}
	return b
}

// Brush <-> list of ints, for storing a group's brushes in the preferences / workspace files.
// New fields go at the end; missing trailing values keep the base brush's.
// The last value is a format version: lists without it predate pen pressure being on by default.
BRUSH_INTS :: 26
BRUSH_INTS_VERSION :: 1

brush_to_ints :: proc(b: Brush) -> [BRUSH_INTS]int {
	return {
		b.size, b.opacity, b.flow, b.hardness, b.spacing, b.smoothing, b.scatter, b.size_jitter,
		b.grain, b.angle, b.roundness, int(b.tip), int(b.follow), int(b.pressure), b.taper,
		int(b.p_size), int(b.p_opacity), int(b.airbrush), b.load, b.wet, b.bristles, b.strength,
		int(b.alt_mode), b.tone, int(b.clone_merged), BRUSH_INTS_VERSION,
	}
}

brush_from_ints :: proc(base: Brush, v: []int) -> Brush {
	b := base
	a: [BRUSH_INTS]int = brush_to_ints(base)
	for x, i in v {
		if i < BRUSH_INTS do a[i] = x
	}
	b.size = clamp(a[0], 1, BRUSH_MAX)
	b.opacity = clamp(a[1], 1, 100)
	b.flow = clamp(a[2], 1, 100)
	b.hardness = clamp(a[3], 0, 100)
	b.spacing = clamp(a[4], 1, 200)
	b.smoothing = clamp(a[5], 0, 100)
	b.scatter = clamp(a[6], 0, 100)
	b.size_jitter = clamp(a[7], 0, 100)
	b.grain = clamp(a[8], 0, 100)
	b.angle = clamp(a[9], 0, 359)
	b.roundness = clamp(a[10], 5, 100)
	b.tip = Tip(clamp(a[11], 0, len(Tip) - 1))
	b.follow = a[12] != 0
	b.pressure = Pressure(clamp(a[13], 0, len(Pressure) - 1))
	b.taper = clamp(a[14], 0, 1000)
	b.p_size = a[15] != 0
	b.p_opacity = a[16] != 0
	b.airbrush = a[17] != 0
	b.load = clamp(a[18], 0, 100)
	b.wet = clamp(a[19], 0, 100)
	b.bristles = clamp(a[20], 0, 100)
	b.strength = clamp(a[21], 0, 100)
	b.alt_mode = a[22] != 0
	b.tone = clamp(a[23], 0, 2)
	b.clone_merged = a[24] != 0
	if len(v) < BRUSH_INTS && b.pressure == .Off {
		// saved before pressure defaulted to on: "Off" was just the old default
		b.pressure = .Pen
	}
	return b
}

// Per-tool settings (each painting tool remembers its own brush).
brushes: [Tool]Brush
brush_preset_idx: [Tool]int

Preset :: struct {
	name: string,
	tool: Tool,
	b:    Brush,
}

presets: [dynamic]Preset

brush_presets_init :: proc() {
	for t in Tool {
		brushes[t] = brush_default(t)
	}
	add :: proc(name: string, tool: Tool, b: Brush) {
		append(&presets, Preset{name, tool, b})
	}
	b := brush_default(.Brush)
	{
		p := b
		p.size, p.hardness = 12, 90
		add("Hard Round", .Brush, p)
		p = b
		p.size, p.hardness, p.flow = 60, 0, 40
		add("Soft Round", .Brush, p)
		p = b
		p.size, p.hardness, p.flow, p.spacing, p.airbrush = 120, 0, 6, 5, true
		add("Airbrush", .Brush, p)
		p = b
		p.size, p.hardness, p.grain, p.tip, p.opacity, p.spacing = 3, 80, 60, .Chalk, 85, 10
		add("Pencil", .Brush, p)
		p = b
		p.size, p.hardness, p.pressure, p.taper, p.smoothing, p.spacing = 7, 95, .Taper, 60, 45, 5
		add("Ink Pen", .Brush, p)
		p = b
		p.size, p.hardness, p.opacity, p.roundness, p.angle = 26, 75, 55, 55, 30
		add("Marker", .Brush, p)
		p = b
		p.size, p.hardness, p.grain, p.tip, p.spacing, p.scatter = 32, 60, 85, .Chalk, 10, 4
		add("Chalk", .Brush, p)
		p = b
		p.size, p.hardness, p.grain, p.tip, p.opacity, p.size_jitter, p.roundness, p.angle = 22, 70, 95, .Chalk, 90, 30, 55, 70
		add("Charcoal", .Brush, p)
		p = b
		p.size, p.hardness, p.opacity, p.flow, p.grain, p.spacing = 90, 5, 35, 12, 35, 6
		add("Watercolor Wash", .Brush, p)
		p = b
		p.size, p.tip, p.bristles, p.hardness, p.spacing, p.follow = 40, .Bristle, 75, 70, 4, true
		add("Bristle", .Brush, p)
		p = b
		p.size, p.tip, p.roundness, p.angle, p.hardness, p.spacing = 30, .Flat, 20, 45, 95, 3
		add("Calligraphy", .Brush, p)
		p = b
		p.size, p.hardness, p.scatter, p.size_jitter, p.spacing = 50, 90, 100, 85, 70
		add("Splatter", .Brush, p)
	}
	o := brush_default(.Oil)
	{
		p := o
		add("Oil Round", .Oil, p)
		p = o
		p.tip, p.roundness, p.size, p.bristles, p.wet = .Flat, 35, 44, 70, 25
		add("Oil Flat", .Oil, p)
		p = o
		p.load, p.wet, p.bristles, p.hardness, p.tip = 20, 85, 25, 30, .Round
		add("Wet Blender", .Oil, p)
		p = o
		p.load, p.wet, p.bristles, p.hardness = 12, 10, 100, 85
		add("Dry Brush", .Oil, p)
		p = o
		p.tip, p.roundness, p.hardness, p.bristles, p.load, p.wet, p.spacing, p.size = .Flat, 14, 100, 0, 90, 45, 3, 50
		add("Palette Knife", .Oil, p)
		p = o
		p.load, p.wet, p.bristles, p.size = 100, 8, 35, 28
		add("Thick Impasto", .Oil, p)
		p = o
		p.load, p.wet, p.bristles, p.size, p.hardness = 55, 55, 45, 18, 60
		add("Detail Sable", .Oil, p)
	}
	s := brush_default(.Smudge)
	{
		p := s
		add("Soft Smudge", .Smudge, p)
		p = s
		p.hardness, p.strength, p.size = 85, 80, 24
		add("Hard Smudge", .Smudge, p)
		p = s
		p.strength, p.size, p.tip, p.bristles, p.follow = 70, 40, .Bristle, 70, true
		add("Bristle Blend", .Smudge, p)
		p = s
		p.strength, p.size, p.hardness = 30, 80, 0
		add("Gentle Blend", .Smudge, p)
	}
	e := brush_default(.Eraser)
	{
		p := e
		p.hardness = 95
		add("Hard Eraser", .Eraser, p)
		p = e
		p.hardness, p.flow, p.size = 0, 35, 80
		add("Soft Eraser", .Eraser, p)
		p = e
		p.tip, p.grain, p.size = .Chalk, 85, 30
		add("Chalk Eraser", .Eraser, p)
	}
	{
		p := brush_default(.Blur)
		add("Blur", .Blur, p)
		p.alt_mode, p.strength = true, 30
		add("Sharpen", .Blur, p)
		p = brush_default(.Dodge)
		add("Dodge", .Dodge, p)
		p.alt_mode = true
		add("Burn", .Dodge, p)
		p = brush_default(.Clone)
		add("Soft Clone", .Clone, p)
		p.hardness = 90
		add("Hard Clone", .Clone, p)
	}
	// start every tool on its first preset
	for t in Tool {
		for pr, i in presets {
			if pr.tool == t {
				brushes[t] = pr.b
				brush_preset_idx[t] = i
				break
			}
		}
	}
}

paint_tool :: proc(t: Tool) -> bool {
	#partial switch t {
	case .Brush, .Oil, .Smudge, .Eraser, .Blur, .Dodge, .Clone:
		return true
	}
	return false
}

// ---------------------------------------------------------------------------
// Paper grain: tileable value noise sampled in canvas space
// ---------------------------------------------------------------------------

GRAIN :: 256
grain_tex: [GRAIN * GRAIN]f32

rng_state: u64 = 0x9E3779B97F4A7C15

rand_u32 :: proc(s: ^u64) -> u32 {
	x := s^
	x ~= x << 13
	x ~= x >> 7
	x ~= x << 17
	s^ = x
	return u32(x >> 32)
}

rand_f :: proc(s: ^u64) -> f32 {
	return f32(rand_u32(s)) / 4294967296.0
}

brush_init :: proc() {
	brush_presets_init()
	// a few octaves of smooth value noise + fine fibre noise
	s: u64 = 0x1234567
	lattice :: proc(n: int, s: ^u64) -> []f32 {
		g := make([]f32, n * n, context.temp_allocator)
		for &v in g do v = rand_f(s)
		return g
	}
	for &v in grain_tex do v = 0
	amp: f32 = 0.5
	total: f32 = 0
	for cells in ([?]int{8, 16, 32, 64, 128}) {
		g := lattice(cells, &s)
		step := GRAIN / cells
		for y in 0 ..< GRAIN {
			for x in 0 ..< GRAIN {
				gx, gy := x / step, y / step
				fx := f32(x % step) / f32(step)
				fy := f32(y % step) / f32(step)
				fx = fx * fx * (3 - 2 * fx)
				fy = fy * fy * (3 - 2 * fy)
				a := g[gy * cells + gx]
				b := g[gy * cells + (gx + 1) % cells]
				c := g[((gy + 1) % cells) * cells + gx]
				d := g[((gy + 1) % cells) * cells + (gx + 1) % cells]
				grain_tex[y * GRAIN + x] += amp * ((a * (1 - fx) + b * fx) * (1 - fy) + (c * (1 - fx) + d * fx) * fy)
			}
		}
		total += amp
		amp *= 0.7
	}
	for &v in grain_tex {
		v = v / total
		v = clamp((v - 0.5) * 2.2 + 0.5, 0, 1)
	}
}

grain_at :: #force_inline proc(x, y: int) -> f32 {
	return grain_tex[(y & (GRAIN - 1)) * GRAIN + (x & (GRAIN - 1))]
}

// ---------------------------------------------------------------------------
// Stroke state
// ---------------------------------------------------------------------------

Dab :: struct {
	x, y:  f32,
	r:     f32, // radius before pressure
	a:     f32, // alpha before pressure
	dist:  f32, // distance along the stroke
	dir:   Vec2,
	press: f32,
}

Stroke :: struct {
	active:     bool,
	tool:       Tool,
	b:          Brush,
	target:     ^Tiles,
	empty:      Color,
	is_mask:    bool,
	lock_alpha: bool,
	blend:      Blend, // how the brush paint combines with the layer (set from the tool groups)
	orig:       Tiles, // shared copy of the target from before the stroke
	clone_src:  []Color, // merged pixels for "clone merged"
	box:        Box, // area touched so far
	color:      Color,
	erase:      bool,
	// path
	raw:        Vec2, // latest mouse position
	sm:         Vec2, // stabilised position
	pts:        [dynamic]Vec2,
	last_mid:   Vec2,
	since:      f32, // distance travelled since the last dab
	total:      f32,
	dir:        Vec2,
	speed:      f32,
	pen_p:      f32, // smoothed pen pressure
	last_dab_t: f64,
	dabs:       [dynamic]Dab,
	// wet media
	carry:      [][4]f32, // premultiplied colour picked up by the brush, per offset
	carry_r:    int,
	carry_init: bool,
	paint_left: f32,
	bristle:    [48]f32,
	clone_off:  Vec2,
	rng:        u64,
}

stroke: Stroke

// Accumulated per-pixel coverage for brush/eraser/clone strokes (w*h, reused).
stroke_mask: []f32
stroke_mask_w, stroke_mask_h: int

// Clone source (canvas coordinates) and whether the next stroke re-aligns to it.
clone_src_pt: Vec2
clone_src_set: bool
clone_realign: bool

stroke_uses_mask :: proc(t: Tool) -> bool {
	return t == .Brush || t == .Eraser || t == .Clone
}

// Start a stroke at canvas position p. Returns false if the layer can't be painted.
stroke_begin :: proc(t: Tool, p: Vec2, color: Color) -> bool {
	d := doc
	if !can_edit() {
		return false
	}
	if t == .Clone && !clone_src_set {
		set_status("Alt+click to set the clone source first")
		return false
	}
	history_push(d)
	s := &stroke
	clear(&s.pts)
	clear(&s.dabs)
	tgt := s.pts
	dabs := s.dabs
	carry := s.carry
	s^ = Stroke {
		pts   = tgt,
		dabs  = dabs,
		carry = carry,
	}
	s.active = true
	s.tool = t
	s.b = brushes[t]
	if !pen_active() {
		// pressure only exists for a pen: the mouse always paints at full pressure
		s.b.pressure = .Off
	} else if s.b.pressure != .Off {
		// a real pen replaces the simulated pressure
		s.b.pressure = .Pen
		s.pen_p = max(pen.pressure, 0.05)
	}
	s.target, s.empty, s.is_mask = doc_target(d)
	s.lock_alpha = !s.is_mask && d.layers[d.active_layer].lock_alpha
	if t == .Brush || t == .Oil {
		s.blend = brush_blend
	}
	s.orig = tiles_share(s.target)
	s.color = color
	if s.is_mask {
		g := luma(color)
		s.color = Color{g, g, g, 255}
	}
	if t == .Eraser {
		s.erase = !s.is_mask
		if s.is_mask {
			s.color = Color{0, 0, 0, 255} // erasing a mask hides
		}
		if s.lock_alpha {
			s.erase = false
			s.color = bg
		}
	}
	s.rng = u64(ui.time * 1000) * 2654435761 + 12345
	for &v in s.bristle {
		r := rand_f(&s.rng)
		v = 0.35 + 0.65 * math.sqrt(r)
		if rand_f(&s.rng) < 0.18 {
			v *= 0.3 // gaps between bristle groups
		}
	}
	s.paint_left = 1
	if t == .Brush || t == .Oil {
		recent_push(color)
	}
	s.raw, s.sm = p, p
	s.last_mid = p
	append(&s.pts, p)
	s.last_dab_t = ui.time
	if stroke_uses_mask(t) {
		if stroke_mask_w != d.w || stroke_mask_h != d.h {
			delete(stroke_mask)
			stroke_mask = make([]f32, d.w * d.h)
			stroke_mask_w, stroke_mask_h = d.w, d.h
		}
	}
	if t == .Clone {
		if clone_realign || ui.shift {
			s.clone_off = clone_src_pt - p
			clone_off_saved = s.clone_off
			clone_realign = false
		} else {
			s.clone_off = clone_off_saved
		}
		if s.b.clone_merged {
			s.clone_src = doc_flat(d)
		}
	}
	// wet media buffers
	if t == .Oil || t == .Smudge {
		cr := int(f32(s.b.size) * 0.5 * (1 + f32(s.b.scatter) / 100)) + 3
		side := 2 * cr + 1
		if len(s.carry) < side * side {
			delete(s.carry)
			s.carry = make([][4]f32, side * side)
		}
		s.carry_r = cr
		if t == .Oil {
			pc := [4]f32{f32(s.color.r) / 255, f32(s.color.g) / 255, f32(s.color.b) / 255, 1}
			for &c in s.carry[:side * side] do c = pc
			s.carry_init = true
		}
	}
	// the first dab
	stroke_dab_at(p, 0, Vec2{1, 0})
	return true
}

clone_off_saved: Vec2

// Feed the current mouse position; called every frame while the button is held.
stroke_move :: proc(p: Vec2) {
	s := &stroke
	if !s.active {
		return
	}
	s.raw = p
	if s.b.pressure == .Pen {
		s.pen_p += (max(pen.pressure, 0.05) - s.pen_p) * 0.5
	}
	k := 1 - f32(s.b.smoothing) / 100 * 0.93
	prev := s.sm
	s.sm += (s.raw - s.sm) * k
	mv := s.sm - prev
	moved := math.sqrt(mv.x * mv.x + mv.y * mv.y)
	s.speed = s.speed * 0.7 + moved * 0.3
	if moved > 0.05 {
		append(&s.pts, s.sm)
		stroke_flush(false)
	} else if s.b.airbrush && ui.time - s.last_dab_t > 1.0 / 30 {
		stroke_dab_at(s.sm, s.total, s.dir)
	}
}

// Emit dabs along the smoothed path: quadratic curves between point midpoints.
stroke_flush :: proc(final: bool) {
	s := &stroke
	n := len(s.pts)
	if n < 2 {
		return
	}
	a := s.last_mid
	c := s.pts[n - 2]
	e := (s.pts[n - 2] + s.pts[n - 1]) * 0.5
	if final {
		e = s.pts[n - 1]
	}
	if n == 2 && !final {
		c = (a + e) * 0.5
	}
	stroke_curve(a, c, e)
	s.last_mid = e
	if len(s.pts) > 3 {
		// only the last two points matter from here on
		s.pts[0] = s.pts[n - 2]
		s.pts[1] = s.pts[n - 1]
		resize(&s.pts, 2)
	}
}

stroke_spacing :: proc(s: ^Stroke) -> f32 {
	sp := f32(s.b.size) * f32(s.b.spacing) / 100
	if s.b.pressure != .Off && s.b.p_size {
		sp *= max(stroke_pressure(s, s.total), 0.2)
	}
	return max(sp, 0.5)
}

stroke_curve :: proc(a, c, e: Vec2) {
	s := &stroke
	ln := vlen(c - a) + vlen(e - c)
	steps := max(int(ln * 2), 1)
	prev := a
	for i in 1 ..= steps {
		t := f32(i) / f32(steps)
		u := 1 - t
		q := a * (u * u) + c * (2 * u * t) + e * (t * t)
		seg := q - prev
		sl := vlen(seg)
		if sl <= 0 {
			continue
		}
		dirv := seg / sl
		s.dir = vnorm(s.dir * 0.75 + dirv * 0.25)
		pos: f32 = 0
		for {
			need := stroke_spacing(s) - s.since
			if pos + need > sl {
				s.since += sl - pos
				s.total += sl - pos
				break
			}
			pos += need
			s.total += need
			s.since = 0
			stroke_dab_at(prev + dirv * pos, s.total, s.dir)
		}
		prev = q
	}
}

vlen :: #force_inline proc(v: Vec2) -> f32 {
	return math.sqrt(v.x * v.x + v.y * v.y)
}

vnorm :: proc(v: Vec2) -> Vec2 {
	l := vlen(v)
	if l < 1e-6 {
		return Vec2{1, 0}
	}
	return v / l
}

stroke_pressure :: proc(s: ^Stroke, dist: f32) -> f32 {
	switch s.b.pressure {
	case .Off:
		return 1
	case .Taper:
		tl := max(f32(s.b.size) * f32(s.b.taper) / 10, 4)
		t := clamp(dist / tl, 0, 1)
		return 0.12 + 0.88 * t * (2 - t)
	case .Speed:
		v := s.speed / max(f32(s.b.size) * 0.35, 2)
		return clamp(1.15 - v * 0.6, 0.2, 1)
	case .Pen:
		return s.pen_p
	}
	return 1
}

stroke_dab_at :: proc(p: Vec2, dist: f32, dir: Vec2) {
	s := &stroke
	b := &s.b
	r := f32(b.size) / 2
	a: f32 = 1
	pos := p
	if b.size_jitter > 0 {
		r *= 1 - rand_f(&s.rng) * f32(b.size_jitter) / 100
	}
	if b.scatter > 0 {
		ang := rand_f(&s.rng) * math.TAU
		rad := math.sqrt(rand_f(&s.rng)) * f32(b.size) * f32(b.scatter) / 100
		pos += Vec2{math.cos(ang), math.sin(ang)} * rad
	}
	dab := Dab{pos.x, pos.y, r, a, dist, dir, stroke_pressure(s, dist)}
	if stroke_uses_mask(s.tool) && b.pressure == .Taper {
		append(&s.dabs, dab)
	}
	dab_apply(s, dab)
	s.last_dab_t = ui.time
}

// Finish the stroke. Tapered brush strokes are re-rendered once the length is known.
stroke_end :: proc() {
	s := &stroke
	if !s.active {
		return
	}
	stroke_flush(true)
	d := doc
	if stroke_uses_mask(s.tool) && s.b.pressure == .Taper && len(s.dabs) > 1 {
		total := s.dabs[len(s.dabs) - 1].dist
		tl := max(f32(s.b.size) * f32(s.b.taper) / 10, 4)
		// restore the touched area and clear the coverage, then draw again with both ends tapered
		stroke_restore_box(s)
		for &dab in s.dabs {
			tin := clamp(dab.dist / tl, 0, 1)
			tout := clamp((total - dab.dist) / tl, 0, 1)
			t := min(tin, tout)
			dab.press = 0.12 + 0.88 * t * (2 - t)
			dab_apply(s, dab)
		}
	}
	if stroke_uses_mask(s.tool) {
		b := box_clip(s.box, d.w, d.h)
		for y in b.y0 ..< b.y1 {
			row := stroke_mask[y * d.w:][b.x0:b.x1]
			for &v in row do v = 0
		}
	}
	tiles_compact_box(s.target, s.box, s.empty)
	tiles_destroy(&s.orig)
	if s.clone_src != nil {
		delete(s.clone_src)
		s.clone_src = nil
	}
	if box_empty(s.box) {
		history_discard(d)
	}
	s.active = false
	d.thumb_dirty = true
}

// Put back the pre-stroke pixels inside the touched box and clear the coverage there.
stroke_restore_box :: proc(s: ^Stroke) {
	d := doc
	b := box_clip(s.box, d.w, d.h)
	if box_empty(b) {
		return
	}
	tmp := make([]Color, (b.x1 - b.x0) * (b.y1 - b.y0), context.temp_allocator)
	tiles_read_box(&s.orig, b, tmp, s.empty)
	tiles_write_box(s.target, b, tmp, s.empty)
	for y in b.y0 ..< b.y1 {
		row := stroke_mask[y * d.w:][b.x0:b.x1]
		for &v in row do v = 0
	}
	doc_dirty(d, b)
}

// ---------------------------------------------------------------------------
// Tip shape
// ---------------------------------------------------------------------------

Tip_Eval :: struct {
	cx, cy:     f32,
	r, inv_r:   f32,
	ca, sa:     f32, // rotation
	inv_round:  f32,
	hard:       f32,
	tip:        Tip,
	grain:      f32,
	bristles:   f32,
	dry:        f32, // 0 = wet, 1 = bone dry (bristle drop-out)
	small:      f32, // alpha scale for sub-pixel brushes
}

tip_setup :: proc(s: ^Stroke, dab: Dab, r: f32) -> Tip_Eval {
	b := &s.b
	e: Tip_Eval
	e.cx, e.cy = dab.x, dab.y
	e.small = 1
	rr := r
	if rr < 0.7 {
		e.small = (rr / 0.7) * (rr / 0.7)
		rr = 0.7
	}
	e.r = rr
	e.inv_r = 1 / rr
	ang := f32(b.angle) * math.PI / 180
	if b.follow {
		ang += math.atan2(dab.dir.y, dab.dir.x)
	}
	e.ca, e.sa = math.cos(ang), math.sin(ang)
	e.inv_round = 100 / f32(clamp(b.roundness, 5, 100))
	e.hard = f32(b.hardness) / 100
	e.tip = b.tip
	e.grain = f32(b.grain) / 100
	e.bristles = b.tip == .Bristle ? f32(max(b.bristles, 40)) / 100 : f32(b.bristles) / 100
	if s.tool != .Oil && b.tip != .Bristle {
		e.bristles = 0
	}
	e.dry = 1 - s.paint_left
	return e
}

tip_alpha :: #force_inline proc(e: ^Tip_Eval, s: ^Stroke, x, y: int) -> f32 {
	dx := f32(x) + 0.5 - e.cx
	dy := f32(y) + 0.5 - e.cy
	// rotate into tip space: u along the tip axis, v across it
	u := (dx * e.ca + dy * e.sa) * e.inv_round
	v := -dx * e.sa + dy * e.ca
	d: f32
	if e.tip == .Flat {
		// squircle: flat sides with rounded corners
		au, av := abs(u) * e.inv_r, abs(v) * e.inv_r
		d = math.pow(au * au * au * au + av * av * av * av, 0.25)
	} else {
		d = math.sqrt(u * u + v * v) * e.inv_r
	}
	// anti-aliased edge one pixel wide
	edge := clamp((1 - d) * e.r + 0.5, 0, 1)
	if edge <= 0 {
		return 0
	}
	a: f32 = 1
	if d > e.hard {
		t := clamp((d - e.hard) / max(1 - e.hard, 0.001), 0, 1)
		a = (1 - t * t)
		a *= a
	}
	a *= edge * e.small
	if e.bristles > 0 {
		// streaks across the stroke; dry bristles drop out first
		bv := clamp(v * e.inv_r * 0.5 + 0.5, 0, 0.9999) * f32(len(s.bristle) - 1)
		bi := int(bv)
		bf := bv - f32(bi)
		st := s.bristle[bi] * (1 - bf) + s.bristle[bi + 1] * bf
		if e.dry > 0 {
			st *= clamp((st - e.dry * 0.85) * 4, 0, 1)
		}
		a *= 1 - e.bristles + e.bristles * st
	}
	if e.grain > 0 {
		g := grain_at(x, y)
		if e.tip == .Chalk {
			// grain cuts into the dab: only the paper's peaks catch pigment at low coverage
			a = clamp((a - (1 - g) * e.grain) * (1 + e.grain), 0, 1)
		} else {
			a *= 1 - e.grain * (1 - g)
		}
	}
	return a
}

// ---------------------------------------------------------------------------
// Applying one dab
// ---------------------------------------------------------------------------

dab_apply :: proc(s: ^Stroke, dab: Dab) {
	d := doc
	// seamless mode: stamp the dab on every wrapped copy that reaches into the canvas
	if seamless_mode && (s.tool == .Brush || s.tool == .Eraser || s.tool == .Clone || s.tool == .Blur || s.tool == .Dodge) {
		w, h := f32(d.w), f32(d.h)
		base := dab
		base.x -= math.floor(dab.x / w) * w
		base.y -= math.floor(dab.y / h) * h
		for oy in -1 ..= 1 {
			for ox in -1 ..= 1 {
				c := base
				c.x += f32(ox) * w
				c.y += f32(oy) * h
				dab_apply_one(s, c)
			}
		}
		return
	}
	if seamless_mode {
		// stateful tools (oil, smudge) can't be stamped repeatedly; keep the dab centre on the canvas
		c := dab
		c.x -= math.floor(dab.x / f32(d.w)) * f32(d.w)
		c.y -= math.floor(dab.y / f32(d.h)) * f32(d.h)
		dab_apply_one(s, c)
		return
	}
	dab_apply_one(s, dab)
}

dab_apply_one :: proc(s: ^Stroke, dab: Dab) {
	d := doc
	b := &s.b
	press := dab.press
	r := dab.r
	alpha := dab.a
	if b.pressure != .Off {
		if b.p_size do r *= press
		if b.p_opacity do alpha *= press
	}
	e := tip_setup(s, dab, r)
	reach := e.r * max(e.inv_round, 1) + 2
	box := box_clip(Box{int(math.floor(dab.x - reach)), int(math.floor(dab.y - reach)), int(math.ceil(dab.x + reach)) + 1, int(math.ceil(dab.y + reach)) + 1}, d.w, d.h)
	if s.tool == .Oil || s.tool == .Smudge {
		// wet buffers are indexed by offset from the dab centre
		icx, icy := int(math.round(dab.x)), int(math.round(dab.y))
		cr := s.carry_r
		box = box_clip(Box{max(box.x0, icx - cr), max(box.y0, icy - cr), min(box.x1, icx + cr + 1), min(box.y1, icy + cr + 1)}, d.w, d.h)
	}
	if box_empty(box) {
		return
	}
	s.box = box_union(s.box, box)
	switch s.tool {
	case .Brush, .Eraser, .Clone:
		dab_masked(s, &e, box, alpha * f32(b.flow) / 100)
	case .Oil:
		dab_oil(s, &e, box, dab, alpha)
		// paint runs out with distance: at 70% load about 25 brush widths
		s.paint_left *= 1 - (1 - f32(b.load) / 100) * 0.2 * stroke_spacing(s) / max(f32(b.size), 1)
	case .Smudge:
		dab_smudge(s, &e, box, dab, alpha)
	case .Blur:
		dab_blur(s, &e, box, alpha)
	case .Dodge:
		dab_dodge(s, &e, box, alpha)
	case .Bucket, .Gradient, .Picker, .Text, .Select_Rect, .Select_Ellipse, .Lasso, .Wand, .Move, .Transform, .Crop, .Hand, .Zoom:
	}
	doc_dirty(d, box)
}

// Brush / eraser / clone: coverage accumulates in `stroke_mask`, capped by opacity,
// and the result is always computed from the pre-stroke pixels so strokes don't
// darken where dabs overlap.
dab_masked :: proc(s: ^Stroke, e: ^Tip_Eval, box: Box, flow: f32) {
	d := doc
	w := d.w
	opacity := f32(s.b.opacity) / 100
	textured := e.bristles > 0 || (e.tip == .Chalk && e.grain > 0)
	g := s.target
	for ty in box.y0 / TILE ..= (box.y1 - 1) / TILE {
		for tx in box.x0 / TILE ..= (box.x1 - 1) / TILE {
			x0, x1 := max(box.x0, tx * TILE), min(box.x1, (tx + 1) * TILE)
			y0, y1 := max(box.y0, ty * TILE), min(box.y1, (ty + 1) * TILE)
			t := tiles_write(g, tx, ty, s.empty)
			ot := s.orig.t[ty * g.tw + tx]
			for y in y0 ..< y1 {
				for x in x0 ..< x1 {
					a := tip_alpha(e, s, x, y) * flow
					if a <= 0.0005 {
						continue
					}
					i := y * w + x
					m := stroke_mask[i]
					if textured {
						// keep the tip's texture: overlapping dabs don't fill in the gaps
						m = max(m, a)
					} else {
						m += (1 - m) * a
					}
					stroke_mask[i] = m
					cov := m * opacity * f32(sel_at(d, i)) / 255
					li := (y % TILE) * TILE + x % TILE
					o := ot != nil ? ot.pix[li] : s.empty
					res: Color
					switch {
					case s.erase:
						res = Color{o.r, o.g, o.b, u8(f32(o.a) * (1 - cov) + 0.5)}
					case s.tool == .Clone:
						sx := int(math.round(f32(x) + s.clone_off.x))
						sy := int(math.round(f32(y) + s.clone_off.y))
						if sx < 0 || sy < 0 || sx >= d.w || sy >= d.h {
							continue
						}
						src: Color
						if s.clone_src != nil {
							src = s.clone_src[sy * w + sx]
						} else {
							src = tiles_get(&s.orig, sx, sy, s.empty)
						}
						res = s.lock_alpha ? lock_mix(o, src, cov * f32(src.a) / 255) : over_px(o, src, cov * f32(src.a) / 255)
					case s.lock_alpha:
						if s.blend != .Normal {
							res = blend_px(o, s.color, cov, s.blend)
							res.a = o.a
						} else {
							res = lock_mix(o, s.color, cov)
						}
					case s.blend != .Normal:
						res = blend_px(o, s.color, cov, s.blend)
					case:
						res = over_px(o, s.color, cov)
					}
					t.pix[li] = res
				}
			}
		}
	}
}

// Colour change that keeps the existing alpha (lock transparency).
lock_mix :: #force_inline proc(o, c: Color, t: f32) -> Color {
	return Color {
		u8(f32(o.r) + (f32(c.r) - f32(o.r)) * t + 0.5),
		u8(f32(o.g) + (f32(c.g) - f32(o.g)) * t + 0.5),
		u8(f32(o.b) + (f32(c.b) - f32(o.b)) * t + 0.5),
		o.a,
	}
}

@(private = "file")
to_pm :: #force_inline proc(c: Color) -> [4]f32 {
	a := f32(c.a) / 255
	return [4]f32{f32(c.r) / 255 * a, f32(c.g) / 255 * a, f32(c.b) / 255 * a, a}
}

@(private = "file")
from_pm :: #force_inline proc(p: [4]f32) -> Color {
	a := clamp(p[3], 0, 1)
	if a < 0.002 {
		return Color{}
	}
	return Color{u8(clamp(p[0] / a, 0, 1) * 255 + 0.5), u8(clamp(p[1] / a, 0, 1) * 255 + 0.5), u8(clamp(p[2] / a, 0, 1) * 255 + 0.5), u8(a * 255 + 0.5)}
}

// Oil: the brush carries a reservoir of paint per bristle position. It deposits its
// colour, picks up what is on the canvas (wetness) and is refilled from the loaded
// colour while paint remains, so colours mix and drag like real wet paint.
dab_oil :: proc(s: ^Stroke, e: ^Tip_Eval, box: Box, dab: Dab, alpha: f32) {
	d := doc
	w := d.w
	b := &s.b
	icx, icy := int(math.round(dab.x)), int(math.round(dab.y))
	cr := s.carry_r
	side := 2 * cr + 1
	opacity := f32(b.opacity) / 100
	wet := f32(b.wet) / 100
	pick := wet * 0.55
	refill := s.paint_left * (1 - wet * 0.75) * 0.45
	paint := [4]f32{f32(s.color.r) / 255, f32(s.color.g) / 255, f32(s.color.b) / 255, 1}
	// Roughly `overlap` dabs pass over each pixel. Deposit so that one pass of the
	// brush leaves the tip's coverage (bristle gaps stay visible) instead of
	// converging to solid paint everywhere.
	overlap := max(2 * e.r / stroke_spacing(s) * 0.7, 1)
	inv_overlap := 1 / max(overlap * e.bristles / 3, 1)
	// wet paint blends into what is there rather than covering it
	cover := 1.25 * (1 - wet * 0.65)
	g := s.target
	for ty in box.y0 / TILE ..= (box.y1 - 1) / TILE {
		for tx in box.x0 / TILE ..= (box.x1 - 1) / TILE {
			x0, x1 := max(box.x0, tx * TILE), min(box.x1, (tx + 1) * TILE)
			y0, y1 := max(box.y0, ty * TILE), min(box.y1, (ty + 1) * TILE)
			t := tiles_write(g, tx, ty, s.empty)
			for y in y0 ..< y1 {
				for x in x0 ..< x1 {
					a := tip_alpha(e, s, x, y) * alpha
					if a <= 0.001 {
						continue
					}
					a *= f32(sel_at(d, y * w + x)) / 255
					li := (y % TILE) * TILE + x % TILE
					cur := t.pix[li]
					cp := to_pm(cur)
					ci := (y - icy + cr) * side + (x - icx + cr)
					c := s.carry[ci]
					c += (cp - c) * (a * pick)
					c += (paint - c) * (a * refill)
					s.carry[ci] = c
					k := 1 - math.pow(1 - min(a * cover * opacity, 0.999), inv_overlap)
					res: Color
					if s.blend != .Normal {
						// the paint on the brush (including what it picked up) goes on with the blend mode
						res = blend_px(cur, from_pm(c), k, s.blend)
					} else {
						res = from_pm(cp + (c - cp) * k)
					}
					if s.lock_alpha {
						res.a = cur.a
					}
					t.pix[li] = res
				}
			}
		}
	}
}

// Smudge: the brush picks up colour and drags it along the stroke.
dab_smudge :: proc(s: ^Stroke, e: ^Tip_Eval, box: Box, dab: Dab, alpha: f32) {
	d := doc
	w := d.w
	b := &s.b
	icx, icy := int(math.round(dab.x)), int(math.round(dab.y))
	cr := s.carry_r
	side := 2 * cr + 1
	str := f32(b.strength) / 100
	keep := 0.5 + 0.5 * str // how much of the carried colour survives each dab
	opacity := f32(b.opacity) / 100
	g := s.target
	first := !s.carry_init
	for ty in box.y0 / TILE ..= (box.y1 - 1) / TILE {
		for tx in box.x0 / TILE ..= (box.x1 - 1) / TILE {
			x0, x1 := max(box.x0, tx * TILE), min(box.x1, (tx + 1) * TILE)
			y0, y1 := max(box.y0, ty * TILE), min(box.y1, (ty + 1) * TILE)
			t := tiles_write(g, tx, ty, s.empty)
			for y in y0 ..< y1 {
				for x in x0 ..< x1 {
					li := (y % TILE) * TILE + x % TILE
					ci := (y - icy + cr) * side + (x - icx + cr)
					cur := t.pix[li]
					cp := to_pm(cur)
					if first {
						s.carry[ci] = cp
						continue
					}
					a := tip_alpha(e, s, x, y) * alpha
					if a <= 0.001 {
						s.carry[ci] = cp
						continue
					}
					a *= f32(sel_at(d, y * w + x)) / 255
					c := s.carry[ci] * keep + cp * (1 - keep)
					s.carry[ci] = c
					np := cp + (c - cp) * (a * opacity * str)
					res := from_pm(np)
					if s.lock_alpha {
						res.a = cur.a
					}
					t.pix[li] = res
				}
			}
		}
	}
	s.carry_init = true
}

// Blur / sharpen against a small neighbourhood average.
dab_blur :: proc(s: ^Stroke, e: ^Tip_Eval, box: Box, alpha: f32) {
	d := doc
	w := d.w
	b := &s.b
	rad := clamp(b.size / 24, 1, 4)
	ex := box_clip(Box{box.x0 - rad, box.y0 - rad, box.x1 + rad, box.y1 + rad}, d.w, d.h)
	ew := ex.x1 - ex.x0
	src := make([]Color, ew * (ex.y1 - ex.y0), context.temp_allocator)
	tiles_read_box(s.target, ex, src, s.empty)
	str := f32(b.strength) / 100
	for y in box.y0 ..< box.y1 {
		for x in box.x0 ..< box.x1 {
			a := tip_alpha(e, s, x, y) * alpha * str * f32(sel_at(d, y * w + x)) / 255
			if a <= 0.002 {
				continue
			}
			acc: [4]f32
			n: f32
			for yy in max(y - rad, ex.y0) ..= min(y + rad, ex.y1 - 1) {
				for xx in max(x - rad, ex.x0) ..= min(x + rad, ex.x1 - 1) {
					acc += to_pm(src[(yy - ex.y0) * ew + xx - ex.x0])
					n += 1
				}
			}
			avg := acc / n
			cp := to_pm(src[(y - ex.y0) * ew + x - ex.x0])
			np: [4]f32
			if b.alt_mode {
				np = cp + (cp - avg) * (a * 1.5)
				np[3] = cp[3]
				for i in 0 ..< 3 do np[i] = clamp(np[i], 0, np[3])
			} else {
				np = cp + (avg - cp) * a
			}
			res := from_pm(np)
			if s.lock_alpha {
				res.a = src[(y - ex.y0) * ew + x - ex.x0].a
			}
			tiles_set(s.target, x, y, res, s.empty)
		}
	}
}

// Dodge (lighten) / burn (darken), weighted towards a tonal range.
dab_dodge :: proc(s: ^Stroke, e: ^Tip_Eval, box: Box, alpha: f32) {
	d := doc
	w := d.w
	b := &s.b
	ex := f32(b.strength) / 100 * 0.25
	for y in box.y0 ..< box.y1 {
		for x in box.x0 ..< box.x1 {
			a := tip_alpha(e, s, x, y) * alpha * f32(sel_at(d, y * w + x)) / 255
			if a <= 0.002 {
				continue
			}
			c := tiles_get(s.target, x, y, s.empty)
			if c.a == 0 {
				continue
			}
			l := f32(luma(c)) / 255
			wt: f32
			switch b.tone {
			case 0:
				wt = (1 - l) * (1 - l)
			case 2:
				wt = l * l
			case:
				wt = 1 - abs(2 * l - 1) * 0.8
			}
			k := a * ex * wt
			res := c
			for i in 0 ..< 3 {
				v := f32(c[i]) / 255
				if b.alt_mode {
					v = v * (1 - k)
				} else {
					v = v + (1 - v) * k
				}
				res[i] = u8(clamp(v, 0, 1) * 255 + 0.5)
			}
			tiles_set(s.target, x, y, res, s.empty)
		}
	}
}
