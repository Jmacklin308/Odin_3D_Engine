package scene

import "core:math"
import eng "../engine"
import rend "../renderer"

Gizmo_Axis :: distinct int

GIZMO_AXIS_NONE :: Gizmo_Axis(0)
GIZMO_AXIS_X    :: Gizmo_Axis(1)
GIZMO_AXIS_Y    :: Gizmo_Axis(2)
GIZMO_AXIS_Z    :: Gizmo_Axis(3)

GIZMO_PIXEL_LENGTH      :: f32(96.0)
GIZMO_HIT_RADIUS_PIXELS :: f32(10.0)
GIZMO_MIN_SCALE         :: f32(0.2)
GIZMO_SHAFT_START       :: f32(0.18)
GIZMO_SHAFT_LENGTH      :: f32(0.62)
GIZMO_SHAFT_RADIUS      :: f32(0.045)
GIZMO_HEAD_LENGTH       :: f32(0.20)
GIZMO_HEAD_RADIUS       :: f32(0.11)
GIZMO_TOTAL_LENGTH      :: f32(GIZMO_SHAFT_START + GIZMO_SHAFT_LENGTH + GIZMO_HEAD_LENGTH)
GIZMO_HIGHLIGHT_MIX     :: f32(0.35)
GIZMO_EPSILON           :: f32(1e-5)

Gizmo_Drag_Entry :: struct {
	id:       EntityID,
	startPos: eng.Vec3,
}

Translate_Gizmo :: struct {
	mesh: rend.Mesh,
	ready: bool,

	hoveredAxis: Gizmo_Axis,
	activeAxis:  Gizmo_Axis,
	dragging:    bool,

	dragPivot:           eng.Vec3,
	dragPlaneNormal:     eng.Vec3,
	dragPivotStart:      eng.Vec3,
	dragStartAxisOffset: f32,
	dragEntries:         [dynamic]Gizmo_Drag_Entry,
}

Translate_Gizmo_Init :: proc(gizmo: ^Translate_Gizmo) -> bool {
	mesh, ok := rend.Mesh_Create_Cube()
	if !ok do return false

	gizmo.mesh        = mesh
	gizmo.ready       = true
	gizmo.dragEntries = make([dynamic]Gizmo_Drag_Entry, 0, 32)
	return true
}

Translate_Gizmo_Shutdown :: proc(gizmo: ^Translate_Gizmo) {
	delete(gizmo.dragEntries)
	if gizmo.ready {
		rend.Mesh_Destroy(&gizmo.mesh)
	}
	gizmo^ = {}
}

Translate_Gizmo_Handle_Input :: proc(
	gizmo:      ^Translate_Gizmo,
	world:      ^World,
	selection:  ^Selection_Set,
	input:      ^eng.Input,
	cam:        ^eng.Camera,
	screenSize: eng.Vec2,
	aspect:     f32,
) -> bool {
	if !gizmo.ready || selection == nil do return false

	pivot, hasSelection := _gizmo_selection_center(world, selection)
	if !hasSelection {
		_gizmo_cancel_drag(gizmo)
		return false
	}

	gizmoScale := _gizmo_world_scale(pivot, cam, screenSize)

	if gizmo.dragging {
		_gizmo_apply_drag(gizmo, world, input.mousePos, screenSize, cam, aspect)
		if eng.Input_Mouse_Released(input, eng.MOUSE_LEFT) || !eng.Input_Mouse_Down(input, eng.MOUSE_LEFT) {
			gizmo.dragging   = false
			gizmo.activeAxis = GIZMO_AXIS_NONE
		}
		return true
	}

	gizmo.hoveredAxis = _gizmo_hit_test(input.mousePos, pivot, gizmoScale, cam, screenSize, aspect)

	if eng.Input_Mouse_Pressed(input, eng.MOUSE_LEFT) && gizmo.hoveredAxis != GIZMO_AXIS_NONE {
		if _gizmo_begin_drag(gizmo, world, selection, gizmo.hoveredAxis, pivot, input.mousePos, screenSize, cam, aspect) {
			return true
		}
	}

	return false
}

Translate_Gizmo_Draw :: proc(
	gizmo:      ^Translate_Gizmo,
	renderer:   ^rend.Renderer,
	world:      ^World,
	selection:  ^Selection_Set,
	cam:        ^eng.Camera,
	screenSize: eng.Vec2,
) {
	if !gizmo.ready || selection == nil do return

	pivot, hasSelection := _gizmo_selection_center(world, selection)
	if !hasSelection do return

	gizmoScale := _gizmo_world_scale(pivot, cam, screenSize)

	rend.Renderer_Use_Default_Shader(renderer)
	_gizmo_draw_axis(gizmo, renderer, pivot, gizmoScale, GIZMO_AXIS_X)
	_gizmo_draw_axis(gizmo, renderer, pivot, gizmoScale, GIZMO_AXIS_Y)
	_gizmo_draw_axis(gizmo, renderer, pivot, gizmoScale, GIZMO_AXIS_Z)
}

@(private)
_gizmo_cancel_drag :: proc(gizmo: ^Translate_Gizmo) {
	gizmo.dragging    = false
	gizmo.hoveredAxis = GIZMO_AXIS_NONE
	gizmo.activeAxis  = GIZMO_AXIS_NONE
	clear(&gizmo.dragEntries)
}

@(private)
_gizmo_begin_drag :: proc(
	gizmo:      ^Translate_Gizmo,
	world:      ^World,
	selection:  ^Selection_Set,
	axis:       Gizmo_Axis,
	pivot:      eng.Vec3,
	mousePos:   eng.Vec2,
	screenSize: eng.Vec2,
	cam:        ^eng.Camera,
	aspect:     f32,
) -> bool {
	if axis == GIZMO_AXIS_NONE do return false
	axisDir := _gizmo_axis_dir(axis)

	viewDir := cam.position - pivot
	if eng.Vec3_Length_Sq(viewDir) <= GIZMO_EPSILON do viewDir = -eng.Camera_Get_Forward(cam)
	planeNormal := viewDir - axisDir * eng.Vec3_Dot(viewDir, axisDir)

	if eng.Vec3_Length_Sq(planeNormal) <= GIZMO_EPSILON {
		fallback := eng.Camera_Get_Right(cam)
		planeNormal = fallback - axisDir * eng.Vec3_Dot(fallback, axisDir)
	}
	if eng.Vec3_Length_Sq(planeNormal) <= GIZMO_EPSILON {
		fallback := eng.VEC3_UP
		planeNormal = fallback - axisDir * eng.Vec3_Dot(fallback, axisDir)
	}
	if eng.Vec3_Length_Sq(planeNormal) <= GIZMO_EPSILON do return false

	planeNormal = eng.Vec3_Normalize(planeNormal)

	rayOrigin, rayDir := Scene_Ray_From_Screen(mousePos, screenSize, cam, aspect)
	hitPos, hit := _ray_plane_intersection(rayOrigin, rayDir, pivot, planeNormal)
	if !hit do return false

	clear(&gizmo.dragEntries)
	required := COMP_TRANSFORM
	for i in 0 ..< world.count {
		if world.generations[i] == 0 do continue
		if world.masks[i] & required != required do continue
		if !Selection_Contains_Index(selection, world, u32(i)) do continue

		append(&gizmo.dragEntries, Gizmo_Drag_Entry{
			id       = World_Entity_ID(world, u32(i)),
			startPos = world.transforms[i].position,
		})
	}
	if len(gizmo.dragEntries) == 0 do return false

	gizmo.dragging            = true
	gizmo.activeAxis          = axis
	gizmo.hoveredAxis         = axis
	gizmo.dragPivot           = pivot
	gizmo.dragPlaneNormal     = planeNormal
	gizmo.dragPivotStart      = pivot
	gizmo.dragStartAxisOffset = eng.Vec3_Dot(hitPos - pivot, axisDir)
	return true
}

@(private)
_gizmo_apply_drag :: proc(
	gizmo:      ^Translate_Gizmo,
	world:      ^World,
	mousePos:   eng.Vec2,
	screenSize: eng.Vec2,
	cam:        ^eng.Camera,
	aspect:     f32,
) {
	if gizmo.activeAxis == GIZMO_AXIS_NONE do return
	axisDir := _gizmo_axis_dir(gizmo.activeAxis)

	rayOrigin, rayDir := Scene_Ray_From_Screen(mousePos, screenSize, cam, aspect)
	hitPos, hit := _ray_plane_intersection(rayOrigin, rayDir, gizmo.dragPivot, gizmo.dragPlaneNormal)
	if !hit do return

	axisOffset := eng.Vec3_Dot(hitPos - gizmo.dragPivot, axisDir) - gizmo.dragStartAxisOffset
	delta := axisDir * axisOffset

	for entry in gizmo.dragEntries {
		transform, ok := World_Get_Transform(world, entry.id)
		if !ok do continue
		transform.position = entry.startPos + delta
	}
}

@(private)
_gizmo_selection_center :: proc(world: ^World, selection: ^Selection_Set) -> (center: eng.Vec3, ok: bool) {
	if selection == nil do return {}, false

	required := COMP_TRANSFORM
	count := 0
	for i in 0 ..< world.count {
		if world.generations[i] == 0 do continue
		if world.masks[i] & required != required do continue
		if !Selection_Contains_Index(selection, world, u32(i)) do continue

		center += world.transforms[i].position
		count += 1
	}

	if count == 0 do return {}, false
	return center / f32(count), true
}

@(private)
_gizmo_hit_test :: proc(
	mousePos:   eng.Vec2,
	gizmoPos:   eng.Vec3,
	gizmoScale: f32,
	cam:        ^eng.Camera,
	screenSize: eng.Vec2,
	aspect:     f32,
) -> Gizmo_Axis {
	bestAxis   := GIZMO_AXIS_NONE
	bestDistSq := GIZMO_HIT_RADIUS_PIXELS * GIZMO_HIT_RADIUS_PIXELS
	viewProj   := eng.Camera_Get_Projection(cam, aspect) * eng.Camera_Get_View(cam)
	axes := [3]Gizmo_Axis{GIZMO_AXIS_X, GIZMO_AXIS_Y, GIZMO_AXIS_Z}

	for i in 0 ..< len(axes) {
		axis := axes[i]
		axisDir := _gizmo_axis_dir(axis)
		startWorld := gizmoPos + axisDir * (GIZMO_SHAFT_START * gizmoScale)
		endWorld   := gizmoPos + axisDir * (GIZMO_TOTAL_LENGTH * gizmoScale)

		startScreen, startVisible := _gizmo_world_to_screen(startWorld, viewProj, screenSize)
		endScreen, endVisible := _gizmo_world_to_screen(endWorld, viewProj, screenSize)
		if !startVisible || !endVisible do continue

		distSq := _point_segment_distance_sq(mousePos, startScreen, endScreen)
		if distSq <= bestDistSq {
			bestDistSq = distSq
			bestAxis = axis
		}
	}

	return bestAxis
}

@(private)
_gizmo_draw_axis :: proc(
	gizmo:      ^Translate_Gizmo,
	renderer:   ^rend.Renderer,
	origin:     eng.Vec3,
	gizmoScale: f32,
	axis:       Gizmo_Axis,
) {
	axisDir := _gizmo_axis_dir(axis)
	color   := _gizmo_axis_color(axis)

	if gizmo.dragging && gizmo.activeAxis == axis {
		color = eng.Vec3_Lerp(color, eng.Vec3{1, 1, 1}, GIZMO_HIGHLIGHT_MIX)
	} else if gizmo.hoveredAxis == axis {
		color = eng.Vec3_Lerp(color, eng.Vec3{1, 1, 1}, GIZMO_HIGHLIGHT_MIX)
	}

	shaftCenter := origin + axisDir * ((GIZMO_SHAFT_START + GIZMO_SHAFT_LENGTH * 0.5) * gizmoScale)
	headCenter  := origin + axisDir * ((GIZMO_SHAFT_START + GIZMO_SHAFT_LENGTH + GIZMO_HEAD_LENGTH * 0.5) * gizmoScale)

	shaftModel := eng.Mat4_Translate(shaftCenter) * eng.Mat4_Scale(_gizmo_box_scale(axis, GIZMO_SHAFT_LENGTH * gizmoScale, GIZMO_SHAFT_RADIUS * gizmoScale))
	headModel  := eng.Mat4_Translate(headCenter)  * eng.Mat4_Scale(_gizmo_box_scale(axis, GIZMO_HEAD_LENGTH * gizmoScale, GIZMO_HEAD_RADIUS * gizmoScale))

	rend.Renderer_Draw_Mesh(renderer, &gizmo.mesh, shaftModel, color)
	rend.Renderer_Draw_Mesh(renderer, &gizmo.mesh, headModel, color)
}

@(private)
_gizmo_box_scale :: proc(axis: Gizmo_Axis, length, radius: f32) -> eng.Vec3 {
	switch axis {
	case GIZMO_AXIS_X:
		return {length, radius, radius}
	case GIZMO_AXIS_Y:
		return {radius, length, radius}
	case GIZMO_AXIS_Z:
		return {radius, radius, length}
	case:
		return eng.VEC3_ONE
	}
}

@(private)
_gizmo_world_scale :: proc(gizmoPos: eng.Vec3, cam: ^eng.Camera, screenSize: eng.Vec2) -> f32 {
	screenHeight := math.max(screenSize.y, 1.0)
	distance := eng.Vec3_Distance(cam.position, gizmoPos)
	distance = math.max(distance, 0.001)

	worldUnitsPerPixel := (2.0 * distance * math.tan(cam.fovY * 0.5)) / screenHeight
	return math.max(worldUnitsPerPixel * GIZMO_PIXEL_LENGTH, GIZMO_MIN_SCALE)
}

@(private)
_gizmo_axis_dir :: proc(axis: Gizmo_Axis) -> eng.Vec3 {
	switch axis {
	case GIZMO_AXIS_X:
		return eng.VEC3_RIGHT
	case GIZMO_AXIS_Y:
		return eng.VEC3_UP
	case GIZMO_AXIS_Z:
		return eng.VEC3_BACK
	case:
		return eng.VEC3_ZERO
	}
}

@(private)
_gizmo_axis_color :: proc(axis: Gizmo_Axis) -> eng.Vec3 {
	switch axis {
	case GIZMO_AXIS_X:
		return {1.0, 0.2, 0.2}
	case GIZMO_AXIS_Y:
		return {0.2, 0.9, 0.2}
	case GIZMO_AXIS_Z:
		return {0.2, 0.45, 1.0}
	case:
		return {1.0, 1.0, 1.0}
	}
}

@(private)
_ray_plane_intersection :: proc(
	rayOrigin, rayDir: eng.Vec3,
	planePoint, planeNormal: eng.Vec3,
) -> (hitPos: eng.Vec3, ok: bool) {
	denom := eng.Vec3_Dot(planeNormal, rayDir)
	if math.abs(denom) <= GIZMO_EPSILON do return {}, false

	t := eng.Vec3_Dot(planePoint - rayOrigin, planeNormal) / denom
	if t < 0 do return {}, false

	return rayOrigin + rayDir * t, true
}

@(private)
_gizmo_world_to_screen :: proc(worldPos: eng.Vec3, viewProj: eng.Mat4, screenSize: eng.Vec2) -> (screenPos: eng.Vec2, visible: bool) {
	clip := viewProj * eng.Vec4{worldPos.x, worldPos.y, worldPos.z, 1.0}
	if clip.w <= GIZMO_EPSILON do return {}, false

	invW := 1.0 / clip.w
	ndcX := clip.x * invW
	ndcY := clip.y * invW
	ndcZ := clip.z * invW
	if ndcZ < -1.0 || ndcZ > 1.0 do return {}, false

	screenPos.x = (ndcX * 0.5 + 0.5) * screenSize.x
	screenPos.y = (1.0 - (ndcY * 0.5 + 0.5)) * screenSize.y
	return screenPos, true
}

@(private)
_point_segment_distance_sq :: proc(point, a, b: eng.Vec2) -> f32 {
	ab := b - a
	abLenSq := eng.Vec2_Dot(ab, ab)
	if abLenSq <= GIZMO_EPSILON {
		diff := point - a
		return eng.Vec2_Dot(diff, diff)
	}

	t := clamp(eng.Vec2_Dot(point - a, ab) / abLenSq, 0.0, 1.0)
	closest := a + ab * t
	diff := point - closest
	return eng.Vec2_Dot(diff, diff)
}
