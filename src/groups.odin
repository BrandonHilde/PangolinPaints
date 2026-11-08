package pangolin

import "core:fmt"

// Layer groups. A group is a layer with `is_group` set and no pixels of its own. The layer list stays flat, bottom to
// top, in tree order: everything in a group sits directly below it, so a group and its contents are one run of the
// list that ends at the group. Each layer names its group by uid (`parent`). doc_layers_normalize puts the list back in
// tree order after anything that changes the structure, so the commands below only set parents and places.
//
// Compositing (composite_box): a pass-through group's layers blend straight into what is below, with the group's
// visibility and opacity applied to each; any other group combines its layers first, then blends the result by its own
// mode and opacity. A group can't be painted on, and has no mask.

layers_have_groups :: proc(layers: []Layer) -> bool {
	for &l in layers do if l.is_group do return true
	return false
}

layer_find_uid :: proc(layers: []Layer, uid: int) -> int {
	if uid == 0 do return -1
	for &l, i in layers do if l.uid == uid do return i
	return -1
}

layers_next_uid :: proc(layers: []Layer) -> int {
	m := 0
	for &l in layers do m = max(m, l.uid)
	return m + 1
}

// The index of the group layer `i` is in, or -1.
layer_parent_index :: proc(layers: []Layer, i: int) -> int {
	p := layer_find_uid(layers, layers[i].parent)
	return p >= 0 && layers[p].is_group ? p : -1
}

// How many groups layer `i` is inside.
layer_depth :: proc(layers: []Layer, i: int) -> int {
	n, at := 0, i
	for _ in 0 ..< len(layers) {
		at = layer_parent_index(layers, at)
		if at < 0 do break
		n += 1
	}
	return n
}

// Is layer `i` inside group `g`, at any depth?
layer_in_group :: proc(layers: []Layer, i, g: int) -> bool {
	at := i
	for _ in 0 ..< len(layers) {
		at = layer_parent_index(layers, at)
		if at < 0 do return false
		if at == g do return true
	}
	return false
}

// The bottom index of the run made by layer `i` and everything in it (just `i` for a layer that isn't a group).
layer_span_start :: proc(layers: []Layer, i: int) -> int {
	s := i
	if !layers[i].is_group do return s
	for s > 0 && layer_in_group(layers, s - 1, i) do s -= 1
	return s
}

// Is layer `i` hidden, by itself or by a group it is in?
layer_hidden :: proc(layers: []Layer, i: int) -> bool {
	if !layers[i].visible do return true
	at := i
	for _ in 0 ..< len(layers) {
		at = layer_parent_index(layers, at)
		if at < 0 do return false
		if !layers[at].visible do return true
	}
	return false
}

// Puts the list back in tree order: each group's contents right below it, layers in the same group kept in the order
// of `keys` (or of their places in the list). Gives layers without one a uid, and sends a layer whose group is gone, or
// that would be inside itself, to the top level. The active layer stays the active one.
doc_layers_normalize :: proc(d: ^Doc, keys: []f64 = nil) {
	n := len(d.layers)
	if n == 0 do return
	active_i := clamp(d.active_layer, 0, n - 1)
	// uids: one each, never shared (a copy may arrive with its original's)
	next := layers_next_uid(d.layers[:])
	seen := make(map[int]bool, n, context.temp_allocator)
	for &l in d.layers {
		if l.uid == 0 || seen[l.uid] {
			l.uid = next
			next += 1
		}
		seen[l.uid] = true
	}
	active_uid := d.layers[active_i].uid
	for &l in d.layers {
		if l.parent == 0 do continue
		p := layer_find_uid(d.layers[:], l.parent)
		if p < 0 || !d.layers[p].is_group || d.layers[p].uid == l.uid do l.parent = 0
	}
	// a chain of groups that comes back round: the layer leaves it
	for i in 0 ..< n {
		at := i
		for step in 0 ..= n {
			at = layer_parent_index(d.layers[:], at)
			if at < 0 do break
			if at == i || step == n {
				d.layers[i].parent = 0
				break
			}
		}
	}
	key := make([]f64, n, context.temp_allocator)
	for i in 0 ..< n do key[i] = keys != nil && i < len(keys) ? keys[i] : f64(i)
	order := make([dynamic]int, 0, n, context.temp_allocator)
	Ctx :: struct {
		d:     ^Doc,
		key:   []f64,
		order: ^[dynamic]int,
	}
	emit :: proc(c: ^Ctx, parent: int) {
		kids := make([dynamic]int, context.temp_allocator)
		for &l, i in c.d.layers do if l.parent == parent do append(&kids, i)
		key := c.key
		// by key; equal keys keep their order in the list (an insertion sort: these lists are short)
		for i in 1 ..< len(kids) {
			for j := i; j > 0 && key[kids[j - 1]] > key[kids[j]]; j -= 1 do kids[j - 1], kids[j] = kids[j], kids[j - 1]
		}
		for k in kids {
			if c.d.layers[k].is_group do emit(c, c.d.layers[k].uid)
			append(c.order, k)
		}
	}
	c := Ctx{d, key, &order}
	emit(&c, 0)
	if len(order) != n do return // can't happen after the checks above; leave the list alone rather than lose layers
	tmp := make([]Layer, n, context.temp_allocator)
	for k, i in order do tmp[i] = d.layers[k]
	copy(d.layers[:], tmp)
	d.active_layer = max(layer_find_uid(d.layers[:], active_uid), 0)
}

// Puts `l` into the list just above layer `at`, in the same group as it (at < 0: at the bottom of the top level), and
// makes it the active layer. Returns its index.
layer_insert_above :: proc(d: ^Doc, l: Layer, at: int) -> int {
	nl := l
	nl.parent = at >= 0 && at < len(d.layers) ? d.layers[at].parent : 0
	nl.uid = layers_next_uid(d.layers[:])
	pos := clamp(at + 1, 0, len(d.layers))
	inject_at(&d.layers, pos, nl)
	d.active_layer = pos
	doc_layers_normalize(d)
	return d.active_layer
}

@(private = "file")
list_keys :: proc(d: ^Doc) -> []f64 {
	keys := make([]f64, len(d.layers), context.temp_allocator)
	for i in 0 ..< len(keys) do keys[i] = f64(i)
	return keys
}

// A new, empty group above the active layer, in the same group as it.
doc_group_new :: proc(d: ^Doc) {
	history_push(d)
	g := layer_make(fmt.tprintf("Group %d", group_count(d) + 1), d.w, d.h)
	g.is_group, g.pass_through = true, true
	layer_insert_above(d, g, d.active_layer)
	d.edit_mask = false
	doc_touch_all(d)
}

group_count :: proc(d: ^Doc) -> int {
	n := 0
	for &l in d.layers do if l.is_group do n += 1
	return n
}

// Puts the active layer (and all that is in it, for a group) into a new group, which becomes the active layer.
doc_group_wrap :: proc(d: ^Doc) {
	history_push(d)
	i := d.active_layer
	g := layer_make(fmt.tprintf("Group %d", group_count(d) + 1), d.w, d.h)
	g.is_group, g.pass_through = true, true
	g.uid = layers_next_uid(d.layers[:])
	g.parent = d.layers[i].parent
	d.layers[i].parent = g.uid
	inject_at(&d.layers, i + 1, g)
	d.active_layer = i + 1
	doc_layers_normalize(d)
	d.edit_mask = false
	doc_touch_all(d)
}

// Takes the active group apart: what was in it stays where it is, in the group around it. False if it isn't a group.
doc_ungroup :: proc(d: ^Doc) -> bool {
	g := d.active_layer
	if !d.layers[g].is_group do return false
	history_push(d)
	uid, up := d.layers[g].uid, d.layers[g].parent
	for &l in d.layers do if l.parent == uid do l.parent = up
	layer_destroy(&d.layers[g])
	ordered_remove(&d.layers, g)
	d.active_layer = clamp(g - 1, 0, len(d.layers) - 1)
	doc_layers_normalize(d)
	d.edit_mask = false
	doc_touch_all(d)
	return true
}

// Moves the active layer (with what is in it) past the next layer up or down in its group. At the top or bottom of a
// group it moves out of it, above or below the group. False if it can't go further.
doc_move_layer :: proc(d: ^Doc, dir: int) -> bool {
	i := d.active_layer
	n := len(d.layers)
	l := &d.layers[i]
	keys := list_keys(d)
	if dir > 0 {
		found := false
		for j in i + 1 ..< n {
			if d.layers[j].uid == l.parent {
				// the top of its group: out, just above the group
				history_push(d)
				l.parent = d.layers[j].parent
				keys[i] = f64(j) + 0.5
				found = true
				break
			}
			if d.layers[j].parent == l.parent {
				history_push(d)
				keys[i] = f64(j) + 0.5
				found = true
				break
			}
		}
		if !found do return false
	} else {
		s := layer_span_start(d.layers[:], i)
		switch {
		case s > 0 && d.layers[s - 1].parent == l.parent:
			history_push(d)
			keys[i] = f64(layer_span_start(d.layers[:], s - 1)) - 0.5
		case l.parent != 0:
			// the bottom of its group: out, just below the group
			g := layer_parent_index(d.layers[:], i)
			if g < 0 do return false
			history_push(d)
			l.parent = d.layers[g].parent
			keys[i] = f64(layer_span_start(d.layers[:], g)) - 0.5
		case:
			return false
		}
	}
	doc_layers_normalize(d, keys)
	doc_touch_all(d)
	return true
}

Layer_Drop :: enum {
	Above,
	Below,
	Into, // to the top of a group
}

// Moves layer `src` (with what is in it) above or below layer `target`, in target's group, or into group `target`.
// False if that is no move, or would put a group inside itself.
doc_move_to :: proc(d: ^Doc, src, target: int, drop: Layer_Drop) -> bool {
	n := len(d.layers)
	if src < 0 || src >= n || target < 0 || target >= n do return false
	if src == target do return false
	if d.layers[src].is_group && layer_in_group(d.layers[:], target, src) do return false
	if drop == .Into && !d.layers[target].is_group do return false
	history_push(d)
	keys := list_keys(d)
	l := &d.layers[src]
	switch drop {
	case .Above:
		l.parent = d.layers[target].parent
		keys[src] = f64(target) + 0.5
	case .Below:
		l.parent = d.layers[target].parent
		keys[src] = f64(layer_span_start(d.layers[:], target)) - 0.5
	case .Into:
		l.parent = d.layers[target].uid
		keys[src] = f64(target) // above everything already in it
	}
	d.active_layer = src
	doc_layers_normalize(d, keys)
	doc_touch_all(d)
	return true
}

// The layer the active one would merge into: the next layer down in its group, if that is not a group. Else -1.
layer_merge_target :: proc(d: ^Doc) -> int {
	i := d.active_layer
	if d.layers[i].is_group do return -1
	b := i - 1
	if b < 0 || d.layers[b].parent != d.layers[i].parent || d.layers[b].is_group do return -1
	return b
}

// Removes layers [s, e] (a group with what is in it), keeping the list valid. False if no layer would be left.
layers_remove_run :: proc(d: ^Doc, s, e: int) -> bool {
	if e - s + 1 >= len(d.layers) do return false
	for k in s ..= e do layer_destroy(&d.layers[k])
	remove_range(&d.layers, s, e + 1)
	d.active_layer = clamp(s, 0, len(d.layers) - 1)
	doc_layers_normalize(d)
	return true
}

// Copies the active layer, with everything in it for a group, just above it. The copy is the active layer.
doc_dup_run :: proc(d: ^Doc) {
	g := d.active_layer
	s := layer_span_start(d.layers[:], g)
	next := layers_next_uid(d.layers[:])
	remap := make(map[int]int, g - s + 1, context.temp_allocator)
	for k in s ..= g {
		remap[d.layers[k].uid] = next
		next += 1
	}
	copies := make([dynamic]Layer, context.temp_allocator)
	for k in s ..= g {
		c := layer_share(&d.layers[k])
		c.uid = remap[d.layers[k].uid]
		if p, ok := remap[c.parent]; ok do c.parent = p
		if k == g do name_set(&c.name, fmt.tprintf("%s copy", name_str(&d.layers[g].name)))
		append(&copies, c)
	}
	inject_at(&d.layers, g + 1, ..copies[:])
	d.active_layer = g + 1 + (g - s)
	doc_layers_normalize(d)
}

// Group `g` as one picture on frame `f`: what is in it, combined, without the group's own opacity and mode (temp
// memory unless `allocator` says otherwise).
group_pixels :: proc(d: ^Doc, g, f: int, allocator := context.temp_allocator) -> []Color {
	out := make([]Color, d.w * d.h, allocator)
	s := layer_span_start(d.layers[:], g)
	if s == g do return out
	run := d.layers[s:g]
	flat := frame_flat_id(d, f)
	if f == d.active_frame {
		composite_box(d, run, doc_box(d), out, flat)
		return out
	}
	tmp := make([]Layer, len(run), context.temp_allocator)
	for &l, i in run {
		tmp[i] = l
		pix, mask := frame_tiles(d, &l, f)
		tmp[i].pix = pix != nil ? pix^ : Tiles{}
		tmp[i].mask = mask != nil ? mask^ : Tiles{}
	}
	composite_box(d, tmp, doc_box(d), out, flat)
	return out
}

// Turns the active group into one layer showing what it showed, on every frame. False if it isn't a group.
doc_merge_group :: proc(d: ^Doc) -> bool {
	g := d.active_layer
	if !d.layers[g].is_group do return false
	history_push(d)
	s := layer_span_start(d.layers[:], g)
	grp := &d.layers[g]
	nl := layer_make(name_str(&grp.name), d.w, d.h)
	nl.visible, nl.locked, nl.opacity = grp.visible, grp.locked, grp.opacity
	nl.blend = grp.pass_through ? .Normal : grp.blend
	nl.parent = grp.parent
	layer_cels_fit(&nl, len(d.frames))
	for f in 0 ..< len(d.frames) {
		buf := group_pixels(d, g, f)
		if f == d.active_frame {
			tiles_from_buf(&nl.pix, d.w, d.h, buf, {})
			continue
		}
		t := tiles_make(d.w, d.h)
		tiles_from_buf(&t, d.w, d.h, buf, {})
		if tiles_count(&t) == 0 {
			tiles_destroy(&t)
			continue
		}
		c := new(Cel)
		c.refs = 1
		c.pix = t
		nl.cels[f] = c
	}
	nl.uid = layers_next_uid(d.layers[:])
	for k in s ..= g do layer_destroy(&d.layers[k])
	remove_range(&d.layers, s, g + 1)
	inject_at(&d.layers, s, nl)
	d.active_layer = s
	doc_layers_normalize(d)
	d.edit_mask = false
	doc_touch_all(d)
	return true
}
