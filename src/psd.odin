package pangolin

import "core:strings"
import "core:unicode/utf16"
import "core:unicode/utf8"

// ---------------------------------------------------------------------------
// Photoshop documents (.psd / .psb) as layered documents: pixel layers with name, opacity, blend
// mode, visibility and layer masks, in 8 or 16 bits per channel, RGB, greyscale or CMYK.
// Groups are flattened into the layer list (a hidden group hides its layers, group opacity carries
// over). Files with no readable layers fall back to the merged image Photoshop stores at the end.
// ---------------------------------------------------------------------------

@(private = "file")
Psd_Reader :: struct {
	d:   []u8,
	pos: int,
	bad: bool,
	psb: bool, // large document format: some lengths are 64-bit
}

@(private = "file")
p8 :: proc(r: ^Psd_Reader) -> int {
	if r.pos >= len(r.d) {
		r.bad = true
		return 0
	}
	r.pos += 1
	return int(r.d[r.pos - 1])
}

@(private = "file")
p16 :: proc(r: ^Psd_Reader) -> int {
	return p8(r) << 8 | p8(r)
}

@(private = "file")
p32 :: proc(r: ^Psd_Reader) -> int {
	return p16(r) << 16 | p16(r)
}

@(private = "file")
pi32 :: proc(r: ^Psd_Reader) -> int {
	return int(i32(u32(p32(r))))
}

// A length that is 64-bit in PSB files.
@(private = "file")
plen :: proc(r: ^Psd_Reader) -> int {
	if r.psb {
		hi := p32(r)
		lo := p32(r)
		if hi != 0 {
			r.bad = true
			return 0
		}
		return lo
	}
	return p32(r)
}

@(private = "file")
pskip :: proc(r: ^Psd_Reader, n: int) {
	if n < 0 || r.pos + n > len(r.d) {
		r.bad = true
		r.pos = len(r.d)
		return
	}
	r.pos += n
}

@(private = "file")
pbytes :: proc(r: ^Psd_Reader, n: int) -> []u8 {
	if n < 0 || r.pos + n > len(r.d) {
		r.bad = true
		return nil
	}
	r.pos += n
	return r.d[r.pos - n:r.pos]
}

PSD_BLENDS := [?]struct {
	key:   string,
	blend: Blend,
}{
	{"norm", .Normal}, {"mul ", .Multiply}, {"scrn", .Screen}, {"over", .Overlay}, {"sLit", .Soft_Light},
	{"hLit", .Hard_Light}, {"dark", .Darken}, {"lite", .Lighten}, {"div ", .Color_Dodge}, {"idiv", .Color_Burn},
	{"lddg", .Add}, {"fsub", .Subtract}, {"diff", .Difference}, {"hue ", .Hue}, {"sat ", .Saturation},
	{"colr", .Color}, {"lum ", .Luminosity},
}

// Legacy layer names are Mac Roman; these are bytes 128-255.
@(private = "file")
MAC_ROMAN := [128]u16{
	0x00C4, 0x00C5, 0x00C7, 0x00C9, 0x00D1, 0x00D6, 0x00DC, 0x00E1, 0x00E0, 0x00E2, 0x00E4, 0x00E3, 0x00E5, 0x00E7, 0x00E9, 0x00E8,
	0x00EA, 0x00EB, 0x00ED, 0x00EC, 0x00EE, 0x00EF, 0x00F1, 0x00F3, 0x00F2, 0x00F4, 0x00F6, 0x00F5, 0x00FA, 0x00F9, 0x00FB, 0x00FC,
	0x2020, 0x00B0, 0x00A2, 0x00A3, 0x00A7, 0x2022, 0x00B6, 0x00DF, 0x00AE, 0x00A9, 0x2122, 0x00B4, 0x00A8, 0x2260, 0x00C6, 0x00D8,
	0x221E, 0x00B1, 0x2264, 0x2265, 0x00A5, 0x00B5, 0x2202, 0x2211, 0x220F, 0x03C0, 0x222B, 0x00AA, 0x00BA, 0x03A9, 0x00E6, 0x00F8,
	0x00BF, 0x00A1, 0x00AC, 0x221A, 0x0192, 0x2248, 0x2206, 0x00AB, 0x00BB, 0x2026, 0x00A0, 0x00C0, 0x00C3, 0x00D5, 0x0152, 0x0153,
	0x2013, 0x2014, 0x201C, 0x201D, 0x2018, 0x2019, 0x00F7, 0x25CA, 0x00FF, 0x0178, 0x2044, 0x20AC, 0x2039, 0x203A, 0xFB01, 0xFB02,
	0x2021, 0x00B7, 0x201A, 0x201E, 0x2030, 0x00C2, 0x00CA, 0x00C1, 0x00CB, 0x00C8, 0x00CD, 0x00CE, 0x00CF, 0x00CC, 0x00D3, 0x00D4,
	0xF8FF, 0x00D2, 0x00DA, 0x00DB, 0x00D9, 0x0131, 0x02C6, 0x02DC, 0x00AF, 0x02D8, 0x02D9, 0x02DA, 0x00B8, 0x02DD, 0x02DB, 0x02C7,
}

@(private = "file")
mac_roman_string :: proc(b: []u8) -> string {
	sb := strings.builder_make(context.temp_allocator)
	for c in b {
		strings.write_rune(&sb, c < 128 ? rune(c) : rune(MAC_ROMAN[c - 128]))
	}
	return strings.to_string(sb)
}

@(private = "file")
Psd_Channel :: struct {
	id:  int,
	len: int,
}

@(private = "file")
Psd_Layer :: struct {
	top, left, bottom, right: int,
	chans:                    [dynamic]Psd_Channel,
	blend:                    Blend,
	opacity:                  int,
	hidden:                   bool,
	name:                     string,
	divider:                  int, // lsct: 1/2 group start (listed after its contents), 3 group end marker
	doc_i:                    int, // index of the document layer made from it, or -1
	// layer mask
	m_top, m_left, m_bottom, m_right: int,
	m_default:                int,
	m_flags:                  int,
}

// Decodes one channel's data (already positioned after its compression word) into w*h bytes;
// 16-bit samples keep their high byte.
@(private = "file")
psd_channel_data :: proc(r: ^Psd_Reader, comp, w, h, depth, size: int) -> []u8 {
	bpc := depth / 8
	row := w * bpc
	raw := make([]u8, row * h, context.temp_allocator)
	switch comp {
	case 0:
		src := pbytes(r, row * h)
		if src == nil do return nil
		copy(raw, src)
	case 1:
		counts := make([]int, h, context.temp_allocator)
		for &c in counts do c = r.psb ? p32(r) : p16(r)
		for c, y in counts {
			src := pbytes(r, c)
			if src == nil || !psd_unpack_bits(src, raw[y * row:][:row]) do return nil
		}
	case 2, 3:
		src := pbytes(r, size)
		if len(src) < 6 || !inflate_raw(src[2:], raw) do return nil
		if comp == 3 {
			// delta prediction per row, on whole samples
			for y in 0 ..< h {
				rr := raw[y * row:][:row]
				if bpc == 1 {
					for x in 1 ..< w do rr[x] += rr[x - 1]
				} else {
					prev: u16
					for x in 0 ..< w {
						v := u16(rr[x * 2]) << 8 | u16(rr[x * 2 + 1])
						v += prev
						prev = v
						rr[x * 2], rr[x * 2 + 1] = u8(v >> 8), u8(v)
					}
				}
			}
		}
	case:
		return nil
	}
	if bpc == 1 do return raw
	out := make([]u8, w * h, context.temp_allocator)
	for i in 0 ..< w * h do out[i] = raw[i * bpc] // big-endian: the high byte comes first
	return out
}

@(private = "file")
psd_unpack_bits :: proc(src: []u8, out: []u8) -> bool {
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

// Colour from the planes of one pixel in the document's colour mode.
@(private = "file")
psd_color :: proc(mode: int, c0, c1, c2, c3: u8) -> Color {
	switch mode {
	case 1, 8:
		return Color{c0, c0, c0, 255}
	case 4:
		// stored inverted: 255 is no ink
		k := int(c3)
		return Color{u8(int(c0) * k / 255), u8(int(c1) * k / 255), u8(int(c2) * k / 255), 255}
	}
	return Color{c0, c1, c2, 255}
}

@(private = "file")
psd_color_channels :: proc(mode: int) -> int {
	switch mode {
	case 1, 8:
		return 1
	case 4:
		return 4
	}
	return 3
}

// Reads a .psd / .psb file into a new document; `msg` explains a failure.
psd_load :: proc(data: []u8, title: string) -> (d: ^Doc, msg: string) {
	r := Psd_Reader{d = data}
	if len(data) < 26 || string(data[:4]) != "8BPS" {
		return nil, "This is not a Photoshop file."
	}
	r.pos = 4
	ver := p16(&r)
	if ver != 1 && ver != 2 do return nil, "Unsupported Photoshop file version."
	r.psb = ver == 2
	pskip(&r, 6)
	nchan := p16(&r)
	h := p32(&r)
	w := p32(&r)
	depth := p16(&r)
	mode := p16(&r)
	if w < 1 || h < 1 || w > 16384 || h > 16384 {
		return nil, "The image is too large (16384 x 16384 at most)."
	}
	if depth != 8 && depth != 16 {
		return nil, "Only 8 and 16 bit Photoshop files can be opened."
	}
	if mode != 1 && mode != 3 && mode != 4 && mode != 8 {
		return nil, "Only RGB, greyscale and CMYK Photoshop files can be opened."
	}
	pskip(&r, p32(&r)) // colour mode data
	pskip(&r, p32(&r)) // image resources
	lm_len := plen(&r)
	lm_end := r.pos + lm_len
	nd := doc_new(w, h, title)
	for &l in nd.layers do layer_destroy(&l)
	clear(&nd.layers)
	if lm_len > 0 && !r.bad {
		psd_read_layers(&r, nd, w, h, depth, mode)
	}
	if len(nd.layers) == 0 && lm_end <= len(data) {
		// no usable layers: the merged image after the layer section
		r.bad = false
		r.pos = lm_end
		comp := p16(&r)
		planes: [5][]u8
		for c in 0 ..< min(nchan, 5) {
			if comp == 1 {
				// all row counts for all channels come first
				psd_merged_rle(&r, planes[:], min(nchan, 5), w, h, depth)
				break
			}
			planes[c] = psd_channel_data(&r, comp, w, h, depth, len(data) - r.pos)
		}
		nc := psd_color_channels(mode)
		if planes[nc - 1] != nil {
			pix := make([]Color, w * h, context.temp_allocator)
			for i in 0 ..< w * h {
				get :: proc(p: []u8, i: int) -> u8 {return p != nil ? p[i] : 0}
				pix[i] = psd_color(mode, planes[0][i], get(planes[1], i), get(planes[2], i), get(planes[3], i))
				if nchan > nc && planes[nc] != nil do pix[i].a = planes[nc][i]
			}
			l := layer_make("Background", w, h)
			tiles_from_buf(&l.pix, w, h, pix, {})
			append(&nd.layers, l)
		}
	}
	if len(nd.layers) == 0 {
		doc_destroy(nd)
		return nil, "Could not read the image data in this Photoshop file."
	}
	nd.active_layer = len(nd.layers) - 1
	doc_clamp(nd)
	nd.modified = false
	return nd, ""
}

@(private = "file")
psd_merged_rle :: proc(r: ^Psd_Reader, planes: [][]u8, n, w, h, depth: int) {
	row := w * depth / 8
	counts := make([]int, n * h, context.temp_allocator)
	for &c in counts do c = r.psb ? p32(r) : p16(r)
	for c in 0 ..< n {
		raw := make([]u8, row * h, context.temp_allocator)
		for y in 0 ..< h {
			src := pbytes(r, counts[c * h + y])
			if src == nil || !psd_unpack_bits(src, raw[y * row:][:row]) do return
		}
		if depth == 16 {
			out := make([]u8, w * h, context.temp_allocator)
			for i in 0 ..< w * h do out[i] = raw[i * 2]
			planes[c] = out
		} else {
			planes[c] = raw
		}
	}
}

@(private = "file")
psd_read_layers :: proc(r: ^Psd_Reader, nd: ^Doc, w, h, depth, mode: int) {
	li_len := plen(r)
	if li_len == 0 || r.bad do return
	count := int(i16(u16(p16(r))))
	if count < 0 do count = -count
	if count > 4096 do return
	recs := make([]Psd_Layer, count, context.temp_allocator)
	for &L in recs {
		L.top, L.left, L.bottom, L.right = pi32(r), pi32(r), pi32(r), pi32(r)
		nc := p16(r)
		if nc > 64 {
			r.bad = true
			return
		}
		L.chans = make([dynamic]Psd_Channel, context.temp_allocator)
		for _ in 0 ..< nc {
			id := int(i16(u16(p16(r))))
			append(&L.chans, Psd_Channel{id, plen(r)})
		}
		if string(pbytes(r, 4)) != "8BIM" {
			r.bad = true
			return
		}
		key := string(pbytes(r, 4))
		for b in PSD_BLENDS {
			if b.key == key do L.blend = b.blend
		}
		L.opacity = p8(r)
		p8(r) // clipping (clipping masks are not supported: the layer is kept unclipped)
		flags := p8(r)
		L.hidden = flags & 2 != 0
		p8(r)
		extra := p32(r)
		end := r.pos + extra
		// layer mask data
		ml := p32(r)
		mend := r.pos + ml
		if ml >= 18 {
			L.m_top, L.m_left, L.m_bottom, L.m_right = pi32(r), pi32(r), pi32(r), pi32(r)
			L.m_default = p8(r)
			L.m_flags = p8(r)
		}
		r.pos = mend
		pskip(r, p32(r)) // blending ranges
		nl := p8(r)
		L.name = mac_roman_string(pbytes(r, nl))
		pskip(r, (4 - (nl + 1) % 4) % 4)
		// additional layer info: the Unicode name and group markers
		for r.pos + 12 <= end && !r.bad {
			sig := string(pbytes(r, 4))
			if sig != "8BIM" && sig != "8B64" do break
			k := string(pbytes(r, 4))
			long_keys := [?]string{"LMsk", "Lr16", "Lr32", "Layr", "Mt16", "Mt32", "Mtrn", "Alph", "FMsk", "lnk2", "FEid", "FXid", "PxSD"}
			is_long := false
			if r.psb {
				for lk in long_keys do if lk == k do is_long = true
			}
			n := is_long ? plen(r) : p32(r)
			bend := r.pos + n
			switch k {
			case "luni":
				cnt := p32(r)
				if cnt > 0 && cnt < 1024 {
					u := make([]u16, cnt, context.temp_allocator)
					for &c in u do c = u16(p16(r))
					rs := make([]rune, cnt, context.temp_allocator)
					rn := utf16.decode(rs, u)
					for rn > 0 && rs[rn - 1] == 0 do rn -= 1 // some writers count the terminator
					L.name = utf8.runes_to_string(rs[:rn], context.temp_allocator)
				}
			case "lsct", "lsdk":
				L.divider = p32(r)
			}
			r.pos = bend
		}
		r.pos = end
		if r.bad do return
	}
	// channel image data, layer by layer in the same order
	nc := psd_color_channels(mode)
	for i in 0 ..< len(recs) {
		L := &recs[i]
		L.doc_i = -1
		lw, lh := L.right - L.left, L.bottom - L.top
		chan_data := make([dynamic][]u8, context.temp_allocator)
		mask: []u8
		for ch in L.chans {
			start := r.pos
			comp := p16(r)
			cw, chh := lw, lh
			if ch.id == -2 || ch.id == -3 {
				cw, chh = L.m_right - L.m_left, L.m_bottom - L.m_top
			}
			data: []u8
			if cw > 0 && chh > 0 && cw <= 32768 && chh <= 32768 && ch.len > 2 {
				data = psd_channel_data(r, comp, cw, chh, depth, ch.len - 2)
			}
			r.pos = start + ch.len
			if ch.id == -2 {
				mask = data
			}
			append(&chan_data, data)
		}
		if r.bad do return
		if L.divider != 0 do continue
		if lw <= 0 || lh <= 0 || lw > 32768 || lh > 32768 {
			// an empty layer still keeps its place
			l := layer_make(L.name, w, h)
			l.blend, l.opacity, l.visible = L.blend, u8(L.opacity), !L.hidden
			L.doc_i = len(nd.layers)
			append(&nd.layers, l)
			continue
		}
		find :: proc(L: ^Psd_Layer, data: [][]u8, id: int) -> []u8 {
			for ch, k in L.chans do if ch.id == id do return data[k]
			return nil
		}
		cp: [4][]u8
		for c in 0 ..< nc do cp[c] = find(L, chan_data[:], c)
		alpha := find(L, chan_data[:], -1)
		if cp[nc - 1] == nil do continue
		l := layer_make(L.name, w, h)
		l.blend, l.opacity, l.visible = L.blend, u8(L.opacity), !L.hidden
		buf := make([]Color, lw * lh, context.temp_allocator)
		for k in 0 ..< lw * lh {
			get :: proc(p: []u8, i: int) -> u8 {return p != nil ? p[i] : 0}
			buf[k] = psd_color(mode, cp[0][k], get(cp[1], k), get(cp[2], k), get(cp[3], k))
			buf[k].a = alpha != nil ? alpha[k] : 255
		}
		psd_blit(&l.pix, w, h, L.left, L.top, lw, lh, buf)
		// a mask that hides nothing is left out
		hides := L.m_default != 255
		for v in mask do if v != 255 do hides = true
		if mask != nil && L.m_flags & 2 == 0 && hides {
			// mask outside its rectangle has the default colour; inside, the stored grey
			mw, mh := L.m_right - L.m_left, L.m_bottom - L.m_top
			full := make([]Color, w * h, context.temp_allocator)
			dv := u8(L.m_default)
			for &p in full do p = Color{dv, dv, dv, 255}
			for y in 0 ..< mh {
				py := L.m_top + y
				if py < 0 || py >= h do continue
				for x in 0 ..< mw {
					px := L.m_left + x
					if px < 0 || px >= w do continue
					v := mask[y * mw + x]
					full[py * w + px] = Color{v, v, v, 255}
				}
			}
			l.has_mask = true
			l.mask_on = true
			l.mask = tiles_make(w, h)
			tiles_from_buf(&l.mask, w, h, full, MASK_EMPTY)
		}
		L.doc_i = len(nd.layers)
		append(&nd.layers, l)
	}
	psd_apply_groups(recs, nd)
}

// Writes a layer's pixels at (x, y), clipped to the canvas.
@(private = "file")
psd_blit :: proc(g: ^Tiles, w, h, x0, y0, lw, lh: int, buf: []Color) {
	b := box_clip(Box{x0, y0, x0 + lw, y0 + lh}, w, h)
	if box_empty(b) do return
	bw := b.x1 - b.x0
	sub := make([]Color, bw * (b.y1 - b.y0), context.temp_allocator)
	for y in b.y0 ..< b.y1 {
		copy(sub[(y - b.y0) * bw:][:bw], buf[(y - y0) * lw + (b.x0 - x0):][:bw])
	}
	tiles_write_box(g, b, sub, {})
	tiles_compact_box(g, b, {})
}

// Hidden groups hide their layers and group opacity multiplies in. Records run bottom to top, so a
// group's settings are on the record after its contents; walk top-down to apply them.
@(private = "file")
psd_apply_groups :: proc(recs: []Psd_Layer, nd: ^Doc) {
	Group :: struct {
		hidden:  bool,
		opacity: int,
	}
	stack := make([dynamic]Group, context.temp_allocator)
	hidden := false
	op := 255
	for i := len(recs) - 1; i >= 0; i -= 1 {
		L := &recs[i]
		switch L.divider {
		case 1, 2:
			append(&stack, Group{hidden, op})
			hidden = hidden || L.hidden
			op = op * L.opacity / 255
		case 3:
			if len(stack) > 0 {
				g := pop(&stack)
				hidden, op = g.hidden, g.opacity
			}
		case:
			if k := L.doc_i; k >= 0 {
				l := &nd.layers[k]
				if hidden do l.visible = false
				l.opacity = u8(int(l.opacity) * op / 255)
			}
		}
	}
}
