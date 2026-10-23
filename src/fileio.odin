package pangolin

import "base:runtime"
import "core:fmt"
import "core:os"
import "core:strings"
import win "core:sys/windows"
import rl "vendor:raylib"

// ---------------------------------------------------------------------------
// Native file dialogs
// ---------------------------------------------------------------------------

Filter :: struct {
	name, pattern: string,
}

FILTERS_OPEN := [?]Filter {
	{"All supported", "*.ppnt;*.png;*.jpg;*.jpeg;*.jfif;*.bmp;*.tga;*.gif;*.qoi;*.gpl"},
	{"Pangolin Paints project (*.ppnt)", "*.ppnt"},
	{"Images", "*.png;*.jpg;*.jpeg;*.jfif;*.bmp;*.tga;*.gif;*.qoi"},
	{"All files", "*.*"},
}
FILTERS_PROJ := [?]Filter{{"Pangolin Paints project (*.ppnt)", "*.ppnt"}}
FILTERS_IMG := [?]Filter{{"Images", "*.png;*.jpg;*.jpeg;*.jfif;*.bmp;*.tga;*.gif;*.qoi"}, {"All files", "*.*"}}
FILTERS_GPL := [?]Filter{{"GIMP palette (*.gpl)", "*.gpl"}, {"All files", "*.*"}}

native_dialog :: proc(save: bool, title: string, filters: []Filter, def_ext, initial: string) -> (path: string, ok: bool) {
	when ODIN_OS == .Windows {
		return native_dialog_windows(save, title, filters, def_ext, initial)
	} else {
		return native_dialog_zenity(save, title, filters, def_ext, initial)
	}
}

when ODIN_OS == .Windows {
	native_dialog_windows :: proc(save: bool, title: string, filters: []Filter, def_ext, initial: string) -> (path: string, ok: bool) {
		buf := make([]u16, 32768, context.temp_allocator)
		if initial != "" {
			w := win.utf8_to_utf16(initial, context.temp_allocator)
			copy(buf[:len(buf) - 1], w)
		}
		fbuf := make([dynamic]u16, context.temp_allocator)
		for f in filters {
			append(&fbuf, ..win.utf8_to_utf16(f.name, context.temp_allocator))
			append(&fbuf, 0)
			append(&fbuf, ..win.utf8_to_utf16(f.pattern, context.temp_allocator))
			append(&fbuf, 0)
		}
		append(&fbuf, 0)
		append(&fbuf, 0)

		ofn := win.OPENFILENAMEW {
			lStructSize  = size_of(win.OPENFILENAMEW),
			hwndOwner    = win.HWND(rl.GetWindowHandle()),
			lpstrFilter  = win.wstring(raw_data(fbuf)),
			lpstrFile    = raw_data(buf),
			nMaxFile     = u32(len(buf)),
			lpstrTitle   = win.utf8_to_wstring(title),
			Flags        = win.OFN_EXPLORER | win.OFN_NOCHANGEDIR | win.OFN_HIDEREADONLY | (save ? win.OFN_OVERWRITEPROMPT : (win.OFN_FILEMUSTEXIST | win.OFN_PATHMUSTEXIST)),
			lpstrDefExt  = def_ext != "" ? win.utf8_to_wstring(def_ext) : nil,
		}
		r := save ? win.GetSaveFileNameW(&ofn) : win.GetOpenFileNameW(&ofn)
		if !r {
			return "", false
		}
		s, err := win.wstring_to_utf8(win.wstring(raw_data(buf)), -1, context.allocator)
		if err != nil {
			return "", false
		}
		return s, true
	}
}

// Linux/BSD file picker backed by the Zenity or KDialog helper if present.
when ODIN_OS != .Windows {
	// Zenity's `--file-filter` wants space-separated globs, e.g. "*.png *.jpg".
	zenity_pattern :: proc(p: string, alloc: runtime.Allocator) -> string {
		out, _ := strings.replace_all(p, ";", " ", alloc)
		return out
	}

	native_dialog_zenity :: proc(save: bool, title: string, filters: []Filter, def_ext, initial: string) -> (path: string, ok: bool) {
		// Zenity
		{
			cmd := make([dynamic]string, context.temp_allocator)
			append(&cmd, "zenity", "--file-selection")
			append(&cmd, fmt.tprintf("--title=%s", title))
			if save {
				append(&cmd, "--save", "--confirm-overwrite")
			}
			if initial != "" {
				append(&cmd, fmt.tprintf("--filename=%s", initial))
			}
			for f in filters {
				pat := zenity_pattern(f.pattern, context.temp_allocator)
				append(&cmd, fmt.tprintf("--file-filter=%s | %s", f.name, pat))
			}
			if out, code, err := run_dialog(cmd[:]); err == nil {
				if code != 0 {
					return "", false
				}
				return clone_trim(out), true
			}
		}
		// KDialog fallback
		{
			cmd := make([dynamic]string, context.temp_allocator)
			append(&cmd, "kdialog", fmt.tprintf("--title=%s", title))
			if save {
				append(&cmd, "--getsavefilename")
			} else {
				append(&cmd, "--getopenfilename")
			}
			dir := initial
			pattern_spec := "All files (*)"
			if len(filters) > 0 {
				pattern_spec = fmt.tprintf("%s (%s)", filters[0].name, zenity_pattern(filters[0].pattern, context.temp_allocator))
			}
			append(&cmd, dir, pattern_spec)
			if out, code, err := run_dialog(cmd[:]); err == nil {
				if code != 0 {
					return "", false
				}
				return clone_trim(out), true
			}
		}
		return "", false
	}

	run_dialog :: proc(cmd: []string) -> (stdout: string, exit_code: int, err: os.Error) {
		state, out, _ := os.process_exec({command = cmd}, context.temp_allocator) or_return
		return string(out), state.exit_code, nil
	}

	clone_trim :: proc(s: string) -> string {
		return strings.clone(strings.trim_space(s))
	}
}

// ---------------------------------------------------------------------------
// Binary helpers
// ---------------------------------------------------------------------------

Writer :: struct {
	b: [dynamic]u8,
}

w8 :: proc(w: ^Writer, v: u8) {
	append(&w.b, v)
}

w16 :: proc(w: ^Writer, v: u16) {
	append(&w.b, u8(v), u8(v >> 8))
}

w32 :: proc(w: ^Writer, v: u32) {
	append(&w.b, u8(v), u8(v >> 8), u8(v >> 16), u8(v >> 24))
}

wstr :: proc(w: ^Writer, s: string) {
	n := min(len(s), 255)
	w8(w, u8(n))
	append(&w.b, ..transmute([]u8)s[:n])
}

wcol :: proc(w: ^Writer, c: Color) {
	append(&w.b, c.r, c.g, c.b, c.a)
}

Reader :: struct {
	d:   []u8,
	pos: int,
	bad: bool,
}

r8 :: proc(r: ^Reader) -> u8 {
	if r.pos >= len(r.d) {
		r.bad = true
		return 0
	}
	v := r.d[r.pos]
	r.pos += 1
	return v
}

r16 :: proc(r: ^Reader) -> u16 {
	a := u16(r8(r))
	b := u16(r8(r))
	return a | b << 8
}

r32 :: proc(r: ^Reader) -> u32 {
	a := u32(r16(r))
	b := u32(r16(r))
	return a | b << 16
}

rstr :: proc(r: ^Reader) -> string {
	n := int(r8(r))
	if r.pos + n > len(r.d) {
		r.bad = true
		return ""
	}
	s := string(r.d[r.pos:r.pos + n])
	r.pos += n
	return s
}

rcol :: proc(r: ^Reader) -> Color {
	c: Color
	c.r = r8(r)
	c.g = r8(r)
	c.b = r8(r)
	c.a = r8(r)
	return c
}

