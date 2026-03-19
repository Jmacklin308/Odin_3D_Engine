package scene

import eng "../engine"

UNDO_MAX :: 64

Undo_Transform_Entry :: struct {
	id:     EntityID,
	before: eng.Transform,
	after:  eng.Transform,
}

Undo_Command :: struct {
	entries: [dynamic]Undo_Transform_Entry,
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
		delete(h.ring[i % UNDO_MAX].entries)
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

	_undo_push(h, Undo_Command{entries = entries})
}

// Ctrl+Z — restores the before-state of the most recently committed command.
Undo_Apply :: proc(h: ^Undo_History, world: ^World) -> bool {
	if h.cursor <= h.base do return false
	h.cursor -= 1
	cmd := &h.ring[h.cursor % UNDO_MAX]
	for entry in cmd.entries {
		if t, ok := World_Get_Transform(world, entry.id); ok {
			t^ = entry.before
		}
	}
	return true
}

// Ctrl+Y — re-applies the after-state of the next redoable command.
Undo_Redo :: proc(h: ^Undo_History, world: ^World) -> bool {
	if h.cursor >= h.top do return false
	cmd := &h.ring[h.cursor % UNDO_MAX]
	for entry in cmd.entries {
		if t, ok := World_Get_Transform(world, entry.id); ok {
			t^ = entry.after
		}
	}
	h.cursor += 1
	return true
}

@(private)
_undo_push :: proc(h: ^Undo_History, cmd: Undo_Command) {
	// Discard the redo stack above the cursor.
	for i := h.cursor; i < h.top; i += 1 {
		delete(h.ring[i % UNDO_MAX].entries)
		h.ring[i % UNDO_MAX] = {}
	}
	h.top = h.cursor

	// Evict the oldest entry if the ring is full.
	if h.cursor - h.base == UNDO_MAX {
		delete(h.ring[h.base % UNDO_MAX].entries)
		h.ring[h.base % UNDO_MAX] = {}
		h.base += 1
	}

	h.ring[h.cursor % UNDO_MAX] = cmd
	h.cursor += 1
	h.top = h.cursor
}
