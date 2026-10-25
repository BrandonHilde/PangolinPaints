# Linux pen / Wacom tablet support: plan (SDL3)

## Current state
- The app reads one shared `pen` struct (`src/pen.odin`): `in_range`, `touching`, `eraser`, `pressure`, `tilt`, `pos`,
  `down_evt`, `up_evt`, `seen`. Brushes (`brush.odin`), the eraser end (`tools.odin`) and `ui_begin_frame` (`ui.odin:204-223`,
  where the tip becomes the left button and `pen.pos` replaces the mouse position) already consume it.
- Only `pen_windows.odin` fills it. On Linux `pen_other.odin` is an empty stub, so the Wacom behaves as a plain mouse:
  no pressure, no eraser end, and the stroke start lags.
- `gfx_poll` (`src/gfx.odin:352`) handles mouse events but ignores SDL's pen events entirely.
- The old XInput2/libXi plan is dropped. The project moved from raylib to SDL3, and SDL3 (nightly in `vendor:sdl3`) reports pens natively on
  X11 and Wayland (`PEN_PROXIMITY_IN/OUT`, `PEN_DOWN/UP`, `PEN_MOTION`, `PEN_AXIS`, `PEN_BUTTON_*`). It reports pressure, tilt and
  `eraser` too. No new bindings or libraries are needed.

## Steps
1. **Diagnose first (5 min).** Session is Wayland. Check what the tablet exposes, with `libinput list-devices` and
   `libinput debug-events` (the tablet-tool events should show pressure). Then log `PEN_*` events from the SDL loop (temporary
   `fmt.println`) to confirm SDL delivers them. If it doesn't, the likely causes are the compositor lacking
   `zwp_tablet_v2` (unlikely on Fedora GNOME/KDE) or SDL falling back to X11; try `SDL_VIDEODRIVER=wayland` and `=x11`.
2. **Handle the events** in a new `pen_sdl.odin` (`pen_handle_event :: proc(e: ^sdl.Event)`), called from the `gfx_poll`
   switch. It maps events as follows:
   - `PEN_PROXIMITY_IN/OUT` set `in_range` and `seen`. On OUT, if touching, also set `up_evt`, then clear `touching` and `pressure`.
   - `PEN_DOWN/UP` set `touching`, `down_evt`/`up_evt` and `eraser` (from `e.ptouch.eraser`), and update `pos`.
   - `PEN_MOTION` updates `pos`, and sets `in_range` as a fallback if proximity events are missing.
   - `PEN_AXIS` updates `pressure`, and `tilt` from `XTILT/YTILT`.
   - Scale `pos` by `gfx.density`, as the mouse code does.
   - Keep the Windows invariants: `touching` only while the tip is down, and `pressure` is 0 when not touching.
3. **Wire it up.** Make `pen_init` platform-neutral: Windows calls `pen_win_init`, other platforms do nothing. Remove the
   Linux dependency on `pen_other.odin`, or keep it as a stub for macOS.
4. **Avoid double input.** SDL also synthesises mouse events from the pen (`SDL_HINT_PEN_MOUSE_EVENTS`). `ui_begin_frame` already
   ignores them while `pen_active()`. Set `SDL_PEN_MOUSE_EVENTS=0` and `SDL_PEN_TOUCH_EVENTS=0` before `Init` so a tap can't
   start a second stroke, but only if testing shows menus and sliders still work. The pen tip drives the UI via `pen.*` either way.
5. **Update docs.** Fix the stale comment in `pen.odin` ("SDL reports the pen as a mouse") and add a README line on tablet support.

## Test checklist (Wacom)
1. Logged `PEN_*` events show pressure 0..1 and eraser = true when the eraser end is flipped.
2. Brush with Pressure not Off: no delay before the first dab, line width follows pressure.
3. Eraser end with Brush/Oil erases.
4. Menus, sliders, colour picker and the text tool work with the tip; a quick tap makes exactly one dab.
5. Mouse and trackpad still work when the pen is out of range; the status shows "Pen" / "Pen (out of range)".
6. Unplug and replug while running.

## Known risks
- Under XWayland/X11 with the libinput driver, SDL may report the eraser only via the tool type. Verify in step 1.
- The Wacom may report pressure as a mouse button only if the compositor lacks the tablet protocol. Then fall back to X11 via `SDL_VIDEODRIVER=x11`.
- Pen position is in logical pixels; multiply by `gfx.density` or strokes will be offset on HiDPI.
