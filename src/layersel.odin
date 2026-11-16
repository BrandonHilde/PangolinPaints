package pangolin

import "core:fmt"
import "core:slice"
import "core:strings"

// ---------------------------------------------------------------------------
// Several layers selected at once: Ctrl-click and Shift-click in the layer list, Select All Layers, or a macro's Pick
// Layer with Add to Selection. Group, Merge, Duplicate and Delete then work on all of them, and so do a macro's
// effects, layer settings and Export.
//
// The document keeps the selected layers' uids in `layer_sel`. The active layer is always one of them: when anything
// else makes another layer active (a click, a new layer, undo), the selection is that layer alone again.
// ---------------------------------------------------------------------------

// Whether more than the active layer is selected.
layer_sel_multi :: proc(d: ^Doc) -> bool {
	return len(layers_selected(d)) > 1
}

// The selected layers' indices, bottom to top (temp memory). Never empty while there are layers.
layers_selected :: proc(d: ^Doc) -> []int {
	out := make([dynamic]int, 0, max(len(d.layer_sel), 1), context.temp_allocator)
	if len(d.layers) == 0 do return out[:]
	a := clamp(d.active_layer, 0, len(d.layers) - 1)
	active_in := false
	for uid in d.layer_sel do if uid == d.layers[a].uid do active_in = true
	if active_in {
		for &l, i in d.layers {
			for uid in d.layer_sel do if uid == l.uid {
				append(&out, i)
				break
			}
		}
	}
	if len(out) == 0 {
		clear(&d.layer_sel) // the active layer changed: the old selection is gone
		append(&out, a)
	}
	return out[:]
}

layer_is_selected :: proc(d: ^Doc, i: int) -> bool {
	for k in layers_selected(d) do if k == i do return true
	return false
}

// The selected layers that aren't inside another selected group, bottom to top: what is grouped, merged, copied or
// deleted (a group takes what is in it along).
layers_selected_roots :: proc(d: ^Doc) -> []int {
	sel := layers_selected(d)
	out := make([dynamic]int, 0, len(sel), context.temp_allocator)
	for i in sel {
		inside := false
		for g in sel do if g != i && d.layers[g].is_group && layer_in_group(d.layers[:], i, g) do inside = true
		if !inside do append(&out, i)
	}
	return out[:]
}

// Only the active layer is selected.
layer_sel_clear :: proc(d: ^Doc) {
	clear(&d.layer_sel)
}

@(private = "file")
layer_sel_set :: proc(d: ^Doc, idx: []int) {
	clear(&d.layer_sel)
	if len(idx) < 2 do return
	for i in idx do append(&d.layer_sel, d.layers[i].uid)
}

// Adds layer `i` to the selection and makes it the active layer.
layer_sel_add :: proc(d: ^Doc, i: int) {
	if i < 0 || i >= len(d.layers) do return
	cur := slice.clone_to_dynamic(layers_selected(d), context.temp_allocator)
	if !slice.contains(cur[:], i) do append(&cur, i)
	d.active_layer = i
	d.edit_mask = false
	layer_sel_set(d, cur[:])
}

// Ctrl-click: adds layer `i`, or takes it out if it was in (another selected layer becomes the active one then).
layer_sel_toggle :: proc(d: ^Doc, i: int) {
	cur := slice.clone_to_dynamic(layers_selected(d), context.temp_allocator)
	if k, found := slice.linear_search(cur[:], i); found {
		if len(cur) == 1 do return // the active layer stays selected
		ordered_remove(&cur, k)
		if d.active_layer == i do d.active_layer = cur[len(cur) - 1]
	} else {
		append(&cur, i)
		d.active_layer = i
	}
	d.edit_mask = false
	layer_sel_set(d, cur[:])
}

// Shift-click: the rows of the list from the active layer's to row `to`, which becomes the active layer.
layer_sel_range :: proc(d: ^Doc, rows: []int, to: int) {
	from_row, to_row := -1, -1
	for li, r in rows {
		if li == d.active_layer do from_row = r
		if li == to do to_row = r
	}
	if from_row < 0 || to_row < 0 {
		d.active_layer = to
		layer_sel_clear(d)
		return
	}
	idx := make([dynamic]int, context.temp_allocator)
	for r in min(from_row, to_row) ..= max(from_row, to_row) do append(&idx, rows[r])
	d.active_layer = to
	d.edit_mask = false
	layer_sel_set(d, idx[:])
}

// Every layer.
layer_sel_all :: proc(d: ^Doc) {
	idx := make([dynamic]int, context.temp_allocator)
	for _, i in d.layers do append(&idx, i)
	layer_sel_set(d, idx[:])
}

// Selects layers by their uids after the list changed (temp list of uids; ones that are gone are left out).
layer_sel_uids :: proc(d: ^Doc, uids: []int, active_uid: int) {
	idx := make([dynamic]int, context.temp_allocator)
	for uid in uids do if i := layer_find_uid(d.layers[:], uid); i >= 0 do append(&idx, i)
	if a := layer_find_uid(d.layers[:], active_uid); a >= 0 do d.active_layer = a
	layer_sel_set(d, idx[:])
}

// ---------------------------------------------------------------------------
// What the layer commands do with several layers
// ---------------------------------------------------------------------------

// Puts the selected layers (each group with what is in it) into a new group, where the top one of them was, keeping
// their order. The group becomes the active layer.
doc_group_selected :: proc(d: ^Doc, push := true) {
	roots := layers_selected_roots(d)
	if len(roots) < 2 {
		doc_group_wrap(d, push)
		return
	}
	if push do history_push(d)
	top := roots[len(roots) - 1]
	g := layer_make(fmt.tprintf("Group %d", group_count(d) + 1), d.w, d.h)
	g.is_group, g.pass_through = true, true
	g.uid = layers_next_uid(d.layers[:])
	g.parent = d.layers[top].parent
	keys := make([dynamic]f64, 0, len(d.layers) + 1, context.temp_allocator)
	for i in 0 ..< len(d.layers) do append(&keys, f64(i))
	for r in roots do d.layers[r].parent = g.uid
	append(&d.layers, g)
	append(&keys, f64(top) + 0.5) // among the top layer's old neighbours, where it was
	d.active_layer = len(d.layers) - 1
	doc_layers_normalize(d, keys[:])
	layer_sel_clear(d)
	d.edit_mask = false
	doc_touch_all(d)
}

// Turns the selected layers into one layer showing what they showed together, on every frame, where the top one of
// them was and with its name. False if fewer than two are selected.
doc_merge_selected :: proc(d: ^Doc) -> bool {
	roots := layers_selected_roots(d)
	if len(roots) < 2 do return false
	name := strings.clone(name_str(&d.layers[roots[len(roots) - 1]].name), context.temp_allocator)
	history_push(d)
	doc_group_selected(d, false)
	name_set(&d.layers[d.active_layer].name, name)
	doc_merge_group(d, false)
	layer_sel_clear(d)
	return true
}

// Removes the selected layers. False if no layer would be left.
doc_delete_selected :: proc(d: ^Doc) -> bool {
	roots := layers_selected_roots(d)
	n := 0
	for r in roots do n += r - layer_span_start(d.layers[:], r) + 1
	if n >= len(d.layers) do return false
	history_push(d)
	#reverse for r in roots {
		s := layer_span_start(d.layers[:], r)
		for k in s ..= r do layer_destroy(&d.layers[k])
		remove_range(&d.layers, s, r + 1)
	}
	d.active_layer = clamp(roots[0], 0, len(d.layers) - 1)
	doc_layers_normalize(d)
	layer_sel_clear(d)
	d.edit_mask = false
	doc_touch_all(d)
	return true
}

// Copies each selected layer just above itself. The copies are selected afterwards.
doc_dup_selected :: proc(d: ^Doc) {
	roots := layers_selected_roots(d)
	uids := make([dynamic]int, context.temp_allocator)
	for r in roots do append(&uids, d.layers[r].uid)
	history_push(d)
	copies := make([dynamic]int, context.temp_allocator)
	for uid in uids {
		i := layer_find_uid(d.layers[:], uid)
		if i < 0 do continue
		d.active_layer = i
		doc_dup_run(d)
		append(&copies, d.layers[d.active_layer].uid)
	}
	if len(copies) > 0 do layer_sel_uids(d, copies[:], copies[len(copies) - 1])
	d.edit_mask = false
	doc_touch_all(d)
}

// What the selected layers show together on the current frame, as the canvas shows them (allocated).
selected_layers_pixels :: proc(d: ^Doc) -> []Color {
	out := make([]Color, d.w * d.h)
	run := make([dynamic]Layer, context.temp_allocator)
	for r in layers_selected_roots(d) {
		for k in layer_span_start(d.layers[:], r) ..= r do append(&run, d.layers[k])
	}
	composite_box(d, run[:], doc_box(d), out, frame_flat_id(d, d.active_frame))
	return out
}
