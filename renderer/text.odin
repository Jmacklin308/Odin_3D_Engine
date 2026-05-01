package renderer

import eng "../engine"

DEBUG_FONT_GLYPH_W :: f32(5)
DEBUG_FONT_GLYPH_H :: f32(7)
DEBUG_FONT_ADVANCE :: f32(6)
DEBUG_FONT_LINE_ADVANCE :: f32(8)

// Measures a built-in 5x7 debug text block in screen pixels.
Renderer_Measure_Debug_Text :: proc(text: string, scale: f32 = 2.0) -> eng.Vec2 {
	maxCols := 0
	cols    := 0
	lines   := 1

	for i in 0 ..< len(text) {
		if text[i] == '\n' {
			if cols > maxCols do maxCols = cols
			cols = 0
			lines += 1
			continue
		}
		cols += 1
	}
	if cols > maxCols do maxCols = cols

	if maxCols == 0 do return {}
	return {
		f32(maxCols) * DEBUG_FONT_ADVANCE * scale - scale,
		f32(lines) * DEBUG_FONT_LINE_ADVANCE * scale - scale,
	}
}

// Draws a tiny built-in bitmap text overlay. Intended for debug/editor HUD text.
Renderer_Draw_Debug_Text :: proc(
	renderer:   ^Renderer,
	screenSize: eng.Vec2,
	pos:        eng.Vec2,
	text:       string,
	scale:      f32 = 2.0,
	color:      eng.Vec4 = {1, 1, 1, 1},
	drawShadow: bool = true,
) {
	if len(text) == 0 || scale <= 0 do return

	_overlay_begin(renderer, screenSize)
	if drawShadow {
		_debug_text_draw_pass(renderer, pos + eng.Vec2{scale, scale}, text, scale, {0, 0, 0, color.a * 0.85})
	}
	_debug_text_draw_pass(renderer, pos, text, scale, color)
	_overlay_end(renderer)
}

_debug_text_draw_pass :: proc(renderer: ^Renderer, origin: eng.Vec2, text: string, scale: f32, color: eng.Vec4) {
	cursor := origin

	for i in 0 ..< len(text) {
		ch := text[i]
		if ch == '\n' {
			cursor.x = origin.x
			cursor.y += DEBUG_FONT_LINE_ADVANCE * scale
			continue
		}

		_debug_font_draw_glyph(renderer, cursor, scale, _debug_font_normalize_char(ch), color)
		cursor.x += DEBUG_FONT_ADVANCE * scale
	}
}

_debug_font_draw_glyph :: proc(renderer: ^Renderer, pos: eng.Vec2, scale: f32, ch: u8, color: eng.Vec4) {
	if ch == ' ' do return

	glyph := _debug_font_glyph(ch)
	for row in 0 ..< len(glyph) {
		mask := glyph[row]
		if mask == 0 do continue

		runStart := -1
		for col in 0 ..< 5 {
			bit := u8(1 << u32(4 - col))
			filled := mask & bit != 0

			if filled && runStart < 0 {
				runStart = col
			}

			if (!filled || col == 4) && runStart >= 0 {
				runEnd := col
				if filled && col == 4 do runEnd = col + 1

				min := pos + eng.Vec2{f32(runStart) * scale, f32(row) * scale}
				max := min + eng.Vec2{f32(runEnd - runStart) * scale, scale}
				_overlay_draw_rect(renderer, min, max, color)
				runStart = -1
			}
		}
	}
}

_debug_font_normalize_char :: proc(ch: u8) -> u8 {
	if ch >= 'a' && ch <= 'z' do return ch - ('a' - 'A')
	return ch
}

_debug_font_glyph :: proc(ch: u8) -> [7]u8 {
	switch ch {
	case 'A':
		return {0b01110, 0b10001, 0b10001, 0b11111, 0b10001, 0b10001, 0b10001}
	case 'B':
		return {0b11110, 0b10001, 0b10001, 0b11110, 0b10001, 0b10001, 0b11110}
	case 'C':
		return {0b01110, 0b10001, 0b10000, 0b10000, 0b10000, 0b10001, 0b01110}
	case 'D':
		return {0b11110, 0b10001, 0b10001, 0b10001, 0b10001, 0b10001, 0b11110}
	case 'E':
		return {0b11111, 0b10000, 0b10000, 0b11110, 0b10000, 0b10000, 0b11111}
	case 'F':
		return {0b11111, 0b10000, 0b10000, 0b11110, 0b10000, 0b10000, 0b10000}
	case 'G':
		return {0b01110, 0b10001, 0b10000, 0b10111, 0b10001, 0b10001, 0b01111}
	case 'H':
		return {0b10001, 0b10001, 0b10001, 0b11111, 0b10001, 0b10001, 0b10001}
	case 'I':
		return {0b01110, 0b00100, 0b00100, 0b00100, 0b00100, 0b00100, 0b01110}
	case 'J':
		return {0b00001, 0b00001, 0b00001, 0b00001, 0b10001, 0b10001, 0b01110}
	case 'K':
		return {0b10001, 0b10010, 0b10100, 0b11000, 0b10100, 0b10010, 0b10001}
	case 'L':
		return {0b10000, 0b10000, 0b10000, 0b10000, 0b10000, 0b10000, 0b11111}
	case 'M':
		return {0b10001, 0b11011, 0b10101, 0b10101, 0b10001, 0b10001, 0b10001}
	case 'N':
		return {0b10001, 0b11001, 0b10101, 0b10011, 0b10001, 0b10001, 0b10001}
	case 'O':
		return {0b01110, 0b10001, 0b10001, 0b10001, 0b10001, 0b10001, 0b01110}
	case 'P':
		return {0b11110, 0b10001, 0b10001, 0b11110, 0b10000, 0b10000, 0b10000}
	case 'Q':
		return {0b01110, 0b10001, 0b10001, 0b10001, 0b10101, 0b10010, 0b01101}
	case 'R':
		return {0b11110, 0b10001, 0b10001, 0b11110, 0b10100, 0b10010, 0b10001}
	case 'S':
		return {0b01111, 0b10000, 0b10000, 0b01110, 0b00001, 0b00001, 0b11110}
	case 'T':
		return {0b11111, 0b00100, 0b00100, 0b00100, 0b00100, 0b00100, 0b00100}
	case 'U':
		return {0b10001, 0b10001, 0b10001, 0b10001, 0b10001, 0b10001, 0b01110}
	case 'V':
		return {0b10001, 0b10001, 0b10001, 0b10001, 0b10001, 0b01010, 0b00100}
	case 'W':
		return {0b10001, 0b10001, 0b10001, 0b10101, 0b10101, 0b10101, 0b01010}
	case 'X':
		return {0b10001, 0b10001, 0b01010, 0b00100, 0b01010, 0b10001, 0b10001}
	case 'Y':
		return {0b10001, 0b10001, 0b01010, 0b00100, 0b00100, 0b00100, 0b00100}
	case 'Z':
		return {0b11111, 0b00001, 0b00010, 0b00100, 0b01000, 0b10000, 0b11111}
	case '0':
		return {0b01110, 0b10001, 0b10011, 0b10101, 0b11001, 0b10001, 0b01110}
	case '1':
		return {0b00100, 0b01100, 0b00100, 0b00100, 0b00100, 0b00100, 0b01110}
	case '2':
		return {0b01110, 0b10001, 0b00001, 0b00010, 0b00100, 0b01000, 0b11111}
	case '3':
		return {0b11110, 0b00001, 0b00001, 0b01110, 0b00001, 0b00001, 0b11110}
	case '4':
		return {0b00010, 0b00110, 0b01010, 0b10010, 0b11111, 0b00010, 0b00010}
	case '5':
		return {0b11111, 0b10000, 0b10000, 0b11110, 0b00001, 0b00001, 0b11110}
	case '6':
		return {0b01110, 0b10000, 0b10000, 0b11110, 0b10001, 0b10001, 0b01110}
	case '7':
		return {0b11111, 0b00001, 0b00010, 0b00100, 0b01000, 0b01000, 0b01000}
	case '8':
		return {0b01110, 0b10001, 0b10001, 0b01110, 0b10001, 0b10001, 0b01110}
	case '9':
		return {0b01110, 0b10001, 0b10001, 0b01111, 0b00001, 0b00001, 0b01110}
	case '.':
		return {0b00000, 0b00000, 0b00000, 0b00000, 0b00000, 0b00110, 0b00110}
	case ':':
		return {0b00000, 0b00110, 0b00110, 0b00000, 0b00110, 0b00110, 0b00000}
	case '!':
		return {0b00100, 0b00100, 0b00100, 0b00100, 0b00100, 0b00000, 0b00100}
	case '+':
		return {0b00000, 0b00100, 0b00100, 0b11111, 0b00100, 0b00100, 0b00000}
	case '<':
		return {0b00010, 0b00100, 0b01000, 0b10000, 0b01000, 0b00100, 0b00010}
	case '-':
		return {0b00000, 0b00000, 0b00000, 0b01110, 0b00000, 0b00000, 0b00000}
	case '^':
		return {0b00100, 0b01010, 0b10001, 0b00000, 0b00000, 0b00000, 0b00000}
	case '/':
		return {0b00001, 0b00010, 0b00100, 0b01000, 0b10000, 0b00000, 0b00000}
	case '[':
		return {0b01110, 0b01000, 0b01000, 0b01000, 0b01000, 0b01000, 0b01110}
	case ']':
		return {0b01110, 0b00010, 0b00010, 0b00010, 0b00010, 0b00010, 0b01110}
	case '?':
		return {0b01110, 0b10001, 0b00010, 0b00100, 0b00100, 0b00000, 0b00100}
	case ' ':
		return {}
	case:
		return {0b01110, 0b10001, 0b00010, 0b00100, 0b00100, 0b00000, 0b00100}
	}
}
