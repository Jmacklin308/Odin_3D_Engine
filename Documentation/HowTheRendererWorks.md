# Renderer System (Simple, Feynman-Style)

Think of each frame like running a restaurant kitchen:

- The **World** is the order board (all entities + components).
- A **Transform** says where an item is in 3D space.
- A **MeshRef** says which mesh to use and what color it should be.
- The **Renderer** is the kitchen that actually cooks (GPU draw calls).

## 1) Setup (one-time)

1. `Renderer_Init` builds shaders and a per-frame uniform buffer (camera + light data).
2. `World_Register_Mesh` stores each mesh in a registry and enables GPU instancing for it.
3. Entities get:
   - `Transform` (position/rotation/scale)
   - `MeshRef` (`meshKey` + color)

## 2) What happens every frame

1. `Renderer_Begin`:
   - Computes camera view/projection.
   - Clears color + depth buffers.
   - Uploads shared frame data (camera position, light direction/color, ambient) once.

2. `Scene_Render_System`:
   - Scans entities that have both `Transform` and `MeshRef`.
   - Groups them by `meshKey` into render batches.
   - Converts each entity transform + color into `InstanceData`.
   - Tints selected entities yellow.
   - Calls `Renderer_Draw_Instanced` once per mesh batch.

3. `Renderer_Draw_Instanced`:
   - Binds instancing shader.
   - Uploads all instance transforms/colors for that mesh.
   - Issues **one instanced draw call** for many objects.

4. Optional overlay/editor draws:
   - Gizmo, grid, marquee rectangle, UI panels, debug text.
   - UI model previews render real meshes into tiny viewport/scissor rectangles.

5. `Renderer_End` unbinds shader and the frame is presented.

## Why this is fast

- Without batching: 10,000 cubes = ~10,000 draw calls.
- With this system: 10,000 cubes of same mesh = **1 draw call** (+ upload instance data).
- The ECS arrays are scanned sequentially, which is cache-friendly.

## Mental model

- **CPU side**: “Who exists? Where are they? Which mesh/color?”
- **Batch step**: “Put same-mesh objects in the same bucket.”
- **GPU side**: “Draw this one mesh N times using per-instance transforms/colors.”

## UI model previews

The placement drawer can show the actual 3D mesh for an item instead of a flat icon. `UI_Model_Preview` queues a mesh preview command. During `UI_Render`, the renderer:

1. Draws queued UI rectangles.
2. Temporarily changes the viewport/scissor to the preview card.
3. Uploads a small preview camera into the shared frame UBO.
4. Draws the mesh with the normal renderer shader.
5. Restores the scene frame UBO and full-window viewport.
6. Draws queued UI text on top.

This keeps OpenGL state changes inside the renderer, so editor code only asks for “show this mesh in this rectangle.”

That is the core renderer system in your project.
