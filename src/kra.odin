package pangolin

import "core:encoding/xml"
import "core:fmt"
import "core:strconv"
import "core:strings"

// ---------------------------------------------------------------------------
// Krita documents (.kra): a zip holding maindoc.xml (the layer tree) and one tiled pixel file per
// layer. Paint layers (8 or 16-bit integer RGBA / grey) come in with name, position, opacity,
// blend mode and visibility, transparency masks become layer masks, and groups are flattened
// (a hidden group hides its layers, group opacity carries over). Layers without pixel data in the
// file (vector, file, fill, filter layers) are left out; when nothing can be read, Krita's merged
// image is opened instead.
// ---------------------------------------------------------------------------

// Zip archive ---------------------------------------------------------------------

@(private = "file")
Zip_Entry :: struct {
	name:         string,
	method:       int,
	csize, usize: int,
	offset:       int, // local header
}

@(private = "file")
le16 :: proc(b: []u8, i: int) -> int {
	return int(b[i]) | int(b[i + 1]) << 8
}

@(private = "file")
le32 :: proc(b: []u8, i: int) -> int {
	return le16(b, i) | le16(b, i + 2) << 16
}

@(private = "file")
zip_entries :: proc(data: []u8) -> (out: [dynamic]Zip_Entry, ok: bool) {
	out = make([dynamic]Zip_Entry, context.temp_allocator)
	// the end-of-central-directory record is in the last 64 KB
	eocd := -1
	for i := len(data) - 22; i >= max(0, len(data) - 22 - 65535); i -= 1 {
		if le32(data, i) == 0x06054b50 {
			eocd = i
			break
		}
	}
	if eocd < 0 do return
	n := le16(data, eocd + 10)
	p := le32(data, eocd + 16)
	for _ in 0 ..< n {
		if p + 46 > len(data) || le32(data, p) != 0x02014b50 do return
		nl, xl, cl := le16(data, p + 28), le16(data, p + 30), le16(data, p + 32)
		if p + 46 + nl > len(data) do return
		append(&out, Zip_Entry{
			name   = string(data[p + 46:][:nl]),
			method = le16(data, p + 10),
			csize  = le32(data, p + 20),
			usize  = le32(data, p + 24),
			offset = le32(data, p + 42),
		})
		p += 46 + nl + xl + cl
	}
	return out, true
}

@(private = "file")
zip_read :: proc(data: []u8, entries: []Zip_Entry, name: string) -> ([]u8, bool) {
	for e in entries {
		if e.name != name do continue
		p := e.offset
		if p + 30 > len(data) || le32(data, p) != 0x04034b50 do return nil, false
		start := p + 30 + le16(data, p + 26) + le16(data, p + 28)
		if e.csize < 0 || start + e.csize > len(data) || e.usize < 0 || e.usize > 1 << 30 do return nil, false
		src := data[start:][:e.csize]
		switch e.method {
		case 0:
			return src, true
		case 8:
			out := make([]u8, e.usize, context.temp_allocator)
			if e.usize > 0 && !inflate_raw(src, out) do return nil, false
			return out, true
		}
		return nil, false
	}
	return nil, false
}

// LZF (liblzf), as used for Krita's tiles.
@(private = "file")
lzf_decompress :: proc(src, out: []u8) -> bool {
	i, o := 0, 0
	for i < len(src) {
		ctrl := int(src[i])
		i += 1
		if ctrl < 32 {
			n := ctrl + 1
			if i + n > len(src) || o + n > len(out) do return false
			copy(out[o:], src[i:i + n])
			i += n
			o += n
		} else {
			n := ctrl >> 5
			if n == 7 {
				if i >= len(src) do return false
				n += int(src[i])
				i += 1
			}
			if i >= len(src) do return false
			ref := o - ((ctrl & 0x1f) << 8) - int(src[i]) - 1
			i += 1
			n += 2
			if ref < 0 || o + n > len(out) do return false
			for k in 0 ..< n do out[o + k] = out[ref + k] // may overlap
			o += n
		}
	}
	return o == len(out)
}

// Layer pixel files ------------------------------------------------------------------

// Pixel layout of a Krita colour space: bytes per pixel and where each channel's high byte is.
@(private = "file")
Kra_Format :: struct {
	size:       int,
	r, g, b, a: int, // byte offsets (grey: r == g == b)
}

@(private = "file")
kra_format :: proc(cs: string) -> (f: Kra_Format, ok: bool) {
	switch cs {
	case "RGBA":
		// BGRA in memory
		return {4, 2, 1, 0, 3}, true
	case "RGBA16":
		// little-endian 16-bit BGRA: high bytes at the odd offsets
		return {8, 5, 3, 1, 7}, true
	case "GRAYA":
		return {2, 0, 0, 0, 1}, true
	case "GRAYAU16", "GRAYA16":
		return {4, 1, 1, 1, 3}, true
	}
	return
}

// Decodes a tiled pixel file into a w*h buffer, offset by (ox, oy). Mask files (one byte per
// pixel) fill only `grey`.
@(private = "file")
kra_tiles :: proc(data: []u8, f: Kra_Format, w, h, ox, oy: int, out: []Color, grey: []u8) -> bool {
	pos := 0
	line :: proc(data: []u8, pos: ^int) -> string {
		s := pos^
		for pos^ < len(data) && data[pos^] != '\n' do pos^ += 1
		l := string(data[s:pos^])
		if pos^ < len(data) do pos^ += 1
		return l
	}
	tw, th, psize, ntiles := 64, 64, f.size, 0
	for _ in 0 ..< 8 {
		save := pos
		l := line(data, &pos)
		parts := strings.fields(l, context.temp_allocator)
		if len(parts) != 2 {
			pos = save
			break
		}
		v, _ := strconv.parse_int(parts[1])
		switch parts[0] {
		case "TILEWIDTH":
			tw = v
		case "TILEHEIGHT":
			th = v
		case "PIXELSIZE":
			psize = v
		case "DATA":
			ntiles = v
		}
		if parts[0] == "DATA" do break
	}
	if tw <= 0 || th <= 0 || tw > 1024 || th > 1024 || psize != f.size do return false
	tile := make([]u8, tw * th * psize, context.temp_allocator)
	planar := make([]u8, len(tile), context.temp_allocator)
	for _ in 0 ..< ntiles {
		parts := strings.split(line(data, &pos), ",", context.temp_allocator)
		if len(parts) != 4 do return false
		tx, _ := strconv.parse_int(parts[0])
		ty, _ := strconv.parse_int(parts[1])
		size, _ := strconv.parse_int(parts[3])
		if size < 1 || pos + size > len(data) do return false
		blob := data[pos:pos + size]
		pos += size
		// first byte: 1 = LZF compressed, 0 = stored
		if blob[0] == 1 {
			if !lzf_decompress(blob[1:], planar) do return false
		} else {
			if len(blob) - 1 < len(planar) do return false
			copy(planar, blob[1:])
		}
		// tiles are stored planar, one plane per byte of the pixel
		n := tw * th
		for p in 0 ..< n {
			for b in 0 ..< psize do tile[p * psize + b] = planar[b * n + p]
		}
		for y in 0 ..< th {
			py := ty + oy + y
			if py < 0 || py >= h do continue
			for x in 0 ..< tw {
				px := tx + ox + x
				if px < 0 || px >= w do continue
				s := tile[(y * tw + x) * psize:]
				if grey != nil {
					grey[py * w + px] = s[0]
				} else {
					out[py * w + px] = Color{s[f.r], s[f.g], s[f.b], s[f.a]}
				}
			}
		}
	}
	return true
}

// Document ---------------------------------------------------------------------------

KRA_BLENDS := [?]struct {
	op:    string,
	blend: Blend,
}{
	{"normal", .Normal}, {"multiply", .Multiply}, {"screen", .Screen}, {"overlay", .Overlay},
	{"soft_light", .Soft_Light}, {"soft_light_svg", .Soft_Light}, {"hard_light", .Hard_Light},
	{"darken", .Darken}, {"lighten", .Lighten}, {"dodge", .Color_Dodge}, {"burn", .Color_Burn},
	{"add", .Add}, {"linear_dodge", .Add}, {"subtract", .Subtract}, {"diff", .Difference},
	{"hue", .Hue}, {"saturation", .Saturation}, {"color", .Color}, {"luminize", .Luminosity},
	{"erase", .Erase},
}

@(private = "file")
Kra_Ctx :: struct {
	zdata:   []u8,
	entries: []Zip_Entry,
	xdoc:    ^xml.Document,
	dir:     string, // "<image name>/layers/"
	d:       ^Doc,
	skipped: int,
	active:  int,
}

@(private = "file")
attr :: proc(x: ^xml.Document, id: xml.Element_ID, key: string) -> string {
	for a in x.elements[id].attribs {
		if a.key == key do return a.val
	}
	return ""
}

@(private = "file")
attr_int :: proc(x: ^xml.Document, id: xml.Element_ID, key: string, def: int) -> int {
	v, ok := strconv.parse_int(attr(x, id, key))
	return ok ? v : def
}

// Child elements named `ident`.
@(private = "file")
children :: proc(x: ^xml.Document, id: xml.Element_ID, ident: string) -> [dynamic]xml.Element_ID {
	out := make([dynamic]xml.Element_ID, context.temp_allocator)
	for v in x.elements[id].value {
		if c, ok := v.(xml.Element_ID); ok && x.elements[c].ident == ident do append(&out, c)
	}
	return out
}

// Krita lists layers top first; the document wants them bottom first, so walk in reverse.
@(private = "file")
kra_layers :: proc(k: ^Kra_Ctx, layers: xml.Element_ID, hidden: bool, opacity: int) {
	x := k.xdoc
	list := children(x, layers, "layer")
	w, h := k.d.w, k.d.h
	for i := len(list) - 1; i >= 0; i -= 1 {
		id := list[i]
		vis := attr_int(x, id, "visible", 1) != 0 && !hidden
		op := attr_int(x, id, "opacity", 255) * opacity / 255
		switch attr(x, id, "nodetype") {
		case "grouplayer":
			for sub in children(x, id, "layers") do kra_layers(k, sub, !vis, op)
			continue
		case "paintlayer":
		case:
			k.skipped += 1
			continue
		}
		f, fok := kra_format(attr(x, id, "colorspacename"))
		data, dok := zip_read(k.zdata, k.entries, strings.concatenate({k.dir, attr(x, id, "filename")}, context.temp_allocator))
		if !fok || !dok {
			k.skipped += 1
			continue
		}
		pix := make([]Color, w * h, context.temp_allocator)
		ox, oy := attr_int(x, id, "x", 0), attr_int(x, id, "y", 0)
		if !kra_tiles(data, f, w, h, ox, oy, pix, nil) {
			k.skipped += 1
			continue
		}
		l := layer_make(attr(x, id, "name"), w, h)
		tiles_from_buf(&l.pix, w, h, pix, {})
		l.visible = vis
		l.opacity = u8(clamp(op, 0, 255))
		l.locked = attr_int(x, id, "locked", 0) != 0
		cop := attr(x, id, "compositeop")
		for b in KRA_BLENDS do if b.op == cop do l.blend = b.blend
		// the first transparency mask becomes the layer mask
		for ms in children(x, id, "masks") {
			for m in children(x, ms, "mask") {
				if attr(x, m, "nodetype") != "transparencymask" || l.has_mask do continue
				md, mok := zip_read(k.zdata, k.entries, strings.concatenate({k.dir, attr(x, m, "filename")}, context.temp_allocator))
				if !mok do continue
				grey := make([]u8, w * h, context.temp_allocator)
				for &g in grey do g = 255
				mx, my := attr_int(x, m, "x", 0), attr_int(x, m, "y", 0)
				if !kra_tiles(md, Kra_Format{1, 0, 0, 0, 0}, w, h, mx, my, nil, grey) do continue
				mp := make([]Color, w * h, context.temp_allocator)
				for g, j in grey do mp[j] = Color{g, g, g, 255}
				l.has_mask = true
				l.mask_on = attr_int(x, m, "visible", 1) != 0
				l.mask = tiles_make(w, h)
				tiles_from_buf(&l.mask, w, h, mp, MASK_EMPTY)
			}
		}
		if attr(x, id, "selected") == "true" do k.active = len(k.d.layers)
		append(&k.d.layers, l)
	}
}

// Reads a .kra file into a new document; `msg` explains a failure or notes skipped layers.
kra_load :: proc(data: []u8, title: string) -> (d: ^Doc, msg: string) {
	entries, ok := zip_entries(data)
	if !ok do return nil, "This is not a Krita document."
	maindoc, mok := zip_read(data, entries[:], "maindoc.xml")
	if !mok do return nil, "This is not a Krita document."
	x, err := xml.parse_bytes(maindoc, allocator = context.temp_allocator)
	if err != nil do return nil, "The Krita document's layer list could not be read."
	img: xml.Element_ID = 0
	found := false
	for e, i in x.elements {
		if e.ident == "IMAGE" {
			img = xml.Element_ID(i)
			found = true
			break
		}
	}
	if !found do return nil, "The Krita document has no image."
	w, h := attr_int(x, img, "width", 0), attr_int(x, img, "height", 0)
	if w < 1 || h < 1 || w > 16384 || h > 16384 {
		return nil, "The image is too large (16384 x 16384 at most)."
	}
	nd := doc_new(w, h, title)
	for &l in nd.layers do layer_destroy(&l)
	clear(&nd.layers)
	k := Kra_Ctx {
		zdata   = data,
		entries = entries[:],
		xdoc    = x,
		dir     = fmt.tprintf("%s/layers/", attr(x, img, "name")),
		d       = nd,
		active  = -1,
	}
	for ls in children(x, img, "layers") do kra_layers(&k, ls, false, 255)
	if len(nd.layers) == 0 {
		// nothing readable: Krita's flattened copy
		if png, pok := zip_read(data, entries[:], "mergedimage.png"); pok {
			if pix, pw, ph, iok := decode_image(png, ".png"); iok {
				defer delete(pix)
				if pw == w && ph == h {
					l := layer_make("Background", w, h)
					tiles_from_buf(&l.pix, w, h, pix, {})
					append(&nd.layers, l)
					k.skipped = 0
					msg = "Opened Krita's flattened image (its layers could not be read)"
				}
			}
		}
	}
	if len(nd.layers) == 0 {
		doc_destroy(nd)
		return nil, "None of the layers could be read."
	}
	if k.skipped > 0 {
		msg = fmt.tprintf("%d layer(s) left out: only paint layers and transparency masks are imported", k.skipped)
	}
	nd.active_layer = k.active >= 0 ? k.active : len(nd.layers) - 1
	doc_clamp(nd)
	nd.modified = false
	return nd, msg
}
