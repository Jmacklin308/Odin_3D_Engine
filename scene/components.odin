package scene

import eng "../engine"
import rend "../renderer"

// =============================================================================
// Component Mask
// Each bit represents the presence of one component type on an entity.
// =============================================================================

ComponentMask :: distinct u32

COMP_TRANSFORM :: ComponentMask(1 << 0)
COMP_MESH_REF  :: ComponentMask(1 << 1)
COMP_VELOCITY  :: ComponentMask(1 << 2)
// Bits 3-31 reserved for user expansion.

// =============================================================================
// Component Types
// =============================================================================

// Reference to a registered mesh plus a solid colour.
MeshRef :: struct {
	meshKey: u32,      // 1-based index into World.meshRegistry; 0 = none
	color:   eng.Vec3,
}

// =============================================================================
// Render Batch (internal — used by Scene_Render_System)
// =============================================================================

// One batch per unique mesh type.  Rebuilt every frame by Scene_Render_System.
RenderBatch :: struct {
	mesh:         ^rend.Mesh,
	instanceData: [dynamic]rend.InstanceData,
}
