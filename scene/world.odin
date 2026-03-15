package scene

import "core:fmt"
import eng "../engine"
import rend "../renderer"

// =============================================================================
// Constants
// =============================================================================

// Maximum number of entities the World can hold.
// Fixed-size parallel arrays are allocated up front — ~10 MB total.
// Allocate World on the heap (new(World)) to avoid stack overflow.
MAX_ENTITIES      :: 131_072 // 2^17, safely above 100k
MESH_REGISTRY_MAX :: 256

#assert(MAX_ENTITIES <= (1 << 20), "MAX_ENTITIES exceeds 20-bit index space in EntityID")

// =============================================================================
// EntityID
// Packs a 20-bit array index and a 12-bit generation counter into one u32.
// Generation 0 is always invalid — ENTITY_NULL is never a live entity.
// =============================================================================

EntityID :: distinct u32

ENTITY_NULL :: EntityID(0)

@(private = "file")
_INDEX_BITS :: 20
@(private = "file")
_INDEX_MASK :: u32((1 << _INDEX_BITS) - 1)

@(private = "file")
_entity_index :: #force_inline proc(id: EntityID) -> u32 {
	return u32(id) & _INDEX_MASK
}

@(private = "file")
_entity_gen :: #force_inline proc(id: EntityID) -> u32 {
	return u32(id) >> _INDEX_BITS
}

@(private = "file")
_entity_make :: #force_inline proc(idx, gen: u32) -> EntityID {
	return EntityID(idx | (gen << _INDEX_BITS))
}

// =============================================================================
// World
// Owns all entity state and component data.
// IMPORTANT: allocate on the heap — World is ~10 MB due to fixed arrays.
//   w := new(World)
//   World_Init(w, &renderer)
//   defer { World_Shutdown(w); free(w) }
// =============================================================================

World :: struct {
	// --- Entity slot management ---
	generations: [MAX_ENTITIES]u32,           // generation counter per slot
	masks:       [MAX_ENTITIES]ComponentMask, // active components per entity
	count:       int,                          // highest slot ever used + 1
	freeList:    [dynamic]u32,                 // recycled slot indices

	// --- Component arrays (parallel to entity slots) ---
	transforms: [MAX_ENTITIES]eng.Transform,
	meshRefs:   [MAX_ENTITIES]MeshRef,
	velocities: [MAX_ENTITIES]eng.Vec3,

	// --- Mesh registry ---
	// Register meshes with World_Register_Mesh; get back a meshKey for MeshRef.
	meshRegistry:      [MESH_REGISTRY_MAX]^rend.Mesh,
	meshRegistryCount: int,

	// --- Render batch cache (internal, rebuilt each frame) ---
	// Fixed array indexed by meshKey-1; avoids map hashing in the hot path.
	_batches: [MESH_REGISTRY_MAX]RenderBatch,

	// Borrowed pointer to the renderer (World does not own it).
	renderer: ^rend.Renderer,
}

// Initializes a world and binds it to the renderer used for scene draws.
World_Init :: proc(world: ^World, renderer: ^rend.Renderer) {
	world.renderer = renderer
	world.freeList = make([dynamic]u32)
}

// Releases dynamic world storage and clears all state.
World_Shutdown :: proc(world: ^World) {
	for i in 0 ..< MESH_REGISTRY_MAX {
		if world._batches[i].mesh != nil {
			delete(world._batches[i].instanceData)
		}
	}
	delete(world.freeList)
	world^ = {}
}

// Register a mesh for use with MeshRef components.
// Enables GPU instancing on the mesh.  Returns a meshKey (1-based) for use in MeshRef.
World_Register_Mesh :: proc(world: ^World, mesh: ^rend.Mesh) -> (key: u32, ok: bool) {
	if world.meshRegistryCount >= MESH_REGISTRY_MAX {
		fmt.eprintln("[Scene] Mesh registry full — increase MESH_REGISTRY_MAX.")
		return 0, false
	}
	if !rend.Mesh_Enable_Instancing(mesh, MAX_ENTITIES) {
		fmt.eprintln("[Scene] Failed to enable GPU instancing on mesh.")
		return 0, false
	}
	key = u32(world.meshRegistryCount + 1) // 1-based; 0 is reserved for "none"
	world.meshRegistry[world.meshRegistryCount] = mesh
	world.meshRegistryCount += 1
	return key, true
}

// Create a new entity and return its handle.  Reuses freed slots when available.
World_Entity_Create :: proc(world: ^World) -> EntityID {
	idx: u32
	if len(world.freeList) > 0 {
		idx = pop(&world.freeList)
	} else {
		assert(world.count < MAX_ENTITIES, "[Scene] Entity limit reached (MAX_ENTITIES).")
		idx = u32(world.count)
		world.count += 1
	}
	// Bump generation, skip 0 (0 is always the invalid sentinel).
	world.generations[idx] += 1
	if world.generations[idx] == 0 do world.generations[idx] = 1
	world.masks[idx] = {}
	return _entity_make(idx, world.generations[idx])
}

// Destroy an entity.  Invalidates the handle and recycles the slot.
World_Entity_Destroy :: proc(world: ^World, id: EntityID) {
	if !World_Entity_Valid(world, id) do return
	idx := _entity_index(id)
	world.masks[idx] = {}
	world.generations[idx] += 1 // invalidate any live copies of this handle
	append(&world.freeList, idx)
}

// Reconstructs the EntityID for a raw slot index using the current generation.
// Useful for systems that iterate slot indices and need a comparable EntityID.
World_Entity_ID :: proc(world: ^World, idx: u32) -> EntityID {
	return _entity_make(idx, world.generations[idx])
}

// Returns the raw slot index encoded inside an EntityID.
World_Entity_Index :: proc(id: EntityID) -> u32 {
	return _entity_index(id)
}

// Returns true if id refers to a currently live entity.
World_Entity_Valid :: proc(world: ^World, id: EntityID) -> bool {
	if id == ENTITY_NULL do return false
	idx := _entity_index(id)
	if int(idx) >= world.count do return false
	return world.generations[idx] == _entity_gen(id)
}

// Adds or replaces the Transform component for a live entity.
World_Add_Transform :: proc(world: ^World, id: EntityID, t: eng.Transform) -> bool {
	if !World_Entity_Valid(world, id) do return false
	idx := _entity_index(id)
	world.transforms[idx] = t
	world.masks[idx] |= COMP_TRANSFORM
	return true
}

// Returns a pointer to the entity's Transform component.
World_Get_Transform :: proc(world: ^World, id: EntityID) -> (t: ^eng.Transform, ok: bool) {
	if !World_Entity_Valid(world, id) do return nil, false
	idx := _entity_index(id)
	if world.masks[idx] & COMP_TRANSFORM == 0 do return nil, false
	return &world.transforms[idx], true
}

// Removes the Transform component from a live entity.
World_Remove_Transform :: proc(world: ^World, id: EntityID) {
	if !World_Entity_Valid(world, id) do return
	world.masks[_entity_index(id)] &~= COMP_TRANSFORM
}

// Adds or replaces the MeshRef component for a live entity.
World_Add_MeshRef :: proc(world: ^World, id: EntityID, ref: MeshRef) -> bool {
	if !World_Entity_Valid(world, id) do return false
	idx := _entity_index(id)
	world.meshRefs[idx] = ref
	world.masks[idx] |= COMP_MESH_REF
	return true
}

// Returns a pointer to the entity's MeshRef component.
World_Get_MeshRef :: proc(world: ^World, id: EntityID) -> (ref: ^MeshRef, ok: bool) {
	if !World_Entity_Valid(world, id) do return nil, false
	idx := _entity_index(id)
	if world.masks[idx] & COMP_MESH_REF == 0 do return nil, false
	return &world.meshRefs[idx], true
}

// Removes the MeshRef component from a live entity.
World_Remove_MeshRef :: proc(world: ^World, id: EntityID) {
	if !World_Entity_Valid(world, id) do return
	world.masks[_entity_index(id)] &~= COMP_MESH_REF
}

// Adds or replaces the Velocity component for a live entity.
World_Add_Velocity :: proc(world: ^World, id: EntityID, v: eng.Vec3) -> bool {
	if !World_Entity_Valid(world, id) do return false
	idx := _entity_index(id)
	world.velocities[idx] = v
	world.masks[idx] |= COMP_VELOCITY
	return true
}

// Returns a pointer to the entity's Velocity component.
World_Get_Velocity :: proc(world: ^World, id: EntityID) -> (v: ^eng.Vec3, ok: bool) {
	if !World_Entity_Valid(world, id) do return nil, false
	idx := _entity_index(id)
	if world.masks[idx] & COMP_VELOCITY == 0 do return nil, false
	return &world.velocities[idx], true
}

// Removes the Velocity component from a live entity.
World_Remove_Velocity :: proc(world: ^World, id: EntityID) {
	if !World_Entity_Valid(world, id) do return
	world.masks[_entity_index(id)] &~= COMP_VELOCITY
}
