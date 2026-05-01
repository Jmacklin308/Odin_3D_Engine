package renderer

import "core:math"
import "core:mem"
import eng "../engine"

NOTIFICATION_TEXT_MAX :: 128
NOTIFICATION_MAX      :: 6

Notification_Icon :: enum u8 {
	NONE,
	INFO,
	SUCCESS,
	WARNING,
	ERROR,
	UNDO,
	PLACE,
}

Notification :: struct {
	text:    [NOTIFICATION_TEXT_MAX]u8,
	textLen: int,
	age:     f32,
	life:    f32,
	icon:    Notification_Icon,
	accent:  eng.Vec4,
}

Notification_Tray :: struct {
	items: [dynamic]Notification,
}

Notification_Tray_Init :: proc(tray: ^Notification_Tray) {
	tray^ = {}
	tray.items = make([dynamic]Notification, 0, NOTIFICATION_MAX)
}

Notification_Tray_Shutdown :: proc(tray: ^Notification_Tray) {
	delete(tray.items)
	tray^ = {}
}

Notification_Tray_Push :: proc(
	tray:    ^Notification_Tray,
	message: string,
	icon:    Notification_Icon = .INFO,
	life:    f32 = 2.35,
) {
	if len(tray.items) >= NOTIFICATION_MAX {
		for i in 1 ..< len(tray.items) {
			tray.items[i - 1] = tray.items[i]
		}
		resize(&tray.items, len(tray.items) - 1)
	}

	item: Notification
	item.life   = max(life, 0.65)
	item.icon   = icon
	item.accent = _notification_icon_color(icon)

	copyLen := min(len(message), NOTIFICATION_TEXT_MAX)
	if copyLen > 0 {
		mem.copy(&item.text[0], raw_data(message), copyLen)
	}
	item.textLen = copyLen

	append(&tray.items, item)
}

Notification_Tray_Update :: proc(tray: ^Notification_Tray, dt: f32) {
	i := 0
	for i < len(tray.items) {
		tray.items[i].age += dt
		if tray.items[i].age >= tray.items[i].life {
			for j := i + 1; j < len(tray.items); j += 1 {
				tray.items[j - 1] = tray.items[j]
			}
			resize(&tray.items, len(tray.items) - 1)
			continue
		}
		i += 1
	}
}

Notification_Tray_Render :: proc(tray: ^Notification_Tray, renderer: ^Renderer, screenSize: eng.Vec2, uiScale: f32 = 1.0) {
	if renderer == nil || len(tray.items) == 0 do return

	scale  := clamp(uiScale, 0.75, 1.75)
	margin := f32(18.0) * scale
	gap    := f32(8.0) * scale
	y      := margin

	for idx := len(tray.items) - 1; idx >= 0; idx -= 1 {
		item := &tray.items[idx]
		text := string(item.text[:item.textLen])
		textScale := f32(2.0) * scale
		textSize := Renderer_Measure_Debug_Text(text, textScale)

		iconSpace := f32(0.0)
		if item.icon != .NONE do iconSpace = 28.0 * scale

		padX := f32(12.0) * scale
		padY := f32(8.0) * scale
		w := max(96.0 * scale, textSize.x + iconSpace + padX * 2.0)
		h := max(34.0 * scale, textSize.y + padY * 2.0)

		enterT := eng.Smooth_Step(0, 0.26, item.age)
		exitT  := f32(1.0)
		exitAt := item.life - 0.36
		if item.age > exitAt {
			exitT = 1.0 - eng.Smooth_Step(exitAt, item.life, item.age)
		}
		visibleT := clamp(enterT * exitT, 0, 1)
		slideT   := _notification_back_out(visibleT)
		alpha    := visibleT

		targetX := screenSize.x - margin - w
		x := eng.F32_Lerp(screenSize.x + 24.0, targetX, slideT)
		min := eng.Vec2{x, y}
		max := eng.Vec2{x + w, y + h}

		bg := eng.Vec4{0.025, 0.030, 0.040, 0.72 * alpha}
		edge := item.accent
		edge.a *= 0.82 * alpha
		shine := eng.Vec4{1, 1, 1, 0.08 * alpha}
		shadow := eng.Vec4{0, 0, 0, 0.22 * alpha}

		Renderer_Draw_Screen_Rect(renderer, screenSize, min + eng.Vec2{3, 4} * scale, max + eng.Vec2{3, 4} * scale, shadow)
		Renderer_Draw_Screen_Rect(renderer, screenSize, min, max, bg)
		Renderer_Draw_Screen_Rect(renderer, screenSize, min, {min.x + 3 * scale, max.y}, edge)
		Renderer_Draw_Screen_Rect(renderer, screenSize, min, {max.x, min.y + 1.5 * scale}, shine)

		textX := min.x + padX
		if item.icon != .NONE {
			_notification_draw_icon(renderer, screenSize, item.icon, {min.x + 12 * scale, min.y + h * 0.5}, alpha, item.age, scale)
			textX += iconSpace
		}
		textY := min.y + (h - textSize.y) * 0.5
		Renderer_Draw_Debug_Text(renderer, screenSize, {textX, textY}, text, textScale, {0.96, 0.98, 1.0, 0.95 * alpha}, true)

		y += h + gap
		if idx == 0 do break
	}
}

@(private)
_notification_icon_color :: proc(icon: Notification_Icon) -> eng.Vec4 {
	switch icon {
	case .SUCCESS:
		return {0.24, 0.88, 0.55, 1.0}
	case .WARNING:
		return {1.00, 0.72, 0.20, 1.0}
	case .ERROR:
		return {1.00, 0.28, 0.24, 1.0}
	case .UNDO:
		return {0.18, 0.55, 1.00, 1.0}
	case .PLACE:
		return {0.55, 0.90, 1.00, 1.0}
	case .NONE, .INFO:
		return {0.38, 0.70, 1.00, 1.0}
	}
	return {0.38, 0.70, 1.00, 1.0}
}

@(private)
_notification_draw_icon :: proc(
	renderer:   ^Renderer,
	screenSize: eng.Vec2,
	icon:       Notification_Icon,
	center:     eng.Vec2,
	alpha:      f32,
	age:        f32,
	uiScale:    f32,
) {
	color := _notification_icon_color(icon)
	color.a = 0.92 * alpha
	dim := eng.Vec4{0, 0, 0, 0.24 * alpha}

	s := f32(18.0) * uiScale
	pulse := 1.0 + math.sin(age * 8.0) * 0.045
	min := center - eng.Vec2{s * 0.5 * pulse, s * 0.5 * pulse}
	max := center + eng.Vec2{s * 0.5 * pulse, s * 0.5 * pulse}

	Renderer_Draw_Screen_Rect(renderer, screenSize, min, max, dim)
	Renderer_Draw_Screen_Rect(renderer, screenSize, min + eng.Vec2{2, 2} * uiScale, max - eng.Vec2{2, 2} * uiScale, color)

	markColor := eng.Vec4{1, 1, 1, 0.9 * alpha}
	switch icon {
	case .SUCCESS:
		Renderer_Draw_Debug_Text(renderer, screenSize, min + eng.Vec2{6, 3} * uiScale, "V", 1.5 * uiScale, markColor, false)
	case .WARNING:
		Renderer_Draw_Debug_Text(renderer, screenSize, min + eng.Vec2{6, 3} * uiScale, "!", 1.5 * uiScale, markColor, false)
	case .ERROR:
		Renderer_Draw_Debug_Text(renderer, screenSize, min + eng.Vec2{6, 3} * uiScale, "X", 1.5 * uiScale, markColor, false)
	case .UNDO:
		Renderer_Draw_Debug_Text(renderer, screenSize, min + eng.Vec2{6, 3} * uiScale, "<", 1.5 * uiScale, markColor, false)
	case .PLACE:
		Renderer_Draw_Debug_Text(renderer, screenSize, min + eng.Vec2{6, 3} * uiScale, "+", 1.5 * uiScale, markColor, false)
	case .NONE, .INFO:
		Renderer_Draw_Debug_Text(renderer, screenSize, min + eng.Vec2{6, 3} * uiScale, "I", 1.5 * uiScale, markColor, false)
	}
}

@(private)
_notification_back_out :: proc(t: f32) -> f32 {
	x := clamp(t, 0, 1) - 1.0
	c1 := f32(1.70158)
	c3 := c1 + 1.0
	return 1.0 + c3 * x * x * x + c1 * x * x
}
