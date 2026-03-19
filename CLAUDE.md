# Odin 3D Engine — Claude Instructions

## Build & Run
```bash
odin run . -file           # run main.odin directly
odin build . -out:engine   # build executable
odin build . -out:engine -debug  # build executable -debug
```
No build system — just `odin run .` from the project root.

## Language & Renderer
- **Language:** Odin
- **Renderer:** OpenGL 4.1 via `vendor:OpenGL`
- **Windowing/Input:** GLFW via `vendor:glfw`

## Package Structure
```
engine/     → package engine    (import as: import eng "engine")
renderer/   → package renderer  (import as: import rend "renderer")
```
- `engine` is a global singleton (`_eng`) — never instantiate it directly
- `renderer` is user-owned: `r: rend.Renderer`, `rend.Renderer_Init(&r)`
- Both packages may import each other — renderer imports engine for math/camera types; engine may import renderer for debug drawing (grid, etc.)
- `renderer` is designed to be modular: it can be used standalone without the engine singleton if needed

## Naming Conventions
- Variables: `camelCase`
- Procedures: `Package_Verb_Noun` — e.g., `Camera_Get_View`, `Mesh_Create_Cube`
- Private symbols: `@(private)` attribute or underscore prefix (e.g., `_eng`, `_compile_stage`)
- Constants: `ALL_CAPS` or `SCREAMING_SNAKE`

## Key Design Rules
- Camera matrices are **lazily cached** — set `dirty = true` when any camera field changes
- Delta time is **clamped to 1/15s** — do not remove this clamp
- `Vertex` struct is `#packed` at exactly 32 bytes — `#assert(size_of(Vertex) == 32)` must pass
- First mouse frame after cursor lock is **swallowed** — do not remove this guard
- Far plane defaults to **3500 units** — keep this unless explicitly changed

## Style Rules
- Prefer `when` and `#assert` for compile-time checks over runtime panics
- Use `defer` for cleanup — always paired at the allocation site
- Return `(value, bool)` tuples for fallible operations — no exceptions, no nullable pointers
- No global mutable state outside `engine/engine.odin`
- Keep `main.odin` thin — it is a wiring file, not a logic file

## Units
- **1 engine unit = 1 meter** (convention only — nothing enforces this)
- No physics, audio, or networking currently depend on this scale
- If a physics library is added later (e.g. Jolt), it will expect SI units — this convention means no scale conversion will be needed
- Do not add a `METERS_PER_UNIT` constant unless something actually uses it

## What NOT to Do
- Do not add external dependencies beyond `vendor:` packages already in use
- Do not add a build system (Makefile, etc.) unless asked
- Do not split `engine` or `renderer` into sub-packages unless asked
- Do not change the `Vertex` layout or size without updating the `#assert`
