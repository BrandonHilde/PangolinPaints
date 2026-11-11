package pangolin

import "base:runtime"
import "core:fmt"
import "core:os"
import "core:strings"

// ---------------------------------------------------------------------------
// Project format (.ppnt)
//
//   "PPNT" u8 version  u32 w  u32 h  u32 active_layer  u32 layer_count
//   per layer: str name  u8 flags  u8 opacity  u8 blend  tiles  [tiles of the mask]
//   tiles: u32 count, then per stored tile: u32 index  u8 method  u32 size  bytes
//          method 0 = raw RGBA, 1 = deflate. Missing tiles are empty.
// Version 5 adds, after layer_count:
//   u32 frame_count  u32 active_frame  per frame: u32 duration  u32 flat
//   u32 tag_count  per tag: str name  u32 from  u32 to  u8 dir  color
// Version 6 adds layer groups: after a layer's span_id, u32 uid  u32 parent uid  u8 group flags (1 group, 2 pass
// through, 4 closed in the list). Older files load with every layer at the top level.
// Version 7 adds live layer effects after the group flags: u8 count, per effect: str macro name  u8 on  str the macro
// (its .pmacro text, so the painting opens elsewhere: a macro the library lacks is added to it).
// Version 8 writes that macro text as u32 length + bytes: as a str it was cut off at 255 bytes.
// a u32 span_id after a layer's blend mode, and a layer's tiles [and mask] are written once per frame, or once for a text or vector layer, which spans
// them all. Method 2 is a tile written before (u32 size = its number, counting in file order), so tiles
// that frames share stay shared, on disk and after loading.
// ---------------------------------------------------------------------------

PPNT_MAGIC :: "PPNT"
PPNT_VERSION :: 8 // 2: text layers, 3: text character colours, 4: vector layers, 5: frames, 6: layer groups, 7: layer effects, 8: whole macro text

GF_GROUP :: 1
GF_PASS_THROUGH :: 2
GF_COLLAPSED :: 4

LF_VISIBLE :: 1
LF_LOCKED :: 2
LF_LOCK_ALPHA :: 4
LF_HAS_MASK :: 8
LF_MASK_ON :: 16
LF_TEXT :: 32
LF_SHAPE :: 64

@(private = "file")
write_tiles :: proc(w: ^Writer, g: ^Tiles, seen: ^map[^Tile]u32) {
	if g == nil {
		w32(w, 0)
		return
	}
	w32(w, u32(tiles_count(g)))
	for t, i in g.t {
		if t == nil do continue
		w32(w, u32(i))
		if id, have := seen[t]; have {
			w8(w, 2)
			w32(w, id)
			continue
		}
		seen[t] = u32(len(seen))
		raw := ([^]u8)(&t.pix[0])[:size_of(t.pix)]
		comp, cok := deflate_raw(raw)
		if cok && len(comp) > 0 && len(comp) < len(raw) {
			w8(w, 1)
			w32(w, u32(len(comp)))
			append(&w.b, ..comp)
		} else {
			w8(w, 0)
			w32(w, u32(len(raw)))
			append(&w.b, ..raw)
		}
	}
}

@(private = "file")
read_tiles :: proc(r: ^Reader, g: ^Tiles, seen: ^[dynamic]^Tile, w, h: int) {
	n := int(r32(r))
	if n > 0 && len(g.t) == 0 do g^ = tiles_make(w, h) // an empty cel stays without tiles
	for _ in 0 ..< n {
		if r.bad do return
		idx := int(r32(r))
		method := r8(r)
		size := int(r32(r))
		if method == 2 {
			if size < 0 || size >= len(seen) || idx < 0 || idx >= len(g.t) {
				r.bad = true
				return
			}
			t := seen[size]
			t.refs += 1
			tile_release(g.t[idx])
			g.t[idx] = t
			continue
		}
		if r.pos + size > len(r.d) || idx < 0 || idx >= len(g.t) {
			r.bad = true
			return
		}
		data := r.d[r.pos:r.pos + size]
		r.pos += size
		t := tile_new({})
		dst := ([^]u8)(&t.pix[0])[:size_of(t.pix)]
		if method == 0 {
			if size != len(dst) {
				r.bad = true
				free(t)
				return
			}
			copy(dst, data)
		} else {
			if !inflate_raw(data, dst) {
				r.bad = true
				free(t)
				return
			}
		}
		tile_release(g.t[idx])
		g.t[idx] = t
		append(seen, t) // the grids that hold it keep it alive for as long as this list is used
	}
}

project_encode :: proc(d: ^Doc) -> []u8 {
	w := Writer{}
	w.b = make([dynamic]u8, context.temp_allocator)
	append(&w.b, ..transmute([]u8)string(PPNT_MAGIC))
	w8(&w, PPNT_VERSION)
	w32(&w, u32(d.w))
	w32(&w, u32(d.h))
	w32(&w, u32(d.active_layer))
	w32(&w, u32(len(d.layers)))
	w32(&w, u32(len(d.frames)))
	w32(&w, u32(d.active_frame))
	for fr in d.frames {
		w32(&w, u32(fr.duration))
		w32(&w, u32(fr.flat))
	}
	w32(&w, u32(len(d.tags)))
	for &t in d.tags {
		wstr(&w, name_str(&t.name))
		w32(&w, u32(t.from))
		w32(&w, u32(t.to))
		w8(&w, u8(t.dir))
		wcol(&w, t.color)
	}
	seen := make(map[^Tile]u32, 1024, context.temp_allocator)
	for &l in d.layers {
		wstr(&w, name_str(&l.name))
		flags: u8
		if l.visible do flags |= LF_VISIBLE
		if l.locked do flags |= LF_LOCKED
		if l.lock_alpha do flags |= LF_LOCK_ALPHA
		if l.has_mask do flags |= LF_HAS_MASK
		if l.mask_on do flags |= LF_MASK_ON
		if l.text.on do flags |= LF_TEXT
		if l.shape != nil do flags |= LF_SHAPE
		w8(&w, flags)
		w8(&w, l.opacity)
		w8(&w, u8(l.blend))
		w32(&w, u32(l.span_id))
		w32(&w, u32(l.uid))
		w32(&w, u32(l.parent))
		gf: u8
		if l.is_group do gf |= GF_GROUP
		if l.pass_through do gf |= GF_PASS_THROUGH
		if l.collapsed do gf |= GF_COLLAPSED
		w8(&w, gf)
		w8(&w, u8(l.fx_n))
		for &f in l.fx[:l.fx_n] {
			wstr(&w, name_str(&f.name))
			w8(&w, f.on ? 1 : 0)
			m := macro_find(name_str(&f.name))
			// a macro's text can be any length (a name is at most 255 bytes, so wstr is enough for those)
			text := m != nil ? macro_to_text(m) : ""
			w32(&w, u32(len(text)))
			append(&w.b, ..transmute([]u8)text)
		}
		for f in 0 ..< (layer_spans(&l) ? 1 : len(d.frames)) {
			pix, mask := &l.pix, &l.mask
			if !layer_spans(&l) do pix, mask = frame_tiles(d, &l, f)
			write_tiles(&w, pix, &seen)
			if l.has_mask {
				write_tiles(&w, mask, &seen)
			}
		}
		if l.text.on {
			write_text(&w, &l.text)
		}
		if l.shape != nil {
			write_shape(&w, l.shape)
		}
	}
	return w.b[:]
}

project_decode :: proc(data: []u8) -> (d: ^Doc, ok: bool) {
	if len(data) < 5 || string(data[:4]) != PPNT_MAGIC {
		return nil, false
	}
	r := Reader{d = data, pos = 4}
	ver := r8(&r)
	if ver < 1 || ver > PPNT_VERSION {
		return nil, false
	}
	w := int(r32(&r))
	h := int(r32(&r))
	if w < 1 || h < 1 || w > 16384 || h > 16384 {
		return nil, false
	}
	active := int(r32(&r))
	nl := int(r32(&r))
	if nl < 1 || nl > 4096 {
		return nil, false
	}
	nd := doc_new(w, h)
	for &l in nd.layers {
		layer_destroy(&l)
	}
	clear(&nd.layers)
	if ver >= 5 {
		nf := int(r32(&r))
		cur := int(r32(&r))
		if r.bad || nf < 1 || nf > 65536 || cur < 0 || cur >= nf {
			doc_destroy(nd)
			return nil, false
		}
		clear(&nd.frames)
		for _ in 0 ..< nf {
			dur := int(r32(&r))
			append(&nd.frames, Frame{duration = clamp(dur, 10, 600000), flat = int(r32(&r))})
		}
		nd.active_frame = cur
		nt := int(r32(&r))
		if r.bad || nt < 0 || nt > 65536 {
			doc_destroy(nd)
			return nil, false
		}
		for _ in 0 ..< nt {
			t: Tag
			name_set(&t.name, rstr(&r))
			t.from = clamp(int(r32(&r)), 0, nf - 1)
			t.to = clamp(int(r32(&r)), t.from, nf - 1)
			t.dir = Tag_Dir(min(r8(&r), u8(len(Tag_Dir) - 1)))
			t.color = rcol(&r)
			append(&nd.tags, t)
		}
	}
	seen := make([dynamic]^Tile, context.temp_allocator)
	for _ in 0 ..< nl {
		l := layer_make(rstr(&r), w, h)
		flags := r8(&r)
		l.visible = flags & LF_VISIBLE != 0
		l.locked = flags & LF_LOCKED != 0
		l.lock_alpha = flags & LF_LOCK_ALPHA != 0
		l.opacity = r8(&r)
		l.blend = Blend(min(r8(&r), u8(len(Blend) - 1)))
		if ver >= 5 do l.span_id = int(r32(&r))
		if ver >= 6 {
			l.uid = int(r32(&r))
			l.parent = int(r32(&r))
			gf := r8(&r)
			l.is_group, l.pass_through, l.collapsed = gf & GF_GROUP != 0, gf & GF_PASS_THROUGH != 0, gf & GF_COLLAPSED != 0
		}
		if ver >= 7 {
			n := int(r8(&r))
			for k in 0 ..< n {
				name := rstr(&r)
				on := r8(&r) != 0
				text: string
				if ver >= 8 {
					n := int(r32(&r))
					if n < 0 || r.pos + n > len(r.d) {
						r.bad = true
					} else {
						text = string(r.d[r.pos:r.pos + n])
						r.pos += n
					}
				} else {
					text = rstr(&r) // up to version 7 the text was cut off at 255 bytes
				}
				if k >= MAX_LAYER_FX || r.bad do continue
				name_set(&l.fx[l.fx_n].name, name)
				l.fx[l.fx_n].on = on
				l.fx_n += 1
				fx_macro_arrived(name, text)
			}
		}
		if flags & LF_HAS_MASK != 0 {
			l.has_mask = true
			l.mask_on = flags & LF_MASK_ON != 0
			l.mask = tiles_make(w, h)
		}
		// (these flags only exist in the versions that also read the layer's text or outlines)
		per_frame := ver >= 5 && flags & (LF_TEXT | LF_SHAPE) == 0
		for f in 0 ..< (per_frame ? len(nd.frames) : 1) {
			if r.bad do break
			if !per_frame || f == nd.active_frame {
				read_tiles(&r, &l.pix, &seen, w, h)
				if l.has_mask do read_tiles(&r, &l.mask, &seen, w, h)
				continue
			}
			c := new(Cel)
			c.refs = 1
			read_tiles(&r, &c.pix, &seen, w, h)
			if l.has_mask do read_tiles(&r, &c.mask, &seen, w, h)
			if len(c.pix.t) == 0 && len(c.mask.t) == 0 {
				free(c)
				continue
			}
			layer_cels_fit(&l, len(nd.frames))
			l.cels[f] = c
		}
		if flags & LF_TEXT != 0 && ver >= 2 {
			read_text(&r, &l.text, int(ver))
		}
		if flags & LF_SHAPE != 0 && ver >= 4 {
			l.shape = read_shape(&r)
		}
		append(&nd.layers, l)
		if r.bad do break
	}
	if r.bad {
		doc_destroy(nd)
		return nil, false
	}
	nd.active_layer = clamp(active, 0, len(nd.layers) - 1)
	doc_layers_normalize(nd) // uids for layers from older files, and a sound tree
	doc_clamp(nd)
	nd.modified = false
	return nd, true
}

// ---------------------------------------------------------------------------
// Images
// ---------------------------------------------------------------------------

load_image_pixels :: proc(path: string) -> (pix: []Color, w, h: int, ok: bool) {
	// core:os handles UTF-8 paths on every platform
	data, err := os.read_entire_file_from_path(path, context.allocator)
	if err != nil {
		return
	}
	defer delete(data)
	return decode_image(data, lower_ext(path))
}

// Decodes image file bytes, picked by content rather than file extension: our own TIFF, PSD and KRA readers,
// then the formats all the Pangolin tools read (PNG, JPG, WebP, BMP, TGA, GIF, QOI).
decode_image :: proc(data: []u8, ext: string) -> (pix: []Color, w, h: int, ok: bool) {
	if len(data) >= 4 && ((data[0] == 'I' && data[1] == 'I' && data[2] == 42 && data[3] == 0) || (data[0] == 'M' && data[1] == 'M' && data[2] == 0 && data[3] == 42)) {
		return tiff_decode(data)
	}
	// layered documents, flattened (placing one as a layer)
	is_psd := len(data) >= 4 && string(data[:4]) == "8BPS"
	if is_psd || ext == ".kra" {
		ld: ^Doc
		if is_psd {
			ld, _ = psd_load(data, "")
		} else {
			ld, _ = kra_load(data, "")
		}
		if ld == nil do return
		defer doc_destroy(ld)
		return doc_flat(ld), ld.w, ld.h, true
	}
	return decode_common_image(data)
}

doc_from_image :: proc(path: string) -> (d: ^Doc, ok: bool) {
	pix, w, h, lok := load_image_pixels(path)
	if !lok {
		return nil, false
	}
	defer delete(pix)
	if w > 16384 || h > 16384 {
		return nil, false
	}
	nd := doc_new(w, h, path_stem(path))
	tiles_from_buf(&nd.layers[0].pix, w, h, pix, {})
	nd.modified = false
	return nd, true
}

// ---------------------------------------------------------------------------
// High-level file commands
// ---------------------------------------------------------------------------

show_message :: proc(title, msg: string) {
	name_set(&dialog.msg_title, title)
	name_set(&dialog.msg_text, msg)
	dialog_open(.Message)
}

file_open_dialog :: proc() {
	p, ok := native_dialog(false, "Open", FILTERS_OPEN[:], "", "")
	if ok {
		open_path(p)
		delete(p)
	}
}

open_path :: proc(path: string) {
	for d, i in docs {
		if d.path == path {
			switch_doc(i)
			return
		}
	}
	if lower_ext(path) == ".gpl" {
		if swatches_load_gpl(path) {
			set_status("Swatches loaded")
		} else {
			show_message("Swatches", "Could not read the palette file.")
		}
		return
	}
	d, err := doc_load(path)
	if err != "" {
		show_message("Open", err)
		return
	}
	add_doc(d)
	recent_add(path)
	if lower_ext(path) == ".ppnt" {
		set_statusf("Opened %s", path_basename(path))
	} else {
		set_statusf("Opened %s (%dx%d)", path_basename(path), d.w, d.h)
	}
}

// Loads a project or image file as a new document; `err` explains a failure.
doc_load :: proc(path: string) -> (d: ^Doc, err: string) {
	switch lower_ext(path) {
	case ".psd", ".psb", ".kra":
		data, ok := read_file(path)
		if !ok {
			return nil, fmt.tprintf("Cannot read %s", path_basename(path))
		}
		defer delete(data)
		msg: string
		if lower_ext(path) == ".kra" {
			d, msg = kra_load(data, path_stem(path))
		} else {
			d, msg = psd_load(data, path_stem(path))
		}
		if d == nil {
			return nil, fmt.tprintf("Cannot open %s: %s", path_basename(path), msg)
		}
		if msg != "" do set_status(msg)
		return d, ""
	}
	if lower_ext(path) != ".ppnt" {
		ok: bool
		d, ok = doc_from_image(path)
		if !ok {
			return nil, fmt.tprintf("Cannot open %s", path_basename(path))
		}
		return d, ""
	}
	data, ok := read_file(path)
	if !ok {
		return nil, fmt.tprintf("Cannot read %s", path_basename(path))
	}
	defer delete(data)
	dok: bool
	d, dok = project_decode(data)
	if !dok {
		return nil, "This is not a valid Pangolin Paints project."
	}
	d.path = strings.clone(path)
	name_set(&d.title, path_stem(path))
	return d, ""
}

file_save :: proc(d: ^Doc, save_as: bool) -> bool {
	path := d.path
	if path == "" || save_as {
		initial := fmt.tprintf("%s.ppnt", name_str(&d.title))
		p, ok := native_dialog(true, "Save project", FILTERS_PROJ[:], "ppnt", initial)
		if !ok {
			return false
		}
		path = p
		if lower_ext(path) != ".ppnt" {
			path = fmt.tprintf("%s.ppnt", p)
		}
	}
	return file_save_to(d, path)
}

// Saves the painting to `path` without asking; from then on it is the painting's file.
file_save_to :: proc(d: ^Doc, path: string) -> bool {
	data := project_encode(d)
	if !write_file(path, data) {
		show_message("Save", fmt.tprintf("Could not write %s", path_basename(path)))
		return false
	}
	if path != d.path {
		if d.path != "" {
			delete(d.path)
		}
		d.path = strings.clone(path)
		name_set(&d.title, path_stem(path))
	}
	d.modified = false
	recent_add(path)
	set_statusf("Saved %s (%d KB)", path_basename(path), len(data) / 1024)
	return true
}

// Add an image as a new layer, centred and scaled down to fit if larger than the canvas.
file_place_dialog :: proc() {
	p, ok := native_dialog(false, "Import as layer", FILTERS_IMG[:], "", "")
	if !ok {
		return
	}
	defer delete(p)
	place_image(p)
}

place_image :: proc(path: string) {
	d := doc
	pix, w, h, ok := load_image_pixels(path)
	if !ok {
		show_message("Import", "Cannot read the image.")
		return
	}
	defer delete(pix)
	src, sw, sh := pix, w, h
	if w > d.w || h > d.h {
		k := min(f32(d.w) / f32(w), f32(d.h) / f32(h))
		sw, sh = max(int(f32(w) * k), 1), max(int(f32(h) * k), 1)
		src = make([]Color, sw * sh, context.temp_allocator)
		resample(pix, w, h, src, sw, sh, .Bicubic)
	}
	buf := make([]Color, d.w * d.h, context.temp_allocator)
	ox, oy := (d.w - sw) / 2, (d.h - sh) / 2
	for y in 0 ..< sh {
		for x in 0 ..< sw {
			buf[(oy + y) * d.w + ox + x] = src[y * sw + x]
		}
	}
	doc_add_layer_from(d, path_stem(path), buf)
	set_statusf("Imported %s", path_basename(path))
}

file_swatches_load :: proc() {
	p, ok := native_dialog(false, "Load swatches", FILTERS_GPL[:], "gpl", "")
	if ok {
		if swatches_load_gpl(p) {
			set_status("Swatches loaded")
		} else {
			show_message("Swatches", "Could not read the palette file.")
		}
		delete(p)
	}
}

file_swatches_save :: proc() {
	p, ok := native_dialog(true, "Save swatches", FILTERS_GPL[:], "gpl", "swatches.gpl")
	if ok {
		if swatches_save_gpl(p) {
			set_status("Swatches saved")
		} else {
			show_message("Swatches", "Could not write the palette file.")
		}
		delete(p)
	}
}

// ---------------------------------------------------------------------------
// Export
// ---------------------------------------------------------------------------

Export_Format :: enum {
	PNG,
	JPG,
	BMP,
	TGA,
	QOI,
	TIFF,
	// these two need more than one frame
	PNG_Sequence,
	GIF,
}

EXPORT_STILL_FORMATS :: 6 // how many formats save a single picture: those before PNG_Sequence

EXPORT_FORMAT_NAMES := [Export_Format]string {
	.PNG = "PNG (lossless, transparency)",
	.JPG = "JPEG (photos, small files)",
	.BMP = "BMP",
	.TGA = "TGA",
	.QOI = "QOI",
	.TIFF = "TIFF (lossless, transparency)",
	.PNG_Sequence = "PNG sequence (one file per frame)",
	.GIF = "Animated GIF",
}

EXPORT_EXT := [Export_Format]string {
	.PNG = "png",
	.JPG = "jpg",
	.BMP = "bmp",
	.TGA = "tga",
	.QOI = "qoi",
	.TIFF = "tif",
	.PNG_Sequence = "png",
	.GIF = "gif",
}

// Short names for macro files.
EXPORT_KEYS := [Export_Format]string {
	.PNG          = "png",
	.JPG          = "jpg",
	.BMP          = "bmp",
	.TGA          = "tga",
	.QOI          = "qoi",
	.TIFF         = "tiff",
	.PNG_Sequence = "png-sequence",
	.GIF          = "gif",
}

export_format: Export_Format
export_quality := 90

// Encode pixels in the given format. Returns nil on failure.
export_encode :: proc(pix: []Color, w, h: int, f: Export_Format, quality: int) -> []u8 {
	switch f {
	case .JPG:
		return jpeg_encode(pix, w, h, quality, Color{255, 255, 255, 255}, quality < 90, context.temp_allocator)
	case .BMP:
		return bmp_encode(pix, w, h)
	case .TGA:
		return tga_encode(pix, w, h)
	case .QOI:
		return qoi_encode(pix, w, h)
	case .TIFF:
		return tiff_encode(pix, w, h)
	case .PNG, .PNG_Sequence, .GIF:
	}
	return encode_png(pix, w, h)
}

// 32-bit BMP with an alpha channel (BITMAPV4 header so alpha survives).
bmp_encode :: proc(pix: []Color, w, h: int) -> []u8 {
	wr := Writer{}
	wr.b = make([dynamic]u8, 0, 122 + w * h * 4, context.temp_allocator)
	size := 122 + w * h * 4
	append(&wr.b, 'B', 'M')
	w32(&wr, u32(size))
	w32(&wr, 0)
	w32(&wr, 122)
	w32(&wr, 108) // BITMAPV4HEADER
	w32(&wr, u32(w))
	w32(&wr, u32(-i32(h))) // top-down
	w16(&wr, 1)
	w16(&wr, 32)
	w32(&wr, 3) // BI_BITFIELDS
	w32(&wr, u32(w * h * 4))
	w32(&wr, 2835)
	w32(&wr, 2835)
	w32(&wr, 0)
	w32(&wr, 0)
	w32(&wr, 0x00FF0000)
	w32(&wr, 0x0000FF00)
	w32(&wr, 0x000000FF)
	w32(&wr, 0xFF000000)
	w32(&wr, 0x73524742) // 'sRGB'
	for _ in 0 ..< 12 do w32(&wr, 0)
	for p in pix[:w * h] {
		append(&wr.b, p.b, p.g, p.r, p.a)
	}
	return wr.b[:]
}

// Uncompressed 32-bit TGA, top-left origin.
tga_encode :: proc(pix: []Color, w, h: int) -> []u8 {
	wr := Writer{}
	wr.b = make([dynamic]u8, 0, 18 + w * h * 4, context.temp_allocator)
	append(&wr.b, 0, 0, 2)
	for _ in 0 ..< 5 do w8(&wr, 0)
	w16(&wr, 0)
	w16(&wr, 0)
	w16(&wr, u16(w))
	w16(&wr, u16(h))
	w8(&wr, 32)
	w8(&wr, 0x28) // 8 alpha bits, top-left origin
	for p in pix[:w * h] {
		append(&wr.b, p.b, p.g, p.r, p.a)
	}
	return wr.b[:]
}

// QOI ("Quite OK Image") encoder, per the reference specification.
qoi_encode :: proc(pix: []Color, w, h: int) -> []u8 {
	out := make([dynamic]u8, 0, 22 + w * h * 2, context.temp_allocator)
	be32 :: proc(out: ^[dynamic]u8, v: u32) {
		append(out, u8(v >> 24), u8(v >> 16), u8(v >> 8), u8(v))
	}
	append(&out, 'q', 'o', 'i', 'f')
	be32(&out, u32(w))
	be32(&out, u32(h))
	append(&out, 4, 0)
	index: [64]Color
	prev := Color{0, 0, 0, 255}
	run := 0
	n := w * h
	for i in 0 ..< n {
		p := pix[i]
		if p == prev {
			run += 1
			if run == 62 || i == n - 1 {
				append(&out, u8(0xC0 | (run - 1)))
				run = 0
			}
			continue
		}
		if run > 0 {
			append(&out, u8(0xC0 | (run - 1)))
			run = 0
		}
		hsh := (int(p.r) * 3 + int(p.g) * 5 + int(p.b) * 7 + int(p.a) * 11) % 64
		if index[hsh] == p {
			append(&out, u8(hsh))
		} else {
			index[hsh] = p
			if p.a == prev.a {
				vr := int(i8(p.r - prev.r))
				vg := int(i8(p.g - prev.g))
				vb := int(i8(p.b - prev.b))
				vg_r, vg_b := vr - vg, vb - vg
				if vr > -3 && vr < 2 && vg > -3 && vg < 2 && vb > -3 && vb < 2 {
					append(&out, u8(0x40 | (vr + 2) << 4 | (vg + 2) << 2 | (vb + 2)))
				} else if vg_r > -9 && vg_r < 8 && vg > -33 && vg < 32 && vg_b > -9 && vg_b < 8 {
					append(&out, u8(0x80 | (vg + 32)), u8((vg_r + 8) << 4 | (vg_b + 8)))
				} else {
					append(&out, 0xFE, p.r, p.g, p.b)
				}
			} else {
				append(&out, 0xFF, p.r, p.g, p.b, p.a)
			}
		}
		prev = p
	}
	append(&out, 0, 0, 0, 0, 0, 0, 0, 1)
	return out[:]
}

export_run :: proc(f: Export_Format, quality, scale_pct: int) {
	d := doc
	base := name_str(&d.title)
	if d.path != "" {
		base = path_stem(d.path)
	}
	ext := EXPORT_EXT[f]
	filters := [1]Filter{{fmt.tprintf("%s image (*.%s)", strings.to_upper(ext, context.temp_allocator), ext), fmt.tprintf("*.%s", ext)}}
	p, ok := native_dialog(true, "Export image", filters[:], ext, fmt.tprintf("%s.%s", base, ext))
	if !ok {
		return
	}
	defer delete(p)
	if eok, msg := export_to_path(d, p, f, quality, scale_pct); eok {
		set_status(msg)
		macro_record("file.Export", "format", EXPORT_KEYS[f], "quality", fmt.tprint(quality), "scale", fmt.tprint(scale_pct), "path", export_path_template(d, p))
	} else {
		show_message("Export", msg)
	}
}

// Writes the export to `path` without asking: the visible image, or with `layer` >= 0 that layer alone (a still
// format only). `msg` says what was written, or why it failed.
export_to_path :: proc(d: ^Doc, path: string, f: Export_Format, quality, scale_pct: int, layer := -1) -> (ok: bool, msg: string) {
	fail := fmt.tprintf("Failed to write %s", path_basename(path))
	#partial switch f {
	case .GIF:
		data := export_gif_bytes(d, scale_pct)
		if data == nil || !write_file(path, data) do return false, fail
		return true, fmt.tprintf("Exported %s (%d KB)", path_basename(path), len(data) / 1024)
	case .PNG_Sequence:
		n := export_png_sequence(d, path, scale_pct)
		if n == 0 do return false, fail
		return true, fmt.tprintf("Exported %d frames as %s_001.png ...", n, path_stem(path))
	}
	pix: []Color
	w, h: int
	if layer >= 0 {
		pix, w, h = export_layer_pixels(d, layer, scale_pct)
	} else {
		pix, w, h = export_frame_pixels(d, d.active_frame, scale_pct)
	}
	defer delete(pix)
	data := export_encode(pix, w, h, f, quality)
	if data == nil || !write_file(path, data) do return false, fail
	return true, fmt.tprintf("Exported %s (%d KB)", path_basename(path), len(data) / 1024)
}

// One PNG per frame of the playback range: `path` without its extension, then _001.png and so on.
// Returns how many were written, or 0 on failure.
export_png_sequence :: proc(d: ^Doc, path: string, scale_pct: int) -> int {
	lo, hi, _ := play_range()
	stem := strings.trim_suffix(path, path_ext(path))
	for fi in lo ..= hi {
		// a long sequence of large frames should not pile up in temp memory
		tmp := runtime.default_temp_allocator_temp_begin()
		defer runtime.default_temp_allocator_temp_end(tmp)
		pix, w, h := export_frame_pixels(d, fi, scale_pct)
		defer delete(pix)
		if !write_file(fmt.tprintf("%s_%03d.png", stem, fi - lo + 1), encode_png(pix, w, h)) do return 0
	}
	return hi - lo + 1
}

// One frame flattened, at the export scale. The caller frees it.
export_frame_pixels :: proc(d: ^Doc, f, scale_pct: int) -> (pix: []Color, w, h: int) {
	pix = make([]Color, d.w * d.h)
	frame_composite(d, f, pix)
	return export_scaled(pix, d.w, d.h, scale_pct)
}

// One layer's own pixels in the current frame, whether it is shown or not and whatever its opacity and blend mode, at
// the export scale. The caller frees it.
export_layer_pixels :: proc(d: ^Doc, layer, scale_pct: int) -> (pix: []Color, w, h: int) {
	pix = layer_flat(d, &d.layers[layer], context.allocator)
	return export_scaled(pix, d.w, d.h, scale_pct)
}

// `pix` scaled to `scale_pct` (it is freed if a new buffer replaces it).
export_scaled :: proc(pix_in: []Color, w_in, h_in, scale_pct: int) -> (pix: []Color, w, h: int) {
	pix, w, h = pix_in, w_in, h_in
	if scale_pct != 100 {
		nw, nh := max(w * scale_pct / 100, 1), max(h * scale_pct / 100, 1)
		out := make([]Color, nw * nh)
		resample(pix, w, h, out, nw, nh, .Bicubic)
		delete(pix)
		pix, w, h = out, nw, nh
	}
	return
}

// The playback range as an animated GIF, in the order its tag plays. Allocated in temp memory.
export_gif_bytes :: proc(d: ^Doc, scale_pct: int) -> []u8 {
	lo, hi, dir := play_range()
	order := make([dynamic]int, context.temp_allocator)
	switch dir {
	case .Forward:
		for f in lo ..= hi do append(&order, f)
	case .Reverse:
		for f := hi; f >= lo; f -= 1 do append(&order, f)
	case .Ping_Pong:
		for f in lo ..= hi do append(&order, f)
		for f := hi - 1; f > lo; f -= 1 do append(&order, f)
	}
	frames := make([][]Color, len(order), context.temp_allocator)
	delays := make([]int, len(order), context.temp_allocator)
	w, h: int
	cached := make(map[int][]Color, len(order), context.temp_allocator) // ping-pong shows frames twice
	for f, i in order {
		if have, ok := cached[f]; ok {
			frames[i] = have
		} else {
			frames[i], w, h = export_frame_pixels(d, f, scale_pct)
			cached[f] = frames[i]
		}
		delays[i] = d.frames[f].duration
	}
	defer for _, pix in cached do delete(pix)
	return gif_encode_frames(frames, w, h, 1, delays, true)
}

// Text layers: the settings the pixels were rendered from.
write_text :: proc(w: ^Writer, t: ^Text_Info) {
	wstr(w, name_str(&t.font))
	w32(w, u32(t.size))
	wcol(w, t.color)
	w8(w, t.align)
	w32(w, u32(t.line_pct))
	w32(w, transmute(u32)i32(t.track))
	w32(w, transmute(u32)t.x)
	w32(w, transmute(u32)t.y)
	for v in ([4]int{t.bx.x0, t.bx.y0, t.bx.x1, t.bx.y1}) do w32(w, transmute(u32)i32(v))
	w32(w, u32(t.n))
	append(&w.b, ..t.buf[:t.n])
	// version 3: character colours
	w8(w, u8(t.npal))
	for c in t.pal[:t.npal] do wcol(w, c)
	if t.npal > 0 {
		append(&w.b, ..t.cidx[:t.n])
	}
}

read_text :: proc(r: ^Reader, t: ^Text_Info, ver: int) {
	t.on = true
	name_set(&t.font, rstr(r))
	t.size = int(r32(r))
	t.color = rcol(r)
	t.align = min(r8(r), 2)
	t.line_pct = int(r32(r))
	t.track = int(transmute(i32)r32(r))
	t.x = transmute(f32)r32(r)
	t.y = transmute(f32)r32(r)
	t.bx.x0 = int(transmute(i32)r32(r))
	t.bx.y0 = int(transmute(i32)r32(r))
	t.bx.x1 = int(transmute(i32)r32(r))
	t.bx.y1 = int(transmute(i32)r32(r))
	n := int(r32(r))
	if n < 0 || n > TEXT_MAX || r.pos + n > len(r.d) {
		r.bad = true
		return
	}
	copy(t.buf[:n], r.d[r.pos:r.pos + n])
	t.n = n
	r.pos += n
	t.size = clamp(t.size, 1, 4000)
	t.line_pct = clamp(t.line_pct, 10, 1000)
	if ver < 3 do return
	t.npal = int(r8(r))
	if t.npal > TEXT_PAL {
		r.bad = true
		return
	}
	for &c in t.pal[:t.npal] do c = rcol(r)
	if t.npal > 0 {
		if r.pos + n > len(r.d) {
			r.bad = true
			return
		}
		copy(t.cidx[:n], r.d[r.pos:r.pos + n])
		r.pos += n
		for &k in t.cidx[:n] do if int(k) > t.npal do k = 0
	}
}
