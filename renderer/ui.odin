package renderer

import "core:math"
import eng "../engine"

UI_Rect :: struct {
	x, y, w, h: f32,
}

UI_Theme :: struct {
	panel:        eng.Vec4,
	panelAccent:  eng.Vec4,
	text:         eng.Vec4,
	textMuted:    eng.Vec4,
	button:       eng.Vec4,
	buttonHover:  eng.Vec4,
	buttonActive: eng.Vec4,
	buttonOn:     eng.Vec4,
	shadow:       eng.Vec4,
}

UI_DEFAULT_THEME :: UI_Theme{
	panel        = {0.025, 0.032, 0.045, 0.86},
	panelAccent  = {0.20, 0.58, 0.78, 0.92},
	text         = {0.94, 0.97, 1.00, 1.00},
	textMuted    = {0.58, 0.66, 0.74, 1.00},
	button       = {0.10, 0.13, 0.17, 0.92},
	buttonHover  = {0.16, 0.22, 0.28, 0.96},
	buttonActive = {0.05, 0.34, 0.48, 0.98},
	buttonOn     = {0.09, 0.47, 0.62, 0.98},
	shadow       = {0.00, 0.00, 0.00, 0.32},
}

@(private)
UI_Widget_State :: struct {
	id:      u64,
	hoverT:  f32,
	activeT: f32,
}

@(private)
UI_Rect_Command :: struct {
	min:   eng.Vec2,
	max:   eng.Vec2,
	color: eng.Vec4,
}

@(private)
UI_Text_Command :: struct {
	pos:    eng.Vec2,
	text:   string,
	scale:  f32,
	color:  eng.Vec4,
	shadow: bool,
}

@(private)
UI_Model_Command :: struct {
	mesh:  ^Mesh,
	min:   eng.Vec2,
	max:   eng.Vec2,
	angle: f32,
	color: eng.Vec3,
}

UI_Context :: struct {
	renderer:   ^Renderer,
	input:      ^eng.Input,
	screenSize: eng.Vec2,
	dt:         f32,
	time:       f32,
	theme:     UI_Theme,

	hot:           u64,
	active:        u64,
	mouseCaptured: bool,

	states: [dynamic]UI_Widget_State,
	rects:  [dynamic]UI_Rect_Command,
	models: [dynamic]UI_Model_Command,
	texts:  [dynamic]UI_Text_Command,
}

UI_Init :: proc(ctx: ^UI_Context, theme: UI_Theme = UI_DEFAULT_THEME) {
	ctx^ = {}
	ctx.theme = theme
	ctx.states = make([dynamic]UI_Widget_State, 0, 64)
	ctx.rects  = make([dynamic]UI_Rect_Command, 0, 128)
	ctx.models = make([dynamic]UI_Model_Command, 0, 32)
	ctx.texts  = make([dynamic]UI_Text_Command, 0, 64)
}

UI_Shutdown :: proc(ctx: ^UI_Context) {
	delete(ctx.states)
	delete(ctx.rects)
	delete(ctx.models)
	delete(ctx.texts)
	ctx^ = {}
}

UI_Begin :: proc(ctx: ^UI_Context, renderer: ^Renderer, screenSize: eng.Vec2, input: ^eng.Input, dt: f32) {
	ctx.renderer      = renderer
	ctx.input         = input
	ctx.screenSize    = screenSize
	ctx.dt            = dt
	ctx.time         += dt
	ctx.hot           = 0
	ctx.mouseCaptured = ctx.active != 0
	clear(&ctx.rects)
	clear(&ctx.models)
	clear(&ctx.texts)
}

UI_End :: proc(ctx: ^UI_Context) {
	// Reserved for future clipping/navigation passes. Kept so callers get a
	// tidy Begin/End rhythm similar to raylib-style immediate APIs.
	if ctx.input != nil && eng.Input_Mouse_Released(ctx.input, eng.MOUSE_LEFT) {
		ctx.active = 0
	}
}

UI_Render :: proc(ctx: ^UI_Context) {
	if ctx.renderer == nil do return

	for cmd in ctx.rects {
		Renderer_Draw_Screen_Rect(ctx.renderer, ctx.screenSize, cmd.min, cmd.max, cmd.color)
	}
	for cmd in ctx.models {
		Renderer_Draw_Mesh_Preview(ctx.renderer, cmd.mesh, ctx.screenSize, cmd.min, cmd.max, cmd.angle, cmd.color)
	}
	for cmd in ctx.texts {
		Renderer_Draw_Debug_Text(ctx.renderer, ctx.screenSize, cmd.pos, cmd.text, cmd.scale, cmd.color, cmd.shadow)
	}
}

UI_Wants_Mouse :: proc(ctx: ^UI_Context) -> bool {
	return ctx.mouseCaptured || ctx.hot != 0 || ctx.active != 0
}

UI_Panel :: proc(ctx: ^UI_Context, rect: UI_Rect) {
	min, max := _ui_rect_bounds(rect)
	_ui_queue_rect(ctx, min + eng.Vec2{4, 5}, max + eng.Vec2{4, 5}, ctx.theme.shadow)
	_ui_queue_rect(ctx, min, max, ctx.theme.panel)
	_ui_queue_rect(ctx, min, {max.x, min.y + 3}, ctx.theme.panelAccent)
}

UI_Rect_Fill :: proc(ctx: ^UI_Context, rect: UI_Rect, color: eng.Vec4) {
	min, max := _ui_rect_bounds(rect)
	_ui_queue_rect(ctx, min, max, color)
}

UI_Model_Preview :: proc(ctx: ^UI_Context, rect: UI_Rect, mesh: ^Mesh, angle: f32, color: eng.Vec3 = {0.8, 0.4, 0.2}) {
	min, max := _ui_rect_bounds(rect)
	append(&ctx.models, UI_Model_Command{mesh = mesh, min = min, max = max, angle = angle, color = color})
}

UI_Label :: proc(ctx: ^UI_Context, pos: eng.Vec2, text: string, scale: f32 = 2.0, color: eng.Vec4 = UI_DEFAULT_THEME.text) {
	_ui_queue_text(ctx, pos, text, scale, color, true)
}

UI_Time :: proc(ctx: ^UI_Context) -> f32 {
	return ctx.time
}

UI_Hover_Amount :: proc(ctx: ^UI_Context, id: string) -> f32 {
	hash := _ui_hash_string(id)
	for i in 0 ..< len(ctx.states) {
		if ctx.states[i].id == hash do return ctx.states[i].hoverT
	}
	return 0
}

UI_Button :: proc(ctx: ^UI_Context, id: string, rect: UI_Rect, text: string, selected: bool = false) -> bool {
	hash := _ui_hash_string(id)
	state := _ui_state(ctx, hash)
	min, max := _ui_rect_bounds(rect)

	hovered := ctx.input != nil && _ui_point_in_rect(ctx.input.mousePos, min, max)
	pressed := hovered && ctx.input != nil && eng.Input_Mouse_Pressed(ctx.input, eng.MOUSE_LEFT)
	released := hovered && ctx.input != nil && eng.Input_Mouse_Released(ctx.input, eng.MOUSE_LEFT)

	if hovered {
		ctx.hot = hash
		ctx.mouseCaptured = true
	}
	if pressed {
		ctx.active = hash
		ctx.mouseCaptured = true
	}

	isActive := ctx.active == hash
	clicked := isActive && released

	hoverTarget := hovered ? f32(1) : f32(0)
	activeTarget := (isActive || selected) ? f32(1) : f32(0)
	state.hoverT  = _ui_approach(state.hoverT, hoverTarget, ctx.dt, 13.0)
	state.activeT = _ui_approach(state.activeT, activeTarget, ctx.dt, 16.0)

	lift := -2.0 * state.hoverT + 2.0 * state.activeT
	drawMin := min + eng.Vec2{0, lift}
	drawMax := max + eng.Vec2{0, lift}

	base := selected ? ctx.theme.buttonOn : ctx.theme.button
	bg := _ui_color_lerp(base, ctx.theme.buttonHover, state.hoverT)
	bg = _ui_color_lerp(bg, ctx.theme.buttonActive, state.activeT * 0.65)

	_ui_queue_rect(ctx, drawMin + eng.Vec2{3, 4}, drawMax + eng.Vec2{3, 4}, ctx.theme.shadow)
	_ui_queue_rect(ctx, drawMin, drawMax, bg)
	_ui_queue_rect(ctx, drawMin, {drawMax.x, drawMin.y + 2}, _ui_color_lerp(ctx.theme.panelAccent, ctx.theme.text, state.hoverT * 0.35))

	textScale := f32(2.0)
	textSize := Renderer_Measure_Debug_Text(text, textScale)
	textPos := eng.Vec2{
		drawMin.x + (rect.w - textSize.x) * 0.5,
		drawMin.y + (rect.h - textSize.y) * 0.5,
	}
	_ui_queue_text(ctx, textPos, text, textScale, ctx.theme.text, true)

	return clicked
}

_ui_rect_bounds :: proc(rect: UI_Rect) -> (min, max: eng.Vec2) {
	min = {rect.x, rect.y}
	max = {rect.x + rect.w, rect.y + rect.h}
	return
}

_ui_queue_rect :: proc(ctx: ^UI_Context, min, max: eng.Vec2, color: eng.Vec4) {
	append(&ctx.rects, UI_Rect_Command{min = min, max = max, color = color})
}

_ui_queue_text :: proc(ctx: ^UI_Context, pos: eng.Vec2, text: string, scale: f32, color: eng.Vec4, shadow: bool) {
	append(&ctx.texts, UI_Text_Command{pos = pos, text = text, scale = scale, color = color, shadow = shadow})
}

_ui_state :: proc(ctx: ^UI_Context, id: u64) -> ^UI_Widget_State {
	for i in 0 ..< len(ctx.states) {
		if ctx.states[i].id == id do return &ctx.states[i]
	}
	append(&ctx.states, UI_Widget_State{id = id})
	return &ctx.states[len(ctx.states) - 1]
}

_ui_point_in_rect :: proc(point, min, max: eng.Vec2) -> bool {
	return point.x >= min.x && point.y >= min.y && point.x <= max.x && point.y <= max.y
}

_ui_approach :: proc(current, target, dt, speed: f32) -> f32 {
	t := 1.0 - math.pow(f32(0.5), dt * speed)
	return eng.F32_Lerp(current, target, clamp(t, 0, 1))
}

_ui_color_lerp :: proc(a, b: eng.Vec4, t: f32) -> eng.Vec4 {
	mixT := clamp(t, 0, 1)
	return {
		eng.F32_Lerp(a.x, b.x, mixT),
		eng.F32_Lerp(a.y, b.y, mixT),
		eng.F32_Lerp(a.z, b.z, mixT),
		eng.F32_Lerp(a.w, b.w, mixT),
	}
}

_ui_hash_string :: proc(s: string) -> u64 {
	hash := u64(14695981039346656037)
	for i in 0 ..< len(s) {
		hash = (hash ~ u64(s[i])) * 1099511628211
	}
	return hash
}
