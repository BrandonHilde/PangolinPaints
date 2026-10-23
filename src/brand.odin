package pangolin

import rl "vendor:raylib"

APP_NAME :: "Pangolin Paints"
APP_TAGLINE :: "Brushstrokes, scale by scale."

LOGO_SIZE :: 16

// Pixel-art pangolin facing left, holding a paintbrush with a wet tip.
// Characters map to colours in `logo_color`.
LOGO_ART := [LOGO_SIZE]string {
	"...........r....",
	"..........rr....",
	".........kk.....",
	"......oooook....",
	"....ooddbbkdoo..",
	"...oddbbddkbddo.",
	"..oddbbddbkddbbo",
	"..obbddbbdkbbddo",
	".oobddbbddkbddbo",
	"ossoobbddbkddbo.",
	"osswoddbbdldbo..",
	".osssllooolooo..",
	"..ooollo.ol.ol..",
	"....ol.o.ol.ol..",
	"....oo.o.oo.oo..",
	"..yy.bb.rr.gg...",
}

logo_color :: proc(ch: u8) -> (c: Color, ok: bool) {
	switch ch {
	case 'o':
		return Color{46, 32, 24, 255}, true
	case 'd':
		return Color{139, 94, 60, 255}, true
	case 'b':
		return Color{192, 140, 86, 255}, true
	case 'l':
		return Color{224, 185, 136, 255}, true
	case 's':
		return Color{240, 217, 181, 255}, true
	case 'w':
		return Color{255, 255, 255, 255}, true
	case 'k':
		return Color{120, 72, 40, 255}, true // brush handle
	case 'r':
		return Color{214, 64, 52, 255}, true
	case 'y':
		return Color{240, 196, 60, 255}, true
	case 'g':
		return Color{70, 150, 90, 255}, true
	}
	return {}, false
}

logo_tex: rl.Texture2D

logo_image :: proc() -> rl.Image {
	img := rl.GenImageColor(LOGO_SIZE, LOGO_SIZE, rl.BLANK)
	for row, y in LOGO_ART {
		for x in 0 ..< len(row) {
			if c, ok := logo_color(row[x]); ok {
				rl.ImageDrawPixel(&img, i32(x), i32(y), c)
			}
		}
	}
	return img
}

// Window icon and the texture used by the About dialog.
brand_init :: proc() {
	img := logo_image()
	logo_tex = rl.LoadTextureFromImage(img)
	rl.SetTextureFilter(logo_tex, .POINT)
	big := rl.ImageCopy(img)
	rl.ImageResizeNN(&big, 64, 64)
	rl.SetWindowIcon(big)
	rl.UnloadImage(big)
	rl.UnloadImage(img)
}

// Draws the logo at an integer scale.
logo_draw :: proc(x, y, scale: i32) {
	rl.DrawTexturePro(
		logo_tex,
		{0, 0, LOGO_SIZE, LOGO_SIZE},
		{f32(x), f32(y), f32(LOGO_SIZE * scale), f32(LOGO_SIZE * scale)},
		{},
		0,
		rl.WHITE,
	)
}
