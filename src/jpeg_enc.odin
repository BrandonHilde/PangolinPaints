package pangolin

import "base:intrinsics"

// Pure-Odin baseline JPEG encoder (stb_image_write is only linked for PNG).
// Writes JFIF: SOI, APP0, DQT, SOF0, DHT, SOS, EOI. YCbCr 4:2:0 or 4:4:4, standard IJG
// quantization tables scaled by quality (libjpeg formula), standard Annex K Huffman
// tables, float AAN forward DCT. Works on one MCU row at a time, so memory use is
// O(width) apart from the output buffer.

// Natural (row-major) index of the k-th coefficient in zigzag order.
@(private = "file")
jpe_ZIGZAG := [64]u8 {
	0, 1, 8, 16, 9, 2, 3, 10, 17, 24, 32, 25, 18, 11, 4, 5,
	12, 19, 26, 33, 40, 48, 41, 34, 27, 20, 13, 6, 7, 14, 21, 28,
	35, 42, 49, 56, 57, 50, 43, 36, 29, 22, 15, 23, 30, 37, 44, 51,
	58, 59, 52, 45, 38, 31, 39, 46, 53, 60, 61, 54, 47, 55, 62, 63,
}

// ITU-T T.81 Annex K.1 quantization tables, natural order.
@(private = "file")
jpe_QUANT_LUM := [64]u8 {
	16, 11, 10, 16, 24, 40, 51, 61,
	12, 12, 14, 19, 26, 58, 60, 55,
	14, 13, 16, 24, 40, 57, 69, 56,
	14, 17, 22, 29, 51, 87, 80, 62,
	18, 22, 37, 56, 68, 109, 103, 77,
	24, 35, 55, 64, 81, 104, 113, 92,
	49, 64, 78, 87, 103, 121, 120, 101,
	72, 92, 95, 98, 112, 100, 103, 99,
}

@(private = "file")
jpe_QUANT_CHR := [64]u8 {
	17, 18, 24, 47, 99, 99, 99, 99,
	18, 21, 26, 66, 99, 99, 99, 99,
	24, 26, 56, 99, 99, 99, 99, 99,
	47, 66, 99, 99, 99, 99, 99, 99,
	99, 99, 99, 99, 99, 99, 99, 99,
	99, 99, 99, 99, 99, 99, 99, 99,
	99, 99, 99, 99, 99, 99, 99, 99,
	99, 99, 99, 99, 99, 99, 99, 99,
}

// Annex K.3 Huffman tables: code counts per length 1..16, then symbols.
@(private = "file")
jpe_DC_LUM_BITS := [16]u8{0, 1, 5, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0}
@(private = "file")
jpe_DC_LUM_VALS := [12]u8{0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11}
@(private = "file")
jpe_DC_CHR_BITS := [16]u8{0, 3, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0}
@(private = "file")
jpe_DC_CHR_VALS := [12]u8{0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11}

@(private = "file")
jpe_AC_LUM_BITS := [16]u8{0, 2, 1, 3, 3, 2, 4, 3, 5, 5, 4, 4, 0, 0, 1, 0x7d}
@(private = "file")
jpe_AC_LUM_VALS := [162]u8 {
	0x01, 0x02, 0x03, 0x00, 0x04, 0x11, 0x05, 0x12, 0x21, 0x31, 0x41, 0x06, 0x13, 0x51, 0x61, 0x07,
	0x22, 0x71, 0x14, 0x32, 0x81, 0x91, 0xa1, 0x08, 0x23, 0x42, 0xb1, 0xc1, 0x15, 0x52, 0xd1, 0xf0,
	0x24, 0x33, 0x62, 0x72, 0x82, 0x09, 0x0a, 0x16, 0x17, 0x18, 0x19, 0x1a, 0x25, 0x26, 0x27, 0x28,
	0x29, 0x2a, 0x34, 0x35, 0x36, 0x37, 0x38, 0x39, 0x3a, 0x43, 0x44, 0x45, 0x46, 0x47, 0x48, 0x49,
	0x4a, 0x53, 0x54, 0x55, 0x56, 0x57, 0x58, 0x59, 0x5a, 0x63, 0x64, 0x65, 0x66, 0x67, 0x68, 0x69,
	0x6a, 0x73, 0x74, 0x75, 0x76, 0x77, 0x78, 0x79, 0x7a, 0x83, 0x84, 0x85, 0x86, 0x87, 0x88, 0x89,
	0x8a, 0x92, 0x93, 0x94, 0x95, 0x96, 0x97, 0x98, 0x99, 0x9a, 0xa2, 0xa3, 0xa4, 0xa5, 0xa6, 0xa7,
	0xa8, 0xa9, 0xaa, 0xb2, 0xb3, 0xb4, 0xb5, 0xb6, 0xb7, 0xb8, 0xb9, 0xba, 0xc2, 0xc3, 0xc4, 0xc5,
	0xc6, 0xc7, 0xc8, 0xc9, 0xca, 0xd2, 0xd3, 0xd4, 0xd5, 0xd6, 0xd7, 0xd8, 0xd9, 0xda, 0xe1, 0xe2,
	0xe3, 0xe4, 0xe5, 0xe6, 0xe7, 0xe8, 0xe9, 0xea, 0xf1, 0xf2, 0xf3, 0xf4, 0xf5, 0xf6, 0xf7, 0xf8,
	0xf9, 0xfa,
}

@(private = "file")
jpe_AC_CHR_BITS := [16]u8{0, 2, 1, 2, 4, 4, 3, 4, 7, 5, 4, 4, 0, 1, 2, 0x77}
@(private = "file")
jpe_AC_CHR_VALS := [162]u8 {
	0x00, 0x01, 0x02, 0x03, 0x11, 0x04, 0x05, 0x21, 0x31, 0x06, 0x12, 0x41, 0x51, 0x07, 0x61, 0x71,
	0x13, 0x22, 0x32, 0x81, 0x08, 0x14, 0x42, 0x91, 0xa1, 0xb1, 0xc1, 0x09, 0x23, 0x33, 0x52, 0xf0,
	0x15, 0x62, 0x72, 0xd1, 0x0a, 0x16, 0x24, 0x34, 0xe1, 0x25, 0xf1, 0x17, 0x18, 0x19, 0x1a, 0x26,
	0x27, 0x28, 0x29, 0x2a, 0x35, 0x36, 0x37, 0x38, 0x39, 0x3a, 0x43, 0x44, 0x45, 0x46, 0x47, 0x48,
	0x49, 0x4a, 0x53, 0x54, 0x55, 0x56, 0x57, 0x58, 0x59, 0x5a, 0x63, 0x64, 0x65, 0x66, 0x67, 0x68,
	0x69, 0x6a, 0x73, 0x74, 0x75, 0x76, 0x77, 0x78, 0x79, 0x7a, 0x82, 0x83, 0x84, 0x85, 0x86, 0x87,
	0x88, 0x89, 0x8a, 0x92, 0x93, 0x94, 0x95, 0x96, 0x97, 0x98, 0x99, 0x9a, 0xa2, 0xa3, 0xa4, 0xa5,
	0xa6, 0xa7, 0xa8, 0xa9, 0xaa, 0xb2, 0xb3, 0xb4, 0xb5, 0xb6, 0xb7, 0xb8, 0xb9, 0xba, 0xc2, 0xc3,
	0xc4, 0xc5, 0xc6, 0xc7, 0xc8, 0xc9, 0xca, 0xd2, 0xd3, 0xd4, 0xd5, 0xd6, 0xd7, 0xd8, 0xd9, 0xda,
	0xe2, 0xe3, 0xe4, 0xe5, 0xe6, 0xe7, 0xe8, 0xe9, 0xea, 0xf2, 0xf3, 0xf4, 0xf5, 0xf6, 0xf7, 0xf8,
	0xf9, 0xfa,
}

// AAN scale factors: cos(k*pi/16) * sqrt(2), k > 0; 1 for k = 0.
@(private = "file")
jpe_AAN := [8]f32{1.0, 1.387039845, 1.306562965, 1.175875602, 1.0, 0.785694958, 0.541196100, 0.275899379}

// Encoder-side Huffman table: code and length per symbol.
@(private = "file")
Jpe_Huff :: struct {
	code: [256]u16,
	size: [256]u8,
}

@(private = "file")
Jpe_Writer :: struct {
	buf:   [dynamic]u8, // len(buf) is the usable capacity; pos is the real length
	pos:   int,
	acc:   u64, // pending bits, right-aligned (only the low `nbits` matter)
	nbits: uint,
}

// Encodes non-premultiplied RGBA pixels (w*h, row-major) as a baseline JFIF JPEG.
// quality 1..100. Transparent pixels are composited over `matte` (usually white).
// chroma_subsample: true = 4:2:0, false = 4:4:4. Returns bytes allocated with `allocator`.
jpeg_encode :: proc(pix: []Color, w, h: int, quality: int, matte := Color{255, 255, 255, 255}, chroma_subsample := true, allocator := context.allocator) -> []u8 {
	if w <= 0 || h <= 0 || w > 65535 || h > 65535 || len(pix) < w * h {
		return nil
	}

	// Quantization tables (libjpeg quality scaling, clamped to baseline 1..255) and the
	// matching reciprocal divisors with the AAN output scaling folded in.
	q := clamp(quality, 1, 100)
	scale := q < 50 ? 5000 / q : 200 - q * 2
	qt: [2][64]u8
	recip: [2][64]f32
	for t in 0 ..< 2 {
		base := t == 0 ? &jpe_QUANT_LUM : &jpe_QUANT_CHR
		for i in 0 ..< 64 {
			v := clamp((int(base[i]) * scale + 50) / 100, 1, 255)
			qt[t][i] = u8(v)
			recip[t][i] = 1 / (f32(v) * jpe_AAN[i >> 3] * jpe_AAN[i & 7] * 8)
		}
	}

	hdc, hac, cdc, cac: Jpe_Huff
	jpe_build_huff(&hdc, jpe_DC_LUM_BITS, jpe_DC_LUM_VALS[:])
	jpe_build_huff(&hac, jpe_AC_LUM_BITS, jpe_AC_LUM_VALS[:])
	jpe_build_huff(&cdc, jpe_DC_CHR_BITS, jpe_DC_CHR_VALS[:])
	jpe_build_huff(&cac, jpe_AC_CHR_BITS, jpe_AC_CHR_VALS[:])

	wr: Jpe_Writer
	wr.buf = make([dynamic]u8, clamp(w * h / 4, 4096, 64 << 20), allocator)

	// --- Headers ---
	jpe_bytes(&wr, {0xFF, 0xD8})
	// APP0 JFIF 1.01, aspect ratio 1:1, no thumbnail.
	jpe_bytes(&wr, {0xFF, 0xE0, 0, 16, 'J', 'F', 'I', 'F', 0, 1, 1, 0, 0, 1, 0, 1, 0, 0})
	// DQT: both 8-bit tables in one segment, zigzag order.
	jpe_bytes(&wr, {0xFF, 0xDB, 0, 132})
	for t in 0 ..< 2 {
		jpe_byte(&wr, u8(t))
		for k in 0 ..< 64 do jpe_byte(&wr, qt[t][jpe_ZIGZAG[k]])
	}
	// SOF0
	samp: u8 = chroma_subsample ? 0x22 : 0x11
	jpe_bytes(&wr, {0xFF, 0xC0, 0, 17, 8, u8(h >> 8), u8(h), u8(w >> 8), u8(w), 3})
	jpe_bytes(&wr, {1, samp, 0, 2, 0x11, 1, 3, 0x11, 1})
	// DHT: all four tables in one segment.
	dht_len := 2 + 4 * 17 + len(jpe_DC_LUM_VALS) + len(jpe_AC_LUM_VALS) + len(jpe_DC_CHR_VALS) + len(jpe_AC_CHR_VALS)
	jpe_bytes(&wr, {0xFF, 0xC4, u8(dht_len >> 8), u8(dht_len)})
	jpe_dht(&wr, 0x00, jpe_DC_LUM_BITS, jpe_DC_LUM_VALS[:])
	jpe_dht(&wr, 0x10, jpe_AC_LUM_BITS, jpe_AC_LUM_VALS[:])
	jpe_dht(&wr, 0x01, jpe_DC_CHR_BITS, jpe_DC_CHR_VALS[:])
	jpe_dht(&wr, 0x11, jpe_AC_CHR_BITS, jpe_AC_CHR_VALS[:])
	// SOS: Y uses tables 0/0, Cb and Cr use 1/1; full spectral range.
	jpe_bytes(&wr, {0xFF, 0xDA, 0, 12, 3, 1, 0x00, 2, 0x11, 3, 0x11, 0, 63, 0})

	// --- Entropy-coded data, one MCU row at a time ---
	mcu := chroma_subsample ? 16 : 8
	pw := (w + mcu - 1) / mcu * mcu // padded strip width
	strip := make([]f32, 3 * pw * mcu) // Y, Cb, Cr planes for this MCU row, level-shifted
	defer delete(strip)
	ys := strip[:pw * mcu]
	cbs := strip[pw * mcu:][:pw * mcu]
	crs := strip[2 * pw * mcu:][:pw * mcu]

	mr, mg, mb := f32(matte.r), f32(matte.g), f32(matte.b)
	pred_y, pred_cb, pred_cr: int
	blk: [64]f32

	for y0 := 0; y0 < h; y0 += mcu {
		// Colour-convert this strip; rows/columns past the image replicate the edge.
		for r in 0 ..< mcu {
			o := r * pw
			if y0 + r >= h {
				src := (h - 1 - y0) * pw
				copy(ys[o:][:pw], ys[src:][:pw])
				copy(cbs[o:][:pw], cbs[src:][:pw])
				copy(crs[o:][:pw], crs[src:][:pw])
				continue
			}
			row := pix[(y0 + r) * w:][:w]
			#no_bounds_check for x in 0 ..< w {
				c := row[x]
				R, G, B := f32(c.r), f32(c.g), f32(c.b)
				if c.a != 255 {
					a := f32(c.a) * (1.0 / 255)
					R = mr + (R - mr) * a
					G = mg + (G - mg) * a
					B = mb + (B - mb) * a
				}
				ys[o + x] = 0.299 * R + 0.587 * G + 0.114 * B - 128
				cbs[o + x] = -0.168735892 * R - 0.331264108 * G + 0.5 * B
				crs[o + x] = 0.5 * R - 0.418687589 * G - 0.081312411 * B
			}
			#no_bounds_check for x in w ..< pw {
				ys[o + x] = ys[o + w - 1]
				cbs[o + x] = cbs[o + w - 1]
				crs[o + x] = crs[o + w - 1]
			}
		}

		for x0 := 0; x0 < pw; x0 += mcu {
			jpe_reserve(&wr, 6 * 512) // worst case per block, stuffing included, is < 512 bytes
			if chroma_subsample {
				for by in 0 ..< 2 {
					for bx in 0 ..< 2 {
						jpe_load(&blk, ys, pw, x0 + bx * 8, by * 8)
						jpe_block(&wr, &blk, &recip[0], &pred_y, &hdc, &hac)
					}
				}
				jpe_load_sub(&blk, cbs, pw, x0)
				jpe_block(&wr, &blk, &recip[1], &pred_cb, &cdc, &cac)
				jpe_load_sub(&blk, crs, pw, x0)
				jpe_block(&wr, &blk, &recip[1], &pred_cr, &cdc, &cac)
			} else {
				jpe_load(&blk, ys, pw, x0, 0)
				jpe_block(&wr, &blk, &recip[0], &pred_y, &hdc, &hac)
				jpe_load(&blk, cbs, pw, x0, 0)
				jpe_block(&wr, &blk, &recip[1], &pred_cb, &cdc, &cac)
				jpe_load(&blk, crs, pw, x0, 0)
				jpe_block(&wr, &blk, &recip[1], &pred_cr, &cdc, &cac)
			}
		}
	}

	// Pad the final partial byte with 1-bits, then EOI.
	jpe_reserve(&wr, 16)
	if wr.nbits > 0 do jpe_bits(&wr, (1 << (8 - wr.nbits)) - 1, 8 - wr.nbits)
	jpe_bytes(&wr, {0xFF, 0xD9})

	non_zero_resize(&wr.buf, wr.pos)
	shrink(&wr.buf)
	return wr.buf[:]
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

@(private = "file")
jpe_build_huff :: proc(t: ^Jpe_Huff, bits: [16]u8, vals: []u8) {
	code: u16
	k := 0
	for l in 1 ..= 16 {
		for _ in 0 ..< int(bits[l - 1]) {
			t.code[vals[k]] = code
			t.size[vals[k]] = u8(l)
			code += 1
			k += 1
		}
		code <<= 1
	}
	assert(k == len(vals))
}

@(private = "file")
jpe_dht :: proc(wr: ^Jpe_Writer, class_id: u8, bits: [16]u8, vals: []u8) {
	jpe_byte(wr, class_id)
	for b in bits do jpe_byte(wr, b)
	for v in vals do jpe_byte(wr, v)
}

@(private = "file")
jpe_reserve :: #force_inline proc(wr: ^Jpe_Writer, n: int) {
	if wr.pos + n > len(wr.buf) {
		non_zero_resize(&wr.buf, max(len(wr.buf) * 2, wr.pos + n))
	}
}

// Raw (unstuffed) byte, for marker segments.
@(private = "file")
jpe_byte :: proc(wr: ^Jpe_Writer, b: u8) {
	jpe_reserve(wr, 1)
	wr.buf[wr.pos] = b
	wr.pos += 1
}

@(private = "file")
jpe_bytes :: proc(wr: ^Jpe_Writer, bs: []u8) {
	for b in bs do jpe_byte(wr, b)
}

// Appends the low `n` bits of `v` (n <= 24) to the entropy-coded stream with 0xFF
// stuffing. Caller must have reserved space.
@(private = "file")
jpe_bits :: #force_inline proc(wr: ^Jpe_Writer, v: u32, n: uint) {
	wr.acc = (wr.acc << n) | u64(v & ((1 << n) - 1))
	wr.nbits += n
	#no_bounds_check for wr.nbits >= 8 {
		wr.nbits -= 8
		b := u8(wr.acc >> wr.nbits)
		wr.buf[wr.pos] = b
		wr.pos += 1
		if b == 0xFF {
			wr.buf[wr.pos] = 0
			wr.pos += 1
		}
	}
}

// Copies an 8x8 block from a strip plane.
@(private = "file")
jpe_load :: #force_inline proc(blk: ^[64]f32, plane: []f32, pw, x, y: int) {
	#no_bounds_check for r in 0 ..< 8 {
		src := plane[(y + r) * pw + x:]
		for c in 0 ..< 8 do blk[r * 8 + c] = src[c]
	}
}

// Builds an 8x8 chroma block by 2x2 box-averaging a 16x16 strip region (4:2:0).
@(private = "file")
jpe_load_sub :: #force_inline proc(blk: ^[64]f32, plane: []f32, pw, x: int) {
	#no_bounds_check for r in 0 ..< 8 {
		s0 := plane[(2 * r) * pw + x:]
		s1 := plane[(2 * r + 1) * pw + x:]
		for c in 0 ..< 8 {
			blk[r * 8 + c] = (s0[2 * c] + s0[2 * c + 1] + s1[2 * c] + s1[2 * c + 1]) * 0.25
		}
	}
}

// Float AAN forward DCT (as in libjpeg's jfdctflt.c), in place. Output is scaled by
// 8 * AAN[u] * AAN[v]; the quantizer reciprocals undo that.
@(private = "file")
jpe_fdct :: #force_inline proc(d: ^[64]f32) {
	#no_bounds_check for pass in 0 ..< 2 {
		step := pass == 0 ? 1 : 8 // rows, then columns
		for i in 0 ..< 8 {
			o := pass == 0 ? i * 8 : i
			d0, d1, d2, d3 := d[o], d[o + step], d[o + 2 * step], d[o + 3 * step]
			d4, d5, d6, d7 := d[o + 4 * step], d[o + 5 * step], d[o + 6 * step], d[o + 7 * step]

			tmp0, tmp7 := d0 + d7, d0 - d7
			tmp1, tmp6 := d1 + d6, d1 - d6
			tmp2, tmp5 := d2 + d5, d2 - d5
			tmp3, tmp4 := d3 + d4, d3 - d4

			// Even part
			tmp10, tmp13 := tmp0 + tmp3, tmp0 - tmp3
			tmp11, tmp12 := tmp1 + tmp2, tmp1 - tmp2
			d[o] = tmp10 + tmp11
			d[o + 4 * step] = tmp10 - tmp11
			z1 := (tmp12 + tmp13) * 0.707106781
			d[o + 2 * step] = tmp13 + z1
			d[o + 6 * step] = tmp13 - z1

			// Odd part
			tmp10 = tmp4 + tmp5
			tmp11 = tmp5 + tmp6
			tmp12 = tmp6 + tmp7
			z5 := (tmp10 - tmp12) * 0.382683433
			z2 := 0.541196100 * tmp10 + z5
			z4 := 1.306562965 * tmp12 + z5
			z3 := tmp11 * 0.707106781
			z11, z13 := tmp7 + z3, tmp7 - z3
			d[o + 5 * step] = z13 + z2
			d[o + 3 * step] = z13 - z2
			d[o + 1 * step] = z11 + z4
			d[o + 7 * step] = z11 - z4
		}
	}
}

// Number of bits needed for |v| (the JPEG magnitude category).
@(private = "file")
jpe_nbits :: #force_inline proc(v: i32) -> uint {
	a := u32(v < 0 ? -v : v)
	return uint(32 - intrinsics.count_leading_zeros(a))
}

// DCT, quantize and Huffman-code one block.
@(private = "file")
jpe_block :: proc(wr: ^Jpe_Writer, blk: ^[64]f32, recip: ^[64]f32, pred: ^int, dc, ac: ^Jpe_Huff) {
	jpe_fdct(blk)
	zz: [64]i32
	#no_bounds_check for k in 0 ..< 64 {
		n := jpe_ZIGZAG[k]
		// libjpeg's offset trick: round half up without a branch.
		zz[k] = i32(blk[n] * recip[n] + 16384.5) - 16384
	}
	// Keep AC within the baseline range (category <= 10); only extreme q=100 edge cases
	// can exceed it.
	#no_bounds_check for k in 1 ..< 64 do zz[k] = clamp(zz[k], -1023, 1023)

	// DC: difference from the previous block of this component.
	diff := zz[0] - i32(pred^)
	pred^ = int(zz[0])
	s := jpe_nbits(diff)
	jpe_bits(wr, u32(dc.code[s]), uint(dc.size[s]))
	if s > 0 do jpe_bits(wr, u32(diff < 0 ? diff - 1 : diff), s)

	// AC: (run, size) symbols, ZRL for runs of 16 zeros, EOB after the last nonzero.
	run: u32
	#no_bounds_check for k in 1 ..< 64 {
		v := zz[k]
		if v == 0 {
			run += 1
			continue
		}
		for run > 15 {
			jpe_bits(wr, u32(ac.code[0xF0]), uint(ac.size[0xF0]))
			run -= 16
		}
		s = jpe_nbits(v)
		sym := (run << 4) | u32(s)
		jpe_bits(wr, u32(ac.code[sym]), uint(ac.size[sym]))
		jpe_bits(wr, u32(v < 0 ? v - 1 : v), s)
		run = 0
	}
	if run > 0 do jpe_bits(wr, u32(ac.code[0]), uint(ac.size[0]))
}
