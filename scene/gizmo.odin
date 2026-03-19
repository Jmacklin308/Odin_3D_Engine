package scene

import "core:math"
import eng "../engine"
import rend "../renderer"

Gizmo_Mode :: distinct int

GIZMO_MODE_TRANSLATE :: Gizmo_Mode(0)
GIZMO_MODE_ROTATE    :: Gizmo_Mode(1)
GIZMO_MODE_SCALE     :: Gizmo_Mode(2)

Gizmo_Axis :: distinct int

GIZMO_AXIS_NONE :: Gizmo_Axis(0)
GIZMO_AXIS_X    :: Gizmo_Axis(1)
GIZMO_AXIS_Y    :: Gizmo_Axis(2)
GIZMO_AXIS_Z    :: Gizmo_Axis(3)

Gizmo_Handle :: distinct int

GIZMO_HANDLE_NONE          :: Gizmo_Handle(0)
GIZMO_HANDLE_TRANSLATE_X   :: Gizmo_Handle(1)
GIZMO_HANDLE_TRANSLATE_Y   :: Gizmo_Handle(2)
GIZMO_HANDLE_TRANSLATE_Z   :: Gizmo_Handle(3)
GIZMO_HANDLE_ROTATE_X      :: Gizmo_Handle(4)
GIZMO_HANDLE_ROTATE_Y      :: Gizmo_Handle(5)
GIZMO_HANDLE_ROTATE_Z      :: Gizmo_Handle(6)
GIZMO_HANDLE_SCALE_X       :: Gizmo_Handle(7)
GIZMO_HANDLE_SCALE_Y       :: Gizmo_Handle(8)
GIZMO_HANDLE_SCALE_Z       :: Gizmo_Handle(9)
GIZMO_HANDLE_SCALE_UNIFORM :: Gizmo_Handle(10)
GIZMO_HANDLE_TRANSLATE_XY  :: Gizmo_Handle(11) // drag in XY plane (Z is excluded)
GIZMO_HANDLE_TRANSLATE_XZ  :: Gizmo_Handle(12) // drag in XZ plane (Y is excluded)
GIZMO_HANDLE_TRANSLATE_YZ  :: Gizmo_Handle(13) // drag in YZ plane (X is excluded)

GIZMO_PIXEL_LENGTH          :: f32(96.0)
GIZMO_HIT_RADIUS_PIXELS     :: f32(10.0)
GIZMO_MIN_SCALE             :: f32(0.2)
GIZMO_HIGHLIGHT_MIX         :: f32(0.35)
GIZMO_EPSILON               :: f32(1e-5)

GIZMO_TRANSLATE_SHAFT_START  :: f32(0.18)
GIZMO_TRANSLATE_SHAFT_LENGTH :: f32(0.62)
GIZMO_TRANSLATE_SHAFT_RADIUS :: f32(0.045)
GIZMO_TRANSLATE_HEAD_LENGTH  :: f32(0.20)
GIZMO_TRANSLATE_HEAD_RADIUS  :: f32(0.11)
GIZMO_TRANSLATE_TOTAL_LENGTH :: f32(GIZMO_TRANSLATE_SHAFT_START + GIZMO_TRANSLATE_SHAFT_LENGTH + GIZMO_TRANSLATE_HEAD_LENGTH)

GIZMO_TRANSLATE_PLANE_OFFSET    :: f32(0.26)  // distance from origin along each of the two axes
GIZMO_TRANSLATE_PLANE_SIZE      :: f32(0.22)  // visual side length of the square
GIZMO_TRANSLATE_PLANE_THICKNESS :: f32(0.03)  // visual depth of the flat quad
GIZMO_TRANSLATE_PLANE_HIT_SIZE  :: f32(0.28)  // hit-test half-extent (slightly larger than visual)

GIZMO_ROTATE_RADIUS      :: f32(1.02)
GIZMO_ROTATE_THICKNESS   :: f32(0.04)
GIZMO_ROTATE_SEGMENT_ARC :: f32(0.95)
GIZMO_ROTATE_SEGMENTS    :: 48
GIZMO_ROTATE_ARM_LENGTH  :: f32(0.9)
GIZMO_ROTATE_ARM_RADIUS  :: f32(0.03)
GIZMO_ROTATE_ARROW_LENGTH :: f32(0.22)
GIZMO_ROTATE_ARROW_RADIUS :: f32(0.06)

GIZMO_SCALE_SHAFT_START   :: f32(0.18)
GIZMO_SCALE_SHAFT_LENGTH  :: f32(0.48)
GIZMO_SCALE_SHAFT_RADIUS  :: f32(0.035)
GIZMO_SCALE_CUBE_OFFSET   :: f32(0.78)
GIZMO_SCALE_CUBE_SIZE     :: f32(0.14)
GIZMO_SCALE_CENTER_SIZE   :: f32(0.18)
GIZMO_SCALE_MIN_FACTOR    :: f32(0.05)
GIZMO_ENTITY_MIN_SCALE    :: f32(0.01)
GIZMO_UNIFORM_DRAG_PIXELS :: f32(72.0)

Gizmo_Drag_Entry :: struct {
	id:         EntityID,
	startPos:   eng.Vec3,
	startRot:   eng.Quat,
	startScale: eng.Vec3,
}

Transform_Gizmo :: struct {
	mesh:  rend.Mesh,
	ready: bool,
	mode:  Gizmo_Mode,

	hoveredHandle: Gizmo_Handle,
	activeHandle:  Gizmo_Handle,
	dragging:      bool,

	dragPivot:           eng.Vec3,
	dragPlaneNormal:     eng.Vec3,
	dragPivotStart:      eng.Vec3,
	dragStartAxisOffset: f32,
	dragPlaneHitStart:   eng.Vec3, // world-space hit position when a plane handle drag begins

	dragStartMousePos: eng.Vec2,
	dragPrevMousePos:  eng.Vec2,
	dragScreenDir:     eng.Vec2,
	dragPixelsToUnit:  f32,

	rotateStartRadial:   eng.Vec3,
	rotateCurrentRadial: eng.Vec3,
	rotateAccumAngle:    f32,

	dragEntries: [dynamic]Gizmo_Drag_Entry,
}

Transform_Gizmo_Init :: proc(gizmo: ^Transform_Gizmo) -> bool {
	mesh, ok := rend.Mesh_Create_Cube()
	if !ok do return false

	gizmo.mesh        = mesh
	gizmo.ready       = true
	gizmo.mode        = GIZMO_MODE_TRANSLATE
	gizmo.dragEntries = make([dynamic]Gizmo_Drag_Entry, 0, 32)
	return true
}

Transform_Gizmo_Shutdown :: proc(gizmo: ^Transform_Gizmo) {
	delete(gizmo.dragEntries)
	if gizmo.ready {
		rend.Mesh_Destroy(&gizmo.mesh)
	}
	gizmo^ = {}
}

Transform_Gizmo_Set_Mode :: proc(gizmo: ^Transform_Gizmo, mode: Gizmo_Mode) {
	if gizmo.dragging do return
	gizmo.mode          = mode
	gizmo.hoveredHandle = GIZMO_HANDLE_NONE
	gizmo.activeHandle  = GIZMO_HANDLE_NONE
}

Transform_Gizmo_Get_Mode :: proc(gizmo: ^Transform_Gizmo) -> Gizmo_Mode {
	return gizmo.mode
}

Transform_Gizmo_Is_Dragging :: proc(gizmo: ^Transform_Gizmo) -> bool {
	return gizmo.dragging
}

Transform_Gizmo_Mode_Label :: proc(mode: Gizmo_Mode) -> string {
	switch mode {
	case GIZMO_MODE_TRANSLATE:
		return "MOVE"
	case GIZMO_MODE_ROTATE:
		return "ROTATE"
	case GIZMO_MODE_SCALE:
		return "SCALE"
	case:
		return "UNKNOWN"
	}
}

Transform_Gizmo_Handle_Input :: proc(
	gizmo:      ^Transform_Gizmo,
	world:      ^World,
	selection:  ^Selection_Set,
	input:      ^eng.Input,
	cam:        ^eng.Camera,
	screenSize: eng.Vec2,
	aspect:     f32,
) -> (captured: bool, committed: bool) {
	if !gizmo.ready || selection == nil do return false, false

	pivot, hasSelection := _gizmo_selection_center(world, selection)
	if !hasSelection {
		_gizmo_cancel_drag(gizmo)
		return false, false
	}

	gizmoScale := _gizmo_world_scale(pivot, cam, screenSize)

	if gizmo.dragging {
		switch gizmo.mode {
		case GIZMO_MODE_TRANSLATE:
			_gizmo_apply_translate_drag(gizmo, world, input.mousePos, screenSize, cam, aspect)
		case GIZMO_MODE_ROTATE:
			_gizmo_apply_rotate_drag(gizmo, world, input.mousePos, screenSize, cam, aspect, gizmoScale)
		case GIZMO_MODE_SCALE:
			_gizmo_apply_scale_drag(gizmo, world, input.mousePos)
		}

		if eng.Input_Mouse_Released(input, eng.MOUSE_LEFT) || !eng.Input_Mouse_Down(input, eng.MOUSE_LEFT) {
			gizmo.dragging         = false
			gizmo.activeHandle     = GIZMO_HANDLE_NONE
			gizmo.hoveredHandle    = GIZMO_HANDLE_NONE
			gizmo.rotateAccumAngle = 0
			return true, true // drag just ended — caller should commit to undo history
		}
		return true, false
	}

	gizmo.hoveredHandle = _gizmo_hit_test(gizmo.mode, pivot, gizmoScale, input.mousePos, cam, screenSize, aspect)

	if eng.Input_Mouse_Pressed(input, eng.MOUSE_LEFT) && gizmo.hoveredHandle != GIZMO_HANDLE_NONE {
		if _gizmo_begin_drag(gizmo, world, selection, gizmo.hoveredHandle, pivot, gizmoScale, input.mousePos, screenSize, cam, aspect) {
			return true, false
		}
	}

	return false, false
}

Transform_Gizmo_Draw :: proc(
	gizmo:      ^Transform_Gizmo,
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
	rend.Renderer_Set_Depth_Test(false)
	switch gizmo.mode {
	case GIZMO_MODE_TRANSLATE:
		_gizmo_draw_translate(gizmo, renderer, pivot, gizmoScale)
	case GIZMO_MODE_ROTATE:
		_gizmo_draw_rotate(gizmo, renderer, pivot, gizmoScale)
	case GIZMO_MODE_SCALE:
		_gizmo_draw_scale(gizmo, renderer, pivot, gizmoScale)
	}
	rend.Renderer_Set_Depth_Test(true)
}

Translate_Gizmo :: Transform_Gizmo

Translate_Gizmo_Init         :: Transform_Gizmo_Init
Translate_Gizmo_Shutdown     :: Transform_Gizmo_Shutdown
Translate_Gizmo_Handle_Input :: Transform_Gizmo_Handle_Input
Translate_Gizmo_Draw         :: Transform_Gizmo_Draw

@(private)
_gizmo_cancel_drag :: proc(gizmo: ^Transform_Gizmo) {
	gizmo.dragging         = false
	gizmo.hoveredHandle    = GIZMO_HANDLE_NONE
	gizmo.activeHandle     = GIZMO_HANDLE_NONE
	gizmo.rotateAccumAngle = 0
	clear(&gizmo.dragEntries)
}

@(private)
_gizmo_begin_drag :: proc(
	gizmo:      ^Transform_Gizmo,
	world:      ^World,
	selection:  ^Selection_Set,
	handle:     Gizmo_Handle,
	pivot:      eng.Vec3,
	gizmoScale: f32,
	mousePos:   eng.Vec2,
	screenSize: eng.Vec2,
	cam:        ^eng.Camera,
	aspect:     f32,
) -> bool {
	if !_gizmo_capture_selection(gizmo, world, selection) do return false

	gizmo.dragging         = true
	gizmo.activeHandle     = handle
	gizmo.hoveredHandle    = handle
	gizmo.dragPivot        = pivot
	gizmo.dragPivotStart   = pivot
	gizmo.dragStartMousePos = mousePos
	gizmo.dragPrevMousePos  = mousePos
	gizmo.rotateAccumAngle  = 0

	switch _gizmo_handle_mode(handle) {
	case GIZMO_MODE_TRANSLATE:
		switch handle {
		case GIZMO_HANDLE_TRANSLATE_XY, GIZMO_HANDLE_TRANSLATE_XZ, GIZMO_HANDLE_TRANSLATE_YZ:
			return _gizmo_begin_plane_translate_drag(gizmo, handle, pivot, mousePos, screenSize, cam, aspect)
		case:
			return _gizmo_begin_translate_drag(gizmo, _gizmo_handle_axis(handle), pivot, mousePos, screenSize, cam, aspect)
		}
	case GIZMO_MODE_ROTATE:
		return _gizmo_begin_rotate_drag(gizmo, _gizmo_handle_axis(handle), pivot, mousePos, screenSize, cam, aspect)
	case GIZMO_MODE_SCALE:
		return _gizmo_begin_scale_drag(gizmo, handle, pivot, gizmoScale, mousePos, screenSize, cam, aspect)
	case:
		_gizmo_cancel_drag(gizmo)
		return false
	}
}

@(private)
_gizmo_capture_selection :: proc(gizmo: ^Transform_Gizmo, world: ^World, selection: ^Selection_Set) -> bool {
	clear(&gizmo.dragEntries)
	required := COMP_TRANSFORM

	for i in 0 ..< world.count {
		if world.generations[i] == 0 do continue
		if world.masks[i] & required != required do continue
		if !Selection_Contains_Index(selection, world, u32(i)) do continue

		t := world.transforms[i]
		append(&gizmo.dragEntries, Gizmo_Drag_Entry{
			id         = World_Entity_ID(world, u32(i)),
			startPos   = t.position,
			startRot   = t.rotation,
			startScale = t.scale,
		})
	}

	return len(gizmo.dragEntries) > 0
}

@(private)
_gizmo_begin_translate_drag :: proc(
	gizmo:      ^Transform_Gizmo,
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

	gizmo.dragPlaneNormal     = planeNormal
	gizmo.dragStartAxisOffset = eng.Vec3_Dot(hitPos - pivot, axisDir)
	return true
}

@(private)
_gizmo_begin_plane_translate_drag :: proc(
	gizmo:      ^Transform_Gizmo,
	handle:     Gizmo_Handle,
	pivot:      eng.Vec3,
	mousePos:   eng.Vec2,
	screenSize: eng.Vec2,
	cam:        ^eng.Camera,
	aspect:     f32,
) -> bool {
	normalAxis := _gizmo_handle_plane_normal_axis(handle)
	if normalAxis == GIZMO_AXIS_NONE do return false

	normalDir := _gizmo_axis_dir(normalAxis)
	rayOrigin, rayDir := Scene_Ray_From_Screen(mousePos, screenSize, cam, aspect)
	hitPos, hit := _ray_plane_intersection(rayOrigin, rayDir, pivot, normalDir)
	if !hit do return false

	gizmo.dragPlaneNormal   = normalDir
	gizmo.dragPlaneHitStart = hitPos
	return true
}

@(private)
_gizmo_begin_rotate_drag :: proc(
	gizmo:      ^Transform_Gizmo,
	axis:       Gizmo_Axis,
	pivot:      eng.Vec3,
	mousePos:   eng.Vec2,
	screenSize: eng.Vec2,
	cam:        ^eng.Camera,
	aspect:     f32,
) -> bool {
	if axis == GIZMO_AXIS_NONE do return false

	axisDir := _gizmo_axis_dir(axis)
	rayOrigin, rayDir := Scene_Ray_From_Screen(mousePos, screenSize, cam, aspect)
	hitPos, hit := _ray_plane_intersection(rayOrigin, rayDir, pivot, axisDir)

	radial := eng.VEC3_ZERO
	if hit {
		radial = hitPos - pivot
		radial -= axisDir * eng.Vec3_Dot(radial, axisDir)
	}
	if eng.Vec3_Length_Sq(radial) <= GIZMO_EPSILON {
		u, _ := _gizmo_ring_basis(axis)
		radial = u
	}

	gizmo.rotateStartRadial   = eng.Vec3_Normalize(radial)
	gizmo.rotateCurrentRadial = gizmo.rotateStartRadial
	gizmo.dragPlaneNormal     = axisDir
	return true
}

@(private)
_gizmo_begin_scale_drag :: proc(
	gizmo:      ^Transform_Gizmo,
	handle:     Gizmo_Handle,
	pivot:      eng.Vec3,
	gizmoScale: f32,
	mousePos:   eng.Vec2,
	screenSize: eng.Vec2,
	cam:        ^eng.Camera,
	aspect:     f32,
) -> bool {
	viewProj := eng.Camera_Get_Projection(cam, aspect) * eng.Camera_Get_View(cam)

	switch handle {
	case GIZMO_HANDLE_SCALE_UNIFORM:
		centerScreen, visible := _gizmo_world_to_screen(pivot, viewProj, screenSize)
		dir := mousePos - centerScreen
		if !visible || eng.Vec2_Dot(dir, dir) <= GIZMO_EPSILON {
			dir = eng.Vec2{0.70710677, -0.70710677}
		}
		dir = eng.Vec2_Normalize(dir)

		gizmo.dragScreenDir    = dir
		gizmo.dragPixelsToUnit = GIZMO_UNIFORM_DRAG_PIXELS
		return true
	case GIZMO_HANDLE_SCALE_X, GIZMO_HANDLE_SCALE_Y, GIZMO_HANDLE_SCALE_Z:
		axis := _gizmo_handle_axis(handle)
		axisDir := _gizmo_axis_dir(axis)
		startWorld := pivot + axisDir * (GIZMO_SCALE_SHAFT_START * gizmoScale)
		endWorld   := pivot + axisDir * (GIZMO_SCALE_CUBE_OFFSET * gizmoScale)

		startScreen, startVisible := _gizmo_world_to_screen(startWorld, viewProj, screenSize)
		endScreen, endVisible := _gizmo_world_to_screen(endWorld, viewProj, screenSize)

		dir := endScreen - startScreen
		if !startVisible || !endVisible || eng.Vec2_Dot(dir, dir) <= GIZMO_EPSILON {
			dir = eng.Vec2{axisDir.x, -axisDir.y}
		}
		if eng.Vec2_Dot(dir, dir) <= GIZMO_EPSILON {
			dir = eng.Vec2{1, 0}
		}

		gizmo.dragScreenDir    = eng.Vec2_Normalize(dir)
		gizmo.dragPixelsToUnit = math.max(eng.Vec2_Length(dir), 24.0)
		return true
	case:
		return false
	}
}

@(private)
_gizmo_apply_translate_drag :: proc(
	gizmo:      ^Transform_Gizmo,
	world:      ^World,
	mousePos:   eng.Vec2,
	screenSize: eng.Vec2,
	cam:        ^eng.Camera,
	aspect:     f32,
) {
	rayOrigin, rayDir := Scene_Ray_From_Screen(mousePos, screenSize, cam, aspect)
	hitPos, hit := _ray_plane_intersection(rayOrigin, rayDir, gizmo.dragPivot, gizmo.dragPlaneNormal)
	if !hit do return

	delta: eng.Vec3
	switch gizmo.activeHandle {
	case GIZMO_HANDLE_TRANSLATE_XY, GIZMO_HANDLE_TRANSLATE_XZ, GIZMO_HANDLE_TRANSLATE_YZ:
		// Plane drag: full 2D delta within the drag plane
		delta = hitPos - gizmo.dragPlaneHitStart
	case:
		// Single-axis drag: project onto the constrained axis only
		axis := _gizmo_handle_axis(gizmo.activeHandle)
		if axis == GIZMO_AXIS_NONE do return
		axisDir := _gizmo_axis_dir(axis)
		axisOffset := eng.Vec3_Dot(hitPos - gizmo.dragPivot, axisDir) - gizmo.dragStartAxisOffset
		delta = axisDir * axisOffset
	}

	for entry in gizmo.dragEntries {
		transform, ok := World_Get_Transform(world, entry.id)
		if !ok do continue
		transform.position = entry.startPos + delta
	}
}

@(private)
_gizmo_apply_rotate_drag :: proc(
	gizmo:      ^Transform_Gizmo,
	world:      ^World,
	mousePos:   eng.Vec2,
	screenSize: eng.Vec2,
	cam:        ^eng.Camera,
	aspect:     f32,
	gizmoScale: f32,
) {
	axis := _gizmo_handle_axis(gizmo.activeHandle)
	if axis == GIZMO_AXIS_NONE do return

	axisDir := _gizmo_axis_dir(axis)
	ringPoint := gizmo.dragPivot + gizmo.rotateCurrentRadial * (GIZMO_ROTATE_RADIUS * gizmoScale)
	tangentWorld := eng.Vec3_Cross(axisDir, gizmo.rotateCurrentRadial)
	if eng.Vec3_Length_Sq(tangentWorld) <= GIZMO_EPSILON do return
	tangentWorld = eng.Vec3_Normalize(tangentWorld)

	viewProj := eng.Camera_Get_Projection(cam, aspect) * eng.Camera_Get_View(cam)
	centerScreen, centerVisible := _gizmo_world_to_screen(gizmo.dragPivot, viewProj, screenSize)
	pointScreen, pointVisible := _gizmo_world_to_screen(ringPoint, viewProj, screenSize)
	if !centerVisible || !pointVisible do return

	tangentStep := math.max(gizmoScale * 0.12, 0.001)
	tangentScreen0, tangentVisible0 := _gizmo_world_to_screen(ringPoint - tangentWorld * tangentStep, viewProj, screenSize)
	tangentScreen1, tangentVisible1 := _gizmo_world_to_screen(ringPoint + tangentWorld * tangentStep, viewProj, screenSize)

	screenTangent := tangentScreen1 - tangentScreen0
	if !tangentVisible0 || !tangentVisible1 || eng.Vec2_Dot(screenTangent, screenTangent) <= GIZMO_EPSILON {
		screenTangent = pointScreen - centerScreen
		screenTangent = eng.Vec2{-screenTangent.y, screenTangent.x}
	}
	if eng.Vec2_Dot(screenTangent, screenTangent) <= GIZMO_EPSILON do return
	screenTangent = eng.Vec2_Normalize(screenTangent)

	radiusPixels := math.max(eng.Vec2_Length(pointScreen - centerScreen), 1.0)
	mouseDelta := mousePos - gizmo.dragPrevMousePos
	angleDelta := eng.Vec2_Dot(mouseDelta, screenTangent) / radiusPixels
	if math.abs(angleDelta) <= GIZMO_EPSILON {
		gizmo.dragPrevMousePos = mousePos
		return
	}

	gizmo.rotateAccumAngle += angleDelta
	rotDelta := eng.Quat_Axis_Angle(axisDir, gizmo.rotateAccumAngle)
	gizmo.rotateCurrentRadial = eng.Quat_Rotate_Vec3(rotDelta, gizmo.rotateStartRadial)

	for entry in gizmo.dragEntries {
		transform, ok := World_Get_Transform(world, entry.id)
		if !ok do continue
		transform.rotation = eng.Quat_Normalize(rotDelta * entry.startRot)
		
		// To maintain the pivot point under the mouse cursor, we need to rotate the offset from the pivot to the entity's position.
		offset := entry.startPos - gizmo.dragPivot
		transform.position = gizmo.dragPivot + eng.Quat_Rotate_Vec3(rotDelta, offset)
	}

	gizmo.dragPrevMousePos = mousePos
}

@(private)
_gizmo_apply_scale_drag :: proc(gizmo: ^Transform_Gizmo, world: ^World, mousePos: eng.Vec2) {
	if eng.Vec2_Dot(gizmo.dragScreenDir, gizmo.dragScreenDir) <= GIZMO_EPSILON do return

	dragPixels := eng.Vec2_Dot(mousePos - gizmo.dragStartMousePos, gizmo.dragScreenDir)
	scaleFactor := math.max(1.0 + dragPixels / math.max(gizmo.dragPixelsToUnit, 1.0), GIZMO_SCALE_MIN_FACTOR)

	for entry in gizmo.dragEntries {
		transform, ok := World_Get_Transform(world, entry.id)
		if !ok do continue

		switch gizmo.activeHandle {
		case GIZMO_HANDLE_SCALE_X:
			transform.scale.x = math.max(entry.startScale.x * scaleFactor, GIZMO_ENTITY_MIN_SCALE)
		case GIZMO_HANDLE_SCALE_Y:
			transform.scale.y = math.max(entry.startScale.y * scaleFactor, GIZMO_ENTITY_MIN_SCALE)
		case GIZMO_HANDLE_SCALE_Z:
			transform.scale.z = math.max(entry.startScale.z * scaleFactor, GIZMO_ENTITY_MIN_SCALE)
		case GIZMO_HANDLE_SCALE_UNIFORM:
			transform.scale = {
				math.max(entry.startScale.x * scaleFactor, GIZMO_ENTITY_MIN_SCALE),
				math.max(entry.startScale.y * scaleFactor, GIZMO_ENTITY_MIN_SCALE),
				math.max(entry.startScale.z * scaleFactor, GIZMO_ENTITY_MIN_SCALE),
			}
		}
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
	mode:       Gizmo_Mode,
	gizmoPos:   eng.Vec3,
	gizmoScale: f32,
	mousePos:   eng.Vec2,
	cam:        ^eng.Camera,
	screenSize: eng.Vec2,
	aspect:     f32,
) -> Gizmo_Handle {
	rayOrigin, rayDir := Scene_Ray_From_Screen(mousePos, screenSize, cam, aspect)
	hitRadiusWorld := _gizmo_world_units_per_pixel(gizmoPos, cam, screenSize) * GIZMO_HIT_RADIUS_PIXELS

	bestHandle := GIZMO_HANDLE_NONE
	bestT      : f32 = math.F32_MAX

	switch mode {
	case GIZMO_MODE_TRANSLATE:
		axisHandles := [3]Gizmo_Handle{GIZMO_HANDLE_TRANSLATE_X, GIZMO_HANDLE_TRANSLATE_Y, GIZMO_HANDLE_TRANSLATE_Z}
		for handle in axisHandles {
			axis := _gizmo_handle_axis(handle)
			axisDir := _gizmo_axis_dir(axis)
			startWorld := gizmoPos + axisDir * (GIZMO_TRANSLATE_SHAFT_START * gizmoScale)
			endWorld   := gizmoPos + axisDir * (GIZMO_TRANSLATE_TOTAL_LENGTH * gizmoScale)
			hit, hitT := _ray_vs_cylinder_segment(rayOrigin, rayDir, startWorld, endWorld, math.max(hitRadiusWorld, GIZMO_TRANSLATE_SHAFT_RADIUS * gizmoScale))
			if hit && hitT < bestT {
				bestT      = hitT
				bestHandle = handle
			}
		}

		planeHandles := [3]Gizmo_Handle{GIZMO_HANDLE_TRANSLATE_XY, GIZMO_HANDLE_TRANSLATE_XZ, GIZMO_HANDLE_TRANSLATE_YZ}
		for handle in planeHandles {
			normalAxis := _gizmo_handle_plane_normal_axis(handle)
			axis1, axis2 := _gizmo_handle_plane_axes(handle)
			normalDir := _gizmo_axis_dir(normalAxis)
			dir1      := _gizmo_axis_dir(axis1)
			dir2      := _gizmo_axis_dir(axis2)

			center := gizmoPos + dir1 * (GIZMO_TRANSLATE_PLANE_OFFSET * gizmoScale) + dir2 * (GIZMO_TRANSLATE_PLANE_OFFSET * gizmoScale)

			denom := eng.Vec3_Dot(normalDir, rayDir)
			if math.abs(denom) <= GIZMO_EPSILON do continue
			hitT := eng.Vec3_Dot(center - rayOrigin, normalDir) / denom
			if hitT < 0 do continue

			hitPos := rayOrigin + rayDir * hitT
			rel := hitPos - center
			d1 := math.abs(eng.Vec3_Dot(rel, dir1))
			d2 := math.abs(eng.Vec3_Dot(rel, dir2))
			halfHit := GIZMO_TRANSLATE_PLANE_HIT_SIZE * 0.5 * gizmoScale
			if d1 <= halfHit && d2 <= halfHit && hitT < bestT {
				bestT      = hitT
				bestHandle = handle
			}
		}
	case GIZMO_MODE_ROTATE:
		handles := [3]Gizmo_Handle{GIZMO_HANDLE_ROTATE_X, GIZMO_HANDLE_ROTATE_Y, GIZMO_HANDLE_ROTATE_Z}
		radius := GIZMO_ROTATE_RADIUS * gizmoScale
		thickness := math.max(hitRadiusWorld, GIZMO_ROTATE_THICKNESS * gizmoScale)
		for handle in handles {
			axis := _gizmo_handle_axis(handle)
			for seg in 0 ..< GIZMO_ROTATE_SEGMENTS {
				a0 := (f32(seg) / f32(GIZMO_ROTATE_SEGMENTS)) * 2.0 * math.PI
				a1 := (f32(seg + 1) / f32(GIZMO_ROTATE_SEGMENTS)) * 2.0 * math.PI
				p0 := gizmoPos + _gizmo_ring_point(axis, a0) * radius
				p1 := gizmoPos + _gizmo_ring_point(axis, a1) * radius
				hit, hitT := _ray_vs_cylinder_segment(rayOrigin, rayDir, p0, p1, thickness)
				if hit && hitT < bestT {
					bestT      = hitT
					bestHandle = handle
				}
			}
		}
	case GIZMO_MODE_SCALE:
		handles := [3]Gizmo_Handle{GIZMO_HANDLE_SCALE_X, GIZMO_HANDLE_SCALE_Y, GIZMO_HANDLE_SCALE_Z}
		for handle in handles {
			axis := _gizmo_handle_axis(handle)
			axisDir := _gizmo_axis_dir(axis)
			startWorld := gizmoPos + axisDir * (GIZMO_SCALE_SHAFT_START * gizmoScale)
			endWorld   := gizmoPos + axisDir * (GIZMO_SCALE_CUBE_OFFSET * gizmoScale)
			hit, hitT := _ray_vs_cylinder_segment(rayOrigin, rayDir, startWorld, endWorld, math.max(hitRadiusWorld, GIZMO_SCALE_SHAFT_RADIUS * gizmoScale))
			if hit && hitT < bestT {
				bestT      = hitT
				bestHandle = handle
			}

			cubeCenter := gizmoPos + axisDir * (GIZMO_SCALE_CUBE_OFFSET * gizmoScale)
			cubeHalf := eng.Vec3{1, 1, 1} * (GIZMO_SCALE_CUBE_SIZE * gizmoScale * 0.5)
			cubeHit, cubeT := _gizmo_ray_aabb(rayOrigin, rayDir, cubeCenter - cubeHalf, cubeCenter + cubeHalf)
			if cubeHit && cubeT < bestT {
				bestT      = cubeT
				bestHandle = handle
			}
		}

		centerHalf := eng.Vec3{1, 1, 1} * (GIZMO_SCALE_CENTER_SIZE * gizmoScale * 0.5)
		centerHit, centerT := _gizmo_ray_aabb(rayOrigin, rayDir, gizmoPos - centerHalf, gizmoPos + centerHalf)
		if centerHit && centerT < bestT {
			bestHandle = GIZMO_HANDLE_SCALE_UNIFORM
		}
	}

	return bestHandle
}

@(private)
_gizmo_draw_translate :: proc(gizmo: ^Transform_Gizmo, renderer: ^rend.Renderer, origin: eng.Vec3, gizmoScale: f32) {
	axisHandles := [3]Gizmo_Handle{GIZMO_HANDLE_TRANSLATE_X, GIZMO_HANDLE_TRANSLATE_Y, GIZMO_HANDLE_TRANSLATE_Z}
	for handle in axisHandles {
		axis := _gizmo_handle_axis(handle)
		axisDir := _gizmo_axis_dir(axis)
		color := _gizmo_handle_color(gizmo, handle)

		shaftCenter := origin + axisDir * ((GIZMO_TRANSLATE_SHAFT_START + GIZMO_TRANSLATE_SHAFT_LENGTH * 0.5) * gizmoScale)
		headCenter  := origin + axisDir * ((GIZMO_TRANSLATE_SHAFT_START + GIZMO_TRANSLATE_SHAFT_LENGTH + GIZMO_TRANSLATE_HEAD_LENGTH * 0.5) * gizmoScale)

		shaftModel := eng.Mat4_Translate(shaftCenter) * eng.Mat4_Scale(_gizmo_box_scale(axis, GIZMO_TRANSLATE_SHAFT_LENGTH * gizmoScale, GIZMO_TRANSLATE_SHAFT_RADIUS * gizmoScale))
		headModel  := eng.Mat4_Translate(headCenter)  * eng.Mat4_Scale(_gizmo_box_scale(axis, GIZMO_TRANSLATE_HEAD_LENGTH * gizmoScale, GIZMO_TRANSLATE_HEAD_RADIUS * gizmoScale))

		rend.Renderer_Draw_Mesh(renderer, &gizmo.mesh, shaftModel, color)
		rend.Renderer_Draw_Mesh(renderer, &gizmo.mesh, headModel, color)
	}

	// Plane drag squares: small flat quads between each pair of axes
	planeHandles := [3]Gizmo_Handle{GIZMO_HANDLE_TRANSLATE_XY, GIZMO_HANDLE_TRANSLATE_XZ, GIZMO_HANDLE_TRANSLATE_YZ}
	size      := GIZMO_TRANSLATE_PLANE_SIZE      * gizmoScale
	thickness := GIZMO_TRANSLATE_PLANE_THICKNESS * gizmoScale
	for handle in planeHandles {
		normalAxis := _gizmo_handle_plane_normal_axis(handle)
		axis1, axis2 := _gizmo_handle_plane_axes(handle)
		normalDir := _gizmo_axis_dir(normalAxis)
		dir1      := _gizmo_axis_dir(axis1)
		dir2      := _gizmo_axis_dir(axis2)
		color     := _gizmo_handle_color(gizmo, handle)

		center := origin + dir1 * (GIZMO_TRANSLATE_PLANE_OFFSET * gizmoScale) + dir2 * (GIZMO_TRANSLATE_PLANE_OFFSET * gizmoScale)
		model  := _gizmo_basis_model(center, dir1, normalDir, dir2, {size, thickness, size})
		rend.Renderer_Draw_Mesh(renderer, &gizmo.mesh, model, color)
	}
}

@(private)
_gizmo_draw_rotate :: proc(gizmo: ^Transform_Gizmo, renderer: ^rend.Renderer, origin: eng.Vec3, gizmoScale: f32) {
	handles := [3]Gizmo_Handle{GIZMO_HANDLE_ROTATE_X, GIZMO_HANDLE_ROTATE_Y, GIZMO_HANDLE_ROTATE_Z}
	radius := GIZMO_ROTATE_RADIUS * gizmoScale
	thickness := GIZMO_ROTATE_THICKNESS * gizmoScale
	segmentLength := (2.0 * math.PI * radius / f32(GIZMO_ROTATE_SEGMENTS)) * GIZMO_ROTATE_SEGMENT_ARC

	for handle in handles {
		axis := _gizmo_handle_axis(handle)
		color := _gizmo_handle_color(gizmo, handle)

		for seg in 0 ..< GIZMO_ROTATE_SEGMENTS {
			angle := ((f32(seg) + 0.5) / f32(GIZMO_ROTATE_SEGMENTS)) * 2.0 * math.PI
			radial := _gizmo_ring_point(axis, angle)
			tangent := _gizmo_ring_tangent(axis, angle)
			center := origin + radial * radius
			model := _gizmo_basis_model(center, tangent, eng.Vec3_Cross(radial, tangent), radial, {segmentLength, thickness, thickness})
			rend.Renderer_Draw_Mesh(renderer, &gizmo.mesh, model, color)
		}
	}

	if gizmo.dragging {
		switch gizmo.activeHandle {
		case GIZMO_HANDLE_ROTATE_X, GIZMO_HANDLE_ROTATE_Y, GIZMO_HANDLE_ROTATE_Z:
			_gizmo_draw_rotate_indicator(gizmo, renderer, origin, gizmoScale)
		}
	}
}

@(private)
_gizmo_draw_scale :: proc(gizmo: ^Transform_Gizmo, renderer: ^rend.Renderer, origin: eng.Vec3, gizmoScale: f32) {
	handles := [3]Gizmo_Handle{GIZMO_HANDLE_SCALE_X, GIZMO_HANDLE_SCALE_Y, GIZMO_HANDLE_SCALE_Z}

	for handle in handles {
		axis := _gizmo_handle_axis(handle)
		axisDir := _gizmo_axis_dir(axis)
		color := _gizmo_handle_color(gizmo, handle)

		shaftCenter := origin + axisDir * ((GIZMO_SCALE_SHAFT_START + GIZMO_SCALE_SHAFT_LENGTH * 0.5) * gizmoScale)
		cubeCenter  := origin + axisDir * (GIZMO_SCALE_CUBE_OFFSET * gizmoScale)

		shaftModel := eng.Mat4_Translate(shaftCenter) * eng.Mat4_Scale(_gizmo_box_scale(axis, GIZMO_SCALE_SHAFT_LENGTH * gizmoScale, GIZMO_SCALE_SHAFT_RADIUS * gizmoScale))
		cubeModel  := eng.Mat4_Translate(cubeCenter)  * eng.Mat4_Scale(eng.Vec3{1, 1, 1} * (GIZMO_SCALE_CUBE_SIZE * gizmoScale))

		rend.Renderer_Draw_Mesh(renderer, &gizmo.mesh, shaftModel, color)
		rend.Renderer_Draw_Mesh(renderer, &gizmo.mesh, cubeModel, color)
	}

	centerColor := eng.Vec3{0.86, 0.86, 0.9}
	if gizmo.hoveredHandle == GIZMO_HANDLE_SCALE_UNIFORM || gizmo.activeHandle == GIZMO_HANDLE_SCALE_UNIFORM {
		centerColor = eng.Vec3_Lerp(centerColor, eng.Vec3{1, 1, 1}, GIZMO_HIGHLIGHT_MIX)
	}
	centerModel := eng.Mat4_Translate(origin) * eng.Mat4_Scale(eng.Vec3{1, 1, 1} * (GIZMO_SCALE_CENTER_SIZE * gizmoScale))
	rend.Renderer_Draw_Mesh(renderer, &gizmo.mesh, centerModel, centerColor)
}

@(private)
_gizmo_draw_rotate_indicator :: proc(gizmo: ^Transform_Gizmo, renderer: ^rend.Renderer, origin: eng.Vec3, gizmoScale: f32) {
	axis := _gizmo_handle_axis(gizmo.activeHandle)
	if axis == GIZMO_AXIS_NONE do return

	axisDir := _gizmo_axis_dir(axis)
	startRadial := eng.Vec3_Normalize(gizmo.rotateStartRadial)
	currentRadial := eng.Vec3_Normalize(gizmo.rotateCurrentRadial)

	side := eng.Vec3_Cross(startRadial, axisDir)
	if eng.Vec3_Length_Sq(side) <= GIZMO_EPSILON do return
	side = eng.Vec3_Normalize(side)

	armLength := GIZMO_ROTATE_ARM_LENGTH * GIZMO_ROTATE_RADIUS * gizmoScale
	armRadius := GIZMO_ROTATE_ARM_RADIUS * gizmoScale

	startCenter := origin + startRadial * (armLength * 0.5)
	startModel := _gizmo_basis_model(startCenter, startRadial, axisDir, side, {armLength, armRadius, armRadius})
	rend.Renderer_Draw_Mesh(renderer, &gizmo.mesh, startModel, {1.0, 0.96, 0.5})

	currentSide := eng.Vec3_Cross(currentRadial, axisDir)
	if eng.Vec3_Length_Sq(currentSide) <= GIZMO_EPSILON do return
	currentSide = eng.Vec3_Normalize(currentSide)

	currentColor := _gizmo_handle_color(gizmo, gizmo.activeHandle)
	currentCenter := origin + currentRadial * (armLength * 0.5)
	currentModel := _gizmo_basis_model(currentCenter, currentRadial, axisDir, currentSide, {armLength, armRadius, armRadius})
	rend.Renderer_Draw_Mesh(renderer, &gizmo.mesh, currentModel, currentColor)

	arrowDir := eng.Vec3_Cross(axisDir, currentRadial)
	if gizmo.rotateAccumAngle < 0 do arrowDir = -arrowDir
	if eng.Vec3_Length_Sq(arrowDir) <= GIZMO_EPSILON do return
	arrowDir = eng.Vec3_Normalize(arrowDir)

	arrowTip := origin + currentRadial * (GIZMO_ROTATE_RADIUS * gizmoScale)
	arrowCenter := arrowTip + arrowDir * (GIZMO_ROTATE_ARROW_LENGTH * gizmoScale * 0.35)
	arrowModel := _gizmo_basis_model(
		arrowCenter,
		arrowDir,
		axisDir,
		currentRadial,
		{GIZMO_ROTATE_ARROW_LENGTH * gizmoScale, GIZMO_ROTATE_ARROW_RADIUS * gizmoScale, GIZMO_ROTATE_ARROW_RADIUS * gizmoScale},
	)
	rend.Renderer_Draw_Mesh(renderer, &gizmo.mesh, arrowModel, currentColor)
}

@(private)
_gizmo_handle_color :: proc(gizmo: ^Transform_Gizmo, handle: Gizmo_Handle) -> eng.Vec3 {
	color: eng.Vec3
	switch handle {
	case GIZMO_HANDLE_SCALE_UNIFORM:
		color = {0.86, 0.86, 0.9}
	case GIZMO_HANDLE_TRANSLATE_XY, GIZMO_HANDLE_TRANSLATE_XZ, GIZMO_HANDLE_TRANSLATE_YZ:
		// Color by the excluded (normal) axis: XY→blue, XZ→green, YZ→red
		color = _gizmo_axis_color(_gizmo_handle_plane_normal_axis(handle))
	case:
		color = _gizmo_axis_color(_gizmo_handle_axis(handle))
	}

	if gizmo.activeHandle == handle || (!gizmo.dragging && gizmo.hoveredHandle == handle) {
		color = eng.Vec3_Lerp(color, eng.Vec3{1, 1, 1}, GIZMO_HIGHLIGHT_MIX)
	}
	return color
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
	return math.max(_gizmo_world_units_per_pixel(gizmoPos, cam, screenSize) * GIZMO_PIXEL_LENGTH, GIZMO_MIN_SCALE)
}

@(private)
_gizmo_world_units_per_pixel :: proc(gizmoPos: eng.Vec3, cam: ^eng.Camera, screenSize: eng.Vec2) -> f32 {
	screenHeight := math.max(screenSize.y, 1.0)
	distance := eng.Vec3_Distance(cam.position, gizmoPos)
	distance = math.max(distance, 0.001)
	return (2.0 * distance * math.tan(cam.fovY * 0.5)) / screenHeight
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
_gizmo_ring_basis :: proc(axis: Gizmo_Axis) -> (u, v: eng.Vec3) {
	switch axis {
	case GIZMO_AXIS_X:
		return eng.VEC3_UP, eng.VEC3_BACK
	case GIZMO_AXIS_Y:
		return eng.VEC3_BACK, eng.VEC3_RIGHT
	case GIZMO_AXIS_Z:
		return eng.VEC3_RIGHT, eng.VEC3_UP
	case:
		return eng.VEC3_RIGHT, eng.VEC3_UP
	}
}

@(private)
_gizmo_ring_point :: proc(axis: Gizmo_Axis, angle: f32) -> eng.Vec3 {
	u, v := _gizmo_ring_basis(axis)
	return u * math.cos(angle) + v * math.sin(angle)
}

@(private)
_gizmo_ring_tangent :: proc(axis: Gizmo_Axis, angle: f32) -> eng.Vec3 {
	u, v := _gizmo_ring_basis(axis)
	return eng.Vec3_Normalize(-u * math.sin(angle) + v * math.cos(angle))
}

@(private)
_gizmo_basis_model :: proc(position, xAxis, yAxis, zAxis, scale: eng.Vec3) -> eng.Mat4 {
	x := eng.Vec3_Normalize(xAxis) * scale.x
	y := eng.Vec3_Normalize(yAxis) * scale.y
	z := eng.Vec3_Normalize(zAxis) * scale.z

	model := eng.MAT4_IDENTITY
	model[0, 0] = x.x
	model[1, 0] = x.y
	model[2, 0] = x.z

	model[0, 1] = y.x
	model[1, 1] = y.y
	model[2, 1] = y.z

	model[0, 2] = z.x
	model[1, 2] = z.y
	model[2, 2] = z.z

	model[0, 3] = position.x
	model[1, 3] = position.y
	model[2, 3] = position.z
	return model
}

@(private)
_gizmo_handle_axis :: proc(handle: Gizmo_Handle) -> Gizmo_Axis {
	switch handle {
	case GIZMO_HANDLE_TRANSLATE_X, GIZMO_HANDLE_ROTATE_X, GIZMO_HANDLE_SCALE_X:
		return GIZMO_AXIS_X
	case GIZMO_HANDLE_TRANSLATE_Y, GIZMO_HANDLE_ROTATE_Y, GIZMO_HANDLE_SCALE_Y:
		return GIZMO_AXIS_Y
	case GIZMO_HANDLE_TRANSLATE_Z, GIZMO_HANDLE_ROTATE_Z, GIZMO_HANDLE_SCALE_Z:
		return GIZMO_AXIS_Z
	case:
		return GIZMO_AXIS_NONE
	}
}

@(private)
_gizmo_handle_mode :: proc(handle: Gizmo_Handle) -> Gizmo_Mode {
	switch handle {
	case GIZMO_HANDLE_TRANSLATE_X, GIZMO_HANDLE_TRANSLATE_Y, GIZMO_HANDLE_TRANSLATE_Z,
	     GIZMO_HANDLE_TRANSLATE_XY, GIZMO_HANDLE_TRANSLATE_XZ, GIZMO_HANDLE_TRANSLATE_YZ:
		return GIZMO_MODE_TRANSLATE
	case GIZMO_HANDLE_ROTATE_X, GIZMO_HANDLE_ROTATE_Y, GIZMO_HANDLE_ROTATE_Z:
		return GIZMO_MODE_ROTATE
	case GIZMO_HANDLE_SCALE_X, GIZMO_HANDLE_SCALE_Y, GIZMO_HANDLE_SCALE_Z, GIZMO_HANDLE_SCALE_UNIFORM:
		return GIZMO_MODE_SCALE
	case:
		return GIZMO_MODE_TRANSLATE
	}
}

@(private)
_gizmo_handle_plane_normal_axis :: proc(handle: Gizmo_Handle) -> Gizmo_Axis {
	switch handle {
	case GIZMO_HANDLE_TRANSLATE_XY: return GIZMO_AXIS_Z
	case GIZMO_HANDLE_TRANSLATE_XZ: return GIZMO_AXIS_Y
	case GIZMO_HANDLE_TRANSLATE_YZ: return GIZMO_AXIS_X
	case: return GIZMO_AXIS_NONE
	}
}

@(private)
_gizmo_handle_plane_axes :: proc(handle: Gizmo_Handle) -> (Gizmo_Axis, Gizmo_Axis) {
	switch handle {
	case GIZMO_HANDLE_TRANSLATE_XY: return GIZMO_AXIS_X, GIZMO_AXIS_Y
	case GIZMO_HANDLE_TRANSLATE_XZ: return GIZMO_AXIS_X, GIZMO_AXIS_Z
	case GIZMO_HANDLE_TRANSLATE_YZ: return GIZMO_AXIS_Y, GIZMO_AXIS_Z
	case: return GIZMO_AXIS_NONE, GIZMO_AXIS_NONE
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
_gizmo_ray_aabb :: proc(origin, dir, aabbMin, aabbMax: eng.Vec3) -> (hit: bool, t: f32) {
	tMin: f32 = -math.F32_MAX
	tMax: f32 =  math.F32_MAX

	for axis in 0 ..< 3 {
		o := origin[axis]
		d := dir[axis]
		lo := aabbMin[axis]
		hi := aabbMax[axis]

		if math.abs(d) < GIZMO_EPSILON {
			if o < lo || o > hi do return false, 0
		} else {
			t1 := (lo - o) / d
			t2 := (hi - o) / d
			if t1 > t2 do t1, t2 = t2, t1
			if t1 > tMin do tMin = t1
			if t2 < tMax do tMax = t2
			if tMin > tMax do return false, 0
		}
	}

	if tMax < 0 do return false, 0
	t = tMin if tMin >= 0 else tMax
	return true, t
}

@(private)
_ray_vs_cylinder_segment :: proc(
	rayOrigin, rayDir: eng.Vec3,
	a, b:               eng.Vec3,
	radius:             f32,
) -> (hit: bool, t: f32) {
	segDir := b - a
	if eng.Vec3_Length_Sq(segDir) <= GIZMO_EPSILON do return false, 0

	u := segDir
	v := rayDir
	w := a - rayOrigin

	aDot := eng.Vec3_Dot(u, u)
	bDot := eng.Vec3_Dot(u, v)
	cDot := eng.Vec3_Dot(v, v)
	dDot := eng.Vec3_Dot(u, w)
	eDot := eng.Vec3_Dot(v, w)
	denom := aDot * cDot - bDot * bDot

	sN := denom
	sD := denom
	tN := denom
	tD := denom

	if denom < GIZMO_EPSILON {
		sN = 0
		sD = 1
		tN = eDot
		tD = cDot
	} else {
		sN = bDot * eDot - cDot * dDot
		tN = aDot * eDot - bDot * dDot

		if sN < 0 {
			sN = 0
			tN = eDot
			tD = cDot
		} else if sN > sD {
			sN = sD
			tN = eDot + bDot
			tD = cDot
		}
	}

	if tN < 0 {
		tN = 0
		if -dDot < 0 {
			sN = 0
			sD = 1
		} else if -dDot > aDot {
			sN = sD
		} else {
			sN = -dDot
			sD = aDot
		}
	}

	sc := f32(0)
	if math.abs(sD) > GIZMO_EPSILON do sc = sN / sD
	tc := f32(0)
	if math.abs(tD) > GIZMO_EPSILON do tc = tN / tD
	if tc < 0 do return false, 0

	closest := w + u * sc - v * tc
	if eng.Vec3_Dot(closest, closest) > radius * radius do return false, 0
	return true, tc
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
