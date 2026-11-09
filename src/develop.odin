package pangolin

import "core:math"
import "core:strings"

// Develop nodes: photo-style adjustments made for live layer effects, so editing stays non-destructive (the layer keeps
// its pixels; the effect shows the result). They are the Develop category of the node editor: Exposure / Contrast,
// Tone Curve and HSL Color. Each ends with the same settings, which say where it works (Apply):
//
//   - Everywhere: the whole layer. A selection made by an earlier node (Select Ellipse, then Feather) still limits it,
//     as it limits every adjustment, which makes a radial or graduated filter.
//   - Curve: by tone. The curve gives, for each brightness of the layer (dark at the left), how strongly the node works
//     there (top: fully, bottom: not at all), so one node brightens only the shadows, another cools only the highlights.
//   - Layer pixels: the layer the effect is on says where, as a mask you paint. The node changes the picture *under*
//     the layer, as much as the layer is opaque there, and the layer's own colors don't show. Give an empty layer above
//     a photo a Develop effect set to Layer pixels and paint on it where the change should go: a soft brush for a soft
//     edge, a low opacity for a little of it. The layer's opacity fades the whole change, and a Blur before the node
//     softens the painted edge.
//
// Amount fades the node, Invert swaps where it works and where it doesn't, and Show mask paints where it works red
// instead of changing it, so a curve or a painted mask can be checked on the canvas.

DEV_APPLY := [3]string{"Everywhere", "Curve", "Layer pixels"}
DEV_APPLY_EVERYWHERE :: 0
DEV_APPLY_CURVE :: 1
DEV_APPLY_LAYER :: 2
DEV_CHANNELS := [5]string{"RGB", "Luminosity", "Red", "Green", "Blue"}
DEV_COLORS := [9]string{"All", "Reds", "Oranges", "Yellows", "Greens", "Aquas", "Blues", "Purples", "Magentas"}
DEV_HUES := [8]f32{0, 30, 60, 120, 180, 225, 270, 315} // the middle of each color range, in degrees
DEV_MASK_COLOR :: Color{255, 40, 40, 255}
DEV_MASK_SHOW :: 0.6 // how strongly Show mask paints red where the node works fully
DEV_WHERE_DEFAULT :: "0,255 80,240 170,20 255,0" // the shadows

// The picture under the layer whose effects are running, when one of them reads it (Layer pixels); nil otherwise.
fx_below: []Color
// That picture as the Layer pixels nodes have left it (nil until one runs), and how much they changed each pixel.
fx_adj: []Color
fx_adj_cov: []u8

APPLY_HELP :: "Where the node works. Everywhere: the whole layer. Curve: by tone, as the curve below says. Layer pixels: the layer this effect is on becomes a mask you paint: the node changes the picture under the layer wherever you paint on it (more where the paint is more opaque), and the paint itself doesn't show. A selection made by an earlier node limits it too."
WHERE_HELP :: "How strongly the node works on each tone. Tones go along the bottom, dark at the left; at the top of the graph the node works fully, at the bottom not at all. The filled part shows it. Drag a point to move it, click to add one, right-click to remove one."

// The settings every Develop node ends with: where it works.
@(private = "file")
dev_settings :: proc(own: ..Macro_Setting) -> []Macro_Setting {
	s := make([dynamic]Macro_Setting)
	append(&s, ..own)
	append(&s,
		Macro_Setting{key = "apply", name = "Apply", type = .Choice, choices = DEV_APPLY[:], help = APPLY_HELP},
		Macro_Setting{key = "where", name = "Strength by tone", type = .Curve, mask = true, def = {text = DEV_WHERE_DEFAULT}, only = "apply=Curve", help = WHERE_HELP},
		Macro_Setting{key = "invert", name = "Invert", type = .Bool, only = "apply=Curve|Layer pixels", help = "Work where the curve or the paint says not to, and leave alone where it says to."},
		Macro_Setting{key = "amount", name = "Amount", type = .Number, lo = 0, hi = 100, def = {num = 100}, suffix = "%", help = "How much of the change shows. 100% is all of it, 50% half way."},
		Macro_Setting{key = "show_mask", name = "Show mask", type = .Bool, no_wire = true, help = "Paint where this node works red on the canvas, instead of changing it, to check what the curve or the painted pixels pick. Turn it off again when it looks right."},
	)
	return s[:]
}

// The Develop nodes, for the catalogue.
dev_defs :: proc() -> []Macro_Def {
	out := make([dynamic]Macro_Def)
	append(&out, Macro_Def{id = "dev.Exposure", name = "Exposure / Contrast", category = "Develop", help = "Brighten or darken like a longer or shorter camera exposure, push the tones apart or together, and recover the highlights or open up the shadows.", settings = dev_settings(
		Macro_Setting{key = "exposure", name = "Exposure", type = .Number, lo = -5, hi = 5, step = 0.05, suffix = " stops", help = "Each stop up doubles the light, each stop down halves it, as a camera would."},
		Macro_Setting{key = "contrast", name = "Contrast", type = .Number, lo = -100, hi = 100, help = "Above 0, darks get darker and lights lighter, along a soft S that keeps black and white. Below 0, every tone moves toward mid gray."},
		Macro_Setting{key = "highlights", name = "Highlights", type = .Number, lo = -100, hi = 100, help = "Darken (below 0) or brighten (above 0) the light tones, leaving the darks alone. Below 0 brings back detail in a bright sky."},
		Macro_Setting{key = "shadows", name = "Shadows", type = .Number, lo = -100, hi = 100, help = "Brighten (above 0) or darken (below 0) the dark tones, leaving the lights alone. Above 0 opens up a face in shade."},
	)})
	append(&out, Macro_Def{id = "dev.Tone_Curve", name = "Tone Curve", category = "Develop", help = "Remap the tones with a curve: lift it to brighten, lower it to darken, an S shape for more contrast. One channel, or brightness only.", settings = dev_settings(
		Macro_Setting{key = "channel", name = "Channel", type = .Choice, choices = DEV_CHANNELS[:], help = "Which tones the curve changes. RGB: all three color channels alike. Luminosity: brightness only, so colors keep their saturation. Red, Green or Blue: that channel alone, to shift the color of the shadows or the highlights."},
		Macro_Setting{key = "curve", name = "Curve", type = .Curve, def = {text = MACRO_CURVE_DEFAULT}, help = MACRO_CURVE_HELP + " A straight diagonal changes nothing."},
	)})
	append(&out, Macro_Def{id = "dev.HSL", name = "HSL Color", category = "Develop", help = "Change one range of colors (the blues of a sky, the greens of grass) or all of them: shift their hue, make them stronger or weaker, lighter or darker. Grays are left alone in a color range.", settings = dev_settings(
		Macro_Setting{key = "colors", name = "Colors", type = .Choice, choices = DEV_COLORS[:], help = "The colors this node changes. A range fades out toward its neighbours, so the change has no hard edge. Add one HSL node per range."},
		Macro_Setting{key = "hue", name = "Hue", type = .Number, lo = -180, hi = 180, suffix = " deg", help = "Turn these colors around the color wheel, in degrees: a green sky by moving blue toward aqua, warmer skin by moving orange toward red."},
		Macro_Setting{key = "saturation", name = "Saturation", type = .Number, lo = -100, hi = 100, help = "Make these colors stronger (above 0) or closer to gray (-100 removes them)."},
		Macro_Setting{key = "luminance", name = "Luminance", type = .Number, lo = -100, hi = 100, help = "Make these colors lighter (above 0) or darker (below 0)."},
	)})
	return out[:]
}

// Does any Develop node of `m` work on the picture under its layer (Apply set to Layer pixels, or wired)?
macro_reads_below :: proc(m: ^Macro) -> bool {
	if m == nil do return false
	for &n in m.nodes {
		if !strings.has_prefix(n.kind, "dev.") do continue
		def := macro_def_find(n.kind)
		if def == nil do continue
		if macro_wire_from(m, n.id, "apply") != 0 do return true
		vals := macro_node_own_values(&n, def)
		for s, i in def.settings do if s.key == "apply" && int(vals[i].num) == DEV_APPLY_LAYER do return true
	}
	return false
}

@(private = "file")
dev_arg :: proc(def: ^Macro_Def, args: []Macro_Value, key: string) -> Macro_Value {
	for s, i in def.settings do if s.key == key do return args[i]
	return {}
}

// Runs a Develop node.
dev_exec :: proc(def: ^Macro_Def, args: []Macro_Value) -> (ok: bool, msg: string) {
	d := doc
	apply := int(dev_arg(def, args, "apply").num)
	amount := f32(clamp(dev_arg(def, args, "amount").num, 0, 100) / 100)
	invert := dev_arg(def, args, "invert").num != 0
	show := dev_arg(def, args, "show_mask").num != 0
	n := d.w * d.h

	if apply == DEV_APPLY_LAYER {
		if !fx_sandbox || fx_below == nil {
			return false, "Layer pixels works in a layer effect: add the macro to a layer above the picture (Layer > Layer Effects), then paint on that layer where the change should go"
		}
		// the layer's own pixels, as earlier nodes left them, say where
		l := &d.layers[d.active_layer]
		paint := make([]Color, n, context.temp_allocator)
		if !l.is_group do tiles_to_buf(&l.pix, d.w, d.h, paint, {})
		if fx_adj == nil {
			fx_adj = make([]Color, n, context.temp_allocator)
			copy(fx_adj, fx_below)
			fx_adj_cov = make([]u8, n, context.temp_allocator)
		}
		src := make([]Color, n, context.temp_allocator)
		copy(src, fx_adj)
		out := make([]Color, n, context.temp_allocator)
		if !show do dev_adjust(def, args, src, out)
		for i in 0 ..< n {
			m := f32(paint[i].a) / 255
			if invert do m = 1 - m
			m *= amount * f32(sel_at(d, i)) / 255
			if m <= 0 do continue
			fx_adj[i] = show ? mix_px(src[i], DEV_MASK_COLOR, m * DEV_MASK_SHOW) : mix_px(src[i], out[i], m)
			fx_adj_cov[i] = max(fx_adj_cov[i], u8(clamp(math.ceil(m * 255), 1, 255)))
		}
		return true, ""
	}

	if p := layer_problem_dev(d); p != "" do return false, p
	if !live_begin() do return false, "the layer can't be changed"
	orig := live.orig
	out := live_out()
	where_lut: [256]f32
	if apply == DEV_APPLY_CURVE do where_lut = macro_curve_value_lut(dev_arg(def, args, "where"))
	if !show do dev_adjust(def, args, orig, out)
	for i in 0 ..< n {
		m := amount
		if apply == DEV_APPLY_CURVE {
			t := where_lut[luma(orig[i])] / 255
			m *= invert ? 1 - t : t
		}
		if show {
			// keep the layer's own opacity: only where it has pixels turns red
			out[i] = mix_px(orig[i], Color{DEV_MASK_COLOR.r, DEV_MASK_COLOR.g, DEV_MASK_COLOR.b, orig[i].a}, m * DEV_MASK_SHOW)
		} else if m < 1 {
			out[i] = mix_px(orig[i], out[i], m)
		}
	}
	live_store(out)
	live_finish()
	return true, ""
}

@(private = "file")
layer_problem_dev :: proc(d: ^Doc) -> string {
	l := &d.layers[d.active_layer]
	if l.is_group do return "the active layer is a group: pick a layer in it"
	if l.locked do return "the layer is locked"
	if !l.visible do return "the layer is hidden"
	return ""
}

// The node's change itself, everywhere: `src` into `dst`.
@(private = "file")
dev_adjust :: proc(def: ^Macro_Def, args: []Macro_Value, src, dst: []Color) {
	num :: proc(def: ^Macro_Def, args: []Macro_Value, key: string) -> f32 {
		return f32(dev_arg(def, args, key).num)
	}
	switch def.id {
	case "dev.Exposure":
		dev_exposure(src, dst, num(def, args, "exposure"), num(def, args, "contrast") / 100, num(def, args, "highlights") / 100, num(def, args, "shadows") / 100)
	case "dev.Tone_Curve":
		dev_tone_curve(src, dst, int(num(def, args, "channel")), macro_curve_value_lut(dev_arg(def, args, "curve")))
	case "dev.HSL":
		dev_hsl(src, dst, int(num(def, args, "colors")), num(def, args, "hue"), num(def, args, "saturation") / 100, num(def, args, "luminance") / 100)
	case:
		copy(dst, src)
	}
}
