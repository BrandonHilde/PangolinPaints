# Linux pen / graphics tablet support: implementation plan

## Where things stand
Windows is done: `src/pen_windows.odin` fills the shared `pen` struct (`src/pen.odin`) and the rest of the app only
reads that struct:

| Field | Used by |
|-|-|
| `pen.pressure` (0..1), `pen.in_range` | `stroke_begin` / `stroke_move` / `stroke_pressure` in `brush.odin` (`Pressure.Pen`) |
| `pen.eraser` | `eff_tool()` in `tools.odin` (eraser end acts as the Eraser) |
| `pen.touching`, `pen.pos`, `pen.down_evt`, `pen.up_evt` | `ui_begin_frame()` in `ui.odin`: while a pen is in range its tip *is* the left mouse button and its position replaces the mouse position. This removes the OS-synthesised mouse-down delay. |
| `pen.tilt` | filled in, not used by any brush yet |

On Linux `src/pen_other.odin` is an empty stub (`#+build !windows`), so the app builds and runs with a pen acting as a
plain mouse. **The whole job is to write `src/pen_linux.odin` that fills the same `pen` struct**; nothing else in the
app needs to change. Change `pen_other.odin` to `#+build !windows, !linux` (or delete the stub's `pen_win_init` for
Linux) and name the new entry point so `pen_init()` in `pen.odin` calls it. Easiest: rename the hook to `pen_platform_init`
and `pen_platform_poll` in all three files.

## Approach: XInput2 on X11 (also covers Wayland via XWayland)
raylib's GLFW hands pen input over as plain mouse events, so pressure has to come from XInput2 (`libXi`). XWayland
delivers XI2 tablet events too, so this covers most desktops. Native Wayland (`zwp_tablet_v2`) is a possible later step.

### 1. Get the X11 display and window
- raylib 5.5's `rl.GetWindowHandle()` returns the X11 `Window` on Linux/X11 (it calls `glfwGetX11Window`). Check on the
  target raylib version; if it returns nil, declare `glfwGetX11Window` as a foreign proc (GLFW is statically inside raylib).
- Open a **separate** connection: `XOpenDisplay(nil)`. Do not reuse GLFW's `Display`: GLFW drains that event queue and
  would eat or race our events. A second connection selecting events on the same window gets its own copy.
- Under real Wayland (`XDG_SESSION_TYPE=wayland` with no XWayland window) `GetWindowHandle` is not an X11 window. Detect that
  (`XOpenDisplay` fails or the handle is nil) and just leave `pen` unset. To force X11 for testing run with `GLFW_PLATFORM`
  unset and `WAYLAND_DISPLAY=` empty, or `XDG_SESSION_TYPE=x11`.

### 2. Bindings
`vendor:x11/xlib` covers core Xlib (`Display`, `XOpenDisplay`, `XPending`, `XNextEvent`, `XGetEventData`, `XFreeEventData`,
`XQueryExtension`, `XInternAtom`). XInput2 is **not** in Odin's vendor collection, so hand-write a small binding:

```odin
foreign import xi "system:Xi"
// XISelectEvents, XIQueryDevice, XIFreeDeviceInfo, XIQueryVersion
```
Structs needed (layout from `<X11/extensions/XInput2.h>`, verify against the header): `XIEventMask`, `XIDeviceInfo`,
`XIAnyClassInfo`, `XIValuatorClassInfo`, `XIButtonClassInfo`, `XIDeviceEvent`, `XIValuatorState`.

### 3. Setup (in `pen_platform_init`)
1. `XQueryExtension(dpy, "XInputExtension", &opcode, ...)` and `XIQueryVersion(dpy, 2, 2)`.
2. `XISelectEvents(dpy, window, ...)` with a mask for `XI_ButtonPress`, `XI_ButtonRelease`, `XI_Motion`, `XI_Enter`,
   `XI_Leave`, and on the root window `XI_HierarchyChanged` to catch tablets plugged in later. Use `XIAllDevices` (or
   `XIAllMasterDevices` if the slaves' events turn out to be duplicated; try `XIAllDevices` first, since the pen's own
   slave device is what carries the valuators).
3. `XIQueryDevice(dpy, XIAllDevices, &n)`. For each device with a `XIValuatorClass` containing a valuator whose label atom
   is `"Abs Pressure"`, remember `{device id, pressure valuator number, min, max}`. Do the same for `"Abs Tilt X"` / `"Abs Tilt Y"`.
   Also record whether the device name ends in `eraser` (case-insensitive): the xf86-input-wacom driver exposes the stylus
   and the eraser as separate devices (`... Pen stylus`, `... Pen eraser`), which is how the eraser end is detected.
4. Re-run step 3 on `XI_HierarchyChanged`.

### 4. Per-frame polling (call `pen_platform_poll()` at the start of `ui_begin_frame`, before `pen_tip` is read)
```
for XPending(dpy) > 0 {
    XNextEvent(dpy, &ev)
    if ev.type == GenericEvent && ev.xcookie.extension == opcode && XGetEventData(dpy, &ev.xcookie) {
        de := (^XIDeviceEvent)(ev.xcookie.data)
        // skip devices that are not tablets (mouse / touchpad): only handle ids from step 3
        switch ev.xcookie.evtype {
        case XI_ButtonPress:   if de.detail == 1 { pen.touching = true;  pen.down_evt = true }
        case XI_ButtonRelease: if de.detail == 1 { pen.touching = false; pen.up_evt = true }
        case XI_Motion, XI_ButtonPress, XI_ButtonRelease: update pos + valuators
        case XI_Enter: pen.in_range = true
        case XI_Leave: pen.in_range = false (if touching, also set up_evt)
        }
        XFreeEventData(dpy, &ev.xcookie)
    }
}
```
- **Position:** `pen.pos = {de.event_x, de.event_y}` (window-relative, floating point). These are physical pixels, the
  same unit `rl.GetMousePosition()` uses, so no scaling is needed.
- **Pressure / tilt:** `de.valuators` is a bitmask plus a packed array holding only the valuators that are *set*. Walk the mask
  bits in order and increment an index for each set bit to find the value. Normalise: `(v - min) / (max - min)`.
  Only update the field if that valuator's bit is set in the event.
- **Eraser:** set `pen.eraser = device_is_eraser[de.deviceid]` on every event.
- **Tip button:** the Wacom driver reports the tip as button 1. Barrel buttons are 2/3 and can be ignored for now.
- **`pen.seen`:** set on the first event from a tablet device.
- Keep the same invariants as the Windows file: `touching` only while the tip is down, `down_evt` / `up_evt` are
  consumed (cleared) in `ui_begin_frame`, and `pen.pressure` is 0 when not touching.

### 5. Build
- `build.sh` needs nothing extra beyond `foreign import "system:Xi"`; document the dev package in the README:
  Debian/Ubuntu `libxi-dev`, Fedora `libXi-devel`, Arch `libxi`.
- `odin check src -target:linux_amd64` already passes today, so run it again after adding the file to catch binding mistakes
  without needing a Linux box.

## Things to be careful about
- **Duplicate input:** the tip still produces ordinary mouse events through GLFW. `ui_begin_frame` already ignores them for the
  left button while `pen_active()` is true, but check that a quick tap does not start a second stroke when the late GLFW
  press arrives.
- **Hover:** `XI_Enter` / `XI_Leave` are about the pointer entering the *window*, not about proximity. If the driver
  reports proximity it is a valuator (`"Abs Proximity"`) or the device's `XI_Motion` stream; the simple fallback is to set
  `in_range` on any pen motion event and clear it on `XI_Leave` or a short timeout.
- **Hotplug / suspend:** re-query devices on `XI_HierarchyChanged`.
- **libinput driver (no xf86-input-wacom):** the same valuator labels exist, but the device may not be split into
  stylus/eraser; the eraser is then signalled by a different tool type. Check `xinput list --long` on the machine.
- **Wayland native:** would need `zwp_tablet_manager_v2` (tool `pressure`, `tilt`, `down`/`up`, `type == eraser`) and the
  `wl_display`/`wl_surface` from GLFW. Treat as a follow-up.

## Test checklist
1. `xinput list` shows the tablet's `stylus` and `eraser` devices; `xinput test-xi2 --root` prints `XI_Motion` with a pressure valuator.
2. Press the pen on a brush with Pressure set to anything but Off: no delay before the first dab, line widens with pressure.
3. Flip to the eraser end with the Brush / Oil tool: it erases.
4. Menus, sliders and the colour picker still work with the pen tip.
5. A quick tap makes exactly one dab, not two strokes.
6. Mouse and trackpad still work with the pen out of range.
7. Unplug and replug the tablet while the app is running.
