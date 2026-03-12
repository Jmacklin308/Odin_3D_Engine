# 3D Engine — Documentation

> *Yes, it's another 3D engine. No, it's not done. Yes, it will be fun anyway.*

---

## Table of Contents

1. [Project Structure](#project-structure)
2. [Getting Started](#getting-started)
3. [The Game Loop](#the-game-loop)
4. [Math](#math)
5. [Window](#window)
6. [Input](#input)
7. [Camera](#camera)
8. [Mesh](#mesh)
9. [Shader](#shader)
10. [Renderer](#renderer)
11. [Large World Considerations](#large-world-considerations)
12. [Performance Notes](#performance-notes)
13. [What's Next](#whats-next)

---

## Project Structure

```
engine/
├── engine.odin    — Lifecycle, game loop management, global accessors
├── math.odin      — Vec2/3/4, Mat4, Quat, Transform, common operations
├── window.odin    — Window creation via GLFW, OpenGL context setup
├── input.odin     — Keyboard and mouse input (polling + edge detection)
├── camera.odin    — FPS-style camera with lazy matrix caching
├── mesh.odin      — GPU mesh upload, draw calls, built-in primitives
├── shader.odin    — GLSL shader compilation, uniform setters
└── renderer.odin  — Blinn-Phong renderer, draw calls, lighting
```

One package. Import it and go.

---

## Getting Started

### Prerequisites

- [Odin compiler](https://odin-lang.org/) — latest nightly recommended
- The Odin `vendor` libraries (bundled with the compiler): `glfw`, `OpenGL`
- A GPU that supports OpenGL 4.1+ (anything made after 2012, basically)

### Import the Package

In your project's main file:

```odin
import eng "path/to/engine"
```

The path is relative to your project root or absolute — same rules as any Odin import.

### Minimal Example

```odin
package main

import eng "path/to/engine"

main :: proc() {
    if !eng.Init() do return
    defer eng.Shutdown()

    // Create a camera 10 units back from the origin, with a 75° FOV
    cam := eng.Camera_Create({0, 5, 10}, 75)

    // Lock cursor for FPS-style mouse look
    eng.Input_Set_Cursor_Locked(eng.Get_Input(), eng.Get_Window(), true)

    // A cube to prove rendering works
    cube, _ := eng.Mesh_Create_Cube()
    defer eng.Mesh_Destroy(&cube)

    for eng.Running() {
        eng.Begin_Frame()
        dt := eng.Get_Delta_Time()

        // Update
        if eng.Input_Key_Pressed(eng.Get_Input(), eng.KEY_ESCAPE) {
            eng.Quit()
        }
        eng.Camera_FPS_Update(&cam, eng.Get_Input(), dt)

        // Render
        eng.Renderer_Begin(eng.Get_Renderer(), &cam, eng.Get_Window().aspect)
        eng.Renderer_Draw_Mesh(eng.Get_Renderer(), &cube, eng.MAT4_IDENTITY, {0.4, 0.7, 1.0})
        eng.Renderer_End(eng.Get_Renderer())

        eng.End_Frame()
    }
}
```

Build and run it. You should get a blue cube lit by a fake sun. If you get a black window, your drivers are having a moment — check stderr.

---

## The Game Loop

```
Init()
  └── Window_Create()    — GLFW + OpenGL context
  └── Renderer_Init()    — Compile default shader

for Running() {
    Begin_Frame()
      └── Poll events
      └── Update input state
      └── Compute delta time

    [your update code]
    [your render code — Renderer_Begin / Draw / Renderer_End]

    End_Frame()
      └── Swap buffers
}

Shutdown()
```

**`Get_Delta_Time()`** returns seconds since the last frame as `f32`. Multiply everything by it. If you don't, your game will run at wildly different speeds on different machines and you will deserve the bug reports.

Delta time is clamped at `1/15` seconds (~66ms). If your frame takes longer than that, physics and movement will just slow down rather than making objects teleport. You're welcome.

---

## Math

File: `engine/math.odin`

### Types

| Type        | Underlying type       | Description                |
|-------------|----------------------|----------------------------|
| `Vec2`      | `[2]f32`             | 2D vector                  |
| `Vec3`      | `[3]f32`             | 3D vector                  |
| `Vec4`      | `[4]f32`             | 4D vector / RGBA colour    |
| `Mat4`      | `matrix[4,4]f32`     | 4×4 matrix (column-major)  |
| `Quat`      | `quaternion128`      | Unit quaternion (rotation) |
| `Transform` | struct               | Position + rotation + scale |

Odin's built-in vector types support swizzling (`v.xy`, `v.rgb`, etc.) and arithmetic operators out of the box. The types here are just aliases — they're the same type, not wrappers.

### Key Procedures

```odin
// Vectors
Vec3_Normalize(v)         -> Vec3
Vec3_Cross(a, b)          -> Vec3
Vec3_Dot(a, b)            -> f32
Vec3_Length_Sq(v)         -> f32   // avoid sqrt when only comparing distances
Vec3_Lerp(a, b, t)        -> Vec3

// Matrices
Mat4_Perspective(fovY, aspect, near, far) -> Mat4  // fovY in radians
Mat4_Look_At(eye, target, up)             -> Mat4
Mat4_TRS(pos, rot, scale)                 -> Mat4  // build model matrix
Mat4_Normal(model)                        -> Mat4  // for transforming normals

// Quaternions
Quat_From_Euler(pitch, yaw, roll)   -> Quat  // radians, FPS order
Quat_Axis_Angle(axis, angle)        -> Quat
Quat_Nlerp(a, b, t)                 -> Quat

// Transform
Transform_Default()         -> Transform   // pos=0, rot=identity, scale=1
Transform_To_Mat4(t)        -> Mat4

// Utilities
To_Radians(degrees)   -> f32
To_Degrees(radians)   -> f32
Smooth_Step(e0, e1, x)-> f32
```

### Why Quaternions?

Because Euler angles have gimbal lock. You don't want your camera to suddenly decide it'd rather point sideways. Quaternions avoid that. Don't try to directly edit quaternion components unless you know what you're doing — use `Quat_From_Euler` or `Quat_Axis_Angle` to create them.

---

## Window

File: `engine/window.odin`

Usually you don't touch this directly — `Init()` handles it. But if you need custom config:

```odin
cfg := eng.WindowConfig{
    title    = "My Game",
    width    = 1920,
    height   = 1080,
    vsync    = true,
    msaa     = 4,       // 4x MSAA for smoother edges
    glMajor  = 4,
    glMinor  = 1,
    resizable = false,
}
ok := eng.Init(eng.EngineConfig{window = cfg})
```

**VSync** (`vsync = true`): Caps the frame rate to the monitor refresh rate. Prevents tearing. Turn it off if you're benchmarking, leave it on otherwise — your GPU fan will thank you.

**MSAA** (`msaa = 4`): 4× multisample anti-aliasing. Makes jagged edges less jagged. Set to 0 to disable.

---

## Input

File: `engine/input.odin`

### Keyboard

```odin
input := eng.Get_Input()

// Held down — fires every frame while the key is held
if eng.Input_Key_Down(input, eng.KEY_W) { ... }

// Pressed — fires exactly once when the key goes down
if eng.Input_Key_Pressed(input, eng.KEY_SPACE) { ... }

// Released — fires exactly once when the key comes back up
if eng.Input_Key_Released(input, eng.KEY_ESCAPE) { ... }
```

### Mouse

```odin
// Buttons (same three-state API as keys)
if eng.Input_Mouse_Down(input, eng.MOUSE_LEFT) { ... }
if eng.Input_Mouse_Pressed(input, eng.MOUSE_RIGHT) { ... }

// Cursor movement delta (pixels since last frame)
delta := eng.Input_Mouse_Delta(input)
// delta.x = horizontal, delta.y = vertical (screen-space, Y down)

// Scroll wheel
scroll := eng.Input_Scroll_Delta(input)
// scroll.y > 0 = scroll up/forward
```

### Cursor Lock

```odin
// Lock the cursor for FPS camera control (hidden + confined to window)
eng.Input_Set_Cursor_Locked(eng.Get_Input(), eng.Get_Window(), true)

// Unlock it (e.g., for a pause menu)
eng.Input_Set_Cursor_Locked(eng.Get_Input(), eng.Get_Window(), false)
```

When you lock the cursor, the first frame of mouse delta is swallowed. Otherwise you'd get a violent camera snap as the cursor teleports to the centre of the window. You're welcome, again.

### Key Constants

All GLFW key codes are re-exported with a cleaner prefix: `KEY_W`, `KEY_SPACE`, `KEY_LEFT_SHIFT`, `KEY_ESCAPE`, `KEY_F1`–`KEY_F12`, arrow keys, etc. For anything not listed, use `glfw.KEY_*` directly.

---

## Camera

File: `engine/camera.odin`

```odin
// Create a camera at position {0, 5, 10} with a 75° vertical FOV
cam := eng.Camera_Create({0, 5, 10}, 75)

// FPS update (WASD + mouse look) — call this every frame
eng.Camera_FPS_Update(&cam, eng.Get_Input(), dt)

// Custom parameters if defaults aren't exciting enough
params := eng.CameraFPSParams{
    moveSpeed        = 20,
    mouseSensitivity = 0.0015,
    sprintMult       = 4.0,    // Shift to sprint
}
eng.Camera_FPS_Update(&cam, eng.Get_Input(), dt, params)
```

**Movement keys (default):** `W/A/S/D` — forward/left/back/right, `E/Q` — up/down, `Left Shift` — sprint.

### Manual Control

```odin
// Move by an absolute world-space offset
eng.Camera_Move(&cam, {0, 0, -speed * dt})

// Move along local axes (forward/right/up scalars)
eng.Camera_Move_Local(&cam, fwd * speed * dt, 0, 0)

// Rotate by yaw and pitch deltas in radians
eng.Camera_Rotate(&cam, yawDelta, pitchDelta)

// Snap look direction to a point
eng.Camera_Look_At(&cam, target)
```

### Matrices

```odin
view       := eng.Camera_Get_View(&cam)
projection := eng.Camera_Get_Projection(&cam, aspect)
view, proj := eng.Camera_Get_VP(&cam, aspect)
```

The camera caches its view matrix and only rebuilds it when position or rotation changes. Calling `Camera_Get_View` 10 times in a frame costs 10 pointer dereferences, not 10 matrix rebuilds.

The **far plane** defaults to `3500` units — safely beyond the 3000-metre world boundary. Adjust it in `Camera_Create` if your world is larger.

---

## Mesh

File: `engine/mesh.odin`

### Vertex Layout

```
Vertex (32 bytes)
├── pos:    Vec3  — world/local position
├── normal: Vec3  — surface normal for lighting
└── uv:     Vec2  — texture coordinates [0..1]
```

### Creating Meshes

```odin
// From raw geometry data
mesh, ok := eng.Mesh_Create(vertices, indices)

// Built-in primitives
cube,  ok := eng.Mesh_Create_Cube()
plane, ok := eng.Mesh_Create_Plane(width=100, depth=100, subdivisionsX=10, subdivisionsZ=10)
quad,  ok := eng.Mesh_Create_Quad(width=1, height=1)

// Always destroy what you create
defer eng.Mesh_Destroy(&mesh)
```

CPU-side vertex data is **not retained** after upload. The GPU has a copy; you don't. If you need to modify geometry, keep your own `[]Vertex` slice.

### Drawing

```odin
// Usually called from within Renderer_Draw_Mesh, not directly
eng.Mesh_Draw(&mesh)
```

---

## Shader

File: `engine/shader.odin`

The renderer uses a built-in Blinn-Phong shader — you don't need to touch this for basic rendering. When you're ready to write your own:

```odin
// From source strings
shader, ok := eng.Shader_Create(vertSrc, fragSrc)

// From files on disk (hot-reloading friendly)
shader, ok := eng.Shader_Load_Files("assets/shaders/terrain.vert", "assets/shaders/terrain.frag")

defer eng.Shader_Destroy(&shader)

// Setting uniforms (shader must be bound first)
eng.Shader_Bind(&shader)
eng.Shader_Set_Float(&shader, "uTime",  time)
eng.Shader_Set_Vec3(&shader,  "uColor", color)
eng.Shader_Set_Mat4(&shader,  "uModel", &modelMat)
```

### Built-in Shader Uniforms

When using the default renderer shader (`Renderer_Draw_Mesh`), these uniforms are set automatically:

| Uniform         | Type   | Set by            |
|-----------------|--------|-------------------|
| `uModel`        | mat4   | per draw call     |
| `uNormalMatrix` | mat4   | per draw call     |
| `uView`         | mat4   | `Renderer_Begin`  |
| `uProjection`   | mat4   | `Renderer_Begin`  |
| `uViewPos`      | vec3   | `Renderer_Begin`  |
| `uLightDir`     | vec3   | `Renderer_Begin`  |
| `uLightColor`   | vec3   | `Renderer_Begin`  |
| `uAmbient`      | vec3   | `Renderer_Begin`  |
| `uColor`        | vec3   | per draw call     |

---

## Renderer

File: `engine/renderer.odin`

```odin
r := eng.Get_Renderer()

// Every frame:
eng.Renderer_Begin(r, &cam, eng.Get_Window().aspect)

    // Draw as many meshes as you want in here
    eng.Renderer_Draw_Mesh(r, &mesh, modelMatrix, color)
    eng.Renderer_Draw_Transform(r, &mesh, transform, color)

eng.Renderer_End(r)
```

### Lighting

The renderer has one directional light (a sun). Change it like this:

```odin
eng.Renderer_Set_Light(eng.Get_Renderer(), eng.DirLight{
    direction = {-1, -2, -1},      // pointing down-left-forward
    color     = {1.0, 0.9, 0.8},   // warm afternoon sun
    ambient   = {0.05, 0.05, 0.1}, // dim blue sky fill
})
```

### Custom Shaders

```odin
// Switch to your shader for some draw calls, then switch back
eng.Renderer_Use_Shader(r, &myShader)
// ... upload uniforms, draw things ...
eng.Renderer_Use_Default_Shader(r)
```

### Clear Colour

```odin
eng.Renderer_Set_Clear_Color(r, {0.53, 0.81, 0.98, 1.0}) // sky blue
```

---

## Large World Considerations

This engine is built for worlds up to ~3000 metres. Here's what that means in practice.

### Float Precision

`f32` has about 7 significant decimal digits. At 3000 metres from the origin, you have sub-millimetre precision — more than enough for an FPS game.

Beyond ~10 km you'd start seeing visible precision artifacts (jittery objects far from origin). The solution is **origin rebasing**: periodically shift everything in your world so the player is always near `{0, 0, 0}`. This engine doesn't implement that yet, but when you add it, you'd do it in your world update, not in the engine core.

### World Chunking (Future)

For streaming large worlds, divide the world into chunks (e.g., 100×100 metre tiles). Load/unload chunks based on player proximity. The `#soa` directive in Odin will make your per-chunk entity storage significantly cache-friendlier:

```odin
Entity :: struct { pos: Vec3, vel: Vec3, health: f32 }
chunkEntities: #soa [dynamic]Entity
// pos[], vel[], health[] are now stored as separate contiguous arrays.
// Iterating positions touches only position data. Your CPU prefetcher loves this.
```

### Camera Far Plane

`Camera_Create` defaults to a far plane of 3500 units — just past the world edge. Adjust it if your world is bigger. Making it unnecessarily large compresses depth buffer precision and causes Z-fighting on distant geometry.

---

## Performance Notes

### What's Already Done

- **Back-face culling** is enabled by default. Geometry facing away from the camera is not sent to the GPU.
- **Depth testing** is on. Only the closest fragment is shaded.
- **Camera matrix caching.** The view matrix is only rebuilt when the camera moves. `Camera_Get_View` is cheap to call repeatedly.
- **Delta time clamping.** Breakpoints and lag spikes won't send your entities into low orbit.
- **`Vec3_Length_Sq`** — use this instead of `Vec3_Length` when you only need to compare distances. It skips a `sqrt`.

### What You Should Do

- **Batch draw calls.** Every `Renderer_Draw_Mesh` call is a separate OpenGL draw call. For hundreds of identical objects (trees, rocks, enemies), look into instanced rendering.
- **Frustum culling.** Don't draw what the camera can't see. Implement a `Camera_Frustum` and test meshes against it before calling draw.
- **Sort by shader.** State changes (switching shaders) are expensive. Group draw calls by shader/material.
- **Use `#soa` for your entity arrays.** Iterating 1000 entities to update only their positions touches 32×1000 = 32KB of data without `#soa`. With `#soa`, you touch only 12×1000 = 12KB. Fits better in cache, runs faster.

### What You Definitely Shouldn't Do

- Call `gl.GetUniformLocation` every draw call for the same uniform. Cache the location.
- Allocate from the heap inside the game loop. Use arena allocators for per-frame temporary data.
- Set `nearPlane` to `0.001`. You'll destroy your depth buffer precision. Keep it at `0.1` or higher.

---

## What's Next

These features aren't in yet. They're not in the engine the same way your future regrets aren't in your calendar yet — inevitable, just not scheduled.

- [ ] **Texture loading** — upload images to the GPU, sample in shaders
- [ ] **Skybox** — cube-mapped sky
- [ ] **Terrain system** — heightmap-based terrain with LOD
- [ ] **World streaming / chunk management** — async load/unload for large worlds
- [ ] **Instanced rendering** — draw 10,000 trees without 10,000 draw calls
- [ ] **Frustum culling** — skip things you can't see
- [ ] **Shadow mapping** — basic directional shadow
- [ ] **Entity/Component system** — SOA-based, cache-friendly
- [ ] **Audio** — the thing people always add last and regret leaving for last
- [ ] **Networking** — client/server for multiplayer FPS (planned: client-server model)
- [ ] **Physics** — collision detection, rigid body integration

---

*Built in Odin. No garbage collector was harmed in the making of this engine.*
