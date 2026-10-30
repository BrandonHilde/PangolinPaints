package pangolin

// ---------------------------------------------------------------------------
// TIFF: export as one Deflate-compressed RGBA strip (horizontal predictor), and a baseline reader
// for 8-bit greyscale / RGB / RGBA / palette images, uncompressed, PackBits, LZW or Deflate.
// ---------------------------------------------------------------------------

@(private = "file")
T_WIDTH :: 256
@(private = "file")
T_HEIGHT :: 257
@(private = "file")
T_BITS :: 258
@(private = "file")
T_COMPRESSION :: 259
@(private = "file")
T_PHOTOMETRIC :: 262
@(private = "file")
T_STRIP_OFFSETS :: 273
@(private = "file")
T_SAMPLES :: 277
@(private = "file")
T_ROWS_PER_STRIP :: 278
@(private = "file")
T_STRIP_BYTES :: 279
@(private = "file")
T_XRES :: 282
@(private = "file")
T_YRES :: 283
@(private = "file")
T_PLANAR :: 284
@(private = "file")
T_RES_UNIT :: 296
@(private = "file")
T_PREDICTOR :: 317
@(private = "file")
T_COLORMAP :: 320
@(private = "file")
T_EXTRA_SAMPLES :: 338
@(private = "file")
T_SAMPLE_FORMAT :: 339

adler32 :: proc(data: []u8) -> u32 {
	a, b: u32 = 1, 0
	i := 0
	for i < len(data) {
		n := min(len(data) - i, 5552)
		for x in data[i:i + n] {
			a += u32(x)
			b += a
		}
		a %= 65521
		b %= 65521
		i += n
	}
	return b << 16 | a
}

tiff_encode :: proc(pix: []Color, w, h: int) -> []u8 {
	// horizontal differencing makes smooth paint compress far better
	raw := make([]u8, w * h * 4, context.temp_allocator)
	for y in 0 ..< h {
		row := raw[y * w * 4:][:w * 4]
		src := pix[y * w:][:w]
		prev: Color
		for c, x in src {
			row[x * 4 + 0] = c.r - prev.r
			row[x * 4 + 1] = c.g - prev.g
			row[x * 4 + 2] = c.b - prev.b
			row[x * 4 + 3] = c.a - prev.a
			prev = c
		}
	}
	comp, ok := deflate_raw(raw)
	if !ok {
		return nil
	}
	// zlib wrapper: header, raw stream, Adler-32 (big-endian)
	ad := adler32(raw)
	strip := make([dynamic]u8, 0, len(comp) + 6, context.temp_allocator)
	append(&strip, 0x78, 0x01)
	append(&strip, ..comp)
	append(&strip, u8(ad >> 24), u8(ad >> 16), u8(ad >> 8), u8(ad))

	ENTRIES :: 15
	wr := Writer{}
	wr.b = make([dynamic]u8, 0, len(strip) + 256, context.temp_allocator)
	append(&wr.b, 'I', 'I')
	w16(&wr, 42)
	w32(&wr, 8) // first IFD right after the header
	ifd_size := 2 + ENTRIES * 12 + 4
	extra := 8 + ifd_size // bits-per-sample array, then the two resolutions
	data_at := extra + 8 + 16
	ent :: proc(wr: ^Writer, tag, typ: u16, count, val: u32) {
		w16(wr, tag)
		w16(wr, typ)
		w32(wr, count)
		if typ == 3 && count == 1 {
			w16(wr, u16(val))
			w16(wr, 0)
		} else {
			w32(wr, val)
		}
	}
	w16(&wr, ENTRIES)
	ent(&wr, T_WIDTH, 4, 1, u32(w))
	ent(&wr, T_HEIGHT, 4, 1, u32(h))
	ent(&wr, T_BITS, 3, 4, u32(extra))
	ent(&wr, T_COMPRESSION, 3, 1, 8)
	ent(&wr, T_PHOTOMETRIC, 3, 1, 2)
	ent(&wr, T_STRIP_OFFSETS, 4, 1, u32(data_at))
	ent(&wr, T_SAMPLES, 3, 1, 4)
	ent(&wr, T_ROWS_PER_STRIP, 4, 1, u32(h))
	ent(&wr, T_STRIP_BYTES, 4, 1, u32(len(strip)))
	ent(&wr, T_XRES, 5, 1, u32(extra + 8))
	ent(&wr, T_YRES, 5, 1, u32(extra + 16))
	ent(&wr, T_PLANAR, 3, 1, 1)
	ent(&wr, T_RES_UNIT, 3, 1, 2)
	ent(&wr, T_PREDICTOR, 3, 1, 2)
	ent(&wr, T_EXTRA_SAMPLES, 3, 1, 2) // unassociated alpha
	w32(&wr, 0) // no next IFD
	for _ in 0 ..< 4 do w16(&wr, 8)
	w32(&wr, 72)
	w32(&wr, 1)
	w32(&wr, 72)
	w32(&wr, 1)
	append(&wr.b, ..strip[:])
	return wr.b[:]
}

@(private = "file")
Tiff_Reader :: struct {
	d:  []u8,
	be: bool,
}

@(private = "file")
tr16 :: proc(t: ^Tiff_Reader, at: int) -> u32 {
	if at < 0 || at + 2 > len(t.d) do return 0
	a, b := u32(t.d[at]), u32(t.d[at + 1])
	return t.be ? a << 8 | b : b << 8 | a
}

@(private = "file")
tr32 :: proc(t: ^Tiff_Reader, at: int) -> u32 {
	if at < 0 || at + 4 > len(t.d) do return 0
	a, b := tr16(t, at), tr16(t, at + 2)
	return t.be ? a << 16 | b : b << 16 | a
}

// Values of one IFD entry (SHORT or LONG), as u32s.
@(private = "file")
tiff_values :: proc(t: ^Tiff_Reader, e: int) -> []u32 {
	typ := tr16(t, e + 2)
	n := int(tr32(t, e + 4))
	size := typ == 3 ? 2 : 4
	if n <= 0 || n > 1 << 24 || (typ != 3 && typ != 4) do return nil
	at := e + 8
	if n * size > 4 {
		at = int(tr32(t, e + 8))
	}
	if at + n * size > len(t.d) do return nil
	out := make([]u32, n, context.temp_allocator)
	for &v, i in out {
		v = size == 2 ? tr16(t, at + i * 2) : tr32(t, at + i * 4)
	}
	return out
}

@(private = "file")
unpack_bits :: proc(src: []u8, out: []u8) -> bool {
	i, o := 0, 0
	for i < len(src) && o < len(out) {
		n := int(i8(src[i]))
		i += 1
		if n >= 0 {
			cnt := n + 1
			if i + cnt > len(src) || o + cnt > len(out) do return false
			copy(out[o:], src[i:i + cnt])
			i += cnt
			o += cnt
		} else if n != -128 {
			cnt := 1 - n
			if i >= len(src) || o + cnt > len(out) do return false
			for k in 0 ..< cnt do out[o + k] = src[i]
			i += 1
			o += cnt
		}
	}
	return o == len(out)
}

// TIFF LZW: MSB-first codes, 9..12 bits, with the "early change" one code before the table fills.
@(private = "file")
unlzw :: proc(src: []u8, out: []u8) -> bool {
	prefix := make([]u16, 4096, context.temp_allocator)
	suffix := make([]u8, 4096, context.temp_allocator)
	first := make([]u8, 4096, context.temp_allocator)
	length := make([]u16, 4096, context.temp_allocator)
	for i in 0 ..< 256 {
		suffix[i], first[i], length[i] = u8(i), u8(i), 1
	}
	next := 258
	bits := uint(9)
	acc: u32
	nacc: uint
	pos, o := 0, 0
	old := -1
	// writes a code's string, cut short at the end of `out`
	emit :: proc(code: int, out: []u8, o: ^int, prefix: []u16, suffix: []u8, length: []u16) {
		n := int(length[code])
		keep := min(n, len(out) - o^)
		c := code
		for k := n - 1; k >= 0; k -= 1 {
			if k < keep do out[o^ + k] = suffix[c]
			c = int(prefix[c])
		}
		o^ += keep
	}
	for o < len(out) {
		for nacc < bits {
			if pos >= len(src) do return o == len(out)
			acc = acc << 8 | u32(src[pos])
			pos += 1
			nacc += 8
		}
		code := int((acc >> (nacc - bits)) & ((1 << bits) - 1))
		nacc -= bits
		if code == 257 do break
		if code == 256 {
			next = 258
			bits = 9
			old = -1
			continue
		}
		if old < 0 {
			if code > 255 do return false
			out[o] = u8(code)
			o += 1
			old = code
			continue
		}
		if code < next {
			emit(code, out, &o, prefix, suffix, length)
			if next < 4096 {
				prefix[next], suffix[next], first[next], length[next] = u16(old), first[code], first[old], length[old] + 1
				next += 1
			}
		} else if code == next && next < 4096 {
			prefix[next], suffix[next], first[next], length[next] = u16(old), first[old], first[old], length[old] + 1
			next += 1
			emit(code, out, &o, prefix, suffix, length)
		} else {
			return false
		}
		old = code
		if next + 1 >= 1 << bits && bits < 12 do bits += 1
	}
	return o == len(out)
}

tiff_decode :: proc(data: []u8) -> (pix: []Color, w, h: int, ok: bool) {
	if len(data) < 8 do return
	t := Tiff_Reader{d = data}
	switch string(data[:2]) {
	case "II":
	case "MM":
		t.be = true
	case:
		return
	}
	if tr16(&t, 2) != 42 do return
	ifd := int(tr32(&t, 4))
	n := int(tr16(&t, ifd))
	if ifd <= 0 || ifd + 2 + n * 12 > len(data) do return
	bits := []u32{1}
	comp, photo, spp, rps, planar, pred, fmt_ := u32(1), u32(1), u32(1), u32(0), u32(1), u32(1), u32(1)
	offs, counts, cmap, extras: []u32
	for i in 0 ..< n {
		e := ifd + 2 + i * 12
		v := tiff_values(&t, e)
		if len(v) == 0 do continue
		switch tr16(&t, e) {
		case T_WIDTH:
			w = int(v[0])
		case T_HEIGHT:
			h = int(v[0])
		case T_BITS:
			bits = v
		case T_COMPRESSION:
			comp = v[0]
		case T_PHOTOMETRIC:
			photo = v[0]
		case T_STRIP_OFFSETS:
			offs = v
		case T_SAMPLES:
			spp = v[0]
		case T_ROWS_PER_STRIP:
			rps = v[0]
		case T_STRIP_BYTES:
			counts = v
		case T_PLANAR:
			planar = v[0]
		case T_PREDICTOR:
			pred = v[0]
		case T_COLORMAP:
			cmap = v
		case T_EXTRA_SAMPLES:
			extras = v
		case T_SAMPLE_FORMAT:
			fmt_ = v[0]
		}
	}
	if w <= 0 || h <= 0 || w > 16384 || h > 16384 || spp < 1 || spp > 8 || planar != 1 || fmt_ != 1 do return
	for b in bits do if b != 8 do return
	if photo > 3 || (photo == 3 && (spp != 1 || len(cmap) < 768)) || (photo == 2 && spp < 3) do return
	if len(offs) == 0 || len(offs) != len(counts) do return
	if rps == 0 || rps > u32(h) do rps = u32(h)
	row := w * int(spp)
	raw := make([]u8, row * h, context.temp_allocator)
	for s in 0 ..< len(offs) {
		y0 := s * int(rps)
		if y0 >= h do break
		dst := raw[y0 * row:][:min(int(rps), h - y0) * row]
		a, c := int(offs[s]), int(counts[s])
		if a < 0 || c < 0 || a + c > len(data) do return
		src := data[a:a + c]
		switch comp {
		case 1:
			if len(src) < len(dst) do return
			copy(dst, src)
		case 5:
			if !unlzw(src, dst) do return
		case 8, 32946:
			if len(src) < 6 || !inflate_raw(src[2:], dst) do return
		case 32773:
			if !unpack_bits(src, dst) do return
		case:
			return
		}
	}
	if pred == 2 {
		for y in 0 ..< h {
			r := raw[y * row:][:row]
			for x in int(spp) ..< row do r[x] += r[x - int(spp)]
		}
	}
	// associated (premultiplied) alpha is extra sample type 1
	premul := len(extras) > 0 && extras[0] == 1
	has_alpha := (photo == 2 && spp >= 4) || (photo <= 1 && spp >= 2)
	pix = make([]Color, w * h)
	for i in 0 ..< w * h {
		s := raw[i * int(spp):]
		c: Color
		switch photo {
		case 0, 1:
			g := s[0]
			if photo == 0 do g = 255 - g
			c = Color{g, g, g, has_alpha ? s[1] : 255}
		case 2:
			c = Color{s[0], s[1], s[2], has_alpha ? s[3] : 255}
		case 3:
			k := int(s[0])
			c = Color{u8(cmap[k] >> 8), u8(cmap[256 + k] >> 8), u8(cmap[512 + k] >> 8), 255}
		}
		if premul && c.a > 0 && c.a < 255 {
			c.r = u8(min(int(c.r) * 255 / int(c.a), 255))
			c.g = u8(min(int(c.g) * 255 / int(c.a), 255))
			c.b = u8(min(int(c.b) * 255 / int(c.a), 255))
		}
		pix[i] = c
	}
	ok = true
	return
}
