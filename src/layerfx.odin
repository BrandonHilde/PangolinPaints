package pangolin

import "core:fmt"
import "core:os"
import "core:strings"
import "core:sync"

// Live layer effects: macros attached to a layer (or a group), run again whenever it changes, switched on and off,
// saved with the painting. The usual way to give a layer one is its blend list, which offers the macros after the
// blend modes; the Layer Effects window stacks several.
//
// The macros run in order on a copy of the layer in a document of its own (layer_fx_run), never on the painting. What
// that copy looks like at the end, with the blend mode and opacity the macros left it, is drawn in place of the layer's
// own pixels (a group: in place of its layers, combined). So "Soft Light + Blur" blurs the layer and blends it as Soft
// Light. A layer's mask still applies, after the effects. Develop nodes set to Layer pixels (develop.odin) are the one
// exception: they are given the picture under the layer as well, change it where the layer is painted, and that is
// what shows, which makes the layer an adjustment layer you paint.
//
// Results are kept per layer and frame. The current frame's are worked out once the mouse is up after a change
// (fx_update); while painting, the layer shows as it is. Other frames' are worked out when they are drawn or exported
// (frame_layers), and again only when what they read changed. Effects only run on the main thread. Steps that would
// reach outside the copy (saving, exporting, tools, colors, brushes, the clipboard, the canvas size) are refused.
//
// How often they run is up to each macro's Trigger (its Start node, macro_trigger), so a heavy macro needn't run after
// every stroke: On Paint after every change, After a Pause once the layer has been left alone for its Seconds, Every N
// Seconds at most that often, On Demand when added, once when painting on the layer stops (the pen has stayed up for
// FX_PAINT_SETTLE, fx_stroke_done) and on Refresh (the circling arrow by a layer's fx, or the Layer Effects window). A layer's effects run together, so the layer
// follows the most careful trigger among them (layer_fx_trigger). Switching an effect, adding, removing or reordering
// them, or changing the layer's blend mode or opacity runs them straight away whatever the trigger: only new pixels
// and edits to the macros wait for it. On Hotkey macros are run by the user, not on layers: the lists here leave them out.

MAX_LAYER_FX :: 4

Layer_Fx :: struct {
	name: Name, // the macro's name
	on:   bool,
}

Fx_Key :: struct {
	uid, frame: int,
}

// What a layer's effects gave on one frame.
Fx_Cache :: struct {
	pix:     Tiles, // the layer as its effects left it
	blend:   Blend,
	opacity: u8,
	ok:      bool, // pix holds a result
	stale:   bool, // something changed: check what the effects read, and run them again if it changed
	has_sig: bool,
	sig:     u64, // what the result was made from
	set_sig: u64, // the effects and layer settings it was made with (fx_settings_sig): a change there runs them at once
	err:     Name, // why the effects didn't run, if they didn't
	changed_at: f64, // gfx_time of the last change (After a Pause waits from here)
	ran_at:  f64, // gfx_time of the last run (Every N Seconds waits from here)
	refresh: bool, // run them again now, whatever the trigger and even if nothing changed (Refresh)
	below:   bool, // they read the picture under the layer (a Develop node on Layer pixels): any change may change them
	painted: bool, // On Demand: painted on (or under, for `below`); they run once painting has stopped (fx_stroke_done)
	paint_due: bool, // painting has stopped: run them if what they read changed
	patched: bool, // pix shows paint laid on since they ran (fx_paint_through): it isn't their result any more
}

// How long the pen has to stay up, with no new stroke, before On Demand effects count painting as finished. Shorter
// would run them in the gaps between strokes, which is where their time would be felt.
FX_PAINT_SETTLE :: 0.8
fx_paint_end: f64 // gfx_time when the last brush stroke ended

fx_sandbox: bool // the effects of a layer are running, on a copy of it in a document of its own
fx_main_tid: int // the main thread: the only one that runs effects (set at start-up)

current_thread_id :: proc() -> int {
	return sync.current_thread_id()
}

fx_on_main :: proc() -> bool {
	return fx_main_tid == 0 || current_thread_id() == fx_main_tid
}

// Marks layer `uid`'s effects (or every layer's, with uid 0) to be checked again. Effects that read the picture under
// their layer are checked whatever changed: their signature tells whether it was under them.
fx_mark_stale :: proc(d: ^Doc, uid := 0) {
	if fx_sandbox do return
	now := gfx_time()
	for k, &c in d.fx_cache {
		if uid == 0 || k.uid == uid || c.below {
			c.stale = true
			c.changed_at = now
		}
	}
}

// A brush stroke on the active layer just ended (the mouse button is up, the pen lifted off). On Demand effects that read
// what was painted (the layer's own, and those of layers that adjust the picture under it) are marked: fx_update runs
// them once the pen has stayed up for FX_PAINT_SETTLE with no new stroke, so a run of strokes costs one run, at the end,
// and none between strokes. Effects with other triggers keep to them.
fx_stroke_done :: proc(d: ^Doc) {
	if d == nil || len(d.layers) == 0 || fx_sandbox do return
	uid := d.layers[clamp(d.active_layer, 0, len(d.layers) - 1)].uid
	for &l in d.layers {
		if l.fx_n == 0 do continue
		if t, _ := layer_fx_trigger(&l); t != .Demand do continue
		key := Fx_Key{l.uid, d.active_frame}
		c, has := d.fx_cache[key]
		if l.uid != uid && !(has && c.below) do continue
		if !has do continue // never run yet: it runs anyway
		cp := &d.fx_cache[key]
		cp.stale, cp.painted = true, true // stale: the layer's refresh arrow is lit until they run
	}
	fx_paint_end = gfx_time()
}

// A brush stroke is painting box `b` of the active layer. Its effects don't run while painting, so their last result,
// which is what shows, would hide the paint: instead the pixels the stroke changed (against the stroke's copy of the
// layer from before it) are copied into that result, so the canvas shows the strokes as they go down, and the effects
// catch up as their trigger says (On Demand once painting stops). Pixels in the box the stroke didn't change keep the
// effect. Layers above that adjust the picture under them (Layer pixels) let the new paint show through there until
// they run again. Nothing is worked out: it costs a pass over the box.
fx_paint_through :: proc(d: ^Doc, b: Box) {
	if d == nil || len(d.fx_cache) == 0 || d.edit_mask || fx_sandbox || len(d.layers) == 0 || !stroke.active do return
	bw, bh := b.x1 - b.x0, b.y1 - b.y0
	if bw <= 0 || bh <= 0 do return
	li := clamp(d.active_layer, 0, len(d.layers) - 1)
	l := &d.layers[li]
	if l.is_group || stroke.target != &l.pix do return
	now := make([]Color, bw * bh, context.temp_allocator)
	before := make([]Color, bw * bh, context.temp_allocator)
	tiles_read_box(&l.pix, b, now, {})
	tiles_read_box(&stroke.orig, b, before, stroke.empty)
	// lay `now` over a cached result where the stroke changed something: `over` false clears those pixels instead
	patch :: proc(cp: ^Fx_Cache, b: Box, now, before: []Color, over: bool) {
		shown := make([]Color, len(now), context.temp_allocator)
		tiles_read_box(&cp.pix, b, shown, {})
		for i in 0 ..< len(now) do if now[i] != before[i] do shown[i] = over ? now[i] : {}
		tiles_write_box(&cp.pix, b, shown, {})
		cp.patched = true
	}
	if c, has := d.fx_cache[Fx_Key{l.uid, d.active_frame}]; has && c.ok && len(c.pix.t) > 0 {
		patch(&d.fx_cache[Fx_Key{l.uid, d.active_frame}], b, now, before, true)
	}
	for &o, oi in d.layers {
		if oi <= li || o.fx_n == 0 do continue
		c, has := d.fx_cache[Fx_Key{o.uid, d.active_frame}]
		if !has || !c.ok || !c.below || len(c.pix.t) == 0 do continue
		patch(&d.fx_cache[Fx_Key{o.uid, d.active_frame}], b, now, before, false)
	}
}

// Runs again, now, the effects of every layer of `d` that uses macro `name`: it was just changed in the node editor.
fx_refresh_macro :: proc(d: ^Doc, name: string) {
	for &l in d.layers {
		for &f in l.fx[:l.fx_n] {
			if strings.equal_fold(name_str(&f.name), name) {
				fx_refresh(d, l.uid)
				break
			}
		}
	}
}

// Runs layer `uid`'s effects again on every frame, now, whatever their trigger: the Refresh button.
fx_refresh :: proc(d: ^Doc, uid: int) {
	for k, &c in d.fx_cache {
		if k.uid == uid {
			c.stale = true
			c.refresh = true
		}
	}
}

// When layer `l`'s effects run: the most careful trigger among those switched on (On Demand, then After a Pause, then
// Every N Seconds, then On Paint), with the longest Seconds of those that have it. On Hotkey macros are skipped: they
// can't run on a layer, and layer_fx_run says so.
layer_fx_trigger :: proc(l: ^Layer) -> (t: Macro_Trigger, secs: f64) {
	rank :: proc(t: Macro_Trigger) -> int {
		switch t {
		case .Hotkey, .Paint:
			return 0
		case .Timer:
			return 1
		case .Pause:
			return 2
		case .Demand:
			return 3
		}
		return 0
	}
	t = .Paint
	for &f in l.fx[:l.fx_n] {
		if !f.on do continue
		ft, fs := macro_trigger(macro_find(name_str(&f.name)))
		if ft == .Hotkey do continue
		if rank(ft) > rank(t) {
			t, secs = ft, fs
		} else if ft == t {
			secs = max(secs, fs)
		}
	}
	return
}

// The layer's effects (which, switched on or not, in what order) and the settings of its own they read.
fx_settings_sig :: proc(l: ^Layer) -> u64 {
	h: u64 = 14695981039346656037
	mix :: proc(h: ^u64, v: u64) {
		h^ = (h^ ~ v) * 1099511628211
	}
	mix(&h, u64(l.blend))
	mix(&h, u64(l.opacity))
	mix(&h, l.pass_through ? 7 : 3)
	for &f in l.fx[:l.fx_n] {
		for b in f.name.b[:f.name.n] do mix(&h, u64(b))
		mix(&h, f.on ? 2 : 1)
	}
	return h
}

// May layer `l`'s effects run now, `c` being what they gave last (`has`: whether they gave anything)? A layer with no
// result yet, asked to Refresh, or whose effects or settings changed runs at once; otherwise its trigger decides.
// `force` (an export, which should show the latest) doesn't wait for a timer, but On Demand still waits for Refresh.
fx_due :: proc(l: ^Layer, c: Fx_Cache, has, force: bool) -> bool {
	if !has || !c.has_sig || c.refresh || c.paint_due || c.set_sig != fx_settings_sig(l) do return true
	// an export shows the effects' result, not the paint shown through it while painting
	if force && (c.patched || c.painted) do return true
	t, secs := layer_fx_trigger(l)
	switch t {
	case .Hotkey, .Paint:
		return true
	case .Pause:
		return force || gfx_time() - c.changed_at >= secs
	case .Timer:
		return force || gfx_time() - c.ran_at >= secs
	case .Demand:
		return false
	}
	return true
}

fx_cache_free :: proc(d: ^Doc) {
	for _, &c in d.fx_cache do tiles_destroy(&c.pix)
	delete(d.fx_cache)
	d.fx_cache = nil
}

// Has the layer an effect switched on?
layer_fx_on :: proc(l: ^Layer) -> bool {
	for f in l.fx[:l.fx_n] do if f.on do return true
	return false
}

// `layers` (frame `frame`'s) with their effects' results in place of their pixels (temp memory), or `layers` itself
// when none has a result. With `compute`, results out of date are worked out first (main thread only).
fx_apply :: proc(d: ^Doc, layers: []Layer, frame: int, compute: bool) -> []Layer {
	if d == nil || len(layers) == 0 do return layers
	out: []Layer
	for &l, i in layers {
		if l.fx_n == 0 || !layer_fx_on(&l) do continue
		if compute && fx_on_main() && !fx_sandbox && !macro_running {
			if li := layer_find_uid(d.layers[:], l.uid); li >= 0 {
				// as fx_update: only a result that something marked out of date is checked again (fx_compute copies
				// and hashes the whole layer, too much to do whenever a frame is drawn)
				prev, has := d.fx_cache[Fx_Key{l.uid, frame}]
				if (!has || prev.stale || prev.refresh) && fx_due(&d.layers[li], prev, has, false) do fx_compute(d, li, frame)
			}
		}
		c, has := d.fx_cache[Fx_Key{l.uid, frame}]
		if !has || !c.ok do continue
		if out == nil {
			out = make([]Layer, len(layers), context.temp_allocator)
			copy(out, layers)
		}
		out[i].pix = c.pix
		out[i].blend = c.blend
		out[i].opacity = c.opacity
		out[i].fx_shown = true
		out[i].has_mask = out[i].has_mask && !l.is_group
	}
	return out != nil ? out : layers
}

// For compositing the current frame: `layers` (part of d.layers) with the effects' results kept for it in place.
fx_layers :: proc(d: ^Doc, layers: []Layer) -> []Layer {
	if d == nil || len(d.fx_cache) == 0 || len(layers) == 0 do return layers
	base, end := uintptr(raw_data(d.layers)), uintptr(raw_data(d.layers)) + uintptr(len(d.layers) * size_of(Layer))
	if p := uintptr(raw_data(layers)); p < base || p >= end do return layers // a frame's copy: frame_layers did it
	return fx_apply(d, layers, d.active_frame, false)
}

// What layer `li`'s effects read on frame `f`: its pixels there, or for a group, its layers combined (temp memory).
fx_input :: proc(d: ^Doc, li, f: int) -> []Color {
	l := &d.layers[li]
	if l.is_group do return group_pixels(d, li, f)
	out := make([]Color, d.w * d.h, context.temp_allocator)
	if pix, _ := frame_tiles(d, l, f); pix != nil do tiles_to_buf(pix, d.w, d.h, out, {})
	return out
}

// Do layer `l`'s effects (those switched on) read the picture under it?
layer_fx_reads_below :: proc(l: ^Layer) -> bool {
	for &f in l.fx[:l.fx_n] do if f.on && macro_reads_below(macro_find(name_str(&f.name))) do return true
	return false
}

// The picture under layer `li` on frame `f`, for effects that adjust it (temp memory): the layers below it in its group
// (or below it at all, outside any group) combined, with their own effects.
fx_below_pixels :: proc(d: ^Doc, li, f: int) -> []Color {
	out := make([]Color, d.w * d.h, context.temp_allocator)
	p := layer_parent_index(d.layers[:], li)
	start := p >= 0 ? layer_span_start(d.layers[:], p) : 0
	end := layer_span_start(d.layers[:], li)
	if end <= start do return out
	run := d.layers[start:end]
	flat := frame_flat_id(d, f)
	if f == d.active_frame {
		composite_box(d, run, doc_box(d), out, flat) // their effects, as worked out for this frame
		return out
	}
	tmp := make([]Layer, len(run), context.temp_allocator)
	for &l, i in run {
		tmp[i] = l
		pix, mask := frame_tiles(d, &l, f)
		tmp[i].pix = pix != nil ? pix^ : Tiles{}
		tmp[i].mask = mask != nil ? mask^ : Tiles{}
	}
	composite_box(d, fx_apply(d, tmp, f, true), doc_box(d), out, flat)
	return out
}

@(private = "file")
fx_signature :: proc(l: ^Layer, input, below: []Color) -> u64 {
	h: u64 = 14695981039346656037
	mix :: proc(h: ^u64, v: u64) {
		h^ = (h^ ~ v) * 1099511628211
	}
	for p in input do mix(&h, u64(transmute(u32)p))
	for p in below do mix(&h, u64(transmute(u32)p))
	mix(&h, below != nil ? 5 : 9)
	mix(&h, u64(l.blend))
	mix(&h, u64(l.opacity))
	mix(&h, l.pass_through ? 7 : 3)
	mix(&h, u64(macro_lib_gen))
	for &f in l.fx[:l.fx_n] {
		for b in f.name.b[:f.name.n] do mix(&h, u64(b))
		mix(&h, f.on ? 2 : 1)
	}
	return h
}

// Makes layer `li`'s effects' result on frame `f` current. True if it ran them (or switched them off).
fx_compute :: proc(d: ^Doc, li, f: int) -> bool {
	l := &d.layers[li]
	key := Fx_Key{l.uid, f}
	if _, has := d.fx_cache[key]; !has do d.fx_cache[key] = Fx_Cache{stale = true}
	input := fx_input(d, li, f)
	reads := layer_fx_reads_below(l)
	below := reads ? fx_below_pixels(d, li, f) : nil // (this may run lower layers' effects, adding to the cache)
	sig := fx_signature(l, input, below)
	c := &d.fx_cache[key]
	c.stale = false
	c.paint_due = false
	c.below = reads
	// what the settings are now, before the early return: left behind, fx_due would ask for this every frame
	c.set_sig = fx_settings_sig(l)
	if c.has_sig && c.sig == sig && !c.refresh && !c.patched do return false // (patched: what shows isn't their result)
	c.patched = false
	c.has_sig, c.sig = true, sig
	c.refresh = false
	c.ran_at = gfx_time()
	if !layer_fx_on(l) {
		c.ok = false
		return true
	}
	pix, blend, op, ok, msg := layer_fx_run(d, l, input, below)
	c = &d.fx_cache[key]
	if ok {
		if len(c.pix.t) == 0 do c.pix = tiles_make(d.w, d.h)
		tiles_from_buf(&c.pix, d.w, d.h, pix, {})
		c.blend, c.opacity, c.ok = blend, op, true
		name_set(&c.err, "")
	} else {
		c.ok = false
		name_set(&c.err, msg)
		if f == d.active_frame do set_statusf("Layer effects of %s: %s", name_str(&l.name), msg)
	}
	return true
}

// Runs the effects of layer `src` (a layer or group of the painting) on `input`, its pixels. Returns the copy as they
// left it, w*h (temp memory). `below` is the picture under the layer, for Develop nodes on Layer pixels (nil if none
// reads it). If one of them ran, what shows is that picture as they changed it, wherever they changed it, and not the
// layer's own pixels: those only said where.
layer_fx_run :: proc(d: ^Doc, src: ^Layer, input: []Color, below: []Color = nil) -> (pix: []Color, blend: Blend, opacity: u8, ok: bool, msg: string) {
	if !fx_on_main() do return nil, {}, 0, false, "effects only run on the main thread"
	sb := doc_new(d.w, d.h, "effects")
	defer doc_destroy(sb)
	for &l in sb.layers do layer_destroy(&l)
	clear(&sb.layers)
	base := layer_make(name_str(&src.name), d.w, d.h)
	tiles_from_buf(&base.pix, d.w, d.h, input, {})
	base.blend, base.opacity = src.blend, src.opacity
	if src.is_group && src.pass_through do base.blend = .Normal
	base.uid = 1
	append(&sb.layers, base)
	sb.active_layer = 0
	saved := doc
	doc = sb
	fx_sandbox = true
	fx_below, fx_adj, fx_adj_cov = below, nil, nil
	defer fx_below, fx_adj, fx_adj_cov = nil, nil, nil
	for &f in src.fx[:src.fx_n] {
		if !f.on do continue
		m := macro_find(name_str(&f.name))
		if m == nil {
			msg = fmt.tprintf("there is no macro called %s", name_str(&f.name))
			break
		}
		if !macro_is_layer_effect(m) {
			msg = fmt.tprintf("%s runs On Hotkey, not on a layer: set its Start node's Trigger to a layer trigger", m.name)
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
	if fx_adj != nil {
		// the layer was a mask: what shows is the picture under it as adjusted, only where something changed it (so
		// soft or see-through pixels under it aren't doubled where nothing did)
		shown := make([]Color, d.w * d.h, context.temp_allocator)
		for c, i in fx_adj do if fx_adj_cov[i] > 0 do shown[i] = c
		tiles_from_buf(&b.pix, d.w, d.h, shown, {})
	}
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

fx_lib_seen := -1 // macro_lib_gen when the effects were last checked

// Works out the current frame's effects that are out of date. Called every frame; unless `force`, does nothing while
// the mouse is down or something is being edited, so painting shows the layer as it is and its effects follow when the
// stroke ends.
fx_update :: proc(d: ^Doc, force := false) {
	if d == nil || macro_running || fx_sandbox || !fx_on_main() do return
	if fx_lib_seen != macro_lib_gen {
		fx_lib_seen = macro_lib_gen
		fx_mark_stale(d)
	}
	// a layer with effects but no id: its result would be dropped below as "a layer that is gone", and worked out
	// again from scratch the next frame, every frame. Give it an id first.
	for &l in d.layers {
		if l.fx_n > 0 && l.uid == 0 {
			layers_give_ids(d)
			break
		}
	}
	// results of layers that are gone, have no effects any more, or of frames that are gone
	for k, &c in d.fx_cache {
		i := layer_find_uid(d.layers[:], k.uid)
		if i < 0 || d.layers[i].fx_n == 0 || k.frame >= len(d.frames) {
			tiles_destroy(&c.pix)
			delete_key(&d.fx_cache, k)
			fx_redraw(d)
			break // the map changed: the rest next frame
		}
	}
	if !force {
		busy := ui.down[0] || ui.down[1] || stroke.active || drag.active || text_edit.active || xform.active || (dialog.kind != .None && dialog.kind != .Layer_Fx && dialog.kind != .Layer_Props)
		if busy do return
	}
	// painting has stopped (the pen stayed up long enough): On Demand effects painted on run, once
	if gfx_time() - fx_paint_end >= FX_PAINT_SETTLE {
		for _, &c in d.fx_cache {
			if !c.painted do continue
			c.painted, c.paint_due, c.stale = false, true, true
		}
	}
	f := d.active_frame
	// what is in a group comes before it in the list, so a group's effects read its layers' results
	for &l, li in d.layers {
		if l.fx_n == 0 do continue
		c, has := d.fx_cache[Fx_Key{l.uid, f}]
		if has && !c.stale && !c.refresh do continue
		if !fx_due(&l, c, has, force) do continue // stays stale: checked again next frame
		if fx_compute(d, li, f) do fx_redraw(d)
	}
}

// The picture needs drawing again (without marking the effects out of date: that is what doc_dirty would do).
fx_redraw :: proc(d: ^Doc) {
	d.comp_dirty = box_union(d.comp_dirty, doc_box(d))
	d.thumb_dirty = true
	d.comp_lazy = false
	frame_cache_drop(d)
}

// ---------------------------------------------------------------------------
// A layer's mode: a blend mode, or a macro
// ---------------------------------------------------------------------------

LAYER_MODE_TIP :: "How the layer mixes with the layers below it, such as Multiply to darken or Screen to lighten. A macro (after the blend modes) runs on the layer as a live effect, as often as its Trigger says: its result is what shows, blended as the macro sets. The wheel steps through them."

// The macros that can be layer effects, by name (temp memory): those with a layer trigger.
fx_macros :: proc() -> []^Macro {
	out := make([dynamic]^Macro, context.temp_allocator)
	for m in macro_lib do if macro_is_layer_effect(m) do append(&out, m)
	return out[:]
}

// The choices of a layer's mode list (temp memory): Pass Through for a group, the blend modes, then the macros.
layer_mode_names :: proc(l: ^Layer) -> []string {
	out := make([dynamic]string, context.temp_allocator)
	if l.is_group do append(&out, "Pass Through")
	append(&out, ..blend_names_slice())
	for m in fx_macros() do append(&out, fmt.tprintf("Macro: %s", m.name))
	return out[:]
}

layer_mode_current :: proc(l: ^Layer) -> int {
	nb := len(Blend) + (l.is_group ? 1 : 0)
	if l.fx_n > 0 && l.fx[0].on {
		for m, i in fx_macros() do if strings.equal_fold(m.name, name_str(&l.fx[0].name)) do return nb + i
	}
	if l.is_group && l.pass_through do return 0
	return int(l.blend) + (l.is_group ? 1 : 0)
}

// Sets choice `i` of layer_mode_names: a blend mode (taking a macro off), or a macro as the layer's one effect.
layer_mode_set :: proc(l: ^Layer, i: int) {
	off := l.is_group ? 1 : 0
	nb := len(Blend) + off
	switch {
	case l.is_group && i == 0:
		l.pass_through = true
		l.fx_n = 0
		l.fx = {}
	case i < nb:
		l.blend = Blend(i - off)
		l.pass_through = false
		l.fx_n = 0
		l.fx = {}
	case i - nb < len(fx_macros()):
		l.fx = {}
		name_set(&l.fx[0].name, fx_macros()[i - nb].name)
		l.fx[0].on = true
		l.fx_n = 1
	}
}

// What a layer's mode list shows for it, and its row in the layer list: the macros it runs, else its blend mode.
layer_mode_text :: proc(l: ^Layer) -> string {
	if layer_fx_on(l) {
		sb := strings.builder_make(context.temp_allocator)
		for &f in l.fx[:l.fx_n] {
			if !f.on do continue
			if strings.builder_len(sb) > 0 do strings.write_string(&sb, " + ")
			strings.write_string(&sb, name_str(&f.name))
		}
		return strings.to_string(sb)
	}
	if l.is_group && l.pass_through do return "Pass Through"
	return BLEND_NAMES[l.blend]
}

// Adds a macro as an effect of the active layer. False if it has as many as it can hold.
layer_fx_add :: proc(d: ^Doc, name: string) -> bool {
	l := &d.layers[d.active_layer]
	if l.fx_n >= MAX_LAYER_FX do return false
	history_push(d)
	name_set(&l.fx[l.fx_n].name, name)
	l.fx[l.fx_n].on = true
	l.fx_n += 1
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

// Makes the active layer's effects part of its pixels, on every frame, and takes them off. A group becomes one layer
// (Merge Group) first. False if they can't run.
layer_fx_apply :: proc(d: ^Doc) -> bool {
	li := d.active_layer
	if d.layers[li].fx_n == 0 do return false
	if d.layers[li].is_group {
		fx_keep := d.layers[li].fx
		fx_n := d.layers[li].fx_n
		if !doc_merge_group(d) do return false
		li = d.active_layer
		d.layers[li].fx, d.layers[li].fx_n = fx_keep, fx_n
	}
	results := make([][]Color, len(d.frames), context.temp_allocator)
	blend: Blend
	op: u8
	for f in 0 ..< len(d.frames) {
		below := layer_fx_reads_below(&d.layers[li]) ? fx_below_pixels(d, li, f) : nil
		pix, b, o, ok, msg := layer_fx_run(d, &d.layers[li], fx_input(d, li, f), below)
		if !ok {
			set_statusf("The effects can't be applied: %s", msg)
			return false
		}
		results[f] = pix
		if f == d.active_frame do blend, op = b, o
	}
	history_push(d)
	l := &d.layers[li]
	layer_rasterize(d, l)
	for f in 0 ..< len(d.frames) {
		if f == d.active_frame || layer_spans(l) {
			tiles_from_buf(&l.pix, d.w, d.h, results[d.active_frame], {})
			continue
		}
		t := tiles_make(d.w, d.h)
		tiles_from_buf(&t, d.w, d.h, results[f], {})
		layer_cels_fit(l, len(d.frames))
		if l.cels[f] != nil do cel_release(l.cels[f])
		c := new(Cel)
		c.refs = 1
		c.pix = t
		l.cels[f] = c
	}
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
	{
		if l.fx_n == 0 {
			for line, i in tooltip_wrap("No effects yet. Add a macro below: it runs on this layer as often as its Trigger says, and the canvas shows the result.", c.w, text_w) {
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
			m := macro_find(name)
			missing := m == nil
			bx := c.x + c.w - 4 * 24
			text_clipped(Rect{c.x + 22, ry + 3, bx - 4 - c.x - 22, 12}, missing ? fmt.tprintf("%s (there is no macro called this)", name) : name, missing ? C_DANGER : (f.on ? C_TEXT : C_TEXT_DIM))
			if !missing {
				// its trigger, after the name; an On Hotkey macro can't run here
				tx := c.x + 22 + text_w(name) + 8
				layer_ok := macro_is_layer_effect(m)
				text_clipped(Rect{tx, ry + 3, bx - 4 - tx, 12}, layer_ok ? macro_trigger_text(m) : "On Hotkey: can't run on a layer", layer_ok ? C_TEXT_OFF : C_DANGER)
			}
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
		fxm := fx_macros()
		if len(fxm) == 0 {
			text_clipped(Rect{c.x, y + 3, c.w, 12}, "No macro is a layer effect yet: give one a layer Trigger on its Start node.", C_TEXT_DIM)
		} else if l.fx_n < MAX_LAYER_FX {
			@(static) names: [MACRO_MAX + 1]string
			names[0] = "Add an effect..."
			n := min(len(fxm), MACRO_MAX)
			for m, i in fxm[:n] do names[i + 1] = m.name
			if nv, ch := combo(Rect{c.x, y, 220, 14}, names[:n + 1], 0, {"Add an effect", "Pick a macro to run on this layer. These are the macros whose Start node has a layer Trigger (On Paint, After a Pause, Every N Seconds or On Demand); make one in Macros > Node Editor."}); ch && nv > 0 {
				layer_fx_add(d, fxm[nv - 1].name)
			}
		}
		y += 22
		if fc, has := d.fx_cache[Fx_Key{l.uid, d.active_frame}]; has && fc.err.n > 0 {
			text_clipped(Rect{c.x, y + 3, c.w, 12}, fmt.tprintf("Not shown: %s", name_str(&fc.err)), C_DANGER)
		} else if layer_fx_on(l) {
			t, secs := layer_fx_trigger(l)
			// effects run as one stack: with several, the most careful trigger among them
			text_clipped(Rect{c.x, y + 3, c.w, 12}, fmt.tprintf(l.fx_n > 1 ? "Updates (all together): %s" : "Updates: %s", macro_trigger_words(t, secs)), C_TEXT_DIM)
		}
		if button(Rect{c.x, c.y + c.h - 18, 110, 18}, "Apply Effects", {"", cmd_help(.Layer_Fx_Apply)}, l.fx_n > 0) {
			dialog_close()
			run_cmd(.Layer_Fx_Apply)
			return
		}
		if button(Rect{c.x + 116, c.y + c.h - 18, 80, 18}, "Refresh", {"Refresh", "Run this layer's effects again now, whatever their trigger (the circling arrow by the layer's fx does the same). Effects On Demand update once you stop painting on the layer, and when you click this; After a Pause and Every N Seconds catch up without waiting."}, layer_fx_on(l)) {
			fx_refresh(d, l.uid)
		}
	}
	ok, _ := dialog_buttons(c, "Close this window (Enter).", "Close", "")
	if ok || IsKeyPressed(.ESCAPE) do dialog_close()
}

// A painting brought the macro of one of its effects: the library gets it if it hasn't one by that name.
fx_macro_arrived :: proc(name, text: string) {
	// (not from the file browser's thumbnail thread: the library belongs to the main thread)
	if text == "" || !fx_on_main() || macro_find(name) != nil do return
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
