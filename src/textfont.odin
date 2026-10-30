package pangolin

import "core:math"
import "core:os"
import "core:slice"
import "core:strings"
import "core:unicode/utf16"
import "core:unicode/utf8"
import stbtt "vendor:stb/truetype"

// ---------------------------------------------------------------------------
// Fonts for text layers: the two bundled families plus every TTF / OTF installed on the system.
// System fonts are only listed (by reading their `name` table) and loaded when first drawn with.
// ---------------------------------------------------------------------------

ALICE_DATA :: #load("../assets/fonts/Alice-Regular.ttf")

DEFAULT_FONT :: "Alice"

Ufont :: struct {
	name:  string, // display name; also the key stored in documents
	path:  string, // empty for bundled fonts
	data:  []u8, // loaded lazily
	info:  stbtt.fontinfo,
	ok:    bool,
	tried: bool,
}

ufonts: [dynamic]^Ufont
ufonts_scanned: bool

ufont_add :: proc(name, path: string, data: []u8 = nil) {
	for f in ufonts {
		if f.name == name do return
	}
	f := new(Ufont)
	f.name = strings.clone(name)
	f.path = strings.clone(path)
	f.data = data
	append(&ufonts, f)
}

@(private = "file")
be16 :: proc(b: []u8, i: int) -> int {
	return int(b[i]) << 8 | int(b[i + 1])
}

// Reads the full name (name ID 4) of an sfnt file without loading the whole file.
font_file_name :: proc(path: string) -> (name: string, ok: bool) {
	fh, err := os.open(path)
	if err != nil do return
	defer os.close(fh)
	head: [12]u8
	if n, e := os.read(fh, head[:]); e != nil || n < 12 do return
	tag := string(head[:4])
	if tag != "\x00\x01\x00\x00" && tag != "OTTO" && tag != "true" do return
	count := int(head[4]) << 8 | int(head[5])
	if count < 1 || count > 64 do return
	dir := make([]u8, count * 16, context.temp_allocator)
	if n, e := os.read(fh, dir); e != nil || n < len(dir) do return
	off, length := 0, 0
	for i in 0 ..< count {
		e := dir[i * 16:][:16]
		if string(e[:4]) == "name" {
			off = int(e[8]) << 24 | int(e[9]) << 16 | int(e[10]) << 8 | int(e[11])
			length = int(e[12]) << 24 | int(e[13]) << 16 | int(e[14]) << 8 | int(e[15])
		}
	}
	if off == 0 || length < 6 || length > 1 << 20 do return
	if _, e := os.seek(fh, i64(off), .Start); e != nil do return
	tbl := make([]u8, length, context.temp_allocator)
	if n, e := os.read(fh, tbl); e != nil || n < length do return
	cnt, soff := be16(tbl, 2), be16(tbl, 4)
	best: string
	best_score := 0
	for i in 0 ..< cnt {
		r := 6 + i * 12
		if r + 12 > length do break
		plat, lang, nid, ln, so := be16(tbl, r), be16(tbl, r + 4), be16(tbl, r + 6), be16(tbl, r + 8), be16(tbl, r + 10)
		if nid != 4 || soff + so + ln > length do continue
		raw := tbl[soff + so:][:ln]
		score := 0
		s: string
		if plat == 3 {
			u := make([]u16, ln / 2, context.temp_allocator)
			for k in 0 ..< len(u) do u[k] = u16(raw[k * 2]) << 8 | u16(raw[k * 2 + 1])
			rs := make([]rune, len(u), context.temp_allocator)
			n := utf16.decode(rs, u)
			s = utf8.runes_to_string(rs[:n], context.temp_allocator)
			score = lang == 0x409 ? 3 : 2
		} else if plat == 1 {
			s = strings.clone(string(raw), context.temp_allocator)
			score = 1
		}
		if score > best_score && len(s) > 0 {
			best, best_score = s, score
		}
	}
	if best_score == 0 do return
	return best, true
}

@(private = "file")
scan_font_dir :: proc(dir: string, depth: int) {
	infos, err := os.read_directory_by_path(dir, -1, context.temp_allocator)
	if err != nil do return
	for fi in infos {
		if fi.type == .Directory {
			if depth > 0 do scan_font_dir(fi.fullpath, depth - 1)
			continue
		}
		ext := lower_ext(fi.name)
		if ext != ".ttf" && ext != ".otf" do continue
		if nm, ok := font_file_name(fi.fullpath); ok {
			ufont_add(nm, fi.fullpath)
		}
	}
}

fonts_ensure :: proc() {
	if ufonts_scanned do return
	ufonts_scanned = true
	ufont_add("Alice", "", ALICE_DATA)
	ufont_add("Jersey 10", "", FONT_DATA)
	when ODIN_OS == .Windows {
		scan_font_dir("C:\\Windows\\Fonts", 0)
		if la := os.get_env("LOCALAPPDATA", context.temp_allocator); la != "" {
			scan_font_dir(strings.concatenate({la, "\\Microsoft\\Windows\\Fonts"}, context.temp_allocator), 0)
		}
	} else when ODIN_OS == .Darwin {
		scan_font_dir("/Library/Fonts", 1)
		scan_font_dir("/System/Library/Fonts", 1)
	} else {
		scan_font_dir("/usr/share/fonts", 4)
		scan_font_dir("/usr/local/share/fonts", 4)
		if h := os.get_env("HOME", context.temp_allocator); h != "" {
			scan_font_dir(strings.concatenate({h, "/.local/share/fonts"}, context.temp_allocator), 4)
		}
	}
	slice.sort_by(ufonts[:], proc(a, b: ^Ufont) -> bool {
		return strings.compare(strings.to_lower(a.name, context.temp_allocator), strings.to_lower(b.name, context.temp_allocator)) < 0
	})
}

// The font stored under `key`, or the default one when it is missing on this machine.
ufont_get :: proc(key: string) -> ^Ufont {
	fonts_ensure()
	found: ^Ufont
	for f in ufonts {
		if f.name == key {
			found = f
			break
		}
	}
	if found == nil || !ufont_load(found) {
		for f in ufonts {
			if f.name == DEFAULT_FONT {
				ufont_load(f)
				return f
			}
		}
	}
	return found
}

ufont_load :: proc(f: ^Ufont) -> bool {
	if f.tried do return f.ok
	f.tried = true
	if f.data == nil && f.path != "" {
		d, err := os.read_entire_file_from_path(f.path, context.allocator)
		if err != nil do return false
		f.data = d
	}
	if f.data == nil do return false
	f.ok = bool(stbtt.InitFont(&f.info, raw_data(f.data), stbtt.GetFontOffsetForIndex(raw_data(f.data), 0)))
	return f.ok
}

// Text layout and rendering ----------------------------------------------------

Text_Line :: struct {
	a, b: int, // byte range in the buffer
	w:    f32, // width in pixels
}

Text_Layout :: struct {
	face:  ^Ufont,
	sc:    f32,
	asc:   f32,
	lh:    f32, // line pitch
	lines: [dynamic]Text_Line,
	w:     f32, // widest line
}

text_str :: proc(ti: ^Text_Info) -> string {
	return string(ti.buf[:ti.n])
}

// Character colours -------------------------------------------------------------

text_char_color :: proc(ti: ^Text_Info, i: int) -> Color {
	k := int(ti.cidx[i])
	if k == 0 || k > ti.npal do return ti.color
	return ti.pal[k - 1]
}

// Drops palette entries no character uses any more.
text_pal_compact :: proc(ti: ^Text_Info) {
	used: [TEXT_PAL + 1]bool
	for k in ti.cidx[:ti.n] do used[k] = true
	remap: [TEXT_PAL + 1]u8
	n := 0
	for k in 1 ..= ti.npal {
		if used[k] {
			ti.pal[n] = ti.pal[k - 1]
			n += 1
			remap[k] = u8(n)
		}
	}
	for &k in ti.cidx[:ti.n] do k = remap[k]
	ti.npal = n
}

// Colour index for `c` (0 = the text's own colour), adding it to the palette; -1 if there is no room.
text_pal_index :: proc(ti: ^Text_Info, c: Color) -> int {
	if c == ti.color do return 0
	for p, k in ti.pal[:ti.npal] {
		if p == c do return k + 1
	}
	if ti.npal == TEXT_PAL do text_pal_compact(ti)
	if ti.npal == TEXT_PAL do return -1
	ti.pal[ti.npal] = c
	ti.npal += 1
	return ti.npal
}

text_color_range :: proc(ti: ^Text_Info, a, b: int, c: Color) {
	k := text_pal_index(ti, c)
	if k < 0 do return
	for &x in ti.cidx[a:b] do x = u8(k)
	text_pal_compact(ti)
}

// One colour for the whole text.
text_color_all :: proc(ti: ^Text_Info, c: Color) {
	ti.color = c
	ti.npal = 0
	for &x in ti.cidx[:ti.n] do x = 0
}

// Inserts UTF-8 bytes at byte index `at` with colour index `k`; returns how many bytes fit.
text_insert_bytes :: proc(ti: ^Text_Info, at: int, s: []u8, k: u8) -> int {
	n := min(len(s), TEXT_MAX - ti.n)
	if n <= 0 do return 0
	copy(ti.buf[at + n:ti.n + n], ti.buf[at:ti.n])
	copy(ti.cidx[at + n:ti.n + n], ti.cidx[at:ti.n])
	copy(ti.buf[at:at + n], s[:n])
	for &x in ti.cidx[at:at + n] do x = k
	ti.n += n
	return n
}

// Removes bytes [a, b).
text_delete_range :: proc(ti: ^Text_Info, a, b: int) {
	if b <= a do return
	copy(ti.buf[a:], ti.buf[b:ti.n])
	copy(ti.cidx[a:], ti.cidx[b:ti.n])
	ti.n -= b - a
	if ti.npal > 0 do text_pal_compact(ti)
}

@(private = "file")
glyph_adv :: proc(face: ^Ufont, sc: f32, r, next: rune, track: f32) -> f32 {
	ad, lsb: i32
	stbtt.GetCodepointHMetrics(&face.info, r, &ad, &lsb)
	a := f32(ad) * sc + track
	if next != 0 {
		a += f32(stbtt.GetCodepointKernAdvance(&face.info, r, next)) * sc
	}
	return a
}

text_layout :: proc(ti: ^Text_Info) -> Text_Layout {
	L: Text_Layout
	L.lines = make([dynamic]Text_Line, context.temp_allocator)
	L.face = ufont_get(name_str(&ti.font))
	if L.face == nil do return L
	size := f32(max(ti.size, 1))
	L.sc = stbtt.ScaleForMappingEmToPixels(&L.face.info, size)
	a, d, g: i32
	stbtt.GetFontVMetrics(&L.face.info, &a, &d, &g)
	L.asc = f32(a) * L.sc
	L.lh = f32(a - d + g) * L.sc * f32(ti.line_pct) / 100
	track := size * f32(ti.track) / 100
	s := text_str(ti)
	start := 0
	for start <= len(s) {
		end := start
		for end < len(s) && s[end] != '\n' do end += 1
		rs := utf8.string_to_runes(s[start:end], context.temp_allocator)
		w: f32
		for r, i in rs {
			next: rune
			if i + 1 < len(rs) do next = rs[i + 1]
			w += glyph_adv(L.face, L.sc, r, next, track)
		}
		append(&L.lines, Text_Line{start, end, w})
		L.w = max(L.w, w)
		start = end + 1
	}
	return L
}

// X offset of a line inside the block, for the alignment.
text_line_x :: proc(ti: ^Text_Info, L: ^Text_Layout, w: f32) -> f32 {
	switch ti.align {
	case 1:
		return (L.w - w) / 2
	case 2:
		return L.w - w
	}
	return 0
}

// Canvas position of the caret at byte index `idx`, and the height of its line.
text_caret_xy :: proc(ti: ^Text_Info, idx: int) -> (x, y, h: f32) {
	L := text_layout(ti)
	if L.face == nil do return ti.x, ti.y, f32(ti.size)
	size := f32(max(ti.size, 1))
	track := size * f32(ti.track) / 100
	s := text_str(ti)
	for ln, li in L.lines {
		if idx >= ln.a && idx <= ln.b {
			px := text_line_x(ti, &L, ln.w)
			all := utf8.string_to_runes(s[ln.a:ln.b], context.temp_allocator)
			upto := utf8.rune_count_in_string(s[ln.a:idx])
			for i in 0 ..< min(upto, len(all)) {
				next: rune
				if i + 1 < len(all) do next = all[i + 1]
				px += glyph_adv(L.face, L.sc, all[i], next, track)
			}
			return ti.x + px, ti.y + f32(li) * L.lh, L.lh
		}
	}
	return ti.x, ti.y, L.lh
}

// Byte index nearest to a canvas point.
text_hit_index :: proc(ti: ^Text_Info, p: Vec2) -> int {
	L := text_layout(ti)
	if L.face == nil || len(L.lines) == 0 do return ti.n
	li := clamp(int(math.floor((p.y - ti.y) / max(L.lh, 1))), 0, len(L.lines) - 1)
	ln := L.lines[li]
	size := f32(max(ti.size, 1))
	track := size * f32(ti.track) / 100
	s := text_str(ti)
	px := ti.x + text_line_x(ti, &L, ln.w)
	all := utf8.string_to_runes(s[ln.a:ln.b], context.temp_allocator)
	bytei := ln.a
	for r, i in all {
		next: rune
		if i + 1 < len(all) do next = all[i + 1]
		adv := glyph_adv(L.face, L.sc, r, next, track)
		if p.x < px + adv / 2 do return bytei
		px += adv
		bytei += utf8.rune_size(r)
	}
	return ln.b
}

// Box a text block occupies on the canvas (with a little padding).
text_bounds :: proc(ti: ^Text_Info) -> Box {
	L := text_layout(ti)
	if L.face == nil do return Box{int(ti.x), int(ti.y), int(ti.x) + 1, int(ti.y) + 1}
	h := L.lh * f32(len(L.lines))
	return Box{int(math.floor(ti.x)) - 2, int(math.floor(ti.y)) - 2, int(math.ceil(ti.x + L.w)) + 3, int(math.ceil(ti.y + h)) + 3}
}

// The text's glyph outlines as a vector shape, laid out exactly as text_draw places them;
// consecutive characters of one colour share a path item. nil when there is nothing to draw.
text_to_shape :: proc(ti: ^Text_Info) -> ^Shape {
	if ti.n == 0 do return nil
	L := text_layout(ti)
	if L.face == nil do return nil
	cmds := make([dynamic]Path_Cmd)
	items := make([dynamic]Path_Item)
	size := f32(max(ti.size, 1))
	track := size * f32(ti.track) / 100
	s := text_str(ti)
	for ln, li in L.lines {
		rs := utf8.string_to_runes(s[ln.a:ln.b], context.temp_allocator)
		pen := ti.x + text_line_x(ti, &L, ln.w)
		base := math.round(ti.y + f32(li) * L.lh + L.asc)
		bi := ln.a
		for r, i in rs {
			next: rune
			if i + 1 < len(rs) do next = rs[i + 1]
			col := text_char_color(ti, bi)
			bi += utf8.rune_size(r)
			verts: [^]stbtt.vertex
			nv := int(stbtt.GetCodepointShape(&L.face.info, r, &verts))
			if nv > 0 {
				if len(items) == 0 || items[len(items) - 1].color != col {
					append(&items, Path_Item{col, len(cmds), len(cmds)})
				}
				pt :: proc(pen, base, sc: f32, x, y: stbtt.vertex_type) -> Vec2 {
					return Vec2{pen + f32(x) * sc, base - f32(y) * sc}
				}
				for v in verts[:nv] {
					c := Path_Cmd{p = pt(pen, base, L.sc, v.x, v.y)}
					switch v.type {
					case u8(stbtt.vmove.vmove):
						c.kind = .Move
					case u8(stbtt.vmove.vline):
						c.kind = .Line
					case u8(stbtt.vmove.vcurve):
						c.kind = .Quad
						c.c1 = pt(pen, base, L.sc, v.cx, v.cy)
					case u8(stbtt.vmove.vcubic):
						c.kind = .Cubic
						c.c1 = pt(pen, base, L.sc, v.cx, v.cy)
						c.c2 = pt(pen, base, L.sc, v.cx1, v.cy1)
					case:
						continue
					}
					append(&cmds, c)
				}
				items[len(items) - 1].b = len(cmds)
				stbtt.FreeShape(&L.face.info, verts)
			}
			pen += glyph_adv(L.face, L.sc, r, next, track)
		}
	}
	if len(cmds) == 0 {
		delete(cmds)
		delete(items)
		return nil
	}
	return shape_new(cmds[:], items[:])
}

// Rasterises the text into the layer, replacing its pixels.
text_render_layer :: proc(d: ^Doc, li: int) {
	l := &d.layers[li]
	ti := &l.text
	old := ti.bx
	tiles_destroy(&l.pix)
	l.pix = tiles_make(d.w, d.h)
	nb := Box{}
	if ti.n > 0 {
		L := text_layout(ti)
		if L.face != nil {
			nb = text_draw(d, l, &L)
		}
	}
	ti.bx = nb
	doc_touch(d, box_union(old, nb))
}

@(private = "file")
text_draw :: proc(d: ^Doc, l: ^Layer, L: ^Text_Layout) -> Box {
	ti := &l.text
	bb := box_clip(text_bounds(ti), d.w, d.h)
	if box_empty(bb) do return {}
	bw, bh := bb.x1 - bb.x0, bb.y1 - bb.y0
	cov := make([]f32, bw * bh, context.temp_allocator)
	// with character colours, premultiplied colour is accumulated alongside the coverage
	multi := ti.npal > 0
	acc: [][3]f32
	if multi do acc = make([][3]f32, bw * bh, context.temp_allocator)
	size := f32(max(ti.size, 1))
	track := size * f32(ti.track) / 100
	s := text_str(ti)
	for ln, li in L.lines {
		rs := utf8.string_to_runes(s[ln.a:ln.b], context.temp_allocator)
		pen := ti.x + text_line_x(ti, L, ln.w)
		base := ti.y + f32(li) * L.lh + L.asc
		bi := ln.a
		for r, i in rs {
			next: rune
			if i + 1 < len(rs) do next = rs[i + 1]
			gc := text_char_color(ti, bi)
			gcol := [3]f32{f32(gc.r), f32(gc.g), f32(gc.b)}
			bi += utf8.rune_size(r)
			if r != ' ' && r != '\t' {
				fx := pen - math.floor(pen)
				x0, y0, x1, y1: i32
				stbtt.GetCodepointBitmapBoxSubpixel(&L.face.info, r, L.sc, L.sc, fx, 0, &x0, &y0, &x1, &y1)
				gw, gh := int(x1 - x0), int(y1 - y0)
				if gw > 0 && gh > 0 {
					bm := make([]u8, gw * gh, context.temp_allocator)
					stbtt.MakeCodepointBitmapSubpixel(&L.face.info, raw_data(bm), x1 - x0, y1 - y0, x1 - x0, L.sc, L.sc, fx, 0, r)
					gx := int(math.floor(pen)) + int(x0) - bb.x0
					gy := int(math.round(base)) + int(y0) - bb.y0
					for yy in 0 ..< gh {
						py := gy + yy
						if py < 0 || py >= bh do continue
						for xx in 0 ..< gw {
							px := gx + xx
							if px < 0 || px >= bw do continue
							c := f32(bm[yy * gw + xx]) / 255
							if c <= 0 do continue
							k := &cov[py * bw + px]
							k^ = k^ + c * (1 - k^)
							if multi {
								o := &acc[py * bw + px]
								o^ = gcol * c + o^ * (1 - c)
							}
						}
					}
				}
			}
			pen += glyph_adv(L.face, L.sc, r, next, track)
		}
	}
	col := ti.color
	for y in 0 ..< bh {
		for x in 0 ..< bw {
			c := cov[y * bw + x]
			if c <= 0 do continue
			a := u8(clamp(c * f32(col.a) + 0.5, 0, 255))
			if a == 0 do continue
			pc := col
			if multi {
				v := acc[y * bw + x] / c
				pc = Color{u8(clamp(v.r + 0.5, 0, 255)), u8(clamp(v.g + 0.5, 0, 255)), u8(clamp(v.b + 0.5, 0, 255)), 255}
			}
			tiles_set(&l.pix, bb.x0 + x, bb.y0 + y, Color{pc.r, pc.g, pc.b, a}, {})
		}
	}
	return bb
}
