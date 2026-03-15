package scene

import "core:math"
import eng "../engine"

// Persistent editor-style selection state keyed by entity slot.
// Storing the full EntityID prevents stale selection from surviving slot reuse.
Selection_Set :: struct {
	ids:   [MAX_ENTITIES]EntityID,
	count: int,
}

// Drag rectangle state in window pixel coordinates.
Marquee_Selection :: struct {
	active:   bool,
	dragging: bool,
	start:    eng.Vec2,
	current:  eng.Vec2,
}

MARQUEE_DRAG_THRESHOLD :: f32(4.0)

Selection_Clear :: proc(selection: ^Selection_Set) {
	selection.ids = {}
	selection.count = 0
}

Selection_Contains_Index :: proc(selection: ^Selection_Set, world: ^World, idx: u32) -> bool {
	if selection == nil do return false
	return selection.ids[idx] == World_Entity_ID(world, idx)
}

Selection_Contains_ID :: proc(selection: ^Selection_Set, world: ^World, id: EntityID) -> bool {
	if !World_Entity_Valid(world, id) do return false
	return Selection_Contains_Index(selection, world, World_Entity_Index(id))
}

Selection_Add_Index :: proc(selection: ^Selection_Set, world: ^World, idx: u32) {
	id := World_Entity_ID(world, idx)
	if selection.ids[idx] == id do return
	selection.ids[idx] = id
	selection.count += 1
}

Selection_Add_ID :: proc(selection: ^Selection_Set, world: ^World, id: EntityID) {
	if !World_Entity_Valid(world, id) do return
	Selection_Add_Index(selection, world, World_Entity_Index(id))
}

Selection_Set_Single :: proc(selection: ^Selection_Set, world: ^World, id: EntityID) {
	Selection_Clear(selection)
	Selection_Add_ID(selection, world, id)
}

Marquee_Begin :: proc(marquee: ^Marquee_Selection, start: eng.Vec2) {
	marquee.active   = true
	marquee.dragging = false
	marquee.start    = start
	marquee.current  = start
}

Marquee_Update :: proc(marquee: ^Marquee_Selection, current: eng.Vec2) {
	if !marquee.active do return
	marquee.current = current
	delta := marquee.current - marquee.start
	marquee.dragging = eng.Vec2_Dot(delta, delta) >= MARQUEE_DRAG_THRESHOLD * MARQUEE_DRAG_THRESHOLD
}

Marquee_End :: proc(marquee: ^Marquee_Selection) {
	marquee^ = {}
}

Marquee_Bounds :: proc(marquee: ^Marquee_Selection) -> (min, max: eng.Vec2) {
	min = {
		math.min(marquee.start.x, marquee.current.x),
		math.min(marquee.start.y, marquee.current.y),
	}
	max = {
		math.max(marquee.start.x, marquee.current.x),
		math.max(marquee.start.y, marquee.current.y),
	}
	return
}

Scene_Select_Marquee :: proc(
	world:      ^World,
	selection:  ^Selection_Set,
	marquee:    ^Marquee_Selection,
	screenSize: eng.Vec2,
	cam:        ^eng.Camera,
	aspect:     f32,
) -> int {
	if !marquee.dragging do return 0

	rectMin, rectMax := Marquee_Bounds(marquee)
	view    := eng.Camera_Get_View(cam)
	proj    := eng.Camera_Get_Projection(cam, aspect)
	viewProj := proj * view

	selectedCount := 0
	required := COMP_TRANSFORM | COMP_MESH_REF

	for i in 0 ..< world.count {
		if world.generations[i] == 0 do continue
		if world.masks[i] & required != required do continue

		t := world.transforms[i]
		half := eng.Vec3{t.scale.x * 0.5, t.scale.y * 0.5, t.scale.z * 0.5}

		screenMin := eng.Vec2{math.F32_MAX, math.F32_MAX}
		screenMax := eng.Vec2{-math.F32_MAX, -math.F32_MAX}
		anyVisible := false

		for corner in 0 ..< 8 {
			offset := eng.Vec3{
				(corner & 1) != 0 ? half.x : -half.x,
				(corner & 2) != 0 ? half.y : -half.y,
				(corner & 4) != 0 ? half.z : -half.z,
			}
			screenPos, visible := _world_to_screen(t.position + offset, viewProj, screenSize)
			if !visible do continue

			if screenPos.x < screenMin.x do screenMin.x = screenPos.x
			if screenPos.y < screenMin.y do screenMin.y = screenPos.y
			if screenPos.x > screenMax.x do screenMax.x = screenPos.x
			if screenPos.y > screenMax.y do screenMax.y = screenPos.y
			anyVisible = true
		}

		if !anyVisible do continue
		if !_rects_overlap(rectMin, rectMax, screenMin, screenMax) do continue

		Selection_Add_Index(selection, world, u32(i))
		selectedCount += 1
	}

	return selectedCount
}

@(private)
_world_to_screen :: proc(worldPos: eng.Vec3, viewProj: eng.Mat4, screenSize: eng.Vec2) -> (screenPos: eng.Vec2, visible: bool) {
	clip := viewProj * eng.Vec4{worldPos.x, worldPos.y, worldPos.z, 1.0}
	if clip.w <= 1e-5 do return {}, false

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
_rects_overlap :: proc(aMin, aMax, bMin, bMax: eng.Vec2) -> bool {
	if aMax.x < bMin.x || aMin.x > bMax.x do return false
	if aMax.y < bMin.y || aMin.y > bMax.y do return false
	return true
}
