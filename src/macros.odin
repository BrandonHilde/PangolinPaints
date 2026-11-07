package pangolin

import "core:fmt"
import "core:math"
import "core:reflect"
import "core:strings"

// Node macros: Paints' side. The graph, its file format and the interpreter are shared (shared_macro.odin,
// shared_macro_io.odin); here are the nodes Paints offers and the code that runs them. See PangolinShared/MacroPlan.md.
//
// Node ids: cmd.<Cmd> runs a command that needs no settings, fx.<Fx> applies an adjustment or filter with the settings
// of its window, and the rest (sel.*, image.*, layer.*, ...) are commands whose windows ask for settings.

macro_app_id :: proc() -> string {
	return "paints"
}

macro_dir :: proc() -> string {
	return fmt.tprintf("%smacros/", gfx_app_dir())
}

// A number about the open painting, for the Document Info node (MACRO_INFO order).
macro_info :: proc(what: int) -> f64 {
	d := doc
	if d == nil do return 0
	switch what {
	case 0:
		return f64(d.w)
	case 1:
		return f64(d.h)
	case 2:
		return f64(len(d.layers))
	case 3:
		return f64(d.active_layer + 1)
	case 4:
		return f64(len(d.frames))
	case 5:
		return f64(d.active_frame + 1)
	}
	return 0
}

// The painting, small, for the node editor (which hides the canvas).
macro_preview :: proc(r: Rect) {
	d := doc
	ctl_well(r)
	if d == nil do return
	if d.comp_lazy do doc_refresh_comp(d)
	render_refresh(d)
	z := min(f32(r.w - 8) / f32(d.w), f32(r.h - 8) / f32(d.h))
	w, h := f32(d.w) * z, f32(d.h) * z
	dst := FRect{math.floor(f32(r.x) + (f32(r.w) - w) / 2), math.floor(f32(r.y) + (f32(r.h) - h) / 2), w, h}
	draw_canvas_bg(dst)
	draw_canvas_tex(d, dst)
}

macro_renamed :: proc(old, new: string) {
	tool_groups_rename_macro(old, new)
}

Macro_Cmd :: struct {
	cmd:  Cmd,
	cat:  string,
	name: string,
}

// Commands that are nodes as they are. The tools (Tool_Brush ..= Tool_Seamless) are added to these.
MACRO_CMDS := [?]Macro_Cmd {
	{.Cut, "Edit", "Cut"},
	{.Copy, "Edit", "Copy"},
	{.Copy_Merged, "Edit", "Copy Merged"},
	{.Paste, "Edit", "Paste as Layer"},
	{.Clear, "Edit", "Delete"},
	{.Fill_Fg, "Edit", "Fill with Foreground"},
	{.Fill_Bg, "Edit", "Fill with Background"},
	{.Crop_Sel, "Image", "Crop to Selection"},
	{.Trim, "Image", "Trim Transparent Edges"},
	{.Rotate_CW, "Image", "Rotate 90 CW"},
	{.Rotate_CCW, "Image", "Rotate 90 CCW"},
	{.Rotate_180, "Image", "Rotate 180"},
	{.Flip_H, "Image", "Flip Horizontal"},
	{.Flip_V, "Image", "Flip Vertical"},
	{.Flatten, "Image", "Flatten"},
	{.Auto_Contrast, "Image", "Auto Contrast"},
	{.Layer_New, "Layer", "New Layer"},
	{.Layer_Dup, "Layer", "Duplicate Layer"},
	{.Layer_Del, "Layer", "Delete Layer"},
	{.Layer_Up, "Layer", "Move Layer Up"},
	{.Layer_Down, "Layer", "Move Layer Down"},
	{.Layer_Merge, "Layer", "Merge Down"},
	{.Layer_Text_To_Path, "Layer", "Text to Path"},
	{.Layer_Rasterize, "Layer", "Rasterize Layer"},
	{.Layer_Via_Copy, "Layer", "Layer via Copy"},
	{.Layer_Via_Cut, "Layer", "Layer via Cut"},
	{.Layer_Lock_Alpha, "Layer", "Lock Transparency"},
	{.Mask_Add, "Layer", "Add Layer Mask"},
	{.Mask_From_Sel, "Layer", "Mask from Selection"},
	{.Mask_Delete, "Layer", "Delete Mask"},
	{.Mask_Apply, "Layer", "Apply Mask"},
	{.Mask_Edit, "Layer", "Edit Mask"},
	{.Mask_Enable, "Layer", "Enable Mask"},
	{.Frame_New, "Frame", "New Frame"},
	{.Frame_Dup, "Frame", "Duplicate Frame"},
	{.Frame_From_Visible, "Frame", "New Frame from Visible"},
	{.Frame_Del, "Frame", "Delete Frame"},
	{.Frame_Left, "Frame", "Move Frame Left"},
	{.Frame_Right, "Frame", "Move Frame Right"},
	{.Frame_Prev, "Frame", "Previous Frame"},
	{.Frame_Next, "Frame", "Next Frame"},
	{.Frame_First, "Frame", "First Frame"},
	{.Frame_Last, "Frame", "Last Frame"},
	{.Select_All, "Select", "Select All"},
	{.Deselect, "Select", "Deselect"},
	{.Invert_Sel, "Select", "Invert Selection"},
	{.Select_Alpha, "Select", "Select Layer Opacity"},
	{.Swap_Colors, "Color", "Swap Colors"},
	{.Default_Colors, "Color", "Default Colors"},
	{.Brush_Smaller, "Brush", "Smaller Brush"},
	{.Brush_Bigger, "Brush", "Bigger Brush"},
}

// Commands whose windows ask for settings: a node with those settings stands in for them.
MACRO_CMD_NODES := [?]struct {
	cmd: Cmd,
	id:  string,
} {
	{.Feather, "sel.Feather"},
	{.Grow, "sel.Grow"},
	{.Shrink, "sel.Shrink"},
	{.Image_Size, "image.Size"},
	{.Canvas_Size, "image.Canvas_Size"},
	{.Rotate_Any, "image.Rotate"},
	{.Layer_Props, "layer.Opacity"},
	{.Export, "file.Export"},
	{.Save, "file.Save"},
}

// Commands that are not nodes: they ask for a file, open a window, only change the view, or would undo the macro itself.
MACRO_CMD_EXCLUDED := [?]Cmd {
	.New, .Open, .Save_As, .Place_Image, .Close_Doc, .Exit, .Swatches_Load, .Swatches_Save,
	.Undo, .Redo, .Brush_Settings, .Preferences, .Curves, .Tags, .Frame_Props, .Play, .Toggle_Onion,
	.Zoom_In, .Zoom_Out, .Zoom_Fit, .Zoom_1, .Zoom_2, .Toggle_Pixel_Grid, .Toggle_Thirds, .Toggle_Grid, .Toggle_Snap,
	.Grid_Settings, .Toggle_Mirror, .Toggle_Perspective, .Toggle_Navigator, .Toggle_Canvas_Mode, .Toggle_Seamless,
	.Cycle_Canvas_Bg, .UI_Scale, .Toggle_Timeline, .Toggle_Files, .Help_Keys, .About, .Ws_Manage, .Ws_Import, .Ws_Export,
	.Macro_Record, .Macros, .Macro_Import, .Macro_Editor,
}

SEL_MODES := [4]string{"replace", "add", "subtract", "intersect"}
SEL_UNITS := [2]string{"pixels", "percent"}
LAYER_PICKS := [5]string{"above", "below", "top", "bottom", "number"}

@(private = "file")
cat: [dynamic]Macro_Def

@(private = "file")
cmd_is_node: #sparse [Cmd]bool

macro_catalogue :: proc() -> []Macro_Def {
	if len(cat) == 0 do macro_catalogue_build()
	return cat[:]
}

// The id of command `c`'s node, if it has one that needs no settings.
macro_cmd_id :: proc(c: Cmd) -> (string, bool) {
	macro_catalogue()
	if !cmd_is_node[c] do return "", false
	return fmt.tprintf("cmd.%v", c), true
}

// A setting's key from its name: "Input black" -> "input_black".
macro_key :: proc(name: string) -> string {
	sb := strings.builder_make(context.temp_allocator)
	for r in strings.to_lower(name, context.temp_allocator) {
		switch r {
		case 'a' ..= 'z', '0' ..= '9':
			strings.write_rune(&sb, r)
		case ' ', '-', '_':
			if strings.builder_len(sb) > 0 do strings.write_byte(&sb, '_')
		}
	}
	return strings.trim_right(strings.to_string(sb), "_")
}

@(private = "file")
keep :: proc(s: string) -> string {
	return strings.clone(s)
}

@(private = "file")
num :: proc(key, name: string, lo, hi, def: f64, suffix, help: string, div: f64 = 0) -> Macro_Setting {
	return {key = key, name = name, type = .Number, lo = lo, hi = hi, def = {num = def}, suffix = suffix, help = help, div = div}
}

@(private = "file")
choice :: proc(key, name: string, choices: []string, def: int, help: string) -> Macro_Setting {
	return {key = key, name = name, type = .Choice, choices = choices, def = {num = f64(def)}, help = help}
}

@(private = "file")
flag :: proc(key, name: string, def: bool, help: string) -> Macro_Setting {
	return {key = key, name = name, type = .Bool, def = {num = def ? 1 : 0}, help = help}
}

@(private = "file")
color :: proc(key, name: string, def: Color, help: string) -> Macro_Setting {
	return {key = key, name = name, type = .Color, def = {col = def}, help = help}
}

@(private = "file")
text_setting :: proc(key, name, def, help: string, browse := false) -> Macro_Setting {
	return {key = key, name = name, type = .Text, def = {text = def}, help = help, browse = browse}
}

@(private = "file")
node :: proc(id, name, category, help: string, settings: ..Macro_Setting) {
	s := make([]Macro_Setting, len(settings))
	copy(s, settings)
	append(&cat, Macro_Def{id = id, name = name, category = category, help = help, settings = s})
}

// An enumerated array of names as a slice that lives as long as the program.
@(private = "file")
names_of :: proc(names: []string) -> []string {
	s := make([]string, len(names))
	copy(s, names)
	return s
}

macro_catalogue_build :: proc() {
	for c in MACRO_CMDS {
		node(keep(fmt.tprintf("cmd.%v", c.cmd)), c.name, c.cat, cmd_help(c.cmd))
		cmd_is_node[c.cmd] = true
	}
	for t in Tool {
		c := Cmd(int(Cmd.Tool_Brush) + int(t))
		node(keep(fmt.tprintf("cmd.%v", c)), keep(fmt.tprintf("Pick %s", TOOL_NAMES[t])), "Tools", TOOL_HELP[t])
		cmd_is_node[c] = true
	}

	resample := make([]string, len(Resample))
	for k, i in RESAMPLE_KEYS do resample[int(i)] = k
	formats := make([]string, len(Export_Format))
	for k, i in EXPORT_KEYS do formats[int(i)] = k
	blends := names_of(blend_names_slice())
	units := SEL_UNITS[:]
	modes := SEL_MODES[:]

	// selection
	SHAPE_X :: "The left edge of the shape, in canvas pixels or percent of the width."
	SHAPE_Y :: "The top edge of the shape, in canvas pixels or percent of the height."
	SHAPE_W :: "The width of the shape, in canvas pixels or percent of the width."
	SHAPE_H :: "The height of the shape, in canvas pixels or percent of the height."
	UNITS_TIP :: "Pixels, or percent of the canvas size, so the macro works the same on any size of painting."
	MODE_TIP :: "Replace the selection, add to it, take the shape away from it, or keep only where they overlap."
	for shape in ([2]string{"Rect", "Ellipse"}) {
		node(keep(fmt.tprintf("sel.%s", shape)), shape == "Rect" ? "Select Rectangle" : "Select Ellipse", "Select",
			shape == "Rect" ? "Select a rectangle of the canvas." : "Select an ellipse that fits the given box.",
			num("x", "Left", 0, 100000, 0, "", SHAPE_X), num("y", "Top", 0, 100000, 0, "", SHAPE_Y),
			num("w", "Width", 1, 100000, 100, "", SHAPE_W), num("h", "Height", 1, 100000, 100, "", SHAPE_H),
			choice("units", "Units", units, 1, UNITS_TIP), choice("mode", "Mode", modes, 0, MODE_TIP))
	}
	node("sel.Feather", "Feather Selection", "Select", cmd_help(.Feather), num("px", "Radius", 1, 500, 10, " px", "How wide the soft edge of the selection is, in canvas pixels."))
	node("sel.Grow", "Grow Selection", "Select", cmd_help(.Grow), num("px", "Radius", 1, 500, 5, " px", "How far the edge of the selection moves outward, in canvas pixels."))
	node("sel.Shrink", "Shrink Selection", "Select", cmd_help(.Shrink), num("px", "Radius", 1, 500, 5, " px", "How far the edge of the selection moves inward, in canvas pixels."))

	// edit and colors
	node("edit.Fill", "Fill with Color", "Edit", "Fill the selection, or the whole layer, with a color.", color("color", "Color", {0, 0, 0, 255}, "The fill color."))
	node("color.Foreground", "Set Foreground Color", "Color", "Make this the foreground color, the one the brushes paint with.", color("color", "Color", {0, 0, 0, 255}, "The new foreground color."))
	node("color.Background", "Set Background Color", "Color", "Make this the background color.", color("color", "Color", {255, 255, 255, 255}, "The new background color."))
	node("brush.Opacity", "Brush Opacity", "Brush", "Set the opacity of the current painting tool (the Brush if another tool is picked).", num("opacity", "Opacity", 1, 100, 100, "%", "How solid one stroke is at most."))
	node("brush.Size", "Brush Size", "Brush", "Set the size of the current painting tool (the Brush if another tool is picked).", num("size", "Size", 1, BRUSH_MAX, 20, " px", "The brush diameter, in canvas pixels."))

	// image
	RESAMPLE_TIP :: "How new pixels are worked out. Bicubic is smoothest, Bilinear softer, and Nearest keeps hard pixel edges."
	node("image.Size", "Image Size", "Image", "Scale the painting to a size in pixels. Leave the width or the height at 0 to keep the proportions.",
		num("width", "Width", 0, 16000, 0, " px", "The new width. 0 follows the height, keeping the proportions."),
		num("height", "Height", 0, 16000, 0, " px", "The new height. 0 follows the width, keeping the proportions."),
		choice("resample", "Resample", resample, 0, RESAMPLE_TIP))
	node("image.Scale", "Scale Image", "Image", "Scale the painting by a percentage.",
		num("percent", "Scale", 1, 1000, 50, "%", "The new size as a percentage of the current one."), choice("resample", "Resample", resample, 0, RESAMPLE_TIP))
	node("image.Canvas_Size", "Canvas Size", "Image", "Change the canvas size without scaling the painting. Leave the width or the height at 0 to keep it.",
		num("width", "Width", 0, 16000, 0, " px", "The new canvas width. 0 keeps the current one."),
		num("height", "Height", 0, 16000, 0, " px", "The new canvas height. 0 keeps the current one."),
		choice("anchor", "Anchor", ANCHOR_KEYS[:], 4, "Where the painting sits in the new canvas. Space is added, or cut away, on the other sides."))
	node("image.Rotate", "Rotate by Angle", "Image", cmd_help(.Rotate_Any), num("angle", "Angle", -359, 359, 90, " deg", "How far to turn the painting, clockwise. Negative angles turn it counter-clockwise."))

	// layers
	node("layer.Pick", "Pick Layer", "Layer", "Make another layer the active one.",
		choice("which", "Layer", LAYER_PICKS[:], 0, "The layer above or below the active one, the top or bottom layer, or a layer by its number."),
		num("number", "Number", 1, 10000, 1, "", "With Layer set to number: 1 is the bottom layer."))
	node("layer.Opacity", "Layer Opacity", "Layer", "Set how solid the active layer is.", num("opacity", "Opacity", 0, 100, 100, "%", "100 covers what is below, 0 hides it."))
	node("layer.Blend", "Layer Blend Mode", "Layer", "Set how the active layer mixes with the layers below it.", choice("blend", "Blend mode", blends, 0, BLEND_TIP))
	node("layer.Visible", "Show or Hide Layer", "Layer", "Show or hide the active layer.", flag("visible", "Visible", true, "Show the layer. A hidden layer can't be painted on and isn't exported."))
	node("layer.Lock", "Lock Layer", "Layer", "Lock or unlock the active layer.", flag("locked", "Locked", true, "Protect the layer from painting and other changes."))
	node("layer.Rename", "Rename Layer", "Layer", "Give the active layer a new name.", text_setting("name", "Name", "Layer", "The layer's name in the layer list."))

	// frames
	node("frame.Go", "Go to Frame", "Frame", "Show a frame by its number.", num("frame", "Frame", 1, 10000, 1, "", "The frame's number: 1 is the first."))

	// adjustments and filters, with the settings of their windows
	for fx in Fx {
		def := &FX_DEFS[fx]
		s := make([dynamic]Macro_Setting)
		for p in def.params {
			append(&s, num(keep(macro_key(p.name)), p.name, f64(p.lo), f64(p.hi), f64(p.def), p.suffix, p.help, f64(p.div > 1 ? p.div : 0)))
		}
		if def.flag != "" do append(&s, flag(keep(macro_key(def.flag)), def.flag, def.flag_def, def.flag_help))
		if def.choice != nil {
			is_channel := def.choice[0] == "RGB"
			append(&s, choice(is_channel ? "channel" : "range", is_channel ? "Channel" : "Tonal range", def.choice, fx == .Color_Balance ? 1 : 0, def.choice_help))
		}
		append(&cat, Macro_Def{id = keep(fmt.tprintf("fx.%v", fx)), name = def.name, category = fx < FX_FIRST_FILTER ? "Adjust" : "Filter", help = def.help, settings = s[:]})
	}

	// file
	node("file.Export", "Export", "File", "Save a flat copy of the visible layers, without asking where.",
		choice("format", "Format", formats, 0, "The file format. A PNG sequence and an animated GIF need more than one frame."),
		num("quality", "Quality", 1, 100, 90, "", "JPEG quality: higher looks better and makes a bigger file."),
		num("scale", "Scale", 1, 1000, 100, "%", "The size of the exported image, as a percentage of the painting."),
		text_setting("path", "File", "{dir}/{name}.{ext}", "Where to write it: type it, or pick it with the ... button. {dir} is the painting's folder, {name} its file name, {frame} the frame number and {ext} the format's extension.", true))
	node("file.Save", "Save", "File", "Save the painting with all its layers as a .ppnt project, without asking where.",
		text_setting("path", "File", "", "Leave it empty to save to the painting's own file. Or set where to save it, typed or picked with the ... button: the painting then belongs to that file. {dir} is the painting's folder and {name} its file name.", true))
}

// Why the active layer can't be changed, or "".
@(private = "file")
layer_problem :: proc(d: ^Doc) -> string {
	l := &d.layers[d.active_layer]
	if l.locked do return "the layer is locked"
	if !l.visible do return "the layer is hidden"
	return ""
}

// Runs one node. `args` are its settings in the order of `def.settings`.
macro_exec :: proc(def: ^Macro_Def, args: []Macro_Value) -> (ok: bool, msg: string) {
	d := doc
	kind, _, name := strings.partition(def.id, ".")
	switch kind {
	case "cmd":
		c, cok := reflect.enum_from_name(Cmd, name)
		if !cok || !cmd_is_node[c] do return false, "unknown command"
		return macro_exec_cmd(d, c)
	case "fx":
		fx, fok := reflect.enum_from_name(Fx, name)
		if !fok do return false, "unknown effect"
		return macro_exec_fx(d, fx, args)
	}
	switch def.id {
	case "sel.Rect", "sel.Ellipse":
		x, y, w, h := args[0].num, args[1].num, args[2].num, args[3].num
		if macro_int(args, 4) == 1 {
			x, w = x * f64(d.w) / 100, w * f64(d.w) / 100
			y, h = y * f64(d.h) / 100, h * f64(d.h) / 100
		}
		sel_shape(d, def.id == "sel.Ellipse", x, y, w, h, macro_int(args, 5))
	case "sel.Feather", "sel.Grow", "sel.Shrink":
		op: Sel_Op = def.id == "sel.Feather" ? .Feather : def.id == "sel.Grow" ? .Grow : .Shrink
		if !doc_sel_modify(d, op, macro_int(args, 0)) do return false, "there is no selection"
	case "edit.Fill":
		if p := layer_problem(d); p != "" do return false, p
		edit_fill(args[0].col)
	case "color.Foreground":
		set_fg(args[0].col)
	case "color.Background":
		bg = args[0].col
	case "brush.Opacity", "brush.Size":
		t := paint_tool(cur_tool) ? cur_tool : Tool.Brush
		if def.id == "brush.Opacity" {
			brushes[t].opacity = macro_int(args, 0)
		} else {
			brushes[t].size = macro_int(args, 0)
		}
	case "image.Size":
		w, h := macro_int(args, 0), macro_int(args, 1)
		if w <= 0 && h <= 0 do return false, "give it a width or a height"
		if w <= 0 do w = max(int(f64(d.w) * f64(h) / f64(d.h) + 0.5), 1)
		if h <= 0 do h = max(int(f64(d.h) * f64(w) / f64(d.w) + 0.5), 1)
		if w != d.w || h != d.h do doc_image_size(d, w, h, Resample(macro_int(args, 2)))
	case "image.Scale":
		p := macro_int(args, 0)
		w, h := max(d.w * p / 100, 1), max(d.h * p / 100, 1)
		if w > 16000 || h > 16000 do return false, "the painting would be larger than 16000 pixels"
		if w != d.w || h != d.h do doc_image_size(d, w, h, Resample(macro_int(args, 1)))
	case "image.Canvas_Size":
		w, h := macro_int(args, 0), macro_int(args, 1)
		if w <= 0 do w = d.w
		if h <= 0 do h = d.h
		if w != d.w || h != d.h do doc_canvas_size_anchored(d, w, h, macro_int(args, 2))
	case "image.Rotate":
		a := macro_int(args, 0)
		if a % 360 != 0 do doc_rotate_any(d, f32(a))
	case "layer.Pick":
		i := d.active_layer
		switch macro_int(args, 0) {
		case 0:
			i += 1
		case 1:
			i -= 1
		case 2:
			i = len(d.layers) - 1
		case 3:
			i = 0
		case:
			i = macro_int(args, 1) - 1
		}
		if i < 0 || i >= len(d.layers) do return false, "there is no such layer"
		d.active_layer = i
		d.edit_mask = false
	case "layer.Opacity", "layer.Blend", "layer.Visible", "layer.Lock", "layer.Rename":
		history_push(d)
		l := &d.layers[d.active_layer]
		switch def.id {
		case "layer.Opacity":
			l.opacity = u8(clamp(macro_int(args, 0), 0, 100) * 255 / 100)
		case "layer.Blend":
			l.blend = Blend(macro_int(args, 0))
		case "layer.Visible":
			l.visible = macro_bool(args, 0)
		case "layer.Lock":
			l.locked = macro_bool(args, 0)
		case "layer.Rename":
			name_set(&l.name, strings.trim_space(args[0].text))
		}
		doc_touch_all(d)
	case "frame.Go":
		f := macro_int(args, 0) - 1
		if f < 0 || f >= len(d.frames) do return false, "there is no such frame"
		set_frame(f)
	case "file.Save":
		if t := strings.trim_space(args[0].text); t != "" {
			path, pok, pmsg := macro_export_path(d, t, "ppnt")
			if !pok do return false, pmsg
			if !file_save_to(d, path) do return false, "it could not be saved"
		} else {
			if d.path == "" do return false, "the painting has never been saved: choose a file in the Save node"
			if !file_save(d, false) do return false, "it could not be saved"
		}
	case "file.Export":
		f := Export_Format(macro_int(args, 0))
		if int(f) >= EXPORT_STILL_FORMATS && len(d.frames) < 2 do return false, "this format needs more than one frame"
		path, pok, pmsg := macro_export_path(d, args[3].text, EXPORT_EXT[f])
		if !pok do return false, pmsg
		return export_to_path(d, path, f, macro_int(args, 1), macro_int(args, 2))
	case:
		return false, "unknown node"
	}
	return true, ""
}

@(private = "file")
macro_exec_cmd :: proc(d: ^Doc, c: Cmd) -> (ok: bool, msg: string) {
	l := &d.layers[d.active_layer]
	#partial switch c {
	case .Cut, .Clear, .Fill_Fg, .Fill_Bg, .Auto_Contrast, .Layer_Via_Cut:
		if p := layer_problem(d); p != "" do return false, p
	case .Crop_Sel:
		if d.sel == nil do return false, "there is no selection"
	case .Layer_Del:
		if len(d.layers) < 2 do return false, "it is the only layer"
	case .Layer_Merge:
		if d.active_layer == 0 do return false, "there is no layer below to merge into"
	case .Layer_Text_To_Path:
		if !l.text.on do return false, "the layer is not a text layer"
	case .Frame_Del:
		if len(d.frames) < 2 do return false, "it is the only frame"
	case .Mask_Add:
		if l.has_mask do return false, "the layer already has a mask"
	case .Mask_From_Sel:
		if d.sel == nil do return false, "there is no selection"
		if l.has_mask do return false, "the layer already has a mask"
	case .Mask_Delete, .Mask_Apply, .Mask_Edit, .Mask_Enable:
		if !l.has_mask do return false, "the layer has no mask"
	case .Paste:
		if clip.pix == nil do return false, "the clipboard is empty"
	}
	run_cmd(c)
	return true, ""
}

@(private = "file")
macro_exec_fx :: proc(d: ^Doc, fx: Fx, args: []Macro_Value) -> (ok: bool, msg: string) {
	if p := layer_problem(d); p != "" do return false, p
	def := &FX_DEFS[fx]
	st := Fx_State {
		fx   = fx,
		seed = u64(ui.time * 1000) + 1,
	}
	i := 0
	for _ in def.params {
		st.v[i] = macro_int(args, i)
		i += 1
	}
	if def.flag != "" {
		st.flag = macro_bool(args, i)
		i += 1
	}
	if def.choice != nil do st.choice = macro_int(args, i)
	if !live_begin() do return false, "the layer can't be changed"
	fxs = st
	fx_apply_now()
	live_finish()
	return true, ""
}

// Selects a rectangle or an ellipse fitting the box, combined with the selection by `mode` (Sel_Mode order).
sel_shape :: proc(d: ^Doc, ellipse: bool, x, y, w, h: f64, mode: int) {
	a, b := Vec2{f32(x), f32(y)}, Vec2{f32(x + w), f32(y + h)}
	shape := ellipse ? sel_ellipse(d.w, d.h, a, b) : sel_rect(d.w, d.h, a, b)
	defer delete(shape)
	history_push(d)
	doc_sel_set(d, sel_combine(d.sel != nil ? d.sel.v : nil, shape, Sel_Mode(clamp(mode, 0, len(Sel_Mode) - 1))))
}

// The folder a path starts with, without the last slash.
@(private = "file")
path_dir :: proc(p: string) -> string {
	i := strings.last_index_any(p, "/\\")
	return i >= 0 ? p[:i] : ""
}

// An export path from its template: {dir} the painting's folder, {name} its file name, {frame} the frame number,
// {ext} the format's extension. Adds the extension if the result has none.
macro_export_path :: proc(d: ^Doc, tmpl, ext: string) -> (path: string, ok: bool, msg: string) {
	dir := d.path != "" ? path_dir(d.path) : ""
	name := d.path != "" ? path_stem(d.path) : name_str(&d.title)
	if strings.contains(tmpl, "{dir}") && dir == "" {
		return "", false, "the painting has never been saved, so {dir} is not a folder yet"
	}
	p := tmpl
	p, _ = strings.replace_all(p, "{dir}", dir, context.temp_allocator)
	p, _ = strings.replace_all(p, "{name}", name, context.temp_allocator)
	p, _ = strings.replace_all(p, "{frame}", fmt.tprintf("%03d", d.active_frame + 1), context.temp_allocator)
	p, _ = strings.replace_all(p, "{ext}", ext, context.temp_allocator)
	p = strings.trim_space(p)
	if p == "" || strings.has_suffix(p, "/") || strings.has_suffix(p, "\\") do return "", false, "the file name is empty"
	is_abs := strings.has_prefix(p, "/") || strings.has_prefix(p, "\\") || (len(p) > 2 && p[1] == ':')
	if !is_abs {
		if dir == "" do return "", false, "the painting has never been saved, so the file needs a full path"
		p = fmt.tprintf("%s/%s", dir, p)
	}
	// the file gets the format's extension, whatever was typed
	if path_ext(p) == "" {
		p = fmt.tprintf("%s.%s", p, ext)
	} else if lower_ext(p) != fmt.tprintf(".%s", ext) {
		p = fmt.tprintf("%s.%s", strings.trim_suffix(p, path_ext(p)), ext)
	}
	return p, true, ""
}

// The template a recorded export uses: the painting's folder and name become {dir} and {name}, so the macro works
// on other paintings too.
export_path_template :: proc(d: ^Doc, path: string) -> string {
	if d.path == "" do return path
	dir, file := path_dir(path), path_basename(path)
	stem, ext := path_stem(file), path_ext(file)
	if stem == path_stem(d.path) do stem = "{name}"
	if strings.equal_fold(dir, path_dir(d.path)) do dir = "{dir}"
	return fmt.tprintf("%s/%s%s", dir, stem, ext)
}

// Records an applied effect with its settings.
fx_record :: proc(st: ^Fx_State) {
	if !macro_recording() do return
	def := &FX_DEFS[st.fx]
	args := make([dynamic]string, context.temp_allocator)
	for p, i in def.params do append(&args, macro_key(p.name), fmt.tprint(st.v[i]))
	if def.flag != "" do append(&args, macro_key(def.flag), st.flag ? "1" : "0")
	if def.choice != nil do append(&args, def.choice[0] == "RGB" ? "channel" : "range", def.choice[clamp(st.choice, 0, len(def.choice) - 1)])
	macro_record(fmt.tprintf("fx.%v", st.fx), ..args[:])
}

// ---------------------------------------------------------------------------
// Running
// ---------------------------------------------------------------------------

@(private = "file")
macro_doc: ^Doc

macro_begin :: proc() -> (ok: bool, msg: string) {
	if doc == nil do return false, "there is no painting open"
	if dialog.kind != .None do return false, "close the open window first"
	tools_commit_pending()
	stop_playback()
	history_push(doc)
	doc.history_hold += 1
	macro_doc = doc
	return true, ""
}

macro_end :: proc(keep: bool) {
	d := macro_doc
	macro_doc = nil
	if d == nil do return
	d.history_hold -= 1
	if !keep {
		history_revert(d)
		doc_touch_all(d)
	}
	d.thumb_dirty = true
	d.sel_dirty = true
}

// ---------------------------------------------------------------------------
// Recording, import, export and the Macros window
// ---------------------------------------------------------------------------

FILTERS_MACRO := [?]Filter{{"Pangolin Paints macro (*.pmacro)", "*.pmacro"}, {"All files", "*.*"}}

macro_record_toggle :: proc() {
	if !macro_recording() {
		macro_record_start()
		set_status("Recording a macro: the commands you use now become its steps. Choose Macros > Stop Recording to finish.")
		return
	}
	m := macro_record_stop()
	if m == nil {
		set_status("Stopped recording. Nothing was recorded, so no macro was saved.")
		return
	}
	macro_set_name(m, "Recorded macro")
	if !macro_add(m) {
		macro_free(m)
		show_message("Macro", "Could not write the macro file.")
		return
	}
	set_statusf("Saved macro %s", m.name)
	macro_editor_open(m.name)
}

macro_import :: proc() {
	os_dir := macro_dir()
	p, ok := native_dialog(false, "Import macro", FILTERS_MACRO[:], "pmacro", "", os_dir)
	if !ok do return
	defer delete(p)
	name, iok, msg := macro_import_file(p)
	if !iok {
		show_message("Macro", msg)
		return
	}
	set_statusf("Imported macro %s", name)
}

macro_export :: proc(m: ^Macro) {
	p, ok := native_dialog(true, "Export macro", FILTERS_MACRO[:], "pmacro", fmt.tprintf("%s%s", m.name, MACRO_EXT))
	if !ok do return
	defer delete(p)
	if macro_export_file(m, p) {
		set_statusf("Exported macro to %s", path_basename(p))
	} else {
		show_message("Macro", "Could not write the macro file.")
	}
}

// A step as the Macros window lists it: the node's name and its settings.
macro_step_text :: proc(n: ^Macro_Node) -> string {
	def := macro_def_find(n.kind)
	if def == nil do return fmt.tprintf("%s (not in this version)", n.kind)
	if len(def.settings) == 0 do return def.name
	sb := strings.builder_make(context.temp_allocator)
	strings.write_string(&sb, def.name)
	vals := macro_node_own_values(n, def)
	for &s, i in def.settings {
		strings.write_string(&sb, i == 0 ? ": " : ", ")
		v := macro_value_text(&s, vals[i])
		if s.type == .Number && s.div > 0 do v = macro_num_text(vals[i].num / s.div)
		fmt.sbprintf(&sb, "%s %s%s", strings.to_lower(s.name, context.temp_allocator), v, s.type == .Number ? s.suffix : "")
	}
	return strings.to_string(sb)
}

MACRO_STEP_LINES :: 7

dlg_macros :: proc() {
	c := dialog_frame("Macros", 500, 64 + MACRO_STEP_LINES * 14 + 68)
	y := c.y
	n := len(macro_lib)
	if n == 0 {
		text(c.x, y + 3, "No macros yet. Record one: Macros > Record Macro.", C_TEXT_DIM)
	} else {
		@(static) names: [MACRO_MAX]string
		for m, i in macro_lib do names[i] = m.name
		dialog.a = clamp(dialog.a, 0, n - 1)
		PICK_TIP :: "The macro the buttons below act on."
		tip_text(c.x, y + 3, "Macro", C_TEXT, {"Macro", PICK_TIP})
		if nv, ch := combo(Rect{c.x + 60, y, c.w - 60 - 132, 14}, names[:n], dialog.a, {"Macro", PICK_TIP}); ch {
			dialog.a = nv
			dialog.flag = false
		}
		m := macro_lib[dialog.a]
		if button(Rect{c.x + c.w - 60, y - 1, 60, 16}, "Run", {"", "Run this macro on the painting. One Undo takes it all back."}) {
			dialog_close()
			macro_run_named(m.name)
			return
		}
		if button(Rect{c.x + c.w - 60 - 6 - 60, y - 1, 60, 16}, "Edit", {"", "Open this macro in the node editor."}) {
			dialog_close()
			macro_editor_open(m.name)
			return
		}
		if dialog.b != dialog.a {
			dialog.b = dialog.a
			name_set(&dialog.name, m.name)
		}
		y += 22
		// the steps, in the order they run
		chain, ok, msg := macro_chain(m)
		if !ok {
			text_clipped(Rect{c.x, y, c.w, 14}, fmt.tprintf("This macro can't run: %s.", msg), C_DANGER)
		} else if len(chain) == 0 {
			text(c.x, y, "This macro has no steps.", C_TEXT_DIM)
		} else {
			for s, i in chain {
				if i == MACRO_STEP_LINES - 1 && len(chain) > MACRO_STEP_LINES {
					text(c.x, y + i32(i) * 14, fmt.tprintf("... and %d more steps", len(chain) - i), C_TEXT_DIM)
					break
				}
				text_clipped(Rect{c.x, y + i32(i) * 14, c.w, 14}, fmt.tprintf("%d. %s", i + 1, macro_step_text(s)), C_TEXT)
			}
		}
		y += MACRO_STEP_LINES * 14 + 8
		NAME_TIP :: "A new name for the macro. Tool groups that hold it by its old name need it added again."
		tip_text(c.x, y + 3, "Name", C_TEXT, {"Name", NAME_TIP})
		text_field(Rect{c.x + 60, y, c.w - 60 - 66, 14}, &dialog.name, {"Name", NAME_TIP})
		if button(Rect{c.x + c.w - 60, y - 1, 60, 16}, "Rename", {"", "Give the macro the name typed here."}) {
			old := strings.clone(m.name, context.temp_allocator)
			if rok, rmsg := macro_rename(m, name_str(&dialog.name)); rok {
				tool_groups_rename_macro(old, m.name)
				for x, i in macro_lib do if x == m do dialog.a = i
				dialog.b = dialog.a
				set_statusf("Renamed the macro to %s", m.name)
			} else {
				set_status(rmsg)
			}
		}
		y += 24
		if button(Rect{c.x, y, 80, 16}, "Export...", {"", "Save this macro to a .pmacro file you can share."}) {
			macro_export(m)
		}
		if button(Rect{c.x + 86, y, 80, 16}, dialog.flag ? "Really delete?" : "Delete", {"", "Delete this macro. Click twice: it can't be undone."}) {
			if dialog.flag {
				name := strings.clone(m.name, context.temp_allocator)
				macro_delete(m)
				dialog.flag = false
				dialog.b = -1
				set_statusf("Deleted macro %s", name)
			} else {
				dialog.flag = true
			}
		}
	}
	// on the same row as Export and Delete, at the right
	y = c.y + 22 + MACRO_STEP_LINES * 14 + 8 + 24
	if button(Rect{c.x + c.w - 80, y, 80, 16}, "Import...", {"", cmd_help(.Macro_Import)}) {
		macro_import()
	}
	if button(Rect{c.x + c.w - 80 - 6 - 104 - 6 - 80, y, 80, 16}, "New...", {"", cmd_help(.Macro_Editor)}) {
		dialog_close()
		macro_editor_open()
		return
	}
	if button(Rect{c.x + c.w - 80 - 6 - 104, y, 104, 16}, macro_recording() ? "Stop Recording" : "Record New...", {"", cmd_help(.Macro_Record)}, true, macro_recording()) {
		dialog_close()
		macro_record_toggle()
		return
	}
	ok, _ := dialog_buttons(c, "Close this window (Enter).", "Close", "")
	if ok || IsKeyPressed(.ESCAPE) {
		dialog_close()
	}
}
