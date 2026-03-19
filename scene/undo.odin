package scene

import eng "../engine"

UNDO_MAX :: 64

Undo_Op_Kind :: enum u8 { TRANSFORM, PASTE }

Undo_Transform_Entry :: struct {
	id:     EntityID,
	before: eng.Transform,
	after:  eng.Transform,
}

Undo_Command :: struct {
	kind: Undo_Op_Kind,

	// --- TRANSFORM ---
	entries: [dynamic]Undo_Transform_Entry,

	// --- PASTE ---
	// pastedIds is updated on each redo so undo always targets the live entities.
	pastedIds: [dynamic]EntityID,
	pasteSnap: [dynamic]Clipboard_Entry,
}

// Ring-buffer command history. Zero-value is valid — no explicit Init needed.
// Supports up to UNDO_MAX committed steps; oldest are evicted automatically.
Undo_History :: struct {
	ring:   [UNDO_MAX]Undo_Command,
	base:   int, // logical index of the oldest stored command
	cursor: int, // current position: cursor-1 is the next thing to undo
	top:    int, // one past newest committed command; (top - cursor) = redo depth
}

Undo_History_Init :: proc(h: ^Undo_History) {
	h^ = {}
}

Undo_History_Destroy :: proc(h: ^Undo_History) {
	for i := h.base; i < h.top; i += 1 {
		_undo_command_destroy(&h.ring[i % UNDO_MAX])
	}
	h^ = {}
}

// Call this on the frame a gizmo drag completes.
// Reads before-state from gizmo.dragEntries and after-state from the current world.
Undo_Gizmo_Commit :: proc(h: ^Undo_History, gizmo: ^Transform_Gizmo, world: ^World) {
	if len(gizmo.dragEntries) == 0 do return

	entries := make([dynamic]Undo_Transform_Entry, 0, len(gizmo.dragEntries))
	for drag in gizmo.dragEntries {
		t, ok := World_Get_Transform(world, drag.id)
		if !ok do continue
		before := eng.Transform{position = drag.startPos, rotation = drag.startRot, scale = drag.startScale}
		if before == t^ do continue // entity didn't actually move — skip
		append(&entries, Undo_Transform_Entry{
			id     = drag.id,
			before = before,
			after  = t^,
		})
	}

	if len(entries) == 0 {
		delete(entries)
		return
	}

	_undo_push(h, Undo_Command{kind = .TRANSFORM, entries = entries})
}

// Push a paste operation onto the undo stack.
// Takes ownership of ids and snap (the slices returned by Clipboard_Paste).
Undo_Paste_Commit :: proc(h: ^Undo_History, ids: [dynamic]EntityID, snap: [dynamic]Clipboard_Entry) {
	_undo_push(h, Undo_Command{kind = .PASTE, pastedIds = ids, pasteSnap = snap})
}

// Ctrl+Z — restores the before-state of the most recently committed command.
// Pass sel to have the selection updated when undoing a paste.
Undo_Apply :: proc(h: ^Undo_History, world: ^World, sel: ^Selection_Set = nil) -> bool {
	if h.cursor <= h.base do return false
	h.cursor -= 1
	cmd := &h.ring[h.cursor % UNDO_MAX]
	switch cmd.kind {
	case .TRANSFORM:
		for entry in cmd.entries {
			if t, ok := World_Get_Transform(world, entry.id); ok {
				t^ = entry.before
			}
		}
	case .PASTE:
		for id in cmd.pastedIds {
			World_Entity_Destroy(world, id)
		}
		if sel != nil do Selection_Clear(sel)
	}
	return true
}

// Ctrl+Y — re-applies the after-state of the next redoable command.
// Pass sel to have the selection updated when redoing a paste.
Undo_Redo :: proc(h: ^Undo_History, world: ^World, sel: ^Selection_Set = nil) -> bool {
	if h.cursor >= h.top do return false
	cmd := &h.ring[h.cursor % UNDO_MAX]
	switch cmd.kind {
	case .TRANSFORM:
		for entry in cmd.entries {
			if t, ok := World_Get_Transform(world, entry.id); ok {
				t^ = entry.after
			}
		}
	case .PASTE:
		// Re-create from snapshot and update pastedIds so future undos hit the right slots.
		clear(&cmd.pastedIds)
		if sel != nil do Selection_Clear(sel)
		for e in cmd.pasteSnap {
			id := World_Entity_Create(world)
			if e.mask & COMP_TRANSFORM != 0 do World_Add_Transform(world, id, e.transform)
			if e.mask & COMP_MESH_REF   != 0 do World_Add_MeshRef(world, id, e.meshRef)
			if e.mask & COMP_VELOCITY   != 0 do World_Add_Velocity(world, id, e.velocity)
			append(&cmd.pastedIds, id)
			if sel != nil do Selection_Add_ID(sel, world, id)
		}
	}
	h.cursor += 1
	return true
}

@(private)
_undo_command_destroy :: proc(cmd: ^Undo_Command) {
	delete(cmd.entries)
	delete(cmd.pastedIds)
	delete(cmd.pasteSnap)
	cmd^ = {}
}

@(private)
_undo_push :: proc(h: ^Undo_History, cmd: Undo_Command) {
	// Discard the redo stack above the cursor.
	for i := h.cursor; i < h.top; i += 1 {
		_undo_command_destroy(&h.ring[i % UNDO_MAX])
	}
	h.top = h.cursor

	// Evict the oldest entry if the ring is full.
	if h.cursor - h.base == UNDO_MAX {
		_undo_command_destroy(&h.ring[h.base % UNDO_MAX])
		h.base += 1
	}

	h.ring[h.cursor % UNDO_MAX] = cmd
	h.cursor += 1
	h.top = h.cursor
}
