# Pangolin Paints

*Brushstrokes, scale by scale.* Written in Odin with SDL3.

A painting, oil painting and image editing app, and the sibling of
[Pangolin Pixels](https://github.com/BrandonHilde/PangolinPixels): same look and feel,
built for big painted canvases instead of pixel art.

Build with `./build.sh` on Linux/macOS or `build.bat` on Windows (or `odin build src -out:PangolinPaints -o:speed`).
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
- **Pen tablets**: pressure, tilt and the eraser end work with Wacom/Huion-style tablets on Windows (Windows Ink) and
  Linux (SDL pen events). Set `PANGOLIN_PEN_DEBUG=1` on Linux to print pen events.
- **Layers**: unlimited layers with opacity and 17 blend modes (multiply, screen, overlay, soft/hard light,
  dodge/burn, hue, saturation, colour, luminosity, ...), lock, lock transparency, layer masks (paint black to hide,
  white to reveal; from selection; apply or delete), merge down, flatten, layer via copy/cut, thumbnails.
- **Colour**: HSV picker, RGB sliders, hex entry, swatch sets (oil paints, skin tones, earth & sky, pastels, ...),
  recent colours, GIMP `.gpl` swatch import/export, eyedropper with averaging.
- **Files**: native `.ppnt` project (all layers, masks and settings, compressed sparse tiles); open PNG / JPG (built-in
  decoder: progressive, CMYK, EXIF rotation) / BMP / TGA / GIF / QOI; export PNG, JPG (built-in encoder, quality
  setting), BMP, TGA, QOI, optionally scaled. Multiple documents in tabs, unsaved-change prompts.
- **Big canvases**: pixels live in 64x64 copy-on-write tiles, so undo (100 steps) only stores what changed and
  painting stays fast on 4000x3000 images. Navigator, rule-of-thirds guide, smooth zooming with mipmaps.

Graphics tablets (Windows Ink: Wacom, Huion, Surface, ...): real pen pressure drives size and/or opacity for any brush
whose Pressure setting isn't Off, and the eraser end of the pen erases with the brush / oil tools. Other platforms
(and mouse input) use simulated pressure (taper / speed). If pressure doesn't register, make sure Windows Ink is
enabled in the Wacom driver's tablet properties.

## Shortcuts (F1 in the app shows the full list)
| | |
|-|-|
| B / N / R / Shift+R / E | brush / oil paint / smudge / blur / eraser |
| O / S / G / Shift+G / I | dodge & burn / clone / bucket / gradient / eyedropper |
| M, Shift+M / L / W | marquee / ellipse marquee / lasso / magic wand |
| V / T / C / H / Z | move / free transform / crop / hand / zoom |
| [ ] / 1-9, 0 | brush size / opacity 10%-100% |
| X / D | swap colours / default colours |
| Space (hold) / Alt (hold) | pan / eyedropper |
| Ctrl+L / Ctrl+M / Ctrl+U / Ctrl+B | levels / curves / hue-saturation / colour balance |
| Ctrl+Shift+N / Ctrl+J / Ctrl+E | new layer / layer via copy / merge down |
| Shift+T | text tool (Esc or Ctrl+Enter finishes typing) |
| / and \ | lock transparency / paint on the layer mask |
| Ctrl+0 / Ctrl+1 / wheel | fit / 100% / zoom |
| Enter / Esc | apply / cancel transform or crop |

## Developer flags
`--selftest` (tests), `--bench` (timings on a 4000x3000 canvas), `--brush-sheet out.png` (one stroke per preset),
`--demo` (sample painting), `--shot file.png` (screenshot after a few frames).

## License
BSD 3-Clause. See [LICENSE](LICENSE).
