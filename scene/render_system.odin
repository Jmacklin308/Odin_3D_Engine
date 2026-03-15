package scene

import eng "../engine"
import rend "../renderer"

// Tint applied to the selected entity's colour in the render batch.
SELECTION_TINT :: eng.Vec3{1.0, 0.85, 0.0} // bright yellow

// Batches visible mesh instances by mesh key and submits instanced draw calls.
// Pass a Selection_Set to tint selected entities with SELECTION_TINT.
Scene_Render_System :: proc(world: ^World, selection: ^Selection_Set = nil) {
	// --- Clear previous frame's instance lists (keep allocated capacity) ---
	for i in 0 ..< MESH_REGISTRY_MAX {
		if world._batches[i].mesh != nil {
			clear(&world._batches[i].instanceData)
		}
	}

	// --- Gather phase: sequential scan over all entity slots ---
	// Reads masks[] and meshRefs[] sequentially — both fit comfortably in L2.
	required := COMP_TRANSFORM | COMP_MESH_REF
	for i in 0 ..< world.count {
		if world.generations[i] == 0 do continue           // dead slot
		if world.masks[i] & required != required do continue // missing a component

		meshRef := world.meshRefs[i]
		if meshRef.meshKey == 0 do continue // no mesh assigned

		batchIdx := meshRef.meshKey - 1 // convert to 0-based

		// Lazily initialise the batch the first time this mesh key appears.
		if world._batches[batchIdx].mesh == nil {
			world._batches[batchIdx] = RenderBatch{
				mesh         = world.meshRegistry[batchIdx],
				instanceData = make([dynamic]rend.InstanceData, 0, 1024),
			}
		}

		// Tint selected entity yellow, otherwise use the mesh's own colour.
		color  := meshRef.color
		if Selection_Contains_Index(selection, world, u32(i)) do color = SELECTION_TINT

		inst := rend.Instance_Data_From_Transform(world.transforms[i], color)
		append(&world._batches[batchIdx].instanceData, inst)
	}

	// --- Draw phase: one draw call per batch ---
	for i in 0 ..< MESH_REGISTRY_MAX {
		batch := &world._batches[i]
		if batch.mesh == nil || len(batch.instanceData) == 0 do continue
		rend.Renderer_Draw_Instanced(world.renderer, batch.mesh, batch.instanceData[:])
	}
}

// Moves every entity that has both a Transform and a Velocity component.
Physics_System_Velocity :: proc(world: ^World, dt: f32) {
	q := World_Query(world, COMP_TRANSFORM | COMP_VELOCITY)
	for idx in q.indices {
		world.transforms[idx].position += world.velocities[idx] * dt
	}
}
