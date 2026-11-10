package pangolin

import "core:fmt"

// ---------------------------------------------------------------------------
// Tooltip text for commands and tools. The menus, the toolbar and the panel buttons all read it from here.
// cmd_help has no #partial, so the compiler asks for text whenever a command is added.
// These strings are constants: a popup item keeps its tip across frames.
// ---------------------------------------------------------------------------

cmd_help :: proc(c: Cmd) -> string {
	switch c {
	case .None:
		return ""
	case .New:
		return "Start a new painting in its own tab. The next window asks for its size and background."
	case .Open:
		return "Open a Pangolin Paints project, a Photoshop or Krita file, or an image such as PNG, JPG or WebP, in a new tab."
	case .Save:
		return "Save the painting with all its layers as a .ppnt project, asking for a file name the first time."
	case .Save_As:
		return "Save the painting as a .ppnt project under a new file name."
	case .Place_Image:
		return "Add an image file to this painting as a new layer, centered and scaled down if it is larger than the canvas."
	case .Export:
		return "Save a flat copy of the visible layers as PNG, JPG, BMP, TGA, QOI or TIFF, at a format and scale you choose in the next window. A painting with several frames can also export a PNG sequence or an animated GIF."
	case .Recent_Clear:
		return "Empty the list of recently opened and saved files in the File menu. The files themselves stay where they are."
	case .Recent_First ..= .Recent_Last:
		return "Open this file again. It is one you opened or saved lately."
	case .Close_Doc:
		return "Close the current tab. If it has unsaved changes you are asked first."
	case .Exit:
		return "Quit Pangolin Paints. If a painting has unsaved changes you are asked first."
	case .Swatches_Load:
		return "Replace the swatches with a palette from a GIMP .gpl file."
	case .Swatches_Save:
		return "Save the swatches to a GIMP .gpl palette file, which other programs can read."
	case .Undo:
		return "Take back the last change. Each painting remembers 100 steps."
	case .Redo:
		return "Bring back the change you just undid."
	case .Cut:
		return "Copy the selection, or the whole active layer, to the clipboard and remove it from the layer."
	case .Copy:
		return "Copy the selection, or the whole active layer, to the clipboard."
	case .Copy_Merged:
		return "Copy what you see inside the selection, with all visible layers combined, to the clipboard."
	case .Paste:
		return "Paste the clipboard as a new layer, back where it was copied from when it fits on this canvas."
	case .Clear:
		return "Delete the pixels inside the selection, or the whole active layer, making them transparent."
	case .Fill_Fg:
		return "Fill the selection, or the whole active layer, with the foreground color."
	case .Fill_Bg:
		return "Fill the selection, or the whole active layer, with the background color."
	case .Brush_Settings:
		return "Open every setting of the current brush tool, with a preview stroke."
	case .Preferences:
		return "Choose how transparent areas are shown, and whether the pixel grid and the navigator appear."
	case .Image_Size:
		return "Scale the whole painting to a new size in pixels. All layers are resampled."
	case .Canvas_Size:
		return "Add or cut away canvas around the painting without scaling it. The anchor picks which side stays put."
	case .Crop_Sel:
		return "Cut the canvas down to the box around the selection."
	case .Trim:
		return "Cut away the fully transparent rows and columns around the painting."
	case .Rotate_CW:
		return "Turn the whole painting a quarter turn clockwise."
	case .Rotate_CCW:
		return "Turn the whole painting a quarter turn counter-clockwise."
	case .Rotate_180:
		return "Turn the whole painting upside down."
	case .Rotate_Any:
		return "Turn the whole painting by an angle you choose. The canvas grows to fit."
	case .Flip_H:
		return "Mirror the whole painting left to right."
	case .Flip_V:
		return "Mirror the whole painting top to bottom."
	case .Flatten:
		return "Combine all layers into one. Hidden layers are lost."
	case .Auto_Contrast:
		return "Stretch the tones of the active layer so its darkest part becomes black and its lightest white."
	case .Curves:
		return "Reshape the tones of the active layer by dragging points on a curve, with a histogram behind it and a live preview."
	case .Layer_New:
		return "Add an empty layer above the active one."
	case .Layer_Dup:
		return "Add a copy of the active layer above it."
	case .Layer_Del:
		return "Remove the active layer. The last layer can't be removed."
	case .Layer_Up:
		return "Move the active layer one step up the stack, in front of the layer above it."
	case .Layer_Down:
		return "Move the active layer one step down the stack, behind the layer below it."
	case .Layer_Merge:
		return "Combine the active layer with the layer below it."
	case .Layer_Text_To_Path:
		return "Turn this text layer into a vector layer of glyph outlines. It stays sharp when resized, but can no longer be typed in."
	case .Layer_Rasterize:
		return "Turn this text or vector layer into ordinary pixels you can paint on."
	case .Layer_Group_New:
		return "Add an empty layer group above the active layer. Drag layers onto it in the layer list to put them in it."
	case .Layer_Group:
		return "Put the active layer in a new group of its own. A group shows its layers together: hide it, change its opacity or blend mode, move or copy it, and they all follow."
	case .Layer_Effects:
		return "Attach macros to the active layer as live effects: they run on the layer whenever it changes (Soft Light and a blur, say), can be switched off or removed, and are saved with the painting."
	case .Layer_Fx_Apply:
		return "Make the active layer's effects part of its pixels, and take them off the layer."
	case .Layer_Ungroup:
		return "Take the active group apart: its layers stay where they are, out of the group."
	case .Layer_Props:
		return "Set the active layer's name, opacity and blend mode, and whether it is visible or locked."
	case .Layer_Via_Copy:
		return "Copy the selection to a new layer above the active one. With no selection this duplicates the layer."
	case .Layer_Via_Cut:
		return "Move the selection to a new layer above the active one. With no selection this duplicates the layer."
	case .Layer_Lock_Alpha:
		return "Keep the layer's transparency as it is: paint only lands where the layer already has pixels."
	case .Mask_Add:
		return "Give the active layer a white mask that shows everything. Paint on it with black to hide parts of the layer."
	case .Mask_From_Sel:
		return "Give the active layer a mask that shows only what is inside the selection."
	case .Mask_Delete:
		return "Remove the layer mask and show the whole layer again."
	case .Mask_Apply:
		return "Make the mask's effect permanent by removing the hidden pixels from the layer, then remove the mask."
	case .Mask_Edit:
		return "Switch between painting on the layer and painting on its mask. On the mask, black hides and white reveals."
	case .Mask_Enable:
		return "Turn the mask's effect on or off without losing it."
	case .Frame_New:
		return "Add an empty frame after the current one and go to it. Text and vector layers show on it, as they do on every frame."
	case .Frame_Dup:
		return "Add a copy of the current frame after it and go to it. The copy takes little memory until you paint on it."
	case .Frame_From_Visible:
		return "Add a frame after the current one holding one flat image of everything visible now, so it looks exactly the same. You can paint over it without touching the layers of other frames."
	case .Frame_Del:
		return "Remove the current frame. The last frame can't be removed."
	case .Frame_Left:
		return "Swap the current frame with the one before it."
	case .Frame_Right:
		return "Swap the current frame with the one after it."
	case .Frame_Prev:
		return "Go to the previous frame, wrapping around at the start."
	case .Frame_Next:
		return "Go to the next frame, wrapping around at the end."
	case .Frame_First:
		return "Go to the first frame."
	case .Frame_Last:
		return "Go to the last frame."
	case .Play:
		return "Play or pause the animation, over all frames or the tag picked on the timeline. Frames are slower the first time round, while they are prepared."
	case .Tags:
		return "Name ranges of frames, to play or export only those, forward, backward or back and forth."
	case .Frame_Props:
		return "Set how long the current frame shows when the animation plays, or give every frame the same duration."
	case .Toggle_Onion:
		return "Show the neighbouring frames over the canvas while you paint: earlier ones tinted slightly red, later ones blue. The timeline's bar sets how many and how strongly."
	case .Select_All:
		return "Select the whole canvas."
	case .Deselect:
		return "Clear the selection. Esc does this too."
	case .Invert_Sel:
		return "Select everything that isn't selected, and deselect what is."
	case .Select_Alpha:
		return "Select the pixels of the active layer, as solidly as they are opaque."
	case .Feather:
		return "Soften the edge of the selection by a radius you choose."
	case .Grow:
		return "Push the edge of the selection outward by a radius you choose."
	case .Shrink:
		return "Pull the edge of the selection inward by a radius you choose."
	case .Zoom_In:
		return "Zoom in on the middle of the view. The mouse wheel zooms on the pointer."
	case .Zoom_Out:
		return "Zoom out from the middle of the view. The mouse wheel zooms on the pointer."
	case .Zoom_Fit:
		return "Zoom and scroll so the whole canvas fits in the window."
	case .Zoom_1:
		return "Show one canvas pixel per interface pixel."
	case .Zoom_2:
		return "Show the canvas at twice the size of 100%."
	case .Toggle_Pixel_Grid:
		return "Outline each pixel when you zoom in far enough to see them."
	case .Toggle_Thirds:
		return "Show lines dividing the canvas into thirds, a guide for composing a picture."
	case .Toggle_Grid:
		return "Show or hide the grid over the canvas. While Snap to Grid is on, every tool lands on its lines."
	case .Toggle_Snap:
		return "Make strokes, shapes, selections and moves land on the grid. Turning this on also shows the grid."
	case .Grid_Settings:
		return "Set the grid's cell size, line opacity and angle."
	case .Toggle_Mirror:
		return "Paint with mirror copies across lines through a center point. The options bar sets how many lines and their angle."
	case .Toggle_Perspective:
		return "Show a horizon and vanishing points. While Snap is on, strokes and lines run along their guide lines. Drag the points to place them."
	case .Toggle_Navigator:
		return "Show or hide the small picture of the whole canvas in the side panel. Click or drag in it to move the view."
	case .Toggle_Canvas_Mode:
		return "Hide the toolbar, tabs and side panels to give the painting more room. A bar along the bottom keeps the tool groups."
	case .Toggle_Seamless:
		return "Repeat the canvas around itself and wrap strokes across its edges, for textures that tile without a visible seam."
	case .Cycle_Canvas_Bg:
		return "Step through how transparent areas are shown: checkerboard, black, white or gray."
	case .UI_Scale:
		return "Make the whole interface larger or smaller, or let it size itself to fit your screen."
	case .Toggle_Timeline:
		return "Show or hide the frames of this painting under the canvas, with playback, tags and onion skin."
	case .Toggle_Files:
		return "Show or hide the file browser under the canvas: thumbnails of a folder's images and projects, to drag onto the canvas or the tab bar."
	case .Help_Keys:
		return "List the keyboard shortcuts."
	case .About:
		return "Show the version and license of Pangolin Paints."
	case .Ws_Manage:
		return "Load, save and delete workspaces: named sets of tool groups, swatches and brush settings."
	case .Ws_Import:
		return "Load a workspace from a .ppws file, switch to it and keep a copy in your list."
	case .Ws_Export:
		return "Save the current tool groups, swatches and brush settings to a .ppws file you can share."
	case .Macro_Editor:
		return "Open the node editor: build a macro from nodes wired together, starting from Start, and give their settings values or wire values into them."
	case .Macro_Record:
		return "Start recording a macro: each command you use from now on becomes a step. Choose it again to stop and save the macro."
	case .Macros:
		return "Run, rename, delete, import and export macros: saved chains of commands you can put in a tool group and run with its hotkey."
	case .Macro_Import:
		return "Copy a macro from a .pmacro file into your list of macros."
	case .Swap_Colors:
		return "Swap the foreground and background colors."
	case .Default_Colors:
		return "Set the foreground to black and the background to white."
	case .Brush_Smaller:
		return "Make the current brush about an eighth smaller."
	case .Brush_Bigger:
		return "Make the current brush about an eighth larger."
	case .Opacity_10 ..= .Opacity_100:
		return "Set the opacity of the current brush tool. Shift plus a number key sets 10% to 90%, and Shift+0 sets 100%."
	case .Tool_Brush ..= .Tool_Smart_Select:
		return TOOL_HELP[Tool(int(c) - int(Cmd.Tool_Brush))]
	case .Fx_First ..= .Fx_Last:
		return FX_DEFS[Fx(int(c) - int(Cmd.Fx_First))].help
	case .Macro_First ..= .Macro_Last:
		return "Run this macro on the painting. One Undo takes it all back."
	case .Ws_First ..= .Ws_Last:
		i := int(c) - int(Cmd.Ws_First)
		if i < len(WS_BUILTIN_HELP) do return WS_BUILTIN_HELP[i]
		return "Switch to this saved workspace. Its tool groups, swatches and brush settings replace the current ones."
	}
	return ""
}

TOOL_HELP := [Tool]string {
	.Brush          = "Drag to paint with the foreground color, or right-drag for the background color. Shift-click draws a straight line from the end of the last stroke. Hold Alt to pick a color.",
	.Oil            = "A wet brush: it carries paint, mixes with what is on the canvas and runs dry over distance. Right-drag loads it with the background color. Shift-click draws a straight line. Hold Alt to pick a color.",
	.Smudge         = "Drag to pull the colors on the canvas along, like a finger through wet paint. Shift-click smudges in a straight line. Hold Alt to pick a color.",
	.Eraser         = "Drag to erase from the active layer, or on a mask, to hide. Shift-click erases in a straight line.",
	.Blur           = "Drag to soften the pixels under the brush, or to sharpen them with the Sharpen button in the options bar. Shift-click works in a straight line. Hold Alt to pick a color.",
	.Dodge          = "Drag to lighten what is under the brush, or to darken it with the Burn button in the options bar. The range setting picks which tones are affected. Hold Alt to pick a color.",
	.Clone          = "Alt-click to set the source, then drag to paint a copy of what is there. The source follows the brush, and Shift-drag re-aligns it. All layers can be sampled.",
	.Bucket         = "Click to fill the area of similar color with the foreground color, or right-click for the background color. Tolerance sets how similar. Hold Alt to pick a color.",
	.Gradient       = "Drag across the canvas to fill from the foreground to the background color, or to transparent. It fills the selection if there is one. Hold Alt to pick a color.",
	.Picker         = "Click to make a color on the canvas the foreground color, or right-click for the background color. It reads all visible layers. Hold Alt with most tools to pick for a moment.",
	.Text           = "Click the canvas to type on a new text layer, or click existing text to edit it. Esc or Ctrl+Enter finishes. Text stays editable until you paint on it.",
	.Select_Rect    = "Drag to select a rectangle. Shift adds, Alt subtracts, both together intersect. Press Shift during the drag for a square, Ctrl to draw from the center. Drag inside a selection to move it.",
	.Select_Ellipse = "Drag to select an ellipse. Shift adds, Alt subtracts, both together intersect. Press Shift during the drag for a circle, Ctrl to draw from the center. Drag inside a selection to move it.",
	.Lasso          = "Drag around an area to select it freehand. Shift adds, Alt subtracts, both together intersect. Drag inside a selection to move it.",
	.Wand           = "Click to select the area of similar color. Tolerance sets how similar. Shift adds, Alt subtracts, both together intersect.",
	.Move           = "Drag to move the selection, or the whole layer if nothing is selected. Hold Alt to leave the original in place. Arrow keys nudge by a pixel, or by 10 with Shift.",
	.Transform      = "Drag a corner to scale, with Shift for free proportions. Drag an edge to stretch, outside the box to rotate, inside it to move. Enter or a double click applies, Esc cancels. Ctrl+T also picks this tool.",
	.Crop           = "Drag the area to keep, with Shift for a square. Enter or a double click crops, Esc cancels.",
	.Hand           = "Drag to scroll the view. Holding Space or dragging with the middle mouse button does this with any tool.",
	.Zoom           = "Click to zoom in, right-click to zoom out. The mouse wheel zooms with any tool.",
	.Line           = "Drag for one line, or click to place points and double-click, right-click or press Enter to finish. Click the first point to close the shape. Shift keeps to 15 degree steps, Backspace removes a point, Esc cancels.",
	.Grid           = "A switch: turn the grid on and show its settings in the options bar. Click again to turn it off.",
	.Mirror         = "A switch: paint with mirror copies across lines through a center point. Its settings show in the options bar. Click again to turn it off.",
	.Perspective    = "A switch: show a horizon and vanishing points that strokes and lines snap to. Its settings show in the options bar. Click again to turn it off.",
	.Seamless       = "A switch: repeat the canvas around itself and wrap strokes across its edges, for textures that tile. Click again to turn it off.",
	.Smart_Select   = "Click to select the area of similar color, like the Magic Wand, with more control: curves give some hues or tones more or less tolerance and make the edge soft, and Edge bias stops the area at sharp edges or moves its outline onto them. Shift adds, Alt subtracts, both together intersect. Settings... opens all of it.",
}

// What the status bar says about the current tool. One short line: the tooltip has the rest.
TOOL_HINT := [Tool]string {
	.Brush          = "Drag to paint. Right-drag: background color. Alt: pick a color",
	.Oil            = "Drag to paint with wet oil. Right-drag: background color. Alt: pick a color",
	.Smudge         = "Drag to pull the colors along. Alt: pick a color",
	.Eraser         = "Drag to erase. Shift-click: straight line from the last stroke",
	.Blur           = "Drag to blur or sharpen, as chosen in the options bar",
	.Dodge          = "Drag to lighten or darken, as chosen in the options bar",
	.Clone          = "Alt-click: set the source. Drag: paint a copy of it",
	.Bucket         = "Click to fill with the foreground color. Right-click: background color",
	.Gradient       = "Drag across the canvas to fill with a gradient",
	.Picker         = "Click: foreground color. Right-click: background color",
	.Text           = "Click to type. Click text to edit it. Esc or Ctrl+Enter finishes",
	.Select_Rect    = "Drag to select. Shift: add. Alt: subtract. Drag inside to move it",
	.Select_Ellipse = "Drag to select. Shift: add. Alt: subtract. Drag inside to move it",
	.Lasso          = "Drag around an area to select it. Shift: add. Alt: subtract",
	.Wand           = "Click to select similar color. Shift: add. Alt: subtract",
	.Move           = "Drag to move the selection or the layer. Arrow keys nudge",
	.Transform      = "Corners scale, edges stretch, outside rotates. Enter applies, Esc cancels",
	.Crop           = "Drag the area to keep. Enter or double-click crops, Esc cancels",
	.Hand           = "Drag to scroll the view. Space does this with any tool",
	.Zoom           = "Click to zoom in, right-click to zoom out",
	.Line           = "Drag for a line, or click points. Enter finishes, Esc cancels",
	.Grid           = "",
	.Mirror         = "",
	.Perspective    = "",
	.Seamless       = "",
	.Smart_Select   = "Click to select similar color, shaped by its curves. Shift: add. Alt: subtract",
}

WS_BUILTIN_HELP := [len(WS_BUILTIN_NAMES)]string {
	"The standard tool groups: paint, draw, select, transform and view.",
	"Groups for painting by hand, with the pen's eraser end set to erase and smudge.",
	"Groups for retouching a picture: selecting, framing, then fixing and marking it.",
	"A small set for drawing: brush, line and eraser, fills, and the view tools.",
}

BLEND_HELP := [Blend]string {
	.Normal      = "Covers what is below, as far as its opacity allows.",
	.Multiply    = "Darkens: like layering inks, white disappears and black stays black.",
	.Screen      = "Lightens: like projecting light, black disappears and white stays white.",
	.Overlay     = "Adds contrast: lightens the light parts below and darkens the dark ones.",
	.Soft_Light  = "A gentle Overlay, like shining a soft light on what is below.",
	.Hard_Light  = "A strong Overlay led by this layer's own tones, like a harsh spotlight.",
	.Darken      = "Keeps whichever is darker in each color channel.",
	.Lighten     = "Keeps whichever is lighter in each color channel.",
	.Color_Dodge = "Brightens what is below strongly, giving glowing highlights.",
	.Color_Burn  = "Darkens what is below strongly, giving deep saturated shadows.",
	.Add         = "Adds the colors together, so overlaps get brighter.",
	.Subtract    = "Takes this color away from what is below, so overlaps get darker.",
	.Difference  = "Shows how far apart the two colors are. Identical colors become black.",
	.Hue         = "Takes the hue from here, and saturation and lightness from below.",
	.Saturation  = "Takes the saturation from here, and hue and lightness from below.",
	.Color       = "Takes hue and saturation from here, and lightness from below. Good for tinting.",
	.Luminosity  = "Takes the lightness from here, and hue and saturation from below.",
	.Erase       = "Cuts this shape out of everything below it, such as knocking text out of a picture.",
}

SWATCH_PRESET_HELP := [Swatch_Preset]string {
	.Oil_Paints = "Classic artists' pigments, roughly as they look from the tube.",
	.Basic      = "Black, grays, white and the pure hues.",
	.Skin_Tones = "A range of skin colors, from pale to deep.",
	.Earth_Sky  = "Blues for the sky, warm browns for the earth, and greens for plants.",
	.Pastels    = "Pale, soft colors.",
	.Grays      = "Even steps from black to white.",
}

// Brush settings, shared by the options bar and the Brush Settings window.
HELP_SIZE :: "The diameter of the brush in canvas pixels. [ and ] change it from the keyboard, and Shift moves along round sizes."
HELP_OPACITY :: "The most paint one stroke can lay down. Crossing over it within a stroke adds nothing. Shift plus a number key sets it in tens of percent."
HELP_FLOW :: "How much paint each dab lays down. Low flow builds up gently where the stroke crosses itself."
HELP_HARDNESS :: "How crisp the edge of the brush is: 100 is sharp, 0 fades from the middle."
HELP_SPACING :: "The distance between dabs, as a percent of the brush size. Low values give a smooth line, high values a row of dots."
HELP_SMOOTHING :: "A stabilizer: the stroke trails behind the pointer, which evens out shaky lines."
HELP_SCATTER :: "Throw dabs off the line of the stroke at random, by up to this percent of the brush size."
HELP_SIZE_JITTER :: "Vary the size of each dab at random, by up to this percent."
HELP_GRAIN :: "How much a paper texture breaks up the paint."
HELP_ANGLE :: "The direction a brush that isn't round points in. Shift moves by 5 degrees."
HELP_ROUNDNESS :: "Squash the tip: 100 is round, low values make a thin ellipse. Angle sets its direction."
HELP_TIP :: "The shape of the dab: Round is soft or hard, Bristle streaky, Chalk grainy, and Flat is squared off for calligraphy and knives."
HELP_FOLLOW :: "Turn the tip as the stroke changes direction, like a real flat brush."
HELP_PRESSURE :: "What varies the stroke when there is no tablet pen. Taper thins its ends, Speed thins fast strokes. A pen's own pressure is used whenever a pen is in use, unless this is Off."
HELP_TAPER :: "How long the thin ends of a tapered stroke are."
HELP_P_SIZE :: "Pressure makes the brush larger: the harder, the bigger."
HELP_P_OPACITY :: "Pressure makes the paint more solid: the harder, the stronger."
HELP_AIRBRUSH :: "Keep adding paint while the button is held, even when the pointer isn't moving."
HELP_LOAD :: "How much paint is on the brush. It runs dry sooner at low values, and never at 100."
HELP_WET :: "How much color the brush picks up from the canvas and mixes into its paint."
HELP_BRISTLES :: "How strongly individual bristles show as streaks in the stroke."
HELP_SMUDGE :: "How far colors are dragged along with the brush."
HELP_BLUR :: "How strongly each dab blurs or sharpens."
HELP_EXPOSURE :: "How strongly each dab lightens or darkens."
HELP_TONES :: "Which tones are changed the most: the shadows, the midtones or the highlights."
HELP_CLONE_ALL :: "Copy from what you see with all visible layers combined, rather than only the active layer."
HELP_TOLERANCE :: "How different a color can be from the clicked one and still count as the same area. 0 means exactly equal."
HELP_CONTIGUOUS :: "On: only the connected area. Off: every matching pixel on the canvas."
HELP_ALL_LAYERS :: "Find the area from what you see with all visible layers combined, rather than only the active layer."
HELP_SMOOTH_EDGE :: "Blend the edge of the area with its surroundings, rather than a hard edge of whole pixels."
HELP_FILL_OPACITY :: "How solid the fill is."

// A tool's name and the key that picks it.
tool_title :: proc(t: Tool) -> string {
	sc := shortcut_text(Cmd(int(Cmd.Tool_Brush) + int(t)))
	return sc == "" ? TOOL_NAMES[t] : fmt.tprintf("%s (%s)", TOOL_NAMES[t], sc)
}

// The tooltip of a button that runs a command: its name and shortcut, then what it does.
cmd_tip :: proc(name: string, c: Cmd) -> Tip {
	sc := shortcut_text(c)
	return {sc == "" ? name : fmt.tprintf("%s (%s)", name, sc), cmd_help(c)}
}

// The tooltip of a tool's button: its name and key, then how to use it.
tool_tip :: proc(t: Tool) -> Tip {
	return {tool_title(t), TOOL_HELP[t]}
}

// Where a painting lives and whether it has unsaved changes.
doc_status :: proc(d: ^Doc) -> string {
	where_is := d.path != "" ? d.path : "Not saved to a file yet"
	return fmt.tprintf("%s.%s", where_is, d.modified ? " It has unsaved changes." : "")
}

menu_title_tip :: proc(title: string) -> Tip {
	desc := ""
	switch title {
	case "File":       desc = "Create, open, save, import and export paintings, and load or save swatches."
	case "Edit":       desc = "Undo, the clipboard, filling, and the brush settings and preferences."
	case "Image":      desc = "Change the size of the whole painting, crop, rotate, flip and flatten it."
	case "Adjust":     desc = "Change the tones and colors of the active layer, with a live preview."
	case "Filter":     desc = "Blur, sharpen and stylize the active layer, with a live preview."
	case "Frame":      desc = "Add, copy, move and delete animation frames, step through them and play them."
	case "Layer":      desc = "Add, copy, stack and merge layers, and work with text, vector layers and masks."
	case "Select":     desc = "Select all or nothing, invert the selection, and feather, grow or shrink it."
	case "View":       desc = "Zoom, guides, the grid, mirror, perspective, canvas mode, tiled mode, the UI scale, the timeline and the file browser."
	case "Workspaces": desc = "Switch between sets of tool groups, swatches and brush settings, and save your own."
	case "Macros":     desc = "Run your macros, record a new one, and manage them."
	case "Help":       desc = "Keyboard shortcuts and information about the program."
	}
	return {"", desc}
}
