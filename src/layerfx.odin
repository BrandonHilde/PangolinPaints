package pangolin

import "core:fmt"
import "core:strings"

// Live layer effects: macros attached to a layer, run again whenever the layer changes, switched on and off, saved with
// the painting. The macros run in order on a copy of the layer in a document of its own (layer_fx_run), never on the
// painting: what that copy looks like at the end, with the blend mode and opacity the macros left it, is drawn in place
// of the layer's own pixels (composite_box, through fx_layers). So "Soft Light + Blur" blurs the layer's pixels and
// blends it as Soft Light. The layer's mask still applies, after the effects.
//
// Effects are worked out again once the mouse is up after a change (while painting, the layer shows as it is), and only
// when the layer's pixels, its effects or the macros changed. They apply to the current frame. Steps with an effect
// outside the copy (saving, exporting, tools, colors, brushes, the clipboard, the canvas size) are refused in an effect.

MAX_LAYER_FX :: 4

Layer_Fx :: struct {
	name: Name, // the macro's name
	on:   bool,
}

// What a layer's effects gave, kept by the document per layer uid.
Fx_Cache :: struct {
	pix:     Tiles, // the layer as its effects left it
	blend:   Blend,
	opacity: u8,
	ok:      bool, // pix holds a result
	stale:   bool, // something changed: check, and run the effects again if what they read changed
	sig:     u64, // what the result was made from
	err:     Name, // why the effects didn't run, if they didn't
}

fx_sandbox: bool // the effects of a layer are running, on a copy of it in a document of its own
fx_lib_seen := -1 // macro_lib_gen when the effects were last checked

// Marks layer `uid`'s effects (or every layer's, with uid 0) to be checked again.
fx_mark_stale :: proc(d: ^Doc, uid := 0) {
	if fx_sandbox do return
	for k, &c in d.fx_cache do if uid == 0 || k == uid do c.stale = true
}

fx_cache_free :: proc(d: ^Doc) {
	for _, &c in d.fx_cache do tiles_destroy(&c.pix)
	delete(d.fx_cache)
	d.fx_cache = nil
}

// Does any layer have an effect switched on?
layer_fx_on :: proc(l: ^Layer) -> bool {
	for f in l.fx[:l.fx_n] do if f.on do return true
	return false
}

// The layers to composite with their effects' results in place of their own pixels (temp memory), or `layers` itself
// when no layer of `d` has one. Only for the current frame: `layers` must be (part of) d.layers.
fx_layers :: proc(d: ^Doc, layers: []Layer) -> []Layer {
	if d == nil || len(d.fx_cache) == 0 || len(layers) == 0 do return layers
	// a slice of the document's own list (not a frame's copy)
	base, end := uintptr(raw_data(d.layers)), uintptr(raw_data(d.layers)) + uintptr(len(d.layers) * size_of(Layer))
	if p := uintptr(raw_data(layers)); p < base || p >= end do return layers
	out: []Layer
	for &l, i in layers {
		if l.fx_n == 0 || l.is_group || !layer_fx_on(&l) do continue
		c, has := d.fx_cache[l.uid]
		if !has || !c.ok || c.stale do continue
		if out == nil {
			out = make([]Layer, len(layers), context.temp_allocator)
			copy(out, layers)
		}
		out[i].pix = c.pix
		out[i].blend = c.blend
		out[i].opacity = c.opacity
	}
	return out != nil ? out : layers
}

// What a layer's effects read: its pixels (a hash), and its effects. Changes when either does.
@(private = "file")
fx_signature :: proc(d: ^Doc, l: ^Layer) -> u64 {
	h: u64 = 14695981039346656037
	mix :: proc(h: ^u64, v: u64) {
		h^ = (h^ ~ v) * 1099511628211
	}
	for t, i in l.pix.t {
		if t == nil do continue
		mix(&h, u64(i) + 1)
		for p in t.pix do mix(&h, u64(transmute(u32)p))
	}
	mix(&h, u64(l.blend))
	mix(&h, u64(l.opacity))
	for &f in l.fx[:l.fx_n] {
		for b in f.name.b[:f.name.n] do mix(&h, u64(b))
		mix(&h, f.on ? 2 : 1)
	}
	return h
}

// Runs layer `li`'s effects on a copy of it. Returns the copy as they left it, w*h (temp memory).
layer_fx_run :: proc(d: ^Doc, li: int) -> (pix: []Color, blend: Blend, opacity: u8, ok: bool, msg: string) {
	src := &d.layers[li]
	sb := doc_new(d.w, d.h, "effects")
	defer doc_destroy(sb)
	for &l in sb.layers do layer_destroy(&l)
	clear(&sb.layers)
	base := layer_make(name_str(&src.name), d.w, d.h)
	tiles_from_buf(&base.pix, d.w, d.h, layer_flat(d, src), {})
	base.blend, base.opacity = src.blend, src.opacity
	base.uid = 1
	append(&sb.layers, base)
	sb.active_layer = 0
	saved := doc
	doc = sb
	fx_sandbox = true
	for &f in src.fx[:src.fx_n] {
		if !f.on do continue
		m := macro_find(name_str(&f.name))
		if m == nil {
			msg = fmt.tprintf("there is no macro called %s", name_str(&f.name))
			break
		}
		if rok, rmsg, _ := macro_run(m); !rok {
			msg = fmt.tprintf("%s: %s", m.name, rmsg)
			break
		}
	}
	fx_sandbox = false
	doc = saved
	if msg != "" do return
	if sb.w != d.w || sb.h != d.h do return nil, {}, 0, false, "an effect can't change the painting's size"
	bi := layer_find_uid(sb.layers[:], 1)
	if bi < 0 do return nil, {}, 0, false, "an effect has to keep its layer"
	b := &sb.layers[bi]
	blend, opacity = b.blend, b.opacity
	// the copy itself as plain pixels; layers the effects added in the copy blend onto it by their own modes
	b.blend, b.opacity, b.visible = .Normal, 255, true
	pix = doc_flat(sb, context.temp_allocator)
	return pix, blend, opacity, true, ""
}

// Can this step run in a layer effect? Not if it would reach outside the copy of the layer.
fx_step_allowed :: proc(id: string) -> bool {
	for p in ([?]string{"file.", "color.", "brush.", "image.", "cmd.Tool_", "cmd.Brush_", "cmd.Rotate_"}) do if strings.has_prefix(id, p) do return false
	switch id {
	case "cmd.Copy", "cmd.Copy_Merged", "cmd.Cut", "cmd.Swap_Colors", "cmd.Default_Colors", "cmd.Crop_Sel", "cmd.Trim":
		return false
	}
	return true
}

// Works out the effects that are out of date. Called every frame; does nothing while the mouse is down or something
// is being edited, so painting shows the layer as it is and its effects follow when the stroke ends.
fx_update :: proc(d: ^Doc) {
	if d == nil || macro_running || fx_sandbox do return
	if fx_lib_seen != macro_lib_gen {
		fx_lib_seen = macro_lib_gen
		fx_mark_stale(d)
	}
	// effects of layers that are gone or have none any more
	for uid, &c in d.fx_cache {
		i := layer_find_uid(d.layers[:], uid)
		if i < 0 || d.layers[i].fx_n == 0 {
			tiles_destroy(&c.pix)
			delete_key(&d.fx_cache, uid)
			fx_redraw(d)
			break // the map changed: the rest next frame
		}
	}
	busy := ui.down[0] || ui.down[1] || stroke.active || drag.active || text_edit.active || xform.active || (dialog.kind != .None && dialog.kind != .Layer_Fx)
	if busy do return
	for &l, li in d.layers {
		if l.fx_n == 0 || l.is_group do continue
		c, has := &d.fx_cache[l.uid]
		if !has {
			d.fx_cache[l.uid] = Fx_Cache{stale = true}
			c = &d.fx_cache[l.uid]
		}
		if !c.stale do continue
		c.stale = false
		sig := fx_signature(d, &l)
		if c.ok && c.sig == sig do continue
		was_ok := c.ok
		c.sig = sig
		if !layer_fx_on(&l) {
			c.ok = false
			name_set(&c.err, "")
			if was_ok do fx_redraw(d)
			continue
		}
		pix, blend, op, ok, msg := layer_fx_run(d, li)
		c = &d.fx_cache[l.uid] // the map may have moved
		if ok {
			if len(c.pix.t) == 0 do c.pix = tiles_make(d.w, d.h)
			tiles_from_buf(&c.pix, d.w, d.h, pix, {})
			c.blend, c.opacity, c.ok = blend, op, true
			name_set(&c.err, "")
		} else {
			c.ok = false
			name_set(&c.err, msg)
			set_statusf("Layer effects of %s: %s", name_str(&l.name), msg)
		}
		fx_redraw(d)
	}
}

// The picture needs drawing again (without marking the effects out of date: that is what doc_dirty would do).
@(private = "file")
fx_redraw :: proc(d: ^Doc) {
	d.comp_dirty = box_union(d.comp_dirty, doc_box(d))
	d.thumb_dirty = true
	d.comp_lazy = false
	frame_cache_drop(d)
}

// Adds a macro as an effect of the active layer. False if it has as many as it can hold.
layer_fx_add :: proc(d: ^Doc, name: string) -> bool {
	l := &d.layers[d.active_layer]
	if l.is_group || l.fx_n >= MAX_LAYER_FX do return false
	history_push(d)
	name_set(&l.fx[l.fx_n].name, name)
	l.fx[l.fx_n].on = true
	l.fx_n += 1
	fx_mark_stale(d, l.uid)
	doc_touch_all(d)
	return true
}

layer_fx_remove :: proc(d: ^Doc, k: int) {
	l := &d.layers[d.active_layer]
	if k < 0 || k >= l.fx_n do return
	history_push(d)
	for j in k ..< l.fx_n - 1 do l.fx[j] = l.fx[j + 1]
	l.fx_n -= 1
	l.fx[l.fx_n] = {}
	doc_touch_all(d)
}

// Makes the active layer's effects part of its pixels, and takes them off. False if they can't run.
layer_fx_apply :: proc(d: ^Doc) -> bool {
	li := d.active_layer
	l := &d.layers[li]
	if l.fx_n == 0 do return false
	pix, blend, op, ok, msg := layer_fx_run(d, li)
	if !ok {
		set_statusf("The effects can't be applied: %s", msg)
		return false
	}
	history_push(d)
	l = &d.layers[li]
	layer_rasterize(d, l)
	tiles_from_buf(&l.pix, d.w, d.h, pix, {})
	l.blend, l.opacity = blend, op
	l.fx_n = 0
	l.fx = {}
	doc_touch_all(d)
	return true
}

// ---------------------------------------------------------------------------
// The Layer Effects window
// ---------------------------------------------------------------------------

dlg_layer_fx :: proc() {
	d := doc
	l := &d.layers[d.active_layer]
	c := dialog_frame(fmt.tprintf("Layer Effects: %s", name_str(&l.name)), 400, 64 + MAX_LAYER_FX * 22 + 60)
	y := c.y
	if l.is_group {
		text(c.x, y + 3, "A group can't have effects: pick a layer in it.", C_TEXT_DIM)
	} else {
		if l.fx_n == 0 {
			for line, i in tooltip_wrap("No effects yet. Add a macro below: it runs on this layer whenever the layer changes, and the canvas shows the result.", c.w, text_w) {
				text(c.x, y + 3 + i32(i) * 13, line, C_TEXT_DIM)
			}
		}
		for k := 0; k < l.fx_n; k += 1 {
			f := &l.fx[k]
			ry := y + i32(k) * 22
			on := f.on
			if checkbox(c.x, ry + 2, "", &on, {"On", "Switch this effect on or off. Off, the layer shows as if it weren't there."}) {
				history_push(d)
				f.on = on
				doc_touch_all(d)
			}
			name := name_str(&f.name)
			missing := macro_find(name) == nil
			text_clipped(Rect{c.x + 22, ry + 3, c.w - 22 - 4 * 24, 12}, missing ? fmt.tprintf("%s (there is no macro called this)", name) : name, missing ? C_DANGER : (f.on ? C_TEXT : C_TEXT_DIM))
			bx := c.x + c.w - 4 * 24
			if button(Rect{bx, ry, 22, 16}, "...", {"Edit", "Open this macro in the node editor. Every layer using it follows what you change."}, !missing) {
				dialog_close()
				macro_editor_open(name)
				return
			}
			if icon_button(Rect{bx + 24, ry, 22, 16}, .Up, {"Earlier", "Run this effect before the one above it."}, k > 0) && k > 0 {
				history_push(d)
				l.fx[k], l.fx[k - 1] = l.fx[k - 1], l.fx[k]
				doc_touch_all(d)
			}
			if icon_button(Rect{bx + 48, ry, 22, 16}, .Down, {"Later", "Run this effect after the one below it."}, k < l.fx_n - 1) && k < l.fx_n - 1 {
				history_push(d)
				l.fx[k], l.fx[k + 1] = l.fx[k + 1], l.fx[k]
				doc_touch_all(d)
			}
			if icon_button(Rect{bx + 72, ry, 22, 16}, .Trash, {"Remove", "Take this effect off the layer."}) {
				layer_fx_remove(d, k)
				break
			}
		}
		y += MAX_LAYER_FX * 22 + 4
		if len(macro_lib) == 0 {
			text(c.x, y + 3, "Make a macro first, in Macros > Node Editor.", C_TEXT_DIM)
		} else if l.fx_n < MAX_LAYER_FX {
			@(static) names: [MACRO_MAX + 1]string
			names[0] = "Add an effect..."
			n := min(len(macro_lib), MACRO_MAX)
			for m, i in macro_lib[:n] do names[i + 1] = m.name
			if nv, ch := combo(Rect{c.x, y, 220, 14}, names[:n + 1], 0, {"Add an effect", "Pick a macro to run on this layer whenever it changes. Make one in Macros > Node Editor."}); ch && nv > 0 {
				layer_fx_add(d, macro_lib[nv - 1].name)
			}
		}
		y += 22
		if fc, has := d.fx_cache[l.uid]; has && fc.err.n > 0 {
			text_clipped(Rect{c.x, y + 3, c.w, 12}, fmt.tprintf("Not shown: %s", name_str(&fc.err)), C_DANGER)
		}
		if button(Rect{c.x, c.y + c.h - 18, 110, 18}, "Apply Effects", {"", cmd_help(.Layer_Fx_Apply)}, l.fx_n > 0) {
			dialog_close()
			run_cmd(.Layer_Fx_Apply)
			return
		}
	}
	ok, _ := dialog_buttons(c, "Close this window (Enter).", "Close", "")
	if ok || IsKeyPressed(.ESCAPE) do dialog_close()
}

// A painting brought the macro of one of its effects: the library gets it if it hasn't one by that name.
fx_macro_arrived :: proc(name, text: string) {
	if text == "" || macro_find(name) != nil do return
	m, ok := macro_from_text(text)
	if !ok do return
	if m.app != macro_app_id() {
		macro_free(m)
		return
	}
	macro_set_name(m, name)
	if macro_add(m) {
		set_statusf("Added the macro %s, which an effect in this painting uses", m.name)
	} else {
		macro_free(m)
	}
}
