package pangolin

import "core:fmt"
import "core:strconv"
import "core:os"
import "core:strings"

// Colour swatches shown in the right panel (shared by all documents).
swatches: [dynamic]Color
swatch_sel: int

Swatch_Preset :: enum {
	Oil_Paints,
	Basic,
	Skin_Tones,
	Earth_Sky,
	Pastels,
	Grays,
}

SWATCH_PRESET_NAMES := [Swatch_Preset]string {
	.Oil_Paints = "Oil paints",
	.Basic      = "Basic",
	.Skin_Tones = "Skin tones",
	.Earth_Sky  = "Earth & sky",
	.Pastels    = "Pastels",
	.Grays      = "Grays",
}

// Classic artists' pigments, roughly as they look straight from the tube.
OIL_PAINTS := [?]u32 {
	0xf4f1e8, 0xfbe9a6, 0xf6d32a, 0xf2a31b, 0xe8681e, 0xd73a24, 0xb3202a, 0x8c1c3a,
	0xc8507a, 0x5e2a6e, 0x2a2f8f, 0x1b3a7a, 0x2c6eb5, 0x4aa3c9, 0x1f6d5c, 0x2f7d32,
	0x6b8e23, 0xb8a04a, 0xc38a3c, 0xa0522d, 0x8b4b2b, 0x5b3a29, 0x3b2a20, 0x1c1a1a,
}

BASIC := [?]u32 {
	0x000000, 0x404040, 0x808080, 0xc0c0c0, 0xffffff, 0xff0000, 0xff8000, 0xffff00,
	0x80ff00, 0x00ff00, 0x00ff80, 0x00ffff, 0x0080ff, 0x0000ff, 0x8000ff, 0xff00ff,
}

SKIN_TONES := [?]u32 {
	0xffe0c8, 0xf9cfae, 0xf1c09a, 0xe8ad87, 0xd99a72, 0xc68863, 0xb07352, 0x9a6244,
	0x83523a, 0x6b412e, 0x553425, 0x3d261c, 0xf2b8a0, 0xd88c78, 0xb86b5c, 0x8e4a40,
}

EARTH_SKY := [?]u32 {
	0xdbe9f4, 0xa9cce3, 0x6fa8dc, 0x3d78b5, 0x234b80, 0x1a2c4e, 0xf7d9a8, 0xf0b26b,
	0xd77a3c, 0xa64b2a, 0x6f3a24, 0x40281a, 0xc7d6a0, 0x8fae5b, 0x5b7f3a, 0x34522a,
}

PASTELS := [?]u32 {
	0xffd1dc, 0xffb3ba, 0xffdfba, 0xffffba, 0xbaffc9, 0xbae1ff, 0xc9c9ff, 0xe0bbe4,
	0x957dad, 0xd291bc, 0xfec8d8, 0xffdfd3, 0xb5ead7, 0xc7ceea, 0xe2f0cb, 0xffdac1,
}

swatch_preset_colors :: proc(p: Swatch_Preset) -> []Color {
	src: []u32
	switch p {
	case .Oil_Paints:
		src = OIL_PAINTS[:]
	case .Basic:
		src = BASIC[:]
	case .Skin_Tones:
		src = SKIN_TONES[:]
	case .Earth_Sky:
		src = EARTH_SKY[:]
	case .Pastels:
		src = PASTELS[:]
	case .Grays:
		out := make([]Color, 16, context.temp_allocator)
		for i in 0 ..< 16 {
			v := u8(i * 255 / 15)
			out[i] = Color{v, v, v, 255}
		}
		return out
	}
	out := make([]Color, len(src), context.temp_allocator)
	for v, i in src {
		out[i] = hexc(v)
	}
	return out
}

swatches_set_preset :: proc(p: Swatch_Preset) {
	clear(&swatches)
	for c in swatch_preset_colors(p) {
		append(&swatches, c)
	}
	swatch_sel = 0
}

swatches_save_gpl :: proc(path: string) -> bool {
	sb := strings.builder_make(context.temp_allocator)
	fmt.sbprintf(&sb, "GIMP Palette\nName: Pangolin Paints\nColumns: 8\n#\n")
	for c, i in swatches {
		fmt.sbprintf(&sb, "%3d %3d %3d\tSwatch %d\n", c.r, c.g, c.b, i + 1)
	}
	return write_file(path, transmute([]u8)strings.to_string(sb))
}

swatches_load_gpl :: proc(path: string) -> bool {
	data, ok := read_file(path)
	if !ok {
		return false
	}
	defer delete(data)
	text := string(data)
	pal := make([dynamic]Color, context.temp_allocator)
	for line in strings.split_lines_iterator(&text) {
		l := strings.trim_space(line)
		if len(l) == 0 || l[0] == '#' || strings.has_prefix(l, "GIMP") || strings.has_prefix(l, "Name") || strings.has_prefix(l, "Columns") {
			continue
		}
		fields := strings.fields(l, context.temp_allocator)
		if len(fields) < 3 {
			continue
		}
		r, rok := strconv.parse_int(fields[0])
		g, gok := strconv.parse_int(fields[1])
		b, bok := strconv.parse_int(fields[2])
		if rok && gok && bok {
			append(&pal, Color{u8(clamp(r, 0, 255)), u8(clamp(g, 0, 255)), u8(clamp(b, 0, 255)), 255})
		}
	}
	if len(pal) == 0 {
		return false
	}
	clear(&swatches)
	append(&swatches, ..pal[:])
	swatch_sel = 0
	return true
}

// File helpers.
read_file :: proc(path: string) -> (data: []u8, ok: bool) {
	d, err := os.read_entire_file_from_path(path, context.allocator)
	if err != nil {
		return nil, false
	}
	return d, true
}

write_file :: proc(path: string, data: []u8) -> bool {
	return os.write_entire_file_from_bytes(path, data) == nil
}
