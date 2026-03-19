package scene

import "core:fmt"
import "core:mem"
import "core:os"
import eng "../engine"
import rend "../renderer"

// =============================================================================
// Scene Serialization — binary .o3ds format
//
// File layout:
//   [64 bytes]  _SceneHeader
//   [N × 64]    _MeshNameEntry  (one per registered mesh)
//   [M × 80]    _EntityRecord   (one per live entity, dead slots skipped)
// =============================================================================

@(private = "file")
SCENE_MAGIC :: [4]u8{'O', '3', 'D', 'S'}

@(private = "file")
SCENE_VERSION :: u32(1)

@(private = "file")
_SceneHeader :: struct #packed {
	magic:            [4]u8, // 'O','3','D','S'
	version:          u32,
	entityCount:      u32,   // number of _EntityRecord entries
	meshCount:        u32,   // number of _MeshNameEntry entries
	meshTableOffset:  u32,   // byte offset to mesh table from file start
	entityDataOffset: u32,   // byte offset to entity records from file start
	_reserved:        [40]u8,
}

#assert(size_of(_SceneHeader) == 64)

@(private = "file")
_MeshNameEntry :: struct #packed {
	key:     u32,    // 1-based meshKey as registered at save time
	nameLen: u32,    // byte length of name (not including null terminator)
	name:    [56]u8, // null-terminated UTF-8, max 55 usable chars
}

#assert(size_of(_MeshNameEntry) == 64)

@(private = "file")
_EntityRecord :: struct #packed {
	slotIndex:  u32,    // raw slot index in the World arrays
	generation: u32,    // generation counter for handle validation
	mask:       u32,    // ComponentMask bitfield
	// Transform — zeroed when COMP_TRANSFORM absent
	pos:        [3]f32, // position (Vec3)
	rot:        [4]f32, // rotation as [w, x, y, z] (quaternion128)
	scale:      [3]f32, // scale (Vec3)
	// MeshRef — zeroed when COMP_MESH_REF absent
	meshKey:    u32,
	color:      [3]f32,
	// Velocity — zeroed when COMP_VELOCITY absent
	vel:        [3]f32,
}

#assert(size_of(_EntityRecord) == 80)

// Callback type supplied by the caller to resolve mesh names back to GPU pointers.
Scene_Mesh_Resolver :: #type proc(name: string) -> (mesh: ^rend.Mesh, ok: bool)

// Save the current world state to a binary .o3ds file.
// Returns false on I/O error.
Scene_Save :: proc(world: ^World, path: string) -> bool {
	meshCount    := u32(world.meshRegistryCount)
	meshTableOff  := u32(size_of(_SceneHeader))
	entityDataOff := meshTableOff + meshCount * u32(size_of(_MeshNameEntry))

	// Build the file in memory, then write atomically.
	buf := make([dynamic]u8, 0, 1024 * 1024)
	defer delete(buf)

	// Reserve space for the header — filled at the end once entityCount is known.
	resize(&buf, size_of(_SceneHeader))

	// Mesh name table
	for i in 0 ..< int(meshCount) {
		entry := _MeshNameEntry{
			key     = u32(i + 1),
			nameLen = u32(world.meshNameLens[i]),
		}
		copyLen := min(world.meshNameLens[i], 55)
		mem.copy(&entry.name[0], &world.meshNames[i][0], copyLen)
		oldLen := len(buf)
		resize(&buf, oldLen + size_of(_MeshNameEntry))
		mem.copy(&buf[oldLen], &entry, size_of(_MeshNameEntry))
	}

	// Entity records (live slots only)
	entityCount: u32 = 0
	for i in 0 ..< world.count {
		if world.masks[i] == 0 do continue

		t := world.transforms[i]
		rec := _EntityRecord{
			slotIndex  = u32(i),
			generation = world.generations[i],
			mask       = u32(world.masks[i]),
			pos        = t.position,
			rot        = transmute([4]f32)t.rotation,
			scale      = t.scale,
			meshKey    = world.meshRefs[i].meshKey,
			color      = world.meshRefs[i].color,
			vel        = world.velocities[i],
		}
		oldLen := len(buf)
		resize(&buf, oldLen + size_of(_EntityRecord))
		mem.copy(&buf[oldLen], &rec, size_of(_EntityRecord))
		entityCount += 1
	}

	// Fill header now that entityCount is known
	hdr := _SceneHeader{
		magic            = SCENE_MAGIC,
		version          = SCENE_VERSION,
		entityCount      = entityCount,
		meshCount        = meshCount,
		meshTableOffset  = meshTableOff,
		entityDataOffset = entityDataOff,
	}
	mem.copy(&buf[0], &hdr, size_of(_SceneHeader))

	if !os.write_entire_file(path, buf[:]) {
		fmt.eprintf("[Scene] Failed to write scene to '%s'\n", path)
		return false
	}

	fmt.printf("[Scene] Saved %d entities, %d mesh(es) → '%s'\n", entityCount, meshCount, path)
	return true
}

// Load a scene file, clearing the world and rebuilding entity state.
// resolver is called once per mesh name found in the file to obtain the GPU mesh pointer.
// Returns false on I/O or format error.
Scene_Load :: proc(world: ^World, path: string, resolver: Scene_Mesh_Resolver) -> bool {
	data, ok := os.read_entire_file(path)
	if !ok {
		fmt.eprintf("[Scene] Could not read '%s'\n", path)
		return false
	}
	defer delete(data)

	if len(data) < size_of(_SceneHeader) {
		fmt.eprintf("[Scene] '%s' is too small to be a valid scene file.\n", path)
		return false
	}

	hdr := (^_SceneHeader)(&data[0])^
	if hdr.magic != SCENE_MAGIC {
		fmt.eprintf("[Scene] '%s' has invalid magic bytes — not a .o3ds file.\n", path)
		return false
	}
	if hdr.version != SCENE_VERSION {
		fmt.eprintf("[Scene] '%s' has unsupported version %d (expected %d).\n", path, hdr.version, SCENE_VERSION)
		return false
	}

	// Clear the world and reinitialise (preserve renderer pointer).
	savedRenderer := world.renderer
	World_Shutdown(world)
	World_Init(world, savedRenderer)

	// Resolve meshes and build a fileKey → liveKey remap table.
	fileKeyToLive: [MESH_REGISTRY_MAX + 1]u32 // index by 1-based fileKey
	meshOff := int(hdr.meshTableOffset)
	for i in 0 ..< int(hdr.meshCount) {
		off := meshOff + i * size_of(_MeshNameEntry)
		if off + size_of(_MeshNameEntry) > len(data) {
			fmt.eprintf("[Scene] Mesh table out of bounds at entry %d.\n", i)
			return false
		}
		entry   := (^_MeshNameEntry)(&data[off])^
		nameLen := min(int(entry.nameLen), 55)
		name    := string(entry.name[:nameLen])

		mesh, resolved := resolver(name)
		if !resolved {
			fmt.eprintf("[Scene] Warning: mesh '%s' could not be resolved — entities using it will have meshKey 0.\n", name)
			continue
		}
		liveKey, regOk := World_Register_Mesh(world, mesh, name)
		if !regOk {
			fmt.eprintf("[Scene] Failed to re-register mesh '%s'.\n", name)
			continue
		}
		if int(entry.key) <= MESH_REGISTRY_MAX {
			fileKeyToLive[entry.key] = liveKey
		}
	}

	// Read entity records and reconstruct component arrays.
	entityOff := int(hdr.entityDataOffset)
	maxSlot: u32 = 0
	for i in 0 ..< int(hdr.entityCount) {
		off := entityOff + i * size_of(_EntityRecord)
		if off + size_of(_EntityRecord) > len(data) {
			fmt.eprintf("[Scene] Entity data out of bounds at record %d.\n", i)
			return false
		}
		rec  := (^_EntityRecord)(&data[off])^
		slot := rec.slotIndex
		if int(slot) >= MAX_ENTITIES {
			fmt.eprintf("[Scene] Record %d has invalid slot index %d — skipped.\n", i, slot)
			continue
		}

		world.generations[slot] = rec.generation
		world.masks[slot]       = ComponentMask(rec.mask)
		mask := ComponentMask(rec.mask)

		if mask & COMP_TRANSFORM != 0 {
			world.transforms[slot] = eng.Transform{
				position = rec.pos,
				rotation = transmute(eng.Quat)rec.rot,
				scale    = rec.scale,
			}
		}
		if mask & COMP_MESH_REF != 0 {
			liveKey := u32(0)
			if int(rec.meshKey) <= MESH_REGISTRY_MAX {
				liveKey = fileKeyToLive[rec.meshKey]
			}
			world.meshRefs[slot] = MeshRef{
				meshKey = liveKey,
				color   = rec.color,
			}
		}
		if mask & COMP_VELOCITY != 0 {
			world.velocities[slot] = rec.vel
		}

		if slot > maxSlot do maxSlot = slot
	}

	// Reconstruct world.count and freeList from slot data.
	if hdr.entityCount > 0 {
		world.count = int(maxSlot) + 1
	}
	for i in 0 ..< world.count {
		if world.generations[i] == 0 {
			append(&world.freeList, u32(i))
		}
	}

	fmt.printf("[Scene] Loaded %d entities from '%s'\n", hdr.entityCount, path)
	return true
}
