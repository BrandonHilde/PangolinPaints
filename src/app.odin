package pangolin

import "core:fmt"
import "core:strings"

// Open documents and the active one.
docs: [dynamic]^Doc
doc: ^Doc

cur_tool: Tool = .Brush

fg: Color = {32, 28, 26, 255}
bg: Color = {255, 255, 255, 255}
// HSV of the foreground colour (kept separately so hue survives grey colours).
fg_h, fg_s, fg_v: f32

// Recently used paint colours, newest first.
RECENT_MAX :: 24
recent: [dynamic]Color

// Status bar message
status_msg: Name
status_t: f32

// View toggles
show_pixel_grid := true
show_thirds := false
show_navigator := true
brush_blend: Blend // blend mode of the Brush tool, switched by blend-mode tool groups
canvas_mode := false // Tab: hide the side panels, tabs and status bar, leaving only the top bars
bg_mode := 0 // canvas transparency: 0 checker, 1 black, 2 white, 3 gray

// Internal clipboard (copied pixels with their position)
Clip :: struct {
	w, h: int,
	x, y: int,
	pix:  []Color,
}
clip: Clip

want_quit: bool

set_status :: proc(s: string) {
	name_set(&status_msg, s)
	status_t = 4
}

set_statusf :: proc(format: string, args: ..any) {
	set_status(fmt.tprintf(format, ..args))
}

set_fg :: proc(c: Color) {
	fg = Color{c.r, c.g, c.b, 255}
	h, s, v := rgb_to_hsv(c)
	if s > 0.001 && v > 0.001 {
		fg_h = h
	}
	fg_s, fg_v = s, v
}

set_fg_hsv :: proc(h, s, v: f32) {
	fg_h, fg_s, fg_v = h, s, v
	fg = hsv_to_rgb(h, s, v)
}

// Remember a colour that was painted with.
recent_push :: proc(c: Color) {
	cc := Color{c.r, c.g, c.b, 255}
	for x, i in recent {
		if x == cc {
			ordered_remove(&recent, i)
			break
		}
	}
	inject_at(&recent, 0, cc)
	if len(recent) > RECENT_MAX {
		resize(&recent, RECENT_MAX)
	}
}

add_doc :: proc(d: ^Doc) {
	append(&docs, d)
	doc = d
	d.view_init = false
}

switch_doc :: proc(i: int) {
	if i >= 0 && i < len(docs) && docs[i] != doc {
		tools_commit_pending()
		doc = docs[i]
	}
}

doc_index :: proc(d: ^Doc) -> int {
	for x, i in docs {
		if x == d {
			return i
		}
	}
	return -1
}

close_doc :: proc(d: ^Doc) {
	if d == doc {
		tools_commit_pending()
	}
	i := doc_index(d)
	if i < 0 {
		return
	}
	ordered_remove(&docs, i)
	if tex_doc == d {
		tex_doc = nil
	}
	doc_destroy(d)
	if len(docs) == 0 {
		nd := doc_new_filled(1600, 1200, "Untitled", Color{255, 255, 255, 255})
		nd.modified = false
		append(&docs, nd)
		doc = nd
	} else {
		doc = docs[clamp(i, 0, len(docs) - 1)]
	}
	doc.view_init = false
}

// New document whose background layer is filled with `fill` (alpha 0 = transparent).
doc_new_filled :: proc(w, h: int, title: string, fill: Color) -> ^Doc {
	d := doc_new(w, h, title)
	if fill.a != 0 {
		tiles_fill(&d.layers[0].pix, fill, {})
	} else {
		name_set(&d.layers[0].name, "Layer 1")
	}
	return d
}

// Display name with modified marker.
doc_display_name :: proc(d: ^Doc) -> string {
	return fmt.tprintf("%s%s", name_str(&d.title), d.modified ? "*" : "")
}

path_basename :: proc(p: string) -> string {
	i := strings.last_index_any(p, "/\\")
	if i >= 0 {
		return p[i + 1:]
	}
	return p
}

path_stem :: proc(p: string) -> string {
	b := path_basename(p)
	i := strings.last_index_byte(b, '.')
	if i > 0 {
		return b[:i]
	}
	return b
}

path_ext :: proc(p: string) -> string {
	b := path_basename(p)
	i := strings.last_index_byte(b, '.')
	if i >= 0 {
		return b[i:]
	}
	return ""
}

lower_ext :: proc(p: string) -> string {
	return strings.to_lower(path_ext(p), context.temp_allocator)
}
