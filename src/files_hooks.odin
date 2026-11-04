package pangolin

import "core:fmt"
import "core:math"

// What the shared file browser needs to know about Paints (see shared files.odin).

FILES_HINT :: "Drag an image onto the canvas to add it as a layer, or anything onto the tab bar to open it."

files_listed :: proc(name: string) -> bool {
	ext := lower_ext(name)
	switch ext {
	case ".tif", ".tiff", ".psd", ".psb", ".kra", ".ppnt":
		return true
	}
	return is_common_image_ext(ext)
}

@(private = "file")
is_project :: proc(path: string) -> bool {
	switch lower_ext(path) {
	case ".ppnt", ".psd", ".psb", ".kra":
		return true
	}
	return false
}

// Runs on the thumbnail thread. The decoders and doc_flat only touch the document they make, and
// a decoded document shares its tiles with nothing, so non-atomic tile refs are not a problem. Nothing
// here may reach the main thread's state: `doc`, the frame cache, status messages or fonts.
files_preview :: proc(path: string) -> (pix: []Color, w, h: int, ok: bool) {
	if lower_ext(path) != ".ppnt" do return load_image_pixels(path)
	data, rok := read_file(path)
	if !rok do return
	defer delete(data)
	d, dok := project_decode(data)
	if !dok do return
	defer doc_destroy(d)
	return doc_flat(d), d.w, d.h, true
}

files_preview_on_main :: proc(path: string) -> bool {
	return false
}

bottom_has_timeline :: proc() -> bool {
	return true
}

files_drop_hint :: proc(path: string, on_tabs: bool) -> string {
	if on_tabs do return "Drop to open in a new tab"
	return is_project(path) ? "Drop to open" : "Drop to add as a layer"
}

files_drop :: proc(path: string, on_tabs: bool) {
	stop_playback()
	if on_tabs || is_project(path) {
		open_path(path)
		return
	}
	tools_commit_pending()
	place_image_at(path, pointer_to_canvas())
}

pointer_to_canvas :: proc() -> IVec {
	return ipt(screen_to_canvas(ui.ptr.x / ui.scale, ui.ptr.y / ui.scale))
}

// Where an image's top left corner goes when its middle lands on canvas pixel `center`. Some of it
// always stays on the canvas, so a drop beside the painting does not make an empty layer.
image_place :: proc(w, h: int, center: IVec) -> (x, y: int) {
	return clamp(center.x - w / 2, 1 - w, doc.w - 1), clamp(center.y - h / 2, 1 - h, doc.h - 1)
}

// An image as a new layer at its own size, its middle at `center`; what falls off the canvas is cut.
place_image_at :: proc(path: string, center: IVec) {
	d := doc
	pix, w, h, ok := load_image_pixels(path)
	if !ok {
		show_message("Import", "Cannot read the image.")
		return
	}
	defer delete(pix)
	ox, oy := image_place(w, h, center)
	buf := make([]Color, d.w * d.h, context.temp_allocator)
	for y in max(-oy, 0) ..< min(h, d.h - oy) {
		for x in max(-ox, 0) ..< min(w, d.w - ox) {
			buf[(y + oy) * d.w + x + ox] = pix[y * w + x]
		}
	}
	doc_add_layer_from(d, path_stem(path), buf)
	cut := ox < 0 || oy < 0 || ox + w > d.w || oy + h > d.h
	set_statusf(cut ? "Imported %s (cut to the canvas)" : "Imported %s", path_basename(path))
}

// The thumbnail at the canvas's zoom, cut off where the canvas ends: what the layer will hold.
files_ghost :: proc(thumb: Texture, img_w, img_h: int) -> bool {
	if files_drag.idx < 0 || files_drag.idx >= len(files) || is_project(files[files_drag.idx].path) do return false
	d := doc
	z := d.zoom
	x, y := image_place(img_w, img_h, pointer_to_canvas())
	dst := FRect{d.ox + f32(x) * z, d.oy + f32(y) * z, f32(img_w) * z, f32(img_h) * z}
	clip_begin(canvas_vp)
	clip_begin(Rect{i32(math.floor(d.ox)), i32(math.floor(d.oy)), i32(math.ceil(f32(d.w) * z)), i32(math.ceil(f32(d.h) * z))})
	draw_tex(thumb, {0, 0, f32(thumb.w), f32(thumb.h)}, dst, Color{255, 255, 255, 190})
	clip_end()
	draw_rect_outline(dst, C_ACCENT)
	clip_end()
	return true
}

_ :: fmt
