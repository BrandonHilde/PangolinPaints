# Pangolin Paints

*Brushstrokes, scale by scale.* Written in Odin with SDL3.

A painting, oil painting and image editing app, and the sibling of
[Pangolin Pixels](https://github.com/BrandonHilde/PangolinPixels): same look and feel,
built for big painted canvases instead of pixel art.

Build with `./build.sh` on Linux/macOS or `build.bat` on Windows. [OdinUI](https://gitlab.com/patrick.pixelshuffle/odinui) is a
git submodule in `libs/odinui`: clone with `git clone --recursive`, or let the build scripts fetch it on the first build
(`git submodule update --init`). To build by hand: `odin build src -out:PangolinPaints -o:speed -collection:odinui=libs/odinui`.
Drag images or projects onto the window to open them; hold Shift while dropping to place an image as a layer.
`PangolinPaints --selftest` runs the headless test suite (on Windows use `PangolinPaints-console.exe`, since the GUI build has no console).

## Features
- **Natural brushes**: size up to 1000 px, opacity, flow, hardness, spacing, smoothing (stabiliser), scatter,
  size jitter, paper grain, angle and roundness; round, bristle, chalk and flat tips; airbrush build-up;
  simulated pressure (tapered ends or stroke speed) driving size and/or opacity; Shift+click for straight strokes.
  Presets: hard/soft round, airbrush, pencil, ink pen, marker, chalk, charcoal, watercolour wash, bristle,
  calligraphy, splatter.
- **Oil paint**: a wet brush that carries a reservoir of paint, deposits it, picks up colour from the canvas
  (wetness), runs dry over distance (paint load) and leaves bristle streaks. Presets: oil round, oil flat,
  wet blender, dry brush, palette knife, thick impasto, detail sable.
- **Blending tools**: smudge (soft, hard, bristle), blur / sharpen, dodge / burn (shadows, midtones, highlights),
  clone stamp (Alt+click source, aligned, optionally sampling all layers), eraser presets.
- **Line / polygon tool** (U): drag for a line, or click points and double click / Enter to finish; click the first
  point to close the shape and optionally fill it. Shift keeps segments at 15 degree steps. Painted with its own
  brush settings (size, hardness, taper, ...).
- **Grid**: a resizable grid (View > Grid, Ctrl+;) that every tool snaps to while Snap to Grid (Ctrl+Shift+;) is on:
  brush strokes, lines, selections, gradients, crops, moves, transforms and text placement. Snapping applies once a
  tool is pressed; hovering stays free, so transform handles are always reachable. The grid can be rotated.
- **Mirror painting**: any number of mirror lines through a movable centre (Move Center, then click or drag on the
  canvas), at any angle: one mirror reflects left / right, more make kaleidoscope / snowflake symmetry. Applies to
  every brush tool and the line tool, including filled shapes.
- **Perspective guides** (View > Perspective Guides): a horizon and 1, 2 or 3 vanishing points with guide lines
  fanning out across the canvas. While their settings are shown, drag a point (or the horizon, which carries its
  points) to move it; points out of sight wait at the edge of the view. With Snap on, brush strokes and the line tool
  pick the guide closest to the way they set off and keep to it (verticals, and in 1-point horizontals, count too).
- **Grid, Mirror and Perspective switches** can be added to tool groups (the group's + button) to turn them on and off with a
  click or the group's hotkey. The options bar shows whatever was picked last: clicking a switch shows its settings
  there (clicking it again turns it off), and picking or using a tool brings that tool's settings back.
- **Image editing**
  - Adjust: auto contrast, brightness/contrast, levels, curves (per channel, with histogram), exposure,
    hue/saturation (colorize), vibrance, colour balance, temperature/tint, desaturate, sepia, invert, posterize,
    threshold.
  - Filter: Gaussian/box/motion/radial blur, unsharp mask, oil paint, painterly (Kuwahara), canvas texture, emboss,
    find edges, add noise, median, pixelate, vignette.
  - All with live preview, applied through the (soft) selection to the active layer or mask.
  - Image size (bicubic / bilinear / nearest), canvas size with anchor, crop tool and crop to selection, trim,
    rotate 90/180 or any angle, flip, free transform (scale, stretch, rotate, move).
- **Selections**: rectangle, ellipse, lasso (anti-aliased), magic wand (tolerance, contiguous, all layers);
  add / subtract / intersect; feather, grow, shrink, invert, select layer opacity; selections soften every tool.
- **Text**: a text tool (Shift+T) that makes editable text layers: click the canvas and type. Pick any bundled or installed
  font, size, colour, alignment, line and letter spacing. Text stays live (click it to edit, Move tool repositions it),
  is saved in `.ppnt` projects, and turns into ordinary pixels the moment you paint or filter the layer.
  Select text (drag, Shift+arrows, double click, Ctrl+A) and pick any colour to colour just that part.
  Layer > Convert Text to Path (or right-click the layer) makes a vector layer from the glyph outlines: moving, transforming and resizing it
  redraws the outlines, so it stays sharp at any size.
- **Pen tablets**: pressure, tilt and the eraser end work with Wacom/Huion-style tablets on Windows (Windows Ink) and
  Linux (SDL pen events). Set `PANGOLIN_PEN_DEBUG=1` on Linux to print pen events.
- **Layers**: unlimited layers with opacity and 17 blend modes (multiply, screen, overlay, soft/hard light,
  dodge/burn, hue, saturation, colour, luminosity, ...) plus Erase, which cuts the layer's shape out of everything
  below it (e.g. knock text out of a painting), lock, lock transparency, layer masks (paint black to hide,
  white to reveal; from selection; apply or delete), merge down, flatten, layer via copy/cut, thumbnails.
- **Colour**: HSV picker, RGB sliders, hex entry, swatch sets (oil paints, skin tones, earth & sky, pastels, ...),
  recent colours, GIMP `.gpl` swatch import/export, eyedropper with averaging. Click a colour in a toolbar colour
  group, then use the colour picker to change that colour.
- **Files**: native `.ppnt` project (all layers, masks and settings, compressed sparse tiles); open PNG / JPG (built-in
  decoder: progressive, CMYK, EXIF rotation) / BMP / TGA / GIF / QOI / TIFF; export PNG, JPG (built-in encoder, quality
  setting), BMP, TGA, QOI, TIFF, optionally scaled. Multiple documents in tabs, unsaved-change prompts.
  New paintings start with a clear layer selected above the background.
- **Photoshop and Krita files**: open `.psd` / `.psb` and `.kra` with their layers (names, opacity, blend modes,
  visibility, layer masks; 8 or 16 bit). Groups are flattened into the layer list; Krita vector, fill and filter
  layers have no pixels in the file and are left out.
- **Big canvases**: pixels live in 64x64 copy-on-write tiles, so undo (100 steps) only stores what changed and
  painting stays fast on 4000x3000 images. Navigator, rule-of-thirds guide, smooth zooming with mipmaps.

Graphics tablets (Windows Ink: Wacom, Huion, Surface, ...): real pen pressure drives size and/or opacity for every brush
out of the box (unless its Pressure setting is turned Off), and the eraser end of the pen erases with the brush / oil
tools. The mouse paints at full pressure, or with simulated pressure (taper / speed) if a brush is set to it. If pressure doesn't register, make sure Windows Ink is
enabled in the Wacom driver's tablet properties.

## Shortcuts (F1 in the app shows the full list)
| | |
|-|-|
| B / N / R / Shift+R / E | brush / oil paint / smudge / blur / eraser |
| O / S / G / Shift+G / I | dodge & burn / clone / bucket / gradient / eyedropper |
| M, Shift+M / L / W | marquee / ellipse marquee / lasso / magic wand |
| V / T / C / H / Z | move / free transform / crop / hand / zoom |
| U | line / polygon (Enter finishes, Backspace removes a point, Esc cancels) |
| Ctrl+; / Ctrl+Shift+; | grid / snap to grid |
| Shift on a slider | move in chunks: angles by 5 degrees, sizes along 1, 2, 3, 5, 10, 15, 20, 25, 50 ..., others by about 5% |
| [ ] / 1-9, 0 | brush size / opacity 10%-100% |
| X / D | swap colours / default colours |
| Space (hold) / Alt (hold) | pan / eyedropper |
| Ctrl+L / Ctrl+M / Ctrl+U / Ctrl+B | levels / curves / hue-saturation / colour balance |
| Ctrl+Shift+N / Ctrl+J / Ctrl+E | new layer / layer via copy / merge down |
| Shift+T | text tool (Esc or Ctrl+Enter finishes typing) |
| / and \ | lock transparency / paint on the layer mask |
| Ctrl+0 / Ctrl+1 / wheel | fit / 100% / zoom |
| Enter / Esc | apply / cancel transform or crop |

## Customising the interface
Edit > Preferences has the UI scale: a slider from 100% to 400%, or Auto, the default, which sizes the interface to the
screen the window is on (150% at 1080p, 200% at 1440p, 300% at 4K). A window too small to hold the layout lowers the
scale until it fits.

The interface is laid out and styled with CSS through [OdinUI](https://gitlab.com/patrick.pixelshuffle/odinui). The
default theme is [assets/ui/theme.css](assets/ui/theme.css). To change it, create `theme.css` next to the executable:
it is applied on top of the default theme and reloaded while the program runs, so it only needs what you change.

```css
:root   { --accent: #6aa8ff; --accent-tint: rgba(106, 168, 255, 0.22); --panel: #1f2430; }
#body   { flex-direction: row-reverse; }   /* tools on the right, colour and layers on the left */
#right  { width: 300px; }
optionsbar slider-bar { width: 110px; }    /* wider sliders in the options bar */
```

The colour variables in `:root` also drive the parts the program draws itself (canvas surroundings, layer list,
dialogs, menus). Icons are a font (`font-family: icons`), so `color` and `font-size` style them like text.

## Developer flags
`--selftest` (tests), `--bench` (timings on a 4000x3000 canvas), `--brush-sheet out.png` (one stroke per preset),
`--icon-sheet out.png` (every icon at each size and UI scale, and the logo),
`--demo` (sample painting), `--scale 150` (UI scale in percent, 0 for Auto), `--shot file.png` (screenshot after a few frames),
`--clicks "frame:x,y;..."` (left clicks at window pixels on those frames, for checking the interface with `--shot`).

Icons are SVG files in `assets/icons` (24 x 24, drawn in `currentColor` with round-capped 2 px strokes) and the logo is
`assets/logo.svg`; both are built into the executable and rasterised at the screen's resolution by `src/svg.odin`.

## License
BSD 3-Clause. See [LICENSE](LICENSE).
