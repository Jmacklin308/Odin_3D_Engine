package scene

// =============================================================================
// World Query
// Returns a slice of entity slot indices matching a ComponentMask.
// Uses the temp allocator by default — no manual free required when
// context.temp_allocator is reset at the end of each frame.
//
// Usage:
//   q := scene.World_Query(world, scene.COMP_TRANSFORM | scene.COMP_VELOCITY)
//   for idx in q.indices {
//       world.transforms[idx].position += world.velocities[idx] * dt
//   }
// =============================================================================

WorldQuery :: struct {
	indices: [dynamic]u32,
}

World_Query :: proc(
	world:     ^World,
	mask:      ComponentMask,
	allocator := context.temp_allocator,
) -> WorldQuery {
	q := WorldQuery{
		indices = make([dynamic]u32, 0, world.count, allocator),
	}
	for i in 0 ..< world.count {
		if world.generations[i] == 0 do continue // dead slot
		if world.masks[i] & mask == mask {
			append(&q.indices, u32(i))
		}
	}
	return q
}
