package pangolin


IVec :: [2]int
Vec2 :: [2]f32

// Integer rectangle in logical UI pixels.
Rect :: struct {
	x, y, w, h: i32,
}

// Integer rectangle in canvas pixels, half-open: [x0, x1) x [y0, y1).
Box :: struct {
	x0, y0, x1, y1: int,
}

box_empty :: proc(b: Box) -> bool {
	return b.x1 <= b.x0 || b.y1 <= b.y0
}

box_union :: proc(a, b: Box) -> Box {
	if box_empty(a) do return b
	if box_empty(b) do return a
	return Box{min(a.x0, b.x0), min(a.y0, b.y0), max(a.x1, b.x1), max(a.y1, b.y1)}
}

box_clip :: proc(b: Box, w, h: int) -> Box {
	return Box{max(b.x0, 0), max(b.y0, 0), min(b.x1, w), min(b.y1, h)}
}

// Small fixed-capacity string (names, text inputs). Safe to copy by value.
Name :: struct {
	b: [128]u8,
	n: int,
}

name_set :: proc(nm: ^Name, s: string) {
	n := min(len(s), len(nm.b))
	copy(nm.b[:n], s)
	nm.n = n
}

name_str :: proc(nm: ^Name) -> string {
	return string(nm.b[:nm.n])
}

make_name :: proc(s: string) -> Name {
	r: Name
	name_set(&r, s)
	return r
}

Blend :: enum u8 {
	Normal,
	Multiply,
	Screen,
	Overlay,
	Soft_Light,
	Hard_Light,
	Darken,
	Lighten,
	Color_Dodge,
	Color_Burn,
	Add,
	Subtract,
	Difference,
	Hue,
	Saturation,
	Color,
	Luminosity,
}

BLEND_NAMES := [Blend]string {
	.Normal      = "Normal",
	.Multiply    = "Multiply",
	.Screen      = "Screen",
	.Overlay     = "Overlay",
	.Soft_Light  = "Soft Light",
	.Hard_Light  = "Hard Light",
	.Darken      = "Darken",
	.Lighten     = "Lighten",
	.Color_Dodge = "Color Dodge",
	.Color_Burn  = "Color Burn",
	.Add         = "Add",
	.Subtract    = "Subtract",
	.Difference  = "Difference",
	.Hue         = "Hue",
	.Saturation  = "Saturation",
	.Color       = "Color",
	.Luminosity  = "Luminosity",
}

// ---------------------------------------------------------------------------
// Tiled, copy-on-write pixel storage
//
// Painting documents are large, so pixels live in TILE x TILE blocks. Undo snapshots
// share tiles by reference count; writing to a shared tile clones just that tile.
// A nil tile is fully transparent (or, for masks, fully white / "reveal all").
// ---------------------------------------------------------------------------

TILE :: 64

Tile :: struct {
	refs: int,
	pix:  [TILE * TILE]Color,
}

Tiles :: struct {
	tw, th: int, // tile columns / rows
	t:      []^Tile, // tw*th, nil = empty
}

// Editable text layer. The pixels in `Layer.pix` are a rendering of this; any operation that edits
// the pixels directly turns `on` off ("rasterised") so the two can never disagree.
TEXT_MAX :: 2048

Text_Info :: struct {
	on:        bool,
	buf:       [TEXT_MAX]u8, // UTF-8
	n:         int,
	font:      Name, // key of a font in the font list
	size:      int, // em size in canvas pixels
	color:     Color,
	align:     u8, // 0 left, 1 centre, 2 right
	line_pct:  int, // line height as a percentage of the font's natural line height
	track:     int, // extra letter spacing, 1/100 em
	x, y:      f32, // top-left corner of the text block on the canvas
	bx:        Box, // where it was last rendered
}

Layer :: struct {
	name:       Name,
	visible:    bool,
	locked:     bool,
	lock_alpha: bool, // painting keeps existing transparency
	opacity:    u8,
	blend:      Blend,
	pix:        Tiles,
	has_mask:   bool,
	mask:       Tiles, // grey in .r; nil tile = 255 (fully revealed)
	mask_on:    bool, // mask applied when compositing
	text:       Text_Info, // text.on: this is a text layer
}

// Soft selection mask, shared between undo snapshots. Never modified in place.
Mask :: struct {
	refs: int,
	v:    []u8, // w*h, 0 = unselected, 255 = fully selected
	bbox: Box,
}

// Everything that undo/redo restores.
State :: struct {
	w, h:   int,
	layers: [dynamic]Layer,
	sel:    ^Mask, // nil = no selection
}

Doc :: struct {
	using s:      State,
	undo, redo:   [dynamic]State,
	active_layer: int,
	edit_mask:    bool, // brushes paint on the active layer's mask
	path:         string, // empty if never saved
	title:        Name,
	modified:     bool,

	// view
	zoom:         f32,
	ox, oy:       f32, // screen position of canvas pixel (0,0)
	rot:          f32, // reserved; view rotation is not implemented
	view_init:    bool,

	// caches
	comp:         []Color, // composite of all layers
	comp_dirty:   Box, // region of `comp` that must be recomputed
	tex_dirty:    Box, // region of the texture that must be re-uploaded
	sel_edges:    [dynamic]Sel_Edge,
	sel_dirty:    bool,
	thumb_dirty:  bool,
}

// Run of selection outline: `n` unit edges starting at (x, y).
Sel_Edge :: struct {
	x, y: i32,
	n:    i32,
	vert: bool, // false: horizontal run along the top of row y; true: vertical run along the left of column x
}

Tool :: enum {
	Brush,
	Oil,
	Smudge,
	Eraser,
	Blur,
	Dodge,
	Clone,
	Bucket,
	Gradient,
	Picker,
	Text,
	Select_Rect,
	Select_Ellipse,
	Lasso,
	Wand,
	Move,
	Transform,
	Crop,
	Hand,
	Zoom,
	Line, // after the rest: tool groups are saved by index
}

TOOL_NAMES := [Tool]string {
	.Brush          = "Brush (B)",
	.Oil            = "Oil Paint (N)",
	.Smudge         = "Smudge (R)",
	.Eraser         = "Eraser (E)",
	.Blur           = "Blur / Sharpen",
	.Dodge          = "Dodge / Burn (O)",
	.Clone          = "Clone Stamp (S)",
	.Bucket         = "Paint Bucket (G)",
	.Gradient       = "Gradient (Shift+G)",
	.Picker         = "Eyedropper (I)",
	.Text           = "Text (Shift+T)",
	.Select_Rect    = "Rectangular Marquee (M)",
	.Select_Ellipse = "Elliptical Marquee (Shift+M)",
	.Lasso          = "Lasso (L)",
	.Wand           = "Magic Wand (W)",
	.Move           = "Move (V)",
	.Transform      = "Free Transform (T)",
	.Crop           = "Crop (C)",
	.Hand           = "Hand (H)",
	.Zoom           = "Zoom (Z)",
	.Line           = "Line / Polygon (U)",
}

Sel_Mode :: enum {
	Replace,
	Add,
	Subtract,
	Intersect,
}
