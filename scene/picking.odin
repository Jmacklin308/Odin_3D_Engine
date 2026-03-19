package scene

import "core:math"
import eng "../engine"

// =============================================================================
// Screen-space Ray
// =============================================================================

// Builds a world-space ray from a pixel position (e.g. mouse cursor).
// `screenPos` is in pixels, top-left origin.
// `screenSize` is the window dimensions in pixels.
// Returns a normalised direction and the camera's world position as origin.
Scene_Ray_From_Screen :: proc(
	screenPos:  eng.Vec2,
	screenSize: eng.Vec2,
	cam:        ^eng.Camera,
	aspect:     f32,
) -> (origin, dir: eng.Vec3) {
	// Convert to NDC [-1, 1]
	ndcX :=  (2.0 * screenPos.x / screenSize.x) - 1.0
	ndcY := -(2.0 * screenPos.y / screenSize.y) + 1.0 // Y is flipped

	// Unproject through inverse projection then inverse view.
	proj    := eng.Camera_Get_Projection(cam, aspect)
	view    := eng.Camera_Get_View(cam)
	invProj := eng.Mat4_Inverse(proj)
	invView := eng.Mat4_Inverse(view)

	// View-space ray direction (w=0 means direction, not position)
	clipRay  := eng.Vec4{ndcX, ndcY, -1.0, 1.0}
	eyeRay4  := invProj * clipRay
	eyeDir   := eng.Vec4{eyeRay4.x, eyeRay4.y, -1.0, 0.0}

	// World-space direction
	worldDir4 := invView * eyeDir
	dir = eng.Vec3_Normalize(eng.Vec3{worldDir4.x, worldDir4.y, worldDir4.z})
	origin = cam.position
	return
}

// =============================================================================
// Ray vs AABB (slab method)
// Returns (hit, tMin) — the distance along the ray to the closest hit face.
// =============================================================================

@(private)
_ray_aabb :: proc(origin, dir, aabbMin, aabbMax: eng.Vec3) -> (hit: bool, t: f32) {
	tMin: f32 = -math.F32_MAX
	tMax: f32 =  math.F32_MAX

	for axis in 0..<3 {
		o := origin[axis]
		d := dir[axis]
		lo := aabbMin[axis]
		hi := aabbMax[axis]

		if math.abs(d) < 1e-8 {
			// Ray is parallel to slab — check if origin is inside.
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

	if tMax < 0 do return false, 0 // AABB is behind the ray
	t = tMin if tMin >= 0 else tMax
	return true, t
}

// =============================================================================
// Scene Picking
// =============================================================================

// Cast a ray into the scene and return the closest entity it hits.
// Uses per-entity AABBs derived from Transform (position ± scale*0.5).
// Only tests entities that have both COMP_TRANSFORM and COMP_MESH_REF.
// Returns ENTITY_NULL if nothing is hit.
Scene_Pick :: proc(world: ^World, origin, dir: eng.Vec3) -> EntityID {
	id, _, _ := Scene_Pick_Point(world, origin, dir)
	return id
}

// Like Scene_Pick but also returns the world-space hit point and an ok flag.
// hitPoint is only valid when ok is true.
Scene_Pick_Point :: proc(world: ^World, origin, dir: eng.Vec3) -> (id: EntityID, hitPoint: eng.Vec3, ok: bool) {
	required := COMP_TRANSFORM | COMP_MESH_REF
	bestT: f32 = 3.402823466e+38 // max f32

	for i in 0 ..< world.count {
		if world.generations[i] == 0 do continue
		if world.masks[i] & required != required do continue

		t    := world.transforms[i]
		half := eng.Vec3{t.scale.x * 0.5, t.scale.y * 0.5, t.scale.z * 0.5}

		hit, dist := _ray_aabb(origin, dir, t.position - half, t.position + half)
		if hit && dist < bestT {
			bestT = dist
			id    = World_Entity_ID(world, u32(i))
			ok    = true
		}
	}

	if ok do hitPoint = origin + dir * bestT
	return
}
