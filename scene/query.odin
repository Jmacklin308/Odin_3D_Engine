package scene

// =============================================================================
// World Query
// Returns a slice of entity slot indices matching a ComponentMask.
// Uses the temp allocator by default — no manual free required when
// context.temp_allocator is reset at the end of each frame.
// =============================================================================

WorldQuery :: struct {
	indices: [dynamic]u32,
}

// Returns the live entity slots whose component mask contains all requested bits.
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
