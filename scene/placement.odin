package scene

import eng "../engine"

PLACEMENT_FALLBACK_DIST :: f32(20.0)

// Resolves a cursor ray to a predictable spawn point on the editor ground plane.
// If the ray cannot hit Y=0, fall back to a point in front of the camera.
Scene_Placement_Point_From_Ray :: proc(origin, dir: eng.Vec3) -> eng.Vec3 {
	if dir.y < -1e-6 {
		t := -origin.y / dir.y
		if t >= 0 do return origin + dir * t
	}
	return origin + dir * PLACEMENT_FALLBACK_DIST
}

