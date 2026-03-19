package scene

import eng "../engine"

MAX_CLIPBOARD_ENTRIES :: 1024

// Distance along the cursor ray used when the grid plane cannot be hit.
PASTE_FALLBACK_DIST :: f32(20.0)

// Intersect a ray with the Y=0 grid plane.
// Returns the hit point and true when the ray is aimed toward the plane from above.
@(private)
_ray_grid_plane :: proc(origin, dir: eng.Vec3) -> (hitPoint: eng.Vec3, ok: bool) {
	if dir.y > -1e-6 do return {}, false // parallel or pointing away from plane
	t := -origin.y / dir.y
	if t < 0 do return {}, false         // plane is behind the camera
	return origin + dir * t, true
}

// POD snapshot of one entity's component data.
Clipboard_Entry :: struct {
	mask:      ComponentMask,
	transform: eng.Transform,
	meshRef:   MeshRef,
	velocity:  eng.Vec3,
}

// In-engine clipboard.  Zero-value is valid — no Init needed.
// Holds up to MAX_CLIPBOARD_ENTRIES entity snapshots.
Clipboard :: struct {
	entries: [MAX_CLIPBOARD_ENTRIES]Clipboard_Entry,
	count:   int,
}

// Snapshot the current selection into clip.  Overwrites any previous contents.
Clipboard_Copy :: proc(w: ^World, sel: ^Selection_Set, clip: ^Clipboard) {
	clip.count = 0
	for i in 0 ..< w.count {
		if !Selection_Contains_Index(sel, w, u32(i)) do continue

		e := &clip.entries[clip.count]
		e.mask = {}

		id := World_Entity_ID(w, u32(i))
		if t, ok := World_Get_Transform(w, id); ok {
			e.transform  = t^
			e.mask      |= COMP_TRANSFORM
		}
		if ref, ok := World_Get_MeshRef(w, id); ok {
			e.meshRef  = ref^
			e.mask    |= COMP_MESH_REF
		}
		if vel, ok := World_Get_Velocity(w, id); ok {
			e.velocity  = vel^
			e.mask     |= COMP_VELOCITY
		}

		clip.count += 1
		if clip.count >= MAX_CLIPBOARD_ENTRIES do break
	}
}

// Create new entities from the clipboard at the cursor location.
//
// Placement:
//   - XZ follows the cursor: uses the raycast hit point when the camera is
//     above the grid (origin.y >= 0) and the ray hits something; otherwise
//     falls back to PASTE_FALLBACK_DIST units along the ray.
//   - Y is always preserved from the clipboard — entities appear at the same
//     height they were copied from, relative positions intact.
//
// Replaces the current selection with the newly pasted entities.
// Returns (ids, snap, true) for the caller to pass to Undo_Paste_Commit.
// Returns ok=false if the clipboard is empty.
Clipboard_Paste :: proc(
	w:      ^World,
	sel:    ^Selection_Set,
	clip:   ^Clipboard,
	origin: eng.Vec3,
	dir:    eng.Vec3,
) -> (ids: [dynamic]EntityID, snap: [dynamic]Clipboard_Entry, ok: bool) {
	if clip.count == 0 do return {}, {}, false

	// Resolve XZ paste target.
	// Project cursor ray onto the Y=0 grid plane for a predictable result.
	// Fall back to a fixed distance along the ray when below the grid or
	// when the ray points away from the plane (e.g. looking straight up).
	targetX, targetZ: f32
	if planeHit, hitOk := _ray_grid_plane(origin, dir); hitOk {
		targetX = planeHit.x
		targetZ = planeHit.z
	} else {
		fp := origin + dir * PASTE_FALLBACK_DIST
		targetX = fp.x
		targetZ = fp.z
	}

	// Clipboard XZ centroid — used to offset the group as a whole.
	centroidX, centroidZ: f32
	validCount := 0
	for i in 0 ..< clip.count {
		e := clip.entries[i]
		if e.mask & COMP_TRANSFORM == 0 do continue
		centroidX  += e.transform.position.x
		centroidZ  += e.transform.position.z
		validCount += 1
	}
	if validCount > 0 {
		centroidX /= f32(validCount)
		centroidZ /= f32(validCount)
	}

	xOff := targetX - centroidX
	zOff := targetZ - centroidZ

	ids  = make([dynamic]EntityID,       0, clip.count)
	snap = make([dynamic]Clipboard_Entry, 0, clip.count)

	Selection_Clear(sel)

	for i in 0 ..< clip.count {
		e  := clip.entries[i]
		id := World_Entity_Create(w)

		if e.mask & COMP_TRANSFORM != 0 {
			e.transform.position.x += xOff
			// Y intentionally preserved — paste at copied height.
			e.transform.position.z += zOff
			World_Add_Transform(w, id, e.transform)
		}
		if e.mask & COMP_MESH_REF != 0 {
			World_Add_MeshRef(w, id, e.meshRef)
		}
		if e.mask & COMP_VELOCITY != 0 {
			World_Add_Velocity(w, id, e.velocity)
		}

		Selection_Add_ID(sel, w, id)
		append(&ids,  id)
		append(&snap, e)
	}

	return ids, snap, true
}
